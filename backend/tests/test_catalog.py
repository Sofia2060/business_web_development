"""Tests for the lookup endpoints (categories, collections, ring sizes, gold prices) and the voucher check.
The shop's old JSON files in frontend/mock-data/ are used as a second source of truth: the API must give
the same names and counts, so the pages can switch from the files to the API without a visible change.
Voucher data used (database/01_*.sql): WELCOME5 gives 5% for goods from 2,000,000 VND (max 1,000,000),
VINORA500K gives 500,000 VND for goods from 10,000,000 VND. BT161B-VT is an earring set of 2,361,000 VND."""
import json
import uuid

import pytest

from app import create_app
from app.config import FRONTEND_DIR
from app.db import query, transaction
from conftest import make_user, PASSWORD
from test_orders import add_to_cart, checkout, new_customer

MID = "BT161B-VT"


def mock(name):
    return json.loads((FRONTEND_DIR / "mock-data" / name).read_text(encoding="utf-8"))


# ---------------- categories, collections, ring sizes ----------------

def test_categories_match_the_old_json_file(client):
    api = client.get("/api/categories").get_json()
    old = mock("categories.json")["danhMuc"]
    assert [(c["CategoryName"], c["CategoryGroup"], c["ProductCount"]) for c in api] == \
           [(c["ten"], c["nhom"], c["soLuong"]) for c in old]
    assert sum(c["ProductCount"] for c in api) == 443
    assert [c["RequiresRingSize"] for c in api][:4] == [True, True, True, False]


def test_collections_match_the_old_json_file(client):
    api = {c["CollectionName"]: c for c in client.get("/api/collections").get_json()}
    old = mock("collections.json")["boSuuTap"]
    assert set(api) == {c["ten"] for c in old}
    for c in old:
        got = api[c["ten"]]
        assert got["ProductCount"] == c["soLuong"], c["ten"]
        # The old file lists only the main categories of a collection (the three biggest), the API lists all of them.
        assert set(c["loaiSanPham"]) <= set(got["Categories"]), c["ten"]
        assert set(c["chatLieu"]) <= set(got["Materials"]), c["ten"]
    assert sum(c["ProductCount"] for c in api.values()) == 443


def test_collection_categories_and_materials_are_what_its_products_really_are(client):
    rows = query("SELECT col.CollectionName AS n, cat.CategoryName AS c, p.Material AS m "
                 "FROM dbo.ProductCollections pc JOIN dbo.Collections col ON col.CollectionID = pc.CollectionID "
                 "JOIN dbo.Products p ON p.ProductID = pc.ProductID JOIN dbo.Categories cat ON cat.CategoryID = p.CategoryID")
    for col in client.get("/api/collections").get_json():
        mine = [r for r in rows if r["n"] == col["CollectionName"]]
        assert set(col["Categories"]) == {r["c"] for r in mine}, col["CollectionName"]
        assert set(col["Materials"]) == {r["m"] for r in mine}, col["CollectionName"]


def test_collection_lists_are_in_a_fixed_order(client):
    first = client.get("/api/collections").get_json()[0]
    assert first["Categories"] == sorted(first["Categories"], key=lambda n: query(
        "SELECT DisplayOrder FROM dbo.Categories WHERE CategoryName = ?", (n,))[0]["DisplayOrder"])
    assert first["Materials"] == [m for m in ("10K", "14K", "18K", "22K", "24K", "BAC925") if m in first["Materials"]]


def test_ring_sizes_match_the_old_json_file(client):
    api = {r["SizeVN"]: r for r in client.get("/api/ring-sizes").get_json()}
    assert list(api) == sorted(api) and len(api) >= 20
    for row in mock("size-chart.json")["bangSize"]:
        got = api[row["size"]]
        # The US size is left out on purpose: the two sources differ for size 15 (7.0 in the file, 7.5 in the database).
        assert (got["CircumferenceMm"], got["InnerDiameterMm"]) == (row["chuVi"], row["duongKinh"])


def test_lookup_endpoints_need_no_login(client):
    for url in ("/api/categories", "/api/collections", "/api/ring-sizes", "/api/gold-prices"):
        assert client.get(url).status_code == 200


# ---------------- gold prices ----------------

def test_gold_prices_show_the_price_now_in_force(client):
    data = client.get("/api/gold-prices").get_json()
    assert [row["Material"] for row in data] == ["24K", "22K", "18K", "14K", "10K"]
    assert [row["SellPricePerChi"] for row in data] == sorted((r["SellPricePerChi"] for r in data), reverse=True)
    assert all(row["SellPricePerChi"] >= row["BuyPricePerChi"] > 0 for row in data)


def test_gold_prices_ignore_future_prices_and_use_the_latest_older_one(client):
    # Two extra rows for 10K: one already in force and newer than the seed row, one that starts in the future.
    with transaction() as cur:
        cur.execute("INSERT INTO dbo.GoldPrices (Material, BuyPricePerChi, SellPricePerChi, EffectiveFrom) VALUES "
                    "('10K', 1000, 1100, DATEADD(MINUTE, -5, SYSDATETIME())), "
                    "('10K', 2000, 2200, DATEADD(DAY, 30, SYSDATETIME()))")
    try:
        ten_k = next(r for r in client.get("/api/gold-prices").get_json() if r["Material"] == "10K")
        assert (ten_k["BuyPricePerChi"], ten_k["SellPricePerChi"]) == (1000, 1100)
    finally:
        with transaction() as cur:
            cur.execute("DELETE FROM dbo.GoldPrices WHERE Material = '10K' AND SellPricePerChi IN (1100, 2200)")
    ten_k = next(r for r in client.get("/api/gold-prices").get_json() if r["Material"] == "10K")
    assert ten_k["SellPricePerChi"] > 2200


# ---------------- voucher check ----------------

@pytest.fixture(autouse=True)
def restock(db_ready):
    with transaction() as cur:
        cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = 100 WHERE VariantSKU = ?", (MID,))


@pytest.fixture
def make_voucher(db_ready):
    """Create vouchers for a test and switch them off afterwards (an order that used one keeps a link to it,
    so it cannot be deleted). Returns the code."""
    codes = []

    def make(dtype="Percent", value=10, max_discount=None, min_order=0, start="-1", end="+30", limit=None, used=0, active=1):
        code = "T" + uuid.uuid4().hex[:10].upper()
        codes.append(code)
        with transaction() as cur:
            cur.execute(
                "INSERT INTO dbo.Vouchers (VoucherCode, VoucherName, DiscountType, DiscountValue, MaxDiscountAmount, "
                "MinOrderValue, StartAt, EndAt, UsageLimit, UsedCount, IsActive) VALUES (?, N'Test', ?, ?, ?, ?, "
                f"DATEADD(DAY, {int(start)}, SYSDATETIME()), DATEADD(DAY, {int(end)}, SYSDATETIME()), ?, ?, ?)",
                (code, dtype, value, max_discount, min_order, limit, used, active))
        return code

    yield make
    with transaction() as cur:
        for code in codes:
            cur.execute("UPDATE dbo.Vouchers SET IsActive = 0 WHERE VoucherCode = ?", (code,))


def customer_with_cart(sku=MID, quantity=1):
    client, address_id = new_customer()
    assert add_to_cart(client, sku, quantity).status_code in (200, 201)
    return client, address_id


def check(client, code):
    return client.post("/api/vouchers/check", json={"code": code})


def test_voucher_check_needs_a_customer_login(client):
    assert check(client, "WELCOME5").status_code == 401
    admin = create_app().test_client()
    email = f"cat-admin-{uuid.uuid4().hex[:8]}@example.test"
    make_user(email, role="Admin")
    admin.post("/api/auth/login", json={"email": email, "password": PASSWORD})
    assert check(admin, "WELCOME5").status_code == 403


def test_voucher_check_percent_discount_rounds_to_thousands(client):
    c, _ = customer_with_cart()
    res = check(c, " welcome5 ")           # case and spaces around the code do not matter
    assert res.status_code == 200
    # 5% of 2,361,000 = 118,050, rounded to the nearest 1,000
    assert res.get_json() == {"code": "WELCOME5", "name": res.get_json()["name"], "discount": 118000, "subtotal": 2361000}


def test_voucher_check_is_what_the_order_then_charges(client, make_voucher):
    # 50% of 2,361,000 = 1,180,500 is exactly half way between two thousands: SQL rounds it up.
    codes = [make_voucher(value=50), make_voucher(value=7), make_voucher("Amount", 300000), make_voucher(value=40, max_discount=100000)]
    for code in codes:
        c, address_id = customer_with_cart()
        promised = check(c, code).get_json()["discount"]
        order = checkout(c, address_id, voucherCode=code).get_json()
        charged = query("SELECT DiscountAmount, Subtotal FROM dbo.Orders WHERE OrderCode = ?", (order["OrderCode"],))[0]
        assert promised == charged["DiscountAmount"] > 0, code
        assert order["TotalAmount"] == charged["Subtotal"] - promised + order["ShippingFee"]


def test_voucher_discount_is_capped(client, make_voucher):
    c, _ = customer_with_cart()
    assert check(c, make_voucher(value=40, max_discount=100000)).get_json()["discount"] == 100000
    assert check(c, make_voucher("Amount", 9_000_000)).get_json()["discount"] == 2361000   # never more than the goods


def test_voucher_check_uses_the_whole_cart(client):
    c, _ = customer_with_cart(quantity=2)
    assert check(c, "WELCOME5").get_json()["discount"] == 236000    # 5% of 4,722,000 = 236,100


@pytest.mark.parametrize("kwargs,reason,status", [
    ({"active": 0}, "not_found", 404),                      # a switched-off or not yet started voucher looks unknown
    ({"start": "+2", "end": "+9"}, "not_found", 404),
    ({"start": "-9", "end": "-2"}, "expired", 409),
    ({"limit": 5, "used": 5}, "used_up", 409),
    ({"min_order": 5_000_000}, "min_order", 409),
])
def test_voucher_that_cannot_be_used_says_why(client, make_voucher, kwargs, reason, status):
    c, _ = customer_with_cart()
    res = check(c, make_voucher(**kwargs))
    assert res.status_code == status and res.get_json()["reason"] == reason
    assert ("minOrderValue" in res.get_json()) == (reason == "min_order")


def test_voucher_with_a_free_slot_left_works(client, make_voucher):
    c, _ = customer_with_cart()
    assert check(c, make_voucher(limit=5, used=4)).status_code == 200


def test_voucher_minimum_is_checked_against_the_cart(client):
    c, _ = customer_with_cart()
    res = check(c, "VINORA500K")                 # needs goods from 10,000,000
    assert res.status_code == 409 and res.get_json()["minOrderValue"] == 10_000_000


def test_unknown_voucher_and_bad_input(client):
    c, _ = customer_with_cart()
    assert check(c, "NO-SUCH-CODE").status_code == 404
    for body in ({}, {"code": ""}, {"code": "   "}, {"code": 5}, {"code": None}, {"code": "X" * 31}, [], "x"):
        assert c.post("/api/vouchers/check", json=body).status_code == 400, body
    assert c.post("/api/vouchers/check").status_code == 400


def test_voucher_check_with_empty_cart(client):
    c, _ = new_customer()
    res = check(c, "WELCOME5")
    assert res.status_code == 400 and res.get_json()["error"] == "The cart is empty"


def test_voucher_check_does_not_use_up_the_voucher(client, make_voucher):
    code = make_voucher(limit=1)
    c, _ = customer_with_cart()
    for _ in range(3):
        assert check(c, code).status_code == 200
    assert query("SELECT UsedCount FROM dbo.Vouchers WHERE VoucherCode = ?", (code,))[0]["UsedCount"] == 0


# ---------------- the voucher check for a visitor without an account (the cart is in the browser) ----------------

def guest_check(client, code, items):
    return client.post("/api/vouchers/check", json={"code": code, "items": items})


def test_a_guest_checks_a_voucher_with_the_lines_of_the_browser_cart(client):
    res = guest_check(client, " welcome5 ", [{"variantSku": MID, "quantity": 1}])
    assert res.status_code == 200 and res.get_json()["discount"] == 118000 and res.get_json()["subtotal"] == 2361000
    twice = guest_check(client, "WELCOME5", [{"variantSku": MID, "quantity": 1}, {"variantSku": MID, "quantity": 1}])
    assert twice.get_json()["subtotal"] == 4722000 and twice.get_json()["discount"] == 236000   # 5% of 4,722,000 = 236,100


def test_a_guest_check_gives_the_same_discount_as_the_guest_order(client):
    from test_guest_orders import guest_order
    items = [{"variantSku": MID, "quantity": 1}]
    promised = guest_check(client, "WELCOME5", items).get_json()["discount"]
    _, order = guest_order(client, items=items, voucherCode="WELCOME5")
    assert order.status_code == 201
    charged = query("SELECT DiscountAmount FROM dbo.Orders WHERE OrderCode = ?", (order.get_json()["OrderCode"],))[0]
    assert promised == charged["DiscountAmount"] == 118000


@pytest.mark.parametrize("code,reason,status", [("NO-SUCH-CODE", "not_found", 404), ("VINORA500K", "min_order", 409)])
def test_a_guest_voucher_that_cannot_be_used_says_why(client, code, reason, status):
    res = guest_check(client, code, [{"variantSku": MID, "quantity": 1}])
    assert res.status_code == status and res.get_json()["reason"] == reason


def test_a_guest_check_refuses_bad_lines(client):
    quote = query("SELECT TOP (1) v.VariantSKU FROM dbo.ProductVariants v JOIN dbo.Products p ON p.ProductID = v.ProductID "
                  "WHERE p.IsQuoteOnly = 1 ORDER BY v.VariantID")[0]["VariantSKU"]
    assert guest_check(client, "WELCOME5", [{"variantSku": "NO-SUCH-SKU", "quantity": 1}]).status_code == 404
    res = guest_check(client, "WELCOME5", [{"variantSku": quote, "quantity": 1}])
    assert res.status_code == 409 and res.get_json()["reason"] == "quote_only"
    for items in ([], "x", [1], [{"variantSku": MID, "quantity": 0}], [{"quantity": 1}], [{"variantSku": MID}] * 21):
        assert guest_check(client, "WELCOME5", items).status_code == 400, items
    assert client.post("/api/vouchers/check", json={"code": "WELCOME5"}).status_code == 401      # no login, no items


def test_a_logged_in_customer_is_checked_against_the_cart_not_the_items_they_send(client):
    c, _ = customer_with_cart(quantity=2)
    res = c.post("/api/vouchers/check", json={"code": "WELCOME5", "items": [{"variantSku": MID, "quantity": 1}]})
    assert res.get_json()["subtotal"] == 4722000
