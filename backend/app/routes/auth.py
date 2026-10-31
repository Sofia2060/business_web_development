"""Register, login, logout and "who am I" endpoints. The login lives in a signed session cookie."""
import re

import pyodbc
from flask import Blueprint, jsonify, session

from ..auth import MAX_PASSWORD_BYTES, check_password, current_user, hash_password
from ..db import query, transaction
from ..validation import body, text, utf16_len

bp = Blueprint("auth", __name__, url_prefix="/api/auth")

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
PHONE_RE = re.compile(r"^[0-9+]{9,15}$")  # same rule as the Customers.Phone CHECK constraint
MIN_PASSWORD = 8


def _public(user: dict) -> dict:
    return {"id": user["UserID"], "fullName": user["FullName"], "email": user["Email"], "role": user["Role"]}


def _start_session(user_id: int) -> None:
    session.clear()
    session["user_id"] = user_id


@bp.post("/register")
def register():
    """Create a customer account and log in. The role is always Customer, whatever the body says."""
    data = body()
    fields = [text(data, key) for key in ("fullName", "email", "password", "phone")]
    if None in fields:
        return jsonify(error="All fields must be plain text"), 400
    full_name, email, password, phone = fields
    full_name, email, phone = full_name.strip(), email.strip().lower(), phone.strip() or None

    # SQL Server counts NVARCHAR length in UTF-16 units, so an emoji counts as 2.
    if not full_name or utf16_len(full_name) > 100:
        return jsonify(error="Full name is required (max 100 characters)"), 400
    # Length and ASCII are checked before the regex to keep it fast, and the column is VARCHAR (ASCII only).
    if len(email) > 255 or not email.isascii() or not EMAIL_RE.match(email):
        return jsonify(error="Invalid email"), 400
    if len(password) < MIN_PASSWORD or len(password.encode()) > MAX_PASSWORD_BYTES:
        return jsonify(error=f"Password must be {MIN_PASSWORD} to {MAX_PASSWORD_BYTES} bytes"), 400
    if phone and not PHONE_RE.match(phone):
        return jsonify(error="Invalid phone number"), 400

    if query("SELECT 1 AS x FROM dbo.Users WHERE Email = ?", (email,)):
        return jsonify(error="Email already registered"), 409
    try:
        with transaction() as cur:
            cur.execute(
                "INSERT INTO dbo.Users (FullName, Email, PasswordHash) OUTPUT INSERTED.UserID VALUES (?, ?, ?)",
                (full_name, email, hash_password(password)),
            )
            user_id = cur.fetchval()
            cur.execute("INSERT INTO dbo.Customers (UserID, Phone) VALUES (?, ?)", (user_id, phone))
    except pyodbc.IntegrityError:  # another request registered the same email in between
        return jsonify(error="Email already registered"), 409

    _start_session(user_id)
    return jsonify(id=user_id, fullName=full_name, email=email, role="Customer"), 201


@bp.post("/login")
def login():
    data = body()
    email = (text(data, "email") or "").strip().lower()  # a non-text value counts as empty
    password = text(data, "password") or ""

    rows = query(
        "SELECT UserID, FullName, Email, Role, IsActive, PasswordHash FROM dbo.Users WHERE Email = ?", (email,))
    user = rows[0] if rows else None
    if not check_password(password, user["PasswordHash"] if user else None):
        return jsonify(error="Invalid email or password"), 401
    if not user["IsActive"]:
        return jsonify(error="Account is disabled"), 403

    with transaction() as cur:
        cur.execute("UPDATE dbo.Users SET LastLoginAt = SYSDATETIME() WHERE UserID = ?", (user["UserID"],))
    _start_session(user["UserID"])
    return jsonify(_public(user))


@bp.post("/logout")
def logout():
    session.clear()
    return "", 204


@bp.get("/me")
def me():
    user = current_user()
    if user is None:
        return jsonify(error="Login required"), 401
    return jsonify(_public(user))
