"""Tests for rules that live in the SQL Server procedures, called directly (not through the API).
They run on the rebuilt test database. Each test makes its own customers, so tests do not depend on each other."""
import datetime
import threading
import uuid

import pyodbc
import pytest

from app.db import ProcError, call, query, transaction
from test_orders import MID, add_to_cart, checkout, new_admin, new_customer, order_status

SOON = lambda days=3: datetime.datetime.now() + datetime.timedelta(days=days)   # noqa: E731
BIG = "NDINO131LDIA-VT-11"


@pytest.fixture(autouse=True)
def restock(db_ready):
    """The test database is shared by all test files, so give the products used here plenty of stock."""
    with transaction() as cur:
        cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = 100 WHERE VariantSKU IN (?, ?, ?)",
                    (MID, "NC433-BT-9", BIG))


def customer_id_of(code):
    return query("SELECT CustomerID AS c FROM dbo.Orders WHERE OrderCode = ?", (code,))[0]["c"]


def payment_of(code):
    return query("SELECT p.PaymentID, p.Amount, p.Status FROM dbo.Payments p JOIN dbo.Orders o ON o.OrderID = p.OrderID "
                 "WHERE o.OrderCode = ? ORDER BY p.PaymentID DESC", (code,))[0]


def pay(payment_id, tx=None, **extra):
    args = ["@PaymentID = ?", "@IsSuccess = 1", "@TransactionID = ?", "@ResponseCode = '00'"]
    params = [payment_id, tx or "TX" + uuid.uuid4().hex[:12]]
    if "amount" in extra:
        args.append("@Amount = ?")
        params.append(extra["amount"])
    return call("EXEC dbo.sp_RecordPaymentResult " + ", ".join(args), tuple(params))


def online_order(method="VNPay"):
    client, addr = new_customer()
    add_to_cart(client, MID)
    code = checkout(client, addr, method).get_json()["OrderCode"]
    return client, addr, code


def delivered_order_with_card():
    """A COD order that is delivered, so it has a warranty card. Returns (customer_id, warranty_code, admin_id)."""
    client, addr = new_customer()
    add_to_cart(client, "NC433-BT-9")                       # a ring, so resizing is allowed
    code = checkout(client, addr).get_json()["OrderCode"]
    admin = new_admin()
    for status in ("Confirmed", "Shipping"):
        assert admin.post(f"/api/admin/orders/{code}/status", json={"status": status}).status_code == 200
    assert client.post(f"/api/orders/{code}/confirm-received").status_code == 200
    card = query("SELECT w.WarrantyCode FROM dbo.WarrantyRecords w JOIN dbo.Orders o ON o.OrderID = w.OrderID "
                 "WHERE o.OrderCode = ?", (code,))[0]["WarrantyCode"]
    admin_id = query("SELECT MAX(UserID) AS u FROM dbo.Users WHERE Role = 'Admin'")[0]["u"]
    return customer_id_of(code), card, admin_id


def book(card, customer, service_type, when=None, new_size=None):
    return call("DECLARE @s INT; EXEC dbo.sp_BookAfterSalesService @WarrantyCode = ?, @CustomerID = ?, "
                "@ServiceType = ?, @PreferredDate = ?, @NewRingSize = ?, @ServiceID = @s OUTPUT; SELECT @s AS id",
                (card, customer, service_type, when or SOON(), new_size))[0]["id"]


def schedule_and_complete(service_id, admin_id, **extra):
    call("EXEC dbo.sp_ScheduleAfterSalesService @ServiceID = ?, @AdminUserID = ?, @AppointmentDate = ?",
         (service_id, admin_id, SOON(4)))
    fee = f", @PaidFee = {extra['fee']}" if "fee" in extra else ""
    call(f"EXEC dbo.sp_CompleteAfterSalesService @ServiceID = ?, @AdminUserID = ?{fee}", (service_id, admin_id))
    return query("SELECT IsFreeOfCharge, ServiceFee FROM dbo.AfterSalesServices WHERE ServiceID = ?", (service_id,))[0]


def expect(code, sql, params=()):
    with pytest.raises(ProcError) as caught:
        call(sql, params)
    assert caught.value.code == code, caught.value.message


# ---------------- online orders must be paid ----------------

def test_online_order_cannot_be_confirmed_until_it_is_paid(db_ready):
    client, addr, code = online_order("VNPay")
    admin = new_admin()
    res = admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"})
    assert res.status_code == 409 and res.get_json()["code"] == 50038
    assert order_status(code) == "Pending"
    pay(payment_of(code)["PaymentID"])
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"}).status_code == 200
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Shipping"}).status_code == 200
    assert client.post(f"/api/orders/{code}/confirm-received").status_code == 200


def test_unpaid_online_order_can_still_be_cancelled_by_admin(db_ready):
    _, _, code = online_order("MoMo")
    assert new_admin().post(f"/api/admin/orders/{code}/status", json={"status": "Cancelled"}).status_code == 200


# ---------------- payment callback ----------------

def test_same_callback_twice_is_ignored_but_a_reused_transaction_id_is_an_error(db_ready):
    _, _, first = online_order()
    _, _, second = online_order()
    p1, p2 = payment_of(first)["PaymentID"], payment_of(second)["PaymentID"]
    pay(p1, "TX-REUSE-1")
    pay(p1, "TX-REUSE-1")                                          # a repeated callback is a no-op
    expect(50041, "EXEC dbo.sp_RecordPaymentResult @PaymentID = ?, @IsSuccess = 1, @TransactionID = 'TX-REUSE-1'", (p2,))
    assert payment_of(second)["Status"] == "Pending"


def test_callback_amount_must_match(db_ready):
    _, _, code = online_order()
    payment = payment_of(code)
    expect(50043, "EXEC dbo.sp_RecordPaymentResult @PaymentID = ?, @IsSuccess = 1, @TransactionID = 'TX-AMT-1', "
                  "@Amount = ?", (payment["PaymentID"], payment["Amount"] - 1))
    assert payment_of(code)["Status"] == "Pending"
    pay(payment["PaymentID"], "TX-AMT-2", amount=payment["Amount"])
    assert payment_of(code)["Status"] == "Success"


# ---------------- order procedures: bad input gives a clear error ----------------

def test_keep_order_null_does_not_cancel_the_order(db_ready):
    client, addr = new_customer()
    add_to_cart(client, MID)
    code = checkout(client, addr).get_json()["OrderCode"]
    request_id = client.post(f"/api/orders/{code}/cancel", json={}).get_json()["RequestID"]
    expect(50045, "EXEC dbo.sp_RespondCancelPopup @RequestID = ?, @CustomerID = ?, @KeepOrder = ?",
           (request_id, customer_id_of(code), None))
    assert order_status(code) == "Pending"


@pytest.mark.parametrize("status", [None, "Foo", ""])
def test_update_status_rejects_unknown_status(db_ready, status):
    client, addr = new_customer()
    add_to_cart(client, MID)
    code = checkout(client, addr).get_json()["OrderCode"]
    order_id = query("SELECT OrderID AS i FROM dbo.Orders WHERE OrderCode = ?", (code,))[0]["i"]
    admin_id = query("SELECT MAX(UserID) AS u FROM dbo.Users WHERE Role = 'Admin'")[0]["u"]
    expect(50046, "EXEC dbo.sp_UpdateOrderStatus @OrderID = ?, @NewStatus = ?, @AdminUserID = ?",
           (order_id, status, admin_id))


def test_place_order_rejects_missing_token_and_bad_fee(db_ready):
    client, addr = new_customer()
    add_to_cart(client, MID)
    cust = query("SELECT MAX(CustomerID) AS c FROM dbo.Customers")[0]["c"]
    sql = ("DECLARE @o INT; EXEC dbo.sp_PlaceOrder @CustomerID = ?, @AddressID = ?, @PaymentMethod = ?, "
           "@CheckoutToken = ?, @ShippingFee = ?, @OrderID = @o OUTPUT")
    expect(50047, sql, (cust, addr, "COD", None, 0))
    expect(50047, sql, (cust, addr, "COD", str(uuid.uuid4()), -1))
    expect(50010, sql, (cust, addr, None, str(uuid.uuid4()), 0))


def test_place_order_refuses_another_customers_token(db_ready):
    a, addr_a = new_customer()
    add_to_cart(a, MID)
    token = str(uuid.uuid4())
    assert checkout(a, addr_a, token=token).status_code == 201
    b, addr_b = new_customer()
    add_to_cart(b, MID)
    cust_b = query("SELECT MAX(CustomerID) AS c FROM dbo.Customers")[0]["c"]
    expect(50048, "DECLARE @o INT; EXEC dbo.sp_PlaceOrder @CustomerID = ?, @AddressID = ?, @PaymentMethod = 'COD', "
                  "@CheckoutToken = ?, @OrderID = @o OUTPUT", (cust_b, addr_b, token))


def test_a_shipping_address_over_400_characters_is_refused_not_cut(db_ready):
    client, addr = new_customer()
    add_to_cart(client, MID)
    cust = query("SELECT MAX(CustomerID) AS c FROM dbo.Customers")[0]["c"]
    with transaction() as cur:     # the API limits this to 400, so insert the long address straight into the table
        cur.execute("INSERT INTO dbo.CustomerAddresses (CustomerID, RecipientName, Phone, AddressLine, Ward, Province) "
                    "OUTPUT INSERTED.AddressID VALUES (?, 'A', '0901234567', ?, ?, ?)", (cust, "a" * 255, "w" * 100, "p" * 100))
        long_id = cur.fetchval()
    expect(50011, "DECLARE @o INT; EXEC dbo.sp_PlaceOrder @CustomerID = ?, @AddressID = ?, @PaymentMethod = 'COD', "
                  "@CheckoutToken = ?, @OrderID = @o OUTPUT", (cust, long_id, str(uuid.uuid4())))


def test_two_requests_with_the_same_token_at_once_both_get_the_same_order(db_ready):
    client, addr = new_customer()
    add_to_cart(client, MID)
    cust = query("SELECT MAX(CustomerID) AS c FROM dbo.Customers")[0]["c"]
    token, barrier, results = str(uuid.uuid4()), threading.Barrier(2), []

    def go():
        barrier.wait()
        try:
            rows = call("DECLARE @o INT; EXEC dbo.sp_PlaceOrder @CustomerID = ?, @AddressID = ?, @PaymentMethod = 'COD', "
                        "@CheckoutToken = ?, @OrderID = @o OUTPUT; SELECT @o AS id", (cust, addr, token))
            results.append(rows[0]["id"])
        except Exception as exc:               # a failure here is what the test is looking for
            results.append(repr(exc))

    threads = [threading.Thread(target=go) for _ in range(2)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert len(set(results)) == 1 and isinstance(results[0], int), results
    assert query("SELECT COUNT(*) AS n FROM dbo.Orders WHERE CustomerID = ?", (cust,))[0]["n"] == 1


# ---------------- after-sales procedures ----------------

def test_booking_rejects_bad_input_with_clear_errors(db_ready):
    cust, card, _ = delivered_order_with_card()
    sql = ("DECLARE @s INT; EXEC dbo.sp_BookAfterSalesService @WarrantyCode = ?, @CustomerID = ?, @ServiceType = ?, "
           "@PreferredDate = ?, @NewRingSize = ?, @ServiceID = @s OUTPUT")
    expect(50039, sql, (card, cust, "Bogus", SOON(), None))
    expect(50039, sql, (card, cust, None, SOON(), None))
    expect(50032, sql, (card, cust, "Cleaning", None, None))
    expect(50032, sql, (card, cust, "Cleaning", SOON(-1), None))
    expect(50032, sql, (card, cust, "Cleaning", SOON(800), None))              # more than one year ahead
    expect(50042, sql, (card, cust, "Resizing", SOON(), None))                 # resizing needs the new size
    expect(50042, sql, (card, cust, "Cleaning", SOON(), 10))                   # other services have no new size
    expect(50042, sql, (card, cust, "Resizing", SOON(), 99))                   # size not in the chart
    expect(50031, sql, (card, cust + 1000000, "Cleaning", SOON(), None))       # not this customer's card
    assert book(card, cust, "Polishing")                                       # a valid booking still works


def test_scheduling_needs_a_future_date(db_ready):
    cust, card, admin_id = delivered_order_with_card()
    service = book(card, cust, "Cleaning")
    sql = "EXEC dbo.sp_ScheduleAfterSalesService @ServiceID = ?, @AdminUserID = ?, @AppointmentDate = ?"
    expect(50032, sql, (service, admin_id, None))
    expect(50032, sql, (service, admin_id, SOON(-1)))
    assert query("SELECT Status FROM dbo.AfterSalesServices WHERE ServiceID = ?", (service,))[0]["Status"] == "Pending"


def test_completing_a_service_checks_fee_and_card(db_ready):
    cust, card, admin_id = delivered_order_with_card()
    service = book(card, cust, "Cleaning")
    call("EXEC dbo.sp_ScheduleAfterSalesService @ServiceID = ?, @AdminUserID = ?, @AppointmentDate = ?",
         (service, admin_id, SOON(4)))
    expect(50044, "EXEC dbo.sp_CompleteAfterSalesService @ServiceID = ?, @AdminUserID = ?, @PaidFee = -5", (service, admin_id))
    expect(50044, "EXEC dbo.sp_CompleteAfterSalesService @ServiceID = ?, @AdminUserID = ?, @PaidFee = ?", (service, admin_id, None))
    with transaction() as cur:
        cur.execute("UPDATE dbo.WarrantyRecords SET Status = 'Voided' WHERE WarrantyCode = ?", (card,))
    expect(50031, "EXEC dbo.sp_CompleteAfterSalesService @ServiceID = ?, @AdminUserID = ?", (service, admin_id))
    assert query("SELECT Status FROM dbo.AfterSalesServices WHERE ServiceID = ?", (service,))[0]["Status"] != "Completed"


def test_cleaning_quota_makes_extra_cleanings_chargeable(db_ready):
    cust, card, admin_id = delivered_order_with_card()
    with transaction() as cur:
        cur.execute("UPDATE dbo.WarrantyPolicies SET CleaningQuota = 1")
    try:
        first = schedule_and_complete(book(card, cust, "Cleaning"), admin_id)
        second = schedule_and_complete(book(card, cust, "Cleaning"), admin_id, fee=70000)
    finally:
        with transaction() as cur:
            cur.execute("UPDATE dbo.WarrantyPolicies SET CleaningQuota = NULL")
    assert first["IsFreeOfCharge"] is True and first["ServiceFee"] == 0
    assert second["IsFreeOfCharge"] is False and second["ServiceFee"] == 70000


def test_unlimited_quota_stays_free(db_ready):
    cust, card, admin_id = delivered_order_with_card()
    for _ in range(3):
        assert schedule_and_complete(book(card, cust, "Cleaning"), admin_id)["IsFreeOfCharge"] is True


def test_warranty_view_shows_the_size_after_a_resize(db_ready):
    cust, card, admin_id = delivered_order_with_card()
    before = query("SELECT PurchasedRingSize, RingSize FROM dbo.vw_CustomerWarranties WHERE WarrantyCode = ?", (card,))[0]
    assert before["PurchasedRingSize"] == before["RingSize"] == 9
    schedule_and_complete(book(card, cust, "Resizing", new_size=12), admin_id)
    after = query("SELECT PurchasedRingSize, RingSize, ResizingCount FROM dbo.vw_CustomerWarranties WHERE WarrantyCode = ?", (card,))[0]
    assert after == {"PurchasedRingSize": 9, "RingSize": 12, "ResizingCount": 1}


# ---------------- other ----------------

def test_two_first_views_of_a_product_at_once_do_not_collide(db_ready):
    client, _ = new_customer(with_address=False)
    cust = query("SELECT MAX(CustomerID) AS c FROM dbo.Customers")[0]["c"]
    product = query("SELECT MIN(ProductID) AS p FROM dbo.Products")[0]["p"]
    barrier, errors = threading.Barrier(2), []

    def go():
        barrier.wait()
        try:
            call("EXEC dbo.sp_TrackProductView @CustomerID = ?, @ProductID = ?", (cust, product))
        except Exception as exc:
            errors.append(repr(exc))

    threads = [threading.Thread(target=go) for _ in range(2)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert errors == []
    assert query("SELECT ViewCount AS v FROM dbo.RecentlyViewedProducts WHERE CustomerID = ? AND ProductID = ?",
                 (cust, product))[0]["v"] == 2


def test_indexes_added_after_review_exist(db_ready):
    names = {r["name"] for r in query("SELECT name FROM sys.indexes WHERE name LIKE 'IX[_]%'")}
    assert {"IX_Warranty_Order", "IX_CustomerAddresses_Cust", "IX_CancelReq_Order"} <= names


def test_cancel_limit_message_follows_the_limit_function(db_ready):
    message = query("SELECT dbo.fn_OnlineCancelLimit() AS limit")[0]["limit"]
    client, addr = new_customer()
    add_to_cart(client, BIG)
    code = checkout(client, addr).get_json()["OrderCode"]
    error = client.post(f"/api/orders/{code}/cancel", json={}).get_json()["error"]
    assert f"{message:,}".replace(",", ".") in error                       # "5.000.000"
