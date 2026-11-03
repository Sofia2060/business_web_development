"""Tests for the customer side of warranty cards and after-sales appointments (backend/app/routes/warranty.py).
The cards are made by the database when an order is delivered; each test makes its own customer."""
import datetime

import pytest

from app.db import query, transaction
from test_guest_orders import guest_order
from test_orders import MID, SMALL, add_to_cart, checkout, new_admin, new_customer

RING = "NC433-BT-9"            # a ring, so resizing is allowed
STOCKED = (MID, SMALL, RING)
SOON = lambda days=3: (datetime.datetime.now() + datetime.timedelta(days=days)).replace(microsecond=0)   # noqa: E731


@pytest.fixture(autouse=True)
def restock(db_ready):
    """Plenty of stock while a test runs, then put back: other tests rely on the small stock they start with."""
    marks = ", ".join("?" * len(STOCKED))
    before = query(f"SELECT VariantSKU, StockQuantity FROM dbo.ProductVariants WHERE VariantSKU IN ({marks})", STOCKED)
    with transaction() as cur:
        cur.execute(f"UPDATE dbo.ProductVariants SET StockQuantity = 100 WHERE VariantSKU IN ({marks})", STOCKED)
    yield
    with transaction() as cur:
        for row in before:
            cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = ? WHERE VariantSKU = ?", (row["StockQuantity"], row["VariantSKU"]))


def delivered(sku=RING):
    """A customer with one delivered cash order. Returns (client, order code)."""
    client, address = new_customer()
    add_to_cart(client, sku)
    code = checkout(client, address).get_json()["OrderCode"]
    admin = new_admin()
    for status in ("Confirmed", "Shipping"):
        assert admin.post(f"/api/admin/orders/{code}/status", json={"status": status}).status_code == 200
    assert client.post(f"/api/orders/{code}/confirm-received").status_code == 200
    return client, code


def card_of(client):
    (card,) = client.get("/api/warranties").get_json()
    return card


def book(client, card, kind="Cleaning", when=None, **extra):
    body = {"warrantyCode": card["WarrantyCode"], "serviceType": kind, "preferredDate": (when or SOON()).isoformat()}
    body.update(extra)
    return client.post("/api/after-sales", json=body)


# ---------------- who may call ----------------

@pytest.mark.parametrize("method,path", [("get", "/api/warranties"), ("get", "/api/after-sales"),
                                         ("post", "/api/after-sales"), ("post", "/api/after-sales/1/cancel")])
def test_customer_endpoints_need_a_customer(client, method, path):
    assert getattr(client, method)(path).status_code == 401
    assert getattr(new_admin(), method)(path).status_code == 403


# ---------------- cards ----------------

def test_the_card_appears_after_delivery_with_the_product_and_the_quota(client):
    c, address = new_customer()
    add_to_cart(c, RING)
    code = checkout(c, address).get_json()["OrderCode"]
    assert c.get("/api/warranties").get_json() == []                       # not delivered yet
    admin = new_admin()
    for status in ("Confirmed", "Shipping"):
        admin.post(f"/api/admin/orders/{code}/status", json={"status": status})
    assert c.post(f"/api/orders/{code}/confirm-received").status_code == 200
    card = card_of(c)
    assert card["WarrantyCode"].startswith("VNW") and card["OrderCode"] == code and card["Status"] == "Active"
    assert card["VariantSKU"] == RING and card["ProductSKU"] and card["ProductName"] and card["IsRing"] is True
    assert card["PolishingQuota"] == 5 and card["PolishingCountLeft"] == 5 and card["CleaningCount"] == 0 and card["ResizingCount"] == 0
    assert card["CleaningQuota"] is None and card["ResizingQuota"] is None            # no limit
    assert card["RingSize"] == card["PurchasedRingSize"] == 9 and card["CompletedServices"] == 0 and card["IssueDate"]


def test_a_customer_only_sees_their_own_cards(client):
    first, _ = delivered()
    second, _ = delivered()
    assert card_of(first)["WarrantyCode"] != card_of(second)["WarrantyCode"]


def test_the_cards_of_an_order_for_the_owner_and_for_a_guest(client):
    owner, code = delivered()
    assert [c["OrderCode"] for c in owner.get(f"/api/orders/{code}/warranties").get_json()] == [code]
    other, other_code = delivered()
    assert owner.get(f"/api/orders/{other_code}/warranties").status_code == 404           # not my order
    # a guest proves it with the phone of the order
    visitor = client.application.test_client()
    phone, res = guest_order(visitor)
    gcode = res.get_json()["OrderCode"]
    assert visitor.get(f"/api/orders/{gcode}/warranties", query_string={"phone": phone}).get_json() == []      # not delivered yet
    admin = new_admin()
    for status in ("Confirmed", "Shipping"):
        admin.post(f"/api/admin/orders/{gcode}/status", json={"status": status})
    assert visitor.post(f"/api/orders/{gcode}/confirm-received", json={"phone": phone}).status_code == 200
    (card,) = visitor.get(f"/api/orders/{gcode}/warranties", query_string={"phone": phone}).get_json()
    assert card["OrderCode"] == gcode and card["PolishingCountLeft"] == 5
    assert visitor.get(f"/api/orders/{gcode}/warranties", query_string={"phone": "0900000000"}).status_code == 404
    assert visitor.get(f"/api/orders/{gcode}/warranties").status_code == 401


def test_look_up_a_card_by_its_code_shows_the_product_but_not_the_owner(client):
    owner, _ = delivered()
    card = card_of(owner)
    spaced = " ".join([card["WarrantyCode"][:4], card["WarrantyCode"][4:]]).lower()
    found = client.get(f"/api/warranties/{spaced}")
    assert found.status_code == 200
    body = found.get_json()
    assert body["WarrantyCode"] == card["WarrantyCode"] and body["ProductName"] == card["ProductName"] and body["Status"] == "Active"
    assert not {"OrderCode", "CustomerName", "CustomerID", "CustomerPhone"} & body.keys()
    assert client.get("/api/warranties/VNW0000000000-9").status_code == 404


# ---------------- appointments ----------------

def test_book_list_and_cancel_an_appointment(client):
    c, _ = delivered()
    card = card_of(c)
    when = SOON(4)
    res = book(c, card, "Polishing", when, note="Showroom Quận 1. Nhẫn bị xỉn nhẹ")
    assert res.status_code == 201
    row = res.get_json()
    assert row["Status"] == "Pending" and row["ServiceType"] == "Polishing" and row["WarrantyCode"] == card["WarrantyCode"]
    assert row["PreferredDate"].startswith(when.isoformat()[:16]) and row["AppointmentDate"] is None
    assert row["CustomerNote"] == "Showroom Quận 1. Nhẫn bị xỉn nhẹ" and row["ProductName"] == card["ProductName"]
    assert [r["ServiceID"] for r in c.get("/api/after-sales").get_json()] == [row["ServiceID"]]
    cancelled = c.post(f"/api/after-sales/{row['ServiceID']}/cancel")
    assert cancelled.status_code == 200 and cancelled.get_json()["Status"] == "Cancelled"
    assert card_of(c)["PolishingCountLeft"] == 5                           # a cancelled appointment costs no turn
    assert c.post(f"/api/after-sales/{row['ServiceID']}/cancel").status_code == 409        # twice
    assert book(c, card, "Polishing").status_code == 201                    # and a new one can be booked


def test_resizing_needs_a_new_size_and_the_card_code_may_have_spaces(client):
    c, _ = delivered()
    card = card_of(c)
    assert book(c, card, "Resizing").status_code == 400                    # no size
    assert book(c, card, "Cleaning", newRingSize=10).status_code == 400    # a size for another service
    assert book(c, card, "Resizing", newRingSize=9999).status_code == 400
    spaced = " ".join([card["WarrantyCode"][:4], card["WarrantyCode"][4:]]).lower()
    res = c.post("/api/after-sales", json={"warrantyCode": spaced, "serviceType": "Resizing", "newRingSize": 10,
                                           "preferredDate": SOON().isoformat()})
    assert res.status_code == 201 and res.get_json()["NewRingSize"] == 10


def test_wrong_booking_requests(client):
    c, _ = delivered()
    card = card_of(c)
    assert book(c, card, "Dancing").status_code == 400
    assert book(c, card, "Cleaning", when=SOON(-1)).status_code == 400                     # in the past
    assert book(c, card, "Cleaning", when=SOON(400)).status_code == 400                    # more than a year away
    assert book(c, card, "Cleaning", preferredDate="tomorrow").status_code == 400
    assert book(c, card, "Cleaning", preferredDate=5).status_code == 400
    assert book(c, card, "Cleaning", note="x" * 501).status_code == 400
    assert book(c, card, "Cleaning", note=5).status_code == 400
    assert c.post("/api/after-sales", json={}).status_code == 400
    assert c.post("/api/after-sales", json={"warrantyCode": "VNW0000000000-9", "serviceType": "Cleaning",
                                            "preferredDate": SOON().isoformat()}).status_code == 409   # no such card


def test_one_open_appointment_per_type_and_nobody_books_another_customers_card(client):
    c, _ = delivered()
    card = card_of(c)
    assert book(c, card, "Cleaning").status_code == 201
    assert book(c, card, "Cleaning", SOON(5)).status_code == 409           # the same type is still open
    assert book(c, card, "Polishing").status_code == 201                   # another type is fine
    stranger, _ = delivered()
    assert book(stranger, card, "Cleaning").status_code == 409             # not their card
    assert [r["ServiceType"] for r in stranger.get("/api/after-sales").get_json()] == []


def test_a_customer_cannot_cancel_another_customers_appointment(client):
    c, _ = delivered()
    service = book(c, card_of(c), "Cleaning").get_json()["ServiceID"]
    stranger, _ = delivered()
    assert stranger.post(f"/api/after-sales/{service}/cancel").status_code == 409
    assert c.get("/api/after-sales").get_json()[0]["Status"] == "Pending"
    assert stranger.post("/api/after-sales/999999999/cancel").status_code == 409


def test_what_the_customer_books_the_shop_sees_and_the_customer_sees_the_answer(client):
    c, _ = delivered()
    card = card_of(c)
    service = book(c, card, "Polishing", SOON(4), note="Showroom Quận 1").get_json()["ServiceID"]
    admin = new_admin()
    seen = next(s for s in admin.get("/api/admin/services").get_json() if s["ServiceID"] == service)
    assert seen["Status"] == "Pending" and seen["CustomerNote"] == "Showroom Quận 1" and seen["WarrantyCode"] == card["WarrantyCode"]
    assert admin.post(f"/api/admin/services/{service}/schedule", json={}).status_code == 200
    mine = c.get("/api/after-sales").get_json()[0]
    assert mine["Status"] == "Confirmed" and mine["AppointmentDate"]
    other_time = SOON(6).isoformat()
    admin.post(f"/api/admin/services/{service}/schedule", json={"appointmentDate": other_time})
    proposed = c.get("/api/after-sales").get_json()[0]
    assert proposed["Status"] == "Rescheduled" and proposed["AppointmentDate"].startswith(other_time[:16])
    cancelled = c.post(f"/api/after-sales/{service}/cancel")                # the customer can still say no
    assert cancelled.status_code == 200 and cancelled.get_json()["Status"] == "Cancelled"


def test_a_completed_appointment_uses_one_turn_and_cannot_be_cancelled(client):
    c, _ = delivered()
    card = card_of(c)
    service = book(c, card, "Polishing", SOON(4)).get_json()["ServiceID"]
    admin = new_admin()
    assert admin.post(f"/api/admin/services/{service}/schedule", json={}).status_code == 200
    assert admin.post(f"/api/admin/services/{service}/complete", json={"resultNote": "Đã xi mới"}).status_code == 200
    mine = c.get("/api/after-sales").get_json()[0]
    assert mine["Status"] == "Completed" and mine["IsFreeOfCharge"] is True and mine["ResultNote"] == "Đã xi mới" and mine["CompletedAt"]
    assert card_of(c)["PolishingCountLeft"] == 4 and card_of(c)["CompletedServices"] == 1
    assert c.post(f"/api/after-sales/{service}/cancel").status_code == 409
