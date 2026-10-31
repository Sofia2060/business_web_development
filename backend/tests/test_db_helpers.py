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
