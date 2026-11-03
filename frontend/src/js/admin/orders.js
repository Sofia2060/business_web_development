/* =====================================================================
   QUẢN TRỊ – ĐƠN HÀNG (nối API /api/admin/orders)
   - Lọc theo trạng thái / phương thức thanh toán, tìm theo mã đơn, tên, số điện thoại
   - Ngăn chi tiết (?ma=): khách, sản phẩm, tiền, thanh toán, nhật ký (lấy từ GET /api/admin/orders/<mã>)
   - Thao tác: xác nhận đã nhận tiền chuyển khoản · xác nhận đơn · bắt đầu chế tác · bàn giao vận chuyển
     · giao thành công (kích hoạt bảo hành) · hủy đơn
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-dh-bang')) return;
  const TAB = [['tat-ca', 'Tất cả'], ['Pending', 'Chờ xử lý'], ['Confirmed', 'Đã xác nhận'], ['Shipping', 'Đang giao'], ['Delivered', 'Đã nhận'], ['Cancelled', 'Đã hủy']];
  const tt = { tab: VN.thamSo('tt') || 'tat-ca', pt: '', tim: '', trang: 1, ma: VN.thamSo('ma') || '' };
  if (!TAB.some(([k]) => k === tt.tab)) tt.tab = 'tat-ca';
  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  let theBaoHanh = [];     // all warranty cards (GET /api/admin/warranties), loaded when a delivered order is opened

  const hopTab = (d, k) => (k === 'tat-ca' ? true : d.trangThai === k);
  const hanHtml = (d) => {
    if (!qt.chuaTra(d) || !d.hanThanhToan) return '';
    const con = VN.donHang.conLaiThanhToan(d);
    return `<span class="qt-han${con < 3600000 ? ' sap-het' : ''}" data-khung-dem-nguoc>${VN.bt('dong-ho', 'bt--nho')} còn <span class="so-deu" data-dem-nguoc="${d.hanThanhToan}">${VN.dinhDangDemNguoc(con)}</span></span>`;
  };

  /* ================= DANH SÁCH ================= */
  const ve = () => {
    const tat = qt.don.slice().sort((a, b) => new Date(b.ngayDat) - new Date(a.ngayDat));
    VN.$('#qt-dh-tab').innerHTML = TAB.map(([k, ten]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${k === tt.tab}">${ten}<span class="dem">${tat.filter((d) => hopTab(d, k)).length}</span></button>`).join('');
    const tu = VN.khongDau(tt.tim.trim());
    const ds = tat.filter((d) => hopTab(d, tt.tab) && (!tt.pt || d.thanhToan.phuongThuc === tt.pt)
      && (!tu || VN.khongDau([d.ma, d.nguoiNhan.hoTen, d.nguoiNhan.sdt, d.sdtKhach, qt.khach(d).ten].join(' ')).includes(tu)));
    const p = qt.phanTrang(ds, tt.trang, 15); tt.trang = p.trang;
    VN.$('#qt-dh-bang').innerHTML = ds.length ? `<thead><tr><th>Mã đơn</th><th>Khách hàng</th><th>Sản phẩm</th><th class="so">Tổng tiền</th><th>Thanh toán</th><th>Trạng thái</th><th></th></tr></thead>
      <tbody>${p.muc.map((d) => { const k = qt.khach(d); const sl = d.sanPham.reduce((a, x) => a + x.soLuong, 0); return `<tr${d.ma === tt.ma ? ' class="chon"' : ''}>
        <td><span class="ma">${VN.thoat(d.ma)}</span><small>${VN.ngayGio(d.ngayDat)}</small></td>
        <td>${VN.thoat(k.ten)}<small>${VN.thoat(k.sdt)}${k.coTaiKhoan ? '' : ' · không tài khoản'}</small></td>
        <td>${VN.thoat(d.sanPham[0].ten)}<small>${sl} sản phẩm${d.sanPham.length > 1 ? ` · ${d.sanPham.length} mẫu` : ''}</small></td>
        <td class="so">${VN.tien(d.tongTien)}</td>
        <td>${qt.nhanTT(d)}<small>${VN.thoat(VN.TEN_THANH_TOAN[d.thanhToan.phuongThuc])}</small>${hanHtml(d)}</td>
        <td>${qt.nhanDon(d)}</td>
        <td><button type="button" class="nut nut--vien nut--rat-nho" data-xem="${VN.thoat(d.ma)}">Xử lý</button></td></tr>`; }).join('')}</tbody>`
      : `<tbody><tr><td>${qt.trong('Không có đơn hàng phù hợp.')}</td></tr></tbody>`;
    VN.$('#qt-dh-trang').innerHTML = ds.length ? qt.htmlPhanTrang(p) : '';
  };

  /* ================= CHI TIẾT + THAO TÁC ================= */
  const nutThaoTac = (d) => {
    const n = [];
    const nut = (tac, bt, chu, lop = 'nut--chinh') => n.push(`<button type="button" class="nut ${lop} nut--nho" data-tac="${tac}">${bt ? VN.bt(bt) + ' ' : ''}${chu}</button>`);
    if (d.trangThai === 'Pending' && d.thanhToan.phuongThuc === 'BANK' && d.thanhToan.trangThai !== 'Success') nut('nhan-tien', 'qr', 'Xác nhận đã nhận tiền');
    if (d.trangThai === 'Pending' && !qt.chuaTra(d)) nut('xac-nhan', 'xac-nhan', 'Xác nhận đơn');
    if (d.trangThai === 'Confirmed' && !d.daBatDauCheTac) nut('che-tac', 'thuoc', 'Bắt đầu chế tác');
    if (d.trangThai === 'Confirmed') nut('giao', 'xe-giao', 'Bàn giao vận chuyển');
    if (d.trangThai === 'Shipping') nut('da-giao', 'xac-nhan', 'Giao thành công');
    const huyDuoc = d.trangThai === 'Pending' || (d.trangThai === 'Confirmed' && !d.daBatDauCheTac);
    if (huyDuoc) nut('huy', '', 'Hủy đơn', 'nut--vien nut-huy-don');
    const huy = huyDuoc ? `<form class="qt-form" data-form-huy hidden>
        <div class="truong"><label class="nhan-truong" for="qt-ly-do-huy">Lý do hủy (khách sẽ thấy)</label>
          <select class="o-chon" id="qt-ly-do-huy" name="lyDo"><option>Hết hàng mẫu / size khách chọn</option><option>Không liên hệ được khách để xác nhận đơn</option><option>Khách yêu cầu hủy qua hotline</option><option>Đơn trùng hoặc nghi ngờ đặt ảo</option></select></div>
        <div class="hang hang--quan"><button class="nut nut--nguy nut--nho" type="submit">Xác nhận hủy đơn</button><button class="nut nut--chu" type="button" data-bo-huy>Thôi</button></div></form>` : '';
    return n.length ? `<div class="qt-hanh-dong">${n.join('')}</div>${huy}` : '<p class="chu-nho chu-phu">Không còn thao tác cần làm với đơn này.</p>';
  };

  const veChiTiet = (d, moMoi = true) => {
    const ma = d.ma;
    tt.ma = ma;
    const k = qt.khach(d); const nn = d.nguoiNhan; const yc = d.yeuCauHuy;
    const pa = VN.hoTro.theoDon(d.ma); const dg = d.danhGia;
    const the = theBaoHanh.filter((t) => t.OrderCode === d.ma).map((t) => ({ ma: t.WarrantyCode }));
    const html = `
      <div class="qt-ct__muc"><div class="hang hang--quan">${qt.nhanDon(d)} ${qt.nhanTT(d)} ${hanHtml(d)}</div>${nutThaoTac(d)}
        ${d.trangThai === 'Pending' && qt.chuaTra(d) && d.thanhToan.phuongThuc !== 'BANK' ? `<p class="chu-nho chu-phu">Đơn chờ khách thanh toán qua cổng trực tuyến; quá ${VN.HAN_THANH_TOAN_PHUT} phút hệ thống tự hủy.</p>` : ''}</div>
      <div class="qt-ct__muc"><h3>Khách hàng</h3><dl class="qt-dl">
        <div><dt>Khách</dt><dd>${VN.thoat(k.ten)} ${k.coTaiKhoan ? '<span class="nhan nhan--ngoc nhan--tron">Có tài khoản</span>' : '<span class="nhan nhan--tron">Không tài khoản</span>'}</dd></div>
        <div><dt>Mã khách (SĐT)</dt><dd class="so-deu">${VN.thoat(d.sdtKhach || '')}</dd></div>
        ${k.email ? `<div><dt>Email</dt><dd>${VN.thoat(k.email)}</dd></div>` : ''}
        <div><dt>Người nhận</dt><dd>${VN.thoat(nn.hoTen)} · <span class="so-deu">${VN.thoat(nn.sdt)}</span></dd></div>
        <div><dt>Địa chỉ</dt><dd>${VN.thoat(VN.diaChiDay(nn))}</dd></div>
        <div><dt>Giao hàng</dt><dd>${VN.thoat(d.giaoHang.ten)}</dd></div>
        ${nn.ghiChu ? `<div><dt>Ghi chú của khách</dt><dd>${VN.thoat(nn.ghiChu)}</dd></div>` : ''}
      </dl></div>
      <div class="qt-ct__muc"><h3>Sản phẩm</h3>
        ${d.sanPham.map((s) => `<div class="qt-sp-nho"><img src="${VN.anh(s.anh)}" alt=""><span>${VN.thoat(s.ten)}<small>${[s.ma, s.mau, s.size ? 'Size ' + s.size : '', s.khacChu ? `Khắc “${s.khacChu}” (${TEN_KIEU[s.kieuChu] || 'Cổ điển'})` : ''].filter(Boolean).map(VN.thoat).join(' · ')}</small><small>${s.soLuong} × ${VN.tien(s.donGia)}</small></span></div>`).join('')}
        <dl class="qt-dl">
          <div><dt>Tạm tính</dt><dd class="so-deu">${VN.tien(d.tamTinh)}</dd></div>
          ${d.giamGia ? `<div><dt>Mã ${VN.thoat(d.maUuDai)}</dt><dd class="so-deu">−${VN.tien(d.giamGia)}</dd></div>` : ''}
          <div><dt>Phí giao</dt><dd class="so-deu">${d.phiGiao ? VN.tien(d.phiGiao) : 'Miễn phí'}</dd></div>
          <div><dt><strong>Tổng</strong></dt><dd class="so-deu"><strong>${VN.tien(d.tongTien)}</strong></dd></div>
        </dl></div>
      <div class="qt-ct__muc"><h3>Thanh toán</h3><dl class="qt-dl">
        <div><dt>Phương thức</dt><dd>${VN.thoat(VN.TEN_THANH_TOAN[d.thanhToan.phuongThuc])}</dd></div>
        <div><dt>Trạng thái</dt><dd>${qt.nhanTT(d)}</dd></div>
        ${d.thanhToan.maGiaoDich ? `<div><dt>Mã giao dịch</dt><dd class="so-deu">${VN.thoat(d.thanhToan.maGiaoDich)}</dd></div>` : ''}
        ${d.hanThanhToan && qt.chuaTra(d) ? `<div><dt>Hạn thanh toán</dt><dd>${VN.ngayGio(d.hanThanhToan)}</dd></div>` : ''}
        ${yc && yc.daHuy ? `<div><dt>Lý do hủy</dt><dd>${VN.thoat(yc.lyDo || '')}${yc.tuDong ? ' (tự động)' : ''}</dd></div>` : ''}
      </dl></div>
      ${the.length || dg || pa.length ? `<div class="qt-ct__muc"><h3>Hậu mãi</h3><dl class="qt-dl">
        ${the.length ? `<div><dt>Thẻ bảo hành</dt><dd>${the.map((t) => `<span class="so-deu">${VN.thoat(VN.soTheDep ? VN.soTheDep(t.ma) : t.ma)}</span>`).join('<br>')}</dd></div>` : ''}
        ${dg ? `<div><dt>Đánh giá</dt><dd>${'★'.repeat(dg.soSao)}${'☆'.repeat(5 - dg.soSao)} ${dg.noiDung ? '– “' + VN.thoat(dg.noiDung) + '”' : ''} <a class="lien-ket" href="${VN.url('qtDanhGia', { ma: dg.ma })}">Xem</a></dd></div>` : ''}
        ${pa.length ? `<div><dt>Phản ánh</dt><dd>${pa.map((x) => `<a class="lien-ket" href="${VN.url('qtPhanAnh', { ma: x.ma })}">${VN.thoat(x.ma)}</a> · ${VN.thoat(x.tenLoai)} <span class="nhan ${VN.TRANG_THAI_HO_TRO[x.trangThai].lop}">${VN.TRANG_THAI_HO_TRO[x.trangThai].ten}</span>`).join('<br>')}</dd></div>` : ''}
      </dl></div>` : ''}
      <div class="qt-ct__muc"><h3>Nhật ký đơn hàng</h3>${qt.nhatKy(d.lichSu)}</div>`;
    qt.moChiTiet(`Đơn ${d.ma}`, html, `Đặt ${VN.ngayGio(d.ngayDat)}`);
    if (moMoi) history.replaceState(null, '', VN.url('qtDonHang', Object.assign(tt.tab === 'tat-ca' ? {} : { tt: tt.tab }, { ma })));
    VN.$$('#qt-dh-bang tr').forEach((tr) => tr.classList.toggle('chon', !!VN.$(`[data-xem="${ma}"]`, tr)));
  };

  /** Lấy chi tiết một đơn từ máy chủ rồi mở ngăn chi tiết */
  const moDon = async (ma, moMoi = true) => {
    try {
      const d = await qt.napMotDon(ma);
      // Warranty cards are made by the database when an order is delivered, so only a delivered order has any
      if (d.trangThai === 'Delivered') theBaoHanh = await VN.api.get('/api/admin/warranties').catch(() => theBaoHanh);
      veChiTiet(d, moMoi);
    }
    catch (loi) { VN.thongBao({ tieuDe: 'Không mở được đơn ' + ma, noiDung: VN.thoat(loi.message), loai: 'loi' }); }
  };

  const thaoTac = async (tac) => {
    const ma = tt.ma; const d = qt.don.find((x) => x.ma === ma); if (!d) return;
    const goi = (duong, thanTin) => VN.api.post(`/api/admin/orders/${encodeURIComponent(ma)}/${duong}`, thanTin);
    let lam = null; let thanhCong = '';
    if (tac === 'nhan-tien') {
      const ok = await VN.xacNhan({ nhan: `Đơn ${ma}`, tieuDe: 'Xác nhận đã nhận tiền chuyển khoản?', noiDung: `Kiểm tra sao kê: số tiền <strong>${VN.tien(d.tongTien)}</strong>, nội dung <strong>${VN.thoat(ma)}</strong>.`, chuDongY: 'Đã nhận tiền' });
      if (ok) { lam = () => goi('confirm-payment'); thanhCong = 'Đã ghi nhận thanh toán'; }
    } else if (tac === 'xac-nhan') {
      const ok = await VN.xacNhan({ nhan: `Đơn ${ma}`, tieuDe: 'Xác nhận đơn hàng?', noiDung: 'Đơn chuyển sang Đã xác nhận. Khách vẫn hủy được cho đến khi cửa hàng bắt đầu chế tác.', chuDongY: 'Xác nhận đơn' });
      if (ok) { lam = () => goi('status', { status: 'Confirmed', reason: '' }); thanhCong = 'Đã xác nhận đơn'; }
    } else if (tac === 'che-tac') {
      const ok = await VN.xacNhan({ nhan: `Đơn ${ma}`, tieuDe: 'Bắt đầu chế tác đơn này?', noiDung: 'Sau bước này không ai hủy được đơn, kể cả qua hotline.', chuDongY: 'Bắt đầu chế tác' });
      if (ok) { lam = () => goi('start-production'); thanhCong = 'Đã ghi nhận bắt đầu chế tác'; }
    } else if (tac === 'giao') {
      const ok = await VN.xacNhan({ nhan: `Đơn ${ma}`, tieuDe: 'Bàn giao cho đơn vị vận chuyển?', noiDung: 'Sau bước này khách không thể tự hủy đơn trên website.', chuDongY: 'Bàn giao' });
      if (ok) { lam = () => goi('status', { status: 'Shipping', reason: '' }); thanhCong = 'Đơn đã chuyển sang Đang giao'; }
    } else if (tac === 'da-giao') {
      const ok = await VN.xacNhan({ nhan: `Đơn ${ma}`, tieuDe: 'Đơn vị vận chuyển đã giao thành công?', noiDung: `Đơn chuyển sang Đã nhận${d.thanhToan.phuongThuc === 'COD' ? ', ghi nhận đã thu tiền COD' : ''} và kích hoạt thẻ bảo hành cho từng sản phẩm.`, chuDongY: 'Giao thành công' });
      if (ok) { lam = () => goi('status', { status: 'Delivered', reason: '' }); thanhCong = 'Đã giao thành công, thẻ bảo hành đã kích hoạt'; }
    } else if (tac === 'huy') {
      const f = VN.$('.qt-ct [data-form-huy]'); if (f) { f.hidden = false; f.lyDo.focus(); }
      return;
    }
    if (lam) await lamVaTai(lam, thanhCong);
  };

  /** Gọi API, báo kết quả, rồi tải lại danh sách (sự kiện don-hang vẽ lại danh sách và ngăn chi tiết) */
  const lamVaTai = async (lam, thanhCong) => {
    await qt.lam(lam, thanhCong);
    await qt.napDon().catch(qt.baoLoiTai);
  };

  /* ================= SỰ KIỆN ================= */
  VN.$('#qt-dh-tab').addEventListener('click', (e) => { const b = e.target.closest('[data-tab]'); if (!b) return; tt.tab = b.dataset.tab; tt.trang = 1; ve(); });
  VN.$('#qt-dh-tt').addEventListener('change', (e) => { tt.pt = e.target.value; tt.trang = 1; ve(); });
  VN.$('#qt-dh-tim').addEventListener('input', VN.chongDoi((e) => { tt.tim = e.target.value; tt.trang = 1; ve(); }, 150));
  VN.$('#qt-dh-trang').addEventListener('click', (e) => { const b = e.target.closest('[data-trang]'); if (b) { tt.trang = Number(b.dataset.trang); ve(); } });
  VN.$('#qt-dh-bang').addEventListener('click', (e) => { const b = e.target.closest('[data-xem]'); if (b) moDon(b.dataset.xem); });
  document.addEventListener('click', (e) => { const b = e.target.closest('.qt-ct [data-tac]'); if (b) thaoTac(b.dataset.tac); });
  document.addEventListener('click', (e) => { if (e.target.closest('[data-bo-huy]')) VN.$('.qt-ct [data-form-huy]').hidden = true; });
  document.addEventListener('submit', (e) => {
    const fh = e.target.closest('[data-form-huy]');
    if (!fh) return;
    e.preventDefault();
    const ma = tt.ma;
    lamVaTai(() => VN.api.post(`/api/admin/orders/${encodeURIComponent(ma)}/status`, { status: 'Cancelled', reason: fh.lyDo.value }), 'Đã hủy đơn');
  });
  document.addEventListener('close', (e) => { if (e.target.classList && e.target.classList.contains('qt-ct')) { tt.ma = ''; history.replaceState(null, '', VN.url('qtDonHang', tt.tab === 'tat-ca' ? {} : { tt: tt.tab })); VN.$$('#qt-dh-bang tr.chon').forEach((tr) => tr.classList.remove('chon')); } }, true);
  // Danh sách vừa tải lại (sau một thao tác, hoặc đồng hồ đếm ngược về 0) -> vẽ lại; ngăn chi tiết đang mở thì lấy lại bản mới
  window.addEventListener('vinora:don-hang', VN.chongDoi(() => { ve(); if (qt.dangMoChiTiet() && tt.ma) moDon(tt.ma, false); }, 80));

  VN.$('#qt-dh-bang').innerHTML = `<tbody><tr><td>${qt.trong('Đang tải đơn hàng…')}</td></tr></tbody>`;
  qt.sanSang.then(() => { ve(); if (tt.ma) moDon(tt.ma, false); });
})();
