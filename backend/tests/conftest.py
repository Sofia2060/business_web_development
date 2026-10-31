import glob
import os
import re
from contextlib import closing
from pathlib import Path

import pyodbc
import pytest

# Tests run on their own database, rebuilt from database/01_*.sql, so the dev data is never touched.
TEST_DB = "VinoraJewelry_Test"
os.environ["DB_NAME"] = TEST_DB
os.environ.setdefault("SECRET_KEY", "test-secret-not-for-production-0123456789")

from app import create_app
from app.auth import hash_password
from app.config import db_connection_string
from app.db import query, transaction

TEST_EMAIL_LIKE = "pytest-%@example.test"
PASSWORD = "Test@12345"
SCHEMA_SCRIPT = sorted(glob.glob(str(Path(__file__).resolve().parents[2] / "database" / "01_*.sql")))[0]


def _build_test_database():
    """Run the schema script against a database named VinoraJewelry_Test. The script drops it first."""
    sql = Path(SCHEMA_SCRIPT).read_text(encoding="utf-8-sig")
    sql = re.sub(r"\bVinoraJewelry\b", TEST_DB, sql)
    batches = [b for b in re.split(r"^\s*GO\s*$", sql, flags=re.M | re.I) if b.strip()]
    master = db_connection_string().replace(f"DATABASE={TEST_DB}", "DATABASE=master")
    with closing(pyodbc.connect(master, timeout=10, autocommit=True)) as conn:
        for batch in batches:
            cursor = conn.cursor()
            cursor.execute(batch)
            while cursor.nextset():  # a batch can hold several statements, run them all
                pass


@pytest.fixture(scope="session")
def db_ready():
    try:
        _build_test_database()
    except Exception as exc:
        pytest.skip(f"Cannot build the test database on SQL Server: {exc}")


@pytest.fixture
def client(db_ready):
    return create_app().test_client()


def delete_test_users():
    with transaction() as cur:
        cur.execute("DELETE FROM dbo.Customers WHERE UserID IN (SELECT UserID FROM dbo.Users WHERE Email LIKE ?)",
                    (TEST_EMAIL_LIKE,))
        cur.execute("DELETE FROM dbo.Users WHERE Email LIKE ?", (TEST_EMAIL_LIKE,))


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
