"""The shop pages read the API through adapters in frontend/src/js/core/api.js. This test feeds those adapters with
real answers of the API (run by Node, no browser) and checks the shapes the pages rely on, so renaming a column or a
field in the API cannot silently break the pages. Skipped when Node is not installed."""
import datetime
import json
import re
import shutil
import subprocess
import uuid
from pathlib import Path

import pytest

from app.config import FRONTEND_DIR
from app.db import query, transaction
from test_orders import CHEAP, DEAL, MID, SMALL, add_to_cart, checkout, new_admin, new_customer
from test_guest_orders import guest_order

NODE = shutil.which("node")
HARNESS = Path(__file__).parent / "js" / "adapters.js"
API_JS = FRONTEND_DIR / "src" / "js" / "core" / "api.js"
RING = CHEAP.format(11)          # a ring that can be engraved
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

pytestmark = pytest.mark.skipif(NODE is None, reason="Node is not installed")


def real_errors(customer, address_id):
    """Real error answers of the API, in the order the test below expects them: [{"status", "body"}]."""
    answers = []

    def keep(res):
        answers.append({"status": res.status_code, "body": res.get_json()})

    visitor = customer.application.test_client()
    keep(visitor.post("/api/auth/login", json={"email": "nobody@example.test", "password": "wrong-password-1"}))     # 0
    keep(visitor.post("/api/auth/register", json={"fullName": "Trùng Email", "email": customer.get("/api/auth/me").get_json()["email"],
                                                  "password": "Mat@khau123"}))                                  # 1
    with transaction() as cur:
        cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = 1 WHERE VariantSKU = ?", (SMALL,))
    keep(add_to_cart(customer, SMALL, 2))                                                                         # 2
    with transaction() as cur:
        cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = 100 WHERE VariantSKU = ?", (SMALL,))
    quote_only = query("SELECT TOP (1) v.VariantSKU FROM dbo.ProductVariants v JOIN dbo.Products p ON p.ProductID = v.ProductID "
                       "WHERE p.IsQuoteOnly = 1 ORDER BY v.VariantID")[0]["VariantSKU"]
    keep(add_to_cart(customer, quote_only))                                                                       # 3
    keep(visitor.get("/api/orders/VN000000000000", query_string={"phone": "0911111111"}))                          # 4
    code = next(o for o in customer.get("/api/orders").get_json() if o["CancelChannel"] == "Hotline")["OrderCode"]   # the engraved order
    keep(customer.post(f"/api/orders/{code}/cancel", json={"reason": "thử"}))                                      # 5
    assert add_to_cart(customer, SMALL).status_code in (200, 201)
    keep(customer.post("/api/vouchers/check", json={"code": "VINORA500K"}))                                        # 6 min order
    keep(customer.post("/api/vouchers/check", json={"code": "NO-SUCH-CODE"}))                                      # 7 not found
    keep(visitor.get("/api/cart"))                                                                                 # 8 login needed
    phone = "09" + str(uuid.uuid4().int)[:8]
    assert visitor.post("/api/auth/register", json={"fullName": "Có Tài Khoản", "email": f"err-{uuid.uuid4().hex[:8]}@example.test",
                                                    "password": "Mat@khau123", "phone": phone}).status_code == 201
    _, res = guest_order(customer.application.test_client(), phone)                                               # 9 phone has an account
    keep(res)
    return answers


APPOINTMENT_NOTE = "Showroom: Showroom Quận 1 | SĐT: 0901234567 | Ảnh chọn: 2 (chưa lưu)\nNhẫn bị xỉn nhẹ"      # as VN.ghiChuLich writes it


def warranty_samples():
    """The real answers of GET /api/warranties, GET /api/after-sales and the order for a customer with a delivered ring, one booking
    and a review of the order."""
    customer, address = new_customer()
    assert add_to_cart(customer, RING).status_code == 201
    code = checkout(customer, address).get_json()["OrderCode"]
    admin = new_admin()
    for status in ("Confirmed", "Shipping"):
        assert admin.post(f"/api/admin/orders/{code}/status", json={"status": status}).status_code == 200
    assert customer.post(f"/api/orders/{code}/confirm-received").status_code == 200
    card = customer.get("/api/warranties").get_json()[0]
    when = (datetime.datetime.now() + datetime.timedelta(days=3)).replace(hour=14, minute=0, second=0, microsecond=0)
    res = customer.post("/api/after-sales", json={"warrantyCode": card["WarrantyCode"], "serviceType": "Polishing",
                                                  "preferredDate": when.isoformat(), "note": APPOINTMENT_NOTE})
    assert res.status_code == 201, res.get_json()
    assert customer.post(f"/api/orders/{code}/feedback", json={"rating": 4, "text": "Đẹp", "topics": ["Đúng size", "Nhầm size nhẫn"]}).status_code == 201
    row = next(o for o in customer.get("/api/orders").get_json() if o["OrderCode"] == code)
    return (customer.get("/api/warranties").get_json(), customer.get("/api/after-sales").get_json(),
            customer.get(f"/api/orders/{code}").get_json(), row)


@pytest.fixture(scope="module")
def adapted(db_ready, tmp_path_factory):
    with transaction() as cur:
        cur.execute("UPDATE dbo.ProductVariants SET StockQuantity = 100 WHERE VariantSKU IN (?, ?, ?, ?)", (MID, SMALL, DEAL, RING))
    client, address_id = new_customer()
    get = lambda url: client.get(url).get_json()      # noqa: E731
    samples = {
        "productPages": [get(f"/api/products?limit=100&page={n}") for n in range(1, 6)],
        "detail": get("/api/products/NDINO131LDIA"),
        "categories": get("/api/categories"),
        "collections": get("/api/collections"),
    }
    # An engraved ring in the cart, one order paid online (shows a payment deadline) and one cash order
    assert add_to_cart(client, RING, 2, engravingText="Anh & Em", engravingStyle="Handwritten").status_code == 201
    samples["cart"] = get("/api/cart")
    assert checkout(client, address_id, method="VNPay").status_code == 201
    assert add_to_cart(client, SMALL).status_code == 201
    assert checkout(client, address_id, method="COD").status_code == 201
    samples["me"] = get("/api/auth/me")
    samples["profile"] = get("/api/profile")
    samples["addresses"] = get("/api/addresses")
    samples["orders"] = get("/api/orders")
    samples["orderDetails"] = [get(f"/api/orders/{o['OrderCode']}") for o in samples["orders"]]
    phone, res = guest_order(client.application.test_client(), items=[{"variantSku": SMALL, "quantity": 1}])
    samples["guestOrder"] = client.application.test_client().get(f"/api/orders/{res.get_json()['OrderCode']}",
                                                                  query_string={"phone": phone}).get_json()
    samples["errors"] = real_errors(client, address_id)
    samples["warranties"], samples["services"], samples["reviewedOrder"], samples["reviewedRow"] = warranty_samples()
    path = tmp_path_factory.mktemp("adapters") / "samples.json"
    path.write_text(json.dumps(samples), encoding="utf-8")
    run = subprocess.run([NODE, str(HARNESS), str(API_JS), str(path)], capture_output=True, text=True, encoding="utf-8", timeout=60)
    assert run.returncode == 0, run.stderr
    return json.loads(run.stdout)


def test_every_product_has_what_the_cards_and_filters_use(adapted):
    products = adapted["products"]
    assert len(products) == 443 and len({p["ma"] for p in products}) == 443
    for p in products:
        assert p["ma"] and p["ten"] and p["danhMuc"] and p["chatLieu"], p["ma"]
        assert isinstance(p["mau"], list) and 1 <= len(p["anh"]) <= 2, p["ma"]
        assert DATE.match(p["ngayTao"]), p["ma"]
        assert isinstance(p["canChonSize"], bool) and isinstance(p["coMoTa"], bool)
        assert p["coTheMua"] == (p["giaBan"] is not None), p["ma"]
    assert sum(not p["coTheMua"] for p in products) == 22            # the gold priced products are sold by quote only
    assert all(p["giaBan"] is None and p["gia"] is None for p in products if not p["coTheMua"])


def test_a_discount_is_a_percentage_of_the_old_price(adapted):
    sale = [p for p in adapted["products"] if p["giaCu"]]
    assert sale and all(p["giaCu"] > p["giaBan"] and p["giam"] == round((p["giaCu"] - p["giaBan"]) * 100 / p["giaCu"]) for p in sale)
    assert all(p["giam"] is None for p in adapted["products"] if not p["giaCu"])


def test_the_detail_has_all_images_stones_and_variants(adapted):
    detail = adapted["detail"]
    assert detail["ma"] == "NDINO131LDIA" and len(detail["anh"]) == 8 and detail["mau"] == ["Vàng Trắng"]
    assert detail["da"] == {"kichThuoc": "1.25 mm", "soVien": 14, "ten": detail["da"]["ten"]}
    variants = {v["ma"]: v for v in detail["bienThe"]}
    assert variants["NDINO131LDIA-VT-10"]["size"] == 10 and variants["NDINO131LDIA-VT-10"]["mau"] == "Vàng Trắng"
    assert all(isinstance(v["tonKho"], int) for v in variants.values()) and detail["khacDuoc"] is True


def test_categories_and_collections_keep_the_names_the_pages_use(adapted):
    assert [c["ten"] for c in adapted["categories"]][:3] == ["Nhẫn cầu hôn", "Nhẫn cưới", "Nhẫn thời trang"]
    assert all({"id", "ten", "nhom", "moTa", "soLuong"} <= c.keys() for c in adapted["categories"])
    evermore = next(b for b in adapted["collections"] if b["ten"] == "Evermore")
    assert evermore["soLuong"] == 87 and "Nhẫn cầu hôn" in evermore["loaiSanPham"] and "14K" in evermore["chatLieu"]


def test_a_cart_line_keeps_colour_size_and_the_engraving_in_page_codes(adapted):
    (line,) = adapted["cartLines"]
    product_sku = query("SELECT p.SKU FROM dbo.ProductVariants v JOIN dbo.Products p ON p.ProductID = v.ProductID "
                        "WHERE v.VariantSKU = ?", (RING,))[0]["SKU"]
    assert line["bienThe"] == RING and line["ma"] == product_sku
    assert line["size"] == 11 and line["soLuong"] == 2 and line["khacChu"] == "Anh & Em" and line["kieuChu"] == "viet-tay"
    assert line["donGia"] > 0 and line["tonKho"] > 0 and isinstance(line["id"], int)


def test_the_customer_and_the_address_book(adapted):
    customer = adapted["customer"]
    assert customer["vaiTro"] == "customer" and customer["email"].endswith("@example.test") and customer["hoTen"] == "Khách Test"
    (address,) = customer["diaChi"]
    assert address["macDinh"] is True and address["tinh"] == "Thành phố Hồ Chí Minh" and address["diaChi"] == "1 Lê Lợi"
    assert address["phuongXa"] == "Phường Bến Thành" and address["hoTen"] == "Khách Test" and isinstance(address["id"], int)


def test_the_order_list_and_detail_in_page_shape(adapted):
    cash, online = adapted["orderDetails"]      # newest first: the cash order, then the online one
    assert online["thanhToan"]["phuongThuc"] == "VNPAY" and cash["thanhToan"]["phuongThuc"] == "COD"
    assert online["trangThai"] == "Pending" and online["hanThanhToan"] and cash["hanThanhToan"] is None   # only an unpaid online order has a deadline
    assert online["kenhHuy"] == "Hotline" and online["coKhacChu"] is True       # an engraved order is cancelled by phone
    assert cash["kenhHuy"] == "Web" and cash["tongTien"] == 139000 + 30000
    item = online["sanPham"][0]
    assert item["maBienThe"] == RING and item["size"] == 11 and item["khacChu"] == "Anh & Em" and item["kieuChu"] == "viet-tay"
    assert item["soLuong"] == 2 and item["donGia"] > 0 and item["laNhan"] is True
    assert online["nguoiNhan"]["hoTen"] == "Khách Test" and "1 Lê Lợi" in online["nguoiNhan"]["diaChi"]
    assert [l["trangThai"] for l in online["lichSu"]][0] == "Pending"
    # the list rows carry the same totals and items, but not the address or the history
    row = next(o for o in adapted["orders"] if o["ma"] == cash["ma"])
    assert row["tongTien"] == cash["tongTien"] and row["sanPham"][0]["maBienThe"] == cash["sanPham"][0]["maBienThe"]
    assert "nguoiNhan" not in row and row["kenhHuy"] == "Web"


def test_a_guest_order_keeps_the_phone_it_was_looked_up_with(adapted):
    order = adapted["guestOrder"]
    assert order["ma"].startswith("VN") and order["sdtKhach"] == "0912345678" and order["khachHang"] is None
    assert order["thanhToan"]["phuongThuc"] == "COD" and order["sanPham"][0]["maBienThe"] == SMALL


def test_a_warranty_card_in_page_shape(adapted):
    (card,) = adapted["cards"]
    assert card["ma"].startswith("VNW") and card["donHang"].startswith("VN") and card["maSP"] and card["tenSP"] and card["conHieuLuc"] is True
    assert card["laNhan"] is True and card["size"] == 11 and card["chatLieu"] and card["hieuLuc"] == "Trọn đời"
    assert card["hanMuc"] == {"Cleaning": None, "Polishing": 5, "Resizing": None}        # null = no limit
    assert card["daDung"] == {"Cleaning": 0, "Polishing": 0, "Resizing": 0} and card["lichSuDichVu"] == []
    assert card["anh"] and DATE.match(card["ngayKichHoat"][:10])


def test_an_appointment_in_page_shape_and_its_note_reads_back(adapted):
    (service,) = adapted["services"]
    assert service["ma"] == f"LH{service['id']}" and service["trangThai"] == "Pending" and service["dangMo"] is True
    assert service["loai"] == "Polishing" and service["maBaoHanh"].startswith("VNW") and service["khungGio"] == "14:00"
    assert DATE.match(service["ngayHen"]) and service["daDoiGio"] is False and service["sizeMoi"] is None
    assert (service["tenCuaHang"], service["sdt"], service["soAnh"], service["ghiChu"]) == ("Showroom Quận 1", "0901234567", 2, "Nhẫn bị xỉn nhẹ")
    assert adapted["noteRoundTrip"] == APPOINTMENT_NOTE


def test_an_order_carries_its_review(adapted):
    expected = {"ma": adapted["reviewedOrder"]["danhGia"]["ma"], "donHang": adapted["reviewedOrder"]["ma"], "soSao": 4,
                "noiDung": "Đẹp", "chuDe": ["Đúng size", "Nhầm size nhẫn"]}
    for order in (adapted["reviewedOrder"], adapted["reviewedRow"]):               # the detail and the list row
        assert order["daDanhGia"] is True and isinstance(order["danhGia"]["ma"], int) and DATE.match(order["danhGia"]["luc"][:10])
        assert {k: order["danhGia"][k] for k in expected} == expected
    cash = adapted["orderDetails"][0]
    assert cash["daDanhGia"] is False and cash["danhGia"] is None             # an order nobody reviewed


def test_the_pages_do_not_use_the_removed_demo_data():
    """The demo accounts and the browser-only order store are gone; a page that still calls them would break at run time."""
    gone = re.compile(r"VN\.(demo|DEMO|otp|QUAN_TRI_DEMO|bamMatKhau)\b|VN\.donHang\.(tatCa|luuTatCa|tao\(\{\s*sanPham|doiSangCOD|ghiThanhToan)|VN\.gioHang\.(luu|ds\(\)\.find)|VN\.baoHanh\.(kichHoatChoDon|ghiDichVu|taoMa|luuTatCa)|VN\.lichHen\.(capNhat|luuTatCa)|VN\.danhGia\.(tatCa|theoDon|phanLoai|phanHoi)")
    offenders = []
    for path in sorted((FRONTEND_DIR / "src" / "js").glob("*/*.js")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if gone.search(line):
                offenders.append(f"{path.relative_to(FRONTEND_DIR)}:{number}")
    assert not offenders, offenders


def test_the_client_turns_real_api_errors_into_vietnamese_messages(adapted):
    errors = adapted["errors"]
    wanted = [
        "Email hoặc mật khẩu chưa đúng. Vui lòng kiểm tra lại.",
        "Email này đã được dùng để đăng ký. Vui lòng đăng nhập hoặc dùng email khác.",
        "Số lượng trong kho không đủ cho lựa chọn này.",
        "Sản phẩm này chỉ báo giá, không bán trực tuyến. Vui lòng liên hệ cửa hàng để được báo giá.",
        "Không tìm thấy đơn hàng khớp với mã đơn và số điện thoại này. Vui lòng kiểm tra lại.",
        None,                                                                         # 5: the stored procedure's own text, shown as it is
        "Mã ưu đãi áp dụng cho đơn từ 10.000.000 ₫.",
        "Mã ưu đãi không tồn tại hoặc đã hết hạn.",
        "Vui lòng đăng nhập để tiếp tục.",
        "Số điện thoại này đã có tài khoản. Vui lòng đăng nhập để đặt hàng.",
    ]
    assert len(errors) == len(wanted)
    for index, expected in enumerate(wanted):
        if expected is not None:
            assert errors[index]["message"] == expected, (index, errors[index])
    hotline = errors[5]
    assert hotline["status"] == 403 and hotline["code"] == 50029 and "hotline" in hotline["message"].lower()
    assert [e["reason"] for e in errors if e["reason"]] == ["quote_only", "min_order", "not_found", "phone_has_account"]
