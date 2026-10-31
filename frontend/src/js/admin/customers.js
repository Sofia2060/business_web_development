/* =====================================================================
   QUẢN TRỊ – KHÁCH HÀNG
   Gộp khách có tài khoản và khách mua không tài khoản (mã khách = số điện thoại);
   số đơn, tổng chi tiêu, thẻ bảo hành, đơn gần nhất; xem lịch sử mua của từng khách.
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-kh-bang')) return;
  const tt = { loai: '', tim: '' };

  const gom = () => {
    const don = VN.donHang.tatCa(); const the = VN.baoHanh.tatCa();
    const khach = {};
    VN.taiKhoan.ds().forEach((u) => { khach['TK:' + u.id] = { khoa: 'TK:' + u.id, ten: u.hoTen, email: u.email, sdt: u.sdt || '', coTaiKhoan: true, ngayTao: u.ngayTao, don: [], soThe: 0 }; });
    don.forEach((d) => {
      const k = d.khachHang ? 'TK:' + d.khachHang : 'SDT:' + d.sdtKhach;
      if (!khach[k]) khach[k] = { khoa: k, ten: d.nguoiNhan.hoTen, email: d.nguoiNhan.email || '', sdt: d.sdtKhach, coTaiKhoan: false, ngayTao: d.ngayDat, don: [], soThe: 0 };
      khach[k].don.push(d);
    });
    the.forEach((t) => { const k = t.khachHang ? 'TK:' + t.khachHang : 'SDT:' + t.sdtKhach; if (khach[k]) khach[k].soThe++; });
    return Object.values(khach).map((k) => Object.assign(k, {
      chiTieu: k.don.filter((d) => d.thanhToan.trangThai === 'Success').reduce((a, d) => a + d.tongTien, 0),
      ganNhat: k.don.reduce((m, d) => (!m || d.ngayDat > m ? d.ngayDat : m), ''),
    }));
  };

  const ve = () => {
    const tat = gom();
    VN.$('#qt-kh-so').innerHTML = [
      ['', 'Khách hàng', tat.length, `${tat.filter((k) => k.don.length).length} khách đã mua`],
      ['ngoc', 'Có tài khoản', tat.filter((k) => k.coTaiKhoan).length, 'Đăng ký trên website'],
      ['cam', 'Mua không tài khoản', tat.filter((k) => !k.coTaiKhoan).length, 'Nhận diện bằng số điện thoại'],
      ['xanh', 'Mua lại', tat.filter((k) => k.don.length > 1).length, 'Khách có từ 2 đơn trở lên'],
    ].map(([lop, t, so, phu]) => `<div class="qt-o-so${lop ? ' qt-o-so--' + lop : ''}"><span>${t}</span><strong>${so}</strong><small>${phu}</small></div>`).join('');
    VN.$$('#qt-kh-tab [data-loai]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.loai === tt.loai)));
    const tu = VN.khongDau(tt.tim);
    const ds = tat.filter((k) => (!tt.loai || (tt.loai === 'tk') === k.coTaiKhoan) && (!tu || VN.khongDau([k.ten, k.email, k.sdt].join(' ')).includes(tu)))
      .sort((a, b) => b.chiTieu - a.chiTieu || (b.ganNhat || '').localeCompare(a.ganNhat || ''));
    VN.$('#qt-kh-bang').innerHTML = ds.length ? `<thead><tr><th>Khách hàng</th><th>Liên hệ</th><th>Loại</th><th class="so">Số đơn</th><th class="so">Đã chi</th><th class="so">Thẻ BH</th><th>Đơn gần nhất</th><th></th></tr></thead><tbody>${ds.map((k) => `<tr>
      <td><strong>${VN.thoat(k.ten)}</strong><small>Từ ${VN.ngay(k.ngayTao)}</small></td>
      <td><span class="so-deu">${VN.thoat(k.sdt || '—')}</span><small>${VN.thoat(k.email || '')}</small></td>
      <td>${k.coTaiKhoan ? '<span class="nhan nhan--ngoc nhan--tron">Tài khoản</span>' : '<span class="nhan nhan--tron">Không tài khoản</span>'}</td>
      <td class="so">${k.don.length}</td><td class="so">${VN.tien(k.chiTieu)}</td><td class="so">${k.soThe}</td>
      <td>${k.ganNhat ? VN.ngay(k.ganNhat) : '—'}</td>
      <td><button type="button" class="nut nut--vien nut--rat-nho" data-xem="${VN.thoat(k.khoa)}">Xem</button></td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td>${qt.trong('Không có khách hàng phù hợp.')}</td></tr></tbody>`;
  };

  const xem = (khoa) => {
    const k = gom().find((x) => x.khoa === khoa); if (!k) return;
    const don = k.don.slice().sort((a, b) => new Date(b.ngayDat) - new Date(a.ngayDat));
    qt.moChiTiet(k.ten, `<div class="qt-ct__muc"><dl class="qt-dl">
        <div><dt>Loại</dt><dd>${k.coTaiKhoan ? 'Có tài khoản' : 'Mua không tài khoản (mã khách là số điện thoại)'}</dd></div>
        <div><dt>Số điện thoại</dt><dd class="so-deu">${VN.thoat(k.sdt || '—')}</dd></div>
        ${k.email ? `<div><dt>Email</dt><dd>${VN.thoat(k.email)}</dd></div>` : ''}
        <div><dt>Đã chi</dt><dd><strong>${VN.tien(k.chiTieu)}</strong> · ${k.don.length} đơn · ${k.soThe} thẻ bảo hành</dd></div>
      </dl></div>
      <div class="qt-ct__muc"><h3>Lịch sử mua hàng</h3>${don.length ? `<div class="qt-bang-boc"><table class="qt-bang"><thead><tr><th>Mã đơn</th><th class="so">Tổng</th><th>Trạng thái</th></tr></thead><tbody>${don.map((d) => `<tr>
        <td><a class="ma lien-ket" href="${VN.url('qtDonHang', { ma: d.ma })}">${VN.thoat(d.ma)}</a><small>${VN.ngayGio(d.ngayDat)}</small></td><td class="so">${VN.tien(d.tongTien)}</td><td>${qt.nhanDon(d)} ${qt.nhanTT(d)}</td></tr>`).join('')}</tbody></table></div>` : '<p class="chu-nho chu-phu">Khách chưa có đơn hàng.</p>'}</div>`, 'Hồ sơ khách hàng');
  };

  VN.$('#qt-kh-tab').addEventListener('click', (e) => { const b = e.target.closest('[data-loai]'); if (b) { tt.loai = b.dataset.loai; ve(); } });
  VN.$('#qt-kh-tim').addEventListener('input', VN.chongDoi((e) => { tt.tim = e.target.value; ve(); }, 150));
  VN.$('#qt-kh-bang').addEventListener('click', (e) => { const b = e.target.closest('[data-xem]'); if (b) xem(b.dataset.xem); });
  window.addEventListener('storage', VN.chongDoi((e) => { if (/^vinora\.(donHang|nguoiDung|baoHanh)$/.test(e.key || '')) ve(); }, 150));
  ve();
})();
