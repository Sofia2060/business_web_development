"""Read-only product API: list (with filters and sorting) and detail."""
from flask import Blueprint, jsonify, request

from ..db import query
from ..validation import id_list, money, page_number

bp = Blueprint("products", __name__, url_prefix="/api/products")

DEFAULT_LIMIT = 24
MAX_LIMIT = 100
MATERIALS = ("10K", "14K", "18K", "22K", "24K", "BAC925")
MAX_COLORS = 10

# Sort name -> ORDER BY text. Only these fixed texts reach the SQL, never the raw query string.
# Products without a price (gold-rate items with no gold price yet) always come last when sorting by price.
SORTS = {
    # Products with a description first (the shop's own picks), then newest.
    "featured": "CASE WHEN p.Description IS NULL THEN 1 ELSE 0 END, p.CreatedAt DESC, c.ProductID",
    "newest": "p.CreatedAt DESC, c.ProductID DESC",
    "price_asc": "CASE WHEN c.CurrentPrice IS NULL THEN 1 ELSE 0 END, c.CurrentPrice, c.ProductID",
    "price_desc": "CASE WHEN c.CurrentPrice IS NULL THEN 1 ELSE 0 END, c.CurrentPrice DESC, c.ProductID",
    # Biggest percentage off first; products that are not on sale count as 0%.
    "discount": "CASE WHEN c.OriginalPrice > c.CurrentPrice THEN (c.OriginalPrice - c.CurrentPrice) * 100.0 / c.OriginalPrice "
                "ELSE 0 END DESC, c.CurrentPrice DESC, c.ProductID",
}


def _filters(args) -> tuple[list[str], list]:
    """Turn the query string into WHERE conditions and their parameters (always '?' placeholders).
    Raises ValueError(parameter name) when a value is not valid."""
    where, params = ["c.Status = 'Active'"], []

    def in_list(column_sql: str, values: list):
        where.append(f"{column_sql} IN ({','.join('?' * len(values))})")
        params.extend(values)

    for name in ("category", "collection"):
        if args.get(name) is not None:
            ids = id_list(args[name])
            if ids is None:
                raise ValueError(name)
            if name == "category":
                in_list("c.CategoryID", ids)
            else:
                # A product can sit in several collections, so look at the link table, not only the main collection.
                where.append(f"EXISTS (SELECT 1 FROM dbo.ProductCollections pc WHERE pc.ProductID = c.ProductID "
                             f"AND pc.CollectionID IN ({','.join('?' * len(ids))}))")
                params.extend(ids)

    if args.get("material") is not None:
        materials = list(dict.fromkeys(args["material"].split(",")))   # no repeats, so the list stays short
        if not set(materials) <= set(MATERIALS):
            raise ValueError("material")
        in_list("c.Material", materials)

    if args.get("color") is not None:
        colors = args["color"].split(",")
        if len(colors) > MAX_COLORS or not all(0 < len(color) <= 20 for color in colors):
            raise ValueError("color")
        where.append(f"EXISTS (SELECT 1 FROM dbo.ProductVariants v WHERE v.ProductID = c.ProductID AND v.IsActive = 1 "
                     f"AND v.GoldColor IN ({','.join('?' * len(colors))}))")
        params.extend(colors)

    for name, operator in (("minPrice", ">="), ("maxPrice", "<=")):
        if args.get(name) is not None:
            amount = money(args[name])
            if amount is None:
                raise ValueError(name)
            where.append(f"c.CurrentPrice {operator} ?")  # a product with no price never matches a price range
            params.append(amount)

    if args.get("onSale") is not None:
        if args["onSale"] not in ("0", "1"):
            raise ValueError("onSale")
        if args["onSale"] == "1":
            where.append("c.OriginalPrice > c.CurrentPrice")

    q = args.get("q", "").strip()
    if q:
        # The database collation (Vietnamese_100_CI_AI) does NOT fold accents, so "nhan" would not
        # match "Nhẫn". Compare with Latin1_General_100_CI_AI instead, which does.
        # That collation keeps "đ" as a separate letter, so map it to "d" on both sides.
        term = q.replace("đ", "d").replace("Đ", "D")
        for special in ("\\", "%", "_", "["):    # the typed text is searched as it is, not as a LIKE pattern
            term = term.replace(special, "\\" + special)
        where.append("REPLACE(c.ProductName, N'đ', N'd') COLLATE Latin1_General_100_CI_AI LIKE ? ESCAPE '\\'")
        params.append("%" + term + "%")
    return where, params


def _add_card_details(items: list[dict]) -> None:
    """Add what a product card shows to each row: Colors (gold colors of the active variants, in the order the
    variants were created) and Images (the first two image URLs, the thumbnail first)."""
    if not items:
        return
    ids = tuple(item["ProductID"] for item in items)
    marks = ",".join("?" * len(ids))
    colors: dict[int, list[str]] = {}
    for row in query(f"SELECT ProductID, GoldColor FROM dbo.ProductVariants WHERE IsActive = 1 AND GoldColor IS NOT NULL "
                     f"AND ProductID IN ({marks}) GROUP BY ProductID, GoldColor ORDER BY ProductID, MIN(VariantID)", ids):
        colors.setdefault(row["ProductID"], []).append(row["GoldColor"])
    images: dict[int, list[str]] = {}
    for row in query(f"SELECT ProductID, ImageUrl FROM (SELECT ProductID, ImageUrl, ROW_NUMBER() OVER "
                     f"(PARTITION BY ProductID ORDER BY IsThumbnail DESC, SortOrder) AS n FROM dbo.ProductImages "
                     f"WHERE ProductID IN ({marks})) x WHERE n <= 2 ORDER BY ProductID, n", ids):
        images.setdefault(row["ProductID"], []).append(row["ImageUrl"])
    for item in items:
        item["Colors"] = colors.get(item["ProductID"], [])
        item["Images"] = images.get(item["ProductID"], [])


@bp.get("")
def list_products():
    """List active products.

    Query: page, limit, q (name search without accents), sort (featured, newest, price_asc, price_desc, discount),
    and filters that combine with AND: category, collection (comma separated ids), material (10K, 14K, ...),
    color (gold colors such as "Vàng Trắng"), minPrice, maxPrice (VND), onSale=1 (only discounted products).
    Each item also has Colors, Images (first two), HasDescription and CreatedAt, so a page can draw cards from it.
    """
    page = page_number(request.args.get("page"), 1)
    limit = page_number(request.args.get("limit"), DEFAULT_LIMIT)
    sort = request.args.get("sort", "featured")
    if not page or not limit or sort not in SORTS:
        return jsonify(error="Invalid query parameter"), 400
    limit = min(limit, MAX_LIMIT)
    try:
        where, params = _filters(request.args)
    except ValueError as bad:
        return jsonify(error=f"Invalid query parameter: {bad}"), 400
    clause = " AND ".join(where)

    total = query(f"SELECT COUNT(*) AS n FROM dbo.vw_ProductCatalog c WHERE {clause}", tuple(params))[0]["n"]
    items = query(
        f"SELECT c.*, p.CreatedAt, CAST(CASE WHEN p.Description IS NULL OR p.Description = N'' THEN 0 ELSE 1 END AS BIT) "
        f"AS HasDescription FROM dbo.vw_ProductCatalog c JOIN dbo.Products p ON p.ProductID = c.ProductID "
        f"WHERE {clause} ORDER BY {SORTS[sort]} OFFSET ? ROWS FETCH NEXT ? ROWS ONLY",
        tuple(params) + ((page - 1) * limit, limit),
    )
    _add_card_details(items)
    return jsonify(total=total, page=page, limit=limit, items=items)


@bp.get("/<sku>")
def get_product(sku: str):
    """Return one product with its images, stones and variants."""
    rows = query(
        "SELECT c.*, p.Description, p.IsEngravable, p.CreatedAt FROM dbo.vw_ProductCatalog c "
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
