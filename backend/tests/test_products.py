"""Integration tests for the product API. They use the local VinoraJewelry database
loaded from database/01_init_schema.sql (443 products, all Active)."""
import pytest

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


@pytest.mark.parametrize("qs", ["page=0", "page=abc", "limit=-1", "category=abc"])
def test_invalid_params_return_400(client, qs):
    assert client.get(f"/api/products?{qs}").status_code == 400


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
