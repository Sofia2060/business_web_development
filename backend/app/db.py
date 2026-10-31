"""Small helpers to run SQL queries and get rows back as dictionaries."""
from contextlib import closing, contextmanager
from decimal import Decimal

import pyodbc

from .config import db_connection_string


def _clean(value):
    # DECIMAL columns come back as Decimal. Whole prices become int, others float,
    # so the JSON output holds plain numbers instead of strings.
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    return value


def query(sql: str, params: tuple = ()) -> list[dict]:
    """Run a SELECT and return every row as a dict {column name: value}."""
    with closing(pyodbc.connect(db_connection_string(), timeout=5)) as conn:
        cursor = conn.cursor()
        cursor.execute(sql, params)
        names = [col[0] for col in cursor.description]
        return [{n: _clean(v) for n, v in zip(names, row)} for row in cursor.fetchall()]


@contextmanager
def transaction():
    """Yield a cursor for writes. Commits when the block ends, rolls back on any error."""
    conn = pyodbc.connect(db_connection_string(), timeout=5, autocommit=False)
    try:
        yield conn.cursor()
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
