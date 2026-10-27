/* =====================================================================
   VINORA JEWELRY — chung.js (dùng chung cho mọi trang khách hàng)
   ---------------------------------------------------------------------
   1. Tiện ích DOM & định dạng (tiền VNĐ, ngày giờ, bỏ dấu tiếng Việt)
   2. Đường dẫn trang & ảnh sản phẩm
   3. AJAX bằng XMLHttpRequest + kho dữ liệu (JSON, XML)
   4. Lưu trữ cục bộ – mô phỏng CSDL khi chưa nối back-end
   5. Tài khoản (User / Customer)
   6. Giỏ hàng & tính tiền đơn hàng
   7. Đơn hàng – Thanh toán – Giữ chân hủy đơn – Bảo hành – Lịch hẹn – Đánh giá
   8. Sản phẩm đã xem
   9. Thành phần giao diện: thông báo, hộp thoại xác nhận, thẻ sản phẩm
   10. Đầu trang: menu, tìm kiếm gợi ý, giỏ hàng mini
   11. Dữ liệu trải nghiệm (tài khoản demo) & khởi động
   Ghi chú tích hợp back-end: các hàm trong mục 5 – 7 đang lưu bằng localStorage.
   Khi có API Python, chỉ cần thay phần thân hàm bằng lời gọi AJAX tương ứng.
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

  /* Nguồn ảnh mặc định (khớp static/dulieu/sanpham.json) – dùng được ngay cả khi trang chưa tải danh sách sản phẩm */
  let nguonAnh = { cdn: 'https://cdn.huythanhjewelry.vn/storage/photos/', cloud: 'https://cloud.huythanhjewelry.vn/storage/photos/' };
  /** Ảnh sản phẩm lưu dạng rút gọn "cdn|shares/..." -> URL đầy đủ */
  VN.anh = (duong) => {
    if (!duong) return VN.anhTam();
    if (/^https?:|^\//.test(duong)) return duong;
    const i = duong.indexOf('|');
    return i > 0 ? (nguonAnh[duong.slice(0, i)] || '') + duong.slice(i + 1) : duong;
  };
  VN.anhTam = () => (duongDan.hinh || '') + 'minhhoa/anh-tam.svg';
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

  const tepDuLieu = (ten) => (duongDan.duLieu || 'static/dulieu/') + ten;
  const cache = {};
  VN.duLieu = {
    /** Danh sách sản phẩm + chỉ mục theo mã (SKU) */
    sanPham() {
      return cache.sp || (cache.sp = VN.taiJSON(tepDuLieu('sanpham.json')).then((d) => {
        nguonAnh = Object.assign({}, nguonAnh, d.nguonAnh || {});
        const theoMa = {};
        d.sanPham.forEach((sp) => {
          sp.coTheMua = sp.loaiGia !== 'gia_cong';          // giá công: cần báo giá theo giá vàng ngày
          sp.giaBan = sp.coTheMua ? sp.gia : null;
          theoMa[sp.ma] = sp;
        });
        return { ds: d.sanPham, theoMa };
      }));
    },
    danhMuc() {
      return cache.dm || (cache.dm = VN.taiJSON(tepDuLieu('danhmuc.json')).then((d) => {
        const theoId = {}; d.danhMuc.forEach((x) => { theoId[x.id] = x; });
        return { ds: d.danhMuc, theoId };
      }));
    },
    boSuuTap() {
      return cache.bst || (cache.bst = VN.taiJSON(tepDuLieu('bosuutap.json')).then((d) => {
        const theoId = {}; d.boSuuTap.forEach((x) => { theoId[x.id] = x; });
        return { ds: d.boSuuTap, theoId };
      }));
    },
    cauHinh() { return cache.ch || (cache.ch = VN.taiJSON(tepDuLieu('cauhinh.json'))); },
    bangSize() { return cache.size || (cache.size = VN.taiJSON(tepDuLieu('bangsize.json'))); },
    tinhThanh() { return cache.tinh || (cache.tinh = VN.taiJSON(tepDuLieu('tinhthanh.json'))); },
    /** Danh sách showroom đọc từ tệp XML bằng DOM (getElementsByTagName) */
    cuaHang() {
      return cache.ch_xml || (cache.ch_xml = VN.taiXML(tepDuLieu('cuahang.xml')).then((xml) => {
        const lay = (nut, the) => (nut.getElementsByTagName(the)[0] || {}).textContent || '';
        return Array.from(xml.getElementsByTagName('cuahang')).map((n) => ({
          ma: n.getAttribute('ma'), ten: lay(n, 'ten'), diaChi: lay(n, 'diachi'), khuVuc: lay(n, 'khuvuc'),
          dienThoai: lay(n, 'dienthoai'), gioMoCua: lay(n, 'giomocua'), banDo: lay(n, 'bando'),
        }));
      }));
    },
    /** Tải đồng thời dữ liệu cốt lõi và gắn tên danh mục, bộ sưu tập vào từng sản phẩm */
    coBan() {
      return cache.coBan || (cache.coBan = Promise.all([this.sanPham(), this.danhMuc(), this.boSuuTap(), this.cauHinh()])
        .then(([sp, dm, bst, ch]) => {
          sp.ds.forEach((s) => {
            s.dm = dm.theoId[s.danhMuc] || { ten: '', nhom: '' };
            s.bst = bst.theoId[s.boSuuTap] || { ten: '' };
            s.tenChatLieu = (ch.tenChatLieu || {})[s.chatLieu] || s.chatLieu;
            s.tuKhoa = VN.khongDau([s.ten, s.ma, s.dm.ten, s.dm.nhom, s.bst.ten, s.tenChatLieu, s.mau.join(' ')].join(' '));
          });
          return { sp, dm, bst, ch };
        }));
    },
  };

  /* ================= 4. LƯU TRỮ CỤC BỘ (mô phỏng CSDL) ================= */
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

  /* ================= 5. TÀI KHOẢN ================= */
  /** Băm mật khẩu SHA-256 phía trình duyệt (chỉ để mô phỏng – back-end thật phải băm có salt, NFR1) */
  VN.bamMatKhau = async (matKhau, email) => {
    const chuoi = 'vinora|' + String(email).trim().toLowerCase() + '|' + matKhau;
    if (window.crypto && crypto.subtle && window.TextEncoder) {
      const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(chuoi));
      return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
    }
    let h = 5381; for (let i = 0; i < chuoi.length; i++) h = ((h << 5) + h + chuoi.charCodeAt(i)) >>> 0;
    return 'djb2-' + h.toString(16);
  };

  const DEMO = { email: 'demo@vinora.vn', matKhau: 'Vinora@2026', hoTen: 'Nguyễn Minh Anh', sdt: '0901234567' };
  VN.DEMO = DEMO;

  VN.taiKhoan = {
    ds() { return VN.kho.doc('nguoiDung', []); },
    luu(ds) { VN.kho.ghi('nguoiDung', ds); },
    docPhien() {
      try { const s = sessionStorage.getItem(TIEN_TO + 'phien'); if (s) return JSON.parse(s); } catch (e) { /* bỏ qua */ }
      return VN.kho.doc('phien', null);
    },
    hienTai() {
      const phien = this.docPhien();
      if (!phien) return null;
      return this.ds().find((u) => u.id === phien.id) || null;
    },
    datPhien(id, ghiNho = true) {
      const phien = { id, luc: Date.now() };
      if (ghiNho) VN.kho.ghi('phien', phien);
      else { try { sessionStorage.setItem(TIEN_TO + 'phien', JSON.stringify(phien)); } catch (e) { VN.kho.ghi('phien', phien); } }
    },
    async dangKy({ hoTen, email, matKhau, sdt = '' }) {
      email = String(email).trim().toLowerCase();
      const ds = this.ds();
      if (ds.some((u) => u.email === email)) throw new Error('Email này đã được dùng để đăng ký. Vui lòng đăng nhập hoặc dùng email khác.');
      const nguoi = {
        id: 'KH' + Date.now().toString(36).toUpperCase(), vaiTro: 'customer', hoTen: hoTen.trim(), email, sdt,
        matKhauBam: await VN.bamMatKhau(matKhau, email), diaChi: [], sizeNhan: null, ngaySinh: '', ngayTao: new Date().toISOString(),
      };
      ds.push(nguoi); this.luu(ds); this.datPhien(nguoi.id, true);
      phatSuKien('tai-khoan', nguoi);
      return nguoi;
    },
    async dangNhap(email, matKhau, ghiNho = true) {
      email = String(email).trim().toLowerCase();
      if (email === DEMO.email) await VN.demo.damBaoTaiKhoan();
      const nguoi = this.ds().find((u) => u.email === email);
      if (!nguoi || nguoi.matKhauBam !== await VN.bamMatKhau(matKhau, email)) throw new Error('Email hoặc mật khẩu chưa đúng. Vui lòng kiểm tra lại.');
      this.datPhien(nguoi.id, ghiNho);
      if (email === DEMO.email) await VN.demo.damBaoDuLieu(nguoi.id);
      phatSuKien('tai-khoan', nguoi);
      return nguoi;
    },
    dangXuat() {
      VN.kho.xoa('phien');
      try { sessionStorage.removeItem(TIEN_TO + 'phien'); } catch (e) { /* bỏ qua */ }
      phatSuKien('tai-khoan', null);
    },
    capNhat(thayDoi) {
      const hienTai = this.hienTai(); if (!hienTai) return null;
      const ds = this.ds(); const i = ds.findIndex((u) => u.id === hienTai.id);
      ds[i] = Object.assign({}, ds[i], thayDoi); this.luu(ds); phatSuKien('tai-khoan', ds[i]);
      return ds[i];
    },
    async doiMatKhau(cu, moi) {
      const nguoi = this.hienTai();
      if (nguoi.matKhauBam !== await VN.bamMatKhau(cu, nguoi.email)) throw new Error('Mật khẩu hiện tại chưa đúng.');
      this.capNhat({ matKhauBam: await VN.bamMatKhau(moi, nguoi.email) });
    },
    /** Chuyển đến trang đăng nhập nếu chưa đăng nhập; trả về người dùng hiện tại nếu đã đăng nhập */
    yeuCau(quayLai = location.pathname + location.search) {
      const nguoi = this.hienTai();
      if (!nguoi) { location.href = VN.url('taiKhoan', { tiep: quayLai }); return null; }
      return nguoi;
    },
    tenGoi(nguoi) { const p = String(nguoi?.hoTen || '').trim().split(/\s+/); return p[p.length - 1] || ''; },
  };
  VN.kiemTraMatKhau = (mk) => {
    const loi = [];
    if (mk.length < 8) loi.push('ít nhất 8 ký tự');
    if (!/[A-Z]/.test(mk)) loi.push('1 chữ in hoa');
    if (!/[a-z]/.test(mk)) loi.push('1 chữ thường');
    if (!/\d/.test(mk)) loi.push('1 chữ số');
    return loi;
  };

  /* ================= 6. GIỎ HÀNG ================= */
  VN.gioHang = {
    ds() { return VN.kho.doc('gioHang', []); },
    luu(ds) { VN.kho.ghi('gioHang', ds); phatSuKien('gio', ds); },
    /** Mỗi dòng giỏ được phân biệt theo mã + màu + size + nội dung khắc (FR9) */
    khoa(d) { return [d.ma, d.mau || '', d.size || '', d.khacChu || '', d.kieuChu || ''].join('|'); },
    them(dong, toiDa = 5) {
      const ds = this.ds(); const k = this.khoa(dong);
      const co = ds.find((x) => this.khoa(x) === k);
      let vuotMuc = false;
      if (co) { const sl = co.soLuong + dong.soLuong; vuotMuc = sl > toiDa; co.soLuong = Math.min(toiDa, sl); }
      else ds.unshift(Object.assign({ soLuong: 1 }, dong, { themLuc: Date.now() }));
      this.luu(ds);
      return { ds, vuotMuc };
    },
    datSoLuong(khoa, sl) { const ds = this.ds(); const d = ds.find((x) => this.khoa(x) === khoa); if (d) { d.soLuong = sl; this.luu(ds); } },
    xoa(khoa) { const ds = this.ds(); const i = ds.findIndex((x) => this.khoa(x) === khoa); let da = null; if (i > -1) { da = ds.splice(i, 1)[0]; this.luu(ds); } return da; },
    khoiPhuc(dong, viTri = 0) { const ds = this.ds(); ds.splice(viTri, 0, dong); this.luu(ds); },
    /** Sửa size / chữ khắc / màu của một dòng; nếu trùng với dòng khác thì gộp số lượng (FR9) */
    capNhatDong(khoaCu, thayDoi, toiDa = 5) {
      const ds = this.ds(); const i = ds.findIndex((x) => this.khoa(x) === khoaCu);
      if (i < 0) return null;
      const moi = Object.assign({}, ds[i], thayDoi);
      ['mau', 'size', 'khacChu', 'kieuChu'].forEach((k) => { if (moi[k] === '' || moi[k] === null || moi[k] === undefined) delete moi[k]; });
      if (!moi.khacChu) delete moi.kieuChu;
      const k = this.khoa(moi);
      const j = ds.findIndex((x, n) => n !== i && this.khoa(x) === k);
      if (j > -1) { ds[j].soLuong = Math.min(toiDa, ds[j].soLuong + moi.soLuong); ds.splice(i, 1); } else ds[i] = moi;
      this.luu(ds);
      return k;
    },
    xoaHet() { this.luu([]); },
    tongSoLuong() { return this.ds().reduce((t, d) => t + (d.soLuong || 0), 0); },
    /** Ghép dữ liệu sản phẩm mới nhất để kiểm tra lại giá (FR10) */
    async chiTiet() {
      const { sp } = await VN.duLieu.coBan();
      return this.ds().map((d) => {
        const s = sp.theoMa[d.ma];
        return s && s.coTheMua ? Object.assign({}, d, { sp: s, donGia: s.giaBan, thanhTien: s.giaBan * d.soLuong, khoa: this.khoa(d) }) : null;
      }).filter(Boolean);
    },
  };

  /** Tùy chọn của giỏ hàng (gói quà, lời nhắn thiệp, mã ưu đãi) – dùng chung cho trang giỏ hàng và thanh toán */
  VN.tuyChonGio = {
    doc() { return Object.assign({ goiQua: true, loiNhan: '', maUuDai: '' }, VN.kho.doc('tuyChonGio', {})); },
    ghi(thayDoi) { return VN.kho.ghi('tuyChonGio', Object.assign(this.doc(), thayDoi)); },
    xoa() { VN.kho.xoa('tuyChonGio'); },
  };

  /** Tính tiền đơn hàng – một nơi duy nhất cho giỏ hàng, giỏ mini và thanh toán (NFR5) */
  VN.tinhTien = (dong, ch, { maUuDai = '', maGiao = 'tieu-chuan' } = {}) => {
    const tamTinh = dong.reduce((t, d) => t + d.donGia * d.soLuong, 0);
    let giam = 0; let uuDai = null; let loi = '';
    const ma = String(maUuDai || '').trim().toUpperCase();
    if (ma) {
      const u = (ch.maUuDai || []).find((x) => x.ma === ma);
      if (!u) loi = 'Mã ưu đãi không tồn tại hoặc đã hết hạn.';
      else if (tamTinh < (u.donToiThieu || 0)) loi = `Mã ${u.ma} áp dụng cho đơn từ ${VN.tien(u.donToiThieu)}.`;
      else {
        uuDai = u;
        if (u.loai === 'phan-tram') giam = Math.min(Math.round(tamTinh * u.giaTri / 100), u.toiDa || Infinity);
        else if (u.loai === 'so-tien') giam = Math.min(u.giaTri, tamTinh);
      }
    }
    const dsGiao = ch.giaoHang.phuongThuc;
    const pt = dsGiao.find((p) => p.ma === maGiao) || dsGiao[0];
    let phiGiao = pt.phi;
    const duMienPhi = tamTinh >= ch.giaoHang.mienPhiTu;
    if (pt.mienPhiTheoDon && duMienPhi) phiGiao = 0;
    if (uuDai && uuDai.loai === 'mien-phi-giao') phiGiao = 0;
    if (!dong.length) phiGiao = 0;
    return { tamTinh, giam, phiGiao, tong: Math.max(0, tamTinh - giam) + phiGiao, uuDai, loi, pt, duMienPhi, conThieu: Math.max(0, ch.giaoHang.mienPhiTu - tamTinh) };
  };

  /* ================= 7. ĐƠN HÀNG – THANH TOÁN – BẢO HÀNH – LỊCH HẸN – ĐÁNH GIÁ ================= */
  VN.TRANG_THAI_DON = {
    Pending: { ten: 'Chờ xử lý', lop: 'nhan--cam', bt: 'dong-ho' },
    Shipping: { ten: 'Đang giao', lop: 'nhan--xanh', bt: 'xe-giao' },
    Delivered: { ten: 'Đã nhận', lop: 'nhan--ngoc', bt: 'xac-nhan' },
    Cancelled: { ten: 'Đã hủy', lop: 'nhan--do', bt: 'huy' },
  };
  VN.TRANG_THAI_TT = {
    Pending: { ten: 'Chờ thanh toán', lop: 'nhan--cam' },
    Success: { ten: 'Đã thanh toán', lop: 'nhan--ngoc' },
    Failed: { ten: 'Thanh toán thất bại', lop: 'nhan--do' },
    Refunded: { ten: 'Đã hoàn tiền', lop: 'nhan--xanh' },
  };
  VN.TEN_THANH_TOAN = { COD: 'Thanh toán khi nhận hàng', BANK: 'Chuyển khoản VietQR', VNPAY: 'VNPay (Sandbox)', MOMO: 'Ví MoMo (Sandbox)' };
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

  VN.donHang = {
    tatCa() { return VN.kho.doc('donHang', []); },
    luuTatCa(ds) { VN.kho.ghi('donHang', ds); phatSuKien('don-hang', ds); },
    cuaToi() { const u = VN.taiKhoan.hienTai(); return u ? this.tatCa().filter((d) => d.khachHang === u.id).sort((a, b) => new Date(b.ngayDat) - new Date(a.ngayDat)) : []; },
    lay(ma) { const u = VN.taiKhoan.hienTai(); return this.tatCa().find((d) => d.ma === ma && (!u || d.khachHang === u.id)) || null; },
    capNhat(ma, hamSua) {
      const ds = this.tatCa(); const don = ds.find((d) => d.ma === ma);
      if (!don) throw new Error('Không tìm thấy đơn hàng ' + ma);
      hamSua(don); this.luuTatCa(ds); return don;
    },
    /** Tạo đơn hàng mới ở trạng thái Chờ xử lý (FR10) – mã đơn duy nhất */
    tao(duLieu) {
      const u = VN.taiKhoan.hienTai();
      const ds = this.tatCa();
      let ma; do { ma = 'VNR' + yymmdd() + VN.chuNgauNhien(4); } while (ds.some((d) => d.ma === ma));
      const don = Object.assign({
        ma, khachHang: u.id, ngayDat: new Date().toISOString(), trangThai: 'Pending',
        giuChan: { daApDung: false }, yeuCauHuy: null, daDanhGia: false, lichSu: [],
      }, duLieu);
      ghiLichSu(don, 'Đặt hàng thành công, đơn chờ cửa hàng xác nhận.', 'Khách hàng', 'Pending');
      ds.push(don); this.luuTatCa(ds);
      return don;
    },
    /** Ghi nhận kết quả thanh toán từ cổng Sandbox (FR11) */
    ghiThanhToan(ma, ketQua) {
      return this.capNhat(ma, (don) => {
        don.thanhToan.trangThai = ketQua ? 'Success' : 'Failed';
        don.thanhToan.maGiaoDich = ketQua ? 'SBX' + Date.now() : null;
        don.thanhToan.luc = new Date().toISOString();
        ghiLichSu(don, ketQua ? `Thanh toán thành công qua ${VN.TEN_THANH_TOAN[don.thanhToan.phuongThuc]} (giao dịch ${don.thanhToan.maGiaoDich}).` : `Thanh toán qua ${VN.TEN_THANH_TOAN[don.thanhToan.phuongThuc]} không thành công.`, 'Cổng thanh toán');
      });
    },
    doiSangCOD(ma) {
      return this.capNhat(ma, (don) => {
        don.thanhToan = { phuongThuc: 'COD', trangThai: 'Pending', maGiaoDich: null };
        ghiLichSu(don, 'Khách hàng đổi phương thức thanh toán sang thanh toán khi nhận hàng.');
      });
    },
    coTheHuy(don) { return don && don.trangThai === 'Pending'; },
    /** Ưu đãi giữ chân: tối đa 1 lần mỗi đơn (BRD5, FR13) */
    tinhUuDaiGiuChan(don, ch) {
      const cfg = ch.giuChanDon;
      const giaTriHang = Math.max(0, don.tamTinh - (don.giamGia || 0));
      return Math.min(Math.round(giaTriHang * cfg.phanTram / 100), cfg.toiDa);
    },
    apDungGiuChan(ma, ch) {
      return this.capNhat(ma, (don) => {
        if (!this.coTheHuy(don)) throw new Error('Đơn hàng không còn ở trạng thái có thể điều chỉnh.');
        if (don.giuChan && don.giuChan.daApDung) throw new Error('Đơn hàng này đã nhận ưu đãi giữ chân trước đó.');
        const giam = this.tinhUuDaiGiuChan(don, ch);
        don.giuChan = { daApDung: true, maVoucher: ch.giuChanDon.maVoucher, phanTram: ch.giuChanDon.phanTram, giam, luc: new Date().toISOString() };
        don.yeuCauHuy = { luc: new Date().toISOString(), chapNhanGiuDon: true };
        don.tongTien = Math.max(0, don.tongTien - giam);
        ghiLichSu(don, `Khách yêu cầu hủy và chấp nhận giữ đơn với voucher ${ch.giuChanDon.maVoucher} (−${VN.tien(giam)}).`);
      });
    },
    huy(ma, lyDo, ghiChu = '') {
      return this.capNhat(ma, (don) => {
        if (!this.coTheHuy(don)) throw new Error('Đơn hàng đã được bàn giao vận chuyển nên không thể hủy trên website.');
        const daGiuChan = don.giuChan && don.giuChan.daApDung;
        don.yeuCauHuy = Object.assign({}, don.yeuCauHuy || {}, { luc: new Date().toISOString(), chapNhanGiuDon: daGiuChan ? true : false, lyDo, ghiChu, daHuy: true });
        don.trangThai = 'Cancelled';
        if (don.thanhToan.trangThai === 'Success') don.thanhToan.trangThai = 'Refunded';
        ghiLichSu(don, `Khách hàng hủy đơn. Lý do: ${lyDo}${ghiChu ? ' – ' + ghiChu : ''}.`, 'Khách hàng', 'Cancelled');
      });
    },
    /** Khách xác nhận đã nhận hàng -> Đã nhận -> tự kích hoạt thẻ bảo hành (FR14, FR15) */
    xacNhanDaNhan(ma) {
      const don = this.capNhat(ma, (d) => {
        if (d.trangThai !== 'Shipping') throw new Error('Chỉ xác nhận được với đơn đang giao.');
        d.trangThai = 'Delivered'; d.ngayNhan = new Date().toISOString();
        if (d.thanhToan.phuongThuc === 'COD') { d.thanhToan.trangThai = 'Success'; d.thanhToan.luc = d.ngayNhan; }
        ghiLichSu(d, 'Khách hàng xác nhận đã nhận đủ sản phẩm.', 'Khách hàng', 'Delivered');
      });
      const the = VN.baoHanh.kichHoatChoDon(don);
      this.capNhat(ma, (d) => ghiLichSu(d, `Hệ thống kích hoạt ${the.length} thẻ bảo hành điện tử.`, 'Hệ thống'));
      return { don, the };
    },
    /** Mô phỏng thao tác của cửa hàng khi chưa có trang quản trị (chỉ dùng khi trình bày) */
    moPhongGiaoHang(ma) {
      return this.capNhat(ma, (d) => {
        if (d.trangThai !== 'Pending') throw new Error('Chỉ chuyển được đơn đang chờ xử lý.');
        d.trangThai = 'Shipping'; d.ngayGiao = new Date().toISOString();
        ghiLichSu(d, 'Cửa hàng xác nhận đơn và bàn giao cho đơn vị vận chuyển.', 'Cửa hàng (mô phỏng)', 'Shipping');
      });
    },
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
            ma: this.taoMa(ds), khachHang: don.khachHang, donHang: don.ma, viTri, donVi,
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
      if (trangThai === 'Completed') VN.baoHanh.ghiDichVu(lich.maBaoHanh, lich.loai, `${VN.TEN_DICH_VU[lich.loai]} tại ${lich.tenCuaHang}`, lich.ma);
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
    tao({ donHang, soSao, noiDung, chuDe }) {
      const ds = this.tatCa(); const u = VN.taiKhoan.hienTai();
      if (ds.some((d) => d.donHang === donHang)) throw new Error('Đơn hàng này đã được đánh giá.');
      const dg = { ma: 'DG' + Date.now().toString(36).toUpperCase(), donHang, khachHang: u.id, soSao, noiDung, chuDe, camXuc: this.phanLoai(soSao, noiDung, chuDe), luc: new Date().toISOString() };
      ds.push(dg); VN.kho.ghi('danhGia', ds);
      VN.donHang.capNhat(donHang, (d) => { d.daDanhGia = true; ghiLichSu(d, `Khách hàng đánh giá ${soSao}/5 sao.`); });
      return dg;
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
      return `<span class="the-sp__gia-cong">Giá vàng theo ngày · công <strong>${VN.tien(sp.gia)}</strong></span>`;
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
    return the;
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
    let daNapAnh = false;
    const napAnhMenu = () => {
      if (daNapAnh) return; daNapAnh = true;
      VN.duLieu.sanPham().then(({ theoMa }) => VN.$$('[data-anh-ma]').forEach((img) => {
        const sp = theoMa[img.dataset.anhMa]; if (sp) { img.src = VN.anh(sp.anh[0]); img.alt = sp.ten; }
      })).catch(() => {});
    };

    // Ngăn kéo menu & giỏ hàng
    VN.$$('[data-mo-menu]').forEach((b) => b.addEventListener('click', () => VN.moHopThoai(VN.$('#menu-di-dong'))));
    VN.$$('[data-mo-gio]').forEach((b) => b.addEventListener('click', VN.moGioMini));
    VN.$$('[data-dong-ngan-keo]').forEach((b) => b.addEventListener('click', () => VN.dongHopThoai(b.closest('dialog'))));
    const gioMini = VN.$('#gio-mini');
    if (gioMini) gioMini.addEventListener('click', (e) => {
      const nut = e.target.closest('[data-xoa-mini]');
      if (nut) { const da = VN.gioHang.xoa(nut.dataset.xoaMini); VN.veGioMini(); if (da) VN.thongBao({ tieuDe: 'Đã xóa khỏi giỏ hàng', hanhDong: { chu: 'Hoàn tác', khiBam: () => { VN.gioHang.khoiPhuc(da); VN.veGioMini(); } } }); }
    });

    // Thanh thông báo xoay vòng
    const chuXoay = VN.$$('[data-chu-xoay] span');
    if (chuXoay.length > 1 && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
      let i = 0; setInterval(() => { chuXoay[i].classList.remove('dang-hien'); i = (i + 1) % chuXoay.length; chuXoay[i].classList.add('dang-hien'); }, 5000);
    }
    khoiTaoTimKiem(dauTrang);
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
      dem('[data-tk-dem-don]', u ? VN.donHang.cuaToi().filter((d) => ['Pending', 'Shipping'].includes(d.trangThai)).length : 0);
      dem('[data-tk-dem-the]', u ? VN.baoHanh.cuaToi().length : 0);
      dem('[data-tk-dem-lich]', u ? VN.lichHen.cuaToi().filter((l) => ['Pending', 'Confirmed'].includes(l.trangThai)).length : 0);
    };
    ve();
    ['vinora:don-hang', 'vinora:bao-hanh', 'vinora:lich-hen', 'vinora:tai-khoan'].forEach((ten) => window.addEventListener(ten, ve));
    VN.$$('[data-dang-xuat]').forEach((b) => b.addEventListener('click', async () => {
      const dongY = await VN.xacNhan({ nhan: 'Tài khoản', tieuDe: 'Đăng xuất khỏi Vinora?', noiDung: 'Giỏ hàng và lịch sử xem vẫn được giữ trên trình duyệt này.', chuDongY: 'Đăng xuất' });
      if (!dongY) return;
      VN.taiKhoan.dangXuat();
      location.href = VN.url('taiKhoan');
    }));
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

  /* ================= 11. DỮ LIỆU TRẢI NGHIỆM (TÀI KHOẢN DEMO) & KHỞI ĐỘNG ================= */
  /**
   * Tài khoản trải nghiệm demo@vinora.vn được tạo sẵn vài đơn hàng thật từ dữ liệu sản phẩm
   * để trình bày đủ luồng: hủy đơn có giữ chân, xác nhận nhận hàng, thẻ bảo hành, lịch hẹn.
   */
  VN.demo = {
    async damBaoTaiKhoan() {
      const ds = VN.taiKhoan.ds();
      if (ds.some((u) => u.email === DEMO.email)) return;
      ds.push({
        id: 'KHDEMO', vaiTro: 'customer', hoTen: DEMO.hoTen, email: DEMO.email, sdt: DEMO.sdt,
        matKhauBam: await VN.bamMatKhau(DEMO.matKhau, DEMO.email), sizeNhan: 12, ngaySinh: '2003-08-16', ngayTao: '2026-03-02T09:00:00.000Z',
        diaChi: [{ id: 'DC1', hoTen: DEMO.hoTen, sdt: DEMO.sdt, tinh: 'Thành phố Hồ Chí Minh', phuongXa: 'Phường Linh Xuân', diaChi: '669 Quốc lộ 1', macDinh: true }],
      });
      VN.taiKhoan.luu(ds);
    },
    async damBaoDuLieu(idKhach, batBuoc = false) {
      if (!batBuoc && VN.kho.doc('demoDaTao') === idKhach) return;
      const { sp } = await VN.duLieu.coBan();
      const lay = (ma) => sp.theoMa[ma];
      const dong = (ma, soLuong, them = {}) => {
        const s = lay(ma); if (!s) return null;
        return Object.assign({ ma: s.ma, ten: s.ten, anh: s.anh[0], chatLieu: s.chatLieu, mau: s.mau[0] || '', soLuong, donGia: s.giaBan, laNhan: !!s.canChonSize }, them);
      };
      const lui = (ngay, gio = 10) => { const d = new Date(); d.setDate(d.getDate() - ngay); d.setHours(gio, 12, 0, 0); return d.toISOString(); };
      const nhan = { hoTen: DEMO.hoTen, sdt: DEMO.sdt, email: DEMO.email, tinh: 'Thành phố Hồ Chí Minh', phuongXa: 'Phường Linh Xuân', diaChi: '669 Quốc lộ 1', ghiChu: '' };
      const taoDon = (hauTo, ngay, trangThai, dongHang, thanhToan, them = {}) => {
        const ma = 'VNR' + yymmdd(new Date(lui(ngay))) + hauTo;
        const dsDong = dongHang.filter(Boolean);
        const tamTinh = dsDong.reduce((t, d) => t + d.donGia * d.soLuong, 0);
        const giamGia = them.giamGia || 0;
        const phiGiao = tamTinh >= 2000000 ? 0 : 30000;
        return Object.assign({
          ma, khachHang: idKhach, ngayDat: lui(ngay), trangThai, sanPham: dsDong, tamTinh, giamGia, maUuDai: them.maUuDai || '',
          phiGiao, tongTien: tamTinh - giamGia + phiGiao, giaoHang: { ma: 'tieu-chuan', ten: 'Giao tiêu chuẩn có bảo hiểm' },
          nguoiNhan: nhan, goiQua: true, thanhToan, giuChan: { daApDung: false }, yeuCauHuy: null, daDanhGia: false, lichSu: [],
        }, them.khac || {});
      };
      const don1 = taoDon('K7Q2', 73, 'Delivered', [dong('NDINO131LDIA', 1, { size: 12, khacChu: 'M & A 2026', kieuChu: 'co-dien' }), dong('BT408', 1)],
        { phuongThuc: 'VNPAY', trangThai: 'Success', maGiaoDich: 'SBX1786700000000', luc: lui(73) }, { khac: { ngayNhan: lui(69, 15), daDanhGia: true } });
      don1.lichSu = [
        { luc: lui(73), noiDung: 'Đặt hàng thành công, đơn chờ cửa hàng xác nhận.', boi: 'Khách hàng', trangThai: 'Pending' },
        { luc: lui(73, 11), noiDung: 'Thanh toán thành công qua VNPay (Sandbox).', boi: 'Cổng thanh toán', trangThai: 'Pending' },
        { luc: lui(72), noiDung: 'Cửa hàng xác nhận đơn và bàn giao cho đơn vị vận chuyển.', boi: 'Cửa hàng', trangThai: 'Shipping' },
        { luc: lui(69, 15), noiDung: 'Khách hàng xác nhận đã nhận đủ sản phẩm.', boi: 'Khách hàng', trangThai: 'Delivered' },
        { luc: lui(69, 15), noiDung: 'Hệ thống kích hoạt 2 thẻ bảo hành điện tử.', boi: 'Hệ thống', trangThai: 'Delivered' },
      ];
      const don2 = taoDon('P3M8', 5, 'Shipping', [dong('NCZ113', 2, { size: 14, mau: 'Vàng Vàng', khacChu: 'Forever', kieuChu: 'viet-tay' })],
        { phuongThuc: 'COD', trangThai: 'Pending', maGiaoDich: null });
      don2.lichSu = [
        { luc: lui(5), noiDung: 'Đặt hàng thành công, đơn chờ cửa hàng xác nhận.', boi: 'Khách hàng', trangThai: 'Pending' },
        { luc: lui(4), noiDung: 'Cửa hàng xác nhận đơn và bàn giao cho đơn vị vận chuyển.', boi: 'Cửa hàng', trangThai: 'Shipping' },
      ];
      const don3 = taoDon('H6T4', 1, 'Pending', [dong('DCBTCC86', 1), dong('MDZ117', 1)],
        { phuongThuc: 'BANK', trangThai: 'Success', maGiaoDich: 'SBX1792900000000', luc: lui(1) }, { giamGia: 200000, maUuDai: 'CHAOBAN200' });
      don3.lichSu = [
        { luc: lui(1), noiDung: 'Đặt hàng thành công, đơn chờ cửa hàng xác nhận.', boi: 'Khách hàng', trangThai: 'Pending' },
        { luc: lui(1, 11), noiDung: 'Thanh toán thành công qua Chuyển khoản VietQR.', boi: 'Cổng thanh toán', trangThai: 'Pending' },
      ];
      const don4 = taoDon('B2C9', 26, 'Cancelled', [dong('NZ081', 1, { size: 10 })], { phuongThuc: 'COD', trangThai: 'Pending' },
        { khac: { yeuCauHuy: { luc: lui(26, 14), chapNhanGiuDon: false, lyDo: 'Tôi muốn đổi sang mẫu hoặc size khác', daHuy: true } } });
      don4.lichSu = [
        { luc: lui(26), noiDung: 'Đặt hàng thành công, đơn chờ cửa hàng xác nhận.', boi: 'Khách hàng', trangThai: 'Pending' },
        { luc: lui(26, 14), noiDung: 'Khách hàng hủy đơn. Lý do: Tôi muốn đổi sang mẫu hoặc size khác.', boi: 'Khách hàng', trangThai: 'Cancelled' },
      ];
      const dsDon = VN.donHang.tatCa().filter((d) => d.khachHang !== idKhach);
      VN.donHang.luuTatCa(dsDon.concat([don1, don2, don3, don4]));

      // Thẻ bảo hành cho đơn đã nhận + lịch sử dịch vụ mẫu
      VN.baoHanh.luuTatCa(VN.baoHanh.tatCa().filter((t) => t.khachHang !== idKhach));
      const the = VN.baoHanh.kichHoatChoDon(don1, don1.ngayNhan);
      const dsLich = VN.lichHen.tatCa().filter((l) => l.khachHang !== idKhach);
      if (the[0]) {
        const theBh = VN.baoHanh.tatCa();
        const t0 = theBh.find((t) => t.ma === the[0].ma);
        t0.daDung.Cleaning = 1; t0.daDung.Polishing = 1;
        t0.lichSuDichVu = [
          { luc: lui(40, 16), loai: 'Cleaning', noiDung: 'Làm sạch tại Vinora Linh Xuân', maLich: 'LH260916001' },
          { luc: lui(40, 16), loai: 'Polishing', noiDung: 'Đánh bóng & xi mới tại Vinora Linh Xuân', maLich: 'LH260916001' },
        ];
        VN.baoHanh.luuTatCa(theBh);
        const ngayToi = new Date(); ngayToi.setDate(ngayToi.getDate() + 4);
        const maLich1 = 'LH' + yymmdd(new Date(lui(40))) + '001'; const maLich2 = 'LH' + yymmdd(new Date(lui(2))) + '002';
        t0.lichSuDichVu.forEach((x) => { x.maLich = maLich1; });
        VN.baoHanh.luuTatCa(theBh);
        dsLich.push(
          { ma: maLich1, khachHang: idKhach, maBaoHanh: t0.ma, loai: 'Polishing', ngayHen: VN.ngayIso(lui(40)), khungGio: '15:30', cuaHang: 'HCM-LX', tenCuaHang: 'Vinora Linh Xuân', sdt: DEMO.sdt, ghiChu: 'Làm sạch và xi mới trước dịp kỷ niệm.', trangThai: 'Completed', taoLuc: lui(43), lichSu: [] },
          { ma: maLich2, khachHang: idKhach, maBaoHanh: t0.ma, loai: 'Resizing', ngayHen: VN.ngayIso(ngayToi), khungGio: '11:00', cuaHang: 'HCM-SG', tenCuaHang: 'Vinora Đồng Khởi', sdt: DEMO.sdt, sizeMoi: 13, ghiChu: 'Nới size 12 lên 13.', trangThai: 'Confirmed', taoLuc: lui(2), lichSu: [] },
        );
      }
      VN.lichHen.luuTatCa(dsLich);
      const dsDg = VN.danhGia.tatCa().filter((d) => d.khachHang !== idKhach);
      dsDg.push({ ma: 'DGDEMO1', donHang: don1.ma, khachHang: idKhach, soSao: 5, noiDung: 'Nhẫn sáng, đóng gói rất sang. Chữ khắc đẹp đúng như bản xem trước.', chuDe: ['Độ sáng bóng', 'Đóng gói sang trọng'], camXuc: 'Positive', luc: lui(68) });
      VN.kho.ghi('danhGia', dsDg);
      VN.kho.ghi('demoDaTao', idKhach);
    },
    async khoiPhuc() {
      await this.damBaoTaiKhoan();
      await this.damBaoDuLieu('KHDEMO', true);
    },
  };

  VN.khoiDong = () => {
    xuLyAnhLoi();
    khoiTaoMenu();
    khoiTaoNhanTin();
    khoiTaoMenuTaiKhoan();
    capNhatSoGio(false);
    capNhatTaiKhoanDauTrang();
    VN.hienDan();
    window.addEventListener('vinora:gio', () => { capNhatSoGio(true); });
    window.addEventListener('vinora:tai-khoan', capNhatTaiKhoanDauTrang);
    // Đồng bộ giỏ hàng giữa các thẻ trình duyệt đang mở
    window.addEventListener('storage', (e) => { if (e.key === TIEN_TO + 'gioHang') capNhatSoGio(false); });
    // Tải trước dữ liệu khi trình duyệt rảnh để tìm kiếm phản hồi tức thì
    const ranh = window.requestIdleCallback || ((f) => setTimeout(f, 600));
    ranh(() => VN.duLieu.coBan().catch((loi) => console.error(loi)));
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', VN.khoiDong);
  else VN.khoiDong();
})();
