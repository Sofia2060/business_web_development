# Cơ sở dữ liệu Vinora Jewelry

Thư mục này chứa toàn bộ script để tạo cơ sở dữ liệu SQL Server cho backend.

| File | Nội dung |
|---|---|
| `01_VinoraJewelry_SQLServer.sql` | Tạo database `VinoraJewelry`: 26 bảng, ràng buộc, chỉ mục, hàm, trigger, 12 thủ tục, 9 view; nạp 443 sản phẩm thật (crawl) và dữ liệu mẫu nhỏ |
| `02_VinoraJewelry_FakeData.sql` | Sinh dữ liệu giả lập: 100 khách hàng, 300 đơn hàng, thanh toán, thẻ bảo hành, đánh giá, lịch hậu mãi… |

> File 01 **xóa và tạo lại** database mỗi lần chạy. Chạy lại file 01 thì phải chạy lại file 02.

---

## 1. Yêu cầu

- SQL Server 2019 trở lên (Developer hoặc Express đều được) + SQL Server Management Studio (SSMS)
- Backend Python: [ODBC Driver 18 for SQL Server](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server). Thư viện Python cài bằng `uv sync` ở gốc repo (đã khai báo trong `pyproject.toml`).

## 2. Tạo database

**Cách 1 – SSMS:** mở `01_...sql` → nhấn **F5** → chờ chạy xong → mở cửa sổ query **mới** → mở `02_...sql` → **F5**.

**Cách 2 – dòng lệnh** (chạy tại thư mục gốc của repo):

```bat
sqlcmd -S localhost -E -C -I -b -f 65001 -i database\01_VinoraJewelry_SQLServer.sql
sqlcmd -S localhost -E -C -I -b -f 65001 -i database\02_VinoraJewelry_FakeData.sql
```

File 01 chạy khoảng 6 giây, file 02 khoảng 45 giây.

- `-f 65001` **bắt buộc**: đọc file theo UTF-8, thiếu sẽ lỗi tiếng Việt.
- `-I` **bắt buộc**: bật `QUOTED_IDENTIFIER`. Thiếu cờ này file 02 báo lỗi `INSERT failed because the following SET options have incorrect settings: 'QUOTED_IDENTIFIER'`, vì bảng có chỉ mục lọc.
- `-C` tin chứng chỉ của server. ODBC Driver 18 mặc định bắt mã hóa, thiếu cờ này trên máy cá nhân sẽ báo lỗi chứng chỉ.
- `-b` dừng và trả mã lỗi khi có lỗi, để biết lệnh có chạy xong không.
- `-E` đăng nhập bằng tài khoản Windows; dùng tài khoản SQL thì thay bằng `-U sa -P <mật_khẩu>`.
- Nếu server không phải `localhost` (ví dụ SQL Express): `-S localhost\SQLEXPRESS`.

**Kiểm tra:** cuối mỗi file có bảng đếm số dòng. File 01 in thêm bảng kết quả kiểm thử, tất cả phải là **ĐẠT**.

| Bảng | Số dòng sau khi chạy 2 file (xấp xỉ) |
|---|---|
| Products / ProductVariants / ProductImages | 443 / 4.238 / 2.950 |
| Users / Customers | 104 / 103 |
| Orders / OrderCancellationRequests | 304 / 102 |
| WarrantyRecords | ~330 (sinh tự động theo đơn đã nhận, thay đổi mỗi lần sinh) |
| CustomerFeedbacks / AfterSalesServices | 102 / 103 |

## 3. Kết nối từ backend

Backend đọc cấu hình từ file `.env` ở **gốc repo** (không commit file này). Tạo bằng cách sao chép `.env.example`:

```env
DB_SERVER=localhost
DB_NAME=VinoraJewelry
DB_USER=
DB_PASSWORD=
SECRET_KEY=<chuỗi ngẫu nhiên từ 32 ký tự trở lên>
```

- `DB_USER` để trống thì backend đăng nhập bằng tài khoản Windows. Dùng tài khoản SQL thì điền `DB_USER` và `DB_PASSWORD`, và bật SQL Server Authentication trên server.
- Server dạng SQL Express: `DB_SERVER=localhost\SQLEXPRESS`.
- `SECRET_KEY` ký cookie đăng nhập. Tạo bằng: `uv run python -c "import secrets; print(secrets.token_hex(32))"`.

Code kết nối nằm ở `backend/app/db.py`, gồm ba hàm:

| Hàm | Dùng để |
|---|---|
| `query(sql, params)` | Chạy `SELECT`, trả về danh sách dict `{tên cột: giá trị}` |
| `transaction()` | Mở một giao dịch để ghi dữ liệu. Tự commit khi xong, tự rollback khi lỗi |
| `call(sql, params, actor=(user_id, nhãn))` | Gọi thủ tục. Hàm gắn người thực hiện vào `SESSION_CONTEXT` để trigger ghi đúng vào `AuditLogs`, và đổi lỗi `THROW 50xxx` thành `ProcError` |

Chuỗi kết nối ODBC được ghép trong `backend/app/config.py` (`db_connection_string()`).

## 4. Tài khoản mẫu

| Email | Vai trò |
|---|---|
| `admin@vinora.vn` | Admin |
| `minhanh@example.com`, `giahuy@example.com`, `thuha@example.com` | Customer (dữ liệu mẫu) |
| 100 email dạng `ten.ho1xx@gmail.com`… | Customer (dữ liệu giả lập) |

`PasswordHash` trong dữ liệu mẫu chỉ là **chuỗi minh họa, không đăng nhập được**. Sau khi chạy file 01 và 02, đặt mật khẩu thật cho tài khoản cần dùng bằng script (chạy ở gốc repo):

```bash
uv run python scripts/set_password.py admin@vinora.vn
```

Script hỏi mật khẩu hai lần (không hiện lên màn hình), dài từ 8 đến 72 byte, rồi lưu dạng bcrypt. Chạy lại file 01 thì mật khẩu về chuỗi minh họa, phải đặt lại.

## 5. Quy tắc nghiệp vụ đã nằm trong database

Backend **gọi thủ tục**, không tự viết lại logic (giá, tồn kho, chống trùng, chuyển trạng thái đã được kiểm tra trong DB):

- Đơn chỉ được đi theo quy trình `Pending → Confirmed → Shipping → Delivered`, hoặc hủy (`Cancelled`) khi đang `Pending`/`Confirmed`. Đơn `Delivered`/`Cancelled` không sửa được.
- Khi đơn chuyển sang `Delivered`, **trigger tự tạo thẻ bảo hành** (mỗi đơn vị sản phẩm một thẻ), backend không cần insert `WarrantyRecords`.
- Tồn kho nằm ở `ProductVariants.StockQuantity` (theo màu × size), không bao giờ âm.
- Mỗi đơn tối đa 1 đánh giá, chỉ khi đã `Delivered`.
- Admin không đặt lại được đúng trạng thái hiện tại của đơn (lỗi 50028), nên ngày xác nhận/giao/nhận không bị ghi đè.
- Yêu cầu hủy còn chờ khách phản hồi sẽ tự chuyển sang `Closed` khi đơn được giao/nhận/hủy theo đường khác (ví dụ admin hủy).
- **Hủy đơn (BRD5, FR13):**
  - Chỉ đơn `Pending`/`Confirmed` mới hủy được.
  - Đơn có `TotalAmount` **trên 5.000.000đ không hủy được trên web**: `sp_RequestCancelOrder` báo lỗi 50029, giao diện hiện số hotline. Nhân viên nhận cuộc gọi thì admin hủy bằng `sp_UpdateOrderStatus @NewStatus='Cancelled', @Reason=N'Khách gọi hotline...'`. Ngưỡng nằm trong hàm `dbo.fn_OnlineCancelLimit()`.
  - Đơn từ 5.000.000đ trở xuống: bấm "Hủy đơn" → `sp_RequestCancelOrder` **chưa hủy ngay** mà trả về mã voucher và số tiền voucher đang giảm để hiện **popup nhắc nhở** (ví dụ: *"Nếu hủy bây giờ, bạn sẽ mất voucher WELCOME5 đang giảm 190.000đ cho đơn này"*). Đơn không dùng voucher thì `@VoucherCode = NULL`, popup hiện câu nhắc chung.
  - Khách chọn trong popup → `sp_RespondCancelPopup`: **giữ đơn** thì đơn giữ nguyên, không đổi tiền, chỉ đánh dấu `IsRetentionApplied = 1` để thống kê; **xác nhận hủy** thì hủy đơn, hoàn tồn kho, đơn đã thanh toán chuyển ngay `Payments.Status = 'Refunded'`. Việc chuyển tiền thật chưa có (xem mục 11). **Voucher đã áp không được hoàn lượt.**
  - Cột `CancelChannel` trong `vw_CustomerOrderHistory` cho biết đơn hiện nút hủy (`'Web'`), dòng "Gọi hotline để hủy" (`'Hotline'`), hay không hủy được nữa (`NULL`).
- Giá bán hiện hành luôn lấy qua `dbo.fn_GetCurrentPrice(ProductID)` hoặc view `vw_ProductCatalog` (có sản phẩm tính giá theo giá vàng).

## 6. Thủ tục (stored procedure)

| Thủ tục | Tham số (OUTPUT in đậm) | Dùng cho |
|---|---|---|
| `sp_PlaceOrder` | `@CustomerID, @AddressID, @PaymentMethod ('COD'/'BankTransfer'/'VNPay'/'MoMo'), @CheckoutToken UNIQUEIDENTIFIER, @ShippingFee=0, @VoucherCode=NULL, @Note=NULL,` **`@OrderID`** | Đặt hàng từ giỏ. Tạo `CheckoutToken = uuid4()` khi mở trang thanh toán; bấm lặp cùng token sẽ trả về cùng đơn |
| `sp_RecordPaymentResult` | `@PaymentID, @IsSuccess BIT, @TransactionID, @ResponseCode=NULL, @Amount=NULL` (nếu truyền thì phải khớp số tiền đơn) | Callback cổng thanh toán sandbox (đã kiểm tra chữ ký) |
| `sp_RequestCancelOrder` | `@OrderID, @CustomerID, @Reason=NULL,` **`@RequestID, @VoucherCode, @VoucherDiscount`** | Khách bấm "Hủy đơn" (đơn ≤ 5 triệu). Dùng `@VoucherCode`, `@VoucherDiscount` để hiện popup nhắc nhở |
| `sp_RespondCancelPopup` | `@RequestID, @CustomerID, @KeepOrder BIT` | Khách chọn trong popup: giữ đơn (1) hoặc xác nhận hủy (0) |
| `sp_UpdateOrderStatus` | `@OrderID, @NewStatus, @AdminUserID, @Reason=NULL` | Admin xác nhận / giao / hủy đơn |
| `sp_ConfirmOrderReceived` | `@OrderID, @CustomerID` | Nút "Đã nhận được hàng" |
| `sp_BookAfterSalesService` | `@WarrantyCode, @CustomerID, @ServiceType ('Cleaning'/'Polishing'/'Replating'/'Resizing'), @PreferredDate, @NewRingSize=NULL, @CustomerNote=NULL,` **`@ServiceID`** | Đặt lịch hậu mãi |
| `sp_ScheduleAfterSalesService` | `@ServiceID, @AdminUserID, @AppointmentDate` | Admin xác nhận/đổi lịch |
| `sp_CompleteAfterSalesService` | `@ServiceID, @AdminUserID, @ResultNote=NULL, @PaidFee=50000` | Admin hoàn tất dịch vụ (tự trừ lượt) |
| `sp_CancelAfterSalesService` | `@ServiceID, @CustomerID` | Khách hủy lịch (không mất lượt) |
| `sp_TrackProductView` | `@CustomerID, @ProductID` | Gọi khi khách mở trang chi tiết sản phẩm |

Thủ tục và API tương ứng của backend (xem code trong `backend/app/routes/`):

| Thủ tục | API |
|---|---|
| `sp_PlaceOrder` | `POST /api/orders` |
| `sp_RequestCancelOrder` | `POST /api/orders/<mã đơn>/cancel` |
| `sp_RespondCancelPopup` | `POST /api/orders/<mã đơn>/cancel/respond` |
| `sp_ConfirmOrderReceived` | `POST /api/orders/<mã đơn>/confirm-received` |
| `sp_UpdateOrderStatus` | `POST /api/admin/orders/<mã đơn>/status` |
| `sp_TrackProductView` | `POST /api/recently-viewed` |
| `sp_RecordPaymentResult`, 4 thủ tục hậu mãi | Chưa có API |

Ví dụ gọi thủ tục có tham số OUTPUT bằng hàm `call()` (trích từ `backend/app/routes/orders.py`):

```python
from app.db import call

rows = call(
    "DECLARE @OrderID INT; "
    "EXEC dbo.sp_PlaceOrder @CustomerID = ?, @AddressID = ?, @PaymentMethod = ?, @CheckoutToken = ?, "
    "@ShippingFee = ?, @VoucherCode = ?, @Note = ?, @OrderID = @OrderID OUTPUT; "
    "SELECT OrderCode, TotalAmount, ShippingFee FROM dbo.Orders WHERE OrderID = @OrderID;",
    (customer_id, address_id, "VNPay", str(checkout_token), shipping_fee, voucher_code, note),
    actor=(user_id, f"Customer:{customer_id}"))
order = rows[0]
```

## 7. View cho giao diện và dashboard

| View | Dùng cho |
|---|---|
| `vw_ProductCatalog` | Danh sách sản phẩm, lọc theo danh mục/khoảng giá (`CurrentPrice`, `IsInStock`, `ThumbnailUrl`) |
| `vw_RevenueOrders` | Các đơn được tính doanh thu (đã giao và có thanh toán thành công), nền của hai view doanh thu bên dưới |
| `vw_CustomerOrderHistory` | Trang "Đơn hàng của tôi" (có cột `CancelChannel`: `'Web'` / `'Hotline'` / `NULL`) |
| `vw_CustomerWarranties` | Cổng bảo hành điện tử (lượt đánh bóng còn lại…) |
| `vw_RevenueByMonth`, `vw_RevenueByMaterial` | Biểu đồ doanh thu theo tháng, theo tuổi vàng |
| `vw_RetentionStats` | Widget hiệu quả popup giữ đơn: số đơn bấm hủy, số đơn giữ lại, số đơn giữ lại rồi nhận hàng, tỷ lệ giữ |
| `vw_SentimentSummary`, `vw_FeedbackAspectSummary` | Biểu đồ cảm xúc khách hàng |

## 8. Mã lỗi nghiệp vụ

Thủ tục/trigger báo lỗi bằng `THROW` với mã 50xxx và thông báo tiếng Việt. Hàm `call()` trong `backend/app/db.py` đổi lỗi này thành `ProcError(code, message)`. Backend trả về JSON `{"error": <thông báo>, "code": <mã>}`. HTTP status lấy từ bảng `PROC_ERROR_STATUS` trong `backend/app/__init__.py` (mã không có trong bảng trả 400).

| Mã | Ý nghĩa |
|---|---|
| 50001 / 50002 | Sửa đơn đã hoàn tất/hủy · chuyển trạng thái sai quy trình |
| 50010 – 50016 | Đặt hàng: phương thức thanh toán, địa chỉ, giỏ trống, sản phẩm ngừng bán, thiếu giá vàng, **hết hàng**, mã ưu đãi không hợp lệ |
| 50017 | Không có giao dịch chờ thanh toán |
| 50020 / 50021 / 50022 | Hủy đơn: không còn được hủy · không tìm thấy đơn · yêu cầu hủy (popup) không còn hiệu lực |
| 50024 / 50025 / 50026 | Không có quyền admin · không tìm thấy đơn · chỉ xác nhận được đơn đang giao |
| 50028 | Đơn hàng đã ở trạng thái này – không cho đặt lại cùng trạng thái (gợi ý trả HTTP 409) |
| 50029 | Đơn trên 5.000.000đ không hủy được trên web – hiển thị hotline (gợi ý trả HTTP 403/409) |
| 50030 | Chỉ đánh giá đơn đã nhận |
| 50031 – 50037 | Hậu mãi: thẻ không hợp lệ, thời gian hẹn, chỉnh size chỉ cho nhẫn, trùng lịch, trạng thái lịch không hợp lệ |
| 50038 | Đơn thanh toán trực tuyến chưa thanh toán nên chưa xác nhận được (gợi ý HTTP 409) |
| 50039 | Loại dịch vụ hậu mãi không hợp lệ |
| 50040 | Biến thể nhẫn phải có size |
| 50041 | Mã giao dịch đã được dùng cho một thanh toán khác (gợi ý HTTP 409) |
| 50042 | Chỉnh size cần size mới hợp lệ, dịch vụ khác không có size mới |
| 50043 | Số tiền cổng thanh toán báo về không khớp số tiền đơn (gợi ý HTTP 409) |
| 50044 | Phí dịch vụ không được âm hoặc để trống |
| 50045 | Phải chọn giữ đơn hoặc xác nhận hủy (không được để trống) |
| 50046 | Trạng thái đơn hàng không hợp lệ |
| 50047 | Đặt hàng thiếu mã thanh toán (`@CheckoutToken`) hoặc phí giao hàng sai |
| 50048 | Mã thanh toán (`@CheckoutToken`) thuộc về khách khác |

## 9. Quy ước khi thay đổi database

1. Không sửa bảng trực tiếp trong SSMS rồi bỏ đó – mọi thay đổi phải nằm trong script trong repo.
2. Giai đoạn phát triển: sửa thẳng file `01_…`, commit, báo nhóm chạy lại 01 rồi 02.
3. Khi đã có dữ liệu cần giữ: thêm file mới `03_<mo_ta>.sql`, `04_…` (chỉ chứa `ALTER`/`CREATE OR ALTER`), chạy tiếp theo thứ tự số. Đồng thời sửa luôn file 01 để database tạo mới đã có sẵn thay đổi.
4. Đổi tên cột/bảng thì cập nhật luôn README này và thông báo người làm frontend/backend.

## 10. Lỗi thường gặp

| Lỗi | Cách xử lý |
|---|---|
| Tiếng Việt bị lỗi font khi chạy bằng `sqlcmd` | Thêm `-f 65001` |
| File 02 báo `INSERT failed because the following SET options have incorrect settings: 'QUOTED_IDENTIFIER'` | Thêm `-I` vào lệnh `sqlcmd` |
| `Cannot drop database because it is currently in use` | Đóng các cửa sổ query/backend đang kết nối `VinoraJewelry` rồi chạy lại |
| `Dữ liệu giả lập đã tồn tại` | Chạy lại file 01 trước, sau đó file 02 |
| `Data source name not found` khi kết nối Python | Chưa cài ODBC Driver 18, hoặc tên driver trong `backend/app/config.py` sai (xem tên đang có bằng `uv run python -c "import pyodbc; print(pyodbc.drivers())"`) |
| `SSL Provider: certificate chain was issued by an authority that is not trusted` khi chạy `sqlcmd` | Thêm `-C` vào lệnh. Backend đã tự đặt `TrustServerCertificate=yes` |
| `Login failed for user` | Để `DB_USER` trống trong `.env` để dùng tài khoản Windows, hoặc điền `DB_USER` và `DB_PASSWORD` và bật SQL Server Authentication (SSMS → Server Properties → Security) |

## 11. Điểm database chưa xử lý (thanh toán)

Ba chỗ dưới đây chờ nhóm quyết định cách làm trước khi sửa script:

1. **Tiền về sau khi đơn đã hủy.** Khi hủy đơn, lần thanh toán đang chờ bị đổi sang `Failed`. Nếu cổng báo thành công sau đó, `sp_RecordPaymentResult` báo lỗi 50017 và không lưu gì, nên khách mất tiền mà hệ thống không có dấu vết để hoàn.
2. **Thanh toán lại và quá hạn.** Chỉ `sp_PlaceOrder` tạo dòng trong `Payments`. Khi thanh toán lỗi hoặc đóng trang, không có cách tạo lần thử mới. Giao diện hứa tự hủy đơn chưa trả sau 24 giờ nhưng database chưa có thủ tục làm việc này.
3. **Trạng thái `Refunded`.** Hủy đơn đã trả tiền đặt `Refunded` ngay, trong khi thực tế chưa chuyển tiền. Giao diện cần hai bước: "Chờ hoàn tiền", rồi admin xác nhận "Đã hoàn tiền". Database cũng chưa có chỗ lưu số tài khoản nhận hoàn tiền của khách.
