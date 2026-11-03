/* =====================================================================
   QUẢN TRỊ – BẢO HÀNH & LỊCH HẸN (nối API /api/admin/services và /api/admin/warranties)
   - Lịch hẹn: xác nhận giờ khách chọn hoặc đề xuất giờ khác -> hoàn tất dịch vụ (máy chủ trừ lượt của thẻ,
     miễn phí hay tính phí tùy lượt còn lại) hoặc hủy (khách không mất lượt)
   - Thẻ bảo hành: tất cả thẻ, chủ thẻ, lượt dịch vụ đã dùng
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-bh-bang')) return;
  const tt = { khu: VN.thamSo('khu') === 'the' ? 'the' : 'lich', loc: 'mo', tim: '', the: [] };
  const MO = ['Pending', 'Confirmed', 'Rescheduled'];          // lịch hẹn chưa hoàn tất, chưa hủy
  const nhanLich = (l) => { const t = VN.TRANG_THAI_LICH[l.Status]; return `<span class="nhan ${t.lop}">${t.ten}</span>`; };
  const gio = (l) => l.AppointmentDate || l.PreferredDate;
  const dichVu = (l) => `${VN.thoat(VN.TEN_DICH_VU[l.ServiceType] || l.ServiceType)}${l.NewRingSize ? ` → size ${l.NewRingSize}` : ''}`;
  const khach = (x) => `${VN.thoat(x.CustomerName)}<small class="so-deu">${VN.thoat(x.CustomerPhone || '')}</small>`;

  const ve = () => {
    VN.$$('#qt-bh-tab [data-khu]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.khu === tt.khu)));
    VN.$('#qt-bh-loc').hidden = tt.khu !== 'lich';
    const lich = qt.lich; const the = tt.the;
    VN.$('[data-dem-khu="lich"]').textContent = lich.filter((l) => l.Status === 'Pending').length || '';
    VN.$('[data-dem-khu="the"]').textContent = the.length;
    const tu = VN.khongDau(tt.tim);
    if (tt.khu === 'lich') {
      const dangMo = tt.loc === 'mo' || tt.loc === 'Pending' || tt.loc === 'Confirmed' || tt.loc === 'Rescheduled';
      const ds = lich.filter((l) => (tt.loc === 'mo' ? MO.includes(l.Status) : !tt.loc || l.Status === tt.loc))
        .filter((l) => !tu || VN.khongDau([l.ServiceID, l.WarrantyCode, l.ProductName, l.CustomerPhone, l.CustomerName].join(' ')).includes(tu))
        .sort((a, b) => (gio(a) || '').localeCompare(gio(b) || '') * (dangMo ? 1 : -1));
      VN.$('#qt-bh-bang').innerHTML = ds.length ? `<thead><tr><th>Lịch hẹn</th><th>Ngày giờ</th><th>Dịch vụ</th><th>Khách</th><th>Trạng thái</th><th>Thao tác</th></tr></thead><tbody>${ds.map((l) => {
        const nut = [];
        if (l.Status === 'Pending') nut.push(`<button type="button" class="nut nut--chinh nut--rat-nho" data-lich="schedule" data-ma="${l.ServiceID}">Xác nhận</button>`);
        if (l.Status === 'Confirmed' || l.Status === 'Rescheduled') nut.push(`<button type="button" class="nut nut--chinh nut--rat-nho" data-lich="complete" data-ma="${l.ServiceID}">Hoàn tất</button>`);
        if (MO.includes(l.Status)) nut.push(`<button type="button" class="nut nut--chu nut-huy-don" data-lich="cancel" data-ma="${l.ServiceID}">Hủy</button>`);
        nut.push(`<button type="button" class="nut nut--chu" data-xem-lich="${l.ServiceID}">Chi tiết</button>`);
        return `<tr><td class="ma">LH${l.ServiceID}<small>Gửi ${VN.ngayGio(l.CreatedAt)}</small></td>
          <td>${VN.ngayGio(gio(l))}${l.AppointmentDate && l.AppointmentDate !== l.PreferredDate ? `<small>Khách chọn ${VN.ngayGio(l.PreferredDate)}</small>` : ''}</td>
          <td>${dichVu(l)}<small>${VN.thoat(l.ProductName)}</small></td>
          <td>${khach(l)}</td>
          <td>${nhanLich(l)}</td><td><div class="qt-hanh-dong">${nut.join('')}</div></td></tr>`;
      }).join('')}</tbody>` : `<tbody><tr><td>${qt.trong('Không có lịch hẹn phù hợp.')}</td></tr></tbody>`;
    } else {
      const ds = the.filter((t) => !tu || VN.khongDau([t.WarrantyCode, t.ProductName, t.SKU, t.OrderCode, t.CustomerPhone, t.CustomerName].join(' ')).includes(tu));
      VN.$('#qt-bh-bang').innerHTML = ds.length ? `<thead><tr><th>Mã thẻ</th><th>Sản phẩm</th><th>Chủ thẻ</th><th>Đơn hàng</th><th>Kích hoạt</th><th>Đã dùng</th><th></th></tr></thead><tbody>${ds.map((t) => `<tr>
        <td class="ma so-deu">${VN.thoat(t.WarrantyCode)}${t.Status === 'Voided' ? '<small>Đã vô hiệu</small>' : ''}</td>
        <td>${VN.thoat(t.ProductName)}<small>${VN.thoat(t.SKU)}${t.RingSize ? ' · Size ' + t.RingSize : ''}</small></td>
        <td>${khach(t)}</td>
        <td><a class="lien-ket" href="${VN.url('qtDonHang', { ma: t.OrderCode })}">${VN.thoat(t.OrderCode)}</a></td>
        <td>${VN.ngay(t.IssueDate)}</td>
        <td>${daDung(t) || '<span class="chu-phu">Chưa dùng</span>'}</td>
        <td><button type="button" class="nut nut--chu" data-xem-the="${VN.thoat(t.WarrantyCode)}">Chi tiết</button></td></tr>`).join('')}</tbody>` : `<tbody><tr><td>${qt.trong('Chưa có thẻ bảo hành nào.')}</td></tr></tbody>`;
    }
  };

  /** Các lượt dịch vụ của thẻ đã dùng (từ số đếm trên thẻ) */
  const daDung = (t) => [
    t.CleaningCount ? `Làm sạch: ${t.CleaningCount}` : '',
    t.PolishingQuota !== null && t.PolishingCountLeft < t.PolishingQuota ? `Đánh bóng & xi mới: ${t.PolishingQuota - t.PolishingCountLeft}` : '',
    t.ResizingCount ? `Chỉnh size: ${t.ResizingCount}` : '',
  ].filter(Boolean).join('<br>');

  /** Tải lại lịch hẹn và thẻ (hoàn tất một lịch làm đổi số lượt trên thẻ) */
  const taiLai = async () => {
    const [, the] = await Promise.all([qt.napLich(), VN.api.get('/api/admin/warranties')]);
    tt.the = the; ve();
  };

  const capNhatLich = async (id, hanhDong) => {
    const l = qt.lich.find((x) => String(x.ServiceID) === String(id)); if (!l) return;
    const goi = (thanTin) => VN.api.post(`/api/admin/services/${id}/${hanhDong}`, thanTin);
    let kq = null;
    if (hanhDong === 'schedule') {
      kq = await qt.lam(() => goi({}), 'Đã xác nhận lịch hẹn');
    } else if (hanhDong === 'complete') {
      const ok = await VN.xacNhan({ nhan: 'Lịch hẹn LH' + id, tieuDe: 'Dịch vụ đã hoàn tất?', noiDung: `${VN.thoat(VN.TEN_DICH_VU[l.ServiceType])}: thẻ sẽ bị trừ 1 lượt. Hết lượt miễn phí thì khách trả phí.${l.NewRingSize ? ` Size trên thẻ đổi thành ${l.NewRingSize}.` : ''}`, chuDongY: 'Hoàn tất' });
      if (!ok) return;
      kq = await qt.lam(() => goi({}));
      if (kq) VN.thongBao({ tieuDe: 'Đã hoàn tất dịch vụ', noiDung: kq.IsFreeOfCharge ? 'Miễn phí cho khách.' : `Khách trả phí ${VN.tien(kq.ServiceFee)}.`, loai: 'thanh-cong' });
    } else if (hanhDong === 'cancel') {
      const ok = await VN.xacNhan({ nhan: 'Lịch hẹn LH' + id, tieuDe: 'Hủy lịch hẹn này?', noiDung: 'Hãy gọi báo khách trước khi hủy. Khách không bị mất lượt dịch vụ.', chuDongY: 'Hủy lịch', nguy: true });
      if (!ok) return;
      kq = await qt.lam(() => goi({}), 'Đã hủy lịch hẹn');
    }
    await taiLai().catch(qt.baoLoiTai);
    if (kq && qt.dangMoChiTiet()) qt.dongChiTiet();
  };

  const xemLich = (id) => {
    const l = qt.lich.find((x) => String(x.ServiceID) === String(id)); if (!l) return;
    qt.moChiTiet(`Lịch hẹn LH${l.ServiceID}`, `<div class="qt-ct__muc"><div>${nhanLich(l)}</div><dl class="qt-dl">
      <div><dt>Dịch vụ</dt><dd>${dichVu(l)}</dd></div>
      <div><dt>Khách chọn</dt><dd>${VN.ngayGio(l.PreferredDate)}</dd></div>
      ${l.AppointmentDate ? `<div><dt>Giờ hẹn</dt><dd>${VN.ngayGio(l.AppointmentDate)}</dd></div>` : ''}
      <div><dt>Thẻ</dt><dd class="so-deu">${VN.thoat(l.WarrantyCode)} · ${VN.thoat(l.ProductName)}</dd></div>
      <div><dt>Đơn hàng</dt><dd><a class="lien-ket" href="${VN.url('qtDonHang', { ma: l.OrderCode })}">${VN.thoat(l.OrderCode)}</a></dd></div>
      <div><dt>Khách</dt><dd>${VN.thoat(l.CustomerName)} · <span class="so-deu">${VN.thoat(l.CustomerPhone || '')}</span></dd></div>
      ${l.CustomerNote ? `<div><dt>Ghi chú của khách</dt><dd>“${VN.thoat(l.CustomerNote)}”</dd></div>` : ''}
      ${l.Status === 'Completed' ? `<div><dt>Kết quả</dt><dd>${l.IsFreeOfCharge ? 'Miễn phí' : 'Tính phí ' + VN.tien(l.ServiceFee)}${l.ResultNote ? ' · ' + VN.thoat(l.ResultNote) : ''} · ${VN.ngayGio(l.CompletedAt)}</dd></div>` : ''}
      </dl></div>
      ${MO.includes(l.Status) ? `<form class="qt-form qt-ct__muc" data-form-gio="${l.ServiceID}"><h3>Đề xuất giờ khác</h3>
        <div class="truong"><label class="nhan-truong" for="qt-bh-gio">Ngày giờ mới</label><input class="o-nhap" id="qt-bh-gio" name="gio" type="datetime-local" required></div>
        <div class="hang hang--quan"><button class="nut nut--vien nut--nho" type="submit">Gửi đề xuất</button></div></form>` : ''}`, 'Lịch hẹn hậu mãi');
  };
  const xemThe = (ma) => {
    const t = tt.the.find((x) => x.WarrantyCode === ma); if (!t) return;
    const dv = qt.lich.filter((l) => l.WarrantyCode === ma).sort((a, b) => b.ServiceID - a.ServiceID);
    qt.moChiTiet(`Thẻ ${t.WarrantyCode}`, `<div class="qt-ct__muc"><dl class="qt-dl">
        <div><dt>Sản phẩm</dt><dd>${VN.thoat(t.ProductName)} · <span class="so-deu">${VN.thoat(t.SKU)}</span></dd></div>
        ${t.RingSize ? `<div><dt>Size hiện tại</dt><dd>${t.RingSize}${t.PurchasedRingSize && t.PurchasedRingSize !== t.RingSize ? ` (lúc mua: ${t.PurchasedRingSize})` : ''}</dd></div>` : ''}
        <div><dt>Chủ thẻ</dt><dd>${VN.thoat(t.CustomerName)} · <span class="so-deu">${VN.thoat(t.CustomerPhone || '')}</span></dd></div>
        <div><dt>Đơn hàng</dt><dd><a class="lien-ket" href="${VN.url('qtDonHang', { ma: t.OrderCode })}">${VN.thoat(t.OrderCode)}</a></dd></div>
        <div><dt>Kích hoạt</dt><dd>${VN.ngay(t.IssueDate)}${t.Status === 'Voided' ? ' · đã vô hiệu' : ''}</dd></div>
        <div><dt>Chính sách</dt><dd>${VN.thoat(t.PolicyName)}</dd></div>
      </dl></div>
      <div class="qt-ct__muc"><h3>Quyền lợi đã dùng</h3><dl class="qt-dl">
        <div><dt>Làm sạch</dt><dd>${t.CleaningCount} lần</dd></div>
        <div><dt>Đánh bóng &amp; xi mới</dt><dd>${t.PolishingQuota === null ? 'Không giới hạn' : `còn ${t.PolishingCountLeft} / ${t.PolishingQuota} lượt`}</dd></div>
        <div><dt>Chỉnh size</dt><dd>${t.ResizingCount} lần</dd></div></dl></div>
      <div class="qt-ct__muc"><h3>Lịch hẹn của thẻ</h3>${dv.length ? `<ol class="nhat-ky-qt">${dv.map((l) => `<li><time>${VN.ngayGio(gio(l))}</time><div>${dichVu(l)} · ${VN.TRANG_THAI_LICH[l.Status].ten}<small>LH${l.ServiceID}${l.Status === 'Completed' ? (l.IsFreeOfCharge ? ' · miễn phí' : ' · tính phí ' + VN.tien(l.ServiceFee)) : ''}</small></div></li>`).join('')}</ol>` : '<p class="chu-nho chu-phu">Chưa có lịch hẹn nào.</p>'}</div>`, `Đơn ${t.OrderCode}`);
  };

  document.addEventListener('submit', async (e) => {
    const f = e.target.closest('[data-form-gio]'); if (!f) return;
    e.preventDefault();
    const kq = await qt.lam(() => VN.api.post(`/api/admin/services/${f.dataset.formGio}/schedule`, { appointmentDate: f.gio.value }), 'Đã gửi đề xuất giờ mới');
    if (kq) { qt.dongChiTiet(); await taiLai().catch(qt.baoLoiTai); }
  });
  VN.$('#qt-bh-tab').addEventListener('click', (e) => { const b = e.target.closest('[data-khu]'); if (b) { tt.khu = b.dataset.khu; ve(); } });
  VN.$('#qt-bh-loc').addEventListener('change', (e) => { tt.loc = e.target.value; ve(); });
  VN.$('#qt-bh-tim').addEventListener('input', VN.chongDoi((e) => { tt.tim = e.target.value; ve(); }, 150));
  VN.$('#qt-bh-bang').addEventListener('click', (e) => {
    const b = e.target.closest('[data-lich]'); if (b) { capNhatLich(b.dataset.ma, b.dataset.lich); return; }
    const l = e.target.closest('[data-xem-lich]'); if (l) { xemLich(l.dataset.xemLich); return; }
    const t = e.target.closest('[data-xem-the]'); if (t) xemThe(t.dataset.xemThe);
  });

  VN.$('#qt-bh-bang').innerHTML = `<tbody><tr><td>${qt.trong('Đang tải…')}</td></tr></tbody>`;
  Promise.all([qt.sanSang, VN.api.get('/api/admin/warranties')]).then(([, the]) => { tt.the = the; ve(); }).catch(qt.baoLoiTai);
})();
