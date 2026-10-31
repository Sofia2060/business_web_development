import os

import pytest

os.environ.setdefault("SECRET_KEY", "test-secret-not-for-production-0123456789")

from app import create_app
from app.auth import hash_password
from app.db import query, transaction

TEST_EMAIL_LIKE = "pytest-%@example.test"
PASSWORD = "Test@12345"


def delete_test_users():
    with transaction() as cur:
        cur.execute("DELETE FROM dbo.Customers WHERE UserID IN (SELECT UserID FROM dbo.Users WHERE Email LIKE ?)",
                    (TEST_EMAIL_LIKE,))
        cur.execute("DELETE FROM dbo.Users WHERE Email LIKE ?", (TEST_EMAIL_LIKE,))


@pytest.fixture(scope="session")
def db_ready():
    try:
        query("SELECT 1 AS ok")
    except Exception:
        pytest.skip("SQL Server database VinoraJewelry is not reachable")


@pytest.fixture
def client(db_ready):
    return create_app().test_client()


@pytest.fixture
def clean_users(db_ready):
    """Remove the accounts a test created, before and after it runs."""
    delete_test_users()
    yield
    delete_test_users()


def make_user(email, role="Customer", active=True, password=PASSWORD):
    """Insert a user straight into the database (bypassing the API)."""
    with transaction() as cur:
        cur.execute(
            "INSERT INTO dbo.Users (FullName, Email, PasswordHash, Role, IsActive) VALUES (?, ?, ?, ?, ?)",
            (f"Test {role}", email, hash_password(password), role, 1 if active else 0),
        )
