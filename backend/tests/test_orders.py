"""Integration tests for addresses, cart, orders and the admin order status.
They run on the rebuilt test database. Seed data used (see database/01_*.sql):
  NC433-BT-6..11      silver ring, 1,481,000 VND, engravable, stock 3 each  (under the free-shipping line)
  BT161B-VT           earrings, 2,361,000 VND, not engravable               (over the free-shipping line)
  NDINO131LDIA-VT-11  engagement ring, 25,448,000 VND, engravable, stock 3  (over the 5,000,000 VND online cancel limit)
Rules: shipping is 30,000 VND below 2,000,000 VND of goods, else free. Voucher WELCOME5 gives 5% (rounded to 1,000).
Cancel rule: an order of 5,000,000 VND or less can be cancelled on the website after a reminder popup;
a larger order must be cancelled by phone (an admin cancels it).
Each test uses its own new customer, and orders are never deleted (the database is rebuilt every run)."""
import uuid

import pytest

from app import create_app
from app.db import query, transaction
from conftest import PASSWORD, make_user

CHEAP = "NC433-BT-{}"  # format with a ring size 6..11
MID = "BT161B-VT"
BIG = "NDINO131LDIA-VT-11"


@pytest.fixture(autouse=True)
def restock_mid(db_ready):
    """Many tests buy MID, so give it plenty of stock before each test."""
    with transaction() as cur:
        cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = 100 WHERE VariantSKU = ?", (MID,))


def new_customer(app_client=None, with_address=True):
    """Register a brand new customer (logged in) and give them one address."""
    client = create_app().test_client()
    email = f"ord-{uuid.uuid4().hex[:12]}@example.test"
    res = client.post("/api/auth/register", json={"fullName": "Khách Test", "email": email, "password": PASSWORD})
    assert res.status_code == 201
    address_id = None
    if with_address:
        res = client.post("/api/addresses", json={
            "recipientName": "Khách Test", "phone": "0901234567", "addressLine": "1 Lê Lợi",
            "ward": "Phường Bến Thành", "province": "Thành phố Hồ Chí Minh"})
        assert res.status_code == 201
        address_id = res.get_json()["id"]
    return client, address_id


def new_admin():
    client = create_app().test_client()
    email = f"ord-admin-{uuid.uuid4().hex[:8]}@example.test"
    make_user(email, role="Admin")
    assert client.post("/api/auth/login", json={"email": email, "password": PASSWORD}).status_code == 200
    return client


def add_to_cart(client, sku, quantity=1, **extra):
    return client.post("/api/cart", json={"variantSku": sku, "quantity": quantity, **extra})


def checkout(client, address_id, method="COD", token=None, **extra):
    body = {"addressId": address_id, "paymentMethod": method, "checkoutToken": token or str(uuid.uuid4()), **extra}
    return client.post("/api/orders", json=body)


def stock(sku):
    return query("SELECT StockQuantity FROM dbo.ProductVariants WHERE VariantSKU = ?", (sku,))[0]["StockQuantity"]


def order_status(code):
    return query("SELECT OrderStatus FROM dbo.Orders WHERE OrderCode = ?", (code,))[0]["OrderStatus"]


def place(client, address_id, sku, quantity=1, **extra):
    """Add one item and check out. Returns the response body of the new order."""
    assert add_to_cart(client, sku, quantity).status_code in (200, 201)
    res = checkout(client, address_id, **extra)
    assert res.status_code == 201, res.get_json()
    return res.get_json()


# ---------------- addresses ----------------

def test_first_address_is_default_and_new_default_replaces_it(client):
    c, first = new_customer()
    second = c.post("/api/addresses", json={"recipientName": "B", "phone": "0912345678", "addressLine": "2 Trần Phú",
                                           "ward": "Phường 1", "province": "Thành phố Đà Nẵng"}).get_json()
    assert second["isDefault"] is False
    third = c.post("/api/addresses", json={"recipientName": "C", "phone": "0912345678", "addressLine": "3 Trần Phú",
                                          "ward": "Phường 1", "province": "Thành phố Đà Nẵng", "isDefault": True})
    assert third.get_json()["isDefault"] is True
    listed = c.get("/api/addresses").get_json()
    assert len(listed) == 3
    assert [a["IsDefault"] for a in listed].count(True) == 1 and listed[0]["AddressID"] == third.get_json()["id"]


@pytest.mark.parametrize("bad", [{"phone": "12ab"}, {"recipientName": ""}, {"province": None}, {"ward": "x" * 101},
                                 {"isDefault": "yes"}, {"addressLine": 5}])
def test_address_validation(client, bad):
    c, _ = new_customer(with_address=False)
    body = {"recipientName": "A", "phone": "0901234567", "addressLine": "1 Lê Lợi", "ward": "P1", "province": "HCM"}
    body.update(bad)
    assert c.post("/api/addresses", json=body).status_code == 400


def test_addresses_are_private(client):
    a, _ = new_customer()
    b, _ = new_customer(with_address=False)
    assert b.get("/api/addresses").get_json() == []
    assert len(a.get("/api/addresses").get_json()) == 1


# ---------------- access rules ----------------

@pytest.mark.parametrize("method,path", [("get", "/api/cart"), ("post", "/api/cart"), ("get", "/api/orders"),
                                         ("post", "/api/orders"), ("get", "/api/addresses"),
                                         ("post", "/api/orders/X/cancel"), ("post", "/api/orders/X/confirm-received")])
def test_customer_endpoints_need_login(client, method, path):
    assert getattr(client, method)(path).status_code == 401


def test_admin_account_cannot_use_customer_endpoints(client):
    assert new_admin().get("/api/cart").status_code == 403


def test_customer_cannot_use_admin_order_endpoints(client):
    c, _ = new_customer()
    assert c.get("/api/admin/orders").status_code == 403
    assert c.post("/api/admin/orders/X/status", json={"status": "Confirmed"}).status_code == 403


# ---------------- cart ----------------

def test_cart_add_total_and_shipping_rule(client):
    c, _ = new_customer()
    assert add_to_cart(c, CHEAP.format(6), 2).status_code == 201
    cart = c.get("/api/cart").get_json()
    assert cart["subtotal"] == 2 * 1481000 and cart["shippingFee"] == 0 and cart["total"] == 2962000  # >= 2M: free
    c2, _ = new_customer()
    add_to_cart(c2, CHEAP.format(6), 1)
    cart = c2.get("/api/cart").get_json()
    assert cart["subtotal"] == 1481000 and cart["shippingFee"] == 30000 and cart["total"] == 1511000


def test_cart_empty(client):
    c, _ = new_customer()
    assert c.get("/api/cart").get_json() == {"items": [], "subtotal": 0, "shippingFee": 0, "total": 0}


def test_cart_same_variant_adds_up_but_engraving_makes_a_new_line(client):
    c, _ = new_customer()
    assert add_to_cart(c, CHEAP.format(7)).status_code == 201
    res = add_to_cart(c, CHEAP.format(7))
    assert res.status_code == 200 and res.get_json()["quantity"] == 2
    assert add_to_cart(c, CHEAP.format(7), engravingText="Forever").status_code == 201
    assert len(c.get("/api/cart").get_json()["items"]) == 2


@pytest.mark.parametrize("payload,status", [
    ({"variantSku": "NO-SUCH-SKU"}, 404),
    ({"variantSku": CHEAP.format(8), "quantity": 0}, 400),
    ({"variantSku": CHEAP.format(8), "quantity": 11}, 400),
    ({"variantSku": CHEAP.format(8), "quantity": True}, 400),
    ({"variantSku": CHEAP.format(8), "quantity": "2"}, 400),
    ({"variantSku": CHEAP.format(8), "quantity": 4}, 409),               # stock is 3
    ({"variantSku": MID, "engravingText": "Love"}, 400),                 # not engravable
    ({"variantSku": CHEAP.format(8), "engravingText": "x" * 31}, 400),
    ({"variantSku": 123}, 400),
    ({}, 400),
])
def test_cart_add_validation(client, payload, status):
    c, _ = new_customer()
    assert c.post("/api/cart", json=payload).status_code == status


def test_cart_change_and_remove(client):
    c, _ = new_customer()
    item = add_to_cart(c, CHEAP.format(9)).get_json()["id"]
    assert c.patch(f"/api/cart/{item}", json={"quantity": 3}).status_code == 200
    assert c.get("/api/cart").get_json()["items"][0]["Quantity"] == 3
    assert c.patch(f"/api/cart/{item}", json={"quantity": 4}).status_code == 409
    assert c.patch(f"/api/cart/{item}", json={"quantity": 0}).status_code == 400
    assert c.delete(f"/api/cart/{item}").status_code == 204
    assert c.delete(f"/api/cart/{item}").status_code == 404
    assert c.get("/api/cart").get_json()["items"] == []


def test_cart_items_of_other_customers_are_hidden(client):
    a, _ = new_customer()
    b, _ = new_customer()
    item = add_to_cart(a, CHEAP.format(9)).get_json()["id"]
    assert b.patch(f"/api/cart/{item}", json={"quantity": 2}).status_code == 404
    assert b.delete(f"/api/cart/{item}").status_code == 404
    assert len(a.get("/api/cart").get_json()["items"]) == 1


# ---------------- placing an order ----------------

def test_place_order_basic(client):
    c, addr = new_customer()
    before = stock(CHEAP.format(10))
    order = place(c, addr, CHEAP.format(10))
    assert order["OrderCode"].startswith("VN")
    assert order["ShippingFee"] == 30000 and order["TotalAmount"] == 1481000 + 30000
    assert stock(CHEAP.format(10)) == before - 1
    assert c.get("/api/cart").get_json()["items"] == []        # cart is emptied
    assert order_status(order["OrderCode"]) == "Pending"
    detail = c.get(f"/api/orders/{order['OrderCode']}").get_json()
    assert detail["items"][0]["Quantity"] == 1 and detail["items"][0]["UnitPrice"] == 1481000
    assert detail["payments"][0]["PaymentMethod"] == "COD" and detail["payments"][0]["Status"] == "Pending"
    assert detail["ShipAddress"].startswith("1 Lê Lợi")


def test_place_order_free_shipping_and_voucher(client):
    c, addr = new_customer()
    add_to_cart(c, MID)
    res = checkout(c, addr, "VNPay", voucherCode="WELCOME5")
    assert res.status_code == 201
    order = res.get_json()
    assert order["ShippingFee"] == 0
    assert order["TotalAmount"] == 2361000 - 118000           # 5% of 2,361,000 = 118,050, rounded to 118,000
    detail = c.get(f"/api/orders/{order['OrderCode']}").get_json()
    assert detail["DiscountAmount"] == 118000 and detail["payments"][0]["Amount"] == order["TotalAmount"]


def test_same_checkout_token_gives_the_same_order_once(client):
    c, addr = new_customer()
    before = stock(CHEAP.format(11))
    add_to_cart(c, CHEAP.format(11))
    token = str(uuid.uuid4())
    first = checkout(c, addr, token=token)
    second = checkout(c, addr, token=token)
    assert first.status_code == 201 and second.status_code == 200
    assert first.get_json() == second.get_json()      # same keys and same values on a retry
    assert stock(CHEAP.format(11)) == before - 1
    assert len(c.get("/api/orders").get_json()) == 1


def test_checkout_token_of_another_customer_is_refused(client):
    a, addr_a = new_customer()
    token = str(uuid.uuid4())
    place(a, addr_a, MID, token=token)
    b, addr_b = new_customer()
    add_to_cart(b, MID)
    assert checkout(b, addr_b, token=token).status_code == 409


@pytest.mark.parametrize("extra", [{"paymentMethod": "Bitcoin"}, {"checkoutToken": "not-a-uuid"}, {"addressId": "1"},
                                   {"addressId": 0}, {"voucherCode": 5}, {"note": "x" * 501}])
def test_checkout_validation(client, extra):
    c, addr = new_customer()
    add_to_cart(c, MID)
    body = {"addressId": addr, "paymentMethod": "COD", "checkoutToken": str(uuid.uuid4())}
    body.update(extra)
    assert c.post("/api/orders", json=body).status_code == 400


def test_checkout_rules_from_the_database(client):
    c, addr = new_customer()
    assert checkout(c, addr).status_code == 400                       # empty cart
    other, other_addr = new_customer()
    add_to_cart(c, MID)
    assert checkout(c, other_addr).status_code == 400                 # address belongs to someone else
    assert checkout(c, addr, voucherCode="NOPE").status_code == 400   # unknown voucher
    assert checkout(c, addr, voucherCode="VINORA500K").status_code == 400  # needs 10M of goods


def test_not_enough_stock_is_409_and_nothing_is_created(client):
    a, addr_a = new_customer()
    b, addr_b = new_customer()
    add_to_cart(a, CHEAP.format(8), 3)
    add_to_cart(b, CHEAP.format(8), 3)
    assert checkout(a, addr_a).status_code == 201
    res = checkout(b, addr_b)
    assert res.status_code == 409 and "tồn kho" in res.get_json()["error"]
    assert b.get("/api/orders").get_json() == []
    assert len(b.get("/api/cart").get_json()["items"]) == 1           # cart is kept


def test_orders_are_private(client):
    a, addr_a = new_customer()
    code = place(a, addr_a, MID)["OrderCode"]
    b, _ = new_customer()
    assert b.get(f"/api/orders/{code}").status_code == 404
    assert b.post(f"/api/orders/{code}/cancel").status_code == 404
    assert b.post(f"/api/orders/{code}/confirm-received").status_code == 404
    assert b.get("/api/orders").get_json() == []
    assert [o["OrderCode"] for o in a.get("/api/orders").get_json()] == [code]


# ---------------- cancelling ----------------

def test_cancel_request_only_asks_and_a_confirmed_cancel_returns_stock(client):
    c, addr = new_customer()
    sku = CHEAP.format(6)
    before = stock(sku)
    code = place(c, addr, sku)["OrderCode"]
    res = c.post(f"/api/orders/{code}/cancel", json={"reason": "Đổi ý"})
    assert res.status_code == 200
    popup = res.get_json()
    assert popup["RequestID"] and popup["VoucherCode"] is None and popup["VoucherDiscount"] == 0
    assert order_status(code) == "Pending" and stock(sku) == before - 1      # nothing is cancelled yet
    done = c.post(f"/api/orders/{code}/cancel/respond", json={"keepOrder": False}).get_json()
    assert done["OrderStatus"] == "Cancelled" and stock(sku) == before


def test_popup_names_the_voucher_the_customer_would_lose(client):
    c, addr = new_customer()
    add_to_cart(c, MID)
    code = checkout(c, addr, voucherCode="WELCOME5").get_json()["OrderCode"]
    popup = c.post(f"/api/orders/{code}/cancel", json={}).get_json()
    assert popup["VoucherCode"] == "WELCOME5" and popup["VoucherDiscount"] == 118000
    detail = c.get(f"/api/orders/{code}").get_json()        # the page can show the popup again after a reload
    assert detail["pendingCancelRequest"] == {"RequestID": popup["RequestID"], "VoucherCode": "WELCOME5",
                                              "VoucherDiscount": 118000}


def test_keeping_the_order_changes_nothing_about_the_money(client):
    c, addr = new_customer()
    before = stock(MID)
    add_to_cart(c, MID)
    order = checkout(c, addr, voucherCode="WELCOME5").get_json()
    code = order["OrderCode"]
    c.post(f"/api/orders/{code}/cancel", json={})
    done = c.post(f"/api/orders/{code}/cancel/respond", json={"keepOrder": True}).get_json()
    assert done["OrderStatus"] == "Pending" and done["TotalAmount"] == order["TotalAmount"]
    assert done["IsRetentionApplied"] is True
    assert stock(MID) == before - 1
    assert c.get(f"/api/orders/{code}").get_json()["pendingCancelRequest"] is None
    # the customer may press cancel again later and gets a new popup
    assert c.post(f"/api/orders/{code}/cancel", json={}).status_code == 200


def test_pressing_cancel_twice_gives_the_same_request(client):
    c, addr = new_customer()
    code = place(c, addr, CHEAP.format(7))["OrderCode"]
    first = c.post(f"/api/orders/{code}/cancel", json={}).get_json()
    second = c.post(f"/api/orders/{code}/cancel", json={}).get_json()
    assert first["RequestID"] == second["RequestID"]


def test_order_over_5_million_cannot_be_cancelled_on_the_website(client):
    c, addr = new_customer()
    code = place(c, addr, BIG)["OrderCode"]
    res = c.post(f"/api/orders/{code}/cancel", json={})
    assert res.status_code == 403 and "hotline" in res.get_json()["error"]
    assert order_status(code) == "Pending"
    assert c.get("/api/orders").get_json()[0]["CancelChannel"] == "Hotline"
    # an admin can still cancel it, as if the customer called
    admin = new_admin()
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Cancelled"}).status_code == 200
    assert order_status(code) == "Cancelled"


def test_cancel_channel_in_the_order_list(client):
    c, addr = new_customer()
    code = place(c, addr, MID)["OrderCode"]
    assert c.get("/api/orders").get_json()[0]["CancelChannel"] == "Web"
    admin = new_admin()
    for status in ("Confirmed", "Shipping"):
        admin.post(f"/api/admin/orders/{code}/status", json={"status": status})
    assert c.get("/api/orders").get_json()[0]["CancelChannel"] is None       # shipping: no longer cancellable


def test_answer_without_a_waiting_request_is_409_and_bad_body_is_400(client):
    c, addr = new_customer()
    code = place(c, addr, MID)["OrderCode"]
    assert c.post(f"/api/orders/{code}/cancel/respond", json={"keepOrder": True}).status_code == 409
    c.post(f"/api/orders/{code}/cancel", json={})
    assert c.post(f"/api/orders/{code}/cancel/respond", json={"keepOrder": "yes"}).status_code == 400
    assert c.post(f"/api/orders/{code}/cancel/respond", json={}).status_code == 400


def test_cannot_cancel_a_shipping_order_or_cancel_twice(client):
    c, addr = new_customer()
    code = place(c, addr, CHEAP.format(7))["OrderCode"]
    c.post(f"/api/orders/{code}/cancel", json={})
    c.post(f"/api/orders/{code}/cancel/respond", json={"keepOrder": False})
    assert c.post(f"/api/orders/{code}/cancel", json={}).status_code == 409       # already cancelled
    other, other_addr = new_customer()
    shipped = place(other, other_addr, MID)["OrderCode"]
    admin = new_admin()
    for status in ("Confirmed", "Shipping"):
        admin.post(f"/api/admin/orders/{shipped}/status", json={"status": status})
    assert other.post(f"/api/orders/{shipped}/cancel", json={}).status_code == 409


# ---------------- admin status and delivery ----------------

def test_admin_moves_order_forward_and_customer_confirms_receipt(client):
    c, addr = new_customer()
    code = place(c, addr, CHEAP.format(10), quantity=1)["OrderCode"]
    admin = new_admin()
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"}).get_json()["OrderStatus"] == "Confirmed"
    assert c.post(f"/api/orders/{code}/confirm-received").status_code == 409     # not shipped yet
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Shipping"}).get_json()["OrderStatus"] == "Shipping"
    res = c.post(f"/api/orders/{code}/confirm-received")
    assert res.status_code == 200 and res.get_json()["OrderStatus"] == "Delivered"
    # delivery creates one warranty card per unit, and a COD payment is marked paid
    cards = query("SELECT COUNT(*) AS n FROM dbo.WarrantyRecords w JOIN dbo.Orders o ON o.OrderID = w.OrderID "
                  "WHERE o.OrderCode = ?", (code,))[0]["n"]
    assert cards == 1
    assert c.get(f"/api/orders/{code}").get_json()["payments"][0]["Status"] == "Success"


def test_two_units_make_two_warranty_cards(client):
    c, addr = new_customer()
    code = place(c, addr, MID, quantity=2)["OrderCode"]
    admin = new_admin()
    for status in ("Confirmed", "Shipping", "Delivered"):
        assert admin.post(f"/api/admin/orders/{code}/status", json={"status": status}).status_code == 200
    assert query("SELECT COUNT(*) AS n FROM dbo.WarrantyRecords w JOIN dbo.Orders o ON o.OrderID = w.OrderID "
                 "WHERE o.OrderCode = ?", (code,))[0]["n"] == 2


def test_admin_cannot_skip_steps_or_change_finished_orders(client):
    c, addr = new_customer()
    code = place(c, addr, MID)["OrderCode"]
    admin = new_admin()
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Delivered"}).status_code == 409
    assert order_status(code) == "Pending"
    admin.post(f"/api/admin/orders/{code}/status", json={"status": "Cancelled", "reason": "Hết hàng"})
    assert order_status(code) == "Cancelled"
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"}).status_code == 409


@pytest.mark.parametrize("payload", [{"status": "Pending"}, {"status": "Done"}, {"status": 5}, {},
                                     {"status": "Confirmed", "reason": 5}])
def test_admin_status_validation(client, payload):
    c, addr = new_customer()
    code = place(c, addr, MID)["OrderCode"]
    assert new_admin().post(f"/api/admin/orders/{code}/status", json=payload).status_code == 400


def test_admin_status_unknown_order_is_404(client):
    assert new_admin().post("/api/admin/orders/VN000000000/status", json={"status": "Confirmed"}).status_code == 404


def test_admin_order_list_filters_and_pages(client):
    c, addr = new_customer()
    code = place(c, addr, MID)["OrderCode"]
    admin = new_admin()
    everything = admin.get("/api/admin/orders?limit=100").get_json()
    assert everything["total"] >= 4 and len(everything["items"]) == min(100, everything["total"])
    assert everything["items"][0]["OrderCode"] == code            # newest first
    assert {"CustomerName", "CustomerEmail", "TotalAmount"} <= everything["items"][0].keys()
    pending = admin.get("/api/admin/orders?status=Pending").get_json()
    assert all(o["OrderStatus"] == "Pending" for o in pending["items"])
    for bad in ("status=Nope", "page=0", "limit=0", "limit=101", "page=x"):
        assert admin.get(f"/api/admin/orders?{bad}").status_code == 400


# ---------------- cases found in code review ----------------

def test_address_id_above_int_range_is_400(client):
    c, _ = new_customer()
    add_to_cart(c, MID)
    assert checkout(c, 3_000_000_000).status_code == 400


def test_full_address_longer_than_400_is_refused(client):
    c, _ = new_customer(with_address=False)
    body = {"recipientName": "A", "phone": "0901234567", "addressLine": "a" * 255, "ward": "w" * 100, "province": "p" * 100}
    assert c.post("/api/addresses", json=body).status_code == 400          # 459 with separators
    body.update(addressLine="a" * 190)
    assert c.post("/api/addresses", json=body).status_code == 201          # 394 with separators


@pytest.mark.parametrize("first,similar", [("Mại", "Mai"), ("ABC", "abc")])
def test_similar_engraving_text_is_not_merged_into_one_line(client, first, similar):
    # The database ignores case and tone marks when it compares text, so these pairs count as equal there.
    c, _ = new_customer()
    assert add_to_cart(c, CHEAP.format(6), engravingText=first).status_code == 201
    assert add_to_cart(c, CHEAP.format(6), engravingText=similar).status_code == 409
    assert add_to_cart(c, CHEAP.format(6), engravingText=first).status_code == 200   # exact same text adds up
    items = c.get("/api/cart").get_json()["items"]
    assert len(items) == 1 and items[0]["EngravingText"] == first and items[0]["Quantity"] == 2


def test_engraving_with_a_different_letter_is_a_separate_line(client):
    c, _ = new_customer()
    add_to_cart(c, CHEAP.format(6), engravingText="Năm")
    assert add_to_cart(c, CHEAP.format(6), engravingText="Nam").status_code == 201   # ă and a are different letters
    assert len(c.get("/api/cart").get_json()["items"]) == 2


def test_admin_cannot_set_the_same_status_twice(client):
    c, addr = new_customer()
    code = place(c, addr, MID)["OrderCode"]
    admin = new_admin()
    first = admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"}).get_json()
    again = admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"})
    assert again.status_code == 409
    after = query("SELECT ConfirmedAt FROM dbo.Orders WHERE OrderCode = ?", (code,))[0]["ConfirmedAt"]
    assert after == first["ConfirmedAt"]                                   # the original date is kept


@pytest.mark.parametrize("qs", ["page=%C2%B2", "page=99999999999999999999", "limit=%C2%B2", "page=-1", "page=1.5"])
def test_odd_page_numbers_are_400_not_500(client, qs):
    assert new_admin().get(f"/api/admin/orders?{qs}").status_code == 400
    assert client.get(f"/api/products?{qs}").status_code == 400


def test_admin_cancel_closes_a_waiting_cancel_request(client):
    c, addr = new_customer()
    code = place(c, addr, MID)["OrderCode"]
    c.post(f"/api/orders/{code}/cancel", json={})                          # popup is waiting
    assert c.get(f"/api/orders/{code}").get_json()["pendingCancelRequest"] is not None
    new_admin().post(f"/api/admin/orders/{code}/status", json={"status": "Cancelled"})
    detail = c.get(f"/api/orders/{code}").get_json()
    assert detail["OrderStatus"] == "Cancelled" and detail["pendingCancelRequest"] is None
    status = query("SELECT r.Decision FROM dbo.OrderCancellationRequests r JOIN dbo.Orders o ON o.OrderID = r.OrderID "
                   "WHERE o.OrderCode = ?", (code,))[0]["Decision"]
    assert status == "Closed"


def test_deeply_nested_json_gives_400_not_500(client):
    deep = "[" * 8000 + "]" * 8000
    res = client.post("/api/auth/register", data=deep, content_type="application/json")
    assert res.status_code == 400
