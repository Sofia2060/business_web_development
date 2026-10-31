"""Admin-only endpoints."""
from flask import Blueprint, g, jsonify, request

from ..auth import admin_required
from ..db import call, query
from ..validation import body, page_number, text, utf16_len

bp = Blueprint("admin", __name__, url_prefix="/api/admin")

ORDER_STATUSES = ("Pending", "Confirmed", "Shipping", "Delivered", "Cancelled")
# Statuses an admin can move an order to. Pending is the starting state only.
CAN_SET_STATUS = ("Confirmed", "Shipping", "Delivered", "Cancelled")


@bp.get("/users")
@admin_required
def list_users():
    """List all accounts. Never includes password hashes."""
    return jsonify(query(
        "SELECT UserID, FullName, Email, Role, IsActive, LastLoginAt, CreatedAt FROM dbo.Users ORDER BY UserID"))


@bp.get("/orders")
@admin_required
def list_orders():
    """All orders, newest first. Query: status, page, limit (max 100)."""
    status = request.args.get("status")
    page, limit = page_number(request.args.get("page"), 1), page_number(request.args.get("limit"), 20)
    if (status and status not in ORDER_STATUSES) or not page or not limit or limit > 100:
        return jsonify(error="Invalid query parameter"), 400
    where, params = ("WHERE o.OrderStatus = ?", (status,)) if status else ("", ())
    total = query(f"SELECT COUNT(*) AS n FROM dbo.Orders o {where}", params)[0]["n"]
    items = query(
        "SELECT o.OrderCode, o.CreatedAt, o.OrderStatus, o.TotalAmount, u.FullName AS CustomerName, "
        "u.Email AS CustomerEmail FROM dbo.Orders o JOIN dbo.Customers c ON c.CustomerID = o.CustomerID "
        f"JOIN dbo.Users u ON u.UserID = c.UserID {where} "
        "ORDER BY o.OrderID DESC OFFSET ? ROWS FETCH NEXT ? ROWS ONLY",
        params + ((page - 1) * limit, limit))
    return jsonify(total=total, page=page, limit=limit, items=items)


@bp.post("/orders/<code>/status")
@admin_required
def set_order_status(code: str):
    """Move an order forward (sp_UpdateOrderStatus). The database rejects wrong steps, for example Pending to Delivered."""
    data = body()
    status, reason = data.get("status"), text(data, "reason")
    if status not in CAN_SET_STATUS or reason is None or utf16_len(reason) > 500:
        return jsonify(error=f"status must be one of {', '.join(CAN_SET_STATUS)}; reason is text up to 500 characters"), 400
    rows = query("SELECT OrderID FROM dbo.Orders WHERE OrderCode = ?", (code,))
    if not rows:
        return jsonify(error="Order not found"), 404
    admin_id = g.user["UserID"]
    call("EXEC dbo.sp_UpdateOrderStatus @OrderID = ?, @NewStatus = ?, @AdminUserID = ?, @Reason = ?",
         (rows[0]["OrderID"], status, admin_id, reason.strip() or None), actor=(admin_id, f"Admin:{admin_id}"))
    return jsonify(query("SELECT OrderCode, OrderStatus, ConfirmedAt, ShippedAt, DeliveredAt, CancelledAt "
                         "FROM dbo.Orders WHERE OrderID = ?", (rows[0]["OrderID"],))[0])
