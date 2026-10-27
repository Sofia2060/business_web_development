/* =====================================================================
   KÍCH HOẠT THẺ BẢO HÀNH & ĐÁNH GIÁ (?don=mã đơn) – FR14, FR15, FR18, FR25
   Trang mở sau khi khách bấm "Đã nhận được hàng": hiển thị các thẻ đã kích hoạt
   (gọi lại kichHoatChoDon không tạo thêm thẻ) và biểu mẫu đánh giá 1 – 5 sao.
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const khungThe = VN.$('#kh-ds-the');
  if (!khungThe) return;
  const u = VN.taiKhoan.yeuCau(); if (!u) return;
  const maDon = VN.thamSo('don') || '';
  const CHU_SAO = ['', 'Rất không hài lòng', 'Chưa hài lòng', 'Bình thường', 'Hài lòng', 'Tuyệt vời'];
  const CHU_DE = { tot: ['Độ sáng bóng', 'Đóng gói sang trọng', 'Chữ khắc đẹp', 'Đúng size', 'Giao hàng đúng hẹn', 'Tư vấn tận tình'], chua: ['Nhầm size nhẫn', 'Giao trễ giờ kỷ niệm', 'Sản phẩm trầy xước', 'Chữ khắc chưa đẹp'] };

  const batDau = async () => {
    const ch = await VN.duLieu.cauHinh();
    const don = VN.donHang.lay(maDon);
    if (!don || don.trangThai !== 'Delivered') {
      VN.$('#kh-td').textContent = don ? 'Đơn hàng chưa ở trạng thái Đã nhận' : 'Không tìm thấy đơn hàng';
      VN.$('#kh-mo-ta').textContent = don ? 'Thẻ bảo hành được kích hoạt khi bạn bấm “Đã nhận được hàng” trên đơn đang giao.' : 'Vui lòng mở trang này từ mục Đơn hàng của tôi.';
      VN.$('#danh-gia').hidden = true; return;
    }
    VN.$('#kh-dd').textContent = 'Đơn ' + don.ma;
    VN.$('#kh-xem-don').href = VN.url('donHang', { ma: don.ma });
    const dsThe = VN.baoHanh.kichHoatChoDon(don, don.ngayNhan);   // xử lý lặp: không tạo thêm thẻ (FR15)
    VN.$('#kh-mo-ta').innerHTML = `Đơn <strong>${VN.thoat(don.ma)}</strong> · ${dsThe.length} thẻ trọn đời kích hoạt ngày ${VN.ngay(dsThe[0].ngayKichHoat)}. Bấm vào thẻ để lật xem quyền lợi.`;
    khungThe.innerHTML = dsThe.map((t, i) => `<div class="o-the hien-dan" style="transition-delay:${i * 120}ms">${VN.htmlTheBaoHanh(t, ch, u.hoTen)}
      <a class="nut nut--chu" href="${VN.url('congBaoHanh', { the: t.ma })}">Chi tiết thẻ &amp; đặt lịch</a></div>`).join('');
    VN.$('#kh-dat-lich').href = VN.url('congBaoHanh', { the: dsThe[0].ma });
    VN.hienDan(khungThe);
    veDanhGia(don);
  };

  const veKetQua = (dg) => {
    VN.$('#form-danh-gia').hidden = true;
    const kq = VN.$('#kq-danh-gia'); kq.hidden = false;
    const tichCuc = dg.camXuc === 'Positive';
    kq.innerHTML = `<div class="ket-qua-dg__dau"><span class="sao-danh-gia" aria-label="${dg.soSao} trên 5 sao">${Array.from({ length: 5 }, (_, i) => VN.bt('sao', i < dg.soSao ? 'sang' : '')).join('')}</span>
        <span class="nhan ${tichCuc ? 'nhan--ngoc' : 'nhan--do'}">${tichCuc ? 'Tích cực' : 'Tiêu cực'} · mô phỏng</span></div>
      <h3 class="t-3">Cảm ơn bạn đã đánh giá!</h3>
      ${dg.noiDung ? `<blockquote>“${VN.thoat(dg.noiDung)}”</blockquote>` : ''}
      ${dg.chuDe && dg.chuDe.length ? `<div class="chip-nhom">${dg.chuDe.map((c) => `<span class="chip chip--nho">${VN.thoat(c)}</span>`).join('')}</div>` : ''}
      <p class="chu-rat-nho chu-phu">Gửi lúc ${VN.ngayGio(dg.luc)}. Nhãn cảm xúc được hệ thống phân loại mô phỏng theo số sao và từ khóa để phục vụ dashboard quản trị (6.2.2).</p>`;
  };

  const veDanhGia = (don) => {
    const daCo = VN.danhGia.theoDon(don.ma);
    if (daCo) { veKetQua(daCo); return; }
    const form = VN.$('#form-danh-gia');
    VN.$('#dg-chu-de').innerHTML = CHU_DE.tot.concat(CHU_DE.chua).map((c) => `<label><input class="an-chu" type="checkbox" name="chuDe" value="${c}"><span class="chip chip--nho chip--tron${CHU_DE.chua.includes(c) ? ' chip--chua' : ''}">${c}</span></label>`).join('');
    form.addEventListener('change', (e) => {
      if (e.target.name === 'soSao') { VN.$('#chu-sao').textContent = `${e.target.value}/5 · ${CHU_SAO[e.target.value]}`; VN.$('#loi-sao').textContent = ''; }
    });
    form.noiDung.addEventListener('input', () => { VN.$('#dg-dem').textContent = `${form.noiDung.value.length}/500`; });
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const sao = VN.$('input[name="soSao"]:checked', form);
      if (!sao) { VN.$('#loi-sao').textContent = 'Vui lòng chọn số sao.'; return; }
      try {
        const dg = VN.danhGia.tao({ donHang: don.ma, soSao: Number(sao.value), noiDung: form.noiDung.value.trim(), chuDe: VN.$$('input[name="chuDe"]:checked', form).map((x) => x.value) });
        veKetQua(dg);
        VN.thongBao({ tieuDe: 'Đã gửi đánh giá', loai: 'thanh-cong' });
      } catch (loi) { VN.thongBao({ tieuDe: 'Không gửi được đánh giá', noiDung: loi.message, loai: 'loi' }); }
    });
  };

  if (u.email === VN.DEMO.email) VN.demo.damBaoDuLieu(u.id).then(batDau); else batDau();
})();
