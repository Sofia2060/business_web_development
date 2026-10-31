/* =====================================================================
   QUẢN TRỊ – ĐÁNH GIÁ
   - Điểm trung bình, phân bố số sao, tỷ lệ tích cực / tiêu cực (phân loại tự động theo số sao + từ khóa,
     chỉ hiển thị cho quản trị – khách hàng không thấy nhãn này)
   - Phản hồi đánh giá: nội dung hiện trong chi tiết đơn hàng của khách
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-dg-ds')) return;
  const TAB = [['tat-ca', 'Tất cả'], ['chua', 'Chưa phản hồi'], ['Negative', 'Tiêu cực'], ['Positive', 'Tích cực']];
  const tt = { tab: 'tat-ca', sao: '', ma: VN.thamSo('ma') || '' };
  const sao = (n) => `<span class="sao-danh-gia" aria-label="${n} trên 5 sao">${Array.from({ length: 5 }, (_, i) => VN.bt('sao', i < n ? 'sang' : '')).join('')}</span>`;
  const hop = (x, k) => (k === 'tat-ca' ? true : k === 'chua' ? !x.phanHoi : x.camXuc === k);

  const ve = () => {
    const tat = VN.danhGia.tatCa().sort((a, b) => new Date(b.luc) - new Date(a.luc));
    const tb = tat.length ? tat.reduce((t, x) => t + x.soSao, 0) / tat.length : 0;
    const am = tat.filter((x) => x.camXuc === 'Negative').length;
    VN.$('#qt-dg-tong').innerHTML = `<div class="qt-dg-tong__diem"><strong>${tat.length ? tb.toLocaleString('vi-VN', { maximumFractionDigits: 1 }) : '—'}</strong>${sao(Math.round(tb))}<span class="chu-nho chu-phu">${tat.length} đánh giá</span></div>
      <div class="qt-thanh-sao">${[5, 4, 3, 2, 1].map((n) => { const c = tat.filter((x) => x.soSao === n).length; return `<div><span>${n} sao</span><i><span style="width:${tat.length ? c * 100 / tat.length : 0}%"></span></i><span class="so-deu">${c}</span></div>`; }).join('')}
        <p class="chu-nho chu-phu">Phân loại tự động: <strong>${tat.length - am}</strong> tích cực · <strong class="chu-do">${am}</strong> tiêu cực (theo số sao và từ khóa như “trầy”, “giao trễ”, “nhầm size”).</p></div>`;
    VN.$('#qt-dg-tab').innerHTML = TAB.map(([k, ten]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${k === tt.tab}">${ten}<span class="dem">${tat.filter((x) => hop(x, k)).length}</span></button>`).join('');
    const ds = tat.filter((x) => hop(x, tt.tab) && (!tt.sao || x.soSao === Number(tt.sao)));
    VN.$('#qt-dg-ds').innerHTML = ds.length ? ds.map((x) => {
      const d = VN.donHang.tatCa().find((o) => o.ma === x.donHang);
      return `<article class="qt-dg" id="dg-${VN.thoat(x.ma)}">
        <div class="qt-dg__dau"><span>${sao(x.soSao)} · ${VN.thoat(qt.tenKhachTheoId(x.khachHang, d && d.sdtKhach))} · ${VN.ngayGio(x.luc)}</span>
          <span><span class="nhan ${x.camXuc === 'Negative' ? 'nhan--do' : 'nhan--ngoc'}">${x.camXuc === 'Negative' ? 'Tiêu cực' : 'Tích cực'}</span> <a class="lien-ket" href="${VN.url('qtDonHang', { ma: x.donHang })}">${VN.thoat(x.donHang)}</a></span></div>
        ${d ? `<p class="chu-nho chu-phu">${d.sanPham.map((s) => VN.thoat(s.ten)).join(', ')}</p>` : ''}
        ${x.noiDung ? `<blockquote>“${VN.thoat(x.noiDung)}”</blockquote>` : '<p class="chu-nho chu-phu">Khách không viết nhận xét.</p>'}
        ${x.chuDe && x.chuDe.length ? `<div class="chip-nhom">${x.chuDe.map((c) => `<span class="chip chip--nho">${VN.thoat(c)}</span>`).join('')}</div>` : ''}
        ${x.phanHoi ? `<div class="qt-dg__phan-hoi"><strong>Đã phản hồi</strong> · ${VN.ngayGio(x.phanHoi.luc)}<br>${VN.thoat(x.phanHoi.noiDung)}</div>` : ''}
        <form class="o-nhap-kem-nut" data-phan-hoi="${VN.thoat(x.ma)}"><label class="an-chu" for="ph-${VN.thoat(x.ma)}">Phản hồi khách</label>
          <input class="o-nhap" id="ph-${VN.thoat(x.ma)}" name="noiDung" maxlength="300" placeholder="${x.phanHoi ? 'Sửa phản hồi…' : x.camXuc === 'Negative' ? 'Xin lỗi và hướng dẫn khách gửi phản ánh để được xử lý…' : 'Cảm ơn khách…'}">
          <button class="nut nut--vien nut--nho" type="submit">${x.phanHoi ? 'Cập nhật' : 'Gửi phản hồi'}</button></form>
      </article>`;
    }).join('') : `<div class="qt-khoi">${qt.trong(tat.length ? 'Không có đánh giá phù hợp.' : 'Chưa có đánh giá nào.')}</div>`;
  };

  VN.$('#qt-dg-tab').addEventListener('click', (e) => { const b = e.target.closest('[data-tab]'); if (b) { tt.tab = b.dataset.tab; ve(); } });
  VN.$('#qt-dg-sao').addEventListener('change', (e) => { tt.sao = e.target.value; ve(); });
  VN.$('#qt-dg-ds').addEventListener('submit', (e) => {
    const f = e.target.closest('[data-phan-hoi]'); if (!f) return;
    e.preventDefault();
    const nd = f.noiDung.value.trim(); if (nd.length < 5) { f.noiDung.focus(); return; }
    if (qt.lam(() => VN.danhGia.phanHoi(f.dataset.phanHoi, nd, 'Vinora Jewelry'), 'Đã gửi phản hồi tới khách')) { ve(); qt.veKhung(); }
  });
  window.addEventListener('storage', VN.chongDoi((e) => { if (/^vinora\.danhGia$/.test(e.key || '')) ve(); }, 120));
  ve();
  if (tt.ma) setTimeout(() => { const el = document.getElementById('dg-' + tt.ma); if (el) { el.scrollIntoView({ block: 'center' }); el.style.outline = '2px solid var(--vang)'; } }, 100);
})();
