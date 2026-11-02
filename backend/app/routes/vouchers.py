"""Check a voucher code against the logged-in customer's cart, before placing the order."""
from flask import Blueprint, g, jsonify

from ..auth import customer_required
from ..db import query
from ..validation import body, text
from .cart import cart_subtotal

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


@bp.post("/check")
@customer_required
def check_voucher():
    """Body: {"code": "WELCOME5"}. Answers with the discount this voucher would give on the current cart.
    The real discount is fixed again by sp_PlaceOrder when the order is placed."""
    code = (text(body(), "code") or "").strip()
    if not code or len(code) > MAX_CODE:
        return jsonify(error="code is required"), 400
    subtotal = cart_subtotal(g.customer_id)
    if not subtotal:
        return jsonify(error="The cart is empty"), 400

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
