"""Admin-only endpoints."""
import uuid

from flask import Blueprint, g, jsonify, request

from ..auth import admin_required
from ..db import call, query
from ..validation import body, page_number, text, utf16_len
from .orders import order_detail

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


_CUSTOMER_COLUMNS = ("c.CustomerID, COALESCE(u.FullName, o.ShipRecipientName) AS CustomerName, u.Email AS CustomerEmail, c.Phone AS CustomerPhone, "
                     "CAST(CASE WHEN c.UserID IS NULL THEN 1 ELSE 0 END AS BIT) AS IsGuest")


@bp.get("/orders")
@admin_required
def list_orders():
    """All orders, newest first, each with its items. Query: status, page, limit (max 100)."""
    status = request.args.get("status")
    page, limit = page_number(request.args.get("page"), 1), page_number(request.args.get("limit"), 20)
    if (status and status not in ORDER_STATUSES) or not page or not limit or limit > 100:
        return jsonify(error="Invalid query parameter"), 400
    where, params = ("WHERE o.OrderStatus = ?", (status,)) if status else ("", ())
    total = query(f"SELECT COUNT(*) AS n FROM dbo.Orders o {where}", params)[0]["n"]
    orders = query(
        "SELECT o.OrderID, o.OrderCode, o.CreatedAt, o.OrderStatus, o.TotalAmount, o.ShipRecipientName, o.ShipPhone, "
        f"{_CUSTOMER_COLUMNS}, p.PaymentMethod, p.Status AS PaymentStatus, p.PaidAt, h.PaymentDeadline, "
        "o.ProductionStartedAt FROM dbo.Orders o JOIN dbo.Customers c ON c.CustomerID = o.CustomerID "
        "LEFT JOIN dbo.Users u ON u.UserID = c.UserID "
        "JOIN dbo.vw_CustomerOrderHistory h ON h.OrderID = o.OrderID "
        "OUTER APPLY (SELECT TOP (1) PaymentMethod, Status, PaidAt FROM dbo.Payments WHERE OrderID = o.OrderID "
        f"ORDER BY PaymentID DESC) p {where} "
        "ORDER BY o.OrderID DESC OFFSET ? ROWS FETCH NEXT ? ROWS ONLY",
        params + ((page - 1) * limit, limit))
    items: dict[int, list] = {}
    if orders:
        marks = ", ".join("?" * len(orders))      # the ids come from the query above, never from the request
        for item in query(
                "SELECT oi.OrderID, oi.ProductNameSnap, oi.SKUSnap, oi.GoldColor, oi.RingSize, oi.Quantity, oi.UnitPrice, "
                "p.SKU AS ProductSKU FROM dbo.OrderItems oi JOIN dbo.Products p ON p.ProductID = oi.ProductID "
                f"WHERE oi.OrderID IN ({marks}) ORDER BY oi.OrderID, oi.OrderItemID", tuple(o["OrderID"] for o in orders)):
            items.setdefault(item.pop("OrderID"), []).append(item)
    for order in orders:
        order["items"] = items.get(order.pop("OrderID"), [])
    return jsonify(total=total, page=page, limit=limit, items=orders)


@bp.get("/orders/<code>")
@admin_required
def get_order(code: str):
    """One order in full: items, payments, addresses and times, plus who the customer is."""
    order = order_detail(code)
    if not order:
        return jsonify(error="Order not found"), 404
    order["customer"] = query(
        f"SELECT {_CUSTOMER_COLUMNS} FROM dbo.Orders o JOIN dbo.Customers c ON c.CustomerID = o.CustomerID "
        "LEFT JOIN dbo.Users u ON u.UserID = c.UserID WHERE o.OrderCode = ?", (code,))[0]
    return jsonify(order)


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


@bp.post("/orders/<code>/confirm-payment")
@admin_required
def confirm_bank_transfer(code: str):
    """The shop saw the bank transfer arrive (simulated: no bank is connected). Records the payment as successful
    (sp_RecordPaymentResult). Only for BankTransfer orders; an order past the 15 minute limit answers 409."""
    rows = query("SELECT TOP (1) o.OrderID, p.PaymentID, p.PaymentMethod, p.Amount, p.Status FROM dbo.Orders o "
                 "JOIN dbo.Payments p ON p.OrderID = o.OrderID WHERE o.OrderCode = ? ORDER BY p.PaymentID DESC", (code,))
    if not rows:
        return jsonify(error="Order not found"), 404
    payment = rows[0]
    if payment["PaymentMethod"] != "BankTransfer":
        return jsonify(error="Only bank transfer orders are confirmed by the shop"), 400
    if payment["Status"] == "Success":
        return jsonify(error="The order is already paid"), 409
    admin_id = g.user["UserID"]
    call("EXEC dbo.sp_RecordPaymentResult @PaymentID = ?, @IsSuccess = 1, @TransactionID = ?, @ResponseCode = '00', "
         "@Amount = ?", (payment["PaymentID"], f"SIM-BANK-{uuid.uuid4().hex}", payment["Amount"]),
         actor=(admin_id, f"Admin:{admin_id}"))
    return jsonify(OrderCode=code, PaymentStatus="Success")


@bp.post("/orders/<code>/start-production")
@admin_required
def start_production(code: str):
    """Mark that the shop began crafting the order (sp_StartOrderProduction). From then on nobody can cancel it,
    not even by phone. Only a confirmed order can start."""
    rows = query("SELECT OrderID FROM dbo.Orders WHERE OrderCode = ?", (code,))
    if not rows:
        return jsonify(error="Order not found"), 404
    admin_id = g.user["UserID"]
    call("EXEC dbo.sp_StartOrderProduction @OrderID = ?, @AdminUserID = ?", (rows[0]["OrderID"], admin_id),
         actor=(admin_id, f"Admin:{admin_id}"))
    return jsonify(query("SELECT OrderCode, OrderStatus, ProductionStartedAt FROM dbo.Orders WHERE OrderID = ?",
                         (rows[0]["OrderID"],))[0])
