"""An admin who is logged in on the same browser sees the shop as a visitor (the pages know no customer account), so the
pages send the proof of a visitor: the phone of the order, or the cart lines. The server must accept that proof from an
admin session too. Everything an admin could not do before stays refused."""
from app.db import query
from test_catalog import MID
from test_guest_orders import guest_order, unique_phone
from test_orders import SMALL, add_to_cart, checkout, new_admin, new_customer
from test_warranty import restock  # noqa: F401  (autouse: plenty of stock while the test runs)


def guest_pending_order(client):
    """A visitor's cash order. Returns (phone, order code)."""
    phone, res = guest_order(client)
    assert res.status_code == 201
    return phone, res.get_json()["OrderCode"]


# ---------------- what now works ----------------

def test_an_admin_looks_up_a_visitors_order_with_the_phone_like_any_visitor(client):
    phone, code = guest_pending_order(client.application.test_client())
    admin = new_admin()
    res = admin.get(f"/api/orders/{code}", query_string={"phone": phone})
    assert res.status_code == 200 and res.get_json()["OrderCode"] == code
    assert admin.get(f"/api/orders/{code}/warranties", query_string={"phone": phone}).get_json() == []


def test_an_admin_session_can_follow_the_guest_checkout_to_the_end(client):
    admin = new_admin()
    phone, res = guest_order(admin)                                   # the guest order itself never needed a login
    code = res.get_json()["OrderCode"]
    assert admin.get(f"/api/orders/{code}", query_string={"phone": phone}).status_code == 200
    popup = admin.post(f"/api/orders/{code}/cancel", json={"phone": phone})
    assert popup.status_code == 200
    done = admin.post(f"/api/orders/{code}/cancel/respond", json={"phone": phone, "keepOrder": False})
    assert done.status_code == 200 and done.get_json()["OrderStatus"] == "Cancelled"


def test_the_audit_log_names_the_guest_not_the_admin_who_browses_as_a_visitor(client):
    admin = new_admin()
    phone, res = guest_order(admin)
    code = res.get_json()["OrderCode"]
    admin.post(f"/api/orders/{code}/cancel", json={"phone": phone})
    admin.post(f"/api/orders/{code}/cancel/respond", json={"phone": phone, "keepOrder": False})
    rows = query("SELECT a.PerformedBy, a.PerformedByUserID FROM dbo.AuditLogs a JOIN dbo.Orders o ON o.OrderID = a.EntityID "
                 "WHERE a.EntityName = 'Orders' AND o.OrderCode = ? AND a.Action <> 'OrderCreated'", (code,))
    assert rows and all(r["PerformedBy"].startswith("Guest:") and r["PerformedByUserID"] is None for r in rows), rows


def test_the_audit_log_still_names_the_customer_when_a_customer_acts(client):
    """The other side of the test above: a customer's own session is not turned into a guest."""
    customer, address = new_customer()
    add_to_cart(customer, SMALL)
    code = checkout(customer, address).get_json()["OrderCode"]
    assert customer.post(f"/api/orders/{code}/cancel", json={}).status_code == 200
    assert customer.post(f"/api/orders/{code}/cancel/respond", json={"keepOrder": False}).status_code == 200
    rows = query("SELECT a.PerformedBy, a.PerformedByUserID FROM dbo.AuditLogs a JOIN dbo.Orders o ON o.OrderID = a.EntityID "
                 "WHERE a.EntityName = 'Orders' AND o.OrderCode = ? AND a.Action <> 'OrderCreated'", (code,))
    assert rows and all(r["PerformedBy"].startswith("Customer:") and r["PerformedByUserID"] is not None for r in rows), rows


def test_an_admin_checks_a_voucher_with_the_lines_of_the_browser_cart(client):
    res = new_admin().post("/api/vouchers/check", json={"code": "WELCOME5", "items": [{"variantSku": MID, "quantity": 1}]})
    assert res.status_code == 200 and res.get_json()["discount"] == 118000 and res.get_json()["subtotal"] == 2361000


# ---------------- what stays refused ----------------

def test_an_admin_without_a_proof_is_still_turned_away(client):
    admin = new_admin()
    assert admin.get("/api/orders/VN1").status_code == 403
    assert admin.post("/api/orders/VN1/cancel", json={}).status_code == 403
    assert admin.post("/api/orders/VN1/feedback", json={"rating": 5}).status_code == 403
    assert admin.post("/api/vouchers/check", json={"code": "WELCOME5"}).status_code == 403
    assert admin.get("/api/cart").status_code == 403


def test_the_proof_of_an_admin_is_judged_like_the_proof_of_a_visitor(client):
    phone, code = guest_pending_order(client.application.test_client())
    other_phone, other_code = guest_pending_order(client.application.test_client())
    admin = new_admin()
    assert admin.get(f"/api/orders/{code}", query_string={"phone": unique_phone()}).status_code == 404       # wrong phone
    assert admin.get("/api/orders/VN000000000000", query_string={"phone": phone}).status_code == 404         # wrong order
    assert admin.get(f"/api/orders/{other_code}", query_string={"phone": phone}).status_code == 404          # phone of another order


def test_a_phone_that_belongs_to_an_account_is_no_proof_even_for_an_admin(client):
    owner, address = new_customer()
    phone = unique_phone()
    assert owner.patch("/api/profile", json={"phone": phone}).status_code == 200
    add_to_cart(owner, SMALL)
    code = checkout(owner, address).get_json()["OrderCode"]
    assert owner.get(f"/api/orders/{code}").status_code == 200                                              # the owner sees it
    assert new_admin().get(f"/api/orders/{code}", query_string={"phone": phone}).status_code == 404


def test_a_logged_in_customer_never_falls_back_to_the_phone_proof(client):
    phone, code = guest_pending_order(client.application.test_client())
    customer, _ = new_customer()
    # a customer with an account is a customer: the phone of someone else's guest order opens nothing
    assert customer.get(f"/api/orders/{code}", query_string={"phone": phone}).status_code == 404
    assert customer.get("/api/orders/VN1").status_code == 404
