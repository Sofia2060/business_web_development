"""Read-only product API: list and detail."""
from flask import Blueprint, jsonify, request

from ..db import query

bp = Blueprint("products", __name__, url_prefix="/api/products")

DEFAULT_LIMIT = 24
MAX_LIMIT = 100


def _int_arg(name: str, default: int, minimum: int = 1):
    """Read a positive integer from the query string. Returns None when invalid."""
    raw = request.args.get(name)
    if raw is None:
        return default
    if not raw.isdigit() or int(raw) < minimum:
        return None
    return int(raw)


@bp.get("")
def list_products():
    """List active products. Query: category (id), q (name search), page, limit."""
    page = _int_arg("page", 1)
    limit = _int_arg("limit", DEFAULT_LIMIT)
    category = _int_arg("category", None)
    if page is None or limit is None or (request.args.get("category") and category is None):
        return jsonify(error="Invalid query parameter"), 400
    limit = min(limit, MAX_LIMIT)

    where, params = ["Status = 'Active'"], []
    if category:
        where.append("CategoryID = ?")
        params.append(category)
    q = request.args.get("q", "").strip()
    if q:
        # The database collation (Vietnamese_100_CI_AI) does NOT fold accents, so "nhan" would not
        # match "Nhẫn". Compare with Latin1_General_100_CI_AI instead, which does.
        # That collation keeps "đ" as a separate letter, so map it to "d" on both sides.
        where.append("REPLACE(ProductName, N'đ', N'd') COLLATE Latin1_General_100_CI_AI LIKE ?")
        params.append("%" + q.replace("đ", "d").replace("Đ", "D") + "%")
    clause = " AND ".join(where)

    total = query(f"SELECT COUNT(*) AS n FROM dbo.vw_ProductCatalog WHERE {clause}", tuple(params))[0]["n"]
    items = query(
        f"SELECT * FROM dbo.vw_ProductCatalog WHERE {clause} "
        "ORDER BY ProductID OFFSET ? ROWS FETCH NEXT ? ROWS ONLY",
        tuple(params) + ((page - 1) * limit, limit),
    )
    return jsonify(total=total, page=page, limit=limit, items=items)


@bp.get("/<sku>")
def get_product(sku: str):
    """Return one product with its images, stones and variants."""
    rows = query(
        "SELECT c.*, p.Description, p.IsEngravable FROM dbo.vw_ProductCatalog c "
        "JOIN dbo.Products p ON p.ProductID = c.ProductID WHERE c.SKU = ? AND c.Status = 'Active'",
        (sku,),
    )
    if not rows:
        return jsonify(error="Product not found"), 404
    product = rows[0]
    pid = product["ProductID"]
    product["images"] = query(
        "SELECT ImageUrl, IsThumbnail FROM dbo.ProductImages WHERE ProductID = ? ORDER BY SortOrder", (pid,))
    product["stones"] = query(
        "SELECT StoneType, StoneName, SizeMm, Quantity, IsMainStone FROM dbo.ProductStones WHERE ProductID = ?",
        (pid,))
    product["variants"] = query(
        "SELECT VariantSKU, GoldColor, RingSize, StockQuantity FROM dbo.ProductVariants "
        "WHERE ProductID = ? AND IsActive = 1 ORDER BY GoldColor, RingSize", (pid,))
    return jsonify(product)
