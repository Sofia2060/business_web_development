"""The review a customer (or a guest) writes after an order is delivered. One review per order.
A guest proves who they are with the phone number of the order, like on the other order endpoints."""
import re
import unicodedata

import pyodbc
from flask import Blueprint, g, jsonify

from ..auth import customer_or_guest
from ..db import query, transaction
from ..validation import body, is_int, text, utf16_len

bp = Blueprint("feedback", __name__, url_prefix="/api")

MAX_REVIEW_LENGTH = 500

# The topics the review form offers, and whether each one is praise or a complaint (FeedbackAspects.Polarity)
ASPECTS = {
    "Độ sáng bóng": "Positive", "Đóng gói sang trọng": "Positive", "Chữ khắc đẹp": "Positive",
    "Đúng size": "Positive", "Giao hàng đúng hẹn": "Positive", "Tư vấn tận tình": "Positive",
    "Nhầm size nhẫn": "Negative", "Giao trễ giờ kỷ niệm": "Negative", "Sản phẩm trầy xước": "Negative",
    "Chữ khắc chưa đẹp": "Negative",
}
# Complaint words, with and without accents (people often type without). Whole words only, and the accents count:
# "xinh" and "Sài Gòn" are not complaints, "xỉn" and "sai" are.
NEGATIVE_WORDS = ("trễ", "chậm", "nhầm", "sai", "xấu", "thất vọng", "lỗi", "hỏng", "không vừa", "trầy", "xỉn",
                  "tre", "cham", "nham", "xau", "that vong", "loi", "hong", "khong vua", "tray", "xin")
COMPLAINT = re.compile(r"(?<!\w)(?:" + "|".join(NEGATIVE_WORDS) + r")(?!\w)")


def simulated_sentiment(stars: int, review: str, topics: list[str]) -> str:
    """The simulated sentiment label (FR25; the row is marked IsSentimentSimulated). 4-5 stars are positive, 1-2 negative.
    Three stars are negative when a complaint topic is ticked or the text has a complaint word (a whole word)."""
    if stars >= 4:
        return "Positive"
    if stars <= 2:
        return "Negative"
    if any(ASPECTS[t] == "Negative" for t in topics) or COMPLAINT.search(unicodedata.normalize("NFC", review).lower()):
        return "Negative"
    return "Positive"


def feedbacks_where(condition: str, params: tuple) -> dict[int, dict]:
    """Reviews matching `condition` (on CustomerFeedbacks f), by OrderID, each with its topics."""
    rows = query("SELECT f.FeedbackID, f.OrderID, f.RatingStar, f.ReviewText, f.CreatedAt FROM dbo.CustomerFeedbacks f "
                 f"WHERE {condition}", params)
    if not rows:
        return {}
    topics: dict[int, list] = {}
    for a in query("SELECT a.FeedbackID, a.AspectName, a.Polarity FROM dbo.FeedbackAspects a "
                   f"JOIN dbo.CustomerFeedbacks f ON f.FeedbackID = a.FeedbackID WHERE {condition} ORDER BY a.AspectID", params):
        topics.setdefault(a.pop("FeedbackID"), []).append(a)
    by_order = {}
    for row in rows:
        row["aspects"] = topics.get(row["FeedbackID"], [])
        by_order[row.pop("OrderID")] = row
    return by_order


@bp.post("/orders/<code>/feedback")
@customer_or_guest
def create_feedback(code: str):
    """Body: rating (1 to 5), text (optional, up to 500 characters), topics (optional, names from the review form).
    Only a delivered order can be reviewed, and only once. A guest also sends phone."""
    data = body()
    rating, review, topics = data.get("rating"), text(data, "text"), data.get("topics") or []
    if (not is_int(rating, 1, 5) or review is None or utf16_len(review) > MAX_REVIEW_LENGTH
            or not isinstance(topics, list) or not all(isinstance(t, str) and t in ASPECTS for t in topics)):
        return jsonify(error=f"rating is 1 to 5; text is up to {MAX_REVIEW_LENGTH} characters; topics are names from the review form"), 400
    topics = list(dict.fromkeys(topics))      # a topic ticked twice counts once
    rows = query("SELECT OrderID, OrderStatus FROM dbo.Orders WHERE OrderCode = ? AND CustomerID = ?", (code, g.customer_id))
    if not rows:
        return jsonify(error="Order not found"), 404
    order_id = rows[0]["OrderID"]
    if rows[0]["OrderStatus"] != "Delivered":
        return jsonify(error="Only a delivered order can be reviewed"), 409
    if query("SELECT 1 AS x FROM dbo.CustomerFeedbacks WHERE OrderID = ?", (order_id,)):
        return jsonify(error="This order has already been reviewed"), 409
    review = review.strip()
    try:
        _save(order_id, rating, review, topics)
    except pyodbc.IntegrityError:      # another request reviewed the same order a moment ago (UNIQUE on the order)
        return jsonify(error="This order has already been reviewed"), 409
    return jsonify(feedbacks_where("f.OrderID = ?", (order_id,))[order_id]), 201


def _save(order_id: int, rating: int, review: str, topics: list[str]) -> None:
    with transaction() as cur:
        cur.execute("INSERT INTO dbo.CustomerFeedbacks (OrderID, CustomerID, RatingStar, ReviewText, SentimentLabel, AnalyzedAt) "
                    "VALUES (?, ?, ?, ?, ?, SYSDATETIME())",
                    (order_id, g.customer_id, rating, review or None, simulated_sentiment(rating, review, topics)))
        # The table has a trigger, so OUTPUT is not allowed; one review per order makes the order the key
        cur.execute("SELECT FeedbackID FROM dbo.CustomerFeedbacks WHERE OrderID = ?", (order_id,))
        feedback_id = cur.fetchval()
        for name in topics:
            cur.execute("INSERT INTO dbo.FeedbackAspects (FeedbackID, AspectName, Polarity) VALUES (?, ?, ?)",
                        (feedback_id, name, ASPECTS[name]))
