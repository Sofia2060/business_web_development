"""Tests for ordering without an account (a guest), where the phone number is the customer id:
checkout, looking up and cancelling with the phone, and linking the old orders when the guest registers.
Products used (see test_orders.py): SMALL 139,000 VND, DEAL 2,198,000 VND (voucher GIAM300K takes off 300,000),
CHEAP size 11 is a ring that can be engraved."""
import uuid

import pytest

from app import create_app
from app.db import query, transaction
from conftest import PASSWORD
from test_orders import CHEAP, DEAL, SMALL, add_to_cart, new_admin, new_customer, stock

RING = CHEAP.format(11)
OTP = "123456"


@pytest.fixture(autouse=True)
def restock(db_ready):
    with transaction() as cur:
        cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = 100 WHERE VariantSKU IN (?, ?, ?)", (SMALL, DEAL, RING))


def unique_phone():
    return "09" + str(uuid.uuid4().int)[:8]


def guest_body(phone, items=None, **extra):
    body = {"fullName": "Phạm Khách Lẻ", "phone": phone, "addressLine": "7 Lê Lợi", "ward": "Phường Bến Thành",
            "province": "Thành phố Hồ Chí Minh", "items": [{"variantSku": SMALL, "quantity": 1}] if items is None else items,
            "paymentMethod": "COD", "checkoutToken": str(uuid.uuid4())}
    body.update(extra)
    return body


def guest_order(client, phone=None, items=None, **extra):
    phone = phone or unique_phone()
    res = client.post("/api/orders/guest", json=guest_body(phone, items, **extra))
    return phone, res


def customer_row(phone):
    rows = query("SELECT CustomerID, UserID FROM dbo.Customers WHERE Phone = ?", (phone,))
    return rows[0] if rows else None


def count(sql, params):
    return query(sql, params)[0]["n"]


# ---------------- checkout ----------------

def test_guest_places_an_order_with_only_a_phone_number(client):
    before = stock(SMALL)
    phone, res = guest_order(client)
    assert res.status_code == 201
    order = res.get_json()
    assert order["TotalAmount"] == 139000 + 30000 and order["ShippingFee"] == 30000
    customer = customer_row(phone)
    assert customer["UserID"] is None                                   # a guest has no account
    row = query("SELECT ShipRecipientName, ShipPhone, ShipAddress, OrderStatus FROM dbo.Orders WHERE OrderCode = ?",
                (order["OrderCode"],))[0]
    assert row == {"ShipRecipientName": "Phạm Khách Lẻ", "ShipPhone": phone, "OrderStatus": "Pending",
                   "ShipAddress": "7 Lê Lợi, Phường Bến Thành, Thành phố Hồ Chí Minh"}
    assert stock(SMALL) == before - 1
    assert count("SELECT COUNT(*) AS n FROM dbo.CartItems WHERE CustomerID = ?", (customer["CustomerID"],)) == 0
    assert count("SELECT COUNT(*) AS n FROM dbo.CustomerAddresses WHERE CustomerID = ? AND IsDefault = 1",
                 (customer["CustomerID"],)) == 1


def test_phone_is_stored_in_one_spelling(client):
    phone = unique_phone()
    _, first = guest_order(client, "+84" + phone[1:])
    _, second = guest_order(client, phone)
    assert first.status_code == second.status_code == 201
    assert count("SELECT COUNT(*) AS n FROM dbo.Customers WHERE Phone = ?", (phone,)) == 1
    assert count("SELECT COUNT(*) AS n FROM dbo.Orders o JOIN dbo.Customers c ON c.CustomerID = o.CustomerID "
                 "WHERE c.Phone = ?", (phone,)) == 2


def test_same_checkout_token_gives_the_same_order_and_takes_stock_once(client):
    phone = unique_phone()
    token = str(uuid.uuid4())
    before = stock(SMALL)
    _, first = guest_order(client, phone, checkoutToken=token)
    _, again = guest_order(client, phone, checkoutToken=token)
    assert (first.status_code, again.status_code) == (201, 200) and first.get_json() == again.get_json()
    assert stock(SMALL) == before - 1
    # a token that already made an order for another customer is refused
    _, stolen = guest_order(client, checkoutToken=token)
    assert stolen.status_code == 409


def test_same_address_is_kept_once_and_a_new_one_is_added(client):
    phone = unique_phone()
    guest_order(client, phone)
    guest_order(client, phone)
    cid = customer_row(phone)["CustomerID"]
    assert count("SELECT COUNT(*) AS n FROM dbo.CustomerAddresses WHERE CustomerID = ?", (cid,)) == 1
    guest_order(client, phone, addressLine="9 Trần Phú")
    assert count("SELECT COUNT(*) AS n FROM dbo.CustomerAddresses WHERE CustomerID = ?", (cid,)) == 2
    assert count("SELECT COUNT(*) AS n FROM dbo.CustomerAddresses WHERE CustomerID = ? AND IsDefault = 1", (cid,)) == 1


def test_guest_can_use_a_voucher_and_several_lines(client):
    used = query("SELECT UsedCount FROM dbo.Vouchers WHERE VoucherCode = 'GIAM300K'")[0]["UsedCount"]
    items = [{"variantSku": DEAL, "quantity": 1}, {"variantSku": RING, "quantity": 2, "engravingText": "Love"}]
    _, res = guest_order(client, items=items, voucherCode="GIAM300K")
    assert res.status_code == 201
    row = query("SELECT Subtotal, DiscountAmount, ShippingFee FROM dbo.Orders WHERE OrderCode = ?",
                (res.get_json()["OrderCode"],))[0]
    assert row == {"Subtotal": 2198000 + 2 * 1481000, "DiscountAmount": 300000, "ShippingFee": 0}
    assert query("SELECT UsedCount FROM dbo.Vouchers WHERE VoucherCode = 'GIAM300K'")[0]["UsedCount"] == used + 1
    engraved = query("SELECT EngravingText FROM dbo.OrderItems oi JOIN dbo.Orders o ON o.OrderID = oi.OrderID "
                     "WHERE o.OrderCode = ? AND oi.EngravingText IS NOT NULL", (res.get_json()["OrderCode"],))
    assert [r["EngravingText"] for r in engraved] == ["Love"]


def test_a_phone_that_has_an_account_must_log_in(client):
    phone = unique_phone()
    owner = create_app().test_client()
    assert owner.post("/api/auth/register", json={"fullName": "A", "email": f"g-{uuid.uuid4().hex[:8]}@example.test",
                                                  "password": PASSWORD, "phone": phone}).status_code == 201
    _, res = guest_order(client, phone)
    assert res.status_code == 409 and res.get_json()["reason"] == "phone_has_account"
    assert count("SELECT COUNT(*) AS n FROM dbo.Orders o JOIN dbo.Customers c ON c.CustomerID = o.CustomerID "
                 "WHERE c.Phone = ?", (phone,)) == 0


@pytest.mark.parametrize("change", [
    {"items": []}, {"items": "x"}, {"items": [5]}, {"items": [{"variantSku": SMALL}] * 21},
    {"items": [{"variantSku": SMALL, "quantity": 0}]}, {"items": [{"variantSku": SMALL, "quantity": 11}]},
    {"items": [{"variantSku": SMALL, "quantity": "2"}]}, {"items": [{"quantity": 1}]},
    {"items": [{"variantSku": SMALL, "engravingText": "x"}]},                # not engravable
    {"items": [{"variantSku": RING, "engravingText": "x" * 16}]},
    {"items": [{"variantSku": RING, "engravingText": "Love", "engravingStyle": "Gothic"}]},
    {"items": [{"variantSku": RING, "engravingText": "Love", "engravingStyle": 5}]},
    {"fullName": ""}, {"fullName": None}, {"fullName": 5}, {"phone": "12ab"}, {"phone": ""}, {"phone": None},
    {"addressLine": ""}, {"ward": "w" * 101}, {"province": 5},
    {"paymentMethod": "Bitcoin"}, {"paymentMethod": None}, {"checkoutToken": "nope"}, {"checkoutToken": None},
    {"voucherCode": 5}, {"note": "n" * 501}, {"voucherCode": "V" * 31},
])
def test_guest_checkout_validation(client, change):
    phone = unique_phone()
    body = guest_body(phone)
    body.update(change)
    res = client.post("/api/orders/guest", json=body)
    assert res.status_code == 400, res.get_json()
    assert count("SELECT COUNT(*) AS n FROM dbo.Orders o JOIN dbo.Customers c ON c.CustomerID = o.CustomerID "
                 "WHERE c.Phone = ?", (phone,)) == 0


def test_a_bad_line_names_its_number_and_leaves_nothing_behind(client):
    phone = unique_phone()
    items = [{"variantSku": SMALL, "quantity": 1}, {"variantSku": "NO-SUCH-SKU", "quantity": 1}]
    res = client.post("/api/orders/guest", json=guest_body(phone, items))
    assert res.status_code == 404 and res.get_json()["error"].startswith("Item 2:")
    assert customer_row(phone) is None      # the failed attempt created no guest customer, address or cart


def test_a_failed_order_of_a_known_guest_removes_only_what_it_added(client):
    phone, first = guest_order(client)
    cid = customer_row(phone)["CustomerID"]
    bad = client.post("/api/orders/guest", json=guest_body(phone, [{"variantSku": "NO-SUCH-SKU"}], addressLine="Another street"))
    assert bad.status_code == 404
    assert customer_row(phone)["CustomerID"] == cid
    assert count("SELECT COUNT(*) AS n FROM dbo.CustomerAddresses WHERE CustomerID = ?", (cid,)) == 1   # the new address is gone
    assert count("SELECT COUNT(*) AS n FROM dbo.Orders WHERE CustomerID = ?", (cid,)) == 1
    assert count("SELECT COUNT(*) AS n FROM dbo.CartItems WHERE CustomerID = ?", (cid,)) == 0


def test_an_address_that_differs_only_by_tone_marks_is_a_new_address(client):
    phone, _ = guest_order(client, addressLine="12 Hà Long")
    guest_order(client, phone, addressLine="12 Hạ Long")      # the database alone would treat these as equal
    cid = customer_row(phone)["CustomerID"]
    assert count("SELECT COUNT(*) AS n FROM dbo.CustomerAddresses WHERE CustomerID = ?", (cid,)) == 2
    shipped = query("SELECT TOP (1) ShipAddress FROM dbo.Orders WHERE CustomerID = ? ORDER BY OrderID DESC", (cid,))[0]
    assert shipped["ShipAddress"].startswith("12 Hạ Long")


def test_orders_for_the_same_phone_at_the_same_moment_do_not_mix_their_carts(client):
    # Two checkouts share one temporary cart, so without a lock they could add up or empty each other.
    import threading
    phone = unique_phone()
    guest_order(client, phone)                                   # the guest exists already
    results = []

    def go(token):
        res = create_app().test_client().post("/api/orders/guest", json=guest_body(phone, checkoutToken=token))
        results.append((res.status_code, res.get_json()))

    tokens = [str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())]
    threads = [threading.Thread(target=go, args=(t,)) for t in tokens]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert sorted(code for code, _ in results) == [201, 201, 201], results
    cid = customer_row(phone)["CustomerID"]
    quantities = query("SELECT oi.Quantity FROM dbo.OrderItems oi JOIN dbo.Orders o ON o.OrderID = oi.OrderID "
                       "WHERE o.CustomerID = ?", (cid,))
    assert len(quantities) == 4 and {q["Quantity"] for q in quantities} == {1}      # four orders, one item each
    assert count("SELECT COUNT(*) AS n FROM dbo.CartItems WHERE CustomerID = ?", (cid,)) == 0


def test_double_click_with_the_same_token_makes_one_order_of_one_item(client):
    import threading
    phone, token = unique_phone(), str(uuid.uuid4())
    results = []

    def go():
        res = create_app().test_client().post("/api/orders/guest", json=guest_body(phone, checkoutToken=token))
        results.append((res.status_code, res.get_json()["OrderCode"]))

    threads = [threading.Thread(target=go) for _ in range(4)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert sorted(code for code, _ in results) == [200, 200, 200, 201] and len({c for _, c in results}) == 1
    cid = customer_row(phone)["CustomerID"]
    assert query("SELECT SUM(oi.Quantity) AS q FROM dbo.OrderItems oi JOIN dbo.Orders o ON o.OrderID = oi.OrderID "
                 "WHERE o.CustomerID = ?", (cid,))[0]["q"] == 1
    assert count("SELECT COUNT(*) AS n FROM dbo.CartItems WHERE CustomerID = ?", (cid,)) == 0


def test_not_enough_stock_and_bad_voucher_are_clean_errors(client):
    with transaction() as cur:
        cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = 1 WHERE VariantSKU = ?", (RING,))
    _, res = guest_order(client, items=[{"variantSku": RING, "quantity": 2}])
    assert res.status_code == 409 and "Not enough stock" in res.get_json()["error"]
    phone, bad = guest_order(client, voucherCode="NO-SUCH-VOUCHER")
    assert bad.status_code == 400 and bad.get_json()["code"] == 50016
    assert customer_row(phone) is None          # a failed first order leaves no guest customer, address or cart behind


def test_guest_orders_do_not_appear_in_the_logged_in_order_list(client):
    guest_order(client)
    assert client.get("/api/orders").status_code == 401


# ---------------- looking up, cancelling and receiving with the phone ----------------

def test_guest_looks_up_an_order_with_code_and_phone(client):
    phone, res = guest_order(client)
    code = res.get_json()["OrderCode"]
    detail = client.get(f"/api/orders/{code}", query_string={"phone": phone})
    assert detail.status_code == 200 and detail.get_json()["OrderCode"] == code
    assert detail.get_json()["items"][0]["SKUSnap"] == SMALL
    assert client.get(f"/api/orders/{code}", query_string={"phone": "+84" + phone[1:]}).status_code == 200
    # wrong phone, a phone of another guest, an unknown phone, a malformed phone and no phone at all
    other_phone, _ = guest_order(client)
    for q in ({"phone": other_phone}, {"phone": unique_phone()}, {"phone": "abc"}):
        assert client.get(f"/api/orders/{code}", query_string=q).status_code == 404, q
    assert client.get(f"/api/orders/{code}").status_code == 401


def test_a_customers_phone_does_not_open_their_orders_as_a_guest(client):
    c, address = new_customer()
    assert add_to_cart(c, SMALL).status_code == 201
    code = c.post("/api/orders", json={"addressId": address, "paymentMethod": "COD",
                                       "checkoutToken": str(uuid.uuid4())}).get_json()["OrderCode"]
    phone = unique_phone()
    assert c.patch("/api/profile", json={"phone": phone}).status_code == 200
    assert client.get(f"/api/orders/{code}", query_string={"phone": phone}).status_code == 404   # an account, not a guest


def test_guest_cancels_a_small_order_through_the_popup(client):
    phone, res = guest_order(client)
    code = res.get_json()["OrderCode"]
    before = stock(SMALL)
    popup = client.post(f"/api/orders/{code}/cancel", json={"phone": phone, "reason": "Đổi ý"})
    assert popup.status_code == 200 and popup.get_json()["VoucherCode"] is None
    assert popup.get_json()["Subtotal"] == 139000
    done = client.post(f"/api/orders/{code}/cancel/respond", json={"phone": phone, "keepOrder": False})
    assert done.status_code == 200 and done.get_json()["OrderStatus"] == "Cancelled"
    assert stock(SMALL) == before + 1
    # without the phone nothing happens
    other_phone, other = guest_order(client)
    assert client.post(f"/api/orders/{other.get_json()['OrderCode']}/cancel", json={}).status_code == 401
    assert client.post(f"/api/orders/{other.get_json()['OrderCode']}/cancel", json={"phone": phone}).status_code == 404


def test_guest_with_an_engraved_or_big_order_is_told_to_call_the_hotline(client):
    phone, engraved = guest_order(client, items=[{"variantSku": RING, "quantity": 1, "engravingText": "Love"}])
    res = client.post(f"/api/orders/{engraved.get_json()['OrderCode']}/cancel", json={"phone": phone})
    assert res.status_code == 403 and "hotline" in res.get_json()["error"]
    phone2, big = guest_order(client, items=[{"variantSku": DEAL, "quantity": 1}])
    res = client.post(f"/api/orders/{big.get_json()['OrderCode']}/cancel", json={"phone": phone2})
    assert res.status_code == 403


def test_guest_confirms_receipt_and_gets_warranty_cards(client):
    phone, res = guest_order(client)
    code = res.get_json()["OrderCode"]
    admin = new_admin()
    for status in ("Confirmed", "Shipping"):
        assert admin.post(f"/api/admin/orders/{code}/status", json={"status": status}).status_code == 200
    done = client.post(f"/api/orders/{code}/confirm-received", json={"phone": phone})
    assert done.status_code == 200 and done.get_json()["OrderStatus"] == "Delivered"
    cid = customer_row(phone)["CustomerID"]
    assert count("SELECT COUNT(*) AS n FROM dbo.WarrantyRecords WHERE CustomerID = ?", (cid,)) == 1


def test_admin_sees_guest_orders_with_the_recipient_name(client):
    phone, res = guest_order(client)
    item = new_admin().get("/api/admin/orders?limit=5").get_json()["items"][0]
    assert item["OrderCode"] == res.get_json()["OrderCode"]
    assert item["IsGuest"] is True and item["CustomerName"] == "Phạm Khách Lẻ" and item["CustomerPhone"] == phone
    assert item["CustomerEmail"] is None and item["PaymentMethod"] == "COD"
    # The dashboard sums revenue per material, so every item of the admin list carries its material
    assert item["items"] and all(line["MaterialSnap"] for line in item["items"])


# ---------------- registering with the phone of a guest ----------------

def register(client, phone, **extra):
    body = {"fullName": "Phạm Khách Lẻ", "email": f"g-{uuid.uuid4().hex[:10]}@example.test", "password": PASSWORD,
            "phone": phone, **extra}
    return client.post("/api/auth/register", json=body)


def test_guest_registers_and_the_old_orders_become_theirs(client):
    phone, first = guest_order(client)
    guest_order(client, phone)
    guest_id = customer_row(phone)["CustomerID"]

    account = create_app().test_client()
    asked = register(account, phone)
    assert asked.status_code == 409 and asked.get_json()["reason"] == "otp_required" and asked.get_json()["orders"] == 2
    assert register(account, phone, otp="000000").get_json()["reason"] == "otp_invalid"
    assert customer_row(phone)["UserID"] is None                      # nothing changed yet
    done = register(account, phone, otp=OTP)
    assert done.status_code == 201 and done.get_json()["linkedOrders"] == 2

    assert customer_row(phone) == {"CustomerID": guest_id, "UserID": done.get_json()["id"]}
    mine = account.get("/api/orders").get_json()
    assert len(mine) == 2 and first.get_json()["OrderCode"] in {o["OrderCode"] for o in mine}
    assert len(account.get("/api/addresses").get_json()) == 1
    # the phone no longer works as a guest key: the owner has to log in
    assert client.get(f"/api/orders/{first.get_json()['OrderCode']}", query_string={"phone": phone}).status_code == 404
    assert guest_order(client, phone)[1].status_code == 409


def test_a_guest_row_without_orders_is_taken_over_without_a_code(client):
    phone = unique_phone()
    with transaction() as cur:
        cur.execute("INSERT INTO dbo.Customers (UserID, Phone) VALUES (NULL, ?)", (phone,))
    done = register(create_app().test_client(), phone)
    assert done.status_code == 201 and "linkedOrders" not in done.get_json()


@pytest.mark.parametrize("spelling", ["+84{}", "84{}", "0084{}", "+840{}"])
def test_phone_with_an_account_cannot_be_registered_again_in_another_spelling(client, spelling):
    phone = unique_phone()
    assert register(create_app().test_client(), phone).status_code == 201
    res = register(create_app().test_client(), spelling.format(phone[1:]))
    assert res.status_code == 409 and res.get_json()["reason"] == "phone_in_use"


def test_profile_cannot_take_a_guest_or_an_account_phone(client):
    phone, _ = guest_order(client)
    c, _ = new_customer(with_address=False)
    res = c.patch("/api/profile", json={"phone": phone})
    assert res.status_code == 409 and res.get_json()["reason"] == "phone_in_use"
    mine = unique_phone()
    assert c.patch("/api/profile", json={"phone": mine}).status_code == 200
    assert c.patch("/api/profile", json={"phone": mine}).status_code == 200      # its own number again is fine
    other, _ = new_customer(with_address=False)
    assert other.patch("/api/profile", json={"phone": mine}).status_code == 409


def test_otp_field_must_be_text(client):
    phone, _ = guest_order(client)
    res = register(create_app().test_client(), phone, otp=123456)
    assert res.status_code == 400


def test_a_quote_only_line_stops_the_guest_order_and_leaves_nothing(client):
    phone = unique_phone()
    items = [{"variantSku": SMALL, "quantity": 1}, {"variantSku": "MDBZ036-VV", "quantity": 1}]
    res = client.post("/api/orders/guest", json=guest_body(phone, items))
    assert res.status_code == 409 and res.get_json()["error"].startswith("Item 2:")
    assert res.get_json()["reason"] == "quote_only"
    assert customer_row(phone) is None


# ---------------- a gift: the parcel goes to another phone, the buyer keeps the lookup phone ----------------

def test_a_gift_goes_to_another_phone_while_the_buyer_keeps_the_phone_for_lookups(client):
    buyer = unique_phone()
    receiver = unique_phone()
    _, res = guest_order(client, buyer, recipientPhone="+84" + receiver[1:])        # any spelling is accepted
    assert res.status_code == 201
    code = res.get_json()["OrderCode"]
    assert query("SELECT ShipPhone FROM dbo.Orders WHERE OrderCode = ?", (code,))[0]["ShipPhone"] == receiver
    assert customer_row(buyer) is not None and customer_row(receiver) is None        # the buyer is the customer
    assert client.get(f"/api/orders/{code}", query_string={"phone": buyer}).status_code == 200
    assert client.get(f"/api/orders/{code}", query_string={"phone": receiver}).status_code == 404
    # the same address for another receiver is another address, and an empty value means "the buyer"
    _, same = guest_order(client, buyer, recipientPhone="")
    assert same.status_code == 201
    shipped = {r["Phone"] for r in query("SELECT Phone FROM dbo.CustomerAddresses WHERE CustomerID = ?",
                                         (customer_row(buyer)["CustomerID"],))}
    assert shipped == {receiver, buyer}


@pytest.mark.parametrize("bad", ["12345", "abc", 912345678, ["0912345678"]])
def test_a_bad_recipient_phone_is_refused_and_nothing_is_created(client, bad):
    phone, res = guest_order(client, recipientPhone=bad)
    assert res.status_code == 400 and "recipientPhone" in res.get_json()["error"]
    assert customer_row(phone) is None
