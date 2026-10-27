# Vinora Jewelry – bản HTML thuần (mở bằng Live Server)

Không cần Python/Flask. Chỉ gồm HTML + CSS + JavaScript + dữ liệu JSON/XML.

## Cách mở
1. Giải nén, mở thư mục `VinoraJewelry_HTML` bằng VS Code.
2. Cài tiện ích **Live Server** (Ritwick Dey) nếu chưa có.
3. Chuột phải `index.html` → **Open with Live Server** (hoặc bấm *Go Live* góc dưới).

> Không bấm đúp mở file `.html` trực tiếp (đường dẫn `file://`): trình duyệt chặn AJAX đọc `static/dulieu/*.json` và `cuahang.xml`, trang sẽ không có sản phẩm.

## Cấu trúc
```
VinoraJewelry_HTML/
├── index.html                 5.2.1 Trang chủ
├── danhsachsanpham.html       5.2.2 Danh sách sản phẩm (?danhmuc= ?bst= ?q= …)
├── chitietsanpham.html        5.2.3 Chi tiết sản phẩm (?ma=MÃ_SKU)
├── sanphamdaxem.html          5.2.4 Sản phẩm đã xem
├── giohang.html, thanhtoan.html, dathangthanhcong.html      5.2.5
├── quanlydonhang.html (+ popup hủy đơn 5.2.6)               5.2.7
├── kichhoatbaohanh.html, congbaohanh.html                   5.2.8
├── taikhoan.html, gioithieu.html, lienhe.html, huongdanchonsize.html,
│   chinhsachgiaohang.html, chinhsachbaohanh.html, loi404.html
└── static/  css/ (chung, khachhang) · js/ (chung, khachhang) · dulieu/ · hinh/ · thuvien/fonts/
```

## Tài khoản demo
`demo@vinora.vn` / `Vinora@2026` (nút “Dùng tài khoản này” ở trang Tài khoản). Dữ liệu lưu bằng localStorage của trình duyệt – mở DevTools → Application → Local Storage để xem các khóa `vinora.*`.

Mã ưu đãi: `VINORA5`, `CHAOBAN200`, `FREESHIP`. Thẻ VNPay Sandbox (mô phỏng): OTP `123456`.
Mức ưu đãi giữ đơn, phí giao hàng, quyền lợi bảo hành… chỉnh tập trung trong `static/dulieu/cauhinh.json`.

## Lưu ý
- Đầu trang / chân trang được lặp sẵn trong từng file HTML (bản Flask dùng `{% include %}`); khi sửa menu cần sửa ở tất cả các trang.
- Ảnh sản phẩm tải từ CDN gốc nên cần Internet; mất mạng sẽ hiện ảnh tạm.
