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
│   │   ├── routes/            # auth, products, cart, orders, admin (đơn), admin_shop (khách, sản phẩm, đánh giá, bảo hành, lịch hẹn)
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

> **Trạng thái:** giao diện (`frontend/`), API Flask (`backend/`) và database (`database/`) đã có mã. Luồng mua hàng chạy trọn từ
> trình duyệt đến database: xem mục "Giao diện nối API". Chưa nối API: bảo hành và đặt lịch, đánh giá, phản ánh, yêu thích,
> bảy trang quản trị, form liên hệ báo giá. Chi tiết các trang client xem [frontend/README.md](frontend/README.md).

## Chạy cả website (giao diện và API)

Flask phục vụ luôn thư mục `frontend/`, nên trang web và API nằm cùng một địa chỉ. Nhờ vậy cookie đăng nhập hoạt động và không cần cấu hình CORS (CORS là chính sách của trình duyệt chặn trang ở địa chỉ này gọi API ở địa chỉ khác).

```bash
uv run python backend/run.py
```

Mở `http://127.0.0.1:5000/`. Cần đã tạo file `.env` (xem mục Python bên dưới) và đã chạy file SQL 01.

- Trang khách: `http://127.0.0.1:5000/src/pages/client/index.html`
- Trang quản trị: `http://127.0.0.1:5000/src/pages/admin/dashboard.html`
- API: `http://127.0.0.1:5000/api/...`

Chỉ ba thư mục được phục vụ ra ngoài: `src/`, `public/`, `mock-data/` (cùng trang gốc `/`). Các file khác trong `frontend/` như `README.md` không truy cập được qua web. Lỗi dưới `/api/` luôn trả JSON.

Các trang khách gọi API ở cùng địa chỉ (`/api/...`), nên **phải mở qua Flask** như trên. Mở bằng Live Server hoặc bấm đúp file `.html` sẽ không có sản phẩm, vì không có API.

### Giao diện nối API

Các trang khách lấy dữ liệu thật từ API qua hai file dùng chung, nạp sau `common.js` trên mọi trang:

| File | Làm gì |
|---|---|
| `frontend/src/js/core/api.js` | `VN.api` gọi API bằng `fetch` (cookie đi kèm). Lỗi thành `VN.LoiApi` có thông báo tiếng Việt. Chứa các hàm đổi dữ liệu máy chủ sang dạng trang đang dùng (sản phẩm, dòng giỏ, đơn hàng, khách) và `VN.duLieu` (sản phẩm, danh mục, bộ sưu tập). Chỗ duy nhất biết cả hai cách gọi tên: xem `docs/database/doi-chieu-giao-dien.md` |
| `frontend/src/js/core/session.js` | `VN.taiKhoan` (đăng nhập, hồ sơ, sổ địa chỉ), `VN.gioHang`, `VN.uuDai` (kiểm tra mã giảm giá), `VN.donHang` (đặt, tra cứu, thanh toán, hủy, xác nhận nhận hàng). `VN.sanSang` xong khi đã biết ai đang đăng nhập và giỏ hàng có gì |

Cách một trang dùng: `await VN.sanSang`, đọc trạng thái bằng hàm thường (`VN.taiKhoan.hienTai()`, `VN.gioHang.ds()`, `VN.donHang.lay(mã)`), còn thao tác ghi là hàm bất đồng bộ gọi API (`await VN.gioHang.them(...)`).

- **Sản phẩm.** Trang tải cả danh mục một lần (5 lần gọi `GET /api/products?limit=100`, lưu trong `sessionStorage` tối đa 5 phút) rồi lọc, đếm và sắp xếp ngay trên trình duyệt. Với 443 sản phẩm cách này nhanh và giữ nguyên bộ lọc cũ. Giá và tồn kho vẫn được máy chủ kiểm tra lại khi thêm giỏ và đặt hàng. Trang chi tiết gọi thêm `GET /api/products/<mã>` để lấy đủ ảnh, đá và các biến thể (màu, size, tồn kho). Chỉ hiện các size đang có trong kho.
- **Sản phẩm chỉ báo giá** (`IsQuoteOnly`): hiện "Liên hệ báo giá", không có nút mua.
- **Giỏ hàng.** Khách có tài khoản: giỏ nằm trong database. Khách chưa đăng nhập: giỏ nằm trong `localStorage` của trình duyệt, gửi kèm khi đặt hàng. Khi đăng nhập hoặc đăng ký, giỏ của trình duyệt được gộp vào giỏ tài khoản. Mỗi dòng giỏ mua tối đa 5 (giới hạn của giao diện, database cho 10). Nếu lúc tải trang máy chủ không trả lời (mạng chập chờn), trang thử lại 3 lần. Vẫn lỗi thì hiện thông báo "Chưa kết nối được máy chủ" kèm nút Tải lại, và chặn thay đổi giỏ cho tới khi kết nối lại. Khách đã đăng nhập không bị coi là khách vãng lai trong lúc đó, nên giỏ không bị ghi nhầm vào trình duyệt.
- **Trước khi đặt**, trang thanh toán đọc lại danh mục từ máy chủ (bỏ bản lưu 5 phút), bỏ khỏi giỏ các sản phẩm đã ngừng bán hoặc ẩn rồi báo cho khách, và so lại giá. Giá đổi hoặc có dòng bị bỏ thì đơn chưa đặt, khách xem lại tổng tiền rồi bấm đặt lần nữa.
- **Đặt hàng.** Có tài khoản: chọn địa chỉ trong sổ (địa chỉ mới được thêm vào sổ, xóa lại sau khi đặt nếu khách bỏ chọn "Lưu địa chỉ"). Không tài khoản: `POST /api/orders/guest`, số điện thoại là mã khách. Mua tặng người khác thì số người đặt dùng để tra cứu, số người nhận để giao. Mã đơn và số điện thoại của khách không tài khoản được nhớ trong `localStorage` (khóa `donKhach`) để xem lại đơn trên trình duyệt đó.
- **Thanh toán trực tuyến** (VNPay, MoMo) là mô phỏng: cổng giả trên trang gọi `POST /api/orders/<mã>/pay`. Phải xong trong 15 phút, trang kết quả và trang đơn hàng đếm ngược. Hết giờ máy chủ tự hủy đơn.
- **Hủy đơn.** Nút "Hủy đơn" theo `CancelChannel`: `Web` thì hiện bước chọn lý do rồi popup nhắc mất voucher (giữ hoặc hủy); `Hotline` thì hiện hướng dẫn gọi hotline; đơn đang chế tác không có nút.
- **Giờ.** API trả giờ kèm múi giờ của máy chạy backend (`2026-11-03T14:15:00+07:00`), nên đồng hồ đếm ngược đúng ở mọi múi giờ. Database và backend phải chạy cùng múi giờ.
- **Trang quản trị (nhóm C8).** Sáu trong bảy trang đã nối API: **Đơn hàng**, **Tổng quan**, **Khách hàng**, **Đánh giá**, **Bảo hành và lịch hẹn**, **Sản phẩm**. Đơn hàng và lịch hẹn được nạp một lần khi mở trang (`admin.js` giữ trong `qt.don` và `qt.lich`, đơn nạp 100 đơn mỗi lần gọi). Mở một đơn thì gọi thêm `GET /api/admin/orders/<mã>`. Trang **Phản ánh** vẫn đọc dữ liệu mô phỏng trong trình duyệt vì database chưa có bảng phản ánh (đầu trang có dòng nhắc). Database cũng chưa có: hoàn tiền hai bước (`RefundPending`), ghi chú nội bộ của đơn, phản hồi của cửa hàng cho đánh giá, khung giờ và showroom của lịch hẹn (chỉ có một mốc ngày giờ). Các trang này chỉ cập nhật khi tải lại hoặc sau thao tác của admin.
- **Giá và trạng thái sản phẩm** sửa ở trang Sản phẩm, lưu thẳng vào database (`PATCH /api/admin/products/<sku>`). Cửa hàng giữ danh mục 5 phút trong trình duyệt (`sessionStorage`), nên khách thấy giá mới sau tối đa 5 phút.
- **Luồng xử lý đơn ở trang admin:** Chờ xử lý → *Xác nhận đơn* (`Confirmed`) → *Bắt đầu chế tác* (không bắt buộc, từ đó không ai hủy được) → *Bàn giao vận chuyển* (`Shipping`) → *Giao thành công* (`Delivered`, kích hoạt thẻ bảo hành, đơn COD ghi nhận đã thu tiền). Đơn chuyển khoản phải bấm *Xác nhận đã nhận tiền* trước. Hủy đơn được khi `Pending` hoặc `Confirmed` chưa chế tác.
- **Bảo hành, đặt lịch, đánh giá, phản ánh, yêu thích, đã xem:** còn lưu trong `localStorage`, chờ nhóm C6 và C7. Database đã tạo thẻ bảo hành thật khi khách xác nhận nhận hàng, nhưng trang bảo hành chưa đọc chúng.
- Kiểm tra: `backend/tests/test_frontend_adapters.py` chạy các hàm đổi dữ liệu của `api.js` bằng Node trên câu trả lời thật của API (bỏ qua nếu máy chưa cài Node).

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
| `GET /api/products` | Danh sách sản phẩm đang bán, có lọc và sắp xếp (xem bảng dưới) |
| `GET /api/products/<sku>` | Chi tiết một sản phẩm, kèm ảnh, đá và biến thể (`variants`: màu, size, tồn kho). Ví dụ `/api/products/NDINO131LDIA` |

Sản phẩm có `IsQuoteOnly: true` (22 sản phẩm vàng 24K, 22K tính theo giá vàng ngày) **chỉ báo giá**: `CurrentPrice` là `null`, không vào giỏ được (409, `reason: quote_only`), không khớp bộ lọc giá và xếp cuối khi sắp xếp theo giá.

Tham số của `GET /api/products`. Các tham số khác nhau kết hợp bằng AND, các giá trị trong một tham số (cách nhau bằng dấu phẩy) kết hợp bằng OR:

| Tham số | Ý nghĩa |
|---|---|
| `category` | Id danh mục, ví dụ `1,2,3` (tối đa 50 id) |
| `collection` | Id bộ sưu tập. Sản phẩm thuộc bất kỳ bộ sưu tập nào trong danh sách đều khớp |
| `material` | Tuổi vàng: `10K`, `14K`, `18K`, `22K`, `24K`, `BAC925` |
| `color` | Màu vàng, ví dụ `Vàng Trắng,Bạc Trắng` (tối đa 10 màu). Khớp khi sản phẩm có biến thể đang bán màu đó |
| `minPrice`, `maxPrice` | Khoảng giá hiện hành, đơn vị đồng, gồm cả hai đầu |
| `onSale=1` | Chỉ sản phẩm đang giảm giá (`OriginalPrice` lớn hơn `CurrentPrice`) |
| `q` | Tìm theo tên, không phân biệt hoa thường và dấu. Ký tự `%`, `_`, `[` được tìm đúng như đã gõ |
| `sort` | `featured` (mặc định: sản phẩm có mô tả trước), `newest`, `price_asc`, `price_desc`, `discount` (giảm nhiều nhất trước). Sản phẩm chưa có giá luôn xếp cuối khi sắp theo giá |
| `page`, `limit` | Phân trang. `limit` tối đa 100, mặc định 24 |

Mỗi sản phẩm trong danh sách còn có `Colors` (các màu đang bán), `Images` (hai ảnh đầu, ảnh đại diện trước), `HasDescription` và `CreatedAt` (ngày tạo thật, dùng cho "Mới nhất" và nhãn "Mới"), đủ để vẽ thẻ sản phẩm.

Tham số sai trả về 400, kèm tên tham số sai. Mã sản phẩm không có trả về 404. Test nằm ở `backend/tests/test_products.py` và cần database đang chạy.

### Đăng nhập và phân quyền

Cần `SECRET_KEY` trong file `.env` (chuỗi ngẫu nhiên từ 32 ký tự trở lên, dùng để ký cookie đăng nhập). Tạo bằng:

```bash
uv run python -c "import secrets; print(secrets.token_hex(32))"
```

Mật khẩu lưu bằng bcrypt. Đăng nhập được giữ trong cookie phiên. Có hai vai trò: `Customer` và `Admin`. Đăng ký luôn tạo `Customer`.

| Địa chỉ | Việc làm |
|---|---|
| `POST /api/auth/register` | Đăng ký. Body: `fullName`, `email`, `password` (8 đến 72 byte), `phone` (không bắt buộc), `otp` (xem dưới). Trả 201 và tự đăng nhập. Email trùng trả 409. Số điện thoại đã thuộc một tài khoản trả 409 với `reason: phone_in_use` |
| `POST /api/auth/login` | Đăng nhập bằng `email` và `password`. `remember: true` giữ đăng nhập 14 ngày, không có thì cookie hết khi đóng trình duyệt. Sai mật khẩu hoặc email không có đều trả 401 cùng một nội dung. Tài khoản bị khóa trả 403 |
| `POST /api/auth/logout` | Đăng xuất, trả 204 |
| `GET /api/auth/me` | Thông tin người đang đăng nhập, chưa đăng nhập trả 401 |
| `POST /api/auth/change-password` | Đổi mật khẩu. Body: `currentPassword`, `newPassword` (8 đến 72 byte). Mật khẩu hiện tại sai trả 403 (không phải 401, để giao diện không nhầm với hết phiên). Thành công trả 204, vẫn đăng nhập |
| `GET /api/admin/users` | Danh sách tài khoản. Chỉ `Admin`: chưa đăng nhập trả 401, là khách trả 403 |

Các tài khoản mẫu trong database (như `admin@vinora.vn`) mang mã băm giả nên chưa đăng nhập được. Đặt mật khẩu thật cho một tài khoản bằng:

```bash
uv run python scripts/set_password.py admin@vinora.vn
```

Giới hạn đầu vào: tên tối đa 100 ký tự, email chỉ gồm ký tự ASCII (tối đa 255), thân yêu cầu tối đa 16 KB (quá thì trả 413). Các trường phải là chuỗi.

Chưa làm: giới hạn số lần đăng nhập sai, cờ `Secure` cho cookie khi chạy HTTPS, hết hạn phiên phía server. Cookie đăng nhập cũ vẫn dùng được sau khi đổi mật khẩu, vì phiên không gắn với mật khẩu. Cần bổ sung trước khi đưa lên mạng thật.

Test nằm ở `backend/tests/test_auth.py`.

### Giỏ hàng, địa chỉ và đơn hàng

Các API này cần đăng nhập bằng tài khoản khách (`Customer`). Tài khoản `Admin` gọi vào trả 403. Ngoại lệ là các API đơn hàng có `<mã đơn>` và `POST /api/orders/guest`: khách **không có tài khoản** (khách vãng lai) dùng được, xem mục "Đặt hàng không cần tài khoản" bên dưới. Quy tắc nghiệp vụ nằm trong stored procedure của SQL Server. Back-end chỉ kiểm tra đầu vào, gọi thủ tục, và đổi lỗi của thủ tục thành mã HTTP. Thông báo lỗi là câu tiếng Việt viết sẵn trong thủ tục.

| Địa chỉ | Việc làm |
|---|---|
| `GET /api/addresses`, `POST /api/addresses` | Sổ địa chỉ. Địa chỉ đầu tiên tự là mặc định. `isDefault: true` đổi mặc định sang địa chỉ mới |
| `PATCH /api/addresses/<id>` | Sửa địa chỉ, chỉ gửi trường cần đổi. `isDefault: true` đặt làm mặc định. Tắt mặc định của địa chỉ đang là mặc định trả 400, phải đặt địa chỉ khác làm mặc định |
| `DELETE /api/addresses/<id>` | Xóa địa chỉ (204). Xóa địa chỉ mặc định thì địa chỉ cũ nhất còn lại thành mặc định. Đơn đã đặt giữ bản sao địa chỉ riêng |
| `GET /api/cart` | Giỏ hàng kèm `subtotal`, `shippingFee`, `total` |
| `POST /api/cart` | Thêm biến thể: `variantSku`, `quantity` (1 đến 10), `engravingText` (khắc tên, tối đa 15 ký tự), `engravingStyle` (`Classic`, `Modern`, `Handwritten`, mặc định `Classic`, bỏ qua nếu không có chữ khắc). Thêm lại cùng biến thể, cùng chữ khắc và cùng kiểu chữ thì cộng dồn số lượng, khác kiểu chữ là dòng riêng. Quá tồn kho trả 409 |
| `PATCH /api/cart/<id>`, `DELETE /api/cart/<id>` | Đổi số lượng, xóa dòng |
| `POST /api/orders` | Đặt hàng từ giỏ (`sp_PlaceOrder`). Body: `addressId`, `paymentMethod` (`COD`, `BankTransfer`, `VNPay`, `MoMo`), `checkoutToken`, `voucherCode`, `note`. Trả 201 |
| `GET /api/orders`, `GET /api/orders/<mã đơn>` | Đơn của chính khách. Đơn của người khác trả 404. Danh sách mỗi đơn có `items` (sản phẩm, kèm `ProductSKU` và `SKUSnap` là mã biến thể). Chi tiết có thêm địa chỉ, các mốc thời gian, `payments` (kèm `TransactionID`) và `pendingCancelRequest` |
| `POST /api/orders/<mã đơn>/cancel` | Khách bấm "Hủy đơn" (`sp_RequestCancelOrder`). Chưa hủy ngay: trả `RequestID`, `VoucherCode`, `VoucherDiscount`, `Subtotal` (giá gốc), `TotalAmount` để hiện popup "hủy sẽ mất voucher, đặt lại chỉ còn giá gốc". Đơn từ 2.000.000 đ hoặc có khắc chữ trả 403 kèm câu "gọi hotline". Đơn đã bắt đầu chế tác trả 409 |
| `POST /api/orders/<mã đơn>/pay` | Thanh toán mô phỏng cho đơn VNPay hoặc MoMo, luôn thành công (`sp_RecordPaymentResult`). Đơn đã hủy hoặc quá 15 phút trả 409. Đơn COD và chuyển khoản trả 400 |
| `POST /api/orders/<mã đơn>/cancel/respond` | Khách chọn trong popup (`sp_RespondCancelPopup`): `keepOrder: true` giữ đơn, `keepOrder: false` hủy đơn, trả tồn kho, mất voucher |
| `POST /api/orders/<mã đơn>/confirm-received` | Xác nhận đã nhận hàng (`sp_ConfirmOrderReceived`). Chỉ khi đơn đang giao. Database tự tạo thẻ bảo hành |
| `GET /api/admin/orders` | Admin xem mọi đơn, mỗi đơn kèm `items`, `PaymentDeadline`, `PaidAt`. Tham số `status`, `page`, `limit` (tối đa 100) |
| `GET /api/admin/orders/<mã đơn>` | Admin xem một đơn đầy đủ (cùng dạng `GET /api/orders/<mã>`) kèm khối `customer` (tên, email, số điện thoại, `IsGuest`) |
| `POST /api/admin/orders/<mã đơn>/status` | Admin đổi trạng thái (`sp_UpdateOrderStatus`): `Confirmed`, `Shipping`, `Delivered`, `Cancelled`. Nhảy bước trả 409. Hủy đơn đã bắt đầu chế tác trả 409 |
| `POST /api/admin/orders/<mã đơn>/confirm-payment` | Admin xác nhận đã nhận tiền chuyển khoản (mô phỏng, không nối ngân hàng). Chỉ đơn `BankTransfer` |
| `POST /api/admin/orders/<mã đơn>/start-production` | Admin đánh dấu đã bắt đầu chế tác đơn (`sp_StartOrderProduction`). Từ lúc này không ai hủy được đơn. Chỉ đơn đã xác nhận |
| `GET /api/admin/customers` | Mọi khách (có tài khoản và khách vãng lai): số đơn `OrderCount`, đã trả `TotalPaid` (chỉ thanh toán thành công), đơn gần nhất, số thẻ bảo hành |
| `GET /api/admin/feedbacks` | Mọi đánh giá, mới nhất trước, kèm nhãn `SentimentLabel` (chỉ cửa hàng thấy) và các yếu tố `aspects` |
| `GET /api/admin/warranties` | Mọi thẻ bảo hành kèm chủ thẻ, lượt đánh bóng còn lại, số lần làm sạch và chỉnh size |
| `GET /api/admin/services` | Mọi lịch hẹn hậu mãi, mới nhất trước |
| `POST /api/admin/services/<id>/schedule` | Xác nhận lịch hẹn (`sp_ScheduleAfterSalesService`). Không gửi gì: xác nhận giờ khách chọn (`Confirmed`). Gửi `appointmentDate` (giờ tương lai): đề xuất giờ khác (`Rescheduled`) |
| `POST /api/admin/services/<id>/complete` | Hoàn tất dịch vụ (`sp_CompleteAfterSalesService`): trừ một lượt của thẻ, miễn phí hay tính phí do database quyết định. Tùy chọn `resultNote`. Lịch chưa xác nhận hoặc đã xong trả 409 |
| `POST /api/admin/services/<id>/cancel` | Cửa hàng hủy lịch chưa hoàn tất (`sp_CancelAfterSalesService`), khách không mất lượt |
| `GET /api/admin/products` | Mọi sản phẩm, cả đã ẩn và ngừng bán, kèm số đã bán (không tính đơn hủy) |
| `PATCH /api/admin/products/<sku>` | Đổi `price`, `originalPrice` (null bỏ giảm giá), `status` (`Active`, `Hidden`, `Discontinued`). Giá chỉ cho sản phẩm giá cố định, sản phẩm giá theo vàng trả 409 |

Điểm cần nhớ:
- `checkoutToken` là một UUID do trình duyệt tạo cho mỗi lần thanh toán. Gửi lại cùng token (bấm đúp, mạng chậm) thì nhận lại đúng đơn cũ với mã 200, không tạo đơn thứ hai.
- Phí giao hàng do server tính, không nhận từ trình duyệt: 30.000 đ, miễn phí khi tiền hàng từ 2.000.000 đ (tính trước khi giảm giá). Hằng số nằm ở `backend/app/config.py`.
- Quy tắc hủy đơn (số tiền khách phải trả, sau voucher, nằm trong `fn_OnlineCancelLimit()`): **dưới 2.000.000 đ và không khắc chữ** thì khách tự hủy trên web (qua popup nhắc mất voucher). **Từ 2.000.000 đ, hoặc có khắc chữ** thì phải gọi hotline; nhân viên hỏi tình hình chế tác rồi hủy bằng API admin. Đơn đã bắt đầu chế tác thì không ai hủy được. Ví dụ: giá gốc 2.198.000 đ, voucher `GIAM300K` còn 1.898.000 đ thì tự hủy được; không voucher thì phải gọi hotline.
- Hủy đơn có hai bước. Bước 1 (`/cancel`) chỉ tạo yêu cầu và cho biết voucher sẽ mất. Bước 2 (`/cancel/respond`) mới giữ hoặc hủy. Cột `CancelChannel` trong danh sách đơn cho biết trang nên hiện nút hủy (`Web`), dòng "gọi hotline" (`Hotline`) hay không hiện gì (`null`). Admin hủy đơn qua `POST /api/admin/orders/<mã đơn>/status` với `Cancelled`.
- Gửi lại cùng token cho kết quả giống hệt lần đầu (cùng khóa `OrderCode`, `TotalAmount`, `ShippingFee`), chỉ khác mã 200 thay vì 201.
- Địa chỉ đầy đủ (đường, phường, tỉnh) tối đa 400 ký tự, vì đơn hàng chép địa chỉ vào một cột 400 ký tự.
- Kiểu chữ khắc được chép sang đơn hàng (`EngravingStyle`) để nhân viên chế tác biết. Mã và trạng thái giao diện dùng khác database (kiểu chữ, phương thức thanh toán, trạng thái đơn, thanh toán, lịch hẹn): xem `docs/database/doi-chieu-giao-dien.md`.
- Khắc tên: database coi chữ hoa và chữ thường là một, và bỏ qua dấu thanh ("Mai" bằng "Mại"). Thêm một chữ khắc chỉ khác kiểu đó vào giỏ trả 409. Các chữ khác nhau thật như "Năm" và "Nam" là hai dòng riêng.
- Hai yêu cầu chạy cùng lúc gây xung đột (trùng dòng giỏ hàng, mã ưu đãi vừa hết lượt) trả 409 để thử lại. Lỗi database khác trả 500 với câu chung, không lộ nội dung SQL. Khi SQL Server chọn một yêu cầu làm nạn nhân của deadlock (hai yêu cầu chờ nhau), hàm `call()` tự chạy lại thủ tục, tối đa 3 lần.
- Thanh toán là mô phỏng hoàn toàn: không có cổng thật. Đơn trả trực tuyến (VNPay, MoMo, chuyển khoản) phải thanh toán trong **15 phút** (`fn_PaymentTimeoutMinutes()`), quá hạn thì đơn thất bại: hủy, trả tồn kho, trả lượt voucher, thanh toán chuyển sang `Expired`. `PaymentDeadline` trong thông tin đơn là giờ hết hạn, để giao diện đếm ngược. Backend gọi `sp_ExpireUnpaidOrders` trước mỗi yêu cầu `/api/` nên không cần bộ hẹn giờ.
- Chưa làm: bảo hành và lịch hẹn hậu mãi, đánh giá, hoàn tiền thật (hủy đơn đã trả tiền chỉ đổi thanh toán sang `Refunded`).

### Đặt hàng không cần tài khoản

Khách chưa đăng nhập vẫn đặt hàng được. **Số điện thoại là mã khách hàng**: một số là một khách. Số được lưu một kiểu duy nhất (`+84901234567` thành `0901234567`).

| Địa chỉ | Việc làm |
|---|---|
| `POST /api/orders/guest` | Đặt hàng. Body: `fullName`, `phone`, `addressLine`, `ward`, `province`, `items` (tối đa 20 dòng, mỗi dòng `variantSku`, `quantity`, `engravingText`, `engravingStyle`), `paymentMethod`, `checkoutToken`, `voucherCode`, `note`. `recipientPhone` (không bắt buộc) là số người nhận khi mua tặng: `phone` vẫn là số người đặt dùng để tra cứu. Giỏ của khách vãng lai nằm trong trình duyệt nên gửi kèm trong yêu cầu. Trả 201 (gửi lại cùng token trả 200). Số đã có tài khoản trả 409 với `reason: phone_has_account` |
| `GET /api/orders/<mã đơn>?phone=<sđt>` | Tra cứu đơn bằng mã đơn và số điện thoại. Sai số hoặc sai mã đều trả 404 cùng một nội dung |
| `POST /api/orders/<mã đơn>/cancel`, `/cancel/respond`, `/confirm-received`, `/pay` | Giống khách có tài khoản, gửi thêm `phone` trong body |

- Khi khách vãng lai đăng ký tài khoản bằng đúng số đó, đơn, địa chỉ và thẻ bảo hành cũ tự thuộc về tài khoản (dòng khách hàng được gắn thêm `UserID`). Cần mã xác minh: gửi `otp` trong `POST /api/auth/register`. Thiếu mã trả 409 `reason: otp_required`, sai mã trả 400 `reason: otp_invalid`, thành công trả `linkedOrders` (số đơn nhận lại).
- **Mã xác minh là mã giả `123456`** (hằng `DEMO_OTP` trong `backend/app/config.py`), vì cửa hàng không gửi SMS. Ai biết số điện thoại của khách vãng lai và mã này đều nhận được đơn cũ của số đó, nên đây chỉ dùng để demo. Muốn dùng thật phải gửi mã ngẫu nhiên qua SMS.
- Khách vãng lai không có danh sách đơn (cần mã đơn). Admin thấy đơn của họ trong `GET /api/admin/orders` với `IsGuest: true`, tên người nhận và số điện thoại.
- Các yêu cầu đặt hàng cùng một số điện thoại chạy lần lượt (khóa theo số, chờ tối đa 10 giây, quá thì trả 409), vì dùng chung một giỏ tạm. Đặt hàng thất bại thì không để lại khách, địa chỉ hay giỏ nào.
- Số điện thoại được chuẩn hóa: `+84901234567`, `84901234567`, `0084901234567` và `0901234567` là một số.
- **Rủi ro đã biết, chưa xử lý** (cần làm trước khi đưa lên mạng thật, thuộc nhóm bảo mật): mã đơn tăng dần nên đoán được; mã xác minh là mã giả; chưa giới hạn số lần thử theo địa chỉ IP hoặc số điện thoại; trả lời đăng ký cho biết một số điện thoại có đơn hay có tài khoản; số điện thoại nằm trong địa chỉ URL của `GET /api/orders/<mã đơn>?phone=` (nên dùng POST khi có thể); `POST /api/vouchers/check` không cần đăng nhập nên có thể bị dùng để dò mã giảm giá (mã chưa tới ngày hoặc đã tắt vẫn trả 404 như mã không tồn tại).

### Hồ sơ, tra cứu và sản phẩm đã xem

| Địa chỉ | Việc làm |
|---|---|
| `GET /api/profile`, `PATCH /api/profile` | Hồ sơ khách (cần đăng nhập khách). Sửa `fullName`, `phone` (không trùng khách khác, trùng trả 409 `phone_in_use`), `dateOfBirth` (`YYYY-MM-DD`, trước hôm nay), `defaultRingSize` (có trong bảng size nhẫn). Chỉ trường có trong body mới đổi. `null` hoặc `""` xóa số điện thoại, ngày sinh, size. Một trường sai thì không lưu gì. Email và vai trò không đổi được ở đây |
| `GET /api/categories` | Danh mục còn bán, kèm số sản phẩm (`ProductCount`). Thay `mock-data/categories.json` |
| `GET /api/collections` | Bộ sưu tập kèm số sản phẩm, các danh mục (`Categories`) và tuổi vàng (`Materials`) có trong bộ sưu tập. Thay `mock-data/collections.json` |
| `GET /api/ring-sizes` | Bảng quy đổi size nhẫn. Thay `mock-data/size-chart.json` |
| `GET /api/gold-prices` | Giá vàng đang có hiệu lực cho từng tuổi vàng (đồng một chỉ), cao nhất trước |
| `POST /api/vouchers/check` | Kiểm tra mã giảm giá với giỏ hàng hiện tại. Khách đăng nhập: tính trên giỏ trong database. Khách chưa đăng nhập gửi giỏ của trình duyệt trong `items` (cùng dạng với đơn không tài khoản), thiếu cả đăng nhập lẫn `items` trả 401. Body: `code`. Thành công trả `discount`. Mã không có, đã tắt hoặc chưa tới ngày trả 404. Hết hạn, hết lượt hoặc chưa đủ tiền tối thiểu trả 409 kèm `reason` (`expired`, `used_up`, `min_order`). Cách tính giống `sp_PlaceOrder`; việc đặt hàng mới là lúc giảm giá được chốt |
| `POST /api/recently-viewed` | Ghi nhận khách vừa mở một sản phẩm. Body: `sku`. Trả 204 (`sp_TrackProductView`) |
| `GET /api/recently-viewed` | Sản phẩm đã xem, mới nhất trước. Tham số `limit` (mặc định 10, tối đa 50) |

Điểm cần nhớ:
- Các API tra cứu (`categories`, `collections`, `ring-sizes`, `gold-prices`) không cần đăng nhập.
- Khách chưa đăng nhập giữ danh sách đã xem trong trình duyệt, API này chỉ cho khách có tài khoản.
- Bảng size nhẫn trong database và trong `mock-data/size-chart.json` lệch nhau ở size 15 (size Mỹ 7,5 so với 7,0). Các phần còn lại giống nhau.

### Chạy test

```bash
uv run pytest
```

Test nằm trong `backend/tests/` (564 test, chạy khoảng bốn phút). Test không đụng vào dữ liệu thật. Mỗi lần chạy, `backend/tests/conftest.py` dựng lại một database riêng tên `VinoraJewelry_Test` từ file `database/01_*.sql` (mất khoảng 5 giây). Cần quyền tạo database trên SQL Server. Nếu không kết nối được, các test bị bỏ qua và pytest in lý do.

## Quy ước

- Tên file, thư mục, biến trong code: tiếng Anh, `kebab-case` cho file, `snake_case` cho Python.
- Nội dung hiển thị trên giao diện: tiếng Việt.
- Không commit `.env`, mật khẩu, khóa API hay dữ liệu khách hàng thật.
- Làm việc theo nhánh `feature/<tên>`, tạo Pull Request vào `main`.

## Thành viên nhóm

_(điền sau)_
