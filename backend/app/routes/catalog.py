"""Public lookup data for the shop pages: categories, collections, ring size chart, gold prices.
These replace the category and collection JSON files that were in frontend/mock-data/ (the pages still read
size-chart.json, not /api/ring-sizes). No login needed."""
from flask import Blueprint, jsonify

from ..db import query
from .products import MATERIALS

bp = Blueprint("catalog", __name__, url_prefix="/api")


@bp.get("/categories")
def list_categories():
    return jsonify(query(
        "SELECT cat.CategoryID, cat.CategoryName, cat.CategoryGroup, cat.Slug, cat.Description, cat.RequiresRingSize, "
        "(SELECT COUNT(*) FROM dbo.Products p WHERE p.CategoryID = cat.CategoryID AND p.Status = 'Active') AS ProductCount "
        "FROM dbo.Categories cat WHERE cat.IsActive = 1 ORDER BY cat.DisplayOrder, cat.CategoryID"))


@bp.get("/collections")
def list_collections():
    """Each collection with its product count and the categories and materials its products come in."""
    collections = query(
        "SELECT col.CollectionID, col.CollectionName, col.Slug, col.Description, col.BannerImage, "
        "(SELECT COUNT(*) FROM dbo.ProductCollections pc JOIN dbo.Products p ON p.ProductID = pc.ProductID "
        " WHERE pc.CollectionID = col.CollectionID AND p.Status = 'Active') AS ProductCount "
        "FROM dbo.Collections col WHERE col.IsActive = 1 ORDER BY col.DisplayOrder, col.CollectionID")
    pairs = query(
        "SELECT DISTINCT pc.CollectionID, cat.CategoryName, cat.DisplayOrder, p.Material "
        "FROM dbo.ProductCollections pc JOIN dbo.Products p ON p.ProductID = pc.ProductID "
        "JOIN dbo.Categories cat ON cat.CategoryID = p.CategoryID WHERE p.Status = 'Active'")
    for col in collections:
        mine = [pair for pair in pairs if pair["CollectionID"] == col["CollectionID"]]
        col["Categories"] = [name for _, name in sorted({(pair["DisplayOrder"], pair["CategoryName"]) for pair in mine})]
        col["Materials"] = [m for m in MATERIALS if m in {pair["Material"] for pair in mine}]
    return jsonify(collections)


@bp.get("/ring-sizes")
def list_ring_sizes():
    return jsonify(query(
        "SELECT SizeVN, CircumferenceMm, InnerDiameterMm, SizeUS FROM dbo.RingSizeChart ORDER BY SizeVN"))


@bp.get("/gold-prices")
def current_gold_prices():
    """The price in force now for each gold type (VND per chi, 1 chi = 3.75 g), highest first."""
    return jsonify(query(
        "SELECT Material, BuyPricePerChi, SellPricePerChi, EffectiveFrom FROM ("
        " SELECT g.*, ROW_NUMBER() OVER (PARTITION BY g.Material ORDER BY g.EffectiveFrom DESC) AS rn"
        " FROM dbo.GoldPrices g WHERE g.EffectiveFrom <= SYSDATETIME()) x "
        "WHERE rn = 1 ORDER BY SellPricePerChi DESC"))
