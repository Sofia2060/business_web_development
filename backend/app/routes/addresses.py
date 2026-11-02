"""Delivery address book of the logged-in customer."""
from flask import Blueprint, g, jsonify

from ..auth import customer_required
from ..db import query, transaction
from ..validation import INT_MAX, body, normalize_phone, text, utf16_len

bp = Blueprint("addresses", __name__, url_prefix="/api/addresses")

# body field name -> maximum length in UTF-16 units (the column size)
LIMITS = {"recipientName": 100, "addressLine": 255, "ward": 100, "province": 100}
COLUMNS = {"recipientName": "RecipientName", "phone": "Phone", "addressLine": "AddressLine",
           "ward": "Ward", "province": "Province"}
MAX_FULL_ADDRESS = 400  # size of Orders.ShipAddress
SELECT_ADDRESS = ("SELECT AddressID, RecipientName, Phone, AddressLine, Ward, Province, IsDefault "
                  "FROM dbo.CustomerAddresses")


def read_fields(data: dict, keys) -> tuple[dict | None, str | None]:
    """The given body fields, stripped, and an error message when one is not valid."""
    fields = {}
    for key in keys:
        value = text(data, key)
        if value is None:
            return None, "All fields must be plain text"
        fields[key] = value.strip()
    for key, limit in LIMITS.items():
        if key in fields and (not fields[key] or utf16_len(fields[key]) > limit):
            return None, f"{key} is required (max {limit} characters)"
    if "phone" in fields:
        fields["phone"] = normalize_phone(fields["phone"])
        if fields["phone"] is None:
            return None, "Invalid phone number"
    return fields, None


def full_address_error(line: str, ward: str, province: str) -> str | None:
    # An order copies the address into one 400-character text, so a longer address would be cut off.
    if utf16_len(f"{line}, {ward}, {province}") > MAX_FULL_ADDRESS:
        return f"The full address (street, ward, province) is limited to {MAX_FULL_ADDRESS} characters"
    return None


@bp.get("")
@customer_required
def list_addresses():
    return jsonify(query(f"{SELECT_ADDRESS} WHERE CustomerID = ? ORDER BY IsDefault DESC, AddressID", (g.customer_id,)))


@bp.post("")
@customer_required
def add_address():
    """Add an address. The first address is always the default. isDefault=true makes this one the default."""
    data = body()
    fields, error = read_fields(data, (*LIMITS, "phone"))
    if not error:
        error = full_address_error(fields["addressLine"], fields["ward"], fields["province"])
    if not error and not isinstance(data.get("isDefault", False), bool):
        error = "isDefault must be true or false"
    if error:
        return jsonify(error=error), 400

    with transaction() as cur:
        has_any = cur.execute("SELECT 1 FROM dbo.CustomerAddresses WHERE CustomerID = ?", (g.customer_id,)).fetchone()
        make_default = data.get("isDefault", False) or not has_any
        if make_default:  # the database allows only one default address per customer
            cur.execute("UPDATE dbo.CustomerAddresses SET IsDefault = 0 WHERE CustomerID = ?", (g.customer_id,))
        cur.execute(
            "INSERT INTO dbo.CustomerAddresses (CustomerID, RecipientName, Phone, AddressLine, Ward, Province, IsDefault) "
            "OUTPUT INSERTED.AddressID VALUES (?, ?, ?, ?, ?, ?, ?)",
            (g.customer_id, fields["recipientName"], fields["phone"], fields["addressLine"],
             fields["ward"], fields["province"], 1 if make_default else 0))
        address_id = cur.fetchval()
    return jsonify(id=address_id, isDefault=bool(make_default)), 201


@bp.patch("/<int:address_id>")
@customer_required
def edit_address(address_id: int):
    """Change only the fields in the body. isDefault=true makes this the default address.
    The default address cannot be switched off: make another address the default instead."""
    if address_id > INT_MAX:    # larger than any real id, and too big for the database driver
        return jsonify(error="Address not found"), 404
    data = body()
    keys = [key for key in (*LIMITS, "phone") if key in data]
    if not keys and "isDefault" not in data:
        return jsonify(error="Send at least one field to change"), 400
    if "isDefault" in data and not isinstance(data["isDefault"], bool):
        return jsonify(error="isDefault must be true or false"), 400
    fields, error = read_fields(data, keys)
    if error:
        return jsonify(error=error), 400

    with transaction() as cur:
        current = cur.execute(f"{SELECT_ADDRESS} WHERE AddressID = ? AND CustomerID = ?",
                              (address_id, g.customer_id)).fetchone()
        if current is None:
            return jsonify(error="Address not found"), 404
        merged = {"addressLine": current.AddressLine, "ward": current.Ward, "province": current.Province, **fields}
        error = full_address_error(merged["addressLine"], merged["ward"], merged["province"])
        if not error and data.get("isDefault") is False and current.IsDefault:
            error = "Make another address the default instead"
        if error:
            return jsonify(error=error), 400
        if fields:  # column names come from the fixed COLUMNS table, never from the request
            sets = ", ".join(f"{COLUMNS[key]} = ?" for key in fields)
            cur.execute(f"UPDATE dbo.CustomerAddresses SET {sets} WHERE AddressID = ?", (*fields.values(), address_id))
        if data.get("isDefault") is True and not current.IsDefault:
            cur.execute("UPDATE dbo.CustomerAddresses SET IsDefault = 0 WHERE CustomerID = ?", (g.customer_id,))
            cur.execute("UPDATE dbo.CustomerAddresses SET IsDefault = 1 WHERE AddressID = ?", (address_id,))
    rows = query(f"{SELECT_ADDRESS} WHERE AddressID = ?", (address_id,))
    return jsonify(rows[0]) if rows else (jsonify(error="Address not found"), 404)   # deleted by a request that ran at the same time


@bp.delete("/<int:address_id>")
@customer_required
def delete_address(address_id: int):
    """Delete an address. Past orders keep their own copy of the address. If the default one is deleted,
    the oldest remaining address becomes the default."""
    if address_id > INT_MAX:
        return jsonify(error="Address not found"), 404
    with transaction() as cur:
        current = cur.execute("SELECT IsDefault FROM dbo.CustomerAddresses WHERE AddressID = ? AND CustomerID = ?",
                              (address_id, g.customer_id)).fetchone()
        if current is None:
            return jsonify(error="Address not found"), 404
        cur.execute("DELETE FROM dbo.CustomerAddresses WHERE AddressID = ?", (address_id,))
        if current.IsDefault:
            cur.execute(
                "UPDATE dbo.CustomerAddresses SET IsDefault = 1 WHERE AddressID = "
                "(SELECT TOP (1) AddressID FROM dbo.CustomerAddresses WHERE CustomerID = ? ORDER BY AddressID)",
                (g.customer_id,))
    return "", 204
