"""Profile of the logged-in customer: name, phone, birth date and default ring size."""
import re
from datetime import date

from flask import Blueprint, g, jsonify

from ..auth import customer_required
from ..db import query, transaction
from ..validation import body, is_int, text, utf16_len

bp = Blueprint("profile", __name__, url_prefix="/api/profile")

PHONE_RE = re.compile(r"^[0-9+]{9,15}$")  # same rule as the Customers.Phone CHECK constraint
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
EARLIEST_BIRTH = date(1900, 1, 1)
FIELDS = ("fullName", "phone", "dateOfBirth", "defaultRingSize")


def _read(customer_id: int) -> dict:
    row = query(
        "SELECT u.FullName, u.Email, c.Phone, c.DateOfBirth, c.DefaultRingSize FROM dbo.Customers c "
        "JOIN dbo.Users u ON u.UserID = c.UserID WHERE c.CustomerID = ?", (customer_id,))[0]
    return {"fullName": row["FullName"], "email": row["Email"], "phone": row["Phone"],
            "dateOfBirth": row["DateOfBirth"], "defaultRingSize": row["DefaultRingSize"]}


@bp.get("")
@customer_required
def get_profile():
    return jsonify(_read(g.customer_id))


@bp.patch("")
@customer_required
def update_profile():
    """Change only the fields that are in the body. For phone, dateOfBirth and defaultRingSize,
    null or "" clears the value. The email cannot be changed here."""
    data = body()
    changes = {key: data[key] for key in FIELDS if key in data}
    if not changes:
        return jsonify(error=f"Send at least one of: {', '.join(FIELDS)}"), 400

    columns = {}  # column name -> new value, split below between Users and Customers
    if "fullName" in changes:
        name = text(changes, "fullName")
        name = name.strip() if name is not None else ""
        if not name or utf16_len(name) > 100:
            return jsonify(error="fullName is required (max 100 characters)"), 400
        columns["FullName"] = name
    if "phone" in changes:
        phone = text(changes, "phone")
        phone = phone.strip() if phone is not None else None
        if phone is None or (phone and not PHONE_RE.match(phone)):
            return jsonify(error="Invalid phone number"), 400
        columns["Phone"] = phone or None
    if "dateOfBirth" in changes:
        raw = changes["dateOfBirth"]
        if raw in (None, ""):
            columns["DateOfBirth"] = None
        else:
            try:
                born = date.fromisoformat(raw) if isinstance(raw, str) and DATE_RE.match(raw) else None
            except ValueError:  # such as 2000-02-31
                born = None
            if born is None or not EARLIEST_BIRTH <= born < date.today():
                return jsonify(error="dateOfBirth must be a past date written as YYYY-MM-DD"), 400
            columns["DateOfBirth"] = born
    if "defaultRingSize" in changes:
        size = changes["defaultRingSize"]
        if size in (None, ""):
            columns["DefaultRingSize"] = None
        elif not is_int(size, 1, 255) or not query("SELECT 1 AS x FROM dbo.RingSizeChart WHERE SizeVN = ?", (size,)):
            return jsonify(error="defaultRingSize must be a size from the ring size chart"), 400
        else:
            columns["DefaultRingSize"] = size

    with transaction() as cur:
        if "FullName" in columns:
            cur.execute("UPDATE dbo.Users SET FullName = ?, UpdatedAt = SYSDATETIME() WHERE UserID = ?",
                        (columns["FullName"], g.user["UserID"]))
        customer_columns = {k: v for k, v in columns.items() if k != "FullName"}
        if customer_columns:
            # Column names come from the fixed keys above, never from the request.
            sets = ", ".join(f"{name} = ?" for name in customer_columns)
            cur.execute(f"UPDATE dbo.Customers SET {sets}, UpdatedAt = SYSDATETIME() WHERE CustomerID = ?",
                        (*customer_columns.values(), g.customer_id))
    return jsonify(_read(g.customer_id))
