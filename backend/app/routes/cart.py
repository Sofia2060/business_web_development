"""Shopping cart of the logged-in customer. One row per variant and engraving text."""
from flask import Blueprint, g, jsonify

from ..auth import customer_required
from ..config import FREE_SHIPPING_FROM, STANDARD_SHIPPING_FEE
from ..db import query, transaction
from ..validation import body, is_int, text, utf16_len

bp = Blueprint("cart", __name__, url_prefix="/api/cart")

MAX_QTY = 10  # same as the CK_CartItems_Qty constraint
MAX_ENGRAVING = 30


def shipping_fee(subtotal: int) -> int:
    return 0 if subtotal >= FREE_SHIPPING_FROM else STANDARD_SHIPPING_FEE


def cart_subtotal(customer_id: int) -> int:
    rows = query(
        "SELECT ISNULL(SUM(ci.Quantity * dbo.fn_GetCurrentPrice(v.ProductID)), 0) AS s FROM dbo.CartItems ci "
        "JOIN dbo.ProductVariants v ON v.VariantID = ci.VariantID WHERE ci.CustomerID = ?", (customer_id,))
    return rows[0]["s"]


@bp.get("")
@customer_required
def get_cart():
    items = query(
        "SELECT ci.CartItemID, v.VariantSKU, p.SKU, p.ProductName, v.GoldColor, v.RingSize, ci.Quantity, "
        "ci.EngravingText, dbo.fn_GetCurrentPrice(p.ProductID) AS UnitPrice, v.StockQuantity "
        "FROM dbo.CartItems ci JOIN dbo.ProductVariants v ON v.VariantID = ci.VariantID "
        "JOIN dbo.Products p ON p.ProductID = v.ProductID WHERE ci.CustomerID = ? ORDER BY ci.CartItemID",
        (g.customer_id,))
    subtotal = sum((i["UnitPrice"] or 0) * i["Quantity"] for i in items)
    fee = shipping_fee(subtotal) if items else 0
    return jsonify(items=items, subtotal=subtotal, shippingFee=fee, total=subtotal + fee)


@bp.post("")
@customer_required
def add_item():
    """Add a variant. Adding the same variant with the same engraving raises its quantity."""
    data = body()
    sku = text(data, "variantSku")
    engraving = text(data, "engravingText")
    quantity = data.get("quantity", 1)
    if not sku or engraving is None or not is_int(quantity, 1, MAX_QTY):
        return jsonify(error=f"variantSku and a quantity from 1 to {MAX_QTY} are required"), 400
    engraving = engraving.strip() or None
    if engraving and utf16_len(engraving) > MAX_ENGRAVING:
        return jsonify(error=f"Engraving text is limited to {MAX_ENGRAVING} characters"), 400

    variants = query(
        "SELECT v.VariantID, v.StockQuantity, p.IsEngravable FROM dbo.ProductVariants v "
        "JOIN dbo.Products p ON p.ProductID = v.ProductID "
        "WHERE v.VariantSKU = ? AND v.IsActive = 1 AND p.Status = 'Active'", (sku,))
    if not variants:
        return jsonify(error="Variant not found"), 404
    variant = variants[0]
    if engraving and not variant["IsEngravable"]:
        return jsonify(error="This product cannot be engraved"), 400

    with transaction() as cur:
        if engraving:
            cur.execute("SELECT CartItemID, Quantity, EngravingText FROM dbo.CartItems WHERE CustomerID = ? "
                        "AND VariantID = ? AND EngravingText = ?", (g.customer_id, variant["VariantID"], engraving))
        else:
            cur.execute("SELECT CartItemID, Quantity, EngravingText FROM dbo.CartItems WHERE CustomerID = ? "
                        "AND VariantID = ? AND EngravingText IS NULL", (g.customer_id, variant["VariantID"]))
        existing = cur.fetchone()
        # The database compares text without case or accents ("Năm" equals "Nam"). Do not silently merge those.
        if existing and existing.EngravingText != engraving:
            return jsonify(error="The cart has this item with a very similar engraving text. Change that line instead."), 409
        new_qty = quantity + (existing.Quantity if existing else 0)
        if new_qty > MAX_QTY:
            return jsonify(error=f"At most {MAX_QTY} of one item per order"), 400
        if new_qty > variant["StockQuantity"]:
            return jsonify(error="Not enough stock"), 409
        if existing:
            cur.execute("UPDATE dbo.CartItems SET Quantity = ?, UpdatedAt = SYSDATETIME() WHERE CartItemID = ?",
                        (new_qty, existing.CartItemID))
            item_id = existing.CartItemID
        else:
            cur.execute("INSERT INTO dbo.CartItems (CustomerID, VariantID, Quantity, EngravingText) "
                        "OUTPUT INSERTED.CartItemID VALUES (?, ?, ?, ?)",
                        (g.customer_id, variant["VariantID"], quantity, engraving))
            item_id = cur.fetchval()
    return jsonify(id=item_id, quantity=new_qty), (200 if existing else 201)


@bp.patch("/<int:item_id>")
@customer_required
def set_quantity(item_id: int):
    quantity = body().get("quantity")
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
    with transaction() as cur:
        cur.execute("DELETE FROM dbo.CartItems WHERE CartItemID = ? AND CustomerID = ?", (item_id, g.customer_id))
        if cur.rowcount == 0:
            return jsonify(error="Cart item not found"), 404
    return "", 204
