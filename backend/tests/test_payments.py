"""Tests for the simulated online payment, the 15 minute payment limit and the "being crafted" rule.
Online orders (VNPay, MoMo, bank transfer) must be paid within 15 minutes, otherwise the order fails:
it is cancelled, the stock comes back and a voucher it used is given back.
A payment is simulated: POST /api/orders/<code>/pay plays the gateway, an admin confirms bank transfers."""
from datetime import datetime, timedelta

import pytest

from app.db import query, transaction
from test_orders import CHEAP, DEAL, SMALL, add_to_cart, checkout, new_admin, new_customer, order_status, stock
from test_guest_orders import guest_order, unique_phone

RING = CHEAP.format(11)


@pytest.fixture(autouse=True)
def restock(db_ready):
    with transaction() as cur:
        cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = 100 WHERE VariantSKU IN (?, ?, ?)", (SMALL, DEAL, RING))


def online_order(method="VNPay", sku=SMALL, **extra):
    c, address = new_customer()
    assert add_to_cart(c, sku).status_code in (200, 201)
    res = checkout(c, address, method, **extra)
    assert res.status_code == 201, res.get_json()
    return c, res.get_json()["OrderCode"]


def payment(code):
    return query("SELECT p.PaymentID, p.Status, p.PaymentMethod, p.Amount, p.CreatedAt FROM dbo.Payments p "
                 "JOIN dbo.Orders o ON o.OrderID = p.OrderID WHERE o.OrderCode = ? ORDER BY p.PaymentID DESC", (code,))[0]


def make_older(code, minutes):
    """Pretend the order was placed `minutes` ago (the payment time limit counts from the payment row)."""
    with transaction() as cur:
        cur.execute("UPDATE p SET p.CreatedAt = DATEADD(MINUTE, ?, p.CreatedAt) FROM dbo.Payments p "
                    "JOIN dbo.Orders o ON o.OrderID = p.OrderID WHERE o.OrderCode = ?", (-minutes, code))


def sweep(client):
    """Any API request makes the shop cancel the overdue orders."""
    assert client.get("/api/categories").status_code == 200


# ---------------- simulated payment ----------------

def test_online_order_shows_its_payment_deadline(client):
    c, code = online_order()
    detail = c.get(f"/api/orders/{code}").get_json()
    assert detail["PaymentDeadline"] is not None
    made = query("SELECT p.CreatedAt FROM dbo.Payments p JOIN dbo.Orders o ON o.OrderID = p.OrderID "
                 "WHERE o.OrderCode = ?", (code,))[0]["CreatedAt"]
    assert datetime.fromisoformat(detail["PaymentDeadline"]) - datetime.fromisoformat(made) == timedelta(minutes=15)
    assert c.get("/api/orders").get_json()[0]["PaymentDeadline"] == detail["PaymentDeadline"]
    cod, address = new_customer()
    add_to_cart(cod, SMALL)
    cod_code = checkout(cod, address, "COD").get_json()["OrderCode"]
    assert cod.get(f"/api/orders/{cod_code}").get_json()["PaymentDeadline"] is None


@pytest.mark.parametrize("method", ["VNPay", "MoMo"])
def test_paying_makes_the_payment_successful_and_the_order_can_then_be_confirmed(client, method):
    c, code = online_order(method)
    admin = new_admin()
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"}).status_code == 409   # not paid yet
    res = c.post(f"/api/orders/{code}/pay")
    assert res.status_code == 200 and res.get_json()["PaymentStatus"] == "Success"
    assert payment(code)["Status"] == "Success" and order_status(code) == "Pending"
    row = query("SELECT TransactionID, ResponseCode, IsSandbox FROM dbo.Payments p JOIN dbo.Orders o ON o.OrderID = p.OrderID "
                "WHERE o.OrderCode = ?", (code,))[0]
    assert row["TransactionID"].startswith("SIM-") and row["ResponseCode"] == "00" and row["IsSandbox"] is True
    assert c.get(f"/api/orders/{code}").get_json()["PaymentDeadline"] is None
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"}).status_code == 200


def test_paying_twice_or_a_cash_order_or_a_bank_transfer_is_refused(client):
    c, code = online_order()
    assert c.post(f"/api/orders/{code}/pay").status_code == 200
    assert c.post(f"/api/orders/{code}/pay").status_code == 409
    cod, code_cod = online_order("COD")
    assert cod.post(f"/api/orders/{code_cod}/pay").status_code == 400
    bank, code_bank = online_order("BankTransfer")
    assert bank.post(f"/api/orders/{code_bank}/pay").status_code == 400


def test_nobody_else_can_pay_my_order(client):
    c, code = online_order()
    other, _ = new_customer()
    assert other.post(f"/api/orders/{code}/pay").status_code == 404
    assert c.post("/api/orders/VN000000000/pay").status_code == 404
    from app import create_app
    assert create_app().test_client().post(f"/api/orders/{code}/pay").status_code == 401


def test_a_guest_pays_with_the_phone_number(client):
    phone, res = guest_order(client, paymentMethod="MoMo")
    code = res.get_json()["OrderCode"]
    assert client.post(f"/api/orders/{code}/pay", json={"phone": unique_phone()}).status_code == 404
    done = client.post(f"/api/orders/{code}/pay", json={"phone": phone})
    assert done.status_code == 200 and payment(code)["Status"] == "Success"


def test_admin_confirms_a_bank_transfer(client):
    c, code = online_order("BankTransfer")
    admin = new_admin()
    assert admin.post(f"/api/admin/orders/{code}/confirm-payment").json == {"OrderCode": code, "PaymentStatus": "Success"}
    assert payment(code)["Status"] == "Success"
    assert admin.post(f"/api/admin/orders/{code}/confirm-payment").status_code == 409          # already paid
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"}).status_code == 200


def test_only_an_admin_confirms_and_only_bank_transfers(client):
    c, code = online_order("BankTransfer")
    assert c.post(f"/api/admin/orders/{code}/confirm-payment").status_code == 403
    admin = new_admin()
    _, vnpay = online_order("VNPay")
    assert admin.post(f"/api/admin/orders/{vnpay}/confirm-payment").status_code == 400
    assert admin.post("/api/admin/orders/VN000000000/confirm-payment").status_code == 404


# ---------------- the 15 minute limit ----------------

def test_an_online_order_not_paid_in_15_minutes_fails(client):
    voucher_used = query("SELECT UsedCount FROM dbo.Vouchers WHERE VoucherCode = 'GIAM300K'")[0]["UsedCount"]
    before = stock(DEAL)
    c, code = online_order("VNPay", DEAL, voucherCode="GIAM300K")
    assert stock(DEAL) == before - 1
    assert query("SELECT UsedCount FROM dbo.Vouchers WHERE VoucherCode = 'GIAM300K'")[0]["UsedCount"] == voucher_used + 1
    make_older(code, 16)
    sweep(client)
    detail = c.get(f"/api/orders/{code}").get_json()
    assert detail["OrderStatus"] == "Cancelled" and "15 phút" in detail["CancelReason"]
    assert stock(DEAL) == before                                                    # stock is back
    assert query("SELECT UsedCount FROM dbo.Vouchers WHERE VoucherCode = 'GIAM300K'")[0]["UsedCount"] == voucher_used
    assert payment(code)["Status"] == "Expired"
    assert c.get("/api/orders").get_json()[0]["CancelChannel"] is None
    log = query("SELECT PerformedBy FROM dbo.AuditLogs a JOIN dbo.Orders o ON o.OrderID = a.EntityID "
                "WHERE a.EntityName = 'Orders' AND a.Action = 'PaymentExpired' AND o.OrderCode = ?", (code,))
    assert [r["PerformedBy"] for r in log] == ["System:PaymentTimeout"]


@pytest.mark.parametrize("method", ["VNPay", "MoMo", "BankTransfer"])
def test_every_online_method_has_the_limit(client, method):
    _, code = online_order(method)
    make_older(code, 16)
    sweep(client)
    assert order_status(code) == "Cancelled"


def test_14_minutes_is_still_in_time(client):
    c, code = online_order()
    make_older(code, 14)
    sweep(client)
    assert order_status(code) == "Pending"
    assert c.post(f"/api/orders/{code}/pay").status_code == 200


def test_paying_after_the_limit_is_refused_even_before_anyone_swept(client):
    c, code = online_order()
    make_older(code, 20)
    res = c.post(f"/api/orders/{code}/pay")          # the shop sweeps first, then refuses the late payment
    assert res.status_code == 409 and res.get_json()["code"] == 50050
    assert order_status(code) == "Cancelled" and payment(code)["Status"] == "Expired"


def test_paid_orders_and_cash_orders_never_expire(client):
    paid_client, paid = online_order()
    paid_client.post(f"/api/orders/{paid}/pay")
    _, cash = online_order("COD")
    for code in (paid, cash):
        make_older(code, 120)
    sweep(client)
    assert order_status(paid) == "Pending" and order_status(cash) == "Pending"


def test_a_guest_order_expires_too_and_its_voucher_is_given_back(client):
    used = query("SELECT UsedCount FROM dbo.Vouchers WHERE VoucherCode = 'GIAM300K'")[0]["UsedCount"]
    phone, res = guest_order(client, items=[{"variantSku": DEAL, "quantity": 1}], paymentMethod="VNPay", voucherCode="GIAM300K")
    code = res.get_json()["OrderCode"]
    make_older(code, 16)
    sweep(client)
    assert order_status(code) == "Cancelled"
    assert query("SELECT UsedCount FROM dbo.Vouchers WHERE VoucherCode = 'GIAM300K'")[0]["UsedCount"] == used
    assert client.get(f"/api/orders/{code}", query_string={"phone": phone}).get_json()["OrderStatus"] == "Cancelled"


def test_a_cancelled_order_cannot_be_paid_and_a_cancel_by_the_customer_still_returns_the_money_state(client):
    c, code = online_order("VNPay", SMALL)
    popup = c.post(f"/api/orders/{code}/cancel", json={})
    assert popup.status_code == 200
    c.post(f"/api/orders/{code}/cancel/respond", json={"keepOrder": False})
    res = c.post(f"/api/orders/{code}/pay")
    assert res.status_code == 409 and res.get_json()["code"] == 50050
    assert payment(code)["Status"] == "Failed"


def test_a_paid_order_that_is_cancelled_is_refunded(client):
    c, code = online_order("VNPay", SMALL)
    c.post(f"/api/orders/{code}/pay")
    c.post(f"/api/orders/{code}/cancel", json={})
    c.post(f"/api/orders/{code}/cancel/respond", json={"keepOrder": False})
    assert order_status(code) == "Cancelled" and payment(code)["Status"] == "Refunded"


# ---------------- an order that is being crafted cannot be cancelled ----------------

def confirmed(sku=SMALL, **cart):
    c, address = new_customer()
    assert add_to_cart(c, sku, **cart).status_code in (200, 201)
    code = checkout(c, address).get_json()["OrderCode"]
    admin = new_admin()
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"}).status_code == 200
    return c, admin, code


def test_production_can_start_only_on_a_confirmed_order(client):
    c, address = new_customer()
    add_to_cart(c, SMALL)
    code = checkout(c, address).get_json()["OrderCode"]
    admin = new_admin()
    assert admin.post(f"/api/admin/orders/{code}/start-production").status_code == 409          # still Pending
    admin.post(f"/api/admin/orders/{code}/status", json={"status": "Confirmed"})
    res = admin.post(f"/api/admin/orders/{code}/start-production")
    assert res.status_code == 200 and res.get_json()["ProductionStartedAt"] is not None
    assert admin.post(f"/api/admin/orders/{code}/start-production").status_code == 409          # only once


def test_only_an_admin_can_start_production(client):
    c, admin, code = confirmed()
    assert c.post(f"/api/admin/orders/{code}/start-production").status_code == 403
    assert admin.post("/api/admin/orders/VN000000000/start-production").status_code == 404


def test_nobody_can_cancel_an_order_that_is_being_crafted(client):
    # an engraved ring: the customer called, the shop already began crafting, so even the admin cannot cancel it
    c, admin, code = confirmed(RING, engravingText="Love")
    assert admin.post(f"/api/admin/orders/{code}/start-production").status_code == 200
    res = admin.post(f"/api/admin/orders/{code}/status", json={"status": "Cancelled", "reason": "Khách gọi hotline"})
    assert res.status_code == 409 and res.get_json()["code"] == 50049
    assert order_status(code) == "Confirmed"
    detail = c.get(f"/api/orders/{code}").get_json()
    assert detail["ProductionStartedAt"] is not None and detail["CancelChannel"] is None


def test_a_small_order_in_production_cannot_be_cancelled_by_the_customer_either(client):
    c, admin, code = confirmed(SMALL)
    assert c.get("/api/orders").get_json()[0]["CancelChannel"] == "Web"
    admin.post(f"/api/admin/orders/{code}/start-production")
    assert c.get("/api/orders").get_json()[0]["CancelChannel"] is None
    res = c.post(f"/api/orders/{code}/cancel", json={})
    assert res.status_code == 409 and res.get_json()["code"] == 50049
    assert query("SELECT COUNT(*) AS n FROM dbo.OrderCancellationRequests r JOIN dbo.Orders o ON o.OrderID = r.OrderID "
                 "WHERE o.OrderCode = ?", (code,))[0]["n"] == 0


def test_a_confirmed_order_not_in_production_can_still_be_cancelled_by_the_admin(client):
    c, admin, code = confirmed(RING, engravingText="Love")
    assert admin.post(f"/api/admin/orders/{code}/status", json={"status": "Cancelled"}).status_code == 200
    assert order_status(code) == "Cancelled"


def test_starting_production_closes_a_waiting_cancel_popup(client):
    c, admin, code = confirmed(SMALL)
    assert c.post(f"/api/orders/{code}/cancel", json={}).status_code == 200
    assert c.get(f"/api/orders/{code}").get_json()["pendingCancelRequest"] is not None
    admin.post(f"/api/admin/orders/{code}/start-production")
    assert c.get(f"/api/orders/{code}").get_json()["pendingCancelRequest"] is None
    assert c.post(f"/api/orders/{code}/cancel/respond", json={"keepOrder": False}).status_code == 409
    assert order_status(code) == "Confirmed"


def test_a_failing_overdue_check_does_not_stop_the_shop(client, monkeypatch):
    import pyodbc
    import app as app_module

    def broken(*args, **kwargs):
        raise pyodbc.Error("HY000", "the overdue check failed")

    monkeypatch.setattr(app_module, "call", broken)
    assert client.get("/api/categories").status_code == 200


def test_production_start_is_in_the_audit_log(client):
    _, admin, code = confirmed()
    admin.post(f"/api/admin/orders/{code}/start-production")
    n = query("SELECT COUNT(*) AS n FROM dbo.AuditLogs a JOIN dbo.Orders o ON o.OrderID = a.EntityID "
              "WHERE a.EntityName = 'Orders' AND a.Action = 'ProductionStarted' AND o.OrderCode = ?", (code,))[0]["n"]
    assert n == 1
