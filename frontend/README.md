# Vinora Jewelry – bản HTML thuần (mở bằng Live Server)

Không cần Python/Flask. Chỉ gồm HTML + CSS + JavaScript + dữ liệu JSON/XML.
Các trang không dùng `<!DOCTYPE html>` và thẻ `<meta>` (khung nhìn điện thoại được thêm bằng một đoạn script nhỏ trong `<head>`).

## Cách mở
Cách chính (có API và database): chạy `uv run python backend/run.py` ở gốc repo rồi mở `http://127.0.0.1:5000/`. Flask phục vụ thư mục này, xem README ở gốc repo.

Cách chỉ xem giao diện giả lập (không cần database):
1. Mở thư mục `frontend` bằng VS Code.
2. Cài tiện ích **Live Server** (Ritwick Dey) nếu chưa có.
3. Chuột phải `index.html` (ở gốc `frontend/`) → **Open with Live Server**. File này tự chuyển tới `src/pages/client/index.html`.

> Phải mở thư mục `frontend` làm gốc server, vì các trang dùng đường dẫn tương đối `../../../mock-data/` và `../../../public/`.
> Không bấm đúp mở file `.html` trực tiếp (đường dẫn `file://`): trình duyệt chặn AJAX đọc `mock-data/*.json` và `stores.xml`, trang sẽ không có sản phẩm.

## Cấu trúc
```
frontend/
├── index.html                       chuyển hướng tới trang chủ
├── public/
│   ├── fonts/
│   └── images/{logo,placeholders,products}/
├── mock-data/                       products, categories, collections, config, size-chart, provinces (.json), stores.xml
└── src/
    ├── pages/client/
    │   ├── index.html               5.2.1 Trang chủ
    │   ├── products.html           5.2.2 Danh sách sản phẩm (?danhmuc= ?bst= ?q= …)
    │   ├── product-detail.html     5.2.3 Chi tiết sản phẩm (?ma=MÃ_SKU) – nút yêu thích, giấy chứng nhận
    │   ├── recently-viewed.html    5.2.4 Sản phẩm đã xem
    │   ├── wishlist.html           Sản phẩm yêu thích (mới)
    │   ├── cart.html, checkout.html, order-success.html          5.2.5
    │   ├── orders.html (+ popup hủy đơn 5.2.6, phản ánh)         5.2.7 – tra cứu đơn khi chưa đăng nhập
    │   ├── warranty-activation.html, warranty-portal.html        5.2.8
    │   └── account, about, contact, size-guide,
    │       shipping-policy, warranty-policy, 404 (.html)
    ├── pages/admin/
    │   └── dashboard, orders, complaints, warranty, products, customers, reviews (.html)
    ├── css/  base/ · components/ · pages/ (mỗi trang khách một tệp) · admin/admin.css
    └── js/   core/common.js · components/ · pages/ (mỗi trang khách một tệp) · admin/ (admin.js + mỗi trang quản trị một tệp)
```

## Thông tin dùng khi trình bày (không hiển thị trên website)
Giao diện được làm như website bán hàng thật nên **không ghi tài khoản / mã thử nghiệm trên trang**. Khi trình bày dùng các thông tin sau:

| Mục đích | Thông tin |
|---|---|
| Tài khoản khách hàng có sẵn dữ liệu | `demo@vinora.vn` / `Vinora@2026` (5 đơn hàng, 2 thẻ bảo hành, 2 lịch hẹn, 1 đánh giá) |
| Tài khoản quản trị | `admin@vinora.vn` / `Admin@2026` |
| Thẻ ATM ở cổng VNPay | Số thẻ bất kỳ 16 – 19 chữ số (vd. `9704198526191432198`), tên chủ thẻ, ngày phát hành dạng `MM/YY` |
| Mã OTP (VNPay, xác minh số điện thoại) | `123456` |
| Mã ưu đãi | `VINORA5`, `CHAOBAN200`, `FREESHIP` |

Dữ liệu lưu bằng localStorage của trình duyệt (khóa `vinora.*`). Muốn đưa dữ liệu mẫu về ban đầu: đăng nhập quản trị → Tổng quan → **Tạo dữ liệu mẫu** (hiện khi chưa có đơn), hoặc xóa localStorage rồi đăng nhập lại tài khoản khách mẫu.
Phí giao hàng, ngân hàng nhận hoàn tiền, loại vấn đề phản ánh, quyền lợi bảo hành… chỉnh tập trung trong `mock-data/config.json`.

## Trang quản trị (admin)
Chỉ có **một ô đăng nhập** (trang Tài khoản – bấm icon tài khoản từ `index.html`). Hệ thống phân quyền theo tài khoản:
- Khách hàng (`demo@vinora.vn / Vinora@2026` hoặc tài khoản tự đăng ký) → trang tài khoản khách.
- Quản trị (`admin@vinora.vn / Admin@2026`) → trang quản trị `src/pages/admin/dashboard.html`.

- Mỗi trình duyệt chỉ giữ **một phiên**: đăng nhập quản trị sẽ thoát tài khoản khách và ngược lại. Giao diện khách không có bất kỳ đường dẫn nào tới trang quản trị.
- Ai mở thẳng địa chỉ trang quản trị mà chưa đăng nhập quản trị (kể cả đang đăng nhập tài khoản khách) sẽ bị đưa về ô đăng nhập; đăng nhập đúng tài khoản quản trị mới vào được.
Admin dùng chung dữ liệu với cửa hàng (localStorage của cùng trình duyệt; cửa sổ ẩn danh hay trình duyệt khác là dữ liệu riêng). Khi trình bày: thao tác bằng tài khoản khách (hoặc đặt hàng không cần tài khoản), rồi đăng nhập quản trị trong cùng trình duyệt để xử lý – mở song song một thẻ cửa hàng (khách vãng lai) và một thẻ quản trị thì bên này thao tác, bên kia tự cập nhật.

| Trang | Chức năng |
|---|---|
| Tổng quan | Doanh thu đã thu, đơn mới, đơn chờ xử lý, phản ánh mở, điểm đánh giá; biểu đồ doanh thu 14 ngày; việc cần xử lý; đơn mới; sản phẩm bán chạy; nút tạo dữ liệu mẫu |
| Đơn hàng | Lọc theo trạng thái / thanh toán, tìm theo mã – tên – SĐT; xác nhận đã nhận tiền chuyển khoản, xác nhận & giao hàng, giao thành công (kích hoạt thẻ bảo hành), hủy đơn chưa thanh toán, xác nhận đã hoàn tiền (xem đủ số tài khoản khách cung cấp), ghi chú nội bộ, nhật ký |
| Phản ánh | Xem mô tả, ảnh minh chứng; chuyển Đã tiếp nhận → Đang xử lý → Đã giải quyết kèm nội dung gửi khách (khách thấy trong đơn hàng) |
| Bảo hành & lịch hẹn | Xác nhận / hoàn tất / hủy lịch hẹn (tự trừ lượt với dịch vụ có giới hạn, cập nhật size sau khi chỉnh size); danh sách thẻ bảo hành |
| Sản phẩm | 443 mẫu, lọc – tìm – phân trang; sửa giá bán, giá trước giảm, ngừng bán (áp dụng ngay cho cửa hàng) |
| Khách hàng | Gộp khách có tài khoản và khách mua bằng SĐT: số đơn, đã chi, thẻ bảo hành, lịch sử mua |
| Đánh giá | Điểm trung bình, phân bố sao, phân loại tích cực / tiêu cực tự động (chỉ admin thấy), phản hồi khách |

Các nút “Mô phỏng: …” trước đây ở giao diện khách (cửa hàng giao hàng, ngân hàng báo có, showroom xác nhận, CSKH xử lý, kế toán hoàn tiền) đã bỏ – những việc này giờ làm ở trang quản trị.

## Cập nhật theo góp ý
| Góp ý | Đã sửa |
|---|---|
| Menu Nhẫn / Trang sức / BST / Quà tặng rối | Gộp còn **Trang sức** (rê vào *Nhẫn* hiện các loại nhẫn, rê vào *Quà tặng* hiện theo ngân sách) · Bộ sưu tập · Ưu đãi · Bảo hành điện tử · **Về Vinora** |
| Hover đồng hồ / avatar / giỏ | Rê chuột hiện hộp xem nhanh: 5 sản phẩm đã xem, 5 sản phẩm yêu thích, menu tài khoản (như cột trái), các món trong giỏ |
| Giấy chứng nhận | Huy hiệu “Đã kiểm định chất lượng” ở trang sản phẩm mở giấy chứng nhận (trình bày như phiếu bảo hành); mỗi thẻ bảo hành có giấy chứng nhận riêng |
| Thêm / bỏ yêu thích | Nút trái tim trên mọi thẻ sản phẩm và trang chi tiết; trang `wishlist.html` |
| Bắt đăng nhập khi thanh toán | Đặt hàng không cần tài khoản, **số điện thoại là mã khách hàng**; tra cứu đơn bằng mã đơn + SĐT; tạo tài khoản bằng SĐT đó và xác minh OTP thì đơn + thẻ bảo hành tự liên kết |
| 4 ô tổng quan ở Hồ sơ | Đã bỏ, trang chỉ còn thông tin cá nhân |
| Hạn thanh toán | Đơn trả trực tuyến có đồng hồ đếm ngược 24 giờ; quá hạn hệ thống tự hủy |
| Voucher giữ chân khi hủy | Bỏ giảm giá; popup hủy nhắc giá trị đơn + gợi ý *điều chỉnh đơn* thay vì hủy; đơn đã thanh toán thì khách nhập tài khoản nhận hoàn tiền (Chờ hoàn tiền → Đã hoàn tiền) |
| Đánh giá | Bỏ dòng “chỉ dành cho đơn…”, bỏ nhãn cảm xúc và ghi chú mô phỏng; đánh giá hiện ngay trong chi tiết đơn |
| Lịch hẹn dịch vụ không giới hạn | Không còn câu “đã trừ 1 lượt (nếu có giới hạn)”; dịch vụ trọn đời ghi “không giới hạn số lần” |
| Chân trang | Chỉ còn thương hiệu, bảo hành & hậu mãi, hỗ trợ khách hàng |
| Chính sách | Bỏ dòng kỹ thuật ở trang bảo hành; bỏ 2 chính sách phản business ở trang giao hàng; thêm mục **Phản ánh & đổi trả** |
| Phản ánh khi đơn / sản phẩm có vấn đề | Nút “Phản ánh vấn đề” trong đơn hàng: chọn loại vấn đề, mô tả, tối đa 3 ảnh; theo dõi trạng thái ngay trong đơn |

## Lưu ý
- Đầu trang / chân trang được lặp sẵn trong từng file HTML (bản Flask dùng `{% include %}`); khi sửa menu cần sửa ở tất cả các trang.
- Ảnh sản phẩm tải từ CDN gốc nên cần Internet; mất mạng sẽ hiện ảnh tạm.
- Chân trang không còn dòng “Đồ án môn…”.
