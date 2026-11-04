"""Admin-only endpoints for customers, products, reviews, warranty cards and after-sales appointments.
Orders are in admin.py. The business rules of appointments live in the stored procedures; these routes call them."""
from datetime import datetime

from flask import Blueprint, g, jsonify

from ..auth import admin_required
from ..db import call, query, transaction
from ..validation import body, is_int, text, utf16_len

bp = Blueprint("admin_shop", __name__, url_prefix="/api/admin")

PRODUCT_STATUSES = ("Active", "Hidden", "Discontinued")
MAX_PRICE = 999_999_999_999     # DECIMAL(15,0) with room to spare


def _actor():
    return (g.user["UserID"], f"Admin:{g.user['UserID']}")


# ---------------- customers ----------------

@bp.get("/customers")
@admin_required
def list_customers():
    """Every customer, with an account or a guest (the phone number is the guest's id), with what they bought.
    TotalPaid counts successful payments only, so refunded and cancelled orders are left out."""
    return jsonify(query(
        "SELECT c.CustomerID, c.Phone, u.Email, COALESCE(u.FullName, last_order.ShipRecipientName) AS CustomerName, "
        "CAST(CASE WHEN c.UserID IS NULL THEN 1 ELSE 0 END AS BIT) AS IsGuest, COALESCE(u.CreatedAt, c.CreatedAt) AS CreatedAt, "
        "(SELECT COUNT(*) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS OrderCount, "
        "(SELECT COALESCE(SUM(p.Amount), 0) FROM dbo.Payments p JOIN dbo.Orders o ON o.OrderID = p.OrderID "
        " WHERE o.CustomerID = c.CustomerID AND p.Status = 'Success') AS TotalPaid, "
        "(SELECT MAX(o.CreatedAt) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS LastOrderAt, "
        "(SELECT COUNT(*) FROM dbo.WarrantyRecords w WHERE w.CustomerID = c.CustomerID) AS WarrantyCount "
        "FROM dbo.Customers c LEFT JOIN dbo.Users u ON u.UserID = c.UserID "
        "OUTER APPLY (SELECT TOP (1) ShipRecipientName FROM dbo.Orders WHERE CustomerID = c.CustomerID ORDER BY OrderID DESC) last_order "
        "ORDER BY c.CustomerID"))


# ---------------- reviews ----------------

@bp.get("/feedbacks")
@admin_required
def list_feedbacks():
    """All reviews, newest first, with the aspects found in the text. SentimentLabel is only for the shop (the
    customer never sees it); IsSentimentSimulated says the label was made by the simulated analysis."""
    rows = query(
        "SELECT f.FeedbackID, o.OrderCode, f.CustomerID, COALESCE(u.FullName, o.ShipRecipientName) AS CustomerName, "
        "f.RatingStar, f.ReviewText, f.SentimentLabel, f.SentimentScore, f.IsSentimentSimulated, f.CreatedAt "
        "FROM dbo.CustomerFeedbacks f JOIN dbo.Orders o ON o.OrderID = f.OrderID "
        "JOIN dbo.Customers c ON c.CustomerID = f.CustomerID LEFT JOIN dbo.Users u ON u.UserID = c.UserID "
        "ORDER BY f.FeedbackID DESC")
    aspects: dict[int, list] = {}
    for a in query("SELECT FeedbackID, AspectName, Polarity FROM dbo.FeedbackAspects ORDER BY AspectID"):
        aspects.setdefault(a.pop("FeedbackID"), []).append(a)
    for row in rows:
        row["aspects"] = aspects.get(row["FeedbackID"], [])
    return jsonify(rows)


# ---------------- retention popup ----------------

@bp.get("/retention-stats")
@admin_required
def retention_stats():
    """How well the "cancel order" popup keeps orders (vw_RetentionStats, one row). Only cancel requests made on the web
    count. KeepRatePercent is null until the first request."""
    return jsonify(query("SELECT * FROM dbo.vw_RetentionStats")[0])


# ---------------- warranty cards and appointments ----------------

_WHO = ("COALESCE(u.FullName, o.ShipRecipientName) AS CustomerName, c.Phone AS CustomerPhone")


@bp.get("/warranties")
@admin_required
def list_warranties():
    """All warranty cards (vw_CustomerWarranties) with the owner. PolishingCountLeft is what is left of the free
    polishing and plating turns."""
    return jsonify(query(
        f"SELECT v.WarrantyCode, v.IssueDate, v.Status, v.OrderCode, v.ProductName, v.SKU, v.PurchasedRingSize, v.RingSize, "
        f"v.PolicyName, v.PolishingQuota, v.PolishingCountLeft, v.CleaningCount, v.ResizingCount, v.CompletedServices, {_WHO} "
        "FROM dbo.vw_CustomerWarranties v JOIN dbo.Orders o ON o.OrderCode = v.OrderCode "
        "JOIN dbo.Customers c ON c.CustomerID = v.CustomerID LEFT JOIN dbo.Users u ON u.UserID = c.UserID "
        "ORDER BY v.WarrantyID DESC"))


_SERVICE_SELECT = (
    "SELECT s.ServiceID, s.ServiceType, s.PreferredDate, s.AppointmentDate, s.NewRingSize, s.Status, s.CustomerNote, "
    "s.ResultNote, s.IsFreeOfCharge, s.ServiceFee, s.CreatedAt, s.CompletedAt, w.WarrantyCode, oi.ProductNameSnap AS ProductName, "
    f"o.OrderCode, {_WHO} FROM dbo.AfterSalesServices s JOIN dbo.WarrantyRecords w ON w.WarrantyID = s.WarrantyID "
    "JOIN dbo.OrderItems oi ON oi.OrderItemID = w.OrderItemID JOIN dbo.Orders o ON o.OrderID = w.OrderID "
    "JOIN dbo.Customers c ON c.CustomerID = w.CustomerID LEFT JOIN dbo.Users u ON u.UserID = c.UserID ")


@bp.get("/services")
@admin_required
def list_services():
    """All after-sales appointments, newest first."""
    return jsonify(query(_SERVICE_SELECT + "ORDER BY s.ServiceID DESC"))


def _service(service_id: int):
    rows = query(_SERVICE_SELECT + "WHERE s.ServiceID = ?", (service_id,))
    return rows[0] if rows else None


@bp.post("/services/<int:service_id>/schedule")
@admin_required
def schedule_service(service_id: int):
    """Confirm the appointment (sp_ScheduleAfterSalesService). Without appointmentDate the customer's preferred time is
    confirmed (status Confirmed); another time (ISO text, in the future) is a proposal (status Rescheduled)."""
    data = body()
    when = data.get("appointmentDate")
    if not _service(service_id):
        return jsonify(error="Appointment not found"), 404
    if when is not None:
        try:
            when = datetime.fromisoformat(str(when)).replace(tzinfo=None)     # the database keeps local time without a zone
        except ValueError:
            return jsonify(error="appointmentDate must be a date and time such as 2026-12-01T10:00"), 400
    # COALESCE: no date given -> the time the customer asked for
    call("DECLARE @when DATETIME2(0) = COALESCE(?, (SELECT PreferredDate FROM dbo.AfterSalesServices WHERE ServiceID = ?)); "
         "EXEC dbo.sp_ScheduleAfterSalesService @ServiceID = ?, @AdminUserID = ?, @AppointmentDate = @when",
         (when, service_id, service_id, g.user["UserID"]), actor=_actor())
    return jsonify(_service(service_id))


@bp.post("/services/<int:service_id>/complete")
@admin_required
def complete_service(service_id: int):
    """The service is done (sp_CompleteAfterSalesService): one turn of the card is used, and the work is free or
    paid (ServiceFee) depending on what is left of the card's quota. Body: resultNote (optional, up to 500)."""
    note = text(body(), "resultNote")
    if note is None or utf16_len(note) > 500:
        return jsonify(error="resultNote is text up to 500 characters"), 400
    if not _service(service_id):
        return jsonify(error="Appointment not found"), 404
    call("EXEC dbo.sp_CompleteAfterSalesService @ServiceID = ?, @AdminUserID = ?, @ResultNote = ?",
         (service_id, g.user["UserID"], note.strip() or None), actor=_actor())
    return jsonify(_service(service_id))


@bp.post("/services/<int:service_id>/cancel")
@admin_required
def cancel_service(service_id: int):
    """The shop cancels an appointment that is not completed. The customer loses no turn."""
    row = query("SELECT w.CustomerID FROM dbo.AfterSalesServices s JOIN dbo.WarrantyRecords w ON w.WarrantyID = s.WarrantyID "
                "WHERE s.ServiceID = ?", (service_id,))
    if not row:
        return jsonify(error="Appointment not found"), 404
    call("EXEC dbo.sp_CancelAfterSalesService @ServiceID = ?, @CustomerID = ?", (service_id, row[0]["CustomerID"]), actor=_actor())
    return jsonify(_service(service_id))


# ---------------- products ----------------

@bp.get("/products")
@admin_required
def list_products():
    """All products, also the hidden and discontinued ones, with the number sold (not counting cancelled orders)."""
    return jsonify(query(
        "SELECT p.SKU, p.ProductName, p.CategoryID, p.Material, p.PricingMethod, p.Price, p.OriginalPrice, p.IsQuoteOnly, p.Status, "
        "(SELECT TOP (1) ImageUrl FROM dbo.ProductImages i WHERE i.ProductID = p.ProductID ORDER BY i.IsThumbnail DESC, i.SortOrder) AS ImageUrl, "
        "(SELECT COALESCE(SUM(oi.Quantity), 0) FROM dbo.OrderItems oi JOIN dbo.Orders o ON o.OrderID = oi.OrderID "
        " WHERE oi.ProductID = p.ProductID AND o.OrderStatus <> 'Cancelled') AS SoldQuantity "
        "FROM dbo.Products p ORDER BY p.ProductID"))


@bp.patch("/products/<sku>")
@admin_required
def update_product(sku: str):
    """Change the selling price, the price before the discount, or the status. Body: any of price, originalPrice (null
    removes the discount), status. Prices only for fixed price products; gold-rate products are sold by quote.
    The shop pages show the change when they reload the catalog (they keep it for 5 minutes)."""
    data = body()
    unknown = set(data) - {"price", "originalPrice", "status"}
    if unknown or not data:
        return jsonify(error="Send at least one of price, originalPrice, status"), 400
    rows = query("SELECT ProductID, PricingMethod, Price, OriginalPrice FROM dbo.Products WHERE SKU = ?", (sku,))
    if not rows:
        return jsonify(error="Product not found"), 404
    product = rows[0]
    sets, params = [], []
    if "status" in data:
        if data["status"] not in PRODUCT_STATUSES:
            return jsonify(error=f"status must be one of {', '.join(PRODUCT_STATUSES)}"), 400
        sets.append("Status = ?")
        params.append(data["status"])
    if "price" in data or "originalPrice" in data:
        if product["PricingMethod"] != "Fixed":
            return jsonify(error="Only fixed price products have a price to change"), 409
        price = data.get("price", product["Price"])
        original = data["originalPrice"] if "originalPrice" in data else product["OriginalPrice"]
        if not is_int(price, 1000, MAX_PRICE) or (original is not None and not is_int(original, 1, MAX_PRICE)):
            return jsonify(error="price is a whole number of VND from 1000; originalPrice is a whole number or null"), 400
        if original is not None and original < price:
            return jsonify(error="originalPrice must not be lower than price"), 400
        sets += ["Price = ?", "OriginalPrice = ?"]
        params += [price, original]
    with transaction() as cur:
        cur.execute(f"UPDATE dbo.Products SET {', '.join(sets)}, UpdatedAt = SYSDATETIME() WHERE ProductID = ?",
                    (*params, product["ProductID"]))
    return jsonify(query("SELECT SKU, Price, OriginalPrice, Status FROM dbo.Products WHERE ProductID = ?", (product["ProductID"],))[0])
