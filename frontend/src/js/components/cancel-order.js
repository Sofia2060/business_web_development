/* =====================================================================
   5.2.6 POPUP HỦY ĐƠN
   VN.moHuyDon(maDon) -> Promise<'huy' | 'dieu-chinh' | null>
   - Bước 1: nhắc những gì khách sẽ mất (chữ khắc, size giữ hàng, bảo hành) và gợi ý điều chỉnh đơn
     thay vì hủy – không dùng giảm giá để giữ chân
   - Bước 2: chọn lý do; đơn đã thanh toán trực tuyến: khách cung cấp tài khoản nhận hoàn tiền
     (ngân hàng không cho phép hoàn ngược về nguồn tiền) -> trạng thái Chờ hoàn tiền
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const hop = VN.$('#hop-huy-don');
  if (!hop) return;
  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  const form = VN.$('[data-buoc-huy="ly-do"]', hop);
  let ch = null; let maDon = ''; let ketQua = null; let xong = null; let daTra = false;

  const buoc = (ten) => VN.$$('[data-buoc-huy]', hop).forEach((b) => { b.hidden = b.dataset.buocHuy !== ten; });
  const dat = (sel, html) => VN.$$(sel, hop).forEach((el) => { el.innerHTML = html; });

  /* Bước 1: nhắc giá trị của đơn hàng */
  const veNhacNho = (don) => {
    const sp = don.sanPham[0];
    const khac = don.sanPham.find((d) => d.khacChu);
    VN.$('[data-huy-anh]', hop).innerHTML = `<img src="${VN.anh(sp.anh)}" alt=""${VN.laAnhChup(sp.anh) ? ' class="la-anh-chup"' : ''}>${don.sanPham.length > 1 ? `<span class="nhan nhan--toi hop-huy__anh-dem">+${don.sanPham.length - 1} sản phẩm</span>` : ''}<div data-huy-khac-ve></div>`;
    if (khac) VN.veKhacChu(VN.$('[data-huy-khac-ve]', hop), khac.khacChu, khac.kieuChu, khac.mau || 'Vàng Vàng');
    const mat = [];
    if (khac) mat.push(['but', `Chữ khắc <strong>“${VN.thoat(khac.khacChu)}”</strong> (${TEN_KIEU[khac.kieuChu] || 'Cổ điển'}) đang được chuẩn bị riêng cho bạn.`]);
    if (don.sanPham.some((d) => d.size)) mat.push(['nhan-nhan', `Size ${don.sanPham.filter((d) => d.size).map((d) => d.size).join(', ')} đang được giữ hàng – mẫu có thể hết khi đặt lại.`]);
    mat.push(['khien', 'Thẻ bảo hành điện tử trọn đời kích hoạt ngay khi bạn nhận hàng.']);
    mat.push(['xe-giao', `${VN.thoat(don.giaoHang.ten)} – đóng gói niêm phong, bảo hiểm toàn bộ giá trị.`]);
    VN.$('[data-huy-mat]', hop).innerHTML = mat.map(([bt, chu]) => `<li>${VN.bt(bt, 'bt--nho')}<span>${chu}</span></li>`).join('');
  };

  /* Bước 2: lý do + tài khoản nhận hoàn tiền (nếu đã thanh toán) */
  const veLyDo = (don) => {
    form.reset();
    VN.$$('.truong.co-loi', form).forEach((t) => t.classList.remove('co-loi'));
    VN.$$('.loi-truong', form).forEach((p) => { p.textContent = ''; });
    VN.$('[data-huy-ds-ly-do]', hop).innerHTML = ch.lyDoHuy.map((l) => `<label class="the-chon"><input type="radio" name="lyDo" value="${VN.thoat(l)}">
      <span class="the-chon__noi-dung"><span class="the-chon__ten">${VN.thoat(l)}</span></span></label>`).join('');
    dat('[data-huy-bat-buoc]', '(không bắt buộc)');
    daTra = don.thanhToan.trangThai === 'Success';
    VN.$('[data-huy-hoan]', hop).hidden = !daTra;
    VN.$('[data-huy-khong-hoan]', hop).hidden = daTra;
    if (daTra) {
      const ht = ch.hoanTien;
      VN.$('[data-huy-hoan-chu]', hop).innerHTML = `Đơn đã thanh toán <strong>${VN.tien(don.tongTien)}</strong> qua ${VN.thoat(VN.TEN_THANH_TOAN[don.thanhToan.phuongThuc])}. ${VN.thoat(ht.ghiChu)} Thời gian nhận tiền: <strong>${VN.thoat(ht.thoiGian)}</strong>.`;
      form.nganHang.innerHTML = '<option value="">Chọn ngân hàng</option>' + ht.nganHang.map((n) => `<option value="${VN.thoat(n)}">${VN.thoat(n)}</option>`).join('');
      const u = VN.taiKhoan.hienTai();
      form.chuTaiKhoan.value = VN.vietHoaKhongDau((u && u.hoTen) || don.nguoiNhan.hoTen || '');
    }
  };

  const ketThuc = (td, chu) => {
    ketQua = 'huy';
    dat('[data-huy-kq-td]', td); dat('[data-huy-kq-chu]', chu);
    buoc('ket-qua');
  };

  hop.addEventListener('click', async (e) => {
    if (e.target.closest('[data-dong-huy]')) { VN.dongHopThoai(hop); return; }
    if (e.target.closest('[data-van-huy]')) { buoc('ly-do'); return; }
    if (e.target.closest('[data-dieu-chinh]')) {
      // Thay vì hủy: gửi yêu cầu điều chỉnh đơn (dùng chung hộp thoại phản ánh)
      ketQua = 'dieu-chinh';
      VN.dongHopThoai(hop);
      if (VN.moPhanAnh) VN.moPhanAnh(maDon, { loai: 'dieu-chinh' });
    }
  });
  hop.addEventListener('change', (e) => {
    if (e.target.name !== 'lyDo') return;
    dat('[data-huy-bat-buoc]', e.target.value === 'Lý do khác' ? '<span class="bat-buoc">*</span>' : '(không bắt buộc)');
    VN.$('[data-loi-ly-do]', hop).textContent = '';
  });
  // Tên chủ tài khoản ngân hàng: chữ in hoa không dấu
  form.chuTaiKhoan.addEventListener('blur', () => { form.chuTaiKhoan.value = VN.vietHoaKhongDau(form.chuTaiKhoan.value).replace(/\s+/g, ' ').trim(); });
  form.soTaiKhoan.addEventListener('input', () => { form.soTaiKhoan.value = form.soTaiKhoan.value.replace(/\D/g, ''); });

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const chon = VN.$('input[name="lyDo"]:checked', form);
    const ok = [];
    VN.$('[data-loi-ly-do]', hop).textContent = chon ? '' : 'Vui lòng chọn một lý do hủy đơn.'; ok.push(!!chon);
    const canGhiChu = chon && chon.value === 'Lý do khác' && form.ghiChu.value.trim().length < 5;
    VN.baoLoiTruong(form.ghiChu, canGhiChu ? 'Vui lòng ghi rõ lý do (ít nhất 5 ký tự).' : ''); ok.push(!canGhiChu);
    let hoanTien = null;
    if (daTra) {
      form.chuTaiKhoan.value = VN.vietHoaKhongDau(form.chuTaiKhoan.value).replace(/\s+/g, ' ').trim();
      const nh = !!form.nganHang.value; const so = /^\d{6,19}$/.test(form.soTaiKhoan.value); const chu = form.chuTaiKhoan.value.length >= 4;
      VN.baoLoiTruong(form.nganHang, nh ? '' : 'Vui lòng chọn ngân hàng.');
      VN.baoLoiTruong(form.soTaiKhoan, so ? '' : 'Số tài khoản gồm 6 – 19 chữ số.');
      VN.baoLoiTruong(form.chuTaiKhoan, chu ? '' : 'Nhập tên chủ tài khoản đúng như trên thẻ ngân hàng.');
      ok.push(nh, so, chu);
      hoanTien = { nganHang: form.nganHang.value, soTaiKhoan: form.soTaiKhoan.value, chuTaiKhoan: form.chuTaiKhoan.value };
    }
    if (!ok.every(Boolean)) { const dau = VN.$('.co-loi input, .co-loi select, .co-loi textarea', form) || VN.$('input[name="lyDo"]', form); if (dau) dau.focus(); return; }
    try {
      const don = VN.donHang.huy(maDon, chon.value, form.ghiChu.value.trim(), hoanTien);
      ketThuc('Đơn hàng đã được hủy', don.thanhToan.trangThai === 'RefundPending'
        ? `Vinora sẽ chuyển khoản hoàn <strong>${VN.tien(don.hoanTien.soTien)}</strong> vào tài khoản ${VN.thoat(don.hoanTien.nganHang)} <span class="so-deu">${VN.thoat(VN.anSoTaiKhoan(don.hoanTien.soTaiKhoan))}</span> trong ${VN.thoat(ch.hoanTien.thoiGian)}. Bạn theo dõi trạng thái hoàn tiền trong chi tiết đơn hàng.`
        : 'Vinora đã ghi nhận lý do của bạn. Hẹn gặp lại bạn ở một thiết kế khác!');
    } catch (loi) { VN.thongBao({ tieuDe: 'Không thể hủy đơn', noiDung: VN.thoat(loi.message), loai: 'loi' }); VN.dongHopThoai(hop); }
  });
  hop.addEventListener('close', () => { if (xong) { const f = xong; xong = null; f(ketQua); } });

  VN.moHuyDon = async (ma) => {
    ch = ch || await VN.duLieu.cauHinh();
    const don = VN.donHang.lay(ma);
    if (!VN.donHang.coTheHuy(don)) { VN.thongBao({ tieuDe: 'Đơn hàng không thể hủy', noiDung: 'Chỉ hủy được đơn ở trạng thái Chờ xử lý.', loai: 'loi' }); return null; }
    maDon = ma; ketQua = null;
    dat('[data-huy-ma]', VN.thoat(ma));
    veNhacNho(don);
    veLyDo(don);
    buoc('giu');
    return new Promise((r) => { xong = r; VN.moHopThoai(hop); });
  };
})();
