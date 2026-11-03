"""Small helpers to run SQL queries and stored procedures against SQL Server."""
import re
from contextlib import closing, contextmanager
from datetime import date, datetime
from decimal import Decimal

import pyodbc

from .config import db_connection_string


class LockBusy(Exception):
    """Another request holds the lock this request needs and did not let go in time. The caller can try again."""


class ProcError(Exception):
    """A business rule error raised by a stored procedure with THROW (error numbers 50000 and up).
    `message` is the Vietnamese text written in the procedure, safe to show to the user."""

    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


# pyodbc error text looks like: "... [SQL Server]Giỏ hàng đang trống. (50012) (SQLExecDirectW)".
# The trailing "(SQL...)" is part of the pattern so other messages that happen to contain "(5xxxx)" do not match.
_PROC_ERROR = re.compile(r"\[SQL Server\](.*?) \((5\d{4})\) \(SQL\w+\)", re.S)
# SQL Server error 1205: "Transaction ... was deadlocked ... chosen as the deadlock victim. Rerun the transaction."
_DEADLOCK = re.compile(r"\(1205\) \(SQL\w+\)")
DEADLOCK_TRIES = 3


def _connect(autocommit: bool = False):
    """Open a connection. 5 seconds to log in, and a statement that waits on a lock gives up after 30 seconds."""
    conn = pyodbc.connect(db_connection_string(), timeout=5, autocommit=autocommit)
    conn.timeout = 30
    return conn


@contextmanager
def named_lock(name: str, wait_ms: int = 10_000):
    """Hold a SQL Server application lock while the block runs, so two requests for the same thing
    (for example two orders from the same phone number) run one after the other instead of at the same time.
    The lock belongs to a connection kept open for the block. It is released by name, because closing a pooled
    connection only gives it back to the pool and the session (with its lock) stays alive."""
    conn = _connect(autocommit=True)
    held = False
    try:
        got = conn.cursor().execute(
            "SET NOCOUNT ON; DECLARE @r INT; "
            "EXEC @r = sp_getapplock @Resource = ?, @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = ?; "
            "SELECT @r;", (name, wait_ms)).fetchval()
        if got < 0:
            raise LockBusy(name)
        held = True
        yield
    finally:
        try:
            if held:
                conn.cursor().execute("EXEC sp_releaseapplock @Resource = ?, @LockOwner = 'Session'", (name,))
        finally:
            conn.close()


def _clean(value):
    # DECIMAL columns come back as Decimal. Whole prices become int, others float,
    # so the JSON output holds plain numbers instead of strings. Dates become ISO text.
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, datetime):
        # SQL Server gives local time without a zone. Add this machine's offset (the database and the app run in the
        # same zone) so a browser in another zone still reads the right moment, for example the payment deadline.
        try:
            return value.astimezone().isoformat()
        except (OSError, OverflowError, ValueError):    # a date the operating system cannot place in a zone
            return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    return value


def _rows(cursor) -> list[dict]:
    names = [col[0] for col in cursor.description]
    return [{n: _clean(v) for n, v in zip(names, row)} for row in cursor.fetchall()]


def query(sql: str, params: tuple = ()) -> list[dict]:
    """Run a SELECT and return every row as a dict {column name: value}."""
    with closing(_connect()) as conn:
        cursor = conn.cursor()
        cursor.execute(sql, params)
        return _rows(cursor)


@contextmanager
def transaction():
    """Yield a cursor for writes. Commits when the block ends, rolls back on any error."""
    conn = _connect()
    try:
        yield conn.cursor()
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def call(sql: str, params: tuple = (), actor: tuple[int, str] | None = None) -> list[dict]:
    """Run a T-SQL batch that calls stored procedures and return the first result set (if any).

    The procedures open and commit their own transactions, so this uses autocommit.
    `actor` is (user id, label) and goes into the session context, which the procedures
    and triggers write to AuditLogs. A THROW from a procedure becomes ProcError.
    When SQL Server picks this request as the victim of a deadlock (two requests waiting for each other),
    its transaction is rolled back completely, so the call is simply run again (up to 3 tries).
    """
    for attempt in range(DEADLOCK_TRIES):
        try:
            return _call_once(sql, params, actor)
        except pyodbc.Error as exc:
            if attempt == DEADLOCK_TRIES - 1 or not _DEADLOCK.search(str(exc)):
                raise
    raise AssertionError("unreachable")


def _call_once(sql: str, params: tuple, actor: tuple[int, str] | None) -> list[dict]:
    with closing(_connect(autocommit=True)) as conn:
        cursor = conn.cursor()
        try:
            if actor:
                cursor.execute("EXEC sp_set_session_context @key = N'UserID', @value = ?", (actor[0],))
                cursor.execute("EXEC sp_set_session_context @key = N'Actor', @value = ?", (actor[1],))
            cursor.execute("SET NOCOUNT ON;\n" + sql, params)
            while cursor.description is None:  # skip results that return no rows
                if not cursor.nextset():
                    return []
            return _rows(cursor)
        except pyodbc.Error as exc:
            match = _PROC_ERROR.search(str(exc))
            if match:
                raise ProcError(int(match.group(2)), match.group(1).strip()) from exc
            raise
