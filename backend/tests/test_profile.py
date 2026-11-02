"""Tests for the profile, change of password, and editing or deleting addresses."""
import uuid
from datetime import date

import pytest

from app import create_app
from app.db import query, transaction
from conftest import PASSWORD, make_user
from test_orders import add_to_cart, checkout, new_customer

NEW_PASSWORD = "Another@Pass9"
ADDRESS = {"recipientName": "B", "phone": "0912345678", "addressLine": "2 Trần Phú",
           "ward": "Phường 1", "province": "Thành phố Đà Nẵng"}


@pytest.fixture(autouse=True)
def restock(db_ready):
    with transaction() as cur:
        cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = 100 WHERE VariantSKU = 'BT161B-VT'")


def unique_phone():
    """A phone number no other customer has (the phone is the customer id, so it is unique)."""
    return "09" + str(uuid.uuid4().int)[:8]


def email_of(client):
    return client.get("/api/auth/me").get_json()["email"]


def stored(client):
    """The user and customer rows straight from the database."""
    return query("SELECT u.FullName, u.UpdatedAt AS UserUpdated, u.Role, u.Email, c.Phone, c.DateOfBirth, "
                 "c.DefaultRingSize, c.UpdatedAt AS CustomerUpdated FROM dbo.Users u "
                 "JOIN dbo.Customers c ON c.UserID = u.UserID WHERE u.Email = ?", (email_of(client),))[0]


# ---------------- profile ----------------

def test_profile_needs_a_customer_login(client):
    assert client.get("/api/profile").status_code == 401
    assert client.patch("/api/profile", json={"fullName": "x"}).status_code == 401
    admin = create_app().test_client()
    email = f"pf-admin-{uuid.uuid4().hex[:8]}@example.test"
    make_user(email, role="Admin")
    admin.post("/api/auth/login", json={"email": email, "password": PASSWORD})
    assert admin.get("/api/profile").status_code == 403


def test_new_customer_has_an_empty_profile(client):
    c, _ = new_customer(with_address=False)
    profile = c.get("/api/profile").get_json()
    assert profile == {"fullName": "Khách Test", "email": email_of(c), "phone": None,
                       "dateOfBirth": None, "defaultRingSize": None}


def test_update_one_field_leaves_the_others(client):
    c, _ = new_customer(with_address=False)
    phone = unique_phone()
    res = c.patch("/api/profile", json={"phone": f" {phone} "})
    assert res.status_code == 200
    assert res.get_json()["phone"] == phone and res.get_json()["fullName"] == "Khách Test"
    row = stored(c)
    assert row["Phone"] == phone and row["FullName"] == "Khách Test"
    assert row["CustomerUpdated"] is not None and row["UserUpdated"] is None    # only the customer row changed


def test_update_everything_and_read_it_back(client):
    c, _ = new_customer(with_address=False)
    phone = unique_phone()
    body = {"fullName": "Nguyễn Thị Mai", "phone": "+84" + phone[1:], "dateOfBirth": "1995-05-20", "defaultRingSize": 10}
    res = c.patch("/api/profile", json=body)
    assert res.status_code == 200
    # +84 is stored as 0: one number has one spelling
    assert {k: v for k, v in res.get_json().items() if k != "email"} == {**body, "phone": phone}
    assert c.get("/api/profile").get_json()["dateOfBirth"] == "1995-05-20"
    assert c.get("/api/auth/me").get_json()["fullName"] == "Nguyễn Thị Mai"      # the login info sees the new name
    row = stored(c)
    assert row["FullName"] == "Nguyễn Thị Mai" and row["DefaultRingSize"] == 10 and row["UserUpdated"] is not None


@pytest.mark.parametrize("empty", [None, ""])
def test_optional_fields_can_be_cleared(client, empty):
    c, _ = new_customer(with_address=False)
    c.patch("/api/profile", json={"phone": unique_phone(), "dateOfBirth": "1990-01-01", "defaultRingSize": 9})
    res = c.patch("/api/profile", json={"phone": empty, "dateOfBirth": empty, "defaultRingSize": empty})
    assert res.status_code == 200
    assert (res.get_json()["phone"], res.get_json()["dateOfBirth"], res.get_json()["defaultRingSize"]) == (None, None, None)
    row = stored(c)
    assert (row["Phone"], row["DateOfBirth"], row["DefaultRingSize"]) == (None, None, None)


@pytest.mark.parametrize("bad", [
    {}, {"unknown": 1}, {"fullName": ""}, {"fullName": "   "}, {"fullName": None}, {"fullName": 5}, {"fullName": "x" * 101},
    {"phone": "12ab"}, {"phone": "12345678"}, {"phone": 5}, {"phone": ["0901234567"]}, {"phone": "0" * 16},
    {"dateOfBirth": "2999-01-01"}, {"dateOfBirth": date.today().isoformat()}, {"dateOfBirth": "2000-02-31"},
    {"dateOfBirth": "01/02/2000"}, {"dateOfBirth": 20000101}, {"dateOfBirth": "1899-12-31"}, {"dateOfBirth": "2000-1-1"},
    {"defaultRingSize": 99}, {"defaultRingSize": 0}, {"defaultRingSize": "10"}, {"defaultRingSize": True},
    {"defaultRingSize": 10.5}, {"defaultRingSize": -1},
])
def test_profile_validation(client, bad):
    c, _ = new_customer(with_address=False)
    assert c.patch("/api/profile", json=bad).status_code == 400
    assert c.get("/api/profile").get_json()["fullName"] == "Khách Test"


def test_one_bad_field_changes_nothing(client):
    c, _ = new_customer(with_address=False)
    assert c.patch("/api/profile", json={"fullName": "New Name", "phone": "bad"}).status_code == 400
    assert stored(c)["FullName"] == "Khách Test"


def test_email_and_role_cannot_be_changed_here(client):
    c, _ = new_customer(with_address=False)
    before = email_of(c)
    res = c.patch("/api/profile", json={"fullName": "Mai", "email": "hacker@example.test", "role": "Admin", "userId": 1})
    assert res.status_code == 200
    row = stored(c)
    assert row["Email"] == before and row["Role"] == "Customer" and email_of(c) == before


def test_non_object_body(client):
    c, _ = new_customer(with_address=False)
    for body in ([], "x", 5):
        assert c.patch("/api/profile", json=body).status_code == 400
    assert c.patch("/api/profile").status_code == 400


def test_profiles_are_private(client):
    a, _ = new_customer(with_address=False)
    b, _ = new_customer(with_address=False)
    a.patch("/api/profile", json={"fullName": "Only A"})
    assert b.get("/api/profile").get_json()["fullName"] == "Khách Test"


# ---------------- change password ----------------

def change(client, current=PASSWORD, new=NEW_PASSWORD):
    return client.post("/api/auth/change-password", json={"currentPassword": current, "newPassword": new})


def test_change_password_needs_login(client):
    assert change(client).status_code == 401


def test_change_password_end_to_end(client):
    c, _ = new_customer(with_address=False)
    email = email_of(c)
    assert change(c).status_code == 204
    assert c.get("/api/auth/me").status_code == 200                       # still logged in
    stored_hash = query("SELECT PasswordHash FROM dbo.Users WHERE Email = ?", (email,))[0]["PasswordHash"]
    assert stored_hash.startswith("$2b$") and NEW_PASSWORD not in stored_hash
    fresh = create_app().test_client()
    assert fresh.post("/api/auth/login", json={"email": email, "password": PASSWORD}).status_code == 401
    assert fresh.post("/api/auth/login", json={"email": email, "password": NEW_PASSWORD}).status_code == 200


def test_wrong_current_password_is_refused_and_nothing_changes(client):
    c, _ = new_customer(with_address=False)
    res = change(c, current="Wrong@Pass123")
    assert res.status_code == 403 and "wrong" in res.get_json()["error"]
    fresh = create_app().test_client()
    assert fresh.post("/api/auth/login", json={"email": email_of(c), "password": PASSWORD}).status_code == 200


@pytest.mark.parametrize("body", [
    {}, {"currentPassword": PASSWORD}, {"newPassword": NEW_PASSWORD}, {"currentPassword": "", "newPassword": NEW_PASSWORD},
    {"currentPassword": PASSWORD, "newPassword": "short"}, {"currentPassword": PASSWORD, "newPassword": "x" * 73},
    {"currentPassword": PASSWORD, "newPassword": None}, {"currentPassword": 5, "newPassword": NEW_PASSWORD},
    {"currentPassword": PASSWORD, "newPassword": ["a" * 9]}, {"currentPassword": None, "newPassword": NEW_PASSWORD},
])
def test_change_password_validation(client, body):
    c, _ = new_customer(with_address=False)
    assert c.post("/api/auth/change-password", json=body).status_code == 400
    fresh = create_app().test_client()
    assert fresh.post("/api/auth/login", json={"email": email_of(c), "password": PASSWORD}).status_code == 200


def test_admin_can_change_their_own_password(client):
    admin = create_app().test_client()
    email = f"pf-admin-{uuid.uuid4().hex[:8]}@example.test"
    make_user(email, role="Admin")
    admin.post("/api/auth/login", json={"email": email, "password": PASSWORD})
    assert change(admin).status_code == 204
    assert create_app().test_client().post("/api/auth/login", json={"email": email, "password": NEW_PASSWORD}).status_code == 200


# ---------------- edit and delete addresses ----------------

def add(client, **extra):
    res = client.post("/api/addresses", json={**ADDRESS, **extra})
    assert res.status_code == 201
    return res.get_json()["id"]


def listed(client):
    return {a["AddressID"]: a for a in client.get("/api/addresses").get_json()}


def test_edit_changes_only_the_sent_fields(client):
    c, first = new_customer()
    res = c.patch(f"/api/addresses/{first}", json={"phone": "0987654321", "ward": " Phường Mới "})
    assert res.status_code == 200
    got = res.get_json()
    assert (got["Phone"], got["Ward"]) == ("0987654321", "Phường Mới")
    assert (got["RecipientName"], got["AddressLine"], got["Province"]) == ("Khách Test", "1 Lê Lợi", "Thành phố Hồ Chí Minh")
    assert listed(c)[first]["Ward"] == "Phường Mới"


def test_make_an_address_the_default(client):
    c, first = new_customer()
    second = add(c)
    assert listed(c)[first]["IsDefault"] and not listed(c)[second]["IsDefault"]
    assert c.patch(f"/api/addresses/{second}", json={"isDefault": True}).get_json()["IsDefault"] is True
    now = listed(c)
    assert now[second]["IsDefault"] and not now[first]["IsDefault"]
    assert c.get("/api/addresses").get_json()[0]["AddressID"] == second        # the default is listed first
    # Asking again changes nothing.
    assert c.patch(f"/api/addresses/{second}", json={"isDefault": True}).status_code == 200


def test_the_default_cannot_be_switched_off_but_another_address_can_take_over(client):
    c, first = new_customer()
    second = add(c)
    assert c.patch(f"/api/addresses/{first}", json={"isDefault": False}).status_code == 400
    assert listed(c)[first]["IsDefault"]
    assert c.patch(f"/api/addresses/{second}", json={"isDefault": False}).status_code == 200    # already not the default
    assert not listed(c)[second]["IsDefault"]


@pytest.mark.parametrize("bad", [
    {}, {"unknown": 1}, {"phone": "12ab"}, {"recipientName": ""}, {"addressLine": "  "}, {"province": None}, {"ward": "x" * 101},
    {"addressLine": 5}, {"isDefault": "yes"}, {"isDefault": None}, {"isDefault": 1},
])
def test_edit_validation(client, bad):
    c, first = new_customer()
    before = listed(c)[first]
    assert c.patch(f"/api/addresses/{first}", json=bad).status_code == 400
    assert listed(c)[first] == before


def test_edit_keeps_the_full_address_within_400_characters(client):
    c, first = new_customer()
    # Each part is allowed on its own, but street + ward + province together must fit an order's address text.
    assert c.patch(f"/api/addresses/{first}", json={"province": "c" * 100}).status_code == 200
    res = c.patch(f"/api/addresses/{first}", json={"addressLine": "a" * 255, "ward": "b" * 100})   # adds up with the saved province
    assert res.status_code == 400
    assert listed(c)[first]["AddressLine"] == "1 Lê Lợi"


def test_one_bad_field_changes_no_field_of_the_address(client):
    c, first = new_customer()
    assert c.patch(f"/api/addresses/{first}", json={"ward": "Good", "phone": "bad"}).status_code == 400
    assert listed(c)[first]["Ward"] == "Phường Bến Thành"


def test_cannot_touch_another_customers_address(client):
    a, a_address = new_customer()
    b, _ = new_customer()
    assert b.patch(f"/api/addresses/{a_address}", json={"ward": "Hacked"}).status_code == 404
    assert b.delete(f"/api/addresses/{a_address}").status_code == 404
    assert listed(a)[a_address]["Ward"] == "Phường Bến Thành"


def test_editing_and_deleting_need_a_login(client):
    visitor = create_app().test_client()
    assert visitor.patch("/api/addresses/1", json={"ward": "x"}).status_code == 401
    assert visitor.delete("/api/addresses/1").status_code == 401


def test_unknown_address_is_404(client):
    c, _ = new_customer()
    too_big = 2 ** 63        # an id that does not fit the database driver must be a clean 404, not a crash
    assert c.patch(f"/api/addresses/{too_big}", json={"ward": "x"}).status_code == 404
    assert c.delete(f"/api/addresses/{too_big}").status_code == 404
    assert c.patch("/api/addresses/999999999", json={"ward": "x"}).status_code == 404
    assert c.delete("/api/addresses/999999999").status_code == 404


def test_delete_a_normal_address(client):
    c, first = new_customer()
    second = add(c)
    assert c.delete(f"/api/addresses/{second}").status_code == 204
    assert list(listed(c)) == [first] and listed(c)[first]["IsDefault"]
    assert c.delete(f"/api/addresses/{second}").status_code == 404


def test_deleting_the_default_promotes_the_oldest_remaining(client):
    c, first = new_customer()
    second, third = add(c), add(c)
    assert c.delete(f"/api/addresses/{first}").status_code == 204
    now = listed(c)
    assert list(now) == [second, third] or list(now) == [third, second]
    assert now[second]["IsDefault"] and not now[third]["IsDefault"]


def test_deleting_the_last_address_leaves_an_empty_book(client):
    c, first = new_customer()
    assert c.delete(f"/api/addresses/{first}").status_code == 204
    assert c.get("/api/addresses").get_json() == []
    new_first = add(c)                                       # the next one becomes the default again
    assert listed(c)[new_first]["IsDefault"]


def test_a_deleted_address_cannot_be_used_for_an_order_but_old_orders_keep_theirs(client):
    c, address = new_customer()
    c2, address2 = new_customer()
    for client_ in (c, c2):
        assert add_to_cart(client_, "BT161B-VT").status_code in (200, 201)
    done = checkout(c2, address2)
    assert done.status_code == 201
    done = done.get_json()
    assert c2.delete(f"/api/addresses/{address2}").status_code == 204
    shipped_to = query("SELECT ShipAddress FROM dbo.Orders WHERE OrderCode = ?", (done["OrderCode"],))[0]["ShipAddress"]
    assert "1 Lê Lợi" in shipped_to
    assert c.delete(f"/api/addresses/{address}").status_code == 204
    res = checkout(c, address)
    assert res.status_code == 400 and res.get_json()["code"] == 50011

