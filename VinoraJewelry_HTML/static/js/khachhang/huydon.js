/* =====================================================================
   5.2.6 POPUP HỦY ĐƠN (BRD5, FR13)
   VN.moHuyDon(maDon) -> Promise<'giu' | 'huy' | null>
   - Đơn Chờ xử lý, chưa nhận ưu đãi giữ chân: hiện đề nghị giữ đơn + voucher (tối đa 1 lần / đơn)
   - Đồng ý giữ: áp dụng voucher, ghi nhật ký; vẫn hủy: chọn lý do -> hủy, hoàn tiền nếu đã thanh toán
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const hop = VN.$('#hop-huy-don');
  if (!hop) return;
  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  let ch = null; let maDon = ''; let ketQua = null; let xong = null;

  const buoc = (ten) => VN.$$('[data-buoc-huy]', hop).forEach((b) => { b.hidden = b.dataset.buocHuy !== ten; });
  const dat = (sel, html) => VN.$$(sel, hop).forEach((el) => { el.innerHTML = html; });

  const veGiuChan = (don) => {
    const giam = VN.donHang.tinhUuDaiGiuChan(don, ch);
    const cfg = ch.giuChanDon;
    const sp = don.sanPham[0];
    const khac = don.sanPham.find((d) => d.khacChu);
    VN.$('[data-huy-anh]', hop).innerHTML = `<img src="${VN.anh(sp.anh)}" alt=""${VN.laAnhChup(sp.anh) ? ' class="la-anh-chup"' : ''}>${don.sanPham.length > 1 ? `<span class="nhan nhan--toi hop-huy__anh-dem">+${don.sanPham.length - 1} sản phẩm</span>` : ''}<div data-huy-khac-ve></div>`;
    if (khac) VN.veKhacChu(VN.$('[data-huy-khac-ve]', hop), khac.khacChu, khac.kieuChu, khac.mau || 'Vàng Vàng');
    dat('[data-huy-pt]', cfg.phanTram);
    dat('[data-huy-tiet-kiem]', VN.tien(giam));
    dat('[data-huy-voucher]', VN.thoat(cfg.maVoucher));
    dat('[data-huy-tong-moi]', VN.tien(Math.max(0, don.tongTien - giam)));
    dat('[data-huy-tong-cu]', VN.tien(don.tongTien));
    const mat = [];
    if (khac) mat.push(['but', `Chữ khắc <strong>“${VN.thoat(khac.khacChu)}”</strong> (${TEN_KIEU[khac.kieuChu] || 'Cổ điển'}) đã được chuẩn bị riêng cho bạn.`]);
    if (don.sanPham.some((d) => d.size)) mat.push(['nhan-nhan', `Size ${don.sanPham.filter((d) => d.size).map((d) => d.size).join(', ')} đã được giữ hàng – mẫu có thể hết khi đặt lại.`]);
    mat.push(['khien', 'Thẻ bảo hành điện tử trọn đời kích hoạt ngay khi bạn nhận hàng.']);
    mat.push(['xe-giao', `${VN.thoat(don.giaoHang.ten)} – đóng gói niêm phong, bảo hiểm toàn bộ giá trị.`]);
    VN.$('[data-huy-mat]', hop).innerHTML = mat.map(([bt, chu]) => `<li>${VN.bt(bt, 'bt--nho')}<span>${chu}</span></li>`).join('');
    dat('[data-huy-dieu-kien]', `Ưu đãi giảm ${cfg.phanTram}% giá trị hàng, tối đa ${VN.tien(cfg.toiDa)}, áp dụng 1 lần cho đơn đang chờ xử lý.`);
  };

  const veLyDo = (don) => {
    VN.$('[data-huy-ds-ly-do]', hop).innerHTML = ch.lyDoHuy.map((l, i) => `<label class="the-chon"><input type="radio" name="lyDo" value="${VN.thoat(l)}"${i === 0 ? '' : ''}>
      <span class="the-chon__noi-dung"><span class="the-chon__ten">${VN.thoat(l)}</span></span></label>`).join('');
    const luuY = VN.$('[data-huy-luu-y]', hop);
    const daGiu = don.giuChan && don.giuChan.daApDung;
    luuY.hidden = !daGiu;
    if (daGiu) luuY.innerHTML = `${VN.bt('thong-tin')}<span>Đơn đã nhận ưu đãi giữ đơn <strong>${VN.thoat(don.giuChan.maVoucher)}</strong> (−${VN.tien(don.giuChan.giam)}). Nếu hủy, ưu đãi này sẽ không còn hiệu lực.</span>`;
    dat('[data-huy-hoan-tien]', don.thanhToan.trangThai === 'Success'
      ? `${VN.bt('doi-tra', 'bt--nho')} Đơn đã thanh toán ${VN.tien(don.tongTien)} qua ${VN.thoat(VN.TEN_THANH_TOAN[don.thanhToan.phuongThuc])}: tiền được hoàn về tài khoản gốc trong 3 – 7 ngày làm việc.`
      : `${VN.bt('thong-tin', 'bt--nho')} Đơn chưa thanh toán nên không phát sinh hoàn tiền.`);
    const form = VN.$('[data-buoc-huy="ly-do"]', hop); form.reset();
    VN.$('[data-loi-ly-do]', hop).textContent = '';
  };

  const ketThuc = (kq, td, chu, laHuy) => {
    ketQua = kq;
    const bt = VN.$('[data-huy-kq-bt]', hop);
    bt.innerHTML = VN.bt(laHuy ? 'huy' : 'qua', 'bt--lon'); bt.classList.toggle('la-huy', laHuy);
    dat('[data-huy-kq-td]', td); dat('[data-huy-kq-chu]', chu);
    buoc('ket-qua');
  };

  hop.addEventListener('click', (e) => {
    if (e.target.closest('[data-dong-huy]')) { VN.dongHopThoai(hop); return; }
    if (e.target.closest('[data-van-huy]')) { buoc('ly-do'); return; }
    if (e.target.closest('[data-giu-don]')) {
      try {
        const don = VN.donHang.apDungGiuChan(maDon, ch);
        ketThuc('giu', 'Cảm ơn bạn đã giữ lại đơn hàng!', `Voucher <strong>${VN.thoat(don.giuChan.maVoucher)}</strong> đã được áp dụng: giảm ${VN.tien(don.giuChan.giam)}. Tổng thanh toán mới <strong>${VN.tien(don.tongTien)}</strong>${don.thanhToan.trangThai === 'Success' ? ' – phần chênh lệch được hoàn về tài khoản gốc' : ''}.`, false);
      } catch (loi) { VN.thongBao({ tieuDe: 'Không áp dụng được ưu đãi', noiDung: loi.message, loai: 'loi' }); }
    }
  });
  hop.addEventListener('change', (e) => {
    if (e.target.name !== 'lyDo') return;
    const khac = e.target.value === 'Lý do khác';
    dat('[data-huy-bat-buoc]', khac ? '<span class="bat-buoc">*</span>' : '(không bắt buộc)');
    VN.$('[data-loi-ly-do]', hop).textContent = '';
  });
  VN.$('[data-buoc-huy="ly-do"]', hop).addEventListener('submit', (e) => {
    e.preventDefault();
    const f = e.target; const chon = VN.$('input[name="lyDo"]:checked', f);
    if (!chon) { VN.$('[data-loi-ly-do]', hop).textContent = 'Vui lòng chọn một lý do hủy đơn.'; return; }
    if (chon.value === 'Lý do khác' && f.ghiChu.value.trim().length < 5) { VN.baoLoiTruong(f.ghiChu, 'Vui lòng ghi rõ lý do (ít nhất 5 ký tự).'); f.ghiChu.focus(); return; }
    VN.baoLoiTruong(f.ghiChu, '');
    try {
      const don = VN.donHang.huy(maDon, chon.value, f.ghiChu.value.trim());
      ketThuc('huy', 'Đơn hàng đã được hủy', don.thanhToan.trangThai === 'Refunded'
        ? `Vinora đã ghi nhận yêu cầu. Số tiền ${VN.tien(don.tongTien)} sẽ được hoàn về tài khoản gốc trong 3 – 7 ngày làm việc.`
        : 'Vinora đã ghi nhận lý do của bạn. Hẹn gặp lại bạn ở một thiết kế khác!', true);
    } catch (loi) { VN.thongBao({ tieuDe: 'Không thể hủy đơn', noiDung: loi.message, loai: 'loi' }); VN.dongHopThoai(hop); }
  });
  hop.addEventListener('close', () => { if (xong) { const f = xong; xong = null; f(ketQua); } });

  VN.moHuyDon = async (ma) => {
    ch = ch || await VN.duLieu.cauHinh();
    const don = VN.donHang.lay(ma);
    if (!VN.donHang.coTheHuy(don)) { VN.thongBao({ tieuDe: 'Đơn hàng không thể hủy', noiDung: 'Chỉ hủy được đơn ở trạng thái Chờ xử lý.', loai: 'loi' }); return null; }
    maDon = ma; ketQua = null;
    dat('[data-huy-ma]', VN.thoat(ma));
    veLyDo(don);
    if (don.giuChan && don.giuChan.daApDung) buoc('ly-do');
    else { veGiuChan(don); buoc('giu'); }
    return new Promise((r) => { xong = r; VN.moHopThoai(hop); });
  };
})();
