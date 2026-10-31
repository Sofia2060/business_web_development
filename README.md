# Vinora Jewelry

Website thương mại điện tử kinh doanh trang sức cao cấp **Vinora Jewelry** — đồ án môn *Phát triển web kinh doanh*.

- **Front-end:** HTML5, CSS3, JavaScript
- **Back-end:** Python (Flask)
- **Cơ sở dữ liệu:** Microsoft SQL Server
- **Mô hình hóa:** Draw.io (BPMN, Use Case, Sequence, ERD)

## Cấu trúc thư mục

```
business_web_development/
├── README.md
├── .gitignore
├── .editorconfig
├── .env.example               # mẫu biến môi trường (KHÔNG commit .env thật)
│
├── docs/                      # tài liệu đồ án
│   ├── [Web] FinalProject.md  # khung báo cáo
│   ├── report/                # báo cáo hoàn chỉnh (Word/PDF)
│   ├── analysis/              # BPMN, use case, sequence, sitemap
│   ├── database/              # ERD, từ điển dữ liệu 11 bảng
│   ├── design/                # logo, bảng màu, wireframe
│   └── api/                   # mô tả endpoint
│
├── frontend/                  # giao diện
│   ├── index.html             # chuyển hướng tới trang chủ (gốc cho Live Server)
│   ├── README.md
│   ├── public/                # tài nguyên phục vụ nguyên trạng
│   │   ├── fonts/
│   │   └── images/
│   │       ├── logo/
│   │       ├── products/
│   │       └── placeholders/
│   ├── src/
│   │   ├── pages/
│   │   │   ├── client/        # trang khách hàng
│   │   │   └── admin/         # trang quản trị
│   │   ├── partials/          # header, footer dùng chung
│   │   ├── css/
│   │   │   ├── base/          # biến màu, reset, layout
│   │   │   ├── components/    # header/footer, thẻ sản phẩm, modal...
│   │   │   └── pages/         # CSS riêng từng trang
│   │   └── js/
│   │       ├── core/          # hàm chung, API client, storage
│   │       ├── components/
│   │       └── pages/         # JS riêng từng trang
│   └── mock-data/             # JSON/XML mẫu khi chưa có back-end
│
├── backend/                   # Python (Flask)
│   ├── app/
│   │   ├── __init__.py
│   │   ├── config.py
│   │   ├── models/            # User, Customer, Product, Order, Warranty...
│   │   ├── routes/            # auth, products, cart, orders, warranty, admin
│   │   ├── services/          # nghiệp vụ: hủy đơn, kích hoạt bảo hành, phí giao hàng
│   │   ├── schemas/           # kiểm tra dữ liệu vào/ra
│   │   ├── templates/         # Jinja templates (nếu dùng server-side render)
│   │   └── utils/
│   ├── migrations/
│   ├── tests/
│   ├── requirements.txt
│   └── run.py
│
├── database/
│   ├── 01_VinoraJewelry_SQLServer.sql  # tạo DB, 26 bảng, trigger, procedure, view, dữ liệu sản phẩm
│   ├── 02_VinoraJewelry_FakeData.sql   # dữ liệu giả lập cho dev/demo
│   └── README.md
│
├── scripts/                   # script tiện ích (import dữ liệu, build...)
└── .github/
    ├── workflows/             # CI (bổ sung sau)
    ├── ISSUE_TEMPLATE/
    └── PULL_REQUEST_TEMPLATE.md
```

> **Trạng thái:** mã giao diện đã nằm trong `frontend/` (thư mục `VinoraJewelry_HTML/` cũ đã bỏ).
> `backend/`, `database/`, `src/pages/admin/` và `src/partials/` mới là khung rỗng, chưa có mã.
> Chi tiết các trang client xem [frontend/README.md](frontend/README.md).

## Chạy front-end

1. Mở thư mục `frontend` bằng VS Code.
2. Cài tiện ích **Live Server**, chuột phải `frontend/index.html` → *Open with Live Server*.
3. Không mở file `.html` trực tiếp (`file://`), vì trình duyệt chặn đọc JSON/XML.

## Môi trường Python (back-end)

Dùng [uv](https://docs.astral.sh/uv/). Thư viện khai báo trong `pyproject.toml`, khóa phiên bản trong `uv.lock`.

```bash
uv sync
uv run pytest
```

Thêm thư viện: `uv add <tên>`. Thư viện chỉ dùng cho test: `uv add --dev <tên>`.
Kết nối SQL Server cần ODBC Driver 18 (máy hiện tại đã có). Sao chép `.env.example` thành `.env` rồi điền thông tin.
Để trống `DB_USER` thì back-end đăng nhập bằng Windows Authentication.

### Chạy API sản phẩm

Cần đã chạy `database/01_VinoraJewelry_SQLServer.sql`. Mở terminal ở gốc repo:

```bash
uv run python backend/run.py
```

| Địa chỉ | Việc làm |
|---|---|
| `GET /api/products` | Danh sách sản phẩm đang bán. Tham số: `category` (id danh mục), `q` (tìm theo tên, không phân biệt hoa thường và dấu), `page`, `limit` (tối đa 100, mặc định 24) |
| `GET /api/products/<sku>` | Chi tiết một sản phẩm, kèm ảnh, đá và biến thể. Ví dụ `/api/products/NDINO131LDIA` |

Tham số sai trả về 400. Mã sản phẩm không có trả về 404. Test nằm ở `backend/tests/test_products.py` và cần database đang chạy.

### Đăng nhập và phân quyền

Cần `SECRET_KEY` trong file `.env` (chuỗi ngẫu nhiên từ 32 ký tự trở lên, dùng để ký cookie đăng nhập). Tạo bằng:

```bash
uv run python -c "import secrets; print(secrets.token_hex(32))"
```

Mật khẩu lưu bằng bcrypt. Đăng nhập được giữ trong cookie phiên. Có hai vai trò: `Customer` và `Admin`. Đăng ký luôn tạo `Customer`.

| Địa chỉ | Việc làm |
|---|---|
| `POST /api/auth/register` | Đăng ký. Body: `fullName`, `email`, `password` (8 đến 72 byte), `phone` (không bắt buộc). Trả 201 và tự đăng nhập. Email trùng trả 409 |
| `POST /api/auth/login` | Đăng nhập bằng `email` và `password`. Sai mật khẩu hoặc email không có đều trả 401 cùng một nội dung. Tài khoản bị khóa trả 403 |
| `POST /api/auth/logout` | Đăng xuất, trả 204 |
| `GET /api/auth/me` | Thông tin người đang đăng nhập, chưa đăng nhập trả 401 |
| `GET /api/admin/users` | Danh sách tài khoản. Chỉ `Admin`: chưa đăng nhập trả 401, là khách trả 403 |

Các tài khoản mẫu trong database (như `admin@vinora.vn`) mang mã băm giả nên chưa đăng nhập được. Đặt mật khẩu thật cho một tài khoản bằng:

```bash
uv run python scripts/set_password.py admin@vinora.vn
```

Giới hạn đầu vào: tên tối đa 100 ký tự, email chỉ gồm ký tự ASCII (tối đa 255), thân yêu cầu tối đa 16 KB (quá thì trả 413). Các trường phải là chuỗi.

Chưa làm: giới hạn số lần đăng nhập sai, cờ `Secure` cho cookie khi chạy HTTPS, hết hạn phiên phía server. Cần bổ sung trước khi đưa lên mạng thật.

Test nằm ở `backend/tests/test_auth.py`.

### Giỏ hàng, địa chỉ và đơn hàng

Các API này cần đăng nhập bằng tài khoản khách (`Customer`). Tài khoản `Admin` gọi vào trả 403. Quy tắc nghiệp vụ nằm trong stored procedure của SQL Server. Back-end chỉ kiểm tra đầu vào, gọi thủ tục, và đổi lỗi của thủ tục thành mã HTTP. Thông báo lỗi là câu tiếng Việt viết sẵn trong thủ tục.

| Địa chỉ | Việc làm |
|---|---|
| `GET /api/addresses`, `POST /api/addresses` | Sổ địa chỉ. Địa chỉ đầu tiên tự là mặc định. `isDefault: true` đổi mặc định sang địa chỉ mới |
| `GET /api/cart` | Giỏ hàng kèm `subtotal`, `shippingFee`, `total` |
| `POST /api/cart` | Thêm biến thể: `variantSku`, `quantity` (1 đến 10), `engravingText` (khắc tên, tối đa 30 ký tự). Thêm lại cùng biến thể và cùng chữ khắc thì cộng dồn số lượng. Quá tồn kho trả 409 |
| `PATCH /api/cart/<id>`, `DELETE /api/cart/<id>` | Đổi số lượng, xóa dòng |
| `POST /api/orders` | Đặt hàng từ giỏ (`sp_PlaceOrder`). Body: `addressId`, `paymentMethod` (`COD`, `BankTransfer`, `VNPay`, `MoMo`), `checkoutToken`, `voucherCode`, `note`. Trả 201 |
| `GET /api/orders`, `GET /api/orders/<mã đơn>` | Đơn của chính khách. Đơn của người khác trả 404 |
| `POST /api/orders/<mã đơn>/cancel` | Khách bấm "Hủy đơn" (`sp_RequestCancelOrder`). Chưa hủy ngay: trả `RequestID`, `VoucherCode`, `VoucherDiscount` để hiện popup nhắc "hủy sẽ mất voucher". Đơn trên 5.000.000 đ trả 403, khách phải gọi hotline |
| `POST /api/orders/<mã đơn>/cancel/respond` | Khách chọn trong popup (`sp_RespondCancelPopup`): `keepOrder: true` giữ đơn, `keepOrder: false` hủy đơn, trả tồn kho, mất voucher |
| `POST /api/orders/<mã đơn>/confirm-received` | Xác nhận đã nhận hàng (`sp_ConfirmOrderReceived`). Chỉ khi đơn đang giao. Database tự tạo thẻ bảo hành |
| `GET /api/admin/orders` | Admin xem mọi đơn. Tham số `status`, `page`, `limit` |
| `POST /api/admin/orders/<mã đơn>/status` | Admin đổi trạng thái (`sp_UpdateOrderStatus`): `Confirmed`, `Shipping`, `Delivered`, `Cancelled`. Nhảy bước trả 409 |

Điểm cần nhớ:
- `checkoutToken` là một UUID do trình duyệt tạo cho mỗi lần thanh toán. Gửi lại cùng token (bấm đúp, mạng chậm) thì nhận lại đúng đơn cũ với mã 200, không tạo đơn thứ hai.
- Phí giao hàng do server tính, không nhận từ trình duyệt: 30.000 đ, miễn phí khi tiền hàng từ 2.000.000 đ (tính trước khi giảm giá). Hằng số nằm ở `backend/app/config.py`.
- Hủy đơn có hai bước. Bước 1 (`/cancel`) chỉ tạo yêu cầu và cho biết voucher sẽ mất. Bước 2 (`/cancel/respond`) mới giữ hoặc hủy. Cột `CancelChannel` trong danh sách đơn cho biết trang nên hiện nút hủy (`Web`), dòng "gọi hotline" (`Hotline`) hay không hiện gì (`null`). Admin hủy đơn qua `POST /api/admin/orders/<mã đơn>/status` với `Cancelled`.
- Gửi lại cùng token cho kết quả giống hệt lần đầu (cùng khóa `OrderCode`, `TotalAmount`, `ShippingFee`), chỉ khác mã 200 thay vì 201.
- Địa chỉ đầy đủ (đường, phường, tỉnh) tối đa 400 ký tự, vì đơn hàng chép địa chỉ vào một cột 400 ký tự.
- Khắc tên: database coi chữ hoa và chữ thường là một, và bỏ qua dấu thanh ("Mai" bằng "Mại"). Thêm một chữ khắc chỉ khác kiểu đó vào giỏ trả 409. Các chữ khác nhau thật như "Năm" và "Nam" là hai dòng riêng.
- Hai yêu cầu chạy cùng lúc gây xung đột (trùng dòng giỏ hàng, mã ưu đãi vừa hết lượt) trả 409 để thử lại. Lỗi database khác trả 500 với câu chung, không lộ nội dung SQL.
- Chưa làm: cổng thanh toán (ghi nhận kết quả VNPay hoặc MoMo, `sp_RecordPaymentResult`), bảo hành và lịch hẹn hậu mãi, đánh giá. Đơn trả trước hiện ở trạng thái thanh toán `Pending`.

### Chạy test

```bash
uv run pytest
```

Test không đụng vào dữ liệu thật. Mỗi lần chạy, `backend/tests/conftest.py` dựng lại một database riêng tên `VinoraJewelry_Test` từ file `database/01_*.sql` (mất khoảng 5 giây). Cần quyền tạo database trên SQL Server. Nếu không kết nối được, các test bị bỏ qua và pytest in lý do.

## Quy ước

- Tên file, thư mục, biến trong code: tiếng Anh, `kebab-case` cho file, `snake_case` cho Python.
- Nội dung hiển thị trên giao diện: tiếng Việt.
- Không commit `.env`, mật khẩu, khóa API hay dữ liệu khách hàng thật.
- Làm việc theo nhánh `feature/<tên>`, tạo Pull Request vào `main`.

## Thành viên nhóm

_(điền sau)_
