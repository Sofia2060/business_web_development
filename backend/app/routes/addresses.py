"""Delivery address book of the logged-in customer."""
import re

from flask import Blueprint, g, jsonify

from ..auth import customer_required
from ..db import query, transaction
from ..validation import body, text, utf16_len

bp = Blueprint("addresses", __name__, url_prefix="/api/addresses")

PHONE_RE = re.compile(r"^[0-9+]{9,15}$")  # same rule as the CustomerAddresses.Phone CHECK constraint
# body field name -> maximum length in UTF-16 units (the column size)
LIMITS = {"recipientName": 100, "addressLine": 255, "ward": 100, "province": 100}
MAX_FULL_ADDRESS = 400  # size of Orders.ShipAddress


@bp.get("")
@customer_required
def list_addresses():
    return jsonify(query(
        "SELECT AddressID, RecipientName, Phone, AddressLine, Ward, Province, IsDefault "
        "FROM dbo.CustomerAddresses WHERE CustomerID = ? ORDER BY IsDefault DESC, AddressID", (g.customer_id,)))


@bp.post("")
@customer_required
def add_address():
    """Add an address. The first address is always the default. isDefault=true makes this one the default."""
    data = body()
    fields = {key: text(data, key) for key in (*LIMITS, "phone")}
    if None in fields.values():
        return jsonify(error="All fields must be plain text"), 400
    fields = {key: value.strip() for key, value in fields.items()}
    for key, limit in LIMITS.items():
        if not fields[key] or utf16_len(fields[key]) > limit:
            return jsonify(error=f"{key} is required (max {limit} characters)"), 400
    if not PHONE_RE.match(fields["phone"]):
        return jsonify(error="Invalid phone number"), 400
    # An order copies the address into one 400-character text, so a longer address would be cut off.
    full = f"{fields['addressLine']}, {fields['ward']}, {fields['province']}"
    if utf16_len(full) > MAX_FULL_ADDRESS:
        return jsonify(error=f"The full address (street, ward, province) is limited to {MAX_FULL_ADDRESS} characters"), 400
    if not isinstance(data.get("isDefault", False), bool):
        return jsonify(error="isDefault must be true or false"), 400

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
