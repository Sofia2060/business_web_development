"""Admin-only endpoints."""
from flask import Blueprint, jsonify

from ..auth import admin_required
from ..db import query

bp = Blueprint("admin", __name__, url_prefix="/api/admin")


@bp.get("/users")
@admin_required
def list_users():
    """List all accounts. Never includes password hashes."""
    users = query(
        "SELECT UserID, FullName, Email, Role, IsActive, LastLoginAt, CreatedAt FROM dbo.Users ORDER BY UserID")
    for u in users:
        for key in ("LastLoginAt", "CreatedAt"):
            u[key] = u[key].isoformat() if u[key] else None
    return jsonify(users)
