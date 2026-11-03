"""Tests for the review a customer writes after an order is delivered (backend/app/routes/feedback.py)."""
import pytest

from app.db import query
from test_guest_orders import guest_order
from test_orders import add_to_cart, checkout, new_admin, new_customer
from test_warranty import RING, delivered, restock  # noqa: F401  (restock is an autouse fixture)


def review(client, code, **extra):
    body = {"rating": 5, "text": "Nhẫn sáng bóng", "topics": ["Độ sáng bóng"]}
    body.update(extra)
    return client.post(f"/api/orders/{code}/feedback", json=body)


# ---------------- who may call ----------------

def test_a_visitor_or_an_admin_cannot_review(client):
    assert client.post("/api/orders/VN1/feedback", json={"rating": 5}).status_code == 401
    assert review(new_admin(), "VN1").status_code == 403


# ---------------- writing a review ----------------

def test_a_delivered_order_can_be_reviewed_and_the_review_comes_back_with_the_order(client):
    c, code = delivered()
    res = review(c, code, rating=4, text="  Rất đẹp  ", topics=["Độ sáng bóng", "Đúng size", "Độ sáng bóng"])
    assert res.status_code == 201
    body = res.get_json()
    assert body["RatingStar"] == 4 and body["ReviewText"] == "Rất đẹp"
    assert [(a["AspectName"], a["Polarity"]) for a in body["aspects"]] == [("Độ sáng bóng", "Positive"), ("Đúng size", "Positive")]
    detail = c.get(f"/api/orders/{code}").get_json()["feedback"]
    assert detail["FeedbackID"] == body["FeedbackID"] and len(detail["aspects"]) == 2
    listed = {o["OrderCode"]: o for o in c.get("/api/orders").get_json()}
    assert listed[code]["feedback"]["RatingStar"] == 4


def test_an_order_without_a_review_says_so(client):
    c, code = delivered()
    assert c.get(f"/api/orders/{code}").get_json()["feedback"] is None
    assert c.get("/api/orders").get_json()[0]["feedback"] is None


def test_the_shop_sees_the_review_with_a_simulated_sentiment(client):
    c, code = delivered()
    review(c, code, rating=5)
    mine = next(f for f in new_admin().get("/api/admin/feedbacks").get_json() if f["OrderCode"] == code)
    assert mine["RatingStar"] == 5 and mine["SentimentLabel"] == "Positive" and mine["IsSentimentSimulated"] in (True, 1)
    assert [a["AspectName"] for a in mine["aspects"]] == ["Độ sáng bóng"]


@pytest.mark.parametrize("rating,text,topics,label", [
    (5, "", [], "Positive"),
    (4, "Giao trễ nhưng đẹp", [], "Positive"),                 # 4 and 5 stars are positive whatever the words say
    (2, "Cũng được", [], "Negative"),
    (1, "", [], "Negative"),
    (3, "Bình thường", [], "Positive"),
    (3, "Bình thường", ["Sản phẩm trầy xước"], "Negative"),    # a complaint topic is ticked
    (3, "Giao trễ so với hẹn", [], "Negative"),                # a complaint word in the text
    (3, "Hơi TRẦY", [], "Negative"),                           # capitals do not matter
    (3, "giao tre roi", [], "Negative"),                      # typed without accents
    (3, "Màu bị XỈN", [], "Negative"),
    (3, "Có lỗi nhỏ ở hộp", [], "Negative"),
    (3, "Nhẫn rất xinh, chăm sóc tốt", [], "Positive"),        # a complaint word inside another word is not a complaint
    (3, "Chuyển phát từ Sài Gòn", [], "Positive"),
    (3, "Có lời khen cho shop", [], "Positive"),               # "lời" is not "lỗi"
])
def test_the_simulated_sentiment_follows_the_stars_then_the_words(client, rating, text, topics, label):
    c, code = delivered()
    assert review(c, code, rating=rating, text=text, topics=topics).status_code == 201
    row = query("SELECT f.SentimentLabel, f.IsSentimentSimulated, f.ReviewText FROM dbo.CustomerFeedbacks f "
                "JOIN dbo.Orders o ON o.OrderID = f.OrderID WHERE o.OrderCode = ?", (code,))[0]
    assert row["SentimentLabel"] == label and row["IsSentimentSimulated"]
    assert row["ReviewText"] == (text or None)               # no text is stored as NULL


def test_complaint_topics_are_stored_as_negative(client):
    c, code = delivered()
    res = review(c, code, rating=2, topics=["Nhầm size nhẫn", "Tư vấn tận tình"])
    assert {a["AspectName"]: a["Polarity"] for a in res.get_json()["aspects"]} == {"Nhầm size nhẫn": "Negative", "Tư vấn tận tình": "Positive"}


# ---------------- rules ----------------

def test_an_order_can_be_reviewed_once(client):
    c, code = delivered()
    assert review(c, code).status_code == 201
    again = review(c, code, rating=1)
    assert again.status_code == 409
    assert c.get(f"/api/orders/{code}").get_json()["feedback"]["RatingStar"] == 5


def test_an_order_that_is_not_delivered_cannot_be_reviewed(client):
    c, address = new_customer()
    add_to_cart(c, RING)
    code = checkout(c, address).get_json()["OrderCode"]
    assert review(c, code).status_code == 409
    assert query("SELECT COUNT(*) AS n FROM dbo.CustomerFeedbacks f JOIN dbo.Orders o ON o.OrderID = f.OrderID "
                 "WHERE o.OrderCode = ?", (code,))[0]["n"] == 0


def test_nobody_reviews_another_customers_order(client):
    _, code = delivered()
    other, _ = new_customer()
    assert review(other, code).status_code == 404
    assert review(other, "VN000000000").status_code == 404


@pytest.mark.parametrize("extra", [
    {"rating": 0}, {"rating": 6}, {"rating": "5"}, {"rating": True}, {"rating": None}, {"rating": 4.5},
    {"text": "x" * 501}, {"text": 5}, {"text": ["a"]},
    {"topics": ["Không có chủ đề này"]}, {"topics": "Độ sáng bóng"}, {"topics": [5]}, {"topics": {"a": 1}},
])
def test_bad_review_requests_are_400_and_nothing_is_saved(client, extra):
    c, code = delivered()
    assert review(c, code, **extra).status_code == 400
    assert c.get(f"/api/orders/{code}").get_json()["feedback"] is None


def test_the_text_limit_counts_utf16_units_like_the_database(client):
    c, code = delivered()
    assert review(c, code, text="😀" * 251).status_code == 400          # 502 units
    assert review(c, code, text="😀" * 250).status_code == 201          # 500 units


def test_two_reviews_of_one_order_at_the_same_moment_give_a_clear_409(client, monkeypatch):
    """The second request passed the 'already reviewed?' check before the first one saved; the table's UNIQUE answers."""
    import app.routes.feedback as feedback
    c, code = delivered()
    assert review(c, code).status_code == 201
    real_query = feedback.query
    monkeypatch.setattr(feedback, "query", lambda sql, params=(): [] if sql.startswith("SELECT 1 AS x FROM dbo.CustomerFeedbacks") else real_query(sql, params))
    res = review(c, code, rating=1)
    assert res.status_code == 409 and "already been reviewed" in res.get_json()["error"]
    assert query("SELECT COUNT(*) AS n FROM dbo.CustomerFeedbacks f JOIN dbo.Orders o ON o.OrderID = f.OrderID WHERE o.OrderCode = ?", (code,))[0]["n"] == 1


def test_a_review_without_text_or_topics_is_fine_and_text_of_500_characters_too(client):
    c, code = delivered()
    assert c.post(f"/api/orders/{code}/feedback", json={"rating": 3}).status_code == 201
    c2, code2 = delivered()
    assert review(c2, code2, text="đ" * 500).status_code == 201


# ---------------- a guest ----------------

def test_a_guest_reviews_with_the_phone_of_the_order(client):
    visitor = client.application.test_client()
    phone, res = guest_order(visitor)
    code = res.get_json()["OrderCode"]
    admin = new_admin()
    for status in ("Confirmed", "Shipping"):
        admin.post(f"/api/admin/orders/{code}/status", json={"status": status})
    assert visitor.post(f"/api/orders/{code}/confirm-received", json={"phone": phone}).status_code == 200
    assert visitor.post(f"/api/orders/{code}/feedback", json={"rating": 5}).status_code == 401           # no proof
    assert visitor.post(f"/api/orders/{code}/feedback", json={"rating": 5, "phone": "0900000000"}).status_code == 404
    res = visitor.post(f"/api/orders/{code}/feedback", json={"rating": 5, "text": "Tốt", "phone": phone})
    assert res.status_code == 201
    assert visitor.get(f"/api/orders/{code}", query_string={"phone": phone}).get_json()["feedback"]["ReviewText"] == "Tốt"
