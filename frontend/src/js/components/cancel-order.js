/* =====================================================================
   5.2.6 POPUP HỦY ĐƠN
   VN.moHuyDon(maDon) -> Promise<'huy' | 'giu' | 'dieu-chinh' | null>
   Luật hủy đơn (máy chủ quyết định, popup chỉ hiển thị):
   - Đơn dưới 2.000.000 ₫ và không khắc chữ: khách tự hủy trên website. Bước 1 chọn lý do,
     bước 2 popup nhắc "hủy sẽ mất voucher, đặt lại chỉ còn giá gốc" (giữ đơn hoặc vẫn hủy)
   - Đơn từ 2.000.000 ₫ hoặc có khắc chữ: không tự hủy được, popup hướng dẫn gọi hotline
   - Đơn đã bắt đầu chế tác: không ai hủy được (nút Hủy đơn không hiện)
   - Đơn đã thanh toán trực tuyến: khi hủy, thanh toán chuyển sang "Đã hoàn tiền" (thanh toán mô phỏng)
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const hop = VN.$('#hop-huy-don');
  if (!hop) return;
  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  const form = VN.$('[data-buoc-huy="ly-do"]', hop);
  let ch = null; let don = null; let ketQua = null; let xong = null; let dangXuLy = false;

  const buoc = (ten) => VN.$$('[data-buoc-huy]', hop).forEach((b) => { b.hidden = b.dataset.buocHuy !== ten; });
  const dat = (sel, html) => VN.$$(sel, hop).forEach((el) => { el.innerHTML = html; });
  const baoLoi = (loi) => VN.thongBao({ tieuDe: 'Không thể hủy đơn', noiDung: VN.thoat(loi.message), loai: 'loi' });
  const choXuLy = (nut, bat) => { dangXuLy = bat; VN.$$('button', hop).forEach((b) => { b.disabled = bat; }); if (nut) nut.classList.toggle('dang-xu-ly', bat); };

  /* Bước "hotline": đơn giá trị cao hoặc có khắc chữ */
  const veHotline = (thongDiep) => {
    const hotline = ch.thuongHieu.hotline;
    dat('[data-huy-hotline-chu]', VN.thoat(thongDiep || `Khách hàng không thể tự hủy vì đơn hàng có giá trị cao hoặc có sản phẩm khắc chữ. Vui lòng gọi qua hotline ${hotline} để được hỗ trợ.`));
    VN.$('[data-huy-goi]', hop).href = 'tel:' + hotline.replace(/\s/g, '');
    VN.$('[data-huy-goi]', hop).textContent = `Gọi ${hotline}`;
    buoc('hotline');
  };

  /* Bước "lý do" */
  const veLyDo = () => {
    form.reset();
    VN.$$('.truong.co-loi', form).forEach((t) => t.classList.remove('co-loi'));
    VN.$$('.loi-truong', form).forEach((p) => { p.textContent = ''; });
    VN.$('[data-huy-ds-ly-do]', hop).innerHTML = ch.lyDoHuy.map((l) => `<label class="the-chon"><input type="radio" name="lyDo" value="${VN.thoat(l)}">
      <span class="the-chon__noi-dung"><span class="the-chon__ten">${VN.thoat(l)}</span></span></label>`).join('');
    dat('[data-huy-bat-buoc]', '(không bắt buộc)');
    const daTra = don.thanhToan.trangThai === 'Success';
    dat('[data-huy-ghi-chu-tien]', daTra
      ? `${VN.bt('thong-tin', 'bt--nho')} Đơn đã thanh toán <strong>${VN.tien(don.tongTien)}</strong> qua ${VN.thoat(VN.TEN_THANH_TOAN[don.thanhToan.phuongThuc])}: khi hủy, số tiền này được hoàn lại.`
      : `${VN.bt('thong-tin', 'bt--nho')} Đơn chưa thanh toán nên không phát sinh hoàn tiền.`);
    buoc('ly-do');
  };

  /* Bước "giữ chân": nhắc những gì khách sẽ mất, theo dữ liệu máy chủ trả về khi bấm hủy */
  const veNhacNho = (yc) => {
    const sp = don.sanPham[0];
    const khac = don.sanPham.find((d) => d.khacChu);
    VN.$('[data-huy-anh]', hop).innerHTML = `<img src="${VN.anh(sp.anh)}" alt=""${VN.laAnhChup(sp.anh) ? ' class="la-anh-chup"' : ''}>${don.sanPham.length > 1 ? `<span class="nhan nhan--toi hop-huy__anh-dem">+${don.sanPham.length - 1} sản phẩm</span>` : ''}<div data-huy-khac-ve></div>`;
    if (khac) VN.veKhacChu(VN.$('[data-huy-khac-ve]', hop), khac.khacChu, khac.kieuChu, khac.mau || 'Vàng Vàng');
    const mat = [];
    if (yc.maUuDai) {
      mat.push(['the', `Voucher <strong>${VN.thoat(yc.maUuDai)}</strong> (giảm ${VN.tien(yc.tienGiam)}) <strong>sẽ mất</strong>. Nếu đặt lại, bạn trả giá gốc <strong>${VN.tien(yc.giaGoc)}</strong> thay vì <strong>${VN.tien(yc.giaGoc - yc.tienGiam)}</strong>.`]);
    }
    if (don.sanPham.some((d) => d.size)) mat.push(['nhan-nhan', `Size ${don.sanPham.filter((d) => d.size).map((d) => d.size).join(', ')} đang được giữ hàng – mẫu có thể hết khi đặt lại.`]);
    mat.push(['khien', 'Thẻ bảo hành điện tử trọn đời kích hoạt ngay khi bạn nhận hàng.']);
    mat.push(['xe-giao', `${VN.thoat(don.giaoHang.ten)} – đóng gói niêm phong, bảo hiểm toàn bộ giá trị.`]);
    VN.$('[data-huy-mat]', hop).innerHTML = mat.map(([bt, chu]) => `<li>${VN.bt(bt, 'bt--nho')}<span>${chu}</span></li>`).join('');
    buoc('giu');
  };

  const ketThuc = (td, chu) => {
    dat('[data-huy-kq-td]', td); dat('[data-huy-kq-chu]', chu);
    buoc('ket-qua');
  };

  hop.addEventListener('click', async (e) => {
    if (dangXuLy) return;
    if (e.target.closest('[data-dong-huy]')) { VN.dongHopThoai(hop); return; }
    if (e.target.closest('[data-giu-don]')) {            // "Giữ lại đơn hàng": máy chủ ghi nhận khách đã chọn giữ đơn
      choXuLy(null, true);
      try { await VN.donHang.traLoiHuy(don.ma, true); ketQua = 'giu'; VN.dongHopThoai(hop); VN.thongBao({ tieuDe: 'Vinora giữ đơn hàng cho bạn', noiDung: 'Cảm ơn bạn đã tiếp tục tin tưởng Vinora.', loai: 'thanh-cong' }); }
      catch (loi) { baoLoi(loi); VN.dongHopThoai(hop); } finally { choXuLy(null, false); }
      return;
    }
    if (e.target.closest('[data-van-huy]')) {            // "Tôi vẫn muốn hủy": hủy đơn, trả hàng về kho, mất voucher
      choXuLy(null, true);
      try {
        const sau = await VN.donHang.traLoiHuy(don.ma, false);
        ketQua = 'huy';
        ketThuc('Đơn hàng đã được hủy', sau.thanhToan.trangThai === 'Refunded'
          ? `Vinora đã ghi nhận hoàn lại <strong>${VN.tien(sau.tongTien)}</strong> đã thanh toán qua ${VN.thoat(VN.TEN_THANH_TOAN[sau.thanhToan.phuongThuc])}.`
          : 'Vinora đã ghi nhận lý do của bạn. Hẹn gặp lại bạn ở một thiết kế khác!');
      } catch (loi) { baoLoi(loi); VN.dongHopThoai(hop); } finally { choXuLy(null, false); }
      return;
    }
    if (e.target.closest('[data-dieu-chinh]')) {
      // Thay vì hủy: gửi yêu cầu điều chỉnh đơn (dùng chung hộp thoại phản ánh)
      ketQua = 'dieu-chinh';
      VN.dongHopThoai(hop);
      if (VN.moPhanAnh) VN.moPhanAnh(don.ma, { loai: 'dieu-chinh' });
    }
  });
  hop.addEventListener('change', (e) => {
    if (e.target.name !== 'lyDo') return;
    dat('[data-huy-bat-buoc]', e.target.value === 'Lý do khác' ? '<span class="bat-buoc">*</span>' : '(không bắt buộc)');
    VN.$('[data-loi-ly-do]', hop).textContent = '';
  });

  /* Gửi lý do -> máy chủ kiểm tra luật hủy rồi trả về nội dung popup nhắc nhở (chưa hủy gì) */
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (dangXuLy) return;
    const chon = VN.$('input[name="lyDo"]:checked', form);
    const ok = [];
    VN.$('[data-loi-ly-do]', hop).textContent = chon ? '' : 'Vui lòng chọn một lý do hủy đơn.'; ok.push(!!chon);
    const canGhiChu = chon && chon.value === 'Lý do khác' && form.ghiChu.value.trim().length < 5;
    VN.baoLoiTruong(form.ghiChu, canGhiChu ? 'Vui lòng ghi rõ lý do (ít nhất 5 ký tự).' : ''); ok.push(!canGhiChu);
    if (!ok.every(Boolean)) { const dau = VN.$('.co-loi input, .co-loi select, .co-loi textarea', form) || VN.$('input[name="lyDo"]', form); if (dau) dau.focus(); return; }
    const lyDo = [chon.value, form.ghiChu.value.trim()].filter(Boolean).join(' – ').slice(0, 500);
    const nut = VN.$('[type="submit"]', form);
    choXuLy(nut, true);
    try {
      const yc = await VN.donHang.yeuCauHuy(don.ma, lyDo);
      veNhacNho(yc);
    } catch (loi) {
      if (loi.maLoi === 50029) veHotline(loi.message);       // luật hủy đã đổi từ lúc mở popup: đơn này phải gọi hotline
      else { baoLoi(loi); VN.dongHopThoai(hop); }
    } finally { choXuLy(nut, false); }
  });
  hop.addEventListener('close', () => { if (xong) { const f = xong; xong = null; f(ketQua); } });

  /**
   * Mở popup hủy đơn. tiepTuc = đơn đang có yêu cầu hủy chờ khách trả lời (đã bấm hủy nhưng chưa chọn):
   * hiện lại ngay popup nhắc nhở.
   */
  VN.moHuyDon = async (ma, { tiepTuc = false } = {}) => {
    ch = ch || await VN.duLieu.cauHinh();
    try { don = await VN.donHang.napMot(ma); } catch (loi) { baoLoi(loi); return null; }
    if (!VN.donHang.coTheHuy(don)) {
      VN.thongBao({ tieuDe: 'Đơn hàng không thể hủy', noiDung: don.daBatDauCheTac ? 'Đơn hàng đang được chế tác nên không thể hủy.' : 'Đơn hàng đã qua bước có thể hủy.', loai: 'loi' });
      return null;
    }
    ketQua = null;
    dat('[data-huy-ma]', VN.thoat(ma));
    if (don.kenhHuy === 'Hotline') veHotline();
    else if (tiepTuc && don.huyDangCho) veNhacNho(don.huyDangCho);
    else veLyDo();
    return new Promise((r) => { xong = r; VN.moHopThoai(hop); });
  };
})();
