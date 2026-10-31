/* =====================================================================
   QUẢN TRỊ – PHẢN ÁNH: danh sách phản ánh của khách, xem ảnh minh chứng,
   cập nhật trạng thái (Đã tiếp nhận -> Đang xử lý -> Đã giải quyết) kèm phản hồi gửi khách.
   Phản hồi hiện ngay trong mục "Phản ánh & hỗ trợ" của đơn hàng phía khách.
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-pa-bang')) return;
  const TAB = [['mo', 'Đang mở'], ['Received', 'Mới tiếp nhận'], ['Processing', 'Đang xử lý'], ['Resolved', 'Đã giải quyết'], ['tat-ca', 'Tất cả']];
  const tt = { tab: 'mo', tim: '', ma: VN.thamSo('ma') || '' };
  const hop = (x, k) => (k === 'tat-ca' ? true : k === 'mo' ? x.trangThai !== 'Resolved' : x.trangThai === k);
  const nhan = (x) => { const t = VN.TRANG_THAI_HO_TRO[x.trangThai]; return `<span class="nhan ${t.lop}">${t.ten}</span>`; };
  const quaGio = (x) => x.trangThai === 'Received' && Date.now() - new Date(x.luc) > 24 * 3600000;

  const ve = () => {
    const tat = VN.hoTro.tatCa().sort((a, b) => new Date(b.luc) - new Date(a.luc));
    VN.$('#qt-pa-tab').innerHTML = TAB.map(([k, ten]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${k === tt.tab}">${ten}<span class="dem">${tat.filter((x) => hop(x, k)).length}</span></button>`).join('');
    const tu = VN.khongDau(tt.tim);
    const ds = tat.filter((x) => hop(x, tt.tab) && (!tu || VN.khongDau([x.ma, x.donHang, x.lienHe.sdt, x.tenLoai].join(' ')).includes(tu)));
    VN.$('#qt-pa-bang').innerHTML = ds.length ? `<thead><tr><th>Mã</th><th>Vấn đề</th><th>Đơn hàng</th><th>Khách / liên hệ</th><th>Gửi lúc</th><th>Trạng thái</th><th></th></tr></thead><tbody>${ds.map((x) => `<tr${x.ma === tt.ma ? ' class="chon"' : ''}>
      <td class="ma">${VN.thoat(x.ma)}</td>
      <td>${VN.thoat(x.tenLoai)}<small>${VN.thoat(x.moTa.length > 70 ? x.moTa.slice(0, 70) + '…' : x.moTa)}</small></td>
      <td><a class="lien-ket" href="${VN.url('qtDonHang', { ma: x.donHang })}">${VN.thoat(x.donHang)}</a></td>
      <td>${VN.thoat(qt.tenKhachTheoId(x.khachHang, x.lienHe.sdt))}<small>${VN.thoat(x.lienHe.cach)} · ${VN.thoat(x.lienHe.sdt)}</small></td>
      <td>${VN.ngayGio(x.luc)}${quaGio(x) ? '<small class="chu-do">Quá 24 giờ chưa liên hệ</small>' : ''}</td>
      <td>${nhan(x)}</td>
      <td><button type="button" class="nut nut--vien nut--rat-nho" data-xem="${VN.thoat(x.ma)}">Xử lý</button></td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td>${qt.trong(tat.length ? 'Không có phản ánh phù hợp.' : 'Chưa có phản ánh nào từ khách hàng.')}</td></tr></tbody>`;
    if (qt.dangMoChiTiet() && tt.ma) veChiTiet(tt.ma);
  };

  const MAU = {
    Processing: 'Vinora đã nhận phản ánh và đang kiểm tra. Chuyên viên sẽ gọi cho anh/chị để thống nhất cách xử lý.',
    Resolved: 'Vinora đã xử lý xong: đổi sản phẩm mới / sửa miễn phí tại showroom theo thỏa thuận với anh/chị. Cảm ơn anh/chị đã phản hồi.',
  };
  const veChiTiet = (ma) => {
    const x = VN.hoTro.tatCa().find((p) => p.ma === ma); if (!x) return;
    tt.ma = ma;
    const d = VN.donHang.tatCa().find((o) => o.ma === x.donHang);
    const sp = (x.sanPham || []).map((m) => d && d.sanPham.find((s) => s.ma === m)).filter(Boolean);
    const tiep = x.trangThai === 'Received' ? 'Processing' : 'Resolved';
    qt.moChiTiet(`Phản ánh ${x.ma}`, `
      <div class="qt-ct__muc"><div class="hang hang--quan">${nhan(x)}<span class="chu-nho chu-phu">Gửi ${VN.ngayGio(x.luc)}</span></div>
        <dl class="qt-dl">
          <div><dt>Vấn đề</dt><dd><strong>${VN.thoat(x.tenLoai)}</strong></dd></div>
          <div><dt>Mô tả của khách</dt><dd>“${VN.thoat(x.moTa)}”</dd></div>
          ${sp.length ? `<div><dt>Sản phẩm</dt><dd>${sp.map((s) => `${VN.thoat(s.ten)} <small class="chu-phu">(${VN.thoat(s.ma)})</small>`).join('<br>')}</dd></div>` : ''}
          <div><dt>Đơn hàng</dt><dd><a class="lien-ket" href="${VN.url('qtDonHang', { ma: x.donHang })}">${VN.thoat(x.donHang)}</a>${d ? ` · ${VN.TRANG_THAI_DON[d.trangThai].ten} · ${VN.tien(d.tongTien)}` : ''}</dd></div>
          <div><dt>Khách</dt><dd>${VN.thoat(qt.tenKhachTheoId(x.khachHang, x.lienHe.sdt))}</dd></div>
          <div><dt>Liên hệ qua</dt><dd>${VN.thoat(x.lienHe.cach)} · <span class="so-deu">${VN.thoat(x.lienHe.sdt)}</span></dd></div>
        </dl>
        ${x.anh && x.anh.length ? `<div class="qt-anh">${x.anh.map((a, i) => `<a href="${a}" target="_blank" rel="noopener"><img src="${a}" alt="Ảnh minh chứng ${i + 1}"></a>`).join('')}</div>` : '<p class="chu-nho chu-phu">Khách không đính kèm ảnh.</p>'}
      </div>
      <div class="qt-ct__muc"><h3>Phản hồi khách hàng</h3>
        <form class="qt-form" data-form-pa>
          <div class="truong"><label class="nhan-truong" for="qt-pa-tt">Trạng thái</label>
            <select class="o-chon" id="qt-pa-tt" name="trangThai">${Object.entries(VN.TRANG_THAI_HO_TRO).map(([k, t]) => `<option value="${k}"${k === (x.trangThai === 'Resolved' ? 'Resolved' : tiep) ? ' selected' : ''}>${t.ten}</option>`).join('')}</select></div>
          <div class="truong"><label class="nhan-truong" for="qt-pa-ph">Nội dung gửi khách (hiện trong đơn hàng của khách)</label>
            <textarea class="o-van-ban" id="qt-pa-ph" name="phanHoi" rows="3" maxlength="400">${x.trangThai === 'Resolved' ? '' : MAU[tiep]}</textarea></div>
          <div class="hang hang--quan"><button class="nut nut--chinh nut--nho" type="submit">Cập nhật &amp; gửi khách</button></div>
        </form>
      </div>
      <div class="qt-ct__muc"><h3>Lịch sử xử lý</h3>${qt.nhatKy(x.lichSu)}</div>`, x.donHang);
    VN.$$('#qt-pa-bang tr').forEach((tr) => tr.classList.toggle('chon', !!VN.$(`[data-xem="${ma}"]`, tr)));
  };

  VN.$('#qt-pa-tab').addEventListener('click', (e) => { const b = e.target.closest('[data-tab]'); if (b) { tt.tab = b.dataset.tab; ve(); } });
  VN.$('#qt-pa-tim').addEventListener('input', VN.chongDoi((e) => { tt.tim = e.target.value; ve(); }, 150));
  VN.$('#qt-pa-bang').addEventListener('click', (e) => { const b = e.target.closest('[data-xem]'); if (b) veChiTiet(b.dataset.xem); });
  document.addEventListener('change', (e) => { if (e.target.id === 'qt-pa-tt' && MAU[e.target.value]) VN.$('#qt-pa-ph').value = MAU[e.target.value]; });
  document.addEventListener('submit', (e) => {
    const f = e.target.closest('[data-form-pa]'); if (!f) return;
    e.preventDefault();
    const ok = qt.lam(() => VN.hoTro.capNhat(tt.ma, f.trangThai.value, f.phanHoi.value.trim(), qt.boi('CSKH')), 'Đã cập nhật phản ánh');
    if (ok) { ve(); veChiTiet(tt.ma); }
  });
  window.addEventListener('storage', VN.chongDoi((e) => { if (/^vinora\.hoTro$/.test(e.key || '')) ve(); }, 120));
  ve();
  if (tt.ma) { tt.tab = 'tat-ca'; ve(); veChiTiet(tt.ma); }
})();
