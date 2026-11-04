# Vinora Jewelry: giao diện (HTML, CSS, JavaScript thuần)

Giao diện gồm HTML, CSS và JavaScript, không dùng thư viện. Flask phục vụ thư mục này và API ở cùng một địa chỉ.
Các trang không dùng `<!DOCTYPE html>` và thẻ `<meta>` (khung nhìn điện thoại được thêm bằng một đoạn script nhỏ trong `<head>`).

## Cách mở
Chạy `uv run python backend/run.py` ở gốc repo rồi mở `http://127.0.0.1:5000/`. Xem README ở gốc repo để biết cách cài và đặt mật khẩu.

Các trang lấy dữ liệu từ API (`/api/...`), nên không chạy riêng bằng Live Server hay bấm đúp file `.html`.

## Dữ liệu
- **Từ API (database):** sản phẩm, danh mục, bộ sưu tập, tài khoản, giỏ hàng, đơn hàng, thẻ bảo hành, lịch hẹn, đánh giá, sản phẩm đã xem, và toàn bộ trang quản trị trừ trang Phản ánh.
- **Từ thư mục `mock-data/`** (các trang đọc trực tiếp):
  - `config.json`: nhãn và quy tắc hiển thị (phí giao hàng, loại vấn đề phản ánh, quyền lợi bảo hành...).
  - `size-chart.json`: bảng quy đổi size nhẫn.
  - `provinces.json`: danh sách tỉnh thành.
  - `stores.xml`: danh sách showroom (đọc bằng AJAX và DOM).
- **Lưu trong trình duyệt (localStorage, khóa `vinora.*`).** Bản demo, chưa có trong database:
  - sản phẩm yêu thích, form liên hệ báo giá và đăng ký nhận tin (có dòng ghi chú trên trang);
  - phản ánh đơn hàng (trang quản trị Phản ánh đọc cùng dữ liệu này nên chỉ thấy phản ánh tạo trên cùng trình duyệt).
- **Cũng nằm trong trình duyệt, nhưng chỉ là trạng thái tạm:**
  - giỏ hàng và danh sách sản phẩm đã xem của khách chưa đăng nhập, và các đơn khách vãng lai đã đặt (`donKhach`);
  - lựa chọn ở giỏ hàng như gói quà, lời nhắn, mã ưu đãi (`tuyChonGio`);
  - cờ đã đăng nhập quản trị (`phienQuanTri`);
  - danh mục sản phẩm giữ 5 phút trong `sessionStorage` (`vinora.catalog.v1`), nên giá mới hiện sau tối đa 5 phút.

## Cấu trúc
```
frontend/
├── index.html                       chuyển hướng tới trang chủ
├── public/
│   ├── fonts/
│   └── images/{logo,placeholders,products}/
├── mock-data/                       config, size-chart, provinces (.json), stores.xml
└── src/
    ├── pages/client/
    │   ├── index.html               5.2.1 Trang chủ
    │   ├── products.html            5.2.2 Danh sách sản phẩm (?danhmuc= ?bst= ?q= ...)
    │   ├── product-detail.html      5.2.3 Chi tiết sản phẩm (?ma=MÃ_SKU), nút yêu thích, giấy chứng nhận
    │   ├── recently-viewed.html     5.2.4 Sản phẩm đã xem
    │   ├── wishlist.html            Sản phẩm yêu thích
    │   ├── cart.html, checkout.html, order-success.html          5.2.5
    │   ├── orders.html (popup hủy đơn 5.2.6, phản ánh)           5.2.7, tra cứu đơn khi chưa đăng nhập
    │   ├── warranty-activation.html, warranty-portal.html        5.2.8
    │   └── account, about, contact, size-guide,
    │       shipping-policy, warranty-policy, 404 (.html)
    ├── pages/admin/
    │   └── dashboard, orders, complaints, warranty, products, customers, reviews (.html)
    ├── css/  base/ · components/ · pages/ (mỗi trang khách một tệp) · admin/admin.css
    └── js/   core/ · components/ · pages/ (mỗi trang khách một tệp) · admin/ (admin.js và mỗi trang quản trị một tệp)
```

Trong `js/core/`:
- `common.js`: tiện ích dùng chung (định dạng, hộp thông báo, menu, yêu thích, phản ánh).
- `api.js`: gọi API, đổi dữ liệu của API sang dạng các trang dùng, dữ liệu cửa hàng (`VN.duLieu`).
- `session.js`: tài khoản, giỏ hàng, đơn hàng, thẻ bảo hành, lịch hẹn, sản phẩm đã xem, đánh giá. Trang cần tài khoản và giỏ đã tải thì bắt đầu bằng `await VN.sanSang`.

## Thông tin dùng khi trình bày
Giao diện không ghi tài khoản hay mã thử nghiệm lên trang. Khi trình bày dùng các thông tin sau.

| Mục đích | Thông tin |
|---|---|
| Tài khoản quản trị | `admin@vinora.vn`. Mật khẩu do bạn đặt bằng `uv run python scripts/set_password.py admin@vinora.vn` |
| Khách hàng | Tự đăng ký ở trang Tài khoản, hoặc đặt hàng không cần tài khoản bằng số điện thoại |
| Thẻ ATM ở cổng VNPay giả lập | Số thẻ bất kỳ 16 đến 19 chữ số (ví dụ `9704198526191432198`), tên chủ thẻ, ngày phát hành dạng `MM/YY` |
| Mã OTP (cổng VNPay, xác minh số điện thoại) | `123456` |
| Mã giảm giá | `WELCOME5`, `VINORA500K`, `GIAM300K` |

Phí giao hàng, loại vấn đề phản ánh, quyền lợi bảo hành... chỉnh tập trung trong `mock-data/config.json`. Phí giao hàng cũng được lặp trong `backend/app/config.py`, sửa một chỗ thì sửa cả hai.

## Trang quản trị (admin)
Chỉ có **một ô đăng nhập** (trang Tài khoản). Hệ thống phân quyền theo tài khoản: khách vào trang tài khoản khách, quản trị vào `src/pages/admin/dashboard.html`.

- Mỗi trình duyệt chỉ giữ **một phiên**: đăng nhập quản trị sẽ thoát tài khoản khách và ngược lại. Giao diện khách không có đường dẫn nào tới trang quản trị.
- Ai mở thẳng địa chỉ trang quản trị mà chưa đăng nhập quản trị sẽ bị đưa về ô đăng nhập.
- Đơn hàng và lịch hẹn lấy từ máy chủ (`/api/admin/orders`, `/api/admin/services`) một lần khi mở trang. Trang chỉ cập nhật khi tải lại hoặc sau mỗi thao tác của admin.
- Chỉ trang Phản ánh còn dùng dữ liệu mô phỏng trong localStorage (database chưa có bảng phản ánh), đầu trang có dòng nhắc.

| Trang | Chức năng |
|---|---|
| Tổng quan | Doanh thu đã thu, đơn mới, đơn chờ xử lý, điểm đánh giá, biểu đồ doanh thu 14 ngày, doanh thu theo chất liệu (10K đến 24K và bạc 925, tính trên đơn đã thanh toán), việc cần xử lý, đơn mới, sản phẩm bán chạy. Số phản ánh mở là dữ liệu mô phỏng |
| Đơn hàng | Lọc theo trạng thái và thanh toán, tìm theo mã, tên, số điện thoại. Xác nhận đã nhận tiền chuyển khoản, xác nhận đơn, bắt đầu chế tác, bàn giao vận chuyển, giao thành công (kích hoạt thẻ bảo hành), hủy đơn, nhật ký. Chưa có hoàn tiền hai bước và ghi chú nội bộ (database không có) |
| Phản ánh (dữ liệu mô phỏng) | Xem mô tả, ảnh minh chứng. Chuyển Đã tiếp nhận, Đang xử lý, Đã giải quyết kèm nội dung gửi khách |
| Bảo hành và lịch hẹn | Xác nhận lịch khách chọn, đề xuất giờ khác, hoàn tất (database trừ lượt và quyết định miễn phí hay tính phí), hủy lịch. Danh sách thẻ bảo hành kèm lượt đã dùng |
| Sản phẩm | 443 mẫu, lọc, tìm, phân trang. Sửa giá bán, giá trước giảm, trạng thái đang bán, đã ẩn, ngừng bán (lưu vào database, sản phẩm giá theo vàng chỉ đổi được trạng thái) |
| Khách hàng | Khách có tài khoản và khách mua bằng số điện thoại: số đơn, đã chi, thẻ bảo hành, lịch sử mua |
| Đánh giá | Điểm trung bình, phân bố sao, nhãn tích cực hoặc tiêu cực (mô phỏng, chỉ admin thấy), các yếu tố khách nhắc tới. Chưa có chỗ trả lời đánh giá (database không có cột) |

Các nút "Mô phỏng: ..." trước đây ở giao diện khách (cửa hàng giao hàng, ngân hàng báo có, showroom xác nhận, CSKH xử lý, kế toán hoàn tiền) đã bỏ. Những việc này làm ở trang quản trị.

## Cập nhật theo góp ý
| Góp ý | Đã sửa |
|---|---|
| Menu Nhẫn, Trang sức, BST, Quà tặng rối | Gộp còn **Trang sức** (rê vào *Nhẫn* hiện các loại nhẫn, rê vào *Quà tặng* hiện theo ngân sách), Bộ sưu tập, Ưu đãi, Bảo hành điện tử, **Về Vinora** |
| Hover đồng hồ, avatar, giỏ | Rê chuột hiện hộp xem nhanh: 5 sản phẩm đã xem, 5 sản phẩm yêu thích, menu tài khoản, các món trong giỏ |
| Giấy chứng nhận | Huy hiệu "Đã kiểm định chất lượng" ở trang sản phẩm mở giấy chứng nhận (trình bày như phiếu bảo hành). Mỗi thẻ bảo hành có giấy chứng nhận riêng |
| Thêm, bỏ yêu thích | Nút trái tim trên mọi thẻ sản phẩm và trang chi tiết, trang `wishlist.html`. Bản demo: lưu trong trình duyệt |
| Bắt đăng nhập khi thanh toán | Đặt hàng không cần tài khoản, **số điện thoại là mã khách hàng**. Tra cứu đơn bằng mã đơn và số điện thoại. Tạo tài khoản bằng số đó và xác minh OTP thì đơn và thẻ bảo hành tự liên kết |
| 4 ô tổng quan ở Hồ sơ | Đã bỏ, trang chỉ còn thông tin cá nhân |
| Hạn thanh toán | Đơn trả trực tuyến có đồng hồ đếm ngược 15 phút. Quá hạn hệ thống tự hủy |
| Hủy đơn có mã giảm giá | Popup hủy nhắc giá trị đơn và mã giảm giá sẽ mất, khách chọn giữ đơn hoặc hủy. Đơn đã trả tiền được đánh dấu hoàn tiền (chưa hoàn tiền thật) |
| Đánh giá | Bỏ dòng "chỉ dành cho đơn...", không hiện nhãn cảm xúc cho khách. Đánh giá hiện ngay trong chi tiết đơn |
| Lịch hẹn dịch vụ không giới hạn | Dịch vụ trọn đời ghi "không giới hạn số lần" |
| Chân trang | Chỉ còn thương hiệu, bảo hành và hậu mãi, hỗ trợ khách hàng |
| Chính sách | Bỏ dòng kỹ thuật ở trang bảo hành, bỏ 2 chính sách phản business ở trang giao hàng, thêm mục **Phản ánh và đổi trả** |
| Phản ánh khi đơn hoặc sản phẩm có vấn đề | Nút "Phản ánh vấn đề" trong đơn hàng: chọn loại vấn đề, mô tả, tối đa 3 ảnh, theo dõi trạng thái ngay trong đơn |

## Lưu ý
- Đầu trang và chân trang được lặp sẵn trong từng file HTML, nên khi sửa menu cần sửa ở tất cả các trang.
- Ảnh sản phẩm tải từ CDN gốc nên cần Internet. Mất mạng sẽ hiện ảnh tạm.
