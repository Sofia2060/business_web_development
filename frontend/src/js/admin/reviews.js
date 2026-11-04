/* =====================================================================
   QUẢN TRỊ – ĐÁNH GIÁ (nối API /api/admin/feedbacks)
   - Điểm trung bình, phân bố số sao, tỷ lệ tích cực / tiêu cực (nhãn do hệ thống phân tích mô phỏng,
     chỉ hiển thị cho quản trị – khách hàng không thấy nhãn này)
   - Khối phân tích cảm xúc: thanh tích cực / tiêu cực và bảng yếu tố khách quan tâm (đếm theo từng yếu tố)
   - Chưa có phản hồi của cửa hàng: database không có chỗ lưu, nên trang chỉ để xem
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-dg-ds')) return;
  const TAB = [['tat-ca', 'Tất cả'], ['Negative', 'Tiêu cực'], ['Positive', 'Tích cực']];
  const tt = { tab: 'tat-ca', sao: '', ma: VN.thamSo('ma') || '', ds: [] };
  const sao = (n) => `<span class="sao-danh-gia" aria-label="${n} trên 5 sao">${Array.from({ length: 5 }, (_, i) => VN.bt('sao', i < n ? 'sang' : '')).join('')}</span>`;
  const hop = (x, k) => (k === 'tat-ca' ? true : x.camXuc === k);

  /** Một đánh giá của API -> đánh giá dạng trang dùng. Chưa phân tích (nhãn trống) thì tính theo số sao. */
  const danhGiaTuApi = (f) => ({
    ma: f.FeedbackID, donHang: f.OrderCode, ten: f.CustomerName, soSao: f.RatingStar, noiDung: f.ReviewText || '', luc: f.CreatedAt,
    camXuc: f.SentimentLabel || (f.RatingStar <= 2 ? 'Negative' : 'Positive'),
    chuDe: f.aspects.map((a) => ({ ten: a.AspectName, am: a.Polarity === 'Negative' })),
  });

  /** Sentiment block: positive / negative bar, then how often each topic was ticked (praise on the left, complaints on the right) */
  const veCamXuc = (tat) => {
    if (!tat.length) { VN.$('#qt-cam-xuc').innerHTML = qt.trong('Chưa có đánh giá nào.'); return; }
    const am = tat.filter((x) => x.camXuc === 'Negative').length; const duong = tat.length - am;
    const phanTram = (n) => Math.round(n * 100 / tat.length);
    const dem = { tot: {}, chua: {} };
    tat.forEach((x) => x.chuDe.forEach((c) => { const nhom = dem[c.am ? 'chua' : 'tot']; nhom[c.ten] = (nhom[c.ten] || 0) + 1; }));
    const ds = (nhom) => {
      const hang = Object.entries(nhom).sort((a, b) => b[1] - a[1]);
      return hang.length ? `<ul>${hang.map(([ten, n]) => `<li><span>${VN.thoat(ten)}</span><b>${n}</b></li>`).join('')}</ul>` : '<p class="chu-nho chu-phu">Chưa có yếu tố nào được chọn.</p>';
    };
    VN.$('#qt-cam-xuc').innerHTML = `<div class="qt-cam-xuc__thanh" role="img" aria-label="${duong} đánh giá tích cực, ${am} đánh giá tiêu cực">
        <i class="duong" style="width:${duong * 100 / tat.length}%"></i><i class="am" style="width:${am * 100 / tat.length}%"></i></div>
      <div class="qt-cam-xuc__chu"><span><strong>${duong}</strong> tích cực (${phanTram(duong)}%)</span><span><strong class="chu-do">${am}</strong> tiêu cực (${phanTram(am)}%)</span></div>
      <div class="qt-cam-xuc__yeu-to"><div><h3>Mặt tích cực</h3>${ds(dem.tot)}</div><div><h3>Mặt tiêu cực</h3>${ds(dem.chua)}</div></div>`;
  };

  const ve = () => {
    const tat = tt.ds;
    veCamXuc(tat);
    const tb = tat.length ? tat.reduce((t, x) => t + x.soSao, 0) / tat.length : 0;
    const am = tat.filter((x) => x.camXuc === 'Negative').length;
    VN.$('#qt-dg-tong').innerHTML = `<div class="qt-dg-tong__diem"><strong>${tat.length ? tb.toLocaleString('vi-VN', { maximumFractionDigits: 1 }) : '—'}</strong>${sao(Math.round(tb))}<span class="chu-nho chu-phu">${tat.length} đánh giá</span></div>
      <div class="qt-thanh-sao">${[5, 4, 3, 2, 1].map((n) => { const c = tat.filter((x) => x.soSao === n).length; return `<div><span>${n} sao</span><i><span style="width:${tat.length ? c * 100 / tat.length : 0}%"></span></i><span class="so-deu">${c}</span></div>`; }).join('')}
        <p class="chu-nho chu-phu">Phân loại tự động (mô phỏng): <strong>${tat.length - am}</strong> tích cực · <strong class="chu-do">${am}</strong> tiêu cực.</p></div>`;
    VN.$('#qt-dg-tab').innerHTML = TAB.map(([k, ten]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${k === tt.tab}">${ten}<span class="dem">${tat.filter((x) => hop(x, k)).length}</span></button>`).join('');
    const ds = tat.filter((x) => hop(x, tt.tab) && (!tt.sao || x.soSao === Number(tt.sao)));
    VN.$('#qt-dg-ds').innerHTML = ds.length ? ds.map((x) => {
      const d = qt.don.find((o) => o.ma === x.donHang);
      return `<article class="qt-dg" id="dg-${x.ma}">
        <div class="qt-dg__dau"><span>${sao(x.soSao)} · ${VN.thoat(x.ten)} · ${VN.ngayGio(x.luc)}</span>
          <span><span class="nhan ${x.camXuc === 'Negative' ? 'nhan--do' : 'nhan--ngoc'}">${x.camXuc === 'Negative' ? 'Tiêu cực' : 'Tích cực'}</span> <a class="lien-ket" href="${VN.url('qtDonHang', { ma: x.donHang })}">${VN.thoat(x.donHang)}</a></span></div>
        ${d ? `<p class="chu-nho chu-phu">${d.sanPham.map((s) => VN.thoat(s.ten)).join(', ')}</p>` : ''}
        ${x.noiDung ? `<blockquote>“${VN.thoat(x.noiDung)}”</blockquote>` : '<p class="chu-nho chu-phu">Khách không viết nhận xét.</p>'}
        ${x.chuDe.length ? `<div class="chip-nhom">${x.chuDe.map((c) => `<span class="chip chip--nho">${VN.thoat(c.ten)}${c.am ? ' (chưa tốt)' : ''}</span>`).join('')}</div>` : ''}
      </article>`;
    }).join('') : `<div class="qt-khoi">${qt.trong(tat.length ? 'Không có đánh giá phù hợp.' : 'Chưa có đánh giá nào.')}</div>`;
  };

  VN.$('#qt-dg-tab').addEventListener('click', (e) => { const b = e.target.closest('[data-tab]'); if (b) { tt.tab = b.dataset.tab; ve(); } });
  VN.$('#qt-dg-sao').addEventListener('change', (e) => { tt.sao = e.target.value; ve(); });

  VN.$('#qt-dg-ds').innerHTML = `<div class="qt-khoi">${qt.trong('Đang tải đánh giá…')}</div>`;
  Promise.all([VN.api.get('/api/admin/feedbacks'), qt.sanSang]).then(([ds]) => {
    tt.ds = ds.map(danhGiaTuApi).sort((a, b) => new Date(b.luc) - new Date(a.luc)); ve();
    if (tt.ma) { const el = document.getElementById('dg-' + tt.ma); if (el) { el.scrollIntoView({ block: 'center' }); el.style.outline = '2px solid var(--vang)'; } }
  }).catch(qt.baoLoiTai);
})();
