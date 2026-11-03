# Đối chiếu giao diện và database

File này ghi các mã, trạng thái và quy tắc khác nhau giữa giao diện (`frontend/`) và database (`database/`). Khi nối giao diện vào API (lớp `VN.api`), phần đổi mã nằm một chỗ ở lớp này, không rải trong từng trang.

## 1. Mã và giá trị phải đổi qua lại

| Giao diện | Database và API | Ghi chú |
|---|---|---|
| Phương thức thanh toán `COD`, `BANK`, `VNPAY`, `MOMO` | `COD`, `BankTransfer`, `VNPay`, `MoMo` | Gửi sang API bằng tên bên phải |
| Kiểu chữ khắc `co-dien`, `hien-dai`, `viet-tay` | `Classic`, `Modern`, `Handwritten` | Trường `engravingStyle`. Không gửi thì mặc định `Classic`. Chữ khắc tối đa 15 ký tự |
| Loại giá `co_dinh`, `gia_cong` | `Fixed`, `GoldRate` (cột `PricingMethod`) | Xem mục 2 |
| `ma`, `danhMuc`, `boSuuTap`, `chatLieu` | `SKU`, `CategoryID`, `CollectionID`, `Material` | API trả theo tên cột của database |
| `gia`, `giaCu` | `CurrentPrice`, `OriginalPrice` | `giaCu` có khi sản phẩm đang giảm giá |
| `canChonSize` | `RequiresRingSize` | |
| Một dòng giỏ gồm `ma` + `mau` + `size` | `variantSku` | Lấy từ danh sách `variants` của `GET /api/products/<sku>` (có `GoldColor`, `RingSize`, `StockQuantity`) |
| Mã đơn `VNR` + ngày + 4 ký tự | `VN` + ngày + 6 số, ví dụ `VN261102000017` | Giao diện chỉ hiển thị, không tách mã |
| Mã thẻ bảo hành `VNRA` + tháng + 8 ký tự | `VNW` + tháng + 7 số + `-` + số thứ tự đơn vị | Hàm `soTheDep`, `soChungNhan` chỉ định dạng được mã `VNRA…`, cần sửa hoặc bỏ. Trang bảo hành còn dùng thẻ giả lập trên trình duyệt (nhóm C6) |
| Mã ưu đãi `VINORA5`, `CHAOBAN200`, `FREESHIP` | `WELCOME5`, `GIAM300K`, `VINORA500K` | `mock-data/config.json` đã đổi theo database. Số tiền giảm do `POST /api/vouchers/check` tính, giao diện không tự tính |
| Giao hàng: tiêu chuẩn và hỏa tốc (60.000 đ) | Chỉ giao tiêu chuẩn: 30.000 đ, miễn phí từ 2.000.000 đ | Đã bỏ hỏa tốc khỏi `config.json`. Phí do máy chủ tính |
| Gói quà, lời nhắn thiệp, ghi chú | Cột `Note` của đơn (tối đa 500 ký tự) | Giao diện ghép ba phần thành một dòng ghi chú, ví dụ `Gói quà Vinora, thiệp: “Chúc mừng” \| Gọi trước khi giao` |
| Email người nhận trong biểu mẫu thanh toán | Không có | Database không lưu nên đã bỏ ô này |
| Địa chỉ người nhận gồm tỉnh, phường, số nhà | Một chuỗi `ShipAddress` | Trang đơn hàng hiển thị chuỗi đó trong `nguoiNhan.diaChi` |

## 2. Quy tắc đã chốt

1. **22 sản phẩm giá theo giá vàng chỉ báo giá, không bán online.** Đó là 21 mặt dây chuyền và 1 bông tai vàng 24K hoặc 22K. Database đánh dấu `Products.IsQuoteOnly = 1`.
   - API trả `IsQuoteOnly: true` và `CurrentPrice: null` cho các sản phẩm này. Danh sách và trang chi tiết vẫn có (ảnh, màu, size, trọng lượng).
   - Bộ lọc giá và `onSale` không khớp chúng. Khi sắp xếp theo giá chúng luôn nằm cuối. Giao diện đã làm đúng như vậy (`coTheMua`, giá rỗng xếp cuối), nên chỉ cần lấy `coTheMua = !IsQuoteOnly` từ API thay cho `loaiGia !== 'gia_cong'`.
   - Thêm vào giỏ hoặc đặt hàng sản phẩm này: API trả 409 với `reason: quote_only`. Database cũng chặn (lỗi 50014).
   - Giao diện giữ nút "Nhận báo giá" và "Gọi hotline". Số trong `products.json` của 22 sản phẩm này là tiền công, không hiển thị như giá bán. Giá cũ giảm 10% của `MDZ076`, `MDZ081`, `MDZ091` cũng bỏ.
   - Bảng giá vàng (`GoldPrices`) vẫn dùng để nhân viên báo giá. Muốn bán online lại: đặt `IsQuoteOnly = 0`, giá tự tính theo giá vàng.

## 3. Trạng thái

| Đối tượng | Giao diện | Database | Cách xử lý |
|---|---|---|---|
| Đơn hàng | `Pending`, `Shipping`, `Delivered`, `Cancelled` | Thêm `Confirmed` giữa `Pending` và `Shipping` | Giao diện thêm nhãn "Đã xác nhận". Nút "Xác nhận và giao" của admin gọi `Confirmed` rồi `Shipping`. Khách hủy được ở cả `Pending` và `Confirmed` |
| Thanh toán | `Pending`, `Success`, `Failed`, `Expired`, `RefundPending`, `Refunded` | `Pending`, `Success`, `Failed`, `Expired`, `Refunded` | `Expired` đã có (đơn quá 15 phút chưa trả). `RefundPending` chưa có, xem file `database/README.md` mục 11. Hủy đơn đã trả tiền: thanh toán chuyển thẳng sang `Refunded`, giao diện không còn hỏi tài khoản ngân hàng. Hủy đơn chưa trả: thanh toán thành `Failed`, giao diện hiện "Chưa thanh toán" |
| Lịch hẹn | `Pending`, `Confirmed`, `Completed`, `Cancelled` | Thêm `Rescheduled` (cửa hàng đề xuất giờ khác với giờ khách chọn) | Giao diện thêm nhãn "Đã đổi giờ" |
| Dịch vụ hậu mãi | `Cleaning`, `Polishing`, `Resizing` (hiển thị "Đánh bóng và xi mới" chung) | `Cleaning`, `Polishing`, `Replating`, `Resizing` | `Replating` hiện chung nhóm "Đánh bóng và xi mới". Các quyền lợi `CZ`, `Stone`, `Moissanite`, `Repair` không đặt lịch nên không có trong database |
| Màu | `Vàng Vàng`, `Vàng Trắng`, `Vàng Hồng`, nhóm `Bạc` | Thêm `Bạc Trắng`, `Bạc Vàng` (nhóm `Bạc` gồm hai màu này) | Sản phẩm `BTPTB418` ghi màu "Bạc Hồng" trong file giao diện, database không có màu cho biến thể này |

## 4. Giới hạn khác nhau (giao diện chặt hơn, giữ nguyên)

| Nội dung | Giao diện | Database và API |
|---|---|---|
| Số lượng mỗi dòng | 5 | 10 |
| Đặt lịch hậu mãi | Tối đa 30 ngày tới, theo khung giờ | Trong 1 năm, giờ bất kỳ |
| Mật khẩu | 8 ký tự trở lên, có chữ hoa, chữ thường, số | 8 đến 72 byte |
| Size nhẫn | 6 đến 24 | Biến thể có size 6 đến 20 (bảng quy đổi 5 đến 25) |

Size 21 đến 24 và tồn kho là hai chỗ giao diện phải xử lý thêm: API trả 404 khi chọn size không có biến thể, trả 409 khi hết hàng.

## 5. Chưa có trong database

- Lưu yêu cầu báo giá: form liên hệ (`Nhận báo giá`) hiện chỉ lưu trong trình duyệt (khóa `lienHe`), cửa hàng không nhận được. Cần bảng và API nhận yêu cầu liên hệ.
- Danh sách yêu thích, phản ánh đơn hàng kèm ảnh, phản hồi của cửa hàng cho đánh giá.
- Giao hỏa tốc (60.000 đ) và mã miễn phí giao `FREESHIP`: database không có, giao diện đã bỏ. Gói quà và lời nhắn thiệp chỉ nằm trong ghi chú của đơn.
- Đổi sang thanh toán khi nhận hàng (COD) sau khi đã đặt đơn trả trước: chưa có API, nút đã bỏ khỏi giao diện.
- Danh sách đơn của khách không có tài khoản: máy chủ không có, trình duyệt tự nhớ mã đơn và số điện thoại đã đặt hoặc đã tra cứu.
- Hoàn tiền hai bước (`RefundPending`) và tài khoản ngân hàng nhận hoàn.
- Gắn đơn vãng lai vào tài khoản đã có (hiện chỉ gắn lúc đăng ký).
