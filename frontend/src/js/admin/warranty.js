/* =====================================================================
   QUẢN TRỊ – BẢO HÀNH & LỊCH HẸN
   - Lịch hẹn: showroom xác nhận -> hoàn tất dịch vụ (trừ lượt với dịch vụ có giới hạn, cập nhật size sau
     khi chỉnh size) hoặc hủy kèm lý do (không mất lượt)
   - Thẻ bảo hành: tra cứu toàn bộ thẻ, chủ thẻ, lượt dịch vụ đã dùng
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-bh-bang')) return;
  const tt = { khu: VN.thamSo('khu') === 'the' ? 'the' : 'lich', loc: 'mo', tim: '', ch: null };
  const nhanLich = (l) => { const t = VN.TRANG_THAI_LICH[l.trangThai]; return `<span class="nhan ${t.lop}">${t.ten}</span>`; };

  const ve = () => {
    VN.$$('#qt-bh-tab [data-khu]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.khu === tt.khu)));
    VN.$('#qt-bh-loc').hidden = tt.khu !== 'lich';
    const lich = VN.lichHen.tatCa(); const the = VN.baoHanh.tatCa();
    VN.$('[data-dem-khu="lich"]').textContent = lich.filter((l) => l.trangThai === 'Pending').length || '';
    VN.$('[data-dem-khu="the"]').textContent = the.length;
    const tu = VN.khongDau(tt.tim);
    if (tt.khu === 'lich') {
      const ds = lich.filter((l) => (tt.loc === 'mo' ? ['Pending', 'Confirmed'].includes(l.trangThai) : !tt.loc || l.trangThai === tt.loc))
        .filter((l) => { const t = VN.baoHanh.lay(l.maBaoHanh) || {}; return !tu || VN.khongDau([l.ma, l.maBaoHanh, t.tenSP, l.sdt, l.tenCuaHang].join(' ')).includes(tu); })
        .sort((a, b) => (a.ngayHen + a.khungGio).localeCompare(b.ngayHen + b.khungGio) * (tt.loc === 'mo' || tt.loc === 'Pending' || tt.loc === 'Confirmed' ? 1 : -1));
      VN.$('#qt-bh-bang').innerHTML = ds.length ? `<thead><tr><th>Lịch hẹn</th><th>Ngày giờ</th><th>Showroom</th><th>Dịch vụ</th><th>Khách</th><th>Trạng thái</th><th>Thao tác</th></tr></thead><tbody>${ds.map((l) => {
        const t = VN.baoHanh.lay(l.maBaoHanh) || {};
        const nut = [];
        if (l.trangThai === 'Pending') nut.push(`<button type="button" class="nut nut--chinh nut--rat-nho" data-lich="Confirmed" data-ma="${l.ma}">Xác nhận</button>`);
        if (l.trangThai === 'Confirmed') nut.push(`<button type="button" class="nut nut--chinh nut--rat-nho" data-lich="Completed" data-ma="${l.ma}">Hoàn tất</button>`);
        if (['Pending', 'Confirmed'].includes(l.trangThai)) nut.push(`<button type="button" class="nut nut--chu nut-huy-don" data-lich="Cancelled" data-ma="${l.ma}">Hủy</button>`);
        nut.push(`<button type="button" class="nut nut--chu" data-xem-lich="${l.ma}">Chi tiết</button>`);
        return `<tr><td class="ma">${VN.thoat(l.ma)}<small>Gửi ${VN.ngayGio(l.taoLuc)}</small></td>
          <td>${VN.thu(l.ngayHen + 'T00:00')}, ${VN.ngay(l.ngayHen + 'T00:00')}<small>${VN.thoat(l.khungGio)}</small></td>
          <td>${VN.thoat(l.tenCuaHang)}</td>
          <td>${VN.thoat(VN.TEN_DICH_VU[l.loai] || l.loai)}${l.sizeMoi ? ` → size ${l.sizeMoi}` : ''}<small>${VN.thoat(t.tenSP || '')}</small></td>
          <td>${VN.thoat(qt.tenKhachTheoId(l.khachHang, l.sdt))}<small class="so-deu">${VN.thoat(l.sdt || '')}</small></td>
          <td>${nhanLich(l)}</td><td><div class="qt-hanh-dong">${nut.join('')}</div></td></tr>`;
      }).join('')}</tbody>` : `<tbody><tr><td>${qt.trong('Không có lịch hẹn phù hợp.')}</td></tr></tbody>`;
    } else {
      const ds = the.filter((t) => !tu || VN.khongDau([t.ma, t.tenSP, t.maSP, t.donHang, t.sdtKhach].join(' ')).includes(tu)).sort((a, b) => new Date(b.ngayKichHoat) - new Date(a.ngayKichHoat));
      VN.$('#qt-bh-bang').innerHTML = ds.length ? `<thead><tr><th>Mã thẻ</th><th>Sản phẩm</th><th>Chủ thẻ</th><th>Đơn hàng</th><th>Kích hoạt</th><th>Đã dùng</th><th></th></tr></thead><tbody>${ds.map((t) => `<tr>
        <td class="ma so-deu">${VN.soTheDep(t.ma)}</td>
        <td><span class="qt-sp-nho"><img src="${VN.anh(t.anh)}" alt=""><span>${VN.thoat(t.tenSP)}<small>${VN.thoat(t.maSP)}${t.size ? ' · Size ' + t.size : ''}</small></span></span></td>
        <td>${VN.thoat(qt.tenKhachTheoId(t.khachHang, t.sdtKhach))}<small class="so-deu">${VN.thoat(t.sdtKhach || '')}</small></td>
        <td><a class="lien-ket" href="${VN.url('qtDonHang', { ma: t.donHang })}">${VN.thoat(t.donHang)}</a></td>
        <td>${VN.ngay(t.ngayKichHoat)}</td>
        <td>${Object.entries(t.daDung).filter(([, n]) => n).map(([k, n]) => `${VN.thoat(VN.TEN_DICH_VU[k] || k)}: ${n}`).join('<br>') || '<span class="chu-phu">Chưa dùng</span>'}</td>
        <td><button type="button" class="nut nut--chu" data-xem-the="${t.ma}">Chi tiết</button></td></tr>`).join('')}</tbody>` : `<tbody><tr><td>${qt.trong('Chưa có thẻ bảo hành nào.')}</td></tr></tbody>`;
    }
  };

  const capNhatLich = async (ma, trangThai) => {
    const l = VN.lichHen.tatCa().find((x) => x.ma === ma); if (!l) return;
    const ql = tt.ch.baoHanh.quyenLoi.find((q) => q.ma === l.loai); const gioiHan = ql && ql.luot !== null;
    if (trangThai === 'Confirmed') {
      qt.lam(() => VN.lichHen.capNhat(ma, 'Confirmed', `Showroom ${l.tenCuaHang} xác nhận lịch hẹn ${VN.ngay(l.ngayHen + 'T00:00')} lúc ${l.khungGio}.`, qt.boi('Showroom')), 'Đã xác nhận lịch hẹn');
    } else if (trangThai === 'Completed') {
      const ok = await VN.xacNhan({ nhan: 'Lịch hẹn ' + ma, tieuDe: 'Dịch vụ đã hoàn tất?', noiDung: `${VN.TEN_DICH_VU[l.loai]}${gioiHan ? ' – thẻ sẽ bị trừ 1 lượt.' : ' – dịch vụ trọn đời, không trừ lượt.'}${l.loai === 'Resizing' && l.sizeMoi ? ` Size trên thẻ đổi thành ${l.sizeMoi}.` : ''}`, chuDongY: 'Hoàn tất' });
      if (ok) qt.lam(() => VN.lichHen.capNhat(ma, 'Completed', `Hoàn tất ${VN.TEN_DICH_VU[l.loai]} tại ${l.tenCuaHang}.`, qt.boi('Showroom')), 'Đã hoàn tất dịch vụ');
    } else if (trangThai === 'Cancelled') {
      const ok = await VN.xacNhan({ nhan: 'Lịch hẹn ' + ma, tieuDe: 'Hủy lịch hẹn này?', noiDung: 'Hãy gọi báo khách trước khi hủy. Khách không bị mất lượt dịch vụ.', chuDongY: 'Hủy lịch', nguy: true });
      if (ok) qt.lam(() => VN.lichHen.capNhat(ma, 'Cancelled', `Showroom ${l.tenCuaHang} hủy lịch hẹn và đã liên hệ khách để hẹn lại.`, qt.boi('Showroom')), 'Đã hủy lịch hẹn');
    }
    ve();
  };

  const xemLich = (ma) => {
    const l = VN.lichHen.tatCa().find((x) => x.ma === ma); if (!l) return;
    const t = VN.baoHanh.lay(l.maBaoHanh) || {};
    qt.moChiTiet(`Lịch hẹn ${l.ma}`, `<div class="qt-ct__muc"><div>${nhanLich(l)}</div><dl class="qt-dl">
      <div><dt>Dịch vụ</dt><dd>${VN.thoat(VN.TEN_DICH_VU[l.loai] || l.loai)}${l.sizeMoi ? ` (size ${t.size || '?'} → ${l.sizeMoi})` : ''}</dd></div>
      <div><dt>Thời gian</dt><dd>${VN.thu(l.ngayHen + 'T00:00')}, ${VN.ngay(l.ngayHen + 'T00:00')} · ${VN.thoat(l.khungGio)}</dd></div>
      <div><dt>Showroom</dt><dd>${VN.thoat(l.tenCuaHang)}</dd></div>
      <div><dt>Thẻ</dt><dd class="so-deu">${VN.soTheDep(l.maBaoHanh)} · ${VN.thoat(t.tenSP || '')}</dd></div>
      <div><dt>Khách</dt><dd>${VN.thoat(qt.tenKhachTheoId(l.khachHang, l.sdt))} · <span class="so-deu">${VN.thoat(l.sdt || '')}</span></dd></div>
      ${l.ghiChu ? `<div><dt>Ghi chú</dt><dd>“${VN.thoat(l.ghiChu)}”</dd></div>` : ''}
      ${l.soAnh ? `<div><dt>Ảnh tình trạng</dt><dd>${l.soAnh} ảnh</dd></div>` : ''}
      </dl></div><div class="qt-ct__muc"><h3>Lịch sử</h3>${qt.nhatKy(l.lichSu)}</div>`, 'Lịch hẹn hậu mãi');
  };
  const xemThe = (ma) => {
    const t = VN.baoHanh.lay(ma); if (!t) return;
    const chu = qt.tenKhachTheoId(t.khachHang, t.sdtKhach);
    qt.moChiTiet(`Thẻ ${VN.soTheDep(t.ma)}`, `<div class="qt-ct__muc">${VN.htmlTheBaoHanh(t, tt.ch, chu)}</div>
      <div class="qt-ct__muc"><h3>Quyền lợi</h3><dl class="qt-dl">${tt.ch.baoHanh.quyenLoi.map((q) => `<div><dt>${VN.thoat(q.ten)}</dt><dd>Đã dùng ${t.daDung[q.ma] || 0}${q.luot === null ? ' · không giới hạn' : ` / ${q.luot} lượt`}${q.chiChoNhan && !t.laNhan ? ' (chỉ cho nhẫn)' : ''}</dd></div>`).join('')}</dl></div>
      <div class="qt-ct__muc"><h3>Lịch sử dịch vụ</h3>${t.lichSuDichVu.length ? `<ol class="nhat-ky-qt">${t.lichSuDichVu.slice().reverse().map((x) => `<li><time>${VN.ngay(x.luc)}</time><div>${VN.thoat(x.noiDung)}<small>${VN.thoat(x.maLich || '')}</small></div></li>`).join('')}</ol>` : '<p class="chu-nho chu-phu">Chưa có dịch vụ nào.</p>'}</div>`, `Đơn ${t.donHang}`);
  };

  VN.$('#qt-bh-tab').addEventListener('click', (e) => { const b = e.target.closest('[data-khu]'); if (b) { tt.khu = b.dataset.khu; ve(); } });
  VN.$('#qt-bh-loc').addEventListener('change', (e) => { tt.loc = e.target.value; ve(); });
  VN.$('#qt-bh-tim').addEventListener('input', VN.chongDoi((e) => { tt.tim = e.target.value; ve(); }, 150));
  VN.$('#qt-bh-bang').addEventListener('click', (e) => {
    const b = e.target.closest('[data-lich]'); if (b) { capNhatLich(b.dataset.ma, b.dataset.lich); return; }
    const l = e.target.closest('[data-xem-lich]'); if (l) { xemLich(l.dataset.xemLich); return; }
    const t = e.target.closest('[data-xem-the]'); if (t) xemThe(t.dataset.xemThe);
  });
  window.addEventListener('storage', VN.chongDoi((e) => { if (/^vinora\.(lichHen|baoHanh)$/.test(e.key || '')) ve(); }, 120));
  VN.duLieu.cauHinh().then((ch) => { tt.ch = ch; ve(); });
})();
