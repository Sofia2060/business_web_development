"""Unit tests for small helpers. They do not need the database."""
import pytest

from app.db import _PROC_ERROR
from app.validation import page_number


def test_proc_error_is_read_from_a_pyodbc_message():
    msg = ("('42000', '[42000] [Microsoft][ODBC Driver 18 for SQL Server][SQL Server]"
           "Giỏ hàng đang trống. (50012) (SQLExecDirectW)')")
    match = _PROC_ERROR.search(msg)
    assert match.group(1).strip() == "Giỏ hàng đang trống." and match.group(2) == "50012"


def test_proc_error_ignores_other_messages_that_contain_a_number():
    msg = ("('23000', '[23000] [Microsoft][ODBC Driver 18 for SQL Server][SQL Server]"
           "Violation of UNIQUE KEY constraint. The duplicate key value is (51234). (2627) (SQLExecDirectW)')")
    assert _PROC_ERROR.search(msg) is None


@pytest.mark.parametrize("raw,expected", [(None, 7), ("1", 1), ("0", 0), ("123456", 123456),
                                          ("1234567", None), ("-1", None), ("1.5", None), ("²", None), ("", None), ("٣", None)])
def test_page_number(raw, expected):
    assert page_number(raw, 7) == expected


# ---------------- deadlock retry ----------------

DEADLOCK = ("40001", "[40001] [Microsoft][ODBC Driver 18 for SQL Server][SQL Server]Transaction (Process ID 78) was "
                     "deadlocked on lock resources with another process and has been chosen as the deadlock victim. "
                     "Rerun the transaction. (1205) (SQLExecDirectW)")


def fake_call_once(monkeypatch, failures, error=DEADLOCK):
    """Make _call_once fail `failures` times with `error`, then answer. Returns the list of attempts."""
    import pyodbc
    from app import db
    attempts = []

    def once(sql, params, actor):
        attempts.append(1)
        if len(attempts) <= failures:
            raise pyodbc.Error(*error)
        return [{"ok": 1}]

    monkeypatch.setattr(db, "_call_once", once)
    return attempts


def test_call_runs_again_after_a_deadlock(monkeypatch):
    from app.db import call
    attempts = fake_call_once(monkeypatch, failures=2)
    assert call("EXEC anything") == [{"ok": 1}] and len(attempts) == 3


def test_call_gives_up_after_three_deadlocks(monkeypatch):
    import pyodbc
    from app.db import call
    attempts = fake_call_once(monkeypatch, failures=5)
    with pytest.raises(pyodbc.Error):
        call("EXEC anything")
    assert len(attempts) == 3


def test_call_does_not_repeat_other_database_errors(monkeypatch):
    import pyodbc
    from app.db import call
    attempts = fake_call_once(monkeypatch, failures=5, error=("23000", "[23000] duplicate key (2627) (SQLExecDirectW)"))
    with pytest.raises(pyodbc.Error):
        call("EXEC anything")
    assert len(attempts) == 1


# ---------------- phone numbers and the named lock ----------------

@pytest.mark.parametrize("raw,stored", [
    ("0901234567", "0901234567"), ("  0901234567 ", "0901234567"), ("+84901234567", "0901234567"),
    ("84901234567", "0901234567"), ("0084901234567", "0901234567"), ("+840901234567", "0901234567"),
    ("+14155551234", "+14155551234"), ("123456789", "123456789"), ("1" * 15, "1" * 15),
])
def test_one_phone_number_has_one_spelling(raw, stored):
    from app.validation import normalize_phone
    assert normalize_phone(raw) == stored


@pytest.mark.parametrize("raw", ["", "abc", "12345678", "0" * 16, "090 123 4567", "0901+234567", "++84901234567",
                                 "+84123", "０９０１２３４５６７", "0901234567\n9"])
def test_invalid_phone_numbers(raw):
    from app.validation import normalize_phone
    assert normalize_phone(raw) is None


def test_named_lock_makes_a_second_holder_wait_and_then_give_up(db_ready):
    from app.db import LockBusy, named_lock
    with named_lock("pytest-lock-1"):
        with pytest.raises(LockBusy):
            with named_lock("pytest-lock-1", wait_ms=200):
                pass
        with named_lock("pytest-lock-2", wait_ms=200):     # another name is not blocked
            pass
    with named_lock("pytest-lock-1", wait_ms=200):          # free again once the first holder is done
        pass


def test_dates_from_the_database_carry_the_zone_of_this_machine():
    # SQL Server gives local time with no zone; the API adds the offset so a browser elsewhere reads the same moment.
    from datetime import date, datetime

    from app.db import _clean
    moment = datetime(2026, 11, 3, 14, 15, 0)
    text = _clean(moment)
    assert text == moment.astimezone().isoformat()
    assert datetime.fromisoformat(text).utcoffset() == moment.astimezone().utcoffset()
    assert datetime.fromisoformat(text).replace(tzinfo=None) == moment           # the wall clock time is unchanged
    assert _clean(date(2000, 1, 31)) == "2000-01-31"                              # a plain date stays a plain date
    assert _clean(datetime(1900, 1, 1)).startswith("1900-01-01T00:00:00")         # never fails, even for very old dates
