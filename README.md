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
│   │   ├── services/          # nghiệp vụ: giữ đơn, kích hoạt bảo hành, phí giao hàng
│   │   ├── schemas/           # kiểm tra dữ liệu vào/ra
│   │   ├── templates/         # Jinja templates (nếu dùng server-side render)
│   │   └── utils/
│   ├── migrations/
│   ├── tests/
│   ├── requirements.txt
│   └── run.py
│
├── database/
│   ├── 01_init_schema.sql     # tạo DB, 26 bảng, trigger, procedure, view, dữ liệu sản phẩm
│   ├── 02_seed_fake_data.sql  # dữ liệu giả lập cho dev/demo
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

Cần đã chạy `database/01_init_schema.sql`. Mở terminal ở gốc repo:

```bash
uv run python backend/run.py
```

| Địa chỉ | Việc làm |
|---|---|
| `GET /api/products` | Danh sách sản phẩm đang bán. Tham số: `category` (id danh mục), `q` (tìm theo tên, không phân biệt hoa thường và dấu), `page`, `limit` (tối đa 100, mặc định 24) |
| `GET /api/products/<sku>` | Chi tiết một sản phẩm, kèm ảnh, đá và biến thể. Ví dụ `/api/products/NDINO131LDIA` |

Tham số sai trả về 400. Mã sản phẩm không có trả về 404. Test nằm ở `backend/tests/test_products.py` và cần database đang chạy.

## Quy ước

- Tên file, thư mục, biến trong code: tiếng Anh, `kebab-case` cho file, `snake_case` cho Python.
- Nội dung hiển thị trên giao diện: tiếng Việt.
- Không commit `.env`, mật khẩu, khóa API hay dữ liệu khách hàng thật.
- Làm việc theo nhánh `feature/<tên>`, tạo Pull Request vào `main`.

## Thành viên nhóm

_(điền sau)_
