"""Products the logged-in customer opened recently. Guests keep this list in their browser instead."""
from flask import Blueprint, g, jsonify, request

from ..auth import customer_required
from ..db import call, query
from ..validation import body, page_number, text

bp = Blueprint("recently_viewed", __name__, url_prefix="/api/recently-viewed")

DEFAULT_LIMIT = 10
MAX_LIMIT = 50


@bp.get("")
@customer_required
def list_recently_viewed():
    """Newest first. Query: limit (default 10, at most 50). Same fields as the product list, plus LastViewedAt."""
    limit = page_number(request.args.get("limit"), DEFAULT_LIMIT)
    if not limit:
        return jsonify(error="Invalid query parameter"), 400
    return jsonify(query(
        "SELECT TOP (?) c.*, r.LastViewedAt FROM dbo.RecentlyViewedProducts r "
        "JOIN dbo.vw_ProductCatalog c ON c.ProductID = r.ProductID "
        "WHERE r.CustomerID = ? AND c.Status = 'Active' ORDER BY r.LastViewedAt DESC, c.ProductID DESC",
        (min(limit, MAX_LIMIT), g.customer_id)))


@bp.post("")
@customer_required
def track_view():
    """Body: {"sku": "NDINO131LDIA"}. Call it when the product page opens (sp_TrackProductView)."""
    sku = text(body(), "sku")
    if not sku:
        return jsonify(error="sku is required"), 400
    rows = query("SELECT ProductID FROM dbo.Products WHERE SKU = ? AND Status = 'Active'", (sku,))
    if not rows:
        return jsonify(error="Product not found"), 404
    call("EXEC dbo.sp_TrackProductView @CustomerID = ?, @ProductID = ?", (g.customer_id, rows[0]["ProductID"]))
    return "", 204
