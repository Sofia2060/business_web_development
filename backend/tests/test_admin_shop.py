"""Tests for the admin API of customers, reviews, warranty cards, after-sales appointments and products
(backend/app/routes/admin_shop.py). The test database has the catalog but no fake customers, so each test makes its own."""
import datetime

import pytest

from app.db import query, transaction
from test_guest_orders import guest_order
from test_orders import MID, SMALL, add_to_cart, checkout, new_admin, new_customer, place
from test_sql_rules import book, delivered_order_with_card

SOON = lambda days=3: datetime.datetime.now() + datetime.timedelta(days=days)   # noqa: E731


STOCKED = (MID, SMALL, "NC433-BT-9")


@pytest.fixture(autouse=True)
def restock(db_ready):
    """Plenty of stock while a test runs, then the stock is put back: other tests rely on the small stock they start with."""
    marks = ", ".join("?" * len(STOCKED))
    before = query(f"SELECT VariantSKU, StockQuantity FROM dbo.ProductVariants WHERE VariantSKU IN ({marks})", STOCKED)
    with transaction() as cur:
        cur.execute(f"UPDATE dbo.ProductVariants SET StockQuantity = 100 WHERE VariantSKU IN ({marks})", STOCKED)
    yield
    with transaction() as cur:
        for row in before:
            cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = ? WHERE VariantSKU = ?", (row["StockQuantity"], row["VariantSKU"]))


def row_of(rows, key, value):
    return next(r for r in rows if r[key] == value)


# ---------------- who may call ----------------

@pytest.mark.parametrize("method,path", [
    ("get", "/api/admin/customers"), ("get", "/api/admin/feedbacks"), ("get", "/api/admin/warranties"),
    ("get", "/api/admin/retention-stats"),
    ("get", "/api/admin/services"), ("get", "/api/admin/products"),
    ("post", "/api/admin/services/1/schedule"), ("post", "/api/admin/services/1/complete"),
    ("post", "/api/admin/services/1/cancel"), ("patch", "/api/admin/products/X"),
])
def test_only_admins_can_use_the_shop_admin_api(client, method, path):
    assert getattr(client, method)(path).status_code == 401
    customer, _ = new_customer()
    assert getattr(customer, method)(path).status_code == 403


# ---------------- retention popup ----------------

def test_retention_stats_count_kept_and_cancelled_orders(client):
    admin = new_admin()
    before = admin.get("/api/admin/retention-stats").get_json()
    customer, address = new_customer()
    for keep in (True, False):                                  # one order is kept by the popup, the other is cancelled
        code = place(customer, address, SMALL)["OrderCode"]
        assert customer.post(f"/api/orders/{code}/cancel", json={}).status_code == 200
        assert customer.post(f"/api/orders/{code}/cancel/respond", json={"keepOrder": keep}).status_code == 200
    after = admin.get("/api/admin/retention-stats").get_json()
    assert after["OrdersWithCancelRequest"] == before["OrdersWithCancelRequest"] + 2
    assert after["OrdersKeptByPopup"] == before["OrdersKeptByPopup"] + 1
    assert after["OrdersCancelled"] == before["OrdersCancelled"] + 1
    assert after["OrdersKeptAndDelivered"] == before["OrdersKeptAndDelivered"]
    assert 0 < after["KeepRatePercent"] <= 100


# ---------------- customers ----------------

def test_customer_list_has_accounts_and_guests_with_what_they_bought(client):
    customer, address = new_customer()
    add_to_cart(customer, MID)
    assert checkout(customer, address).status_code == 201
    phone, res = guest_order(client)
    assert res.status_code == 201
    rows = new_admin().get("/api/admin/customers").get_json()
    account = row_of(rows, "Email", customer.get("/api/auth/me").get_json()["email"])
    assert account["IsGuest"] is False and account["OrderCount"] == 1 and account["TotalPaid"] == 0       # the cash order is not paid yet
    assert account["CustomerName"] == "Khách Test" and account["LastOrderAt"]
    guest = row_of(rows, "Phone", phone)
    assert guest["IsGuest"] is True and guest["Email"] is None and guest["CustomerName"] == "Phạm Khách Lẻ"
    assert guest["OrderCount"] == 1 and guest["WarrantyCount"] == 0
    assert not any(r["Email"] == "admin@vinora.vn" for r in rows)      # an admin account is not a customer


def test_customer_total_paid_counts_delivered_cash_orders(client):
    customer_id, card, _ = delivered_order_with_card()
    row = row_of(new_admin().get("/api/admin/customers").get_json(), "CustomerID", customer_id)
    assert row["TotalPaid"] > 0 and row["WarrantyCount"] == 1


def test_admin_order_rows_name_the_customer_id(client):
    customer, address = new_customer()
    add_to_cart(customer, MID)
    code = checkout(customer, address).get_json()["OrderCode"]
    admin = new_admin()
    cid = query("SELECT CustomerID AS c FROM dbo.Orders WHERE OrderCode = ?", (code,))[0]["c"]
    assert admin.get("/api/admin/orders?limit=3").get_json()["items"][0]["CustomerID"] == cid
    assert admin.get(f"/api/admin/orders/{code}").get_json()["customer"]["CustomerID"] == cid


# ---------------- reviews ----------------

def test_review_list_has_the_text_the_label_and_the_aspects(client):
    customer_id, card, _ = delivered_order_with_card()
    order = query("SELECT o.OrderID, o.OrderCode FROM dbo.Orders o JOIN dbo.WarrantyRecords w ON w.OrderID = o.OrderID "
                  "WHERE w.WarrantyCode = ?", (card,))[0]
    with transaction() as cur:
        cur.execute("INSERT INTO dbo.CustomerFeedbacks (OrderID, CustomerID, RatingStar, ReviewText, SentimentLabel, SentimentScore) "
                    "VALUES (?, ?, 2, N'Nhẫn bị trầy, giao trễ', 'Negative', 0.9)", (order["OrderID"], customer_id))
        cur.execute("INSERT INTO dbo.FeedbackAspects (FeedbackID, AspectName, Polarity) "
                    "SELECT FeedbackID, N'Giao hàng', 'Negative' FROM dbo.CustomerFeedbacks WHERE OrderID = ?", (order["OrderID"],))
    rows = new_admin().get("/api/admin/feedbacks").get_json()
    mine = row_of(rows, "OrderCode", order["OrderCode"])
    assert mine["RatingStar"] == 2 and mine["ReviewText"] == "Nhẫn bị trầy, giao trễ" and mine["SentimentLabel"] == "Negative"
    assert mine["IsSentimentSimulated"] is True and mine["CustomerName"] == "Khách Test"
    assert mine["aspects"] == [{"AspectName": "Giao hàng", "Polarity": "Negative"}]
    assert rows[0]["FeedbackID"] >= rows[-1]["FeedbackID"]            # newest first


# ---------------- warranty cards and appointments ----------------

def test_warranty_list_shows_the_card_with_its_owner_and_quota(client):
    customer_id, card, _ = delivered_order_with_card()
    mine = row_of(new_admin().get("/api/admin/warranties").get_json(), "WarrantyCode", card)
    assert mine["Status"] == "Active" and mine["CustomerName"] == "Khách Test"
    assert mine["SKU"] == "NC433-BT-9" and mine["PolishingCountLeft"] >= 0 and mine["CompletedServices"] == 0 and mine["OrderCode"].startswith("VN")


def test_appointment_goes_from_pending_to_completed(client):
    customer_id, card, _ = delivered_order_with_card()
    service = book(card, customer_id, "Resizing", SOON(), new_size=10)
    admin = new_admin()
    row = row_of(admin.get("/api/admin/services").get_json(), "ServiceID", service)
    assert row["Status"] == "Pending" and row["ServiceType"] == "Resizing" and row["NewRingSize"] == 10
    assert row["WarrantyCode"] == card and row["CustomerName"] == "Khách Test" and row["AppointmentDate"] is None

    assert admin.post(f"/api/admin/services/{service}/complete", json={}).status_code == 409           # not confirmed yet
    confirmed = admin.post(f"/api/admin/services/{service}/schedule", json={})                          # the customer's time
    assert confirmed.status_code == 200 and confirmed.get_json()["Status"] == "Confirmed"
    assert confirmed.get_json()["AppointmentDate"]
    done = admin.post(f"/api/admin/services/{service}/complete", json={"resultNote": "  Đã chỉnh size 10  "})
    assert done.status_code == 200
    body = done.get_json()
    assert body["Status"] == "Completed" and body["ResultNote"] == "Đã chỉnh size 10" and body["IsFreeOfCharge"] is True and body["CompletedAt"]
    assert admin.post(f"/api/admin/services/{service}/complete", json={}).status_code == 409           # only once
    assert admin.post(f"/api/admin/services/{service}/cancel").status_code == 409                       # already completed
    card_row = row_of(admin.get("/api/admin/warranties").get_json(), "WarrantyCode", card)
    assert card_row["RingSize"] == 10 and card_row["ResizingCount"] == 1 and card_row["CompletedServices"] == 1


def test_the_shop_can_propose_another_time(client):
    customer_id, card, _ = delivered_order_with_card()
    service = book(card, customer_id, "Cleaning", SOON(3))
    admin = new_admin()
    other = (SOON(5)).replace(microsecond=0).isoformat()
    res = admin.post(f"/api/admin/services/{service}/schedule", json={"appointmentDate": other})
    assert res.status_code == 200 and res.get_json()["Status"] == "Rescheduled"
    assert res.get_json()["AppointmentDate"].startswith(other[:16])
    past = (datetime.datetime.now() - datetime.timedelta(days=1)).isoformat()
    assert admin.post(f"/api/admin/services/{service}/schedule", json={"appointmentDate": past}).status_code == 400   # must be in the future
    assert admin.post(f"/api/admin/services/{service}/schedule", json={"appointmentDate": "tomorrow"}).status_code == 400


def test_the_shop_can_cancel_an_appointment_without_costing_a_turn(client):
    customer_id, card, _ = delivered_order_with_card()
    service = book(card, customer_id, "Polishing", SOON())
    before = row_of(new_admin().get("/api/admin/warranties").get_json(), "WarrantyCode", card)["PolishingCountLeft"]
    res = new_admin().post(f"/api/admin/services/{service}/cancel")
    assert res.status_code == 200 and res.get_json()["Status"] == "Cancelled"
    after = row_of(new_admin().get("/api/admin/warranties").get_json(), "WarrantyCode", card)["PolishingCountLeft"]
    assert before == after
    assert new_admin().post(f"/api/admin/services/{service}/cancel").status_code == 409                 # twice


def test_appointment_requests_that_are_wrong(client):
    admin = new_admin()
    for action in ("schedule", "complete", "cancel"):
        assert admin.post(f"/api/admin/services/999999999/{action}", json={}).status_code == 404
    assert admin.post("/api/admin/services/abc/complete").status_code in (404, 405)                     # not a number: no such route
    customer_id, card, _ = delivered_order_with_card()
    service = book(card, customer_id, "Cleaning", SOON())
    assert admin.post(f"/api/admin/services/{service}/complete", json={"resultNote": "x" * 501}).status_code == 400
    assert admin.post(f"/api/admin/services/{service}/complete", json={"resultNote": 5}).status_code == 400


# ---------------- products ----------------

@pytest.fixture
def fixed_product(client):
    """A fixed price product that no other test uses, put back as it was after the test."""
    row = query("SELECT TOP (1) SKU, Price, OriginalPrice, Status FROM dbo.Products WHERE PricingMethod = 'Fixed' "
                "AND IsQuoteOnly = 0 AND Status = 'Active' ORDER BY ProductID DESC")[0]
    yield row
    with transaction() as cur:
        cur.execute("UPDATE dbo.Products SET Price = ?, OriginalPrice = ?, Status = ? WHERE SKU = ?",
                    (row["Price"], row["OriginalPrice"], row["Status"], row["SKU"]))


def test_product_list_has_every_product_with_the_number_sold(client):
    rows = new_admin().get("/api/admin/products").get_json()
    assert len(rows) == query("SELECT COUNT(*) AS n FROM dbo.Products")[0]["n"] >= 443
    one = rows[0]
    assert {"SKU", "ProductName", "CategoryID", "Material", "PricingMethod", "Price", "OriginalPrice", "IsQuoteOnly", "Status",
            "ImageUrl", "SoldQuantity"} <= one.keys()
    assert any(r["IsQuoteOnly"] for r in rows) and all(isinstance(r["SoldQuantity"], int) for r in rows)
    customer, address = new_customer()
    add_to_cart(customer, SMALL, 2)
    assert checkout(customer, address).status_code == 201
    sku = query("SELECT p.SKU FROM dbo.ProductVariants v JOIN dbo.Products p ON p.ProductID = v.ProductID WHERE v.VariantSKU = ?", (SMALL,))[0]["SKU"]
    after = row_of(new_admin().get("/api/admin/products").get_json(), "SKU", sku)
    assert after["SoldQuantity"] >= 2


def test_admin_changes_price_discount_and_status(fixed_product):
    admin, sku = new_admin(), fixed_product["SKU"]
    res = admin.patch(f"/api/admin/products/{sku}", json={"price": 1500000, "originalPrice": 1800000})
    assert res.status_code == 200 and res.get_json() == {"SKU": sku, "Price": 1500000, "OriginalPrice": 1800000, "Status": "Active"}
    card = new_admin().get(f"/api/products/{sku}").get_json()
    assert card["CurrentPrice"] == 1500000 and card["OriginalPrice"] == 1800000                          # the shop sees it at once
    assert admin.patch(f"/api/admin/products/{sku}", json={"originalPrice": None}).get_json()["OriginalPrice"] is None
    assert admin.patch(f"/api/admin/products/{sku}", json={"status": "Hidden"}).get_json()["Status"] == "Hidden"
    assert admin.get(f"/api/products/{sku}").status_code == 404                                          # hidden from the shop
    assert row_of(admin.get("/api/admin/products").get_json(), "SKU", sku)["Status"] == "Hidden"          # but not from the admin
    assert admin.patch(f"/api/admin/products/{sku}", json={"status": "Active"}).get_json()["Status"] == "Active"


@pytest.mark.parametrize("payload", [
    {}, {"colour": "red"}, {"price": 999}, {"price": "1500000"}, {"price": 1.5}, {"price": True}, {"price": 10 ** 12},
    {"originalPrice": 5}, {"originalPrice": 0}, {"price": 2000000, "originalPrice": 1000000}, {"status": "Gone"}, {"status": None},
])
def test_wrong_product_changes_are_400_and_change_nothing(fixed_product, payload):
    sku = fixed_product["SKU"]
    assert new_admin().patch(f"/api/admin/products/{sku}", json=payload).status_code == 400
    now = query("SELECT Price, OriginalPrice, Status FROM dbo.Products WHERE SKU = ?", (sku,))[0]
    assert now == {k: fixed_product[k] for k in ("Price", "OriginalPrice", "Status")}


def test_gold_rate_products_only_change_status(client):
    sku = query("SELECT TOP (1) SKU FROM dbo.Products WHERE PricingMethod = 'GoldRate' ORDER BY ProductID DESC")[0]["SKU"]
    admin = new_admin()
    assert admin.patch(f"/api/admin/products/{sku}", json={"price": 1500000}).status_code == 409
    assert admin.patch(f"/api/admin/products/{sku}", json={"status": "Active"}).status_code == 200
    assert admin.patch("/api/admin/products/NO-SUCH-SKU", json={"status": "Active"}).status_code == 404
