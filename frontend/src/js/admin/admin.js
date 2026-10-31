/* =====================================================================
   VINORA ADMIN – phần dùng chung cho mọi trang quản trị
   - Bảo vệ trang: chưa đăng nhập quản trị -> về ô đăng nhập chung (taikhoan.html), đăng nhập xong quay lại
   - Tên người dùng, đăng xuất, số việc cần xử lý trên menu
   - Tiện ích hiển thị: nhãn trạng thái, tên khách, ngăn chi tiết
   Dữ liệu dùng chung với cửa hàng qua VN.donHang, VN.hoTro, VN.lichHen… (chung.js)
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const qt = (VN.qt = {});

  /* ---------- Phiên quản trị ---------- */
  qt.nguoi = VN.quanTri.hienTai();
  if (!qt.nguoi) {
    location.replace(VN.url('taiKhoan', { tiep: location.pathname + location.search }));
    qt.chan = true;
    return;
  }
  /** Ai thực hiện thao tác (ghi vào nhật ký đơn / phản ánh / lịch hẹn) */
  qt.boi = (vaiTro) => `${vaiTro || 'Cửa hàng'} (${qt.nguoi ? qt.nguoi.hoTen : 'Quản trị'})`;

  /* ---------- Tiện ích hiển thị ---------- */
  qt.nhanDon = (d) => { const t = VN.TRANG_THAI_DON[d.trangThai]; return `<span class="nhan ${t.lop}">${t.ten}</span>`; };
  qt.nhanTT = (d) => {
    const tts = d.thanhToan.trangThai;
    if (tts === 'Pending' && d.trangThai === 'Cancelled') return '<span class="nhan">Chưa thanh toán</span>';
    if (d.thanhToan.phuongThuc === 'COD' && tts === 'Pending') return '<span class="nhan">COD – thu khi giao</span>';
    const t = VN.TRANG_THAI_TT[tts] || { ten: tts, lop: '' };
    return `<span class="nhan ${t.lop}">${t.ten}</span>`;
  };
  qt.chuaTra = (d) => d.trangThai === 'Pending' && d.thanhToan.phuongThuc !== 'COD' && d.thanhToan.trangThai !== 'Success';
  /** Tên khách: tài khoản (nếu có) hoặc người nhận + đánh dấu khách không tài khoản */
  qt.khach = (d) => {
    const u = d.khachHang ? VN.taiKhoan.ds().find((x) => x.id === d.khachHang) : null;
    return { ten: u ? u.hoTen : d.nguoiNhan.hoTen, sdt: d.sdtKhach || d.nguoiNhan.sdt, email: u ? u.email : (d.nguoiNhan.email || ''), coTaiKhoan: !!u };
  };
  qt.tenKhachTheoId = (id, sdt) => { const u = id ? VN.taiKhoan.ds().find((x) => x.id === id) : null; return u ? u.hoTen : (sdt ? `Khách ${VN.anSdt(sdt)}` : 'Khách hàng'); };
  qt.nhatKy = (ls) => `<ol class="nhat-ky-qt">${(ls || []).slice().reverse().map((l) => `<li><time>${VN.ngayGio(l.luc)}</time><div>${VN.thoat(l.noiDung)}<small>${VN.thoat(l.boi || '')}</small></div></li>`).join('')}</ol>`;
  qt.trong = (chu) => `<div class="qt-trong">${chu}</div>`;
  /** Phân trang đơn giản cho bảng dài */
  qt.phanTrang = (ds, trangSo, coTrang = 20) => {
    const tong = Math.max(1, Math.ceil(ds.length / coTrang)); const t = Math.min(Math.max(1, trangSo), tong);
    return { muc: ds.slice((t - 1) * coTrang, t * coTrang), trang: t, tong, tu: ds.length ? (t - 1) * coTrang + 1 : 0, den: Math.min(ds.length, t * coTrang), soMuc: ds.length };
  };
  qt.htmlPhanTrang = (p) => `<div class="qt-trang"><span>Hiển thị ${p.tu} – ${p.den} / ${p.soMuc}</span>${p.tong > 1 ? `<div class="qt-trang__nut">
      <button type="button" class="nut nut--vien nut--rat-nho" data-trang="${p.trang - 1}"${p.trang <= 1 ? ' disabled' : ''}>Trước</button>
      <span class="nut nut--chu nut--rat-nho">${p.trang} / ${p.tong}</span>
      <button type="button" class="nut nut--vien nut--rat-nho" data-trang="${p.trang + 1}"${p.trang >= p.tong ? ' disabled' : ''}>Sau</button></div>` : ''}</div>`;

  /** Ngăn chi tiết bên phải (tạo một lần cho mỗi trang) */
  let ngan = null;
  qt.moChiTiet = (tieuDe, html, nhan = '') => {
    if (!ngan) {
      ngan = document.createElement('dialog');
      ngan.className = 'ngan-keo qt-ct';
      ngan.setAttribute('aria-labelledby', 'qt-ct-td');
      ngan.innerHTML = `<div class="ngan-keo__dau"><div><p class="nhan-tren" data-qt-ct-nhan></p><h2 class="t-4" id="qt-ct-td"></h2></div>
        <button class="nut-bt" type="button" aria-label="Đóng" data-qt-dong>${VN.bt('dong')}</button></div><div class="ngan-keo__than" data-qt-ct-than></div>`;
      document.body.appendChild(ngan);
      ngan.addEventListener('click', (e) => { if (e.target.closest('[data-qt-dong]')) VN.dongHopThoai(ngan); });
    }
    VN.$('#qt-ct-td', ngan).textContent = tieuDe;
    VN.$('[data-qt-ct-nhan]', ngan).textContent = nhan;
    VN.$('[data-qt-ct-than]', ngan).innerHTML = html;
    if (!ngan.open) VN.moHopThoai(ngan);
    return ngan;
  };
  qt.dongChiTiet = () => { if (ngan) VN.dongHopThoai(ngan); };
  qt.thanChiTiet = () => (ngan ? VN.$('[data-qt-ct-than]', ngan) : null);
  qt.dangMoChiTiet = () => !!(ngan && ngan.open);

  /** Thực hiện thao tác, báo kết quả bằng thông báo nhanh */
  qt.lam = (ham, thanhCong) => {
    try { const kq = ham(); if (thanhCong) VN.thongBao({ tieuDe: thanhCong, loai: 'thanh-cong' }); return kq; }
    catch (loi) { VN.thongBao({ tieuDe: 'Không thực hiện được', noiDung: VN.thoat(loi.message), loai: 'loi' }); return null; }
  };

  /* ---------- Khung: người dùng, đăng xuất, số việc trên menu ---------- */
  const veKhung = () => {
    if (!qt.nguoi) return;
    VN.$$('[data-qt-ten]').forEach((el) => { el.textContent = qt.nguoi.hoTen; });
    VN.$$('[data-qt-vai-tro]').forEach((el) => { el.textContent = qt.nguoi.vaiTro; });
    VN.$$('[data-qt-chu-cai]').forEach((el) => { el.textContent = qt.nguoi.hoTen.split(/\s+/).pop().charAt(0).toUpperCase(); });
    VN.donHang.tuHuyQuaHan();
    const don = VN.donHang.tatCa();
    const dem = {
      don: don.filter((d) => d.trangThai === 'Pending' || d.thanhToan.trangThai === 'RefundPending').length,
      'phan-anh': VN.hoTro.tatCa().filter((x) => x.trangThai !== 'Resolved').length,
      lich: VN.lichHen.tatCa().filter((l) => l.trangThai === 'Pending').length,
      'danh-gia': VN.danhGia.tatCa().filter((x) => !x.phanHoi).length,
    };
    VN.$$('[data-qt-dem]').forEach((el) => { const n = dem[el.dataset.qtDem] || 0; el.textContent = n > 99 ? '99+' : n; el.hidden = !n; });
  };
  qt.veKhung = veKhung;
  document.addEventListener('click', async (e) => {
    if (!e.target.closest('[data-qt-dang-xuat]')) return;
    const ok = await VN.xacNhan({ nhan: 'Vinora Admin', tieuDe: 'Đăng xuất khỏi trang quản trị?', chuDongY: 'Đăng xuất' });
    if (!ok) return;
    VN.quanTri.dangXuat(); location.href = VN.url('taiKhoan');
  });
  const batDau = () => {
    veKhung();
    // Màn hình hẹp: menu cuộn ngang -> đưa mục đang mở vào giữa
    const dangMo = VN.$('.qt-ben__ds [aria-current="page"]');
    if (dangMo && matchMedia('(max-width: 900px)').matches) { const nav = dangMo.closest('nav'); nav.scrollLeft = dangMo.offsetLeft - (nav.clientWidth - dangMo.offsetWidth) / 2; }
    ['vinora:don-hang', 'vinora:ho-tro', 'vinora:lich-hen', 'vinora:danh-gia'].forEach((ten) => window.addEventListener(ten, veKhung));
    // Khách thao tác ở thẻ trình duyệt khác (đặt hàng, gửi phản ánh…) -> cập nhật số việc
    window.addEventListener('storage', (e) => { if (/^vinora\./.test(e.key || '')) veKhung(); });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', batDau); else batDau();
})();
