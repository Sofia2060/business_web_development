/* =====================================================================
   VINORA JEWELRY — chung.js (dùng chung cho mọi trang khách hàng)
   ---------------------------------------------------------------------
   1. Tiện ích DOM & định dạng (tiền VNĐ, ngày giờ, bỏ dấu tiếng Việt)
   2. Đường dẫn trang & ảnh sản phẩm
   3. AJAX bằng XMLHttpRequest (tệp tĩnh JSON, XML)
   4. Lưu trữ cục bộ (localStorage): giỏ của khách chưa đăng nhập, yêu thích, đã xem, bảo hành, đánh giá…
   5. Phiên quản trị
   6. Tùy chọn giỏ hàng & tính tiền
   7. Trạng thái đơn hàng – Bảo hành – Lịch hẹn – Đánh giá (còn lưu cục bộ, chờ nối API)
   8. Sản phẩm đã xem
   9. Thành phần giao diện: thông báo, hộp thoại xác nhận, thẻ sản phẩm
   10. Đầu trang: menu, tìm kiếm gợi ý, giỏ hàng mini
   11. Khởi động
   Dữ liệu cửa hàng (sản phẩm, tài khoản, giỏ hàng, đơn hàng) lấy từ API Flask:
   xem api.js (gọi API, đổi dữ liệu) và session.js (VN.taiKhoan, VN.gioHang, VN.donHang).
   ===================================================================== */
(function () {
  'use strict';
  const VN = (window.Vinora = window.Vinora || {});

  /* ================= 1. TIỆN ÍCH DOM & ĐỊNH DẠNG ================= */
  VN.$ = (chon, goc = document) => goc.querySelector(chon);
  VN.$$ = (chon, goc = document) => Array.from(goc.querySelectorAll(chon));
  VN.thoat = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  VN.bt = (ten, lop = '') => `<svg class="bt ${lop}" aria-hidden="true"><use href="#i-${ten}"></use></svg>`;

  /** Định dạng tiền Việt Nam: 25448000 -> "25.448.000 ₫" */
  VN.tien = (n) => (Math.round(Number(n) || 0)).toLocaleString('vi-VN') + ' ₫';
  const hai = (n) => String(n).padStart(2, '0');
  VN.ngay = (d) => { d = new Date(d); return `${hai(d.getDate())}/${hai(d.getMonth() + 1)}/${d.getFullYear()}`; };
  VN.gio = (d) => { d = new Date(d); return `${hai(d.getHours())}:${hai(d.getMinutes())}`; };
  VN.ngayGio = (d) => `${VN.ngay(d)} · ${VN.gio(d)}`;
  VN.ngayIso = (d) => { d = new Date(d); return `${d.getFullYear()}-${hai(d.getMonth() + 1)}-${hai(d.getDate())}`; };
  VN.thu = (d) => ['Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy'][new Date(d).getDay()];
  VN.thoiGianTruoc = (d) => {
    const giay = Math.round((Date.now() - new Date(d).getTime()) / 1000);
    if (giay < 60) return 'vừa xong';
    if (giay < 3600) return Math.floor(giay / 60) + ' phút trước';
    if (giay < 86400) return Math.floor(giay / 3600) + ' giờ trước';
    if (giay < 86400 * 30) return Math.floor(giay / 86400) + ' ngày trước';
    return VN.ngay(d);
  };
  /** Bỏ dấu tiếng Việt để tìm kiếm không phân biệt dấu: "Nhẫn cưới" -> "nhan cuoi" */
  VN.khongDau = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D').toLowerCase();
  VN.thamSo = (ten) => new URLSearchParams(location.search).get(ten);
  VN.chongDoi = (ham, ms = 200) => { let hen; return (...ts) => { clearTimeout(hen); hen = setTimeout(() => ham(...ts), ms); }; };
  VN.ngauNhien = (n) => Array.from({ length: n }, () => Math.floor(Math.random() * 10)).join('');
  VN.chuNgauNhien = (n) => Array.from({ length: n }, () => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[Math.floor(Math.random() * 32)]).join('');
  const yymmdd = (d = new Date()) => String(d.getFullYear()).slice(2) + hai(d.getMonth() + 1) + hai(d.getDate());
  VN.emailHopLe = (e) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(String(e).trim());
  VN.sdtHopLe = (s) => /^(0|\+84)(3|5|7|8|9)\d{8}$/.test(String(s).replace(/[\s.]/g, ''));
  VN.vietHoaKhongDau = (s) => VN.khongDau(s).toUpperCase();
  /** Chuẩn hóa số điện thoại để làm mã khách hàng: bỏ khoảng trắng, dấu chấm; +84 -> 0 */
  VN.chuanSdt = (s) => { let x = String(s || '').replace(/[\s.\-()]/g, ''); if (x.startsWith('+84')) x = '0' + x.slice(3); return x; };
  /** Che bớt số điện thoại / số tài khoản khi hiển thị */
  VN.anSdt = (s) => { const x = VN.chuanSdt(s); return x.length >= 7 ? `${x.slice(0, 3)}****${x.slice(-3)}` : x; };
  VN.anSoTaiKhoan = (s) => { const x = String(s || '').replace(/\s/g, ''); return x.length > 4 ? `•••• ${x.slice(-4)}` : x; };
  /** Đếm ngược dạng 23:59:08 */
  VN.dinhDangDemNguoc = (ms) => { const g = Math.max(0, Math.floor(ms / 1000)); return `${hai(Math.floor(g / 3600))}:${hai(Math.floor(g % 3600 / 60))}:${hai(g % 60)}`; };

  /* ================= 2. ĐƯỜNG DẪN & ẢNH ================= */
  let duongDan = {};
  try { duongDan = JSON.parse(document.getElementById('duong-dan').textContent); } catch (e) { console.error('Thiếu bản đồ đường dẫn', e); }
  VN.duongDan = duongDan;

  /** Dựng URL trang theo tên: VN.url('sanPham', {danhmuc: 1}) -> /san-pham?danhmuc=1 */
  VN.url = (ten, thamSo = {}) => {
    let u = duongDan[ten] || '#';
    const ts = Object.assign({}, thamSo);
    if (u.includes('__MA__')) { u = u.replace('__MA__', encodeURIComponent(ts.ma || '')); delete ts.ma; }
    const q = new URLSearchParams();
    Object.keys(ts).forEach((k) => { if (ts[k] !== undefined && ts[k] !== null && ts[k] !== '') q.set(k, ts[k]); });
    const chuoi = q.toString();
    return chuoi ? u + (u.includes('?') ? '&' : '?') + chuoi : u;
  };
  VN.urlSanPham = (ma) => VN.url('chiTiet', { ma });

  /* Nguồn ảnh mặc định (khớp ../../../mock-data/products.json) – dùng được ngay cả khi trang chưa tải danh sách sản phẩm */
  let nguonAnh = { cdn: 'https://cdn.huythanhjewelry.vn/storage/photos/', cloud: 'https://cloud.huythanhjewelry.vn/storage/photos/' };
  /** Ảnh sản phẩm lưu dạng rút gọn "cdn|shares/..." -> URL đầy đủ */
  VN.anh = (duong) => {
    if (!duong) return VN.anhTam();
    if (/^https?:|^\//.test(duong)) return duong;
    const i = duong.indexOf('|');
    return i > 0 ? (nguonAnh[duong.slice(0, i)] || '') + duong.slice(i + 1) : duong;
  };
  VN.anhTam = () => (duongDan.hinh || '') + 'placeholders/placeholder.svg';
  /** Ảnh chụp người mẫu (jpg) hiển thị kiểu phủ kín; ảnh nền trắng (png) hiển thị trọn vẹn */
  VN.laAnhChup = (duong) => /\.jpe?g($|\?)/i.test(duong || '');

  /* ================= 3. AJAX (XMLHttpRequest) & KHO DỮ LIỆU ================= */
  const boNhoTai = {};
  /**
   * Tải tệp bằng XMLHttpRequest (kỹ thuật AJAX trong bài giảng):
   * open('GET', url, true) -> send() -> chờ readyState 4 & status 200.
   */
  VN.taiTep = (url, kieu = 'json') => {
    if (boNhoTai[url]) return boNhoTai[url];
    const hua = new Promise((xong, loi) => {
      const xhr = new XMLHttpRequest();
      xhr.open('GET', url, true);
      if (kieu === 'json') xhr.overrideMimeType('application/json; charset=utf-8');
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== 4) return;
        if (xhr.status === 200 || (xhr.status === 0 && xhr.responseText)) {
          try {
            if (kieu === 'xml') xong(xhr.responseXML || new DOMParser().parseFromString(xhr.responseText, 'text/xml'));
            else xong(JSON.parse(xhr.responseText));
          } catch (e) { loi(e); }
        } else {
          loi(new Error(`Không tải được ${url} (mã ${xhr.status})`));
        }
      };
      xhr.onerror = () => loi(new Error('Lỗi kết nối khi tải ' + url));
      xhr.send();
    });
    boNhoTai[url] = hua;
    hua.catch(() => { delete boNhoTai[url]; });
    return hua;
  };
  VN.taiJSON = (url) => VN.taiTep(url, 'json');
  VN.taiXML = (url) => VN.taiTep(url, 'xml');

  /* ================= 4. LƯU TRỮ CỤC BỘ ================= */
  const TIEN_TO = 'vinora.';
  const boNhoTam = {};
  VN.kho = {
    doc(khoa, macDinh = null) {
      try { const v = localStorage.getItem(TIEN_TO + khoa); return v === null ? macDinh : JSON.parse(v); }
      catch (e) { return khoa in boNhoTam ? boNhoTam[khoa] : macDinh; }
    },
    ghi(khoa, giaTri) {
      try { localStorage.setItem(TIEN_TO + khoa, JSON.stringify(giaTri)); } catch (e) { boNhoTam[khoa] = giaTri; }
      return giaTri;
    },
    xoa(khoa) { try { localStorage.removeItem(TIEN_TO + khoa); } catch (e) { delete boNhoTam[khoa]; } },
  };
  const phatSuKien = (ten, chiTiet) => window.dispatchEvent(new CustomEvent('vinora:' + ten, { detail: chiTiet }));
  VN.phatSuKien = phatSuKien;

  /* ================= 5. PHIÊN QUẢN TRỊ ================= */
  /**
   * Dấu hiệu "đã đăng nhập quản trị" cho các trang quản trị (còn dùng dữ liệu mô phỏng, chờ nối API – nhóm C8).
   * Việc kiểm tra mật khẩu do máy chủ làm (VN.taiKhoan.dangNhap); hết hạn sau 8 giờ.
   */
  VN.quanTri = {
    datPhien({ email, hoTen }) { VN.kho.ghi('phienQuanTri', { email, hoTen, vaiTro: 'Quản lý cửa hàng', het: Date.now() + 8 * 3600000 }); },
    hienTai() { const p = VN.kho.doc('phienQuanTri', null); return p && p.het > Date.now() ? p : null; },
    xoaPhien() { VN.kho.xoa('phienQuanTri'); },
    dangXuat() { this.xoaPhien(); return VN.api.post('/api/auth/logout').catch(() => {}); },
  };

  VN.kiemTraMatKhau = (mk) => {
    const loi = [];
    if (mk.length < 8) loi.push('ít nhất 8 ký tự');
    if (!/[A-Z]/.test(mk)) loi.push('1 chữ in hoa');
    if (!/[a-z]/.test(mk)) loi.push('1 chữ thường');
    if (!/\d/.test(mk)) loi.push('1 chữ số');
    return loi;
  };

  /* ================= 6. TÙY CHỌN GIỎ HÀNG & TÍNH TIỀN ================= */
  /** Tùy chọn của giỏ hàng (gói quà, lời nhắn thiệp, mã ưu đãi) – dùng chung cho trang giỏ hàng và thanh toán */
  VN.tuyChonGio = {
    doc() { return Object.assign({ goiQua: true, loiNhan: '', maUuDai: '' }, VN.kho.doc('tuyChonGio', {})); },
    ghi(thayDoi) { return VN.kho.ghi('tuyChonGio', Object.assign(this.doc(), thayDoi)); },
    xoa() { VN.kho.xoa('tuyChonGio'); },
  };

  /**
   * Tính tiền đơn hàng – một nơi duy nhất cho giỏ hàng, giỏ mini và thanh toán (NFR5).
   * giam = số tiền giảm của mã ưu đãi do máy chủ tính (VN.uuDai.kiemTra). Phí giao theo quy tắc của máy chủ:
   * miễn phí từ mức mienPhiTu, còn lại phí giao tiêu chuẩn. Máy chủ tính lại khi đặt hàng.
   */
  VN.tinhTien = (dong, ch, { giam = 0 } = {}) => {
    const tamTinh = dong.reduce((t, d) => t + d.donGia * d.soLuong, 0);
    const giamThuc = Math.min(Math.max(0, giam), tamTinh);
    const pt = ch.giaoHang.phuongThuc[0];
    const duMienPhi = tamTinh >= ch.giaoHang.mienPhiTu;
    const phiGiao = !dong.length || duMienPhi ? 0 : pt.phi;
    return { tamTinh, giam: giamThuc, phiGiao, tong: tamTinh - giamThuc + phiGiao, pt, duMienPhi, conThieu: Math.max(0, ch.giaoHang.mienPhiTu - tamTinh) };
  };

  /* ================= 7. ĐƠN HÀNG – THANH TOÁN – BẢO HÀNH – LỊCH HẸN – ĐÁNH GIÁ ================= */
  VN.TRANG_THAI_DON = {
    Pending: { ten: 'Chờ xử lý', lop: 'nhan--cam', bt: 'dong-ho' },
    Confirmed: { ten: 'Đã xác nhận', lop: 'nhan--xanh', bt: 'xac-nhan' },
    Shipping: { ten: 'Đang giao', lop: 'nhan--xanh', bt: 'xe-giao' },
    Delivered: { ten: 'Đã nhận', lop: 'nhan--ngoc', bt: 'xac-nhan' },
    Cancelled: { ten: 'Đã hủy', lop: 'nhan--do', bt: 'huy' },
  };
  VN.TRANG_THAI_TT = {
    Pending: { ten: 'Chờ thanh toán', lop: 'nhan--cam' },
    Success: { ten: 'Đã thanh toán', lop: 'nhan--ngoc' },
    Failed: { ten: 'Thanh toán thất bại', lop: 'nhan--do' },
    RefundPending: { ten: 'Chờ hoàn tiền', lop: 'nhan--cam' },
    Refunded: { ten: 'Đã hoàn tiền', lop: 'nhan--xanh' },
    Expired: { ten: 'Quá hạn thanh toán', lop: 'nhan--do' },
  };
  /** Đơn thanh toán trực tuyến phải trả tiền trong 15 phút, quá hạn máy chủ tự hủy đơn (fn_PaymentTimeoutMinutes) */
  VN.HAN_THANH_TOAN_PHUT = 15;
  VN.TEN_THANH_TOAN = { COD: 'Thanh toán khi nhận hàng', BANK: 'Chuyển khoản VietQR', VNPAY: 'Cổng VNPay', MOMO: 'Ví MoMo' };
  VN.TEN_DICH_VU = { Cleaning: 'Làm sạch', Polishing: 'Đánh bóng & xi mới', Resizing: 'Chỉnh size nhẫn' };
  VN.TRANG_THAI_LICH = {
    Pending: { ten: 'Chờ xác nhận', lop: 'nhan--cam' },
    Confirmed: { ten: 'Đã xác nhận', lop: 'nhan--xanh' },
    Completed: { ten: 'Hoàn tất', lop: 'nhan--ngoc' },
    Cancelled: { ten: 'Đã hủy', lop: 'nhan--do' },
  };

  const ghiLichSu = (doiTuong, noiDung, boi = 'Khách hàng', trangThai) => {
    doiTuong.lichSu = doiTuong.lichSu || [];
    doiTuong.lichSu.push({ luc: new Date().toISOString(), noiDung, boi, trangThai: trangThai || doiTuong.trangThai });
  };

  VN.baoHanh = {
    tatCa() { return VN.kho.doc('baoHanh', []); },
    luuTatCa(ds) { VN.kho.ghi('baoHanh', ds); phatSuKien('bao-hanh', ds); },
    cuaToi() { const u = VN.taiKhoan.hienTai(); return u ? this.tatCa().filter((t) => t.khachHang === u.id).sort((a, b) => new Date(b.ngayKichHoat) - new Date(a.ngayKichHoat)) : []; },
    lay(ma) { ma = String(ma || '').replace(/\s/g, '').toUpperCase(); return this.tatCa().find((t) => t.ma === ma) || null; },
    theoDon(maDon) { return this.tatCa().filter((t) => t.donHang === maDon); },
    taoMa(ds) { let ma; do { ma = 'VNRA' + yymmdd().slice(0, 4) + VN.ngauNhien(8); } while (ds.some((t) => t.ma === ma)); return ma; },
    /** Mỗi sản phẩm (từng đơn vị) nhận một thẻ; gọi lặp không tạo thêm thẻ (FR15) */
    kichHoatChoDon(don, ngayKichHoat) {
      const ds = this.tatCa(); const moi = [];
      don.sanPham.forEach((dong, viTri) => {
        for (let donVi = 1; donVi <= dong.soLuong; donVi++) {
          if (ds.some((t) => t.donHang === don.ma && t.viTri === viTri && t.donVi === donVi)) continue;
          const the = {
            ma: this.taoMa(ds), khachHang: don.khachHang || null, sdtKhach: don.sdtKhach || '', donHang: don.ma, viTri, donVi,
            maSP: dong.ma, tenSP: dong.ten, anh: dong.anh, chatLieu: dong.chatLieu, mau: dong.mau || '', size: dong.size || null,
            khacChu: dong.khacChu || '', laNhan: !!dong.laNhan, ngayKichHoat: ngayKichHoat || new Date().toISOString(),
            hieuLuc: 'Trọn đời', daDung: { Cleaning: 0, Polishing: 0, Resizing: 0, Repair: 0 }, lichSuDichVu: [],
          };
          ds.push(the); moi.push(the);
        }
      });
      this.luuTatCa(ds);
      return moi.length ? moi : ds.filter((t) => t.donHang === don.ma);
    },
    /** Số lượt còn lại theo cấu hình quyền lợi; lượt đang chờ hẹn được giữ chỗ */
    conLai(the, ch, loai) {
      const ql = ch.baoHanh.quyenLoi.find((q) => q.ma === loai);
      if (!ql || ql.luot === null) return Infinity;
      const dangHen = VN.lichHen.tatCa().filter((l) => l.maBaoHanh === the.ma && l.loai === loai && ['Pending', 'Confirmed'].includes(l.trangThai)).length;
      return Math.max(0, ql.luot - (the.daDung[loai] || 0) - dangHen);
    },
    ghiDichVu(maThe, loai, noiDung, maLich) {
      const ds = this.tatCa(); const the = ds.find((t) => t.ma === maThe); if (!the) return;
      the.daDung[loai] = (the.daDung[loai] || 0) + 1;
      the.lichSuDichVu.push({ luc: new Date().toISOString(), loai, noiDung, maLich });
      this.luuTatCa(ds);
    },
  };

  VN.lichHen = {
    tatCa() { return VN.kho.doc('lichHen', []); },
    luuTatCa(ds) { VN.kho.ghi('lichHen', ds); phatSuKien('lich-hen', ds); },
    cuaToi() { const u = VN.taiKhoan.hienTai(); return u ? this.tatCa().filter((l) => l.khachHang === u.id).sort((a, b) => new Date(b.taoLuc) - new Date(a.taoLuc)) : []; },
    tao(duLieu) {
      const u = VN.taiKhoan.hienTai(); const ds = this.tatCa();
      let ma; do { ma = 'LH' + yymmdd() + VN.ngauNhien(3); } while (ds.some((l) => l.ma === ma));
      const lich = Object.assign({ ma, khachHang: u.id, trangThai: 'Pending', taoLuc: new Date().toISOString(), lichSu: [] }, duLieu);
      ghiLichSu(lich, 'Khách hàng gửi yêu cầu đặt lịch.', 'Khách hàng', 'Pending');
      ds.push(lich); this.luuTatCa(ds); return lich;
    },
    capNhat(ma, trangThai, noiDung, boi) {
      const ds = this.tatCa(); const lich = ds.find((l) => l.ma === ma); if (!lich) return null;
      lich.trangThai = trangThai; ghiLichSu(lich, noiDung, boi, trangThai); this.luuTatCa(ds);
      // Chỉ trừ lượt khi dịch vụ hoàn tất; lịch bị hủy không mất lượt (FR17)
      if (trangThai === 'Completed') {
        VN.baoHanh.ghiDichVu(lich.maBaoHanh, lich.loai, `${VN.TEN_DICH_VU[lich.loai]} tại ${lich.tenCuaHang}`, lich.ma);
        if (lich.loai === 'Resizing' && lich.sizeMoi) {   // chỉnh size xong -> cập nhật size mới trên thẻ
          const dsThe = VN.baoHanh.tatCa(); const t = dsThe.find((x) => x.ma === lich.maBaoHanh);
          if (t) { t.size = lich.sizeMoi; VN.baoHanh.luuTatCa(dsThe); }
        }
      }
      return lich;
    },
  };

  VN.danhGia = {
    tatCa() { return VN.kho.doc('danhGia', []); },
    theoDon(maDon) { return this.tatCa().find((d) => d.donHang === maDon) || null; },
    /** Phân loại cảm xúc MÔ PHỎNG theo số sao + từ khóa (FR25 – cần ghi rõ khi trình diễn) */
    phanLoai(soSao, noiDung, chuDe = []) {
      const am = ['trễ', 'chậm', 'nhầm', 'sai', 'xấu', 'thất vọng', 'lỗi', 'hỏng', 'không vừa', 'trầy', 'xỉn', 'giao trễ'];
      const chu = VN.khongDau(noiDung + ' ' + chuDe.join(' '));
      if (soSao >= 4) return 'Positive';
      if (soSao <= 2) return 'Negative';
      return am.some((t) => chu.includes(VN.khongDau(t))) ? 'Negative' : 'Positive';
    },
    /** Cửa hàng phản hồi đánh giá (hiện trong chi tiết đơn của khách) */
    phanHoi(ma, noiDung, boi = 'Vinora Jewelry') {
      const ds = this.tatCa(); const dg = ds.find((x) => x.ma === ma); if (!dg) throw new Error('Không tìm thấy đánh giá.');
      dg.phanHoi = noiDung ? { noiDung, boi, luc: new Date().toISOString() } : null;
      VN.kho.ghi('danhGia', ds); phatSuKien('danh-gia', ds);
      return dg;
    },
    tao({ donHang, soSao, noiDung, chuDe }) {
      const ds = this.tatCa(); const u = VN.taiKhoan.hienTai();
      if (ds.some((d) => d.donHang === donHang)) throw new Error('Đơn hàng này đã được đánh giá.');
      const dg = { ma: 'DG' + Date.now().toString(36).toUpperCase(), donHang, khachHang: u ? u.id : null, soSao, noiDung, chuDe, camXuc: this.phanLoai(soSao, noiDung, chuDe), luc: new Date().toISOString() };
      ds.push(dg); VN.kho.ghi('danhGia', ds);
      return dg;
    },
  };

  /* Phản ánh vấn đề của đơn hàng (sản phẩm lỗi, giao sai, thiếu hàng, hoàn tiền…) */
  VN.TRANG_THAI_HO_TRO = {
    Received: { ten: 'Đã tiếp nhận', lop: 'nhan--cam' },
    Processing: { ten: 'Đang xử lý', lop: 'nhan--xanh' },
    Resolved: { ten: 'Đã giải quyết', lop: 'nhan--ngoc' },
  };
  VN.hoTro = {
    tatCa() { return VN.kho.doc('hoTro', []); },
    luuTatCa(ds) { VN.kho.ghi('hoTro', ds); phatSuKien('ho-tro', ds); },
    theoDon(maDon) { return this.tatCa().filter((x) => x.donHang === maDon).sort((a, b) => new Date(b.luc) - new Date(a.luc)); },
    tao({ donHang, loai, tenLoai, sanPham = [], moTa, anh = [], lienHe }) {
      const ds = this.tatCa(); const u = VN.taiKhoan.hienTai();
      let ma; do { ma = 'HT' + yymmdd() + VN.ngauNhien(3); } while (ds.some((x) => x.ma === ma));
      const pa = { ma, donHang, khachHang: u ? u.id : null, loai, tenLoai, sanPham, moTa, anh, lienHe, trangThai: 'Received', luc: new Date().toISOString(), lichSu: [] };
      ghiLichSu(pa, 'Khách hàng gửi phản ánh.', 'Khách hàng', 'Received');
      ds.push(pa); this.luuTatCa(ds);
      return pa;
    },
    /** Chăm sóc khách hàng cập nhật trạng thái + phản hồi gửi khách (hiện trong đơn hàng của khách) */
    capNhat(ma, trangThai, phanHoi, boi = 'CSKH Vinora') {
      const ds = this.tatCa(); const pa = ds.find((x) => x.ma === ma); if (!pa) throw new Error('Không tìm thấy phản ánh ' + ma);
      const doi = trangThai && trangThai !== pa.trangThai;
      if (!doi && !phanHoi) throw new Error('Chưa có thay đổi nào.');
      if (doi) pa.trangThai = trangThai;
      ghiLichSu(pa, phanHoi || `Cập nhật trạng thái: ${VN.TRANG_THAI_HO_TRO[pa.trangThai].ten}.`, boi, pa.trangThai);
      if (pa.trangThai === 'Resolved' && !pa.xongLuc) pa.xongLuc = new Date().toISOString();
      this.luuTatCa(ds);
      return pa;
    },
  };

  /* ================= 8. SẢN PHẨM ĐÃ XEM ================= */
  VN.daXem = {
    ds() { return VN.kho.doc('daXem', []); },
    ghi(ma) {
      const ds = this.ds().filter((x) => x.ma !== ma);
      ds.unshift({ ma, luc: Date.now() });
      VN.kho.ghi('daXem', ds.slice(0, 40));
    },
    xoa(ma) { VN.kho.ghi('daXem', this.ds().filter((x) => x.ma !== ma)); },
    xoaHet() { VN.kho.ghi('daXem', []); },
    /** Hoàn tác thao tác xóa: gộp lại các mục và giữ thứ tự theo lần xem gần nhất */
    khoiPhuc(dsMuc) {
      const hienCo = this.ds(); const ma = new Set(hienCo.map((x) => x.ma));
      const gop = hienCo.concat([].concat(dsMuc).filter((x) => x && !ma.has(x.ma)));
      VN.kho.ghi('daXem', gop.sort((a, b) => b.luc - a.luc).slice(0, 40));
    },
  };

  /* ================= 8b. SẢN PHẨM YÊU THÍCH ================= */
  /** Danh sách yêu thích lưu trên trình duyệt: [{ ma, luc }] – mới nhất ở đầu, tối đa 60 sản phẩm */
  VN.yeuThich = {
    ds() { return VN.kho.doc('yeuThich', []); },
    luu(ds) { VN.kho.ghi('yeuThich', ds.slice(0, 60)); phatSuKien('yeu-thich', ds); },
    co(ma) { return this.ds().some((x) => x.ma === ma); },
    them(ma) { const ds = this.ds().filter((x) => x.ma !== ma); ds.unshift({ ma, luc: Date.now() }); this.luu(ds); },
    bo(ma) { const ds = this.ds(); const muc = ds.find((x) => x.ma === ma) || null; this.luu(ds.filter((x) => x.ma !== ma)); return muc; },
    /** Thêm nếu chưa có, bỏ nếu đã có; trả về true khi sản phẩm vừa được thêm */
    doi(ma) { if (this.co(ma)) { this.bo(ma); return false; } this.them(ma); return true; },
    xoaHet() { const cu = this.ds(); this.luu([]); return cu; },
    /** Hoàn tác: gộp lại các mục đã bỏ, giữ thứ tự theo thời điểm thêm */
    khoiPhuc(dsMuc) {
      const hienCo = this.ds(); const ma = new Set(hienCo.map((x) => x.ma));
      this.luu(hienCo.concat([].concat(dsMuc).filter((x) => x && !ma.has(x.ma))).sort((a, b) => b.luc - a.luc));
    },
  };

  /* ================= 9. THÀNH PHẦN GIAO DIỆN ================= */
  /** Thông báo nhanh (toast) */
  VN.thongBao = ({ tieuDe, noiDung = '', loai = 'thong-tin', hanhDong = null, thoiGian = 4200 } = {}) => {
    const vung = VN.$('#vung-thong-bao'); if (!vung) return;
    const bt = { 'thanh-cong': 'xac-nhan', loi: 'canh-bao', 'thong-tin': 'thong-tin' }[loai] || 'thong-tin';
    const el = document.createElement('div');
    el.className = 'thong-bao thong-bao--' + loai;
    el.setAttribute('role', loai === 'loi' ? 'alert' : 'status');
    el.innerHTML = `${VN.bt(bt)}<div><span class="thong-bao__tieu-de">${VN.thoat(tieuDe)}</span>${noiDung ? `<p>${noiDung}</p>` : ''}</div>`
      + (hanhDong ? `<button type="button" class="thong-bao__hanh-dong">${VN.thoat(hanhDong.chu)}</button>` : `<button type="button" class="nut-bt" aria-label="Đóng thông báo" style="width:28px;height:28px">${VN.bt('dong', 'bt--nho')}</button>`);
    const an = () => { el.classList.add('dang-an'); setTimeout(() => el.remove(), 320); };
    el.querySelector('button').addEventListener('click', () => { if (hanhDong) hanhDong.khiBam(); an(); });
    vung.appendChild(el);
    if (thoiGian && loai !== 'loi') setTimeout(an, thoiGian);
    return el;
  };

  /** Mở / đóng hộp thoại gốc <dialog>, đóng khi bấm ra ngoài vùng nội dung */
  VN.moHopThoai = (dlg) => {
    if (!dlg) return;
    if (!dlg.dataset.daGan) {
      dlg.dataset.daGan = '1';
      dlg.addEventListener('click', (e) => { if (e.target === dlg) dlg.close('nen'); });
      dlg.addEventListener('close', () => document.documentElement.classList.remove('khoa-cuon'));
    }
    if (typeof dlg.showModal === 'function') { if (!dlg.open) dlg.showModal(); }
    else dlg.setAttribute('open', '');
    document.documentElement.classList.add('khoa-cuon');
  };
  VN.dongHopThoai = (dlg, giaTri) => { if (dlg && dlg.open) dlg.close(giaTri); };

  /** Hộp thoại xác nhận (thay confirm()): trả về Promise<boolean> */
  VN.xacNhan = ({ nhan = '', tieuDe, noiDung = '', chuDongY = 'Đồng ý', chuHuy = 'Quay lại', nguy = false } = {}) => new Promise((xong) => {
    const dlg = VN.$('#hop-xac-nhan');
    if (!dlg) { xong(window.confirm(tieuDe)); return; }
    VN.$('[data-xn="nhan"]', dlg).textContent = nhan;
    VN.$('[data-xn="tieu-de"]', dlg).textContent = tieuDe;
    VN.$('[data-xn="noi-dung"]', dlg).innerHTML = noiDung;
    const dongY = VN.$('[data-xn="nut-dong-y"]', dlg);
    dongY.textContent = chuDongY; dongY.className = 'nut nut--nho ' + (nguy ? 'nut--nguy' : 'nut--chinh');
    VN.$('[data-xn="nut-huy"]', dlg).textContent = chuHuy;
    dlg.returnValue = '';
    const khiDong = () => { dlg.removeEventListener('close', khiDong); xong(dlg.returnValue === 'dong-y'); };
    dlg.addEventListener('close', khiDong);
    VN.moHopThoai(dlg);
  });

  VN.lopMau = (mau) => {
    const k = VN.khongDau(mau);
    if (k.includes('trang')) return k.includes('bac') ? 'cham-mau--bac' : 'cham-mau--trang';
    if (k.includes('hong')) return 'cham-mau--hong';
    if (k.includes('bac')) return 'cham-mau--bac';
    return 'cham-mau--vang';
  };
  const NGAY_MOC_MOI = new Date('2026-06-01');
  VN.laHangMoi = (sp) => sp.ngayTao && new Date(sp.ngayTao) >= NGAY_MOC_MOI;

  /** Nhận diện loại đá từ tên sản phẩm (dữ liệu gốc chỉ có kích thước × số viên): [tên hiển thị, dạng viết trong câu] */
  VN.loaiDa = (ten) => {
    const t = VN.khongDau(ten);
    if (t.includes('kim cuong lab')) return ['Kim cương Lab-grown', 'kim cương lab-grown'];
    if (t.includes('kim cuong')) return ['Kim cương', 'kim cương'];
    if (t.includes('moissanite')) return ['Moissanite', 'đá Moissanite'];
    if (/\be?cz\b/.test(t)) return ['Đá CZ', 'đá CZ'];
    if (t.includes('ngoc trai')) return ['Ngọc trai', 'ngọc trai'];
    if (t.includes('sapphire')) return ['Sapphire tự nhiên', 'đá Sapphire tự nhiên'];
    if (t.includes('ruby')) return ['Ruby tự nhiên', 'đá Ruby tự nhiên'];
    if (t.includes('xa cu') || t.includes('mother of pearl')) return ['Xà cừ', 'xà cừ'];
    if (t.includes('da mau') || t.includes('da tu nhien')) return ['Đá màu', 'đá màu'];
    return ['Đá trang trí', 'đá trang trí'];
  };
  /** Sản phẩm có đính đá: theo thông số đá hoặc theo tên sản phẩm (một số mẫu chưa có thông số viên đá) */
  VN.coDa = (sp) => !!sp.da || /kim cuong|moissanite|\be?cz\b|ngoc trai|\bda\b|sapphire|ruby/.test(VN.khongDau(sp.ten));
  /** Kích thước đá "1.25 mm" -> "1,25 mm" (dấu thập phân kiểu Việt Nam), đã thoát HTML */
  VN.kichThuocDa = (kt) => VN.thoat(String(kt || '').replace(/(\d)\.(\d)/g, '$1,$2'));
  /** Mô tả hàm lượng kim loại quý theo cấu hình: "Hàm lượng vàng 58,5%" / "92,5% bạc nguyên chất" */
  VN.hamLuong = (sp, ch) => {
    const hl = ((ch && ch.hamLuongVang) || {})[sp.chatLieu];
    if (!hl) return '';
    return sp.chatLieu === 'BAC925' ? `${hl} nguyên chất` : `Hàm lượng vàng ${hl}`;
  };
  /** Số kiểu Việt Nam: 1.62 -> "1,62" */
  VN.so = (n, le = 2) => Number(n).toLocaleString('vi-VN', { maximumFractionDigits: le });

  /** Nhãn trên ảnh sản phẩm */
  VN.nhanSanPham = (sp) => {
    const ds = [];
    if (sp.giaCu && sp.giam) ds.push(`<span class="nhan nhan--do nhan--tron">−${sp.giam}%</span>`);
    if (VN.laHangMoi(sp)) ds.push('<span class="nhan">Mới</span>');
    if (sp.chatLieu === '24K') ds.push('<span class="nhan nhan--vang">Vàng 24K</span>');
    return ds.slice(0, 2).join('');
  };

  /** HTML giá: giá bán, giá gốc gạch ngang, hoặc giá công với sản phẩm tính theo giá vàng ngày */
  VN.giaHtml = (sp, lon = false) => {
    if (!sp.coTheMua) {
      return '<span class="the-sp__gia-cong">Giá theo giá vàng ngày · <strong>liên hệ báo giá</strong></span>';
    }
    const lop = 'gia' + (lon ? ' gia--lon' : '') + (sp.giaCu ? ' gia--giam' : '');
    return `<span class="${lop}"><span class="gia__hien-tai">${VN.tien(sp.giaBan)}</span>${sp.giaCu ? `<del aria-label="Giá gốc">${VN.tien(sp.giaCu)}</del>` : ''}</span>`;
  };

  /** Dựng thẻ sản phẩm từ <template id="mau-the-san-pham"> */
  VN.theSanPham = (sp) => {
    const mau = VN.$('#mau-the-san-pham');
    const the = mau.content.firstElementChild.cloneNode(true);
    const lk = VN.$('.the-sp__lien-ket', the);
    lk.href = VN.urlSanPham(sp.ma);
    lk.setAttribute('aria-label', `${sp.ten}, mã ${sp.ma}, ${sp.coTheMua ? VN.tien(sp.giaBan) : 'giá theo giá vàng ngày'}`);
    const anh1 = VN.$('.the-sp__anh-chinh', the); const anh2 = VN.$('.the-sp__anh-phu', the);
    anh1.src = VN.anh(sp.anh[0]); anh1.alt = sp.ten;
    if (VN.laAnhChup(sp.anh[0])) anh1.classList.add('la-anh-chup');
    if (sp.anh[1]) {
      anh2.src = VN.anh(sp.anh[1]);
      if (VN.laAnhChup(sp.anh[1])) anh2.classList.add('la-anh-chup');
      VN.$('.the-sp__anh', the).classList.add('co-anh-phu');
    } else anh2.remove();
    VN.$('.the-sp__nhan', the).innerHTML = VN.nhanSanPham(sp);
    VN.$('.the-sp__bst', the).textContent = sp.bst ? sp.bst.ten : '';
    VN.$('.the-sp__ten', the).textContent = sp.ten;
    VN.$('.the-sp__phu', the).textContent = `${sp.ma} · ${sp.tenChatLieu || sp.chatLieu}`;
    VN.$('.the-sp__gia', the).innerHTML = VN.giaHtml(sp);
    VN.$('.the-sp__mau', the).innerHTML = (sp.mau || []).map((m) => `<span class="cham-mau ${VN.lopMau(m)}" title="${VN.thoat(m)}"></span>`).join('');
    const tim = VN.$('[data-yeu-thich]', the);
    if (tim) { tim.dataset.yeuThich = sp.ma; tim.dataset.ten = sp.ten; datNutTim(tim, VN.yeuThich.co(sp.ma)); }
    return the;
  };
  /** Trạng thái nút trái tim (thẻ sản phẩm, trang chi tiết, danh sách đã xem) */
  const datNutTim = (nut, daThich) => {
    nut.classList.toggle('da-thich', daThich);
    nut.setAttribute('aria-pressed', String(daThich));
    const chu = daThich ? 'Bỏ khỏi yêu thích' : 'Thêm vào yêu thích';
    nut.setAttribute('aria-label', nut.dataset.ten ? `${chu}: ${nut.dataset.ten}` : chu);
    nut.title = chu;
    const nhan = VN.$('[data-chu-tim]', nut); if (nhan) nhan.textContent = daThich ? 'Đã yêu thích' : 'Yêu thích';
  };
  /** Đồng bộ mọi nút trái tim đang có trên trang với danh sách yêu thích */
  VN.capNhatNutTim = (goc = document) => {
    const co = new Set(VN.yeuThich.ds().map((x) => x.ma));
    VN.$$('[data-yeu-thich]', goc).forEach((nut) => { if (nut.dataset.yeuThich) datNutTim(nut, co.has(nut.dataset.yeuThich)); });
  };
  /** Gắn nút mũi tên cho dải trượt ngang (.dai-truot); trả về hàm cập nhật trạng thái nút */
  VN.ganDieuKhienTruot = (dai, khungNut) => {
    if (!dai || !khungNut) return null;
    const nut = VN.$$('[data-cuon]', khungNut);
    const capNhat = () => {
      const khongCuon = dai.scrollWidth <= dai.clientWidth + 4;
      khungNut.hidden = khongCuon;
      nut[0].disabled = dai.scrollLeft <= 4;
      nut[1].disabled = dai.scrollLeft + dai.clientWidth >= dai.scrollWidth - 4;
    };
    nut.forEach((b) => b.addEventListener('click', () => {
      const the = dai.firstElementChild; const buoc = the ? the.getBoundingClientRect().width + 24 : dai.clientWidth;
      dai.scrollBy({ left: Number(b.dataset.cuon) * buoc * 2, behavior: 'smooth' });
    }));
    dai.addEventListener('scroll', VN.chongDoi(capNhat, 60), { passive: true });
    window.addEventListener('resize', VN.chongDoi(capNhat, 120));
    return capNhat;
  };
  VN.theXuong = (n = 8) => Array.from({ length: n }, () => '<div class="the-sp the-sp--xuong" aria-hidden="true"><div class="the-sp__lien-ket"><div class="the-sp__anh"></div><div><div class="xuong-dong"></div><div class="xuong-dong"></div></div></div></div>').join('');
  VN.veLuoi = (khung, dsSp) => {
    const frag = document.createDocumentFragment();
    dsSp.forEach((sp) => frag.appendChild(VN.theSanPham(sp)));
    khung.innerHTML = ''; khung.appendChild(frag);
  };

  /**
   * Xem trước khắc chữ laser: vẽ mặt trong đai nhẫn (SVG) với chữ chạy theo đường cong (textPath).
   * kieu: 'co-dien' | 'hien-dai' | 'viet-tay' ; mau: tên màu vàng của sản phẩm
   */
  VN.veKhacChu = (khung, chu, kieu = 'co-dien', mau = 'Vàng Vàng') => {
    const k = VN.khongDau(mau);
    const bang = k.includes('trang') || k.includes('bac') ? ['#7E838B', '#F4F5F7', '#A8ADB4', '#FDFDFE', '#8F949B']
      : k.includes('hong') ? ['#9A5E50', '#F3D2C4', '#B97C69', '#FBE6DD', '#A86B5C']
        : ['#8A6428', '#F2DCA0', '#B48A43', '#FBF0CF', '#9C7533'];
    const phong = { 'co-dien': "'Cormorant Garamond', serif", 'hien-dai': "'Be Vietnam Pro', sans-serif", 'viet-tay': "'Great Vibes', cursive" }[kieu] || "'Cormorant Garamond', serif";
    const coChu = { 'co-dien': 46, 'hien-dai': 34, 'viet-tay': 54 }[kieu] || 46;
    const gian = kieu === 'hien-dai' ? 6 : kieu === 'co-dien' ? 2 : 0;
    const noiDung = chu ? (kieu === 'hien-dai' ? chu.toUpperCase() : chu) : 'Khắc chữ của bạn';
    const id = 'kc' + Math.random().toString(36).slice(2, 7);
    khung.innerHTML = `
      <svg viewBox="0 0 600 320" role="img" aria-label="Xem trước chữ khắc: ${VN.thoat(chu || 'chưa nhập')}" class="khac-chu-svg">
        <defs>
          <linearGradient id="${id}-kim" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stop-color="${bang[0]}"/><stop offset=".38" stop-color="${bang[1]}"/>
            <stop offset=".6" stop-color="${bang[2]}"/><stop offset=".85" stop-color="${bang[3]}"/><stop offset="1" stop-color="${bang[4]}"/>
          </linearGradient>
          <linearGradient id="${id}-bong" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stop-color="#000" stop-opacity=".28"/><stop offset=".25" stop-color="#000" stop-opacity="0"/>
            <stop offset=".75" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#fff" stop-opacity=".35"/>
          </linearGradient>
          <path id="${id}-duong" d="M 70 214 Q 300 118 530 214"/>
        </defs>
        <ellipse cx="300" cy="286" rx="250" ry="16" fill="#1A1714" opacity=".08"/>
        <path d="M 40 176 Q 300 62 560 176 L 560 252 Q 300 138 40 252 Z" fill="url(#${id}-kim)"/>
        <path d="M 40 176 Q 300 62 560 176 L 560 252 Q 300 138 40 252 Z" fill="url(#${id}-bong)"/>
        <path d="M 40 176 Q 300 62 560 176" fill="none" stroke="#fff" stroke-opacity=".55" stroke-width="1.5"/>
        <path d="M 40 252 Q 300 138 560 252" fill="none" stroke="#000" stroke-opacity=".18" stroke-width="1.5"/>
        <text font-family="${phong}" font-size="${coChu}" letter-spacing="${gian}" text-anchor="middle" fill="#fff" fill-opacity=".55" dy="1.2">
          <textPath href="#${id}-duong" startOffset="50%">${VN.thoat(noiDung)}</textPath></text>
        <text font-family="${phong}" font-size="${coChu}" letter-spacing="${gian}" text-anchor="middle" fill="#3B2A12" fill-opacity="${chu ? '.78' : '.32'}">
          <textPath href="#${id}-duong" startOffset="50%">${VN.thoat(noiDung)}</textPath></text>
      </svg>`;
  };

  /** Hiệu ứng xuất hiện khi cuộn tới (IntersectionObserver) */
  VN.hienDan = (goc = document) => {
    const ds = VN.$$('.hien-dan:not(.da-hien)', goc);
    if (!('IntersectionObserver' in window)) { ds.forEach((el) => el.classList.add('da-hien')); return; }
    const io = new IntersectionObserver((muc) => muc.forEach((m) => { if (m.isIntersecting) { m.target.classList.add('da-hien'); io.unobserve(m.target); } }), { rootMargin: '0px 0px -8% 0px' });
    ds.forEach((el) => io.observe(el));
  };

  /** Hiển thị lỗi cho một trường biểu mẫu (NFR3: nhãn rõ, thông báo lỗi kèm cách sửa) */
  VN.baoLoiTruong = (input, thongDiep) => {
    const truong = input.closest('.truong'); if (!truong) return;
    let loi = VN.$('.loi-truong', truong);
    if (!loi) { loi = document.createElement('p'); loi.className = 'loi-truong'; loi.id = (input.id || 'truong') + '-loi'; truong.appendChild(loi); }
    truong.classList.toggle('co-loi', !!thongDiep);
    loi.textContent = thongDiep || '';
    input.setAttribute('aria-invalid', thongDiep ? 'true' : 'false');
    if (thongDiep) input.setAttribute('aria-describedby', loi.id); else input.removeAttribute('aria-describedby');
  };

  /** Đổ danh sách 34 tỉnh, thành (2 nhóm optgroup) vào thẻ <select> */
  VN.dienChonTinh = async (select, giaTri = '') => {
    const d = await VN.duLieu.tinhThanh();
    const nhom = (nhan, ds) => `<optgroup label="${nhan}">${ds.map((t) => `<option value="${VN.thoat(t)}"${t === giaTri ? ' selected' : ''}>${VN.thoat(t)}</option>`).join('')}</optgroup>`;
    select.innerHTML = '<option value="">Chọn tỉnh / thành phố</option>' + nhom('Thành phố trực thuộc trung ương', d.thanhPho) + nhom('Tỉnh', d.tinh);
  };
  /** Đổ size nhẫn 6 – 24 (theo cấu hình) vào thẻ <select> */
  VN.dienChonSize = async (select, giaTri = null, chuTrong = 'Chưa chọn size') => {
    const ch = await VN.duLieu.cauHinh();
    let html = chuTrong ? `<option value="">${chuTrong}</option>` : '';
    for (let k = ch.sizeNhan.nhoNhat; k <= ch.sizeNhan.lonNhat; k++) html += `<option value="${k}"${Number(giaTri) === k ? ' selected' : ''}>Size ${k}</option>`;
    select.innerHTML = html;
  };
  /** Địa chỉ một dòng: "669 Quốc lộ 1, Phường Linh Xuân, Thành phố Hồ Chí Minh" */
  VN.diaChiDay = (d) => [d.diaChi, d.phuongXa, d.tinh].filter(Boolean).join(', ');

  /* ================= 10. ĐẦU TRANG ================= */
  const capNhatSoGio = (nhay) => {
    const n = VN.gioHang.tongSoLuong();
    VN.$$('[data-so-gio]').forEach((el) => {
      el.textContent = n > 99 ? '99+' : n; el.hidden = n === 0;
      if (nhay) { el.classList.remove('nhay'); void el.offsetWidth; el.classList.add('nhay'); }
    });
    VN.$$('[data-mo-gio]').forEach((b) => b.setAttribute('aria-label', n ? `Giỏ hàng, ${n} sản phẩm` : 'Giỏ hàng trống'));
  };

  const capNhatSoYeuThich = () => {
    const n = VN.yeuThich.ds().length;
    VN.$$('[data-so-yeu-thich]').forEach((el) => { el.textContent = n > 99 ? '99+' : n; el.hidden = n === 0; });
    VN.$$('[data-nut-yeu-thich]').forEach((el) => el.setAttribute('aria-label', n ? `Sản phẩm yêu thích, ${n} sản phẩm` : 'Sản phẩm yêu thích'));
  };

  const capNhatTaiKhoanDauTrang = () => {
    const u = VN.taiKhoan.hienTai();
    VN.$$('[data-ten-tai-khoan]').forEach((el) => { el.textContent = u ? VN.taiKhoan.tenGoi(u) : ''; });
    VN.$$('[data-nut-tai-khoan]').forEach((el) => el.setAttribute('aria-label', u ? `Tài khoản của ${u.hoTen}` : 'Đăng nhập hoặc đăng ký'));
    VN.$$('[data-nut-tai-khoan-di-dong]').forEach((el) => { el.textContent = u ? `Tài khoản: ${u.hoTen}` : 'Đăng nhập / Đăng ký'; });
  };

  /** Giỏ hàng mini trong ngăn kéo */
  VN.veGioMini = async () => {
    const than = VN.$('[data-gio-mini-than]'); if (!than) return;
    const [dong, { ch }] = await Promise.all([VN.gioHang.chiTiet(), VN.duLieu.coBan()]);
    const dem = dong.reduce((t, d) => t + d.soLuong, 0);
    VN.$('[data-gio-mini-dem]').textContent = dem ? `(${dem})` : '';
    VN.$('[data-gio-mini-chan]').hidden = !dong.length;
    if (!dong.length) {
      than.innerHTML = `<div class="trong-rong"><div class="trong-rong__bieu-tuong">${VN.bt('tui')}</div><p>Giỏ hàng của bạn đang trống.</p><a class="nut nut--chinh nut--nho" href="${VN.url('sanPham')}">Khám phá trang sức</a></div>`;
      return;
    }
    than.innerHTML = dong.map((d) => `
      <div class="gio-mini__dong">
        <a class="gio-mini__anh" href="${VN.urlSanPham(d.ma)}"><img src="${VN.anh(d.sp.anh[0])}" alt="" loading="lazy"></a>
        <div>
          <a class="gio-mini__ten" href="${VN.urlSanPham(d.ma)}">${VN.thoat(d.sp.ten)}</a>
          <p class="gio-mini__phu">${[d.ma, d.mau, d.size ? 'Size ' + d.size : '', d.khacChu ? `Khắc “${VN.thoat(d.khacChu)}”` : ''].filter(Boolean).join(' · ')}</p>
          <div class="gio-mini__hang"><span class="so-deu">${d.soLuong} × ${VN.tien(d.donGia)}</span><button type="button" class="gio-mini__xoa" data-xoa-mini="${VN.thoat(d.khoa)}">Xóa</button></div>
        </div>
      </div>`).join('');
    const tien = VN.tinhTien(dong, ch);
    VN.$('[data-gio-mini-tong]').textContent = VN.tien(tien.tamTinh);
    const pt = Math.min(100, Math.round(tien.tamTinh * 100 / ch.giaoHang.mienPhiTu));
    VN.$('[data-gio-mini-mien-phi]').innerHTML = tien.duMienPhi
      ? `<span>${VN.bt('xe-giao', 'bt--nho')} Đơn hàng được <strong>miễn phí giao hàng có bảo hiểm</strong>.</span><div class="thanh-tien-do thanh-tien-do--ngoc"><span style="width:100%"></span></div>`
      : `<span>Mua thêm <strong>${VN.tien(tien.conThieu)}</strong> để được miễn phí giao hàng.</span><div class="thanh-tien-do"><span style="width:${pt}%"></span></div>`;
  };
  VN.moGioMini = () => { VN.veGioMini(); VN.moHopThoai(VN.$('#gio-mini')); };

  const khoiTaoMenu = () => {
    const dauTrang = VN.$('#dau-trang'); if (!dauTrang) return;
    // Bóng đổ khi cuộn
    const khiCuon = () => dauTrang.classList.toggle('da-cuon', window.scrollY > 40);
    window.addEventListener('scroll', khiCuon, { passive: true }); khiCuon();

    // Menu nhiều cấp: rê chuột (có độ trễ nhỏ) hoặc dùng bàn phím
    VN.$$('.co-menu-con', dauTrang).forEach((muc) => {
      const lk = VN.$('.menu-chinh__lien-ket', muc); let hen;
      const mo = () => { clearTimeout(hen); VN.$$('.co-menu-con.dang-mo', dauTrang).forEach((m) => { if (m !== muc) { m.classList.remove('dang-mo'); VN.$('.menu-chinh__lien-ket', m).setAttribute('aria-expanded', 'false'); } }); muc.classList.add('dang-mo'); lk.setAttribute('aria-expanded', 'true'); napAnhMenu(); };
      const dong = (tre = 140) => { clearTimeout(hen); hen = setTimeout(() => { muc.classList.remove('dang-mo'); lk.setAttribute('aria-expanded', 'false'); }, tre); };
      muc.addEventListener('mouseenter', () => { hen = setTimeout(mo, 90); });
      muc.addEventListener('mouseleave', () => dong());
      muc.addEventListener('focusin', mo);
      muc.addEventListener('focusout', (e) => { if (!muc.contains(e.relatedTarget)) dong(0); });
      muc.addEventListener('keydown', (e) => { if (e.key === 'Escape') { dong(0); lk.focus(); } });
    });
    // Menu "Trang sức": rê vào Nhẫn / Quà tặng thì hiện bảng con tương ứng, mục khác giữ bảng mặc định
    VN.$$('[data-ds-loai]', dauTrang).forEach((ds) => {
      const khung = ds.parentElement; let henDoi;
      const dsLoai = VN.$$('.menu-con__loai', ds);
      const chon = (ten) => {
        clearTimeout(henDoi);
        VN.$$('[data-bang-noi-dung]', khung).forEach((b) => b.classList.toggle('dang-chon', b.dataset.bangNoiDung === ten));
        dsLoai.forEach((a) => {
          const coBang = a.dataset.bang !== 'mac-dinh';
          a.classList.toggle('dang-chon', coBang && a.dataset.bang === ten);
          if (coBang) a.setAttribute('aria-expanded', String(a.dataset.bang === ten));
        });
        khung.dataset.bangHienTai = ten;
      };
      dsLoai.forEach((a) => {
        // Đang mở bảng con mà lướt chéo qua mục khác thì chờ một nhịp, tránh bảng nhảy liên tục
        a.addEventListener('mouseenter', () => {
          clearTimeout(henDoi);
          if ((khung.dataset.bangHienTai || 'mac-dinh') === 'mac-dinh') chon(a.dataset.bang);
          else henDoi = setTimeout(() => chon(a.dataset.bang), 160);
        });
        a.addEventListener('focus', () => chon(a.dataset.bang));
      });
      VN.$$('[data-bang-noi-dung]', khung).forEach((b) => b.addEventListener('mouseenter', () => clearTimeout(henDoi)));
      const muc = khung.closest('.co-menu-con');
      if (muc) muc.addEventListener('mouseleave', () => setTimeout(() => { if (!muc.classList.contains('dang-mo')) chon('mac-dinh'); }, 300));
      chon('mac-dinh');
    });

    let daNapAnh = false;
    const napAnhMenu = () => {
      if (daNapAnh) return; daNapAnh = true;
      VN.duLieu.sanPham().then(({ theoMa }) => VN.$$('[data-anh-ma]').forEach((img) => {
        const sp = theoMa[img.dataset.anhMa]; if (sp) { img.src = VN.anh(sp.anh[0]); img.alt = sp.ten; }
      })).catch(() => {});
    };

    // Ngăn kéo menu & giỏ hàng
    VN.$$('[data-mo-menu]').forEach((b) => b.addEventListener('click', () => VN.moHopThoai(VN.$('#menu-di-dong'))));
    VN.$$('[data-mo-gio]').forEach((b) => b.addEventListener('click', () => { dongXemNhanh(); VN.moGioMini(); }));
    VN.$$('[data-dong-ngan-keo]').forEach((b) => b.addEventListener('click', () => VN.dongHopThoai(b.closest('dialog'))));
    const gioMini = VN.$('#gio-mini');
    if (gioMini) gioMini.addEventListener('click', (e) => {
      const nut = e.target.closest('[data-xoa-mini]');
      if (nut) VN.gioHang.xoa(nut.dataset.xoaMini).then((da) => { VN.veGioMini(); if (da) VN.thongBao({ tieuDe: 'Đã xóa khỏi giỏ hàng', hanhDong: { chu: 'Hoàn tác', khiBam: () => VN.gioHang.khoiPhuc(da).then(() => VN.veGioMini()) } }); }).catch((loi) => VN.thongBao({ tieuDe: 'Chưa xóa được', noiDung: VN.thoat(loi.message), loai: 'loi' }));
    });

    // Thanh thông báo xoay vòng
    const chuXoay = VN.$$('[data-chu-xoay] span');
    if (chuXoay.length > 1 && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
      let i = 0; setInterval(() => { chuXoay[i].classList.remove('dang-hien'); i = (i + 1) % chuXoay.length; chuXoay[i].classList.add('dang-hien'); }, 5000);
    }
    khoiTaoTimKiem(dauTrang);
  };

  /* ---------- Hộp xem nhanh khi rê chuột vào biểu tượng đầu trang (máy tính) ---------- */
  const dongMuc = (sp, phu, them = '') => `
    <a class="xn__dong" href="${VN.urlSanPham(sp.ma)}">
      <span class="xn__anh"><img src="${VN.anh(sp.anh[0])}" alt="" width="56" height="56" loading="lazy"></span>
      <span class="xn__chu"><strong>${VN.thoat(sp.ten)}</strong><small>${phu}</small></span>
      ${them}
    </a>`;
  const giaNgan = (sp) => (sp.coTheMua ? VN.tien(sp.giaBan) : 'Liên hệ báo giá');
  const hopRong = (bt, chu, nut) => `<div class="xn__rong">${VN.bt(bt)}<p>${chu}</p>${nut || ''}</div>`;

  const XEM_NHANH = {
    async 'da-xem'() {
      const ds = VN.daXem.ds();
      if (!ds.length) return hopRong('dong-ho', 'Bạn chưa xem sản phẩm nào.', `<a class="nut nut--vien nut--nho" href="${VN.url('sanPham')}">Khám phá trang sức</a>`);
      const { theoMa } = await VN.duLieu.sanPham();
      const muc = ds.map((x) => [x, theoMa[x.ma]]).filter((x) => x[1]).slice(0, 5);
      return `<div class="xn__dau"><strong>Đã xem gần đây</strong><a href="${VN.url('daXem')}">Xem tất cả (${ds.length})</a></div>
        <div class="xn__ds">${muc.map(([x, sp]) => dongMuc(sp, `${giaNgan(sp)} · ${VN.thoiGianTruoc(x.luc)}`)).join('')}</div>`;
    },
    async 'yeu-thich'() {
      const ds = VN.yeuThich.ds();
      if (!ds.length) return hopRong('yeu-thich', 'Bấm biểu tượng trái tim trên sản phẩm để lưu những mẫu bạn thích.', `<a class="nut nut--vien nut--nho" href="${VN.url('sanPham')}">Khám phá trang sức</a>`);
      const { theoMa } = await VN.duLieu.sanPham();
      const muc = ds.map((x) => theoMa[x.ma]).filter(Boolean).slice(0, 5);
      return `<div class="xn__dau"><strong>Sản phẩm yêu thích</strong><a href="${VN.url('yeuThich')}">Xem tất cả (${ds.length})</a></div>
        <div class="xn__ds">${muc.map((sp) => dongMuc(sp, `${VN.thoat(sp.ma)} · ${giaNgan(sp)}`)).join('')}</div>`;
    },
    async 'tai-khoan'() {
      const u = VN.taiKhoan.hienTai();
      if (!u) {
        return `<div class="xn__chao"><strong>Chào bạn!</strong><p>Đăng nhập để lưu địa chỉ, xem lại đơn hàng và thẻ bảo hành ở mọi thiết bị.</p></div>
          <div class="xn__nut-doi"><a class="nut nut--chinh nut--nho" href="${VN.url('taiKhoan')}">Đăng nhập</a><a class="nut nut--vien nut--nho" href="${VN.url('taiKhoan', { dangky: 1 })}">Tạo tài khoản</a></div>
          <ul class="xn__menu">
            <li><a href="${VN.url('donHang')}">${VN.bt('hop-hang')}<span>Tra cứu đơn hàng</span></a></li>
            <li><a href="${VN.url('congBaoHanh', { tab: 'tra-cuu' })}">${VN.bt('khien')}<span>Tra cứu thẻ bảo hành</span></a></li>
            <li><a href="${VN.url('yeuThich')}">${VN.bt('yeu-thich')}<span>Sản phẩm yêu thích</span></a></li>
          </ul>`;
      }
      const dem = (n) => (n ? `<span class="menu-tk__dem">${n}</span>` : '');
      const donMo = VN.donHang.cuaToi().filter((d) => ['Pending', 'Confirmed', 'Shipping'].includes(d.trangThai)).length;
      const lichMo = VN.lichHen.cuaToi().filter((l) => ['Pending', 'Confirmed'].includes(l.trangThai)).length;
      return `<div class="xn__nguoi"><span class="menu-tk__chu-cai" aria-hidden="true">${VN.thoat(VN.taiKhoan.tenGoi(u).charAt(0).toUpperCase())}</span>
          <span><strong>${VN.thoat(u.hoTen)}</strong><small>${VN.thoat(u.email)}</small></span></div>
        <ul class="xn__menu">
          <li><a href="${VN.url('taiKhoan')}">${VN.bt('tai-khoan')}<span>Hồ sơ &amp; địa chỉ</span></a></li>
          <li><a href="${VN.url('donHang')}">${VN.bt('hop-hang')}<span>Đơn hàng của tôi</span>${dem(donMo)}</a></li>
          <li><a href="${VN.url('congBaoHanh')}">${VN.bt('khien')}<span>Thẻ bảo hành điện tử</span>${dem(VN.baoHanh.cuaToi().length)}</a></li>
          <li><a href="${VN.url('congBaoHanh', { tab: 'lich-hen' })}">${VN.bt('lich')}<span>Lịch hẹn hậu mãi</span>${dem(lichMo)}</a></li>
          <li><a href="${VN.url('yeuThich')}">${VN.bt('yeu-thich')}<span>Sản phẩm yêu thích</span>${dem(VN.yeuThich.ds().length)}</a></li>
          <li><a href="${VN.url('daXem')}">${VN.bt('dong-ho')}<span>Sản phẩm đã xem</span></a></li>
          <li><button type="button" data-dang-xuat>${VN.bt('dang-xuat')}<span>Đăng xuất</span></button></li>
        </ul>`;
    },
    async gio() {
      const [dong, { ch }] = await Promise.all([VN.gioHang.chiTiet(), VN.duLieu.coBan()]);
      if (!dong.length) return hopRong('tui', 'Giỏ hàng của bạn đang trống.', `<a class="nut nut--vien nut--nho" href="${VN.url('sanPham')}">Khám phá trang sức</a>`);
      const dem = dong.reduce((t, d) => t + d.soLuong, 0);
      const tien = VN.tinhTien(dong, ch);
      const conLai = dong.length - 4;
      return `<div class="xn__dau"><strong>Giỏ hàng (${dem})</strong><a href="${VN.url('gioHang')}">Chỉnh sửa</a></div>
        <div class="xn__ds">${dong.slice(0, 4).map((d) => dongMuc(d.sp,
          [d.mau, d.size ? 'Size ' + d.size : '', d.khacChu ? `Khắc “${VN.thoat(d.khacChu)}”` : ''].filter(Boolean).join(' · ') || VN.thoat(d.ma),
          `<span class="xn__gia so-deu">${d.soLuong} × ${VN.tien(d.donGia)}</span>`)).join('')}</div>
        ${conLai > 0 ? `<p class="xn__them">và ${conLai} sản phẩm khác trong giỏ</p>` : ''}
        <div class="xn__tong"><span>Tạm tính</span><strong class="so-deu">${VN.tien(tien.tamTinh)}</strong></div>
        <div class="xn__nut-doi"><a class="nut nut--vien nut--nho" href="${VN.url('gioHang')}">Xem giỏ hàng</a><a class="nut nut--chinh nut--nho" href="${VN.url('thanhToan')}">Thanh toán</a></div>`;
    },
  };
  let dongXemNhanh = () => {};
  const khoiTaoXemNhanh = () => {
    const dsHop = VN.$$('[data-xem-nhanh]'); if (!dsHop.length) return;
    const mayTinh = matchMedia('(hover: hover) and (pointer: fine) and (min-width: 1025px)');
    const dong = (khung) => { khung.classList.remove('dang-mo'); };
    dongXemNhanh = () => dsHop.forEach(dong);
    dsHop.forEach((khung) => {
      const hop = VN.$('[data-xem-nhanh-hop]', khung); let hen; let luot = 0;
      const mo = async () => {
        clearTimeout(hen);
        if (!mayTinh.matches) return;
        dsHop.forEach((k) => { if (k !== khung) dong(k); });
        const lan = ++luot;
        try {
          const html = await XEM_NHANH[khung.dataset.xemNhanh]();
          if (lan !== luot) return;                 // đã có lần mở mới hơn
          hop.innerHTML = html;
        } catch (e) { hop.innerHTML = hopRong('canh-bao', 'Chưa tải được dữ liệu, vui lòng thử lại.'); }
        khung.classList.add('dang-mo');
      };
      khung.addEventListener('mouseenter', () => { clearTimeout(hen); hen = setTimeout(mo, 120); });
      khung.addEventListener('mouseleave', () => { clearTimeout(hen); hen = setTimeout(() => dong(khung), 180); });
      khung.addEventListener('focusin', (e) => { if (!hop.contains(e.target)) mo(); });
      khung.addEventListener('focusout', (e) => { if (!khung.contains(e.relatedTarget)) dong(khung); });
      khung.addEventListener('keydown', (e) => { if (e.key === 'Escape') { dong(khung); VN.$('.nut-bt', khung).focus(); } });
    });
    // Dữ liệu đổi (thêm giỏ, bỏ yêu thích, đăng nhập…) khi hộp đang mở thì dựng lại
    ['gio', 'yeu-thich', 'tai-khoan', 'don-hang'].forEach((ten) => window.addEventListener('vinora:' + ten, () => {
      dsHop.filter((k) => k.classList.contains('dang-mo')).forEach(async (k) => { VN.$('[data-xem-nhanh-hop]', k).innerHTML = await XEM_NHANH[k.dataset.xemNhanh](); });
    }));
  };

  /** Nút trái tim ở mọi nơi (ủy quyền sự kiện): thêm / bỏ yêu thích, có hoàn tác */
  const khoiTaoYeuThich = () => {
    document.addEventListener('click', (e) => {
      const nut = e.target.closest('[data-yeu-thich]');
      if (!nut || !nut.dataset.yeuThich) return;
      e.preventDefault(); e.stopPropagation();
      const ma = nut.dataset.yeuThich;
      const muc = VN.yeuThich.co(ma) ? VN.yeuThich.ds().find((x) => x.ma === ma) : null;
      const vuaThem = VN.yeuThich.doi(ma);
      nut.classList.remove('vua-bam'); void nut.offsetWidth; nut.classList.add('vua-bam');
      VN.thongBao(vuaThem
        ? { tieuDe: 'Đã thêm vào yêu thích', noiDung: `<a href="${VN.url('yeuThich')}">Xem danh sách yêu thích</a>`, loai: 'thanh-cong' }
        : { tieuDe: 'Đã bỏ khỏi yêu thích', hanhDong: { chu: 'Hoàn tác', khiBam: () => VN.yeuThich.khoiPhuc(muc) } });
    });
    window.addEventListener('vinora:yeu-thich', () => { VN.capNhatNutTim(); capNhatSoYeuThich(); });
  };

  /** Ô tìm kiếm có gợi ý tức thì, không phân biệt dấu, hỗ trợ phím mũi tên */
  const khoiTaoTimKiem = (dauTrang) => {
    const form = VN.$('#o-tim'); const o = VN.$('#o-tim-nhap'); const hop = VN.$('#goi-y-tim');
    if (!form || !o || !hop) return;
    const q0 = VN.thamSo('q'); if (q0) o.value = q0;
    VN.$$('[data-mo-tim]').forEach((b) => b.addEventListener('click', () => {
      const mo = dauTrang.classList.toggle('tim-mo');
      b.setAttribute('aria-expanded', mo ? 'true' : 'false');
      if (mo) setTimeout(() => o.focus(), 30);
    }));
    let viTri = -1;
    const dong = () => { hop.hidden = true; o.setAttribute('aria-expanded', 'false'); viTri = -1; };
    const danhDau = (chu, tuKhoa) => {
      const goc = VN.thoat(chu); if (!tuKhoa) return goc;
      const kd = VN.khongDau(chu); const i = kd.indexOf(tuKhoa);
      if (i < 0) return goc;
      return VN.thoat(chu.slice(0, i)) + '<mark>' + VN.thoat(chu.slice(i, i + tuKhoa.length)) + '</mark>' + VN.thoat(chu.slice(i + tuKhoa.length));
    };
    const goiY = VN.chongDoi(async () => {
      const chu = o.value.trim();
      if (chu.length < 2) { dong(); return; }
      const { sp, dm, bst } = await VN.duLieu.coBan();
      const kq = VN.timSanPham(sp.ds, chu);
      const tk = VN.khongDau(chu);
      const dmKhop = dm.ds.filter((d) => VN.khongDau(d.ten).includes(tk)).slice(0, 3);
      const bstKhop = bst.ds.filter((b) => VN.khongDau(b.ten).includes(tk)).slice(0, 3);
      let html = '';
      if (dmKhop.length || bstKhop.length) {
        html += `<p class="nhan-tren goi-y-tim__nhom">Danh mục & bộ sưu tập</p><div class="goi-y-tim__chip">`
          + dmKhop.map((d) => `<a class="chip chip--nho" href="${VN.url('sanPham', { danhmuc: d.id })}">${VN.thoat(d.ten)}</a>`).join('')
          + bstKhop.map((b) => `<a class="chip chip--nho" href="${VN.url('sanPham', { bst: b.id })}">${VN.thoat(b.ten)}</a>`).join('') + '</div>';
      }
      if (kq.length) {
        html += `<p class="nhan-tren goi-y-tim__nhom">Sản phẩm</p>` + kq.slice(0, 6).map((s) => `
          <a class="goi-y-tim__sp" role="option" href="${VN.urlSanPham(s.ma)}">
            <img src="${VN.anh(s.anh[0])}" alt="" loading="lazy">
            <span>${danhDau(s.ten, tk)}<small>${danhDau(s.ma, tk)} · ${VN.thoat(s.bst.ten)}</small></span>
            ${s.coTheMua ? `<span class="gia">${VN.tien(s.giaBan)}</span>` : '<span class="chu-rat-nho chu-phu">Báo giá</span>'}
          </a>`).join('');
        html += `<a class="goi-y-tim__tat-ca" role="option" href="${VN.url('sanPham', { q: chu })}">Xem tất cả ${kq.length} kết quả ${VN.bt('mui-ten', 'bt--nho')}</a>`;
      } else if (!html) {
        html = `<p class="goi-y-tim__rong">Không tìm thấy sản phẩm cho “${VN.thoat(chu)}”. Thử từ khóa khác như “nhẫn cưới”, “bông tai”, “14K”.</p>`;
      }
      hop.innerHTML = html; hop.hidden = false; o.setAttribute('aria-expanded', 'true'); viTri = -1;
    }, 140);
    o.addEventListener('input', goiY);
    o.addEventListener('focus', () => { if (o.value.trim().length >= 2) goiY(); });
    o.addEventListener('keydown', (e) => {
      const muc = VN.$$('.goi-y-tim__sp, .goi-y-tim__tat-ca', hop);
      if (e.key === 'Escape') { dong(); return; }
      if (hop.hidden || !muc.length || !['ArrowDown', 'ArrowUp', 'Enter'].includes(e.key)) return;
      if (e.key === 'Enter') { if (viTri >= 0) { e.preventDefault(); location.href = muc[viTri].href; } return; }
      e.preventDefault();
      viTri = (viTri + (e.key === 'ArrowDown' ? 1 : -1) + muc.length) % muc.length;
      muc.forEach((m, i) => m.classList.toggle('dang-chon', i === viTri));
      muc[viTri].scrollIntoView({ block: 'nearest' });
    });
    document.addEventListener('click', (e) => { if (!form.contains(e.target)) dong(); });
    form.addEventListener('submit', (e) => { if (!o.value.trim()) { e.preventDefault(); o.focus(); } });
  };

  /** Tìm sản phẩm: mọi từ khóa (không dấu) phải xuất hiện; ưu tiên khớp mã và tên */
  VN.timSanPham = (ds, chu) => {
    const tu = VN.khongDau(chu).split(/\s+/).filter(Boolean);
    if (!tu.length) return ds.slice();
    const diem = (s) => {
      const ten = VN.khongDau(s.ten); const ma = s.ma.toLowerCase(); let d = 0;
      tu.forEach((t) => { if (ma.startsWith(t)) d += 6; else if (ma.includes(t)) d += 3; if (ten.includes(t)) d += 2; });
      return d;
    };
    return ds.filter((s) => tu.every((t) => s.tuKhoa.includes(t))).map((s) => [diem(s), s]).sort((a, b) => b[0] - a[0]).map((x) => x[1]);
  };

  const khoiTaoNhanTin = () => {
    const form = VN.$('#form-nhan-tin'); if (!form) return;
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const o = form.email; const loi = VN.$('[data-loi-nhan-tin]', form);
      if (!VN.emailHopLe(o.value)) { loi.textContent = 'Email chưa hợp lệ, ví dụ: ten@gmail.com'; o.focus(); return; }
      loi.textContent = ''; const ds = VN.kho.doc('nhanTin', []);
      if (!ds.includes(o.value.trim().toLowerCase())) ds.push(o.value.trim().toLowerCase());
      VN.kho.ghi('nhanTin', ds); form.reset();
      VN.thongBao({ tieuDe: 'Đăng ký nhận tin thành công', noiDung: 'Bạn sẽ là người đầu tiên biết về bộ sưu tập mới.', loai: 'thanh-cong' });
    });
  };

  /** Menu khu vực tài khoản (thanhphan/menutaikhoan.html): tên, số đơn đang xử lý, đăng xuất */
  const khoiTaoMenuTaiKhoan = () => {
    const menu = VN.$('.menu-tk'); if (!menu) return;
    const ve = () => {
      const u = VN.taiKhoan.hienTai();
      VN.$$('[data-tk-ten]', menu).forEach((el) => { el.textContent = u ? u.hoTen : 'Khách hàng'; });
      VN.$$('[data-tk-email]', menu).forEach((el) => { el.textContent = u ? u.email : ''; });
      VN.$$('[data-tk-chu-cai]', menu).forEach((el) => { el.textContent = u ? VN.taiKhoan.tenGoi(u).charAt(0).toUpperCase() : 'V'; });
      const dem = (sel, n) => VN.$$(sel, menu).forEach((el) => { el.textContent = n; el.hidden = !n; });
      dem('[data-tk-dem-don]', u ? VN.donHang.cuaToi().filter((d) => ['Pending', 'Confirmed', 'Shipping'].includes(d.trangThai)).length : 0);
      dem('[data-tk-dem-the]', u ? VN.baoHanh.cuaToi().length : 0);
      dem('[data-tk-dem-lich]', u ? VN.lichHen.cuaToi().filter((l) => ['Pending', 'Confirmed'].includes(l.trangThai)).length : 0);
      dem('[data-tk-dem-yeu-thich]', VN.yeuThich.ds().length);
    };
    ve();
    ['vinora:don-hang', 'vinora:bao-hanh', 'vinora:lich-hen', 'vinora:tai-khoan', 'vinora:yeu-thich'].forEach((ten) => window.addEventListener(ten, ve));
  };
  const khoiTaoDangXuat = () => {
    document.addEventListener('click', async (e) => {
      if (!e.target.closest('[data-dang-xuat]')) return;
      dongXemNhanh();
      const dongY = await VN.xacNhan({ nhan: 'Tài khoản', tieuDe: 'Đăng xuất khỏi Vinora?', noiDung: 'Giỏ hàng của tài khoản được giữ lại cho lần đăng nhập sau. Sản phẩm yêu thích và lịch sử xem vẫn nằm trên trình duyệt này.', chuDongY: 'Đăng xuất' });
      if (!dongY) return;
      await VN.taiKhoan.dangXuat();
      location.href = VN.url('taiKhoan');
    });
  };

  /** Đồng hồ đếm ngược hạn thanh toán: mọi phần tử [data-dem-nguoc="thời điểm hết hạn"] cập nhật mỗi giây */
  const khoiTaoDemNguoc = () => {
    let lanLamMoi = 0;     // hết giờ thì tải lại đơn, nhưng không quá một lần mỗi 10 giây (đồng hồ máy khách có thể chạy trước máy chủ)
    const chay = () => {
      let het = false;
      VN.$$('[data-dem-nguoc]').forEach((el) => {
        const con = new Date(el.dataset.demNguoc).getTime() - Date.now();
        el.textContent = VN.dinhDangDemNguoc(con);
        const khung = el.closest('[data-khung-dem-nguoc]'); if (khung) khung.classList.toggle('sap-het', con < 3600000);
        if (con <= 0) het = true;
      });
      if (het && Date.now() - lanLamMoi > 10000) { lanLamMoi = Date.now(); VN.donHang.heHan(); }   // máy chủ tự hủy đơn, trang nghe 'vinora:don-hang' để vẽ lại
    };
    chay(); setInterval(chay, 1000);
  };

  /** Ảnh lỗi (mất mạng hoặc máy chủ ảnh chặn) -> dùng ảnh tạm của thương hiệu */
  const xuLyAnhLoi = () => {
    document.addEventListener('error', (e) => {
      const img = e.target;
      if (!(img instanceof HTMLImageElement) || img.dataset.daThay) return;
      if (img.classList.contains('the-sp__anh-phu')) { img.remove(); return; }
      if (!/anh-tam\.svg$/.test(img.src) && /huythanhjewelry/.test(img.src)) {
        img.dataset.daThay = '1'; img.classList.remove('la-anh-chup'); img.src = VN.anhTam();
      }
    }, true);
  };

  /* ================= 11. KHỞI ĐỘNG ================= */
  VN.khoiDong = () => {
    xuLyAnhLoi();
    khoiTaoMenu();
    khoiTaoNhanTin();
    khoiTaoMenuTaiKhoan();
    khoiTaoDangXuat();
    khoiTaoXemNhanh();
    khoiTaoYeuThich();
    khoiTaoDemNguoc();
    capNhatSoGio(false);
    capNhatSoYeuThich();
    capNhatTaiKhoanDauTrang();
    VN.hienDan();
    window.addEventListener('vinora:gio', (e) => { capNhatSoGio(!!(e.detail && e.detail.nhay)); });
    window.addEventListener('vinora:tai-khoan', capNhatTaiKhoanDauTrang);
    // Đồng bộ giỏ hàng giữa các thẻ trình duyệt đang mở
    window.addEventListener('storage', (e) => {
      if (e.key === TIEN_TO + 'gioHang' && !VN.taiKhoan.hienTai()) VN.gioHang.nap().catch(() => {});   // giỏ của khách chưa đăng nhập đổi ở thẻ khác
      if (e.key === TIEN_TO + 'yeuThich') { capNhatSoYeuThich(); VN.capNhatNutTim(); }
      const SU_KIEN = { donHang: 'don-hang', hoTro: 'ho-tro', lichHen: 'lich-hen', baoHanh: 'bao-hanh', danhGia: 'danh-gia', nguoiDung: 'nguoi-dung', qtSanPham: 'san-pham' };
      const khoa = String(e.key || '').replace(TIEN_TO, '');
      if (SU_KIEN[khoa]) phatSuKien(SU_KIEN[khoa]);
    });
    // Tải trước dữ liệu khi trình duyệt rảnh để tìm kiếm phản hồi tức thì
    const ranh = window.requestIdleCallback || ((f) => setTimeout(f, 600));
    ranh(() => VN.duLieu.coBan().catch((loi) => console.error(loi)));
    // Đã đăng nhập: tải danh sách đơn để đầu trang đếm số đơn đang xử lý
    VN.sanSang.then(() => { if (VN.taiKhoan.hienTai()) ranh(() => VN.donHang.nap().catch(() => {})); });
  };
  // Chạy sau khi mọi script của trang (đều defer) đã chạy xong, để các mô-đun api.js và session.js đã có mặt
  if (document.readyState === 'complete') VN.khoiDong();
  else window.addEventListener('DOMContentLoaded', VN.khoiDong);
})();
