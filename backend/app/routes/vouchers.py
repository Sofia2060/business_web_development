"""Check a voucher code against the customer's cart (or a guest's browser cart), before placing the order."""
from flask import Blueprint, jsonify

from ..auth import current_user
from ..db import query
from ..validation import body, text
from .cart import cart_subtotal, read_line
from .orders import MAX_GUEST_LINES

bp = Blueprint("vouchers", __name__, url_prefix="/api/vouchers")

MAX_CODE = 30  # size of Vouchers.VoucherCode

REASONS = {
    "not_found": "Voucher not found",
    "expired": "Voucher has expired",
    "used_up": "Voucher has been fully used",
    "min_order": "The cart total is below the minimum order value of this voucher",
}


def _problem(row: dict | None, subtotal: int) -> str | None:
    """Why the voucher cannot be used now, or None. The conditions are the same as in dbo.sp_PlaceOrder."""
    # A switched-off or not yet started voucher looks like an unknown code, so unreleased campaign codes stay hidden.
    if row is None or not row["IsActive"] or row["NotStarted"]:
        return "not_found"
    if row["Ended"]:
        return "expired"
    if row["UsageLimit"] is not None and row["UsedCount"] >= row["UsageLimit"]:
        return "used_up"
    if subtotal < row["MinOrderValue"]:
        return "min_order"
    return None


def _guest_subtotal(items) -> tuple[int | None, tuple[dict, int] | None]:
    """Price of the lines a guest sends in place of a cart. Returns (subtotal, None) or (None, (error body, status))."""
    if not isinstance(items, list) or not 1 <= len(items) <= MAX_GUEST_LINES or not all(isinstance(i, dict) for i in items):
        return None, ({"error": f"items must be a list of 1 to {MAX_GUEST_LINES} lines"}, 400)
    lines = []
    for number, item in enumerate(items, start=1):
        line, error = read_line(item)
        if error:
            return None, ({"error": f"Item {number}: {error}"}, 400)
        lines.append(line)
    skus = sorted({line[0] for line in lines})
    prices = {row["VariantSKU"]: row["Price"] for row in query(
        f"SELECT v.VariantSKU, dbo.fn_GetCurrentPrice(v.ProductID) AS Price FROM dbo.ProductVariants v "
        f"JOIN dbo.Products p ON p.ProductID = v.ProductID WHERE v.IsActive = 1 AND p.Status = 'Active' "
        f"AND v.VariantSKU IN ({','.join('?' * len(skus))})", tuple(skus))}
    for number, line in enumerate(lines, start=1):
        if line[0] not in prices:
            return None, ({"error": f"Item {number}: Variant not found"}, 404)
        if prices[line[0]] is None:
            return None, ({"error": f"Item {number}: This product is sold by quote only. Please contact the shop.",
                           "reason": "quote_only"}, 409)
    return sum(prices[sku] * quantity for sku, quantity, _, _ in lines), None


@bp.post("/check")
def check_voucher():
    """Body: {"code": "WELCOME5"}. Answers with the discount this voucher would give on the current cart.
    A logged-in customer is checked against the cart in the database. A visitor without an account sends the cart of
    the browser as "items" (the same lines as in a guest order). The real discount is fixed again by sp_PlaceOrder
    when the order is placed."""
    data = body()
    code = (text(data, "code") or "").strip()
    if not code or len(code) > MAX_CODE:
        return jsonify(error="code is required"), 400
    user = current_user()
    customer = query("SELECT CustomerID FROM dbo.Customers WHERE UserID = ?", (user["UserID"],)) if user is not None else []
    if customer:
        subtotal = cart_subtotal(customer[0]["CustomerID"])
        if not subtotal:
            return jsonify(error="The cart is empty"), 400
    elif "items" not in data:
        # a logged-in user without a customer account (the admin) has no cart: 403; a visitor is asked to log in or send items
        if user is not None:
            return jsonify(error="Customer account required"), 403
        return jsonify(error="Login required, or send the cart lines as items"), 401
    else:      # a visitor, or an admin whose browser shows the shop as a visitor
        subtotal, failure = _guest_subtotal(data["items"])
        if failure:
            return jsonify(failure[0]), failure[1]

    # The percent discount is worked out in SQL with the same rounding as sp_PlaceOrder (to the nearest 1,000).
    rows = query(
        "SELECT VoucherCode, VoucherName, MaxDiscountAmount, MinOrderValue, IsActive, UsageLimit, UsedCount, "
        "CAST(CASE WHEN SYSDATETIME() < StartAt THEN 1 ELSE 0 END AS BIT) AS NotStarted, "
        "CAST(CASE WHEN SYSDATETIME() > EndAt THEN 1 ELSE 0 END AS BIT) AS Ended, "
        "CASE WHEN DiscountType = 'Percent' THEN ROUND(CAST(? AS DECIMAL(15,0)) * DiscountValue / 100, -3) "
        "     ELSE DiscountValue END AS Discount "
        "FROM dbo.Vouchers WHERE VoucherCode = ?", (subtotal, code))
    row = rows[0] if rows else None
    problem = _problem(row, subtotal)
    if problem:
        extra = {"minOrderValue": row["MinOrderValue"]} if problem == "min_order" else {}
        return jsonify(error=REASONS[problem], reason=problem, **extra), (404 if problem == "not_found" else 409)

    discount = row["Discount"]
    if row["MaxDiscountAmount"] is not None:
        discount = min(discount, row["MaxDiscountAmount"])
    discount = min(discount, subtotal)
    return jsonify(code=row["VoucherCode"], name=row["VoucherName"], discount=discount, subtotal=subtotal)
