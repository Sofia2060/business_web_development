"""Helpers to read and check JSON request bodies."""
import re

from flask import request

INT_MAX = 2_147_483_647  # largest value of a SQL Server INT column
_NUMBER = re.compile(r"[0-9]{1,6}")  # ASCII digits only, short enough that page * limit cannot overflow


def body() -> dict:
    """The JSON body if it is an object, otherwise an empty dict (so a list or text body gives a clean 400/401)."""
    try:
        data = request.get_json(silent=True)
    except RecursionError:  # a body such as [[[[...]]]] nested thousands of levels deep
        return {}
    return data if isinstance(data, dict) else {}


def page_number(raw: str | None, default: int) -> int | None:
    """A query-string number such as page or limit. None when it is not a plain whole number."""
    if raw is None:
        return default
    return int(raw) if _NUMBER.fullmatch(raw) else None


def text(data: dict, key: str) -> str | None:
    """A body field as text. Missing or null gives "". Returns None when the value is not
    a string (number, list...) or cannot be encoded as UTF-8 (lone surrogate), so the caller can reject it."""
    value = data.get(key)
    if value is None:
        return ""
    if not isinstance(value, str):
        return None
    try:
        value.encode()
    except UnicodeEncodeError:
        return None
    return value


def utf16_len(value: str) -> int:
    """Length as SQL Server counts NVARCHAR: UTF-16 units, so an emoji counts as 2."""
    return len(value.encode("utf-16-le")) // 2


def is_int(value, minimum: int = 1, maximum: int | None = None) -> bool:
    """True for a real JSON integer in range (booleans are not accepted)."""
    return (isinstance(value, int) and not isinstance(value, bool) and value >= minimum
            and (maximum is None or value <= maximum))
