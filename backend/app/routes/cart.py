"""Shopping cart of the logged-in customer. One row per variant and engraving text."""
from flask import Blueprint, g, jsonify

from ..auth import customer_required
from ..config import FREE_SHIPPING_FROM, STANDARD_SHIPPING_FEE
from ..db import query, transaction
from ..validation import INT_MAX, body, is_int, text, utf16_len

bp = Blueprint("cart", __name__, url_prefix="/api/cart")

MAX_QTY = 10  # same as the CK_CartItems_Qty constraint
MAX_ENGRAVING = 15  # same as the EngravingText columns and the engraving limit in the shop pages
# Engraving styles stored in the database (the pages call them co-dien, hien-dai and viet-tay).
ENGRAVING_STYLES = ("Classic", "Modern", "Handwritten")


def shipping_fee(subtotal: int) -> int:
    return 0 if subtotal >= FREE_SHIPPING_FROM else STANDARD_SHIPPING_FEE


MAX_SELECTED_LINES = 100   # keeps the id list sent to sp_PlaceOrder (VARCHAR(2000)) short enough


def read_item_ids(data: dict) -> tuple[list[int] | None, str | None]:
    """The cart lines the customer ticked: "cartItemIds" in the request. Returns (ids, error message).
    ids is None when the field is missing (the whole cart is meant)."""
    ids = data.get("cartItemIds")
    if ids is None:
        return None, None
    if not isinstance(ids, list) or not 1 <= len(ids) <= MAX_SELECTED_LINES or not all(is_int(i, 1, INT_MAX) for i in ids):
        return None, f"cartItemIds must be a list of 1 to {MAX_SELECTED_LINES} cart line ids"
    return sorted(set(ids)), None


def cart_subtotal(customer_id: int, item_ids: list[int] | None = None) -> int:
    """Price of the cart of a customer. With item_ids, only those lines count (the lines ticked for checkout)."""
    sql = ("SELECT ISNULL(SUM(ci.Quantity * dbo.fn_GetCurrentPrice(v.ProductID)), 0) AS s FROM dbo.CartItems ci "
           "JOIN dbo.ProductVariants v ON v.VariantID = ci.VariantID WHERE ci.CustomerID = ?")
    params: tuple = (customer_id,)
    if item_ids is not None:
        sql += f" AND ci.CartItemID IN ({','.join('?' * len(item_ids))})"
        params += tuple(item_ids)
    return query(sql, params)[0]["s"]


@bp.get("")
@customer_required
def get_cart():
    items = query(
        "SELECT ci.CartItemID, v.VariantSKU, p.SKU, p.ProductName, v.GoldColor, v.RingSize, ci.Quantity, "
        "ci.EngravingText, ci.EngravingStyle, dbo.fn_GetCurrentPrice(p.ProductID) AS UnitPrice, v.StockQuantity "
        "FROM dbo.CartItems ci JOIN dbo.ProductVariants v ON v.VariantID = ci.VariantID "
        "JOIN dbo.Products p ON p.ProductID = v.ProductID WHERE ci.CustomerID = ? ORDER BY ci.CartItemID",
        (g.customer_id,))
    subtotal = sum((i["UnitPrice"] or 0) * i["Quantity"] for i in items)
    fee = shipping_fee(subtotal) if items else 0
    return jsonify(items=items, subtotal=subtotal, shippingFee=fee, total=subtotal + fee)


def add_line(customer_id: int, sku: str, quantity: int, engraving: str | None,
             style: str | None = None) -> tuple[dict, int]:
    """Put one variant into a customer's cart (a guest's temporary cart works the same way).
    Returns (JSON body, HTTP status). Adding the same variant with the same engraving text and style raises its
    quantity; the same text in another style is a separate line (it is made differently)."""
    variants = query(
        "SELECT v.VariantID, v.StockQuantity, p.IsEngravable, p.IsQuoteOnly FROM dbo.ProductVariants v "
        "JOIN dbo.Products p ON p.ProductID = v.ProductID "
        "WHERE v.VariantSKU = ? AND v.IsActive = 1 AND p.Status = 'Active'", (sku,))
    if not variants:
        return {"error": "Variant not found"}, 404
    variant = variants[0]
    if variant["IsQuoteOnly"]:    # priced by the gold price of the day: the shop gives a quote, nothing is sold online
        return {"error": "This product is sold by quote only. Please contact the shop.", "reason": "quote_only"}, 409
    if engraving and not variant["IsEngravable"]:
        return {"error": "This product cannot be engraved"}, 400

    with transaction() as cur:
        if engraving:
            cur.execute("SELECT CartItemID, Quantity, EngravingText FROM dbo.CartItems WHERE CustomerID = ? "
                        "AND VariantID = ? AND EngravingText = ? AND EngravingStyle = ?",
                        (customer_id, variant["VariantID"], engraving, style))
        else:
            cur.execute("SELECT CartItemID, Quantity, EngravingText FROM dbo.CartItems WHERE CustomerID = ? "
                        "AND VariantID = ? AND EngravingText IS NULL", (customer_id, variant["VariantID"]))
        existing = cur.fetchone()
        # The database compares text without case or accents ("Năm" equals "Nam"). Do not silently merge those.
        if existing and existing.EngravingText != engraving:
            return {"error": "The cart has this item with a very similar engraving text. Change that line instead."}, 409
        new_qty = quantity + (existing.Quantity if existing else 0)
        if new_qty > MAX_QTY:
            return {"error": f"At most {MAX_QTY} of one item per order"}, 400
        if new_qty > variant["StockQuantity"]:
            return {"error": "Not enough stock"}, 409
        if existing:
            cur.execute("UPDATE dbo.CartItems SET Quantity = ?, UpdatedAt = SYSDATETIME() WHERE CartItemID = ?",
                        (new_qty, existing.CartItemID))
            item_id = existing.CartItemID
        else:
            cur.execute("INSERT INTO dbo.CartItems (CustomerID, VariantID, Quantity, EngravingText, EngravingStyle) "
                        "OUTPUT INSERTED.CartItemID VALUES (?, ?, ?, ?, ?)",
                        (customer_id, variant["VariantID"], quantity, engraving, style))
            item_id = cur.fetchval()
    return {"id": item_id, "quantity": new_qty}, (200 if existing else 201)


def read_line(data: dict) -> tuple[tuple | None, str | None]:
    """Check one cart line from a request body: {"variantSku", "quantity", "engravingText", "engravingStyle"}.
    The style is one of Classic, Modern, Handwritten; it defaults to Classic and is ignored without engraving text.
    Returns ((sku, quantity, engraving, style), None) or (None, error message)."""
    sku = text(data, "variantSku")
    engraving = text(data, "engravingText")
    style = text(data, "engravingStyle")
    quantity = data.get("quantity", 1)
    if not sku or engraving is None or style is None or not is_int(quantity, 1, MAX_QTY):
        return None, f"variantSku and a quantity from 1 to {MAX_QTY} are required"
    engraving = engraving.strip() or None
    if engraving and utf16_len(engraving) > MAX_ENGRAVING:
        return None, f"Engraving text is limited to {MAX_ENGRAVING} characters"
    if not engraving:
        return (sku, quantity, None, None), None
    style = style.strip() or "Classic"
    if style not in ENGRAVING_STYLES:
        return None, f"engravingStyle must be one of {', '.join(ENGRAVING_STYLES)}"
    return (sku, quantity, engraving, style), None


@bp.post("")
@customer_required
def add_item():
    """Add a variant. Adding the same variant with the same engraving raises its quantity."""
    line, error = read_line(body())
    if error:
        return jsonify(error=error), 400
    payload, status = add_line(g.customer_id, *line)
    return jsonify(payload), status


@bp.patch("/<int:item_id>")
@customer_required
def set_quantity(item_id: int):
    quantity = body().get("quantity")
    if item_id > INT_MAX:    # too big for the database driver, so no such item
        return jsonify(error="Cart item not found"), 404
    if not is_int(quantity, 1, MAX_QTY):
        return jsonify(error=f"quantity must be a whole number from 1 to {MAX_QTY}"), 400
    rows = query("SELECT v.StockQuantity FROM dbo.CartItems ci JOIN dbo.ProductVariants v ON v.VariantID = ci.VariantID "
                 "WHERE ci.CartItemID = ? AND ci.CustomerID = ?", (item_id, g.customer_id))
    if not rows:
        return jsonify(error="Cart item not found"), 404
    if quantity > rows[0]["StockQuantity"]:
        return jsonify(error="Not enough stock"), 409
    with transaction() as cur:
        cur.execute("UPDATE dbo.CartItems SET Quantity = ?, UpdatedAt = SYSDATETIME() WHERE CartItemID = ?",
                    (quantity, item_id))
    return jsonify(id=item_id, quantity=quantity)


@bp.delete("/<int:item_id>")
@customer_required
def remove_item(item_id: int):
    if item_id > INT_MAX:
        return jsonify(error="Cart item not found"), 404
    with transaction() as cur:
        cur.execute("DELETE FROM dbo.CartItems WHERE CartItemID = ? AND CustomerID = ?", (item_id, g.customer_id))
        if cur.rowcount == 0:
            return jsonify(error="Cart item not found"), 404
    return "", 204
