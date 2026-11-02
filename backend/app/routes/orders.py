"""Orders of customers and of guests. The business rules live in SQL Server stored procedures, these routes call them.

A guest is a visitor without an account who orders with a phone number. The phone number is the customer id.
Guests use the same endpoints as customers, but prove who they are with the phone number
(see customer_or_guest in auth.py)."""
import uuid

import pyodbc
from flask import Blueprint, g, jsonify

from ..auth import customer_or_guest, customer_required
from ..db import ProcError, call, named_lock, query, transaction
from ..validation import INT_MAX, body, is_int, text, utf16_len
from .addresses import LIMITS, full_address_error, read_fields
from .cart import add_line, cart_subtotal, read_line, shipping_fee

bp = Blueprint("orders", __name__, url_prefix="/api/orders")

PAYMENT_METHODS = ("COD", "BankTransfer", "VNPay", "MoMo")
SIMULATED_GATEWAY_METHODS = ("VNPay", "MoMo")   # paid at the (simulated) gateway; a bank transfer is confirmed by the shop
MAX_GUEST_LINES = 20


def _actor():
    if g.get("user"):
        return (g.user["UserID"], f"Customer:{g.customer_id}")
    return (None, f"Guest:{g.customer_id}")


def _order_by_token(token: str, customer_id: int):
    """The customer's order made with this checkout token, in the same shape as a new order response."""
    rows = query("SELECT OrderCode, TotalAmount, ShippingFee FROM dbo.Orders WHERE CheckoutToken = ? AND CustomerID = ?",
                 (token, customer_id))
    return rows[0] if rows else None


def _own_order(code: str):
    """The caller's order row, or None. Orders of other customers look like they do not exist."""
    rows = query("SELECT OrderID, OrderCode, OrderStatus FROM dbo.Orders WHERE OrderCode = ? AND CustomerID = ?",
                 (code, g.customer_id))
    return rows[0] if rows else None


def _read_checkout(data: dict) -> tuple[dict | None, str | None]:
    """paymentMethod, checkoutToken, voucherCode and note of a checkout request. Returns (values, error message)."""
    method, voucher, note = text(data, "paymentMethod"), text(data, "voucherCode"), text(data, "note")
    try:
        token = str(uuid.UUID(str(data.get("checkoutToken"))))
    except ValueError:
        return None, "checkoutToken must be a UUID created by the client for each checkout"
    if method not in PAYMENT_METHODS or None in (voucher, note):
        return None, "a valid paymentMethod is required"
    voucher, note = voucher.strip() or None, note.strip() or None
    if voucher and len(voucher) > 30 or note and utf16_len(note) > 500:
        return None, "voucherCode (max 30) or note (max 500) is too long"
    return {"method": method, "token": token, "voucher": voucher, "note": note}, None


def _token_of_another_customer(token: str, customer_id: int) -> bool:
    return bool(query("SELECT 1 AS x FROM dbo.Orders WHERE CheckoutToken = ? AND CustomerID <> ?", (token, customer_id)))


def _place(customer_id: int, actor, address_id: int, checkout: dict):
    """Turn the customer's cart into an order (sp_PlaceOrder). Returns (response body, HTTP status).
    Sending the same checkout token again returns the same order."""
    earlier = _order_by_token(checkout["token"], customer_id)
    if earlier:
        return earlier, 200
    # The shipping fee is worked out here from the real cart, never taken from the client.
    fee = shipping_fee(cart_subtotal(customer_id))
    try:
        rows = call(
            "DECLARE @OrderID INT; "
            "EXEC dbo.sp_PlaceOrder @CustomerID = ?, @AddressID = ?, @PaymentMethod = ?, @CheckoutToken = ?, "
            "@ShippingFee = ?, @VoucherCode = ?, @Note = ?, @OrderID = @OrderID OUTPUT; "
            "SELECT OrderCode, TotalAmount, ShippingFee FROM dbo.Orders WHERE OrderID = @OrderID;",
            (customer_id, address_id, checkout["method"], checkout["token"], fee, checkout["voucher"], checkout["note"]),
            actor=actor)
    except (pyodbc.IntegrityError, ProcError):
        # Two identical requests ran at the same moment and the other one won. Return its order if it exists.
        earlier = _order_by_token(checkout["token"], customer_id)
        if not earlier:
            raise
        return earlier, 200
    return rows[0], 201


@bp.post("")
@customer_required
def place_order():
    """Turn the cart into an order (sp_PlaceOrder). Sending the same checkoutToken again returns the same order."""
    data = body()
    checkout, error = _read_checkout(data)
    address_id = data.get("addressId")
    if not error and not is_int(address_id, 1, INT_MAX):
        error = "addressId is required"
    if error:
        return jsonify(error=error), 400
    if _token_of_another_customer(checkout["token"], g.customer_id):
        return jsonify(error="Invalid checkoutToken"), 409
    payload, status = _place(g.customer_id, _actor(), address_id, checkout)
    return jsonify(payload), status


def _forget_unused_guest(customer_id: int, new_address_id: int | None, created_now: bool) -> None:
    """After a guest checkout that did not make an order: remove the temporary cart and everything this request
    created, so a failed attempt leaves no guest customer or address behind."""
    with transaction() as cur:
        cur.execute("DELETE FROM dbo.CartItems WHERE CustomerID = ?", (customer_id,))
        if new_address_id:
            cur.execute("DELETE FROM dbo.CustomerAddresses WHERE AddressID = ?", (new_address_id,))
        if created_now:
            cur.execute("DELETE FROM dbo.Customers WHERE CustomerID = ? AND UserID IS NULL "
                        "AND NOT EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = Customers.CustomerID)",
                        (customer_id,))


@bp.post("/guest")
def place_guest_order():
    """Order without an account. Body: fullName, phone, addressLine, ward, province, items
    ([{"variantSku", "quantity", "engravingText", "engravingStyle"}], at most 20 lines), paymentMethod, checkoutToken, voucherCode, note.

    The phone number is the customer id: the first order creates the guest customer, later orders and lookups
    use the same number. If the number belongs to an account the answer is 409 and the owner has to log in.
    The guest cart lives in the browser, so the items come in the request and are put in a temporary cart
    that sp_PlaceOrder then turns into the order. Requests for the same phone run one at a time (a lock),
    because they share that temporary cart."""
    data = body()
    checkout, error = _read_checkout(data)
    items = data.get("items")
    fields, field_error = read_fields({**data, "recipientName": data.get("fullName")}, (*LIMITS, "phone"))
    error = error or (field_error and field_error.replace("recipientName", "fullName"))
    if not error and (not isinstance(items, list) or not 1 <= len(items) <= MAX_GUEST_LINES
                      or not all(isinstance(item, dict) for item in items)):
        error = f"items must be a list of 1 to {MAX_GUEST_LINES} lines"
    if not error:
        error = full_address_error(fields["addressLine"], fields["ward"], fields["province"])
    if error:
        return jsonify(error=error), 400

    lines = []
    for number, item in enumerate(items, start=1):
        line, line_error = read_line(item)
        if line_error:
            return jsonify(error=f"Item {number}: {line_error}"), 400
        lines.append(line)

    with named_lock(f"guest-order-{fields['phone']}"):
        return _guest_order(fields, lines, checkout)


def _guest_order(fields: dict, lines: list, checkout: dict):
    """The part of the guest checkout that runs under the phone's lock."""
    phone = fields["phone"]
    customer = query("SELECT CustomerID, UserID FROM dbo.Customers WHERE Phone = ?", (phone,))
    created_now = not customer
    if created_now:
        try:
            with transaction() as cur:
                cur.execute("INSERT INTO dbo.Customers (UserID, Phone) OUTPUT INSERTED.CustomerID VALUES (NULL, ?)", (phone,))
                customer = [{"CustomerID": cur.fetchval(), "UserID": None}]
        except pyodbc.IntegrityError:    # someone registered with this number a moment ago
            customer, created_now = query("SELECT CustomerID, UserID FROM dbo.Customers WHERE Phone = ?", (phone,)), False
    if customer[0]["UserID"] is not None:
        return jsonify(error="This phone number has an account. Please log in to order.", reason="phone_has_account"), 409
    customer_id = customer[0]["CustomerID"]
    g.customer_id = customer_id

    new_address_id, ordered = None, False
    try:
        if _token_of_another_customer(checkout["token"], customer_id):
            return jsonify(error="Invalid checkoutToken"), 409
        earlier = _order_by_token(checkout["token"], customer_id)    # a repeated request must not touch the cart again
        if earlier:
            return jsonify(earlier), 200

        # Compared with case and tone marks counted (the database default ignores them), so the order keeps the
        # spelling the customer typed this time.
        address = query("SELECT AddressID FROM dbo.CustomerAddresses WHERE CustomerID = ? "
                        "AND RecipientName COLLATE Vietnamese_100_CS_AS = ? AND Phone = ? "
                        "AND AddressLine COLLATE Vietnamese_100_CS_AS = ? AND Ward COLLATE Vietnamese_100_CS_AS = ? "
                        "AND Province COLLATE Vietnamese_100_CS_AS = ?",
                        (customer_id, fields["recipientName"], phone, fields["addressLine"], fields["ward"],
                         fields["province"]))
        if address:
            address_id = address[0]["AddressID"]
        else:
            with transaction() as cur:
                has_any = cur.execute("SELECT 1 FROM dbo.CustomerAddresses WHERE CustomerID = ?", (customer_id,)).fetchone()
                cur.execute(
                    "INSERT INTO dbo.CustomerAddresses (CustomerID, RecipientName, Phone, AddressLine, Ward, Province, IsDefault) "
                    "OUTPUT INSERTED.AddressID VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (customer_id, fields["recipientName"], phone, fields["addressLine"], fields["ward"], fields["province"],
                     0 if has_any else 1))
                address_id = new_address_id = cur.fetchval()

        with transaction() as cur:
            cur.execute("DELETE FROM dbo.CartItems WHERE CustomerID = ?", (customer_id,))
        for number, line in enumerate(lines, start=1):
            payload, status = add_line(customer_id, *line)
            if status >= 400:
                extra = {"reason": payload["reason"]} if "reason" in payload else {}    # for example quote_only
                return jsonify(error=f"Item {number}: {payload['error']}", **extra), status
        payload, status = _place(customer_id, _actor(), address_id, checkout)
        ordered = True
        return jsonify(payload), status
    finally:
        if not ordered:    # sp_PlaceOrder empties the temporary cart itself when it works
            _forget_unused_guest(customer_id, new_address_id, created_now)


@bp.get("")
@customer_required
def list_orders():
    """My orders. CancelChannel says what the page should show: "Web" = cancel button, "Hotline" = call to cancel,
    null = the order can no longer be cancelled. PaymentDeadline is when an unpaid online order fails."""
    return jsonify(query(
        "SELECT OrderCode, CreatedAt, OrderStatus, Subtotal, DiscountAmount, ShippingFee, TotalAmount, "
        "PaymentMethod, PaymentStatus, PaymentDeadline, HasEngraving, CancelChannel "
        "FROM dbo.vw_CustomerOrderHistory WHERE CustomerID = ? ORDER BY OrderID DESC", (g.customer_id,)))


@bp.get("/<code>")
@customer_or_guest
def get_order(code: str):
    """One of my orders. A guest sends ?phone=<the phone used for the order>."""
    rows = query(
        "SELECT o.OrderID, o.OrderCode, o.OrderStatus, o.ShipRecipientName, o.ShipPhone, o.ShipAddress, o.Subtotal, "
        "o.DiscountAmount, v.VoucherCode, o.IsRetentionApplied, o.ShippingFee, o.TotalAmount, o.Note, o.CancelReason, "
        "o.CreatedAt, o.ConfirmedAt, o.ShippedAt, o.DeliveredAt, o.CancelledAt, o.ProductionStartedAt, "
        "h.PaymentDeadline, h.HasEngraving, h.CancelChannel "
        "FROM dbo.Orders o LEFT JOIN dbo.Vouchers v ON v.VoucherID = o.VoucherID "
        "JOIN dbo.vw_CustomerOrderHistory h ON h.OrderID = o.OrderID WHERE o.OrderCode = ? AND o.CustomerID = ?",
        (code, g.customer_id))
    if not rows:
        return jsonify(error="Order not found"), 404
    order = rows[0]
    order["items"] = query(
        "SELECT oi.ProductNameSnap, oi.SKUSnap, oi.MaterialSnap, oi.GoldColor, oi.RingSize, oi.EngravingText, oi.EngravingStyle, "
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
                                      "VoucherDiscount": order["DiscountAmount"], "Subtotal": order["Subtotal"],
                                      "TotalAmount": order["TotalAmount"]} if pending else None)
    del order["OrderID"]
    return jsonify(order)


@bp.post("/<code>/cancel")
@customer_or_guest
def request_cancel(code: str):
    """The customer pressed "Cancel order" (sp_RequestCancelOrder). Nothing is cancelled yet.

    Only an order under 2,000,000 VND without engraved items can be cancelled here. The reply holds what the
    reminder popup needs: the voucher the customer would lose (VoucherCode, VoucherDiscount) and the full price
    (Subtotal) they would pay if they order again. The customer then answers at /cancel/respond.
    Any other order answers 403 with the "please call the hotline" text, and an order being crafted answers 409."""
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
        "SELECT @RequestID AS RequestID, @VoucherCode AS VoucherCode, @VoucherDiscount AS VoucherDiscount, "
        "Subtotal, TotalAmount FROM dbo.Orders WHERE OrderID = ?;",
        (order["OrderID"], g.customer_id, reason.strip() or None, order["OrderID"]), actor=_actor())[0]
    return jsonify(result)


@bp.post("/<code>/cancel/respond")
@customer_or_guest
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
@customer_or_guest
def confirm_received(code: str):
    """The customer got the parcel (sp_ConfirmOrderReceived). The database then issues the warranty cards."""
    order = _own_order(code)
    if not order:
        return jsonify(error="Order not found"), 404
    call("EXEC dbo.sp_ConfirmOrderReceived @OrderID = ?, @CustomerID = ?", (order["OrderID"], g.customer_id),
         actor=_actor())
    return jsonify(query("SELECT OrderCode, OrderStatus, DeliveredAt FROM dbo.Orders WHERE OrderID = ?",
                         (order["OrderID"],))[0])


@bp.post("/<code>/pay")
@customer_or_guest
def pay_order(code: str):
    """Pay an online order (VNPay or MoMo). The payment is simulated: the shop has no real gateway, so this call
    plays the part of "the gateway says the payment succeeded" (sp_RecordPaymentResult with a made-up transaction id).
    An order that is cancelled or past the 15 minute limit answers 409. Cash on delivery is paid on delivery and a
    bank transfer is confirmed by the shop (admin), so those answer 400."""
    order = _own_order(code)
    if not order:
        return jsonify(error="Order not found"), 404
    payment = query("SELECT TOP (1) PaymentID, PaymentMethod, Amount, Status FROM dbo.Payments WHERE OrderID = ? "
                    "ORDER BY PaymentID DESC", (order["OrderID"],))[0]
    if payment["PaymentMethod"] not in SIMULATED_GATEWAY_METHODS:
        return jsonify(error="Only VNPay and MoMo orders are paid online"), 400
    if payment["Status"] == "Success":
        return jsonify(error="The order is already paid"), 409
    call("EXEC dbo.sp_RecordPaymentResult @PaymentID = ?, @IsSuccess = 1, @TransactionID = ?, @ResponseCode = '00', "
         "@Amount = ?", (payment["PaymentID"], f"SIM-{uuid.uuid4().hex}", payment["Amount"]), actor=_actor())
    return jsonify(query("SELECT OrderCode, OrderStatus, TotalAmount FROM dbo.Orders WHERE OrderID = ?",
                         (order["OrderID"],))[0] | {"PaymentStatus": "Success"})
