/* =====================================================================
   QUẢN TRỊ – ĐƠN HÀNG
   - Lọc theo trạng thái / phương thức thanh toán, tìm theo mã đơn, tên, số điện thoại
   - Ngăn chi tiết (?ma=): khách, sản phẩm, tiền, thanh toán, hoàn tiền, phản ánh, nhật ký, ghi chú nội bộ
   - Thao tác: xác nhận đã nhận tiền chuyển khoản · xác nhận & giao hàng · giao thành công (kích hoạt bảo hành)
     · hủy đơn chưa thanh toán · xác nhận đã chuyển khoản hoàn tiền
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-dh-bang')) return;
  const TAB = [['tat-ca', 'Tất cả'], ['Pending', 'Chờ xử lý'], ['Shipping', 'Đang giao'], ['Delivered', 'Đã nhận'], ['Cancelled', 'Đã hủy'], ['hoan-tien', 'Chờ hoàn tiền']];
  const tt = { tab: VN.thamSo('tt') || 'tat-ca', pt: '', tim: '', trang: 1, ma: VN.thamSo('ma') || '' };
  if (!TAB.some(([k]) => k === tt.tab)) tt.tab = 'tat-ca';
  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };

  const hopTab = (d, k) => (k === 'tat-ca' ? true : k === 'hoan-tien' ? d.thanhToan.trangThai === 'RefundPending' : d.trangThai === k);
  const hanHtml = (d) => {
    if (!qt.chuaTra(d) || !d.hanThanhToan) return '';
    const con = VN.donHang.conLaiThanhToan(d);
    return `<span class="qt-han${con < 3600000 ? ' sap-het' : ''}" data-khung-dem-nguoc>${VN.bt('dong-ho', 'bt--nho')} còn <span class="so-deu" data-dem-nguoc="${d.hanThanhToan}">${VN.dinhDangDemNguoc(con)}</span></span>`;
  };

  /* ================= DANH SÁCH ================= */
  const ve = () => {
    VN.donHang.tuHuyQuaHan();
    const tat = VN.donHang.tatCa().sort((a, b) => new Date(b.ngayDat) - new Date(a.ngayDat));
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
    if (qt.dangMoChiTiet() && tt.ma) veChiTiet(tt.ma, false);
  };

  /* ================= CHI TIẾT + THAO TÁC ================= */
  const nutThaoTac = (d) => {
    const n = [];
    if (d.trangThai === 'Pending' && d.thanhToan.phuongThuc === 'BANK' && d.thanhToan.trangThai !== 'Success') n.push(`<button type="button" class="nut nut--chinh nut--nho" data-tac="nhan-tien">${VN.bt('qr')} Xác nhận đã nhận tiền</button>`);
    if (d.trangThai === 'Pending' && !qt.chuaTra(d)) n.push(`<button type="button" class="nut nut--chinh nut--nho" data-tac="giao">${VN.bt('xe-giao')} Xác nhận &amp; giao hàng</button>`);
    if (d.trangThai === 'Shipping') n.push(`<button type="button" class="nut nut--chinh nut--nho" data-tac="da-giao">${VN.bt('xac-nhan')} Giao thành công</button>`);
    if (d.thanhToan.trangThai === 'RefundPending') n.push(`<button type="button" class="nut nut--chinh nut--nho" data-tac="hoan-tien">${VN.bt('doi-tra')} Đã chuyển khoản hoàn tiền</button>`);
    if (d.trangThai === 'Pending' && d.thanhToan.trangThai !== 'Success') n.push(`<button type="button" class="nut nut--vien nut--nho nut-huy-don" data-tac="huy">Hủy đơn</button>`);
    const huy = d.trangThai === 'Pending' && d.thanhToan.trangThai !== 'Success' ? `<form class="qt-form" data-form-huy hidden>
        <div class="truong"><label class="nhan-truong" for="qt-ly-do-huy">Lý do hủy (khách sẽ thấy)</label>
          <select class="o-chon" id="qt-ly-do-huy" name="lyDo"><option>Hết hàng mẫu / size khách chọn</option><option>Không liên hệ được khách để xác nhận đơn</option><option>Khách yêu cầu hủy qua hotline</option><option>Đơn trùng hoặc nghi ngờ đặt ảo</option></select></div>
        <div class="hang hang--quan"><button class="nut nut--nguy nut--nho" type="submit">Xác nhận hủy đơn</button><button class="nut nut--chu" type="button" data-bo-huy>Thôi</button></div></form>` : '';
    return n.length ? `<div class="qt-hanh-dong">${n.join('')}</div>${huy}` : '<p class="chu-nho chu-phu">Không còn thao tác cần làm với đơn này.</p>';
  };

  const veChiTiet = (ma, moMoi = true) => {
    const d = VN.donHang.tatCa().find((x) => x.ma === ma);
    if (!d) { VN.thongBao({ tieuDe: 'Không tìm thấy đơn ' + ma, loai: 'loi' }); return; }
    tt.ma = ma;
    const k = qt.khach(d); const nn = d.nguoiNhan; const ht = d.hoanTien; const yc = d.yeuCauHuy;
    const pa = VN.hoTro.theoDon(d.ma); const dg = VN.danhGia.theoDon(d.ma); const the = VN.baoHanh.theoDon(d.ma);
    const html = `
      <div class="qt-ct__muc"><div class="hang hang--quan">${qt.nhanDon(d)} ${qt.nhanTT(d)} ${hanHtml(d)}</div>${nutThaoTac(d)}
        ${d.trangThai === 'Pending' && qt.chuaTra(d) && d.thanhToan.phuongThuc !== 'BANK' ? '<p class="chu-nho chu-phu">Đơn chờ khách thanh toán qua cổng trực tuyến; quá hạn 24 giờ hệ thống tự hủy.</p>' : ''}</div>
      <div class="qt-ct__muc"><h3>Khách hàng</h3><dl class="qt-dl">
        <div><dt>Khách</dt><dd>${VN.thoat(k.ten)} ${k.coTaiKhoan ? '<span class="nhan nhan--ngoc nhan--tron">Có tài khoản</span>' : '<span class="nhan nhan--tron">Không tài khoản</span>'}</dd></div>
        <div><dt>Mã khách (SĐT)</dt><dd class="so-deu">${VN.thoat(d.sdtKhach || '')}</dd></div>
        ${k.email ? `<div><dt>Email</dt><dd>${VN.thoat(k.email)}</dd></div>` : ''}
        <div><dt>Người nhận</dt><dd>${VN.thoat(nn.hoTen)} · <span class="so-deu">${VN.thoat(nn.sdt)}</span></dd></div>
        <div><dt>Địa chỉ</dt><dd>${VN.thoat(VN.diaChiDay(nn))}</dd></div>
        <div><dt>Giao hàng</dt><dd>${VN.thoat(d.giaoHang.ten)}</dd></div>
        ${nn.ghiChu ? `<div><dt>Ghi chú giao</dt><dd>${VN.thoat(nn.ghiChu)}</dd></div>` : ''}
        ${d.goiQua ? `<div><dt>Quà tặng</dt><dd>Gói quà${d.loiNhan ? ` · Thiệp: “${VN.thoat(d.loiNhan)}”` : ''}</dd></div>` : ''}
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
        ${ht ? `<div><dt>Hoàn tiền</dt><dd><strong>${VN.tien(ht.soTien)}</strong> → ${VN.thoat(ht.nganHang)} <span class="so-deu">${VN.thoat(ht.soTaiKhoan)}</span><br>${VN.thoat(ht.chuTaiKhoan)}${ht.luc ? `<br><small class="chu-phu">Đã chuyển ${VN.ngayGio(ht.luc)}</small>` : ''}</dd></div>` : ''}
        ${yc && yc.daHuy ? `<div><dt>Lý do hủy</dt><dd>${VN.thoat(yc.lyDo || '')}${yc.ghiChu ? ' – ' + VN.thoat(yc.ghiChu) : ''}${yc.boiCuaHang ? ' (cửa hàng hủy)' : yc.tuDong ? ' (tự động)' : ' (khách hủy)'}</dd></div>` : ''}
      </dl></div>
      ${the.length || dg || pa.length ? `<div class="qt-ct__muc"><h3>Hậu mãi</h3><dl class="qt-dl">
        ${the.length ? `<div><dt>Thẻ bảo hành</dt><dd>${the.map((t) => `<span class="so-deu">${VN.thoat(VN.soTheDep ? VN.soTheDep(t.ma) : t.ma)}</span>`).join('<br>')}</dd></div>` : ''}
        ${dg ? `<div><dt>Đánh giá</dt><dd>${'★'.repeat(dg.soSao)}${'☆'.repeat(5 - dg.soSao)} ${dg.noiDung ? '– “' + VN.thoat(dg.noiDung) + '”' : ''} <a class="lien-ket" href="${VN.url('qtDanhGia', { ma: dg.ma })}">Xem</a></dd></div>` : ''}
        ${pa.length ? `<div><dt>Phản ánh</dt><dd>${pa.map((x) => `<a class="lien-ket" href="${VN.url('qtPhanAnh', { ma: x.ma })}">${VN.thoat(x.ma)}</a> · ${VN.thoat(x.tenLoai)} <span class="nhan ${VN.TRANG_THAI_HO_TRO[x.trangThai].lop}">${VN.TRANG_THAI_HO_TRO[x.trangThai].ten}</span>`).join('<br>')}</dd></div>` : ''}
      </dl></div>` : ''}
      <div class="qt-ct__muc"><h3>Ghi chú nội bộ</h3>
        ${(d.ghiChuNoiBo || []).map((g) => `<p class="qt-ghi-chu">${VN.thoat(g.noiDung)}<small>${VN.ngayGio(g.luc)} · ${VN.thoat(g.boi)}</small></p>`).join('') || '<p class="chu-nho chu-phu">Chưa có ghi chú. Khách hàng không nhìn thấy ghi chú nội bộ.</p>'}
        <form class="o-nhap-kem-nut" data-ghi-chu><label class="an-chu" for="qt-ghi-chu">Ghi chú nội bộ</label><input class="o-nhap" id="qt-ghi-chu" name="noiDung" maxlength="200" placeholder="Ví dụ: Khách hẹn giao sau 18h"><button class="nut nut--vien nut--nho" type="submit">Lưu</button></form>
      </div>
      <div class="qt-ct__muc"><h3>Nhật ký đơn hàng</h3>${qt.nhatKy(d.lichSu)}</div>`;
    qt.moChiTiet(`Đơn ${d.ma}`, html, `Đặt ${VN.ngayGio(d.ngayDat)}`);
    if (moMoi) history.replaceState(null, '', VN.url('qtDonHang', Object.assign(tt.tab === 'tat-ca' ? {} : { tt: tt.tab }, { ma })));
    VN.$$('#qt-dh-bang tr').forEach((tr) => tr.classList.toggle('chon', !!VN.$(`[data-xem="${ma}"]`, tr)));
  };

  const thaoTac = async (tac) => {
    const ma = tt.ma; const d = VN.donHang.tatCa().find((x) => x.ma === ma); if (!d) return;
    if (tac === 'nhan-tien') {
      const ok = await VN.xacNhan({ nhan: `Đơn ${ma}`, tieuDe: 'Xác nhận đã nhận tiền chuyển khoản?', noiDung: `Kiểm tra sao kê: số tiền <strong>${VN.tien(d.tongTien)}</strong>, nội dung <strong>${VN.thoat(ma)}</strong>.`, chuDongY: 'Đã nhận tiền' });
      if (ok) qt.lam(() => VN.donHang.xacNhanChuyenKhoan(ma, qt.boi('Kế toán')), 'Đã ghi nhận thanh toán');
    } else if (tac === 'giao') {
      const ok = await VN.xacNhan({ nhan: `Đơn ${ma}`, tieuDe: 'Xác nhận đơn và bàn giao vận chuyển?', noiDung: 'Sau bước này khách không thể tự hủy đơn trên website.', chuDongY: 'Giao hàng' });
      if (ok) qt.lam(() => VN.donHang.giaoHang(ma, qt.boi('Cửa hàng')), 'Đơn đã chuyển sang Đang giao');
    } else if (tac === 'da-giao') {
      const ok = await VN.xacNhan({ nhan: `Đơn ${ma}`, tieuDe: 'Đơn vị vận chuyển đã giao thành công?', noiDung: `Đơn chuyển sang Đã nhận${d.thanhToan.phuongThuc === 'COD' ? ', ghi nhận đã thu tiền COD' : ''} và kích hoạt thẻ bảo hành cho từng sản phẩm.`, chuDongY: 'Giao thành công' });
      if (ok) qt.lam(() => VN.donHang.xacNhanDaNhan(ma, qt.boi('Vận chuyển')), 'Đã giao thành công, thẻ bảo hành đã kích hoạt');
    } else if (tac === 'hoan-tien') {
      const h = d.hoanTien;
      const ok = await VN.xacNhan({ nhan: `Đơn ${ma}`, tieuDe: 'Đã chuyển khoản hoàn tiền cho khách?', noiDung: `${VN.tien(h.soTien)} → ${VN.thoat(h.nganHang)} ${VN.thoat(h.soTaiKhoan)} (${VN.thoat(h.chuTaiKhoan)}).`, chuDongY: 'Đã hoàn tiền' });
      if (ok) qt.lam(() => VN.donHang.hoanTienXong(ma, qt.boi('Kế toán')), 'Đã cập nhật hoàn tiền');
    } else if (tac === 'huy') {
      const f = VN.$('.qt-ct [data-form-huy]'); if (f) { f.hidden = false; f.lyDo.focus(); }
      return;
    }
    ve(); veChiTiet(ma, false);
  };

  /* ================= SỰ KIỆN ================= */
  VN.$('#qt-dh-tab').addEventListener('click', (e) => { const b = e.target.closest('[data-tab]'); if (!b) return; tt.tab = b.dataset.tab; tt.trang = 1; ve(); });
  VN.$('#qt-dh-tt').addEventListener('change', (e) => { tt.pt = e.target.value; tt.trang = 1; ve(); });
  VN.$('#qt-dh-tim').addEventListener('input', VN.chongDoi((e) => { tt.tim = e.target.value; tt.trang = 1; ve(); }, 150));
  VN.$('#qt-dh-trang').addEventListener('click', (e) => { const b = e.target.closest('[data-trang]'); if (b) { tt.trang = Number(b.dataset.trang); ve(); } });
  VN.$('#qt-dh-bang').addEventListener('click', (e) => { const b = e.target.closest('[data-xem]'); if (b) veChiTiet(b.dataset.xem); });
  document.addEventListener('click', (e) => { const b = e.target.closest('.qt-ct [data-tac]'); if (b) thaoTac(b.dataset.tac); });
  document.addEventListener('click', (e) => { if (e.target.closest('[data-bo-huy]')) VN.$('.qt-ct [data-form-huy]').hidden = true; });
  document.addEventListener('submit', (e) => {
    const fh = e.target.closest('[data-form-huy]');
    if (fh) {
      e.preventDefault();
      qt.lam(() => VN.donHang.huyBoiCuaHang(tt.ma, fh.lyDo.value, qt.boi('Cửa hàng')), 'Đã hủy đơn');
      ve(); veChiTiet(tt.ma, false); return;
    }
    const f = e.target.closest('[data-ghi-chu]'); if (!f) return;
    e.preventDefault();
    if (!f.noiDung.value.trim()) return;
    qt.lam(() => VN.donHang.ghiChuNoiBo(tt.ma, f.noiDung.value.trim(), qt.nguoi.hoTen), 'Đã lưu ghi chú');
    veChiTiet(tt.ma, false);
  });
  document.addEventListener('close', (e) => { if (e.target.classList && e.target.classList.contains('qt-ct')) { tt.ma = ''; history.replaceState(null, '', VN.url('qtDonHang', tt.tab === 'tat-ca' ? {} : { tt: tt.tab })); VN.$$('#qt-dh-bang tr.chon').forEach((tr) => tr.classList.remove('chon')); } }, true);
  // Khách đặt hàng / hủy / phản ánh ở thẻ khác -> cập nhật; đơn hết hạn thanh toán -> vẽ lại
  window.addEventListener('storage', VN.chongDoi((e) => { if (/^vinora\.(donHang|hoTro|danhGia|baoHanh)$/.test(e.key || '')) ve(); }, 120));
  window.addEventListener('vinora:don-hang', VN.chongDoi(ve, 80));

  ve();
  if (tt.ma) veChiTiet(tt.ma, false);
})();
