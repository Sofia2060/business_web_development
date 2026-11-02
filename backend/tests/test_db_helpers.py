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
