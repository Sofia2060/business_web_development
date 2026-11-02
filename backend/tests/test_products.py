"""Integration tests for the product API. They use the local VinoraJewelry database
loaded from database/01_VinoraJewelry_SQLServer.sql (443 products, all Active)."""
import pytest

from app.db import query

# The `client` fixture comes from conftest.py.

def test_list_defaults(client):
    data = client.get("/api/products").get_json()
    assert data["total"] == 443
    assert data["page"] == 1 and data["limit"] == 24
    assert len(data["items"]) == 24
    first = data["items"][0]
    assert {"SKU", "ProductName", "CurrentPrice", "ThumbnailUrl"} <= first.keys()
    assert isinstance(first["CurrentPrice"], int)


def test_pagination_pages_do_not_overlap(client):
    p1 = client.get("/api/products?limit=10&page=1").get_json()["items"]
    p2 = client.get("/api/products?limit=10&page=2").get_json()["items"]
    assert {i["SKU"] for i in p1}.isdisjoint({i["SKU"] for i in p2})


def test_last_page_is_partial(client):
    # 443 = 4 * 100 + 43
    data = client.get("/api/products?limit=100&page=5").get_json()
    assert len(data["items"]) == 43


def test_limit_is_capped(client):
    data = client.get("/api/products?limit=1000").get_json()
    assert data["limit"] == 100 and len(data["items"]) == 100


def test_filter_by_category(client):
    data = client.get("/api/products?category=1&limit=100").get_json()
    assert 0 < data["total"] < 443
    assert all(i["CategoryID"] == 1 for i in data["items"])


def test_search_ignores_accents_and_case(client):
    with_accent = client.get("/api/products?q=Nhẫn cầu hôn").get_json()["total"]
    without = client.get("/api/products?q=nhan cau hon").get_json()["total"]
    assert with_accent > 0 and with_accent == without


def test_search_maps_d_stroke(client):
    # "đ" has no base letter in Unicode, so it needs its own handling.
    with_stroke = client.get("/api/products?q=Nhẫn đôi").get_json()["total"]
    without = client.get("/api/products?q=nhan doi").get_json()["total"]
    assert with_stroke > 0 and with_stroke == without


def test_search_without_match(client):
    assert client.get("/api/products?q=zzzzqqqq").get_json()["total"] == 0


@pytest.mark.parametrize("qs", [
    "page=0", "page=abc", "limit=-1", "category=abc", "category=0", "category=1,x", "category=1,,2", "category=",
    "category=" + ",".join(str(i) for i in range(1, 52)),
    "collection=abc", "material=99K", "material=14K,", "material=", "color=", "color=" + "x" * 21,
    "minPrice=-1", "minPrice=1.5", "minPrice=abc", "maxPrice=", "maxPrice=1" + "0" * 12, "onSale=2", "onSale=yes",
    "sort=evil", "sort=price_asc;DROP TABLE dbo.Products", "sort=",
])
def test_invalid_params_return_400(client, qs):
    assert client.get(f"/api/products?{qs}").status_code == 400


# ---------------- filters and sorting ----------------
# Expected numbers come from separate SQL queries on the tables, not from the API code.

def count(where, params=()):
    return query(f"SELECT COUNT(*) AS n FROM dbo.vw_ProductCatalog WHERE Status = 'Active' AND {where}", params)[0]["n"]


def list_all(client, qs, limit=100):
    return client.get(f"/api/products?limit={limit}&{qs}").get_json()


def test_several_categories_are_or_together(client):
    both = client.get("/api/products?category=1,2&limit=100").get_json()
    assert both["total"] == count("CategoryID IN (1, 2)")
    assert {i["CategoryID"] for i in both["items"]} == {1, 2}


def test_price_range(client):
    data = list_all(client, "minPrice=5000000&maxPrice=10000000")
    assert data["total"] == count("CurrentPrice BETWEEN 5000000 AND 10000000") > 0
    assert all(5_000_000 <= i["CurrentPrice"] <= 10_000_000 for i in data["items"])
    assert list_all(client, "minPrice=80000000")["total"] == count("CurrentPrice >= 80000000")
    assert list_all(client, "maxPrice=0")["total"] == 0


@pytest.mark.parametrize("materials", ["14K", "18K,BAC925", "10K,14K,18K,22K,24K,BAC925"])
def test_material_filter(client, materials):
    wanted = materials.split(",")
    data = list_all(client, f"material={materials}")
    assert data["total"] == count(f"Material IN ({','.join('?' * len(wanted))})", tuple(wanted))
    assert {i["Material"] for i in data["items"]} <= set(wanted)


def test_collection_filter_uses_every_collection_a_product_belongs_to(client):
    data = list_all(client, "collection=1")
    expected = query("SELECT COUNT(*) AS n FROM dbo.ProductCollections WHERE CollectionID = 1")[0]["n"]
    assert data["total"] == expected > 0
    both = list_all(client, "collection=1,2")
    assert both["total"] == query("SELECT COUNT(DISTINCT ProductID) AS n FROM dbo.ProductCollections "
                                  "WHERE CollectionID IN (1, 2)")[0]["n"]


def test_color_filter_matches_products_with_a_variant_of_that_color(client):
    data = list_all(client, "color=Vàng Hồng")
    expected = query("SELECT COUNT(DISTINCT v.ProductID) AS n FROM dbo.ProductVariants v "
                     "WHERE v.GoldColor = N'Vàng Hồng' AND v.IsActive = 1")[0]["n"]
    assert data["total"] == expected > 0
    first = client.get(f"/api/products/{data['items'][0]['SKU']}").get_json()
    assert "Vàng Hồng" in {v["GoldColor"] for v in first["variants"]}
    # Two colors: a product with either color matches, so the total is at least as large as for one color.
    assert list_all(client, "color=Vàng Hồng,Bạc Trắng")["total"] >= data["total"]


def test_on_sale_filter_and_discount_sort(client):
    data = list_all(client, "onSale=1&sort=discount")
    assert data["total"] == count("OriginalPrice > CurrentPrice") > 0
    percents = [(i["OriginalPrice"] - i["CurrentPrice"]) / i["OriginalPrice"] for i in data["items"]]
    assert all(p > 0 for p in percents) and percents == sorted(percents, reverse=True)
    assert list_all(client, "onSale=0")["total"] == 443   # 0 means no filter
    # Sorting by discount alone puts the discounted products first, then the rest.
    mixed = list_all(client, "sort=discount")["items"]
    flags = [i["OriginalPrice"] is not None and i["OriginalPrice"] > i["CurrentPrice"] for i in mixed]
    assert flags == sorted(flags, reverse=True)


@pytest.mark.parametrize("sort,reverse", [("price_asc", False), ("price_desc", True)])
def test_price_sort(client, sort, reverse):
    prices = [i["CurrentPrice"] for i in list_all(client, f"sort={sort}")["items"]]
    assert len(prices) == 100 and prices == sorted(prices, reverse=reverse)
    # The sort works over all products, not only the page: the first item is the cheapest or dearest overall.
    extreme = query("SELECT %s(CurrentPrice) AS p FROM dbo.vw_ProductCatalog" % ("MAX" if reverse else "MIN"))[0]["p"]
    assert prices[0] == extreme


def test_newest_sort_and_featured_default(client):
    newest = list_all(client, "sort=newest")["items"]
    assert [i["ProductID"] for i in newest] == sorted((i["ProductID"] for i in newest), reverse=True)   # same created time
    # Featured is the default: products that have a description come first.
    first_page = client.get("/api/products").get_json()["items"]
    described = query("SELECT ProductID FROM dbo.Products WHERE Description IS NOT NULL")
    assert len(described) >= len(first_page)
    assert {i["ProductID"] for i in first_page} <= {r["ProductID"] for r in described}
    assert client.get("/api/products?sort=featured").get_json()["items"] == first_page


def test_filters_combine_with_and_and_paginate(client):
    qs = "category=1&material=14K&minPrice=10000000&onSale=1"
    expected = count("CategoryID = 1 AND Material = '14K' AND CurrentPrice >= 10000000 AND OriginalPrice > CurrentPrice")
    page1 = client.get(f"/api/products?{qs}&limit=1&page=1").get_json()
    assert page1["total"] == expected and len(page1["items"]) == (1 if expected else 0)
    if expected > 1:
        page2 = client.get(f"/api/products?{qs}&limit=1&page=2").get_json()
        assert page2["items"][0]["SKU"] != page1["items"][0]["SKU"]
    assert client.get(f"/api/products?{qs}&q=zzzzqqqq").get_json()["total"] == 0


def test_a_long_list_of_repeated_values_does_not_break_the_query(client):
    res = client.get("/api/products?limit=1&material=" + ",".join(["14K"] * 3000))
    assert res.status_code == 200 and res.get_json()["total"] == count("Material = '14K'")


@pytest.mark.parametrize("term", ["%", "n_an", "[a-c]", "[", "\\", "100%"])
def test_search_text_is_not_a_like_pattern(client, term):
    # "%" and "_" would match almost everything if they were passed on as wildcards.
    assert client.get("/api/products", query_string={"q": term}).get_json()["total"] == 0


def test_filter_values_are_never_run_as_sql(client):
    for qs in ["color=x'); DROP TABLE p;--", "q=' OR 1=1 --"]:   # the color text is at most 20 characters
        res = client.get(f"/api/products?{qs}")
        assert res.status_code == 200 and res.get_json()["total"] == 0
    assert client.get("/api/products").get_json()["total"] == 443


def test_detail(client):
    data = client.get("/api/products/NDINO131LDIA").get_json()
    assert data["SKU"] == "NDINO131LDIA"
    assert data["Material"] == "14K"
    assert data["CurrentPrice"] > 0
    assert len(data["images"]) >= 1
    skus = {v["VariantSKU"] for v in data["variants"]}
    assert "NDINO131LDIA-VT-10" in skus  # white gold, ring size 10


def test_detail_unknown_sku(client):
    assert client.get("/api/products/NOPE").status_code == 404


# ---------------- products that are sold by quote only ----------------
# The 22 gold-priced products (24K and 22K pendants and one earring) have no online price: the shop gives a quote.

QUOTE_SKU = "MDBZ038"          # 24K pendant, 0.74 g, labor 370,000 VND


def test_the_gold_priced_products_are_quote_only(client):
    assert count("IsQuoteOnly = 1") == 22
    assert query("SELECT COUNT(*) AS n FROM dbo.Products WHERE PricingMethod = 'GoldRate' AND IsQuoteOnly = 0")[0]["n"] == 0
    detail = client.get(f"/api/products/{QUOTE_SKU}").get_json()
    assert detail["IsQuoteOnly"] is True and detail["CurrentPrice"] is None and detail["PricingMethod"] == "GoldRate"
    assert detail["variants"]                                   # it can still be shown, with its colours and sizes
    normal = client.get("/api/products/NDINO131LDIA").get_json()
    assert normal["IsQuoteOnly"] is False and normal["CurrentPrice"] > 0


def test_quote_only_products_are_listed_but_not_matched_by_price_filters(client):
    assert client.get("/api/products?limit=1").get_json()["total"] == 443
    assert list_all(client, "minPrice=0")["total"] == 421
    assert list_all(client, "maxPrice=999999999999")["total"] == 421
    assert list_all(client, "onSale=1")["total"] == count("OriginalPrice > CurrentPrice")
    found = client.get("/api/products", query_string={"q": "Mặt dây", "limit": 100}).get_json()["items"]
    assert any(i["IsQuoteOnly"] for i in found)                 # the search still finds them


@pytest.mark.parametrize("sort", ["price_asc", "price_desc"])
def test_quote_only_products_come_last_when_sorting_by_price(client, sort):
    last_page = client.get(f"/api/products?sort={sort}&limit=100&page=5").get_json()["items"]        # products 401 to 443
    assert len(last_page) == 43
    assert [i["CurrentPrice"] is None for i in last_page] == [False] * 21 + [True] * 22
    assert all(i["IsQuoteOnly"] for i in last_page[21:])


def test_turning_the_flag_off_sells_the_product_at_the_gold_price(client):
    # Tomorrow the shop may decide to sell these online again: the price then follows the gold price table.
    from decimal import ROUND_HALF_UP, Decimal
    from app.db import transaction
    row = query("SELECT p.WeightGram, p.LaborPrice, g.SellPricePerChi FROM dbo.Products p CROSS APPLY "
                "(SELECT TOP (1) SellPricePerChi FROM dbo.GoldPrices WHERE Material = p.Material AND EffectiveFrom <= SYSDATETIME() "
                "ORDER BY EffectiveFrom DESC) g WHERE p.SKU = ?", (QUOTE_SKU,))[0]
    exact = Decimal(str(row["WeightGram"])) / Decimal("3.75") * Decimal(row["SellPricePerChi"]) + Decimal(row["LaborPrice"])
    expected = int((exact / 1000).quantize(Decimal(1), rounding=ROUND_HALF_UP) * 1000)
    with transaction() as cur:
        cur.execute("UPDATE dbo.Products SET IsQuoteOnly = 0 WHERE SKU = ?", (QUOTE_SKU,))
    try:
        assert client.get(f"/api/products/{QUOTE_SKU}").get_json()["CurrentPrice"] == expected == 3330000
    finally:
        with transaction() as cur:
            cur.execute("UPDATE dbo.Products SET IsQuoteOnly = 1 WHERE SKU = ?", (QUOTE_SKU,))
    assert client.get(f"/api/products/{QUOTE_SKU}").get_json()["CurrentPrice"] is None
