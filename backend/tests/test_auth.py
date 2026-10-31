"""Integration tests for register, login, logout, me and the admin permission.
Accounts created here use emails like pytest-*@example.test and are removed after each test."""
import pytest

from app.db import query
from conftest import PASSWORD, make_user

EMAIL = "pytest-user@example.test"
ADMIN = "pytest-admin@example.test"


def register(client, **overrides):
    body = {"fullName": "Nguyễn Test", "email": EMAIL, "password": PASSWORD, "phone": "0901234567"}
    body.update(overrides)
    return client.post("/api/auth/register", json=body)


def login(client, email=EMAIL, password=PASSWORD):
    return client.post("/api/auth/login", json={"email": email, "password": password})


# ---------- register ----------

def test_register_creates_customer_and_logs_in(client, clean_users):
    res = register(client)
    assert res.status_code == 201
    assert res.get_json()["role"] == "Customer"
    assert client.get("/api/auth/me").get_json()["email"] == EMAIL
    row = query("SELECT c.Phone FROM dbo.Customers c JOIN dbo.Users u ON u.UserID = c.UserID WHERE u.Email = ?",
                (EMAIL,))
    assert row[0]["Phone"] == "0901234567"


def test_register_stores_a_bcrypt_hash_and_never_returns_it(client, clean_users):
    res = register(client)
    assert "assword" not in res.get_data(as_text=True)
    stored = query("SELECT PasswordHash FROM dbo.Users WHERE Email = ?", (EMAIL,))[0]["PasswordHash"]
    assert stored.startswith("$2b$") and stored != PASSWORD


def test_register_ignores_role_in_body(client, clean_users):
    res = register(client, role="Admin")
    assert res.get_json()["role"] == "Customer"
    assert client.get("/api/admin/users").status_code == 403


def test_register_duplicate_email_is_409(client, clean_users):
    assert register(client).status_code == 201
    assert register(client, email=EMAIL.upper()).status_code == 409  # emails are case-insensitive


@pytest.mark.parametrize("overrides", [
    {"email": "not-an-email"},
    {"email": ""},
    {"password": "short"},
    {"password": "x" * 73},
    {"fullName": "   "},
    {"phone": "12ab"},
    {"phone": "123"},
])
def test_register_invalid_input_is_400(client, clean_users, overrides):
    assert register(client, **overrides).status_code == 400


def test_register_without_json_is_400(client, clean_users):
    assert client.post("/api/auth/register", data="plain text").status_code == 400


# ---------- login / logout / me ----------

def test_login_success_sets_session_and_last_login(client, clean_users):
    register(client)
    client.post("/api/auth/logout")
    res = login(client)
    assert res.status_code == 200 and res.get_json()["email"] == EMAIL
    assert client.get("/api/auth/me").status_code == 200
    last = query("SELECT LastLoginAt FROM dbo.Users WHERE Email = ?", (EMAIL,))[0]["LastLoginAt"]
    assert last is not None


def test_login_wrong_password_and_unknown_email_look_the_same(client, clean_users):
    register(client)
    client.post("/api/auth/logout")
    wrong = login(client, password="Wrong@12345")
    unknown = login(client, email="pytest-nobody@example.test")
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.get_json() == unknown.get_json()
    assert client.get("/api/auth/me").status_code == 401


def test_login_email_is_case_insensitive(client, clean_users):
    register(client)
    assert login(client, email=EMAIL.upper()).status_code == 200


def test_login_missing_fields_is_401(client, clean_users):
    assert client.post("/api/auth/login", json={}).status_code == 401


def test_sample_account_with_fake_hash_cannot_log_in(client):
    # The seed data holds placeholder hashes. They must fail cleanly, not crash with a 500.
    assert login(client, email="minhanh@example.com", password="anything-at-all").status_code == 401


def test_disabled_account_is_403(client, clean_users):
    make_user(EMAIL, active=False)
    assert login(client).status_code == 403


def test_account_disabled_after_login_loses_access(client, clean_users):
    register(client)
    assert client.get("/api/auth/me").status_code == 200
    from app.db import transaction
    with transaction() as cur:
        cur.execute("UPDATE dbo.Users SET IsActive = 0 WHERE Email = ?", (EMAIL,))
    assert client.get("/api/auth/me").status_code == 401


def test_logout_clears_session(client, clean_users):
    register(client)
    assert client.post("/api/auth/logout").status_code == 204
    assert client.get("/api/auth/me").status_code == 401


def test_me_without_login_is_401(client):
    assert client.get("/api/auth/me").status_code == 401


def test_forged_cookie_is_rejected(client):
    client.set_cookie("session", "eyJ1c2VyX2lkIjoxfQ.forged.signature")
    assert client.get("/api/auth/me").status_code == 401


# ---------- permission ----------

def test_admin_users_requires_login(client):
    assert client.get("/api/admin/users").status_code == 401


def test_admin_users_forbidden_for_customer(client, clean_users):
    register(client)
    assert client.get("/api/admin/users").status_code == 403


def test_admin_users_allowed_for_admin(client, clean_users):
    make_user(ADMIN, role="Admin")
    assert login(client, email=ADMIN).status_code == 200
    res = client.get("/api/admin/users")
    assert res.status_code == 200
    users = res.get_json()
    assert any(u["Email"] == ADMIN and u["Role"] == "Admin" for u in users)
    assert not any("PasswordHash" in u for u in users)


# ---------- null and odd JSON values ----------

def test_register_phone_null_is_allowed(client, clean_users):
    assert register(client, phone=None).status_code == 201


@pytest.mark.parametrize("overrides", [{"fullName": None}, {"email": None}, {"password": None}])
def test_register_null_required_field_is_400(client, clean_users, overrides):
    assert register(client, **overrides).status_code == 400


@pytest.mark.parametrize("body", [[1, 2], "text", 5, None])
def test_non_object_json_body_does_not_crash(client, body):
    assert client.post("/api/auth/register", json=body).status_code == 400
    assert client.post("/api/auth/login", json=body).status_code == 401


# ---------- hardening cases found in code review ----------

@pytest.mark.parametrize("overrides", [
    {"email": ["a@b.co"]},
    {"password": 12345678},
    {"phone": 901234567},
    {"fullName": ["Nam"]},
    {"email": "é@example.test"},
    {"fullName": "😀" * 60},  # 120 UTF-16 units, over the NVARCHAR(100) column
])
def test_register_rejects_wrong_types_and_oversized_values(client, clean_users, overrides):
    assert register(client, **overrides).status_code == 400


def test_register_emoji_name_within_limit(client, clean_users):
    assert register(client, fullName="😀" * 50).status_code == 201


def test_lone_surrogate_gives_400_not_500(client, clean_users):
    body = rb'{"fullName":"X","email":"pytest-s@example.test","password":"\ud800abcdefg"}'
    assert client.post("/api/auth/register", data=body, content_type="application/json").status_code == 400
    body = rb'{"email":"\ud800","password":"abcdefgh"}'
    assert client.post("/api/auth/login", data=body, content_type="application/json").status_code == 401


def test_nul_character_in_password_does_not_crash(client, clean_users):
    res = register(client, password="abcdefg\x00h")
    assert res.status_code in (201, 400)
    if res.status_code == 201:
        client.post("/api/auth/logout")
        assert login(client, password="abcdefg\x00h").status_code == 200
        assert login(client, password="abcdefg").status_code == 401  # nothing after NUL is silently dropped


def test_huge_email_is_rejected_fast(client, clean_users):
    import time
    start = time.time()
    res = register(client, email="a@" + "a." * 3000 + "@")
    assert res.status_code == 400 and time.time() - start < 2


def test_oversized_body_is_413(client):
    assert client.post("/api/auth/login", json={"email": "x" * 20000, "password": "y"}).status_code == 413
