# Database (Microsoft SQL Server)

Yêu cầu: SQL Server 2019 trở lên (khuyến nghị 2022), công cụ SSMS.

| File | Vai trò | Khi nào chạy |
|---|---|---|
| `01_init_schema.sql` | Tạo database `VinoraJewelry`, 26 bảng, chỉ mục, trigger, stored procedure, view, dữ liệu danh mục/sản phẩm và dữ liệu mẫu minh họa | Chạy đầu tiên |
| `02_seed_fake_data.sql` | Sinh dữ liệu giả lập (khoảng 100 dòng mỗi bảng chính, 300 đơn hàng) phục vụ demo và dashboard | Chạy sau file 01, chỉ ở môi trường dev/demo |

## Cách chạy
1. Mở `01_init_schema.sql` trong SSMS, nhấn F5.
2. (Tùy chọn) mở `02_seed_fake_data.sql`, nhấn F5.

> **Cảnh báo:** file `01_init_schema.sql` xoá database `VinoraJewelry` nếu đã tồn tại rồi tạo lại. Không chạy trên máy đang có dữ liệu cần giữ. Để sinh lại dữ liệu giả lập, chạy lại file 01 trước.

Mật khẩu của tài khoản mẫu là chuỗi băm giả, không đăng nhập được. Back-end cần tạo băm bcrypt thật.
