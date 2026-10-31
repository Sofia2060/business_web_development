/* =====================================================================
   5.2.7 QUẢN LÝ ĐƠN HÀNG (FR12, FR13, FR14)
   - Đã đăng nhập: đơn của tài khoản. Chưa đăng nhập: tra cứu bằng mã đơn + số điện thoại,
     danh sách các đơn đặt / tra cứu trên trình duyệt này
   - Danh sách theo trạng thái, tìm theo mã hoặc tên; đơn trả trực tuyến chưa thanh toán có đếm ngược 24 giờ
   - Chi tiết đơn (?ma=): tiến trình, hạn thanh toán, sản phẩm, tiền, giao hàng, thanh toán / hoàn tiền,
     đánh giá của bạn, phản ánh & hỗ trợ, nhật ký (NFR8)
   - Hủy đơn -> popup 5.2.6 (huydon.js); phản ánh -> phananh.js
   - "Đã nhận được hàng" (chỉ đơn Đang giao) -> trang Kích hoạt thẻ bảo hành & Đánh giá
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const khuDs = VN.$('#dh-danh-sach'); const khuCt = VN.$('#dh-chi-tiet');
  if (!khuDs) return;
  const u = VN.taiKhoan.hienTai();     // có thể null: khách đặt hàng không cần tài khoản

  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  const TAB = [['tat-ca', 'Tất cả'], ['Pending', 'Chờ xử lý'], ['Shipping', 'Đang giao'], ['Delivered', 'Đã nhận'], ['Cancelled', 'Đã hủy']];
  const tt = { tab: VN.thamSo('tab') || 'tat-ca', tim: '', ch: null };
  if (!TAB.some(([k]) => k === tt.tab)) tt.tab = 'tat-ca';

  const nhanTT = (don) => { const t = VN.TRANG_THAI_DON[don.trangThai]; return `<span class="nhan ${t.lop}">${t.ten}</span>`; };
  const nhanThanhToan = (don) => {
    const tts = don.thanhToan.trangThai;
    if (tts === 'Pending' && don.trangThai === 'Cancelled') return '<span class="nhan">Chưa thanh toán</span>';
    if (don.thanhToan.phuongThuc === 'COD' && tts === 'Pending') return '<span class="nhan">Thanh toán khi nhận</span>';
    const t = VN.TRANG_THAI_TT[tts] || { ten: tts, lop: '' };
    return `<span class="nhan ${t.lop}">${t.ten}</span>`;
  };
  const chuaThanhToanOnline = (d) => d.trangThai === 'Pending' && d.thanhToan.phuongThuc !== 'COD' && d.thanhToan.trangThai !== 'Success';
  const chiTietDong = (d) => [d.ma, d.mau, d.size ? 'Size ' + d.size : ''].filter(Boolean).map(VN.thoat).join(' · ');
  const khacHtml = (d) => (d.khacChu ? `<span class="dh-khac">Khắc “<span class="kieu-${VN.thoat(d.kieuChu || 'co-dien')}">${VN.thoat(d.khacChu)}</span>” · ${TEN_KIEU[d.kieuChu] || 'Cổ điển'}</span>` : '');
  const sao = (n) => `<span class="sao-danh-gia" aria-label="${n} trên 5 sao">${Array.from({ length: 5 }, (_, i) => VN.bt('sao', i < n ? 'sang' : '')).join('')}</span>`;

  /* Nút thao tác theo trạng thái đơn */
  const nutThaoTac = (don, chiTiet = false) => {
    const n = [];
    if (don.trangThai === 'Shipping') n.push(`<button type="button" class="nut nut--chinh nut--nho" data-tac="da-nhan" data-ma="${don.ma}">${VN.bt('xac-nhan')} Đã nhận được hàng</button>`);
    if (chuaThanhToanOnline(don)) n.push(`<a class="nut nut--chinh nut--nho" href="${VN.url('ketQuaDatHang', { ma: don.ma })}">${VN.bt('the')} Thanh toán ngay</a>`);
    if (don.trangThai === 'Delivered') {
      n.push(don.daDanhGia
        ? `<a class="nut nut--vien nut--nho" href="${VN.url('kichHoatBaoHanh', { don: don.ma })}">${VN.bt('khien')} Thẻ bảo hành</a>`
        : `<a class="nut nut--chinh nut--nho" href="${VN.url('kichHoatBaoHanh', { don: don.ma })}#danh-gia">${VN.bt('sao')} Đánh giá &amp; xem thẻ</a>`);
    }
    if (!chiTiet) n.push(`<a class="nut nut--vien nut--nho" href="${VN.url('donHang', { ma: don.ma })}" data-xem="${don.ma}">Xem chi tiết</a>`);
    if (chiTiet || ['Shipping', 'Delivered'].includes(don.trangThai)) n.push(`<button type="button" class="nut nut--vien nut--nho" data-tac="phan-anh" data-ma="${don.ma}">${VN.bt('chat')} Phản ánh vấn đề</button>`);
    if (['Delivered', 'Cancelled'].includes(don.trangThai)) n.push(`<button type="button" class="nut nut--vien nut--nho" data-tac="mua-lai" data-ma="${don.ma}">${VN.bt('doi-tra')} Mua lại</button>`);
    if (VN.donHang.coTheHuy(don)) n.push(`<button type="button" class="nut nut--chu nut-huy-don" data-tac="huy" data-ma="${don.ma}">Hủy đơn</button>`);
    return n.join('');
  };

  /* Đếm ngược hạn thanh toán (chung.js cập nhật mỗi giây các phần tử [data-dem-nguoc]) */
  const hanGon = (don) => (chuaThanhToanOnline(don) && don.hanThanhToan
    ? `<p class="the-don__han${VN.donHang.conLaiThanhToan(don) < 3600000 ? ' sap-het' : ''}" data-khung-dem-nguoc>${VN.bt('dong-ho', 'bt--nho')} Thanh toán trong <strong class="so-deu" data-dem-nguoc="${don.hanThanhToan}">${VN.dinhDangDemNguoc(VN.donHang.conLaiThanhToan(don))}</strong> – quá hạn đơn tự hủy</p>` : '');

  /* ================= TRA CỨU (khách chưa đăng nhập) ================= */
  const formTc = VN.$('#form-tra-cuu-dh');
  formTc.addEventListener('submit', (e) => {
    e.preventDefault();
    const loi = VN.$('#tc-loi');
    const kiemTra = (o, dung, thongDiep) => { VN.baoLoiTruong(o, dung ? '' : thongDiep); return dung; };
    const ok = [
      kiemTra(formTc.ma, /^VNR\w{8,}$/i.test(formTc.ma.value.trim()), 'Mã đơn bắt đầu bằng VNR, ví dụ VNR251030ABCD.'),
      kiemTra(formTc.sdt, VN.sdtHopLe(formTc.sdt.value), 'Số điện thoại gồm 10 số, bắt đầu bằng 03, 05, 07, 08 hoặc 09.'),
    ].every(Boolean);
    if (!ok) { loi.hidden = true; return; }
    const kq = VN.donHang.traCuu(formTc.ma.value, formTc.sdt.value);
    if (kq.loi) {
      loi.hidden = false;
      loi.innerHTML = `${VN.bt('canh-bao')}<span>${VN.thoat(kq.loi)}${kq.canDangNhap ? ` <a class="lien-ket" href="${VN.url('taiKhoan', { tiep: location.pathname + location.search })}">Đăng nhập</a>` : ''}</span>`;
      return;
    }
    loi.hidden = true; formTc.reset();
    history.pushState(null, '', VN.url('donHang', { ma: kq.don.ma }));
    veTheoUrl(); window.scrollTo({ top: 0 });
  });

  /* ================= DANH SÁCH ================= */
  const veDanhSach = () => {
    const tat = VN.donHang.cuaToi();
    const khung = VN.$('#dh-ds');
    VN.$('#dh-nhom-khach').hidden = !!u || !tat.length;
    VN.$('.cong-cu-dh').hidden = !u && !tat.length;
    const dem = (k) => (k === 'tat-ca' ? tat.length : tat.filter((d) => d.trangThai === k).length);
    VN.$('#dh-tab').innerHTML = TAB.map(([k, ten]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${k === tt.tab}">${ten}<span class="dem">${dem(k)}</span></button>`).join('');
    const tu = VN.khongDau(tt.tim.trim());
    const ds = tat.filter((d) => (tt.tab === 'tat-ca' || d.trangThai === tt.tab)
      && (!tu || VN.khongDau(d.ma + ' ' + d.sanPham.map((s) => s.ten + ' ' + s.ma).join(' ')).includes(tu)));
    if (!tat.length) {
      khung.innerHTML = u
        ? `<div class="trong-rong khoi-tk"><div class="trong-rong__bieu-tuong">${VN.bt('hop-hang')}</div><h2 class="t-3">Bạn chưa có đơn hàng nào</h2>
          <p>Khi đặt hàng, đơn sẽ xuất hiện tại đây để bạn theo dõi giao hàng và kích hoạt thẻ bảo hành.</p><a class="nut nut--chinh" href="${VN.url('sanPham')}">Khám phá trang sức</a></div>`
        : '';
      return;
    }
    if (!ds.length) { khung.innerHTML = `<div class="trong-rong khoi-tk"><p>Không có đơn hàng phù hợp${tu ? ` với “${VN.thoat(tt.tim)}”` : ''}.</p></div>`; return; }
    khung.innerHTML = ds.map((don) => {
      const sl = don.sanPham.reduce((a, d) => a + d.soLuong, 0);
      return `<article class="the-don the-don--${don.trangThai.toLowerCase()}">
        <header class="the-don__dau">
          <div><p class="the-don__ma">Đơn <a href="${VN.url('donHang', { ma: don.ma })}" data-xem="${don.ma}">${VN.thoat(don.ma)}</a></p><p class="chu-rat-nho chu-phu">Đặt ${VN.ngayGio(don.ngayDat)}</p></div>
          <div class="the-don__nhan">${nhanTT(don)}${nhanThanhToan(don)}</div>
        </header>
        <ul class="the-don__sp">${don.sanPham.map((d) => `<li>
          <span class="the-don__anh"><img src="${VN.anh(d.anh)}" alt="" width="72" height="72" loading="lazy"${VN.laAnhChup(d.anh) ? ' class="la-anh-chup"' : ''}></span>
          <span class="the-don__chu"><a href="${VN.urlSanPham(d.ma)}">${VN.thoat(d.ten)}</a><small>${chiTietDong(d)} · SL ${d.soLuong}</small>${khacHtml(d)}</span>
          <span class="the-don__gia so-deu">${VN.tien(d.donGia * d.soLuong)}</span></li>`).join('')}</ul>
        ${hanGon(don)}
        <footer class="the-don__chan">
          <p>${sl} sản phẩm · Tổng <strong class="so-deu">${VN.tien(don.tongTien)}</strong></p>
          <div class="the-don__nut">${nutThaoTac(don)}</div>
        </footer>
      </article>`;
    }).join('');
  };
  VN.$('#dh-tab').addEventListener('click', (e) => {
    const b = e.target.closest('[data-tab]'); if (!b) return;
    tt.tab = b.dataset.tab;
    history.replaceState(null, '', VN.url('donHang', tt.tab === 'tat-ca' ? {} : { tab: tt.tab }));
    veDanhSach();
  });
  VN.$('#dh-tim').addEventListener('submit', (e) => e.preventDefault());
  VN.$('#dh-o-tim').addEventListener('input', VN.chongDoi((e) => { tt.tim = e.target.value; veDanhSach(); }, 150));

  /* ================= CHI TIẾT ================= */
  const BUOC = [['Pending', 'Đặt hàng', 'hop-hang'], ['Shipping', 'Đang giao', 'xe-giao'], ['Delivered', 'Đã nhận hàng', 'xac-nhan'], ['BaoHanh', 'Kích hoạt bảo hành', 'khien']];

  const htmlHuy = (don) => {
    const yc = don.yeuCauHuy || {};
    const ht = don.hoanTien;
    let hoan = '';
    if (don.thanhToan.trangThai === 'RefundPending' && ht) hoan = `<div class="hoan-tien">${VN.bt('doi-tra', 'bt--nho')} <span>Vinora đang hoàn <strong>${VN.tien(ht.soTien)}</strong> vào tài khoản <strong>${VN.thoat(ht.nganHang)}</strong> <span class="so-deu">${VN.thoat(VN.anSoTaiKhoan(ht.soTaiKhoan))}</span> – ${VN.thoat(ht.chuTaiKhoan)}. Thời gian nhận tiền: ${VN.thoat(tt.ch ? tt.ch.hoanTien.thoiGian : '3 – 5 ngày làm việc')}.</span></div>`;
    if (don.thanhToan.trangThai === 'Refunded' && ht) hoan = `<div class="hoan-tien">${VN.bt('xac-nhan', 'bt--nho')} <span>Đã hoàn <strong>${VN.tien(ht.soTien)}</strong> vào tài khoản ${VN.thoat(ht.nganHang)} <span class="so-deu">${VN.thoat(VN.anSoTaiKhoan(ht.soTaiKhoan))}</span>${ht.luc ? ` lúc ${VN.ngayGio(ht.luc)}` : ''}.</span></div>`;
    return `<div class="tien-trinh tien-trinh--huy"><span class="tien-trinh__bt">${VN.bt(yc.tuDong ? 'dong-ho' : 'huy')}</span><div>
      <strong>${yc.tuDong ? 'Đơn hàng đã tự động hủy' : 'Đơn hàng đã hủy'}</strong>
      <p>${VN.ngayGio(yc.luc || don.ngayDat)} · ${yc.tuDong ? `Hệ thống tự hủy vì quá ${VN.HAN_THANH_TOAN_GIO} giờ chưa nhận được thanh toán.` : `Lý do: ${VN.thoat(yc.lyDo || '—')}${yc.ghiChu ? ` – ${VN.thoat(yc.ghiChu)}` : ''}`}</p>${hoan}</div></div>`;
  };

  const htmlDanhGia = (don) => {
    if (don.trangThai !== 'Delivered') return '';
    const dg = VN.danhGia.theoDon(don.ma);
    const noiDung = dg
      ? `<div class="dg-don">${sao(dg.soSao)}
          ${dg.noiDung ? `<blockquote>“${VN.thoat(dg.noiDung)}”</blockquote>` : ''}
          ${dg.chuDe && dg.chuDe.length ? `<div class="chip-nhom">${dg.chuDe.map((c) => `<span class="chip chip--nho">${VN.thoat(c)}</span>`).join('')}</div>` : ''}
          <p class="chu-rat-nho chu-phu">Gửi lúc ${VN.ngayGio(dg.luc)}</p>
          ${dg.phanHoi ? `<div class="dg-don__phan-hoi"><strong>${VN.bt('chat', 'bt--nho')} Phản hồi từ ${VN.thoat(dg.phanHoi.boi)}</strong><p>${VN.thoat(dg.phanHoi.noiDung)}</p><small>${VN.ngayGio(dg.phanHoi.luc)}</small></div>` : ''}</div>`
      : `<div class="dg-don__cta"><p>Bạn chưa đánh giá đơn hàng này. Cảm nhận của bạn giúp Vinora hoàn thiện sản phẩm và dịch vụ.</p>
          <a class="nut nut--chinh nut--nho" href="${VN.url('kichHoatBaoHanh', { don: don.ma })}#danh-gia">${VN.bt('sao')} Viết đánh giá</a></div>`;
    return `<section class="khoi-tk" aria-labelledby="td-dg-dh" id="danh-gia-don">
      <div class="khoi-tk__dau"><div><p class="nhan-tren">Đánh giá</p><h2 id="td-dg-dh">Đánh giá của bạn</h2></div></div>${noiDung}</section>`;
  };

  const htmlPhanAnh = (don) => {
    const ds = VN.hoTro.theoDon(don.ma);
    const gio = tt.ch ? tt.ch.hoTro.phanHoiTrongGio : 24;
    const the = (pa) => {
      const t = VN.TRANG_THAI_HO_TRO[pa.trangThai];
      const tenSp = pa.sanPham.map((m) => (don.sanPham.find((d) => d.ma === m) || {}).ten).filter(Boolean);
      return `<article class="the-pa">
        <div class="the-pa__dau"><strong>${VN.thoat(pa.tenLoai)}<small>Mã ${VN.thoat(pa.ma)} · Gửi ${VN.ngayGio(pa.luc)} · Liên hệ qua ${VN.thoat(pa.lienHe.cach.toLowerCase())} ${VN.thoat(VN.anSdt(pa.lienHe.sdt))}</small></strong><span class="nhan ${t.lop}">${t.ten}</span></div>
        ${tenSp.length ? `<p>${VN.bt('kim-cuong', 'bt--nho')} ${tenSp.map(VN.thoat).join(', ')}</p>` : ''}
        <p>“${VN.thoat(pa.moTa)}”</p>
        ${pa.anh && pa.anh.length ? `<div class="the-pa__anh">${pa.anh.map((a, i) => `<img src="${a}" alt="Ảnh minh chứng ${i + 1}">`).join('')}</div>` : ''}
        <ol class="the-pa__ls">${pa.lichSu.slice().reverse().map((l) => `<li><time>${VN.ngayGio(l.luc)}</time><span>${VN.thoat(l.noiDung)}</span></li>`).join('')}</ol>
      </article>`;
    };
    return `<section class="khoi-tk" aria-labelledby="td-pa-dh" id="phan-anh-don">
      <div class="khoi-tk__dau"><div><p class="nhan-tren">Hỗ trợ</p><h2 id="td-pa-dh">Phản ánh &amp; hỗ trợ</h2>
        <p>Sản phẩm lỗi, giao sai, thiếu hàng, giao chậm hay cần hoàn tiền? Gửi phản ánh kèm ảnh – Vinora liên hệ trong ${gio} giờ. Hoặc gọi hotline 1900 0000.</p></div>
        <button type="button" class="nut nut--vien nut--nho" data-tac="phan-anh" data-ma="${don.ma}">${VN.bt('chat')} Gửi phản ánh</button></div>
      ${ds.length ? `<div class="ds-phan-anh">${ds.map(the).join('')}</div>` : ''}</section>`;
  };

  const veChiTiet = (ma) => {
    const don = VN.donHang.lay(ma);
    khuDs.hidden = true; khuCt.hidden = false; VN.$('#dh-tra-cuu').hidden = true; VN.$('#dh-lien-ket').hidden = true;
    VN.$('#dh-tieu-de').textContent = don ? `Đơn hàng ${don.ma}` : 'Không tìm thấy đơn hàng';
    VN.$('#dh-duong-dan').innerHTML = `<li><a href="${VN.url('trangChu')}">Trang chủ</a></li><li><a href="${VN.url('donHang')}" data-ve-ds>${u ? 'Đơn hàng của tôi' : 'Tra cứu đơn hàng'}</a></li><li aria-current="page">${VN.thoat(ma)}</li>`;
    if (!don) {
      VN.$('#dh-mo-ta').textContent = '';
      khuCt.innerHTML = `<div class="trong-rong khoi-tk"><p>Không xem được đơn <strong>${VN.thoat(ma)}</strong>. ${u ? 'Đơn không thuộc tài khoản đang đăng nhập.' : 'Vui lòng tra cứu bằng mã đơn và số điện thoại đặt hàng.'}</p><a class="nut nut--chinh nut--nho" href="${VN.url('donHang')}" data-ve-ds>${u ? 'Về danh sách đơn' : 'Tra cứu đơn hàng'}</a></div>`;
      return;
    }
    VN.$('#dh-mo-ta').innerHTML = `Đặt lúc ${VN.ngayGio(don.ngayDat)} · ${nhanTT(don)} ${nhanThanhToan(don)}`;
    const huy = don.trangThai === 'Cancelled';
    const coThe = VN.baoHanh.theoDon(don.ma).length > 0;
    const moc = { Pending: don.ngayDat, Shipping: don.ngayGiao || (don.lichSu.find((l) => l.trangThai === 'Shipping') || {}).luc, Delivered: don.ngayNhan, BaoHanh: coThe ? don.ngayNhan : null };
    const thuTu = ['Pending', 'Shipping', 'Delivered'].indexOf(don.trangThai) + (coThe ? 1 : 0);
    const tienTrinh = huy ? htmlHuy(don)
      : `<ol class="tien-trinh">${BUOC.map(([k, ten, bt], i) => `<li class="${i < thuTu ? 'da-xong' : i === thuTu ? 'dang-o' : ''}">
          <span class="tien-trinh__bt">${VN.bt(bt)}</span><strong>${ten}</strong><small>${moc[k] && i <= thuTu ? VN.ngayGio(moc[k]) : i === thuTu + 1 && k === 'Shipping' ? 'Chờ cửa hàng xác nhận' : ''}</small></li>`).join('')}</ol>`;
    const han = chuaThanhToanOnline(don) && don.hanThanhToan
      ? `<div class="han-tt han-tt--ct${VN.donHang.conLaiThanhToan(don) < 3600000 ? ' sap-het' : ''}" data-khung-dem-nguoc>${VN.bt('dong-ho')}<span>Thời gian còn lại để thanh toán</span>
          <strong class="so-deu" data-dem-nguoc="${don.hanThanhToan}">${VN.dinhDangDemNguoc(VN.donHang.conLaiThanhToan(don))}</strong>
          <small>Hạn chót ${VN.ngayGio(don.hanThanhToan)}. Sau thời điểm này, nếu chưa nhận được thanh toán, hệ thống tự động hủy đơn. Bạn có thể chuyển sang thanh toán khi nhận hàng để không bị hủy.</small>
          <div class="hang hang--quan"><a class="nut nut--chinh nut--nho" href="${VN.url('ketQuaDatHang', { ma: don.ma })}">${VN.bt('the')} Thanh toán ngay</a><button type="button" class="nut nut--vien nut--nho" data-tac="doi-cod" data-ma="${don.ma}">Chuyển sang thanh toán khi nhận</button></div></div>` : '';
    const nn = don.nguoiNhan;
    const ht = don.hoanTien;
    khuCt.innerHTML = `
      <div class="dh-ct__dau"><a class="nut nut--chu" href="${VN.url('donHang')}" data-ve-ds>${VN.bt('mui-ten-trai', 'bt--nho')} ${u ? 'Tất cả đơn hàng' : 'Tra cứu đơn khác'}</a><div class="the-don__nut">${nutThaoTac(don, true)}</div></div>
      <section class="khoi-tk">${tienTrinh}${han}</section>
      <div class="dh-ct__luoi">
        <section class="khoi-tk" aria-labelledby="td-sp-dh">
          <div class="khoi-tk__dau"><div><p class="nhan-tren">Sản phẩm</p><h2 id="td-sp-dh">${don.sanPham.reduce((a, d) => a + d.soLuong, 0)} sản phẩm</h2></div></div>
          <ul class="the-don__sp the-don__sp--ct">${don.sanPham.map((d) => `<li>
            <a class="the-don__anh" href="${VN.urlSanPham(d.ma)}"><img src="${VN.anh(d.anh)}" alt="" width="96" height="96"${VN.laAnhChup(d.anh) ? ' class="la-anh-chup"' : ''}></a>
            <span class="the-don__chu"><a href="${VN.urlSanPham(d.ma)}">${VN.thoat(d.ten)}</a><small>${chiTietDong(d)} · ${VN.thoat(d.chatLieu)}</small><small>${VN.tien(d.donGia)} × ${d.soLuong}</small>${khacHtml(d)}</span>
            <span class="the-don__gia so-deu">${VN.tien(d.donGia * d.soLuong)}</span></li>`).join('')}</ul>
          <dl class="dong-tien">
            <div><dt>Tạm tính</dt><dd class="so-deu">${VN.tien(don.tamTinh)}</dd></div>
            ${don.giamGia ? `<div class="dong-tien__giam"><dt>Mã ưu đãi <span class="nhan nhan--vang nhan--tron">${VN.thoat(don.maUuDai)}</span></dt><dd class="so-deu">−${VN.tien(don.giamGia)}</dd></div>` : ''}
            <div><dt>${VN.thoat(don.giaoHang.ten)}</dt><dd class="so-deu">${don.phiGiao ? VN.tien(don.phiGiao) : '<span class="chu-ngoc">Miễn phí</span>'}</dd></div>
            <div class="dong-tien__tong"><dt>Tổng thanh toán</dt><dd class="so-deu">${VN.tien(don.tongTien)}</dd></div>
          </dl>
        </section>
        <div class="dh-ct__phai">
          <section class="khoi-tk">
            <p class="nhan-tren">Giao hàng</p>
            <dl class="kq-thong-tin kq-thong-tin--gon">
              <div><dt>Người nhận</dt><dd>${VN.thoat(nn.hoTen)}<br><span class="so-deu">${VN.thoat(nn.sdt)}</span></dd></div>
              <div><dt>Địa chỉ</dt><dd>${VN.thoat(VN.diaChiDay(nn))}</dd></div>
              <div><dt>Hình thức</dt><dd>${VN.thoat(don.giaoHang.ten)}</dd></div>
              ${nn.ghiChu ? `<div><dt>Ghi chú</dt><dd>${VN.thoat(nn.ghiChu)}</dd></div>` : ''}
              ${don.goiQua ? `<div><dt>Quà tặng</dt><dd>Gói quà Vinora${don.loiNhan ? `<br>Thiệp: “${VN.thoat(don.loiNhan)}”` : ''}</dd></div>` : ''}
              ${!don.khachHang && don.sdtKhach ? `<div><dt>Mã khách</dt><dd>SĐT <span class="so-deu">${VN.thoat(VN.anSdt(don.sdtKhach))}</span> (đặt không cần tài khoản)</dd></div>` : ''}
            </dl>
          </section>
          <section class="khoi-tk">
            <p class="nhan-tren">Thanh toán</p>
            <dl class="kq-thong-tin kq-thong-tin--gon">
              <div><dt>Phương thức</dt><dd>${VN.thoat(VN.TEN_THANH_TOAN[don.thanhToan.phuongThuc])}</dd></div>
              <div><dt>Trạng thái</dt><dd>${nhanThanhToan(don)}</dd></div>
              ${don.thanhToan.maGiaoDich ? `<div><dt>Mã giao dịch</dt><dd class="so-deu">${VN.thoat(don.thanhToan.maGiaoDich)}</dd></div>` : ''}
              ${ht ? `<div><dt>Hoàn tiền về</dt><dd>${VN.thoat(ht.nganHang)} <span class="so-deu">${VN.thoat(VN.anSoTaiKhoan(ht.soTaiKhoan))}</span><br>${VN.thoat(ht.chuTaiKhoan)}</dd></div>` : ''}
            </dl>
          </section>
        </div>
      </div>
      ${htmlDanhGia(don)}
      ${htmlPhanAnh(don)}
      <section class="khoi-tk" aria-labelledby="td-nhat-ky">
        <div class="khoi-tk__dau"><div><p class="nhan-tren">Nhật ký đơn hàng</p><h2 id="td-nhat-ky">Lịch sử xử lý</h2><p>Mọi thay đổi trạng thái, thanh toán, hoàn tiền và phản ánh đều được ghi lại kèm thời điểm và người thực hiện.</p></div></div>
        <ol class="nhat-ky">${don.lichSu.slice().reverse().map((l) => `<li><time datetime="${l.luc}">${VN.ngayGio(l.luc)}</time><div><p>${VN.thoat(l.noiDung)}</p><small>${VN.thoat(l.boi)} · ${VN.TRANG_THAI_DON[l.trangThai] ? VN.TRANG_THAI_DON[l.trangThai].ten : ''}</small></div></li>`).join('')}</ol>
      </section>`;
  };

  /* ================= ĐIỀU HƯỚNG & THAO TÁC ================= */
  const veLienKet = () => {
    const khung = VN.$('#dh-lien-ket');
    const ds = u && u.sdt ? VN.donHang.chuaLienKet(u.sdt) : [];
    khung.hidden = !ds.length;
    if (ds.length) khung.innerHTML = `${VN.bt('dien-thoai')}<span>Có <strong>${ds.length} đơn hàng</strong> đặt bằng số <span class="so-deu">${VN.thoat(VN.anSdt(u.sdt))}</span> khi chưa đăng nhập. <a class="lien-ket" href="${VN.url('taiKhoan', { lienket: 1 })}">Xác minh số điện thoại để liên kết vào tài khoản</a>.</span>`;
  };
  const veTheoUrl = () => {
    const ma = VN.thamSo('ma');
    if (ma) {
      veChiTiet(ma);
      if (VN.thamSo('phananh') && VN.donHang.lay(ma)) {
        history.replaceState(null, '', VN.url('donHang', { ma }));
        setTimeout(() => moPhanAnh(ma), 200);
      }
      return;
    }
    khuCt.hidden = true; khuDs.hidden = false;
    VN.$('#dh-tra-cuu').hidden = !!u;
    VN.$('#dh-tieu-de').textContent = u ? 'Đơn hàng của tôi' : 'Tra cứu đơn hàng';
    VN.$('#dh-mo-ta').textContent = u
      ? 'Theo dõi trạng thái, thanh toán, hủy đơn khi còn chờ xử lý, phản ánh khi có vấn đề và xác nhận đã nhận hàng để kích hoạt thẻ bảo hành.'
      : 'Đặt hàng không cần tài khoản? Tra cứu đơn bằng mã đơn và số điện thoại để theo dõi giao hàng, thanh toán, hủy đơn hoặc phản ánh.';
    VN.$('#dh-duong-dan').innerHTML = u
      ? `<li><a href="${VN.url('trangChu')}">Trang chủ</a></li><li><a href="${VN.url('taiKhoan')}">Tài khoản</a></li><li aria-current="page">Đơn hàng của tôi</li>`
      : `<li><a href="${VN.url('trangChu')}">Trang chủ</a></li><li aria-current="page">Tra cứu đơn hàng</li>`;
    veLienKet();
    veDanhSach();
  };
  const lamMoi = () => { if (VN.thamSo('ma')) veChiTiet(VN.thamSo('ma')); else veDanhSach(); };
  window.addEventListener('popstate', veTheoUrl);
  // Đơn thay đổi (tự hủy khi hết hạn thanh toán, phản ánh được xử lý…) -> vẽ lại
  window.addEventListener('vinora:don-hang', VN.chongDoi(lamMoi, 60));
  window.addEventListener('vinora:ho-tro', VN.chongDoi(lamMoi, 60));
  // Cửa hàng xử lý đơn ở trang quản trị (thẻ trình duyệt khác) -> cập nhật ngay
  window.addEventListener('storage', (e) => { if (/^vinora\.(donHang|hoTro|danhGia)$/.test(e.key || '')) lamMoi(); });

  const moPhanAnh = async (ma) => { if (VN.moPhanAnh) await VN.moPhanAnh(ma); };

  document.addEventListener('click', async (e) => {
    const xem = e.target.closest('[data-xem]');
    if (xem) { e.preventDefault(); history.pushState(null, '', VN.url('donHang', { ma: xem.dataset.xem })); veTheoUrl(); window.scrollTo({ top: 0 }); return; }
    const ve = e.target.closest('[data-ve-ds]');
    if (ve) { e.preventDefault(); history.pushState(null, '', VN.url('donHang', tt.tab === 'tat-ca' ? {} : { tab: tt.tab })); veTheoUrl(); return; }
    const b = e.target.closest('[data-tac]'); if (!b) return;
    const ma = b.dataset.ma; const don = ma ? VN.donHang.lay(ma) : null;
    if (b.dataset.tac === 'huy') {
      await VN.moHuyDon(ma);
      lamMoi();
    } else if (b.dataset.tac === 'phan-anh') {
      await moPhanAnh(ma);
    } else if (b.dataset.tac === 'doi-cod') {
      const dongY = await VN.xacNhan({ nhan: 'Đổi phương thức thanh toán', tieuDe: 'Chuyển sang thanh toán khi nhận hàng?', noiDung: 'Bạn sẽ thanh toán bằng tiền mặt hoặc chuyển khoản khi nhận hàng; đơn không còn bị giới hạn 24 giờ.', chuDongY: 'Chuyển sang COD' });
      if (!dongY) return;
      try { VN.donHang.doiSangCOD(ma); VN.thongBao({ tieuDe: 'Đã chuyển sang thanh toán khi nhận hàng', loai: 'thanh-cong' }); } catch (loi) { VN.thongBao({ tieuDe: 'Không đổi được', noiDung: VN.thoat(loi.message), loai: 'loi' }); }
    } else if (b.dataset.tac === 'da-nhan') {
      const dongY = await VN.xacNhan({
        nhan: `Đơn ${ma}`, tieuDe: 'Bạn đã nhận đủ sản phẩm?', chuDongY: 'Đã nhận được hàng', chuHuy: 'Chưa nhận',
        noiDung: `Xác nhận khi bạn đã kiểm tra ${don.sanPham.reduce((a, d) => a + d.soLuong, 0)} sản phẩm còn nguyên niêm phong, đúng size và chữ khắc. Hệ thống sẽ kích hoạt thẻ bảo hành điện tử trọn đời cho từng sản phẩm. Nếu có vấn đề, hãy chọn “Phản ánh vấn đề”.`,
      });
      if (!dongY) return;
      try {
        VN.donHang.xacNhanDaNhan(ma);
        location.href = VN.url('kichHoatBaoHanh', { don: ma });
      } catch (loi) { VN.thongBao({ tieuDe: 'Không xác nhận được', noiDung: VN.thoat(loi.message), loai: 'loi' }); }
    } else if (b.dataset.tac === 'mua-lai') {
      const { sp } = await VN.duLieu.coBan();
      let them = 0;
      don.sanPham.forEach((d) => {
        const s = sp.theoMa[d.ma]; if (!s || !s.coTheMua) return;
        const dong = { ma: d.ma, soLuong: d.soLuong };
        if (d.mau) dong.mau = d.mau; if (d.size) dong.size = d.size;
        if (d.khacChu) { dong.khacChu = d.khacChu; dong.kieuChu = d.kieuChu; }
        VN.gioHang.them(dong); them += d.soLuong;
      });
      if (them) VN.moGioMini();
      else VN.thongBao({ tieuDe: 'Sản phẩm hiện không còn bán trực tuyến', loai: 'loi' });
    }
  });

  const batDau = async () => {
    tt.ch = await VN.duLieu.cauHinh().catch(() => null);
    if (!u) {
      VN.$('.menu-tk').hidden = true; VN.$('.khu-tk').classList.add('khu-tk--khach');
      VN.$('#tc-dang-nhap').href = VN.url('taiKhoan', { tiep: location.pathname + location.search });
    }
    veTheoUrl();
  };
  if (u && u.email === VN.DEMO.email) VN.demo.damBaoDuLieu(u.id).then(batDau); else batDau();
})();
