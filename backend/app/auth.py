"""Password hashing, the logged-in user, and the permission decorators."""
from functools import wraps

import bcrypt
from flask import g, jsonify, session

from .db import query

MAX_PASSWORD_BYTES = 72  # bcrypt ignores everything after 72 bytes, so we refuse longer passwords

# A real bcrypt hash used to burn the same time when the email is unknown,
# so response time does not reveal which emails are registered.
_DUMMY_HASH = bcrypt.hashpw(b"not-a-real-password", bcrypt.gensalt())


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def check_password(password: str, password_hash: str | None) -> bool:
    """True if the password matches. Sample rows in the database hold fake hashes, which never match."""
    if not password_hash:  # unknown email: do a dummy check, then fail
        try:
            bcrypt.checkpw(password.encode(), _DUMMY_HASH)
        except ValueError:
            pass
        return False
    try:
        return bcrypt.checkpw(password.encode(), password_hash.encode())
    except ValueError:  # fake or malformed stored hash, or password over 72 bytes
        return False


def current_user() -> dict | None:
    """The active user stored in the session cookie, read fresh from the database."""
    if "user" not in g:
        g.user = None
        user_id = session.get("user_id")
        if user_id:
            rows = query(
                "SELECT UserID, FullName, Email, Role FROM dbo.Users WHERE UserID = ? AND IsActive = 1",
                (user_id,),
            )
            g.user = rows[0] if rows else None
    return g.user


def login_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if current_user() is None:
            return jsonify(error="Login required"), 401
        return view(*args, **kwargs)
    return wrapper


def admin_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        user = current_user()
        if user is None:
            return jsonify(error="Login required"), 401
        if user["Role"] != "Admin":
            return jsonify(error="Admin only"), 403
        return view(*args, **kwargs)
    return wrapper


def customer_required(view):
    """Logged-in user who has a Customers row. Sets g.customer_id for the view. Admins have none, so they get 403."""
    @wraps(view)
    def wrapper(*args, **kwargs):
        user = current_user()
        if user is None:
            return jsonify(error="Login required"), 401
        rows = query("SELECT CustomerID FROM dbo.Customers WHERE UserID = ?", (user["UserID"],))
        if not rows:
            return jsonify(error="Customer account required"), 403
        g.customer_id = rows[0]["CustomerID"]
        return view(*args, **kwargs)
    return wrapper
