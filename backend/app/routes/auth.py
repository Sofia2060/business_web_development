"""Register, login, logout and "who am I" endpoints. The login lives in a signed session cookie."""
import re

import pyodbc
from flask import Blueprint, jsonify, session

from ..auth import MAX_PASSWORD_BYTES, check_password, current_user, hash_password, login_required
from ..config import DEMO_OTP
from ..db import query, transaction
from ..validation import body, normalize_phone, text, utf16_len

bp = Blueprint("auth", __name__, url_prefix="/api/auth")

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
MIN_PASSWORD = 8


def _public(user: dict) -> dict:
    return {"id": user["UserID"], "fullName": user["FullName"], "email": user["Email"], "role": user["Role"]}


def _start_session(user_id: int, remember: bool = False) -> None:
    """Log in by putting the user id in the signed cookie. Without remember the cookie ends when the browser closes."""
    session.clear()
    session.permanent = remember
    session["user_id"] = user_id


@bp.post("/register")
def register():
    """Create a customer account and log in. The role is always Customer, whatever the body says.

    The phone number is the customer id. If a guest (a visitor who ordered without an account) used this number,
    the new account takes over that guest's orders, addresses and warranty cards. That needs the code sent to the
    phone (field "otp"). The shop sends no SMS, so the code is always the demo code in config.py."""
    data = body()
    fields = [text(data, key) for key in ("fullName", "email", "password", "phone", "otp")]
    if None in fields:
        return jsonify(error="All fields must be plain text"), 400
    full_name, email, password, phone, otp = fields
    full_name, email, phone = full_name.strip(), email.strip().lower(), phone.strip() or None

    # SQL Server counts NVARCHAR length in UTF-16 units, so an emoji counts as 2.
    if not full_name or utf16_len(full_name) > 100:
        return jsonify(error="Full name is required (max 100 characters)"), 400
    # Length and ASCII are checked before the regex to keep it fast, and the column is VARCHAR (ASCII only).
    if len(email) > 255 or not email.isascii() or not EMAIL_RE.match(email):
        return jsonify(error="Invalid email"), 400
    if len(password) < MIN_PASSWORD or len(password.encode()) > MAX_PASSWORD_BYTES:
        return jsonify(error=f"Password must be {MIN_PASSWORD} to {MAX_PASSWORD_BYTES} bytes"), 400
    if phone:
        phone = normalize_phone(phone)
        if phone is None:
            return jsonify(error="Invalid phone number"), 400

    if query("SELECT 1 AS x FROM dbo.Users WHERE Email = ?", (email,)):
        return jsonify(error="Email already registered"), 409

    guest_id, linked_orders = None, 0
    if phone:
        owner = query("SELECT CustomerID, UserID FROM dbo.Customers WHERE Phone = ?", (phone,))
        if owner and owner[0]["UserID"] is not None:
            return jsonify(error="Phone number is already used by an account", reason="phone_in_use"), 409
        if owner:
            guest_id = owner[0]["CustomerID"]
            linked_orders = query("SELECT COUNT(*) AS n FROM dbo.Orders WHERE CustomerID = ?", (guest_id,))[0]["n"]
            if linked_orders and not otp:
                return jsonify(error="This phone number has earlier orders. Enter the code sent to the phone to link them.",
                               reason="otp_required", orders=linked_orders), 409
            if linked_orders and otp != DEMO_OTP:
                return jsonify(error="Wrong code", reason="otp_invalid"), 400

    try:
        with transaction() as cur:
            cur.execute(
                "INSERT INTO dbo.Users (FullName, Email, PasswordHash) OUTPUT INSERTED.UserID VALUES (?, ?, ?)",
                (full_name, email, hash_password(password)),
            )
            user_id = cur.fetchval()
            if guest_id:    # the guest becomes this account: orders, addresses and warranty cards follow by customer id
                cur.execute("UPDATE dbo.Customers SET UserID = ?, UpdatedAt = SYSDATETIME() "
                            "WHERE CustomerID = ? AND UserID IS NULL", (user_id, guest_id))
                if cur.rowcount != 1:    # someone else took the number between the check and now
                    raise pyodbc.IntegrityError("UX_Customers_Phone")
            else:
                cur.execute("INSERT INTO dbo.Customers (UserID, Phone) VALUES (?, ?)", (user_id, phone))
    except pyodbc.IntegrityError as exc:  # another request registered the same email or phone in between
        if "Customers" in str(exc):
            return jsonify(error="Phone number is already used by an account", reason="phone_in_use"), 409
        return jsonify(error="Email already registered"), 409

    _start_session(user_id)
    extra = {"linkedOrders": linked_orders} if linked_orders else {}
    return jsonify(id=user_id, fullName=full_name, email=email, role="Customer", **extra), 201


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
    _start_session(user["UserID"], remember=data.get("remember") is True)
    return jsonify(_public(user))


@bp.post("/logout")
def logout():
    session.clear()
    return "", 204


@bp.post("/change-password")
@login_required
def change_password():
    """Body: {"currentPassword", "newPassword"}. Works for customers and admins. The login stays active."""
    data = body()
    current, new = text(data, "currentPassword"), text(data, "newPassword")
    if not current or new is None:
        return jsonify(error="currentPassword and newPassword are required"), 400
    if len(new) < MIN_PASSWORD or len(new.encode()) > MAX_PASSWORD_BYTES:
        return jsonify(error=f"Password must be {MIN_PASSWORD} to {MAX_PASSWORD_BYTES} bytes"), 400
    user_id = current_user()["UserID"]
    stored = query("SELECT PasswordHash FROM dbo.Users WHERE UserID = ?", (user_id,))[0]["PasswordHash"]
    if not check_password(current, stored):
        return jsonify(error="Current password is wrong"), 403
    with transaction() as cur:
        cur.execute("UPDATE dbo.Users SET PasswordHash = ?, UpdatedAt = SYSDATETIME() WHERE UserID = ?",
                    (hash_password(new), user_id))
    return "", 204


@bp.get("/me")
def me():
    user = current_user()
    if user is None:
        return jsonify(error="Login required"), 401
    return jsonify(_public(user))
