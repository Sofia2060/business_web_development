"""Tests for the recently viewed products of a customer (dbo.sp_TrackProductView)."""
import uuid

import pytest

from app import create_app
from app.db import query, transaction
from conftest import PASSWORD, make_user
from test_orders import new_customer

SKUS = ["NDINO131LDIA", "BT161B", "NC433"]    # three different products


def product_id(sku):
    return query("SELECT ProductID FROM dbo.Products WHERE SKU = ?", (sku,))[0]["ProductID"]


def customer_id(client):
    email = client.get("/api/auth/me").get_json()["email"]
    return query("SELECT c.CustomerID FROM dbo.Customers c JOIN dbo.Users u ON u.UserID = c.UserID "
                 "WHERE u.Email = ?", (email,))[0]["CustomerID"]


def view(client, sku):
    return client.post("/api/recently-viewed", json={"sku": sku})


def test_needs_a_customer_login(client):
    assert client.get("/api/recently-viewed").status_code == 401
    assert view(client, SKUS[0]).status_code == 401
    admin = create_app().test_client()
    email = f"rv-admin-{uuid.uuid4().hex[:8]}@example.test"
    make_user(email, role="Admin")
    admin.post("/api/auth/login", json={"email": email, "password": PASSWORD})
    assert admin.get("/api/recently-viewed").status_code == 403
    assert view(admin, SKUS[0]).status_code == 403


def test_a_viewed_product_shows_up_with_its_catalog_fields(client):
    c, _ = new_customer(with_address=False)
    assert c.get("/api/recently-viewed").get_json() == []
    assert view(c, SKUS[0]).status_code == 204
    items = c.get("/api/recently-viewed").get_json()
    assert [i["SKU"] for i in items] == [SKUS[0]]
    assert {"ProductName", "CurrentPrice", "ThumbnailUrl", "LastViewedAt"} <= items[0].keys()


def test_viewing_again_counts_but_lists_the_product_once(client):
    c, _ = new_customer(with_address=False)
    for _ in range(3):
        view(c, SKUS[0])
    assert len(c.get("/api/recently-viewed").get_json()) == 1
    row = query("SELECT ViewCount FROM dbo.RecentlyViewedProducts WHERE CustomerID = ? AND ProductID = ?",
                (customer_id(c), product_id(SKUS[0])))
    assert row[0]["ViewCount"] == 3


def test_newest_first_and_limit(client):
    c, _ = new_customer(with_address=False)
    cid = customer_id(c)
    for sku in SKUS:
        view(c, sku)
    # The time column keeps whole seconds, so set clear gaps: SKUS[1] is the newest, SKUS[2] the oldest.
    with transaction() as cur:
        for minutes, sku in ((-1, SKUS[1]), (-10, SKUS[0]), (-20, SKUS[2])):
            cur.execute("UPDATE dbo.RecentlyViewedProducts SET LastViewedAt = DATEADD(MINUTE, ?, SYSDATETIME()) "
                        "WHERE CustomerID = ? AND ProductID = ?", (minutes, cid, product_id(sku)))
    assert [i["SKU"] for i in c.get("/api/recently-viewed").get_json()] == [SKUS[1], SKUS[0], SKUS[2]]
    assert [i["SKU"] for i in c.get("/api/recently-viewed?limit=2").get_json()] == [SKUS[1], SKUS[0]]
    view(c, SKUS[2])     # viewing the oldest again moves it to the top
    assert c.get("/api/recently-viewed").get_json()[0]["SKU"] == SKUS[2]


def test_each_customer_sees_only_their_own_list(client):
    a, _ = new_customer(with_address=False)
    b, _ = new_customer(with_address=False)
    view(a, SKUS[0])
    assert b.get("/api/recently-viewed").get_json() == []


@pytest.mark.parametrize("qs", ["limit=0", "limit=-1", "limit=abc", "limit="])
def test_bad_limit(client, qs):
    c, _ = new_customer(with_address=False)
    assert c.get(f"/api/recently-viewed?{qs}").status_code == 400


def test_limit_is_capped_at_50(client):
    c, _ = new_customer(with_address=False)
    for sku in SKUS:
        view(c, sku)
    assert len(c.get("/api/recently-viewed?limit=100000").get_json()) == 3


@pytest.mark.parametrize("body", [{}, {"sku": ""}, {"sku": None}, {"sku": 5}, {"sku": ["x"]}, [], "x"])
def test_track_needs_a_sku_text(client, body):
    c, _ = new_customer(with_address=False)
    assert c.post("/api/recently-viewed", json=body).status_code == 400


def test_unknown_product_is_404_and_nothing_is_stored(client):
    c, _ = new_customer(with_address=False)
    assert view(c, "NO-SUCH-SKU").status_code == 404
    assert c.get("/api/recently-viewed").get_json() == []


def test_hidden_products_are_not_listed_or_tracked(client):
    c, _ = new_customer(with_address=False)
    view(c, SKUS[0])
    pid = product_id(SKUS[0])
    with transaction() as cur:
        cur.execute("UPDATE dbo.Products SET Status = 'Hidden' WHERE ProductID = ?", (pid,))
    try:
        assert c.get("/api/recently-viewed").get_json() == []
        assert view(c, SKUS[0]).status_code == 404
    finally:
        with transaction() as cur:
            cur.execute("UPDATE dbo.Products SET Status = 'Active' WHERE ProductID = ?", (pid,))
    assert len(c.get("/api/recently-viewed").get_json()) == 1
