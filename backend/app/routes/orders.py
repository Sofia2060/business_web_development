"""Customer orders. The business rules live in SQL Server stored procedures, these routes call them."""
import uuid

import pyodbc
from flask import Blueprint, g, jsonify

from ..auth import customer_required
from ..db import ProcError, call, query
from ..validation import INT_MAX, body, is_int, text, utf16_len
from .cart import cart_subtotal, shipping_fee

bp = Blueprint("orders", __name__, url_prefix="/api/orders")

PAYMENT_METHODS = ("COD", "BankTransfer", "VNPay", "MoMo")


def _actor():
    return (g.user["UserID"], f"Customer:{g.customer_id}")


def _order_by_token(token: str):
    """The caller's order made with this checkout token, in the same shape as a new order response."""
    rows = query("SELECT OrderCode, TotalAmount, ShippingFee FROM dbo.Orders WHERE CheckoutToken = ? AND CustomerID = ?",
                 (token, g.customer_id))
    return rows[0] if rows else None


def _own_order(code: str):
    """The caller's order row, or None. Orders of other customers look like they do not exist."""
    rows = query("SELECT OrderID, OrderCode, OrderStatus FROM dbo.Orders WHERE OrderCode = ? AND CustomerID = ?",
                 (code, g.customer_id))
    return rows[0] if rows else None


@bp.post("")
@customer_required
def place_order():
    """Turn the cart into an order (sp_PlaceOrder). Sending the same checkoutToken again returns the same order."""
    data = body()
    method = text(data, "paymentMethod")
    voucher = text(data, "voucherCode")
    note = text(data, "note")
    address_id = data.get("addressId")
    try:
        token = str(uuid.UUID(str(data.get("checkoutToken"))))
    except ValueError:
        return jsonify(error="checkoutToken must be a UUID created by the client for each checkout"), 400
    if method not in PAYMENT_METHODS or not is_int(address_id, 1, INT_MAX) or None in (voucher, note):
        return jsonify(error="addressId and a valid paymentMethod are required"), 400
    voucher, note = voucher.strip() or None, note.strip() or None
    if voucher and len(voucher) > 30 or note and utf16_len(note) > 500:
        return jsonify(error="voucherCode (max 30) or note (max 500) is too long"), 400

    # A repeated request with the same token must not create a second order.
    if query("SELECT 1 AS x FROM dbo.Orders WHERE CheckoutToken = ? AND CustomerID <> ?", (token, g.customer_id)):
        return jsonify(error="Invalid checkoutToken"), 409
    earlier = _order_by_token(token)
    if earlier:
        return jsonify(earlier), 200

    # The shipping fee is worked out here from the real cart, never taken from the client.
    fee = shipping_fee(cart_subtotal(g.customer_id))
    try:
        rows = call(
            "DECLARE @OrderID INT; "
            "EXEC dbo.sp_PlaceOrder @CustomerID = ?, @AddressID = ?, @PaymentMethod = ?, @CheckoutToken = ?, "
            "@ShippingFee = ?, @VoucherCode = ?, @Note = ?, @OrderID = @OrderID OUTPUT; "
            "SELECT OrderCode, TotalAmount, ShippingFee FROM dbo.Orders WHERE OrderID = @OrderID;",
            (g.customer_id, address_id, method, token, fee, voucher, note), actor=_actor())
    except (pyodbc.IntegrityError, ProcError):
        # Two identical requests ran at the same moment and the other one won. Return its order if it exists.
        earlier = _order_by_token(token)
        if not earlier:
            raise
        return jsonify(earlier), 200
    return jsonify(rows[0]), 201


@bp.get("")
@customer_required
def list_orders():
    """My orders. CancelChannel says what the page should show: "Web" = cancel button, "Hotline" = call to cancel,
    null = the order can no longer be cancelled."""
    return jsonify(query(
        "SELECT OrderCode, CreatedAt, OrderStatus, Subtotal, DiscountAmount, ShippingFee, TotalAmount, "
        "PaymentMethod, PaymentStatus, CancelChannel FROM dbo.vw_CustomerOrderHistory WHERE CustomerID = ? "
        "ORDER BY OrderID DESC", (g.customer_id,)))


@bp.get("/<code>")
@customer_required
def get_order(code: str):
    rows = query(
        "SELECT o.OrderID, o.OrderCode, o.OrderStatus, o.ShipRecipientName, o.ShipPhone, o.ShipAddress, o.Subtotal, "
        "o.DiscountAmount, v.VoucherCode, o.IsRetentionApplied, o.ShippingFee, o.TotalAmount, o.Note, o.CancelReason, "
        "o.CreatedAt, o.ConfirmedAt, o.ShippedAt, o.DeliveredAt, o.CancelledAt, h.CancelChannel "
        "FROM dbo.Orders o LEFT JOIN dbo.Vouchers v ON v.VoucherID = o.VoucherID "
        "JOIN dbo.vw_CustomerOrderHistory h ON h.OrderID = o.OrderID WHERE o.OrderCode = ? AND o.CustomerID = ?",
        (code, g.customer_id))
    if not rows:
        return jsonify(error="Order not found"), 404
    order = rows[0]
    order["items"] = query(
        "SELECT oi.ProductNameSnap, oi.SKUSnap, oi.MaterialSnap, oi.GoldColor, oi.RingSize, oi.EngravingText, "
        "oi.Quantity, oi.UnitPrice, oi.LineTotal, p.SKU AS ProductSKU FROM dbo.OrderItems oi "
        "JOIN dbo.Products p ON p.ProductID = oi.ProductID WHERE oi.OrderID = ? ORDER BY oi.OrderItemID",
        (order["OrderID"],))
    order["payments"] = query(
        "SELECT PaymentMethod, Amount, Status, CreatedAt, PaidAt FROM dbo.Payments WHERE OrderID = ? ORDER BY PaymentID",
        (order["OrderID"],))
    # A cancel request that waits for the customer's answer, so the page can show the reminder popup again.
    pending = query("SELECT RequestID FROM dbo.OrderCancellationRequests WHERE OrderID = ? AND Decision = 'Pending'",
                    (order["OrderID"],))
    order["pendingCancelRequest"] = ({"RequestID": pending[0]["RequestID"], "VoucherCode": order["VoucherCode"],
                                      "VoucherDiscount": order["DiscountAmount"]} if pending else None)
    del order["OrderID"]
    return jsonify(order)


@bp.post("/<code>/cancel")
@customer_required
def request_cancel(code: str):
    """The customer pressed "Cancel order" (sp_RequestCancelOrder). Nothing is cancelled yet.
    The reply holds the voucher the customer would lose, for the reminder popup. The customer then answers at
    /cancel/respond. Orders above 5,000,000 VND cannot be cancelled online (403, tell the customer to call)."""
    order = _own_order(code)
    if not order:
        return jsonify(error="Order not found"), 404
    reason = text(body(), "reason")
    if reason is None or utf16_len(reason) > 500:
        return jsonify(error="reason must be text of at most 500 characters"), 400
    result = call(
        "DECLARE @RequestID INT, @VoucherCode VARCHAR(30), @VoucherDiscount DECIMAL(15,0); "
        "EXEC dbo.sp_RequestCancelOrder @OrderID = ?, @CustomerID = ?, @Reason = ?, "
        "@RequestID = @RequestID OUTPUT, @VoucherCode = @VoucherCode OUTPUT, @VoucherDiscount = @VoucherDiscount OUTPUT; "
        "SELECT @RequestID AS RequestID, @VoucherCode AS VoucherCode, @VoucherDiscount AS VoucherDiscount;",
        (order["OrderID"], g.customer_id, reason.strip() or None), actor=_actor())[0]
    return jsonify(result)


@bp.post("/<code>/cancel/respond")
@customer_required
def respond_to_popup(code: str):
    """The customer's answer to the popup (sp_RespondCancelPopup): keepOrder=true keeps the order unchanged,
    keepOrder=false cancels it, returns the stock and loses the voucher."""
    order = _own_order(code)
    if not order:
        return jsonify(error="Order not found"), 404
    keep = body().get("keepOrder")
    if not isinstance(keep, bool):
        return jsonify(error="keepOrder must be true or false"), 400
    pending = query("SELECT RequestID FROM dbo.OrderCancellationRequests WHERE OrderID = ? AND Decision = 'Pending'",
                    (order["OrderID"],))
    if not pending:
        return jsonify(error="There is no cancel request waiting for an answer"), 409
    call("EXEC dbo.sp_RespondCancelPopup @RequestID = ?, @CustomerID = ?, @KeepOrder = ?",
         (pending[0]["RequestID"], g.customer_id, 1 if keep else 0), actor=_actor())
    return jsonify(query("SELECT OrderCode, OrderStatus, IsRetentionApplied, TotalAmount FROM dbo.Orders "
                         "WHERE OrderID = ?", (order["OrderID"],))[0])


@bp.post("/<code>/confirm-received")
@customer_required
def confirm_received(code: str):
    """The customer got the parcel (sp_ConfirmOrderReceived). The database then issues the warranty cards."""
    order = _own_order(code)
    if not order:
        return jsonify(error="Order not found"), 404
    call("EXEC dbo.sp_ConfirmOrderReceived @OrderID = ?, @CustomerID = ?", (order["OrderID"], g.customer_id),
         actor=_actor())
    return jsonify(query("SELECT OrderCode, OrderStatus, DeliveredAt FROM dbo.Orders WHERE OrderID = ?",
                         (order["OrderID"],))[0])
