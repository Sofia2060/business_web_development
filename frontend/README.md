# Vinora Jewelry – bản HTML thuần (mở bằng Live Server)

Không cần Python/Flask. Chỉ gồm HTML + CSS + JavaScript + dữ liệu JSON/XML.
Các trang không dùng `<!DOCTYPE html>` và thẻ `<meta>` (khung nhìn điện thoại được thêm bằng một đoạn script nhỏ trong `<head>`).

## Cách mở
Chạy `uv run python backend/run.py` ở gốc repo rồi mở `http://127.0.0.1:5000/`. Flask phục vụ thư mục này và API ở cùng một địa chỉ, xem README ở gốc repo.

> Các trang khách lấy sản phẩm, tài khoản, giỏ hàng và đơn hàng từ API (`/api/...`), nên không còn chạy riêng bằng Live Server hay bấm đúp file `.html`.
> Chỉ còn đọc từ thư mục `mock-data/`: `config.json` (nhãn và quy tắc hiển thị), `size-chart.json`, `provinces.json`, `stores.xml`.
> `categories.json`, `collections.json` không còn trang nào đọc, `products.json` cũng không còn trang nào đọc (trang quản trị sản phẩm đã nối API). Giữ lại vì test đối chiếu dữ liệu API với dữ liệu gốc; sẽ xóa ở bước dọn dẹp (C9).

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
Đơn hàng của admin lấy từ máy chủ (API `/api/admin/orders`), nên đặt hàng ở trình duyệt nào cũng thấy; trang admin chỉ cập nhật khi tải lại hoặc sau mỗi thao tác của admin. Chỉ trang Phản ánh còn dùng dữ liệu mô phỏng trong localStorage của trình duyệt đó. Các trang còn lại lấy từ API `/api/admin/...`.

| Trang | Chức năng |
|---|---|
| Tổng quan (đơn hàng và doanh thu đã nối API) | Doanh thu đã thu, đơn mới, đơn chờ xử lý, phản ánh mở, điểm đánh giá (hai mục này còn là dữ liệu mô phỏng); biểu đồ doanh thu 14 ngày; việc cần xử lý; đơn mới; sản phẩm bán chạy |
| Đơn hàng (đã nối API) | Lọc theo trạng thái / thanh toán, tìm theo mã – tên – SĐT; xác nhận đã nhận tiền chuyển khoản, xác nhận đơn, bắt đầu chế tác, bàn giao vận chuyển, giao thành công (kích hoạt thẻ bảo hành), hủy đơn, nhật ký. Chưa có hoàn tiền hai bước và ghi chú nội bộ (database không có) |
| Phản ánh (dữ liệu mô phỏng, chưa có bảng trong database) | Xem mô tả, ảnh minh chứng; chuyển Đã tiếp nhận → Đang xử lý → Đã giải quyết kèm nội dung gửi khách (khách thấy trong đơn hàng) |
| Bảo hành & lịch hẹn (đã nối API) | Xác nhận lịch khách chọn, đề xuất giờ khác, hoàn tất (database trừ lượt, quyết định miễn phí hay tính phí), hủy lịch; danh sách thẻ bảo hành kèm lượt đã dùng |
| Sản phẩm (đã nối API) | 443 mẫu, lọc – tìm – phân trang; sửa giá bán, giá trước giảm, trạng thái đang bán / đã ẩn / ngừng bán (lưu vào database; sản phẩm giá theo vàng chỉ đổi được trạng thái) |
| Khách hàng (đã nối API) | Khách có tài khoản và khách mua bằng SĐT: số đơn, đã chi, thẻ bảo hành, lịch sử mua |
| Đánh giá (đã nối API) | Điểm trung bình, phân bố sao, nhãn tích cực / tiêu cực (mô phỏng, chỉ admin thấy), các yếu tố khách nhắc tới. Chưa có phản hồi của cửa hàng |

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
