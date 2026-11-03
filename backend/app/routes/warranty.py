"""Warranty cards and after-sales appointments for customers. The database creates a card for every unit when an order is
delivered (a trigger); the rules of booking, completing and cancelling live in the stored procedures (sp_*AfterSalesService).
The shop side of the appointments is in admin_shop.py."""
from datetime import datetime

from flask import Blueprint, g, jsonify

from ..auth import customer_or_guest, customer_required
from ..db import call, query
from ..validation import body, is_int, text, utf16_len

bp = Blueprint("warranty", __name__, url_prefix="/api")

SERVICE_TYPES = ("Cleaning", "Polishing", "Replating", "Resizing")

# One card with what the pages need: the product, the size now, the quotas of the card's policy and what is used.
# Quotas of NULL mean no limit. PolishingCountLeft is what is left of the free polishing and plating turns.
_CARD = (
    "SELECT v.WarrantyCode, v.IssueDate, v.Status, v.OrderCode, p.SKU AS ProductSKU, v.ProductName, v.SKU AS VariantSKU, "
    "oi.MaterialSnap AS Material, oi.GoldColor, oi.EngravingText, v.PurchasedRingSize, v.RingSize, c.RequiresRingSize AS IsRing, "
    "v.PolicyName, wp.CleaningQuota, wp.PolishingQuota, wp.ResizingQuota, v.PolishingCountLeft, v.CleaningCount, v.ResizingCount, "
    "v.CompletedServices "
    "FROM dbo.vw_CustomerWarranties v JOIN dbo.WarrantyRecords w ON w.WarrantyID = v.WarrantyID "
    "JOIN dbo.OrderItems oi ON oi.OrderItemID = w.OrderItemID JOIN dbo.Products p ON p.ProductID = w.ProductID "
    "JOIN dbo.Categories c ON c.CategoryID = p.CategoryID JOIN dbo.WarrantyPolicies wp ON wp.WarrantyPolicyID = w.WarrantyPolicyID ")

_SERVICE = (
    "SELECT s.ServiceID, s.ServiceType, s.PreferredDate, s.AppointmentDate, s.NewRingSize, s.Status, s.CustomerNote, "
    "s.ResultNote, s.IsFreeOfCharge, s.ServiceFee, s.CreatedAt, s.CompletedAt, w.WarrantyCode, oi.ProductNameSnap AS ProductName "
    "FROM dbo.AfterSalesServices s JOIN dbo.WarrantyRecords w ON w.WarrantyID = s.WarrantyID "
    "JOIN dbo.OrderItems oi ON oi.OrderItemID = w.OrderItemID ")


@bp.get("/warranties")
@customer_required
def my_warranties():
    """All my warranty cards, newest first."""
    return jsonify(query(_CARD + "WHERE v.CustomerID = ? ORDER BY v.WarrantyID DESC", (g.customer_id,)))


@bp.get("/orders/<code>/warranties")
@customer_or_guest
def order_warranties(code: str):
    """The cards of one of my orders (empty until the order is delivered). A guest sends ?phone=<the phone used for the order>."""
    if not query("SELECT 1 AS x FROM dbo.Orders WHERE OrderCode = ? AND CustomerID = ?", (code, g.customer_id)):
        return jsonify(error="Order not found"), 404
    return jsonify(query(_CARD + "WHERE v.OrderCode = ? AND v.CustomerID = ? ORDER BY v.WarrantyID", (code, g.customer_id)))


@bp.get("/warranties/<code>")
def look_up_warranty(code: str):
    """Look a card up by its code (anyone can: the code is the proof). Only what the product says, never the owner."""
    code = "".join(code.split()).upper()
    rows = query("SELECT v.WarrantyCode, v.IssueDate, v.Status, v.ProductName, p.SKU AS ProductSKU, v.PolicyName "
                 "FROM dbo.vw_CustomerWarranties v JOIN dbo.WarrantyRecords w ON w.WarrantyID = v.WarrantyID "
                 "JOIN dbo.Products p ON p.ProductID = w.ProductID WHERE v.WarrantyCode = ?", (code,))
    if not rows:
        return jsonify(error="Warranty card not found"), 404
    return jsonify(rows[0])


@bp.get("/after-sales")
@customer_required
def my_services():
    """All my after-sales appointments, newest first."""
    return jsonify(query(_SERVICE + "WHERE w.CustomerID = ? ORDER BY s.ServiceID DESC", (g.customer_id,)))


def _my_service(service_id: int):
    rows = query(_SERVICE + "WHERE s.ServiceID = ? AND w.CustomerID = ?", (service_id, g.customer_id))
    return rows[0] if rows else None


@bp.post("/after-sales")
@customer_required
def book_service():
    """Book an appointment (sp_BookAfterSalesService). Body: warrantyCode, serviceType (Cleaning, Polishing, Replating,
    Resizing), preferredDate (local date and time, ISO text, in the future and within a year), newRingSize (only for
    Resizing), note (up to 500). A card can have one open appointment for each type of service."""
    data = body()
    code, kind, when, note = text(data, "warrantyCode"), data.get("serviceType"), data.get("preferredDate"), text(data, "note")
    size = data.get("newRingSize")
    if not code or len(code) > 20 or kind not in SERVICE_TYPES or None in (note,) or utf16_len(note) > 500 \
            or (size is not None and not is_int(size, 1, 255)) or not isinstance(when, str):
        return jsonify(error="warrantyCode, serviceType, preferredDate are required; note is text up to 500 characters"), 400
    try:
        when = datetime.fromisoformat(when).replace(tzinfo=None)      # the database keeps local time without a zone
    except ValueError:
        return jsonify(error="preferredDate must be a date and time such as 2026-12-01T10:00"), 400
    service = call("DECLARE @s INT; EXEC dbo.sp_BookAfterSalesService @WarrantyCode = ?, @CustomerID = ?, @ServiceType = ?, "
                   "@PreferredDate = ?, @NewRingSize = ?, @CustomerNote = ?, @ServiceID = @s OUTPUT; SELECT @s AS id",
                   ("".join(code.split()).upper(), g.customer_id, kind, when, size, note.strip() or None),
                   actor=(g.user["UserID"], f"Customer:{g.customer_id}"))[0]["id"]
    return jsonify(_my_service(service)), 201


@bp.post("/after-sales/<int:service_id>/cancel")
@customer_required
def cancel_service(service_id: int):
    """Cancel my appointment that is not completed (sp_CancelAfterSalesService). The card loses no turn."""
    call("EXEC dbo.sp_CancelAfterSalesService @ServiceID = ?, @CustomerID = ?", (service_id, g.customer_id),
         actor=(g.user["UserID"], f"Customer:{g.customer_id}"))
    return jsonify(_my_service(service_id))
