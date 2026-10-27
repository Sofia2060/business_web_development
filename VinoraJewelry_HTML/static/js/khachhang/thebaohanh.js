/* =====================================================================
   THẺ BẢO HÀNH ĐIỆN TỬ DẠNG THẺ ATM (5.2.8) – dùng ở trang Kích hoạt và Cổng bảo hành
   VN.htmlTheBaoHanh(the, ch, chuThe) -> chuỗi HTML thẻ lật 2 mặt (bấm để lật)
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  VN.soTheDep = (ma) => String(ma).replace(/^(VNRA)(\d{4})(\d{4})(\d{4})$/, '$1 $2 $3 $4');
  VN.htmlTheBaoHanh = (the, ch, chuThe) => {
    const k = VN.khongDau(the.mau || '');
    const kieu = k.includes('trang') || k.includes('bac') ? 'trang' : k.includes('hong') ? 'hong' : 'vang';
    const logo = (VN.duongDan.hinh || '') + 'logo/logo-vinora-sang.svg';
    const ql = ch.baoHanh.quyenLoi.filter((q) => q.datLich && (!q.chiChoNhan || the.laNhan));
    const conLai = (q) => { const n = VN.baoHanh.conLai(the, ch, q.ma); return n === Infinity ? 'Trọn đời' : `Còn ${n}/${q.luot}`; };
    return `
      <div class="the-bh the-bh--${kieu}" data-the="${VN.thoat(the.ma)}" role="button" tabindex="0" aria-label="Thẻ bảo hành ${VN.thoat(the.ma)} – bấm để lật xem quyền lợi">
        <div class="the-bh__lat">
          <div class="the-bh__mat">
            <div class="the-bh__dau"><img src="${logo}" alt="Vinora Jewelry" width="120" height="34"><span class="the-bh__loai">E-Warranty</span></div>
            <span class="the-bh__chip" aria-hidden="true"></span>
            <p class="the-bh__so">${VN.soTheDep(the.ma)}</p>
            <div class="the-bh__duoi">
              <div><small>Chủ thẻ</small><strong>${VN.thoat(VN.vietHoaKhongDau(chuThe || ''))}</strong></div>
              <div><small>Kích hoạt</small><strong class="so-deu">${VN.ngay(the.ngayKichHoat)}</strong></div>
              <div><small>Hiệu lực</small><strong>${VN.thoat(the.hieuLuc)}</strong></div>
            </div>
          </div>
          <div class="the-bh__sau">
            <div class="the-bh__sp">
              <span class="the-bh__sp-anh"><img src="${VN.anh(the.anh)}" alt=""></span>
              <div><strong>${VN.thoat(the.tenSP)}</strong><small>${VN.thoat(the.maSP)} · ${VN.thoat(the.chatLieu)}${the.size ? ' · Size ' + the.size : ''}${the.khacChu ? ` · Khắc “${VN.thoat(the.khacChu)}”` : ''}</small></div>
            </div>
            <ul class="the-bh__ql">${ql.map((q) => `<li><span>${VN.thoat(VN.TEN_DICH_VU[q.ma] || q.ten)}</span><b>${conLai(q)}</b></li>`).join('')}</ul>
            <span class="the-bh__ma-vach" aria-hidden="true"></span>
          </div>
        </div>
      </div>`;
  };
  // Bấm / Enter để lật thẻ
  const lat = (el) => el.classList.toggle('dang-lat');
  document.addEventListener('click', (e) => { const t = e.target.closest('.the-bh[data-the]'); if (t && !e.target.closest('a,button')) lat(t); });
  document.addEventListener('keydown', (e) => { const t = e.target.closest && e.target.closest('.the-bh[data-the]'); if (t && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); lat(t); } });
})();
