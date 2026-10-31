/* =====================================================================
   5.2.5 THANH TOÁN (FR10, FR11)
   - Không bắt buộc đăng nhập: khách mua bằng số điện thoại (mã khách hàng), có tài khoản thì chọn địa chỉ trong sổ
   - Nhập địa chỉ mới theo 34 tỉnh, thành; mua tặng thì ghi thêm số điện thoại người đặt
   - Giao tiêu chuẩn / hỏa tốc (chỉ TP.HCM, Hà Nội) – phí tính bằng VN.tinhTien (NFR5)
   - COD, chuyển khoản VietQR, VNPay & MoMo Sandbox (mô phỏng)
   - Kiểm tra lại giá ngay trước khi tạo đơn có mã riêng; đơn trả trực tuyến có hạn thanh toán 24 giờ
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const form = VN.$('#form-thanh-toan');
  if (!form) return;
  const u = VN.taiKhoan.hienTai();       // có thể null: đặt hàng không cần tài khoản

  const BIEU_TUONG = { COD: 'hop-hang', BANK: 'qr', VNPAY: 'the', MOMO: 'dien-thoai' };
  const tt = { ch: null, dong: [], tc: VN.tuyChonGio.doc(), diaChi: 'moi', dangGui: false };

  Promise.all([VN.duLieu.coBan(), VN.gioHang.chiTiet()]).then(async ([{ ch }, dong]) => {
    tt.ch = ch; tt.dong = dong;
    if (!dong.length) { location.replace(VN.url('gioHang')); return; }
    await khoiTaoDiaChi();
    vePhuongThuc();
    khoiTaoQuaTang();
    VN.$('#tt-ma').value = tt.tc.maUuDai || '';
    veTomTat();
    form.removeAttribute('aria-busy');
  }).catch((loi) => {
    console.error(loi);
    VN.thongBao({ tieuDe: 'Chưa tải được dữ liệu', noiDung: 'Vui lòng kiểm tra kết nối mạng rồi tải lại trang.', loai: 'loi' });
  });

  /* ================= 1. ĐỊA CHỈ ================= */
  const khoiTaoDiaChi = async () => {
    const ds = (u && u.diaChi) || [];
    const macDinh = ds.find((d) => d.macDinh) || ds[0];
    await VN.dienChonTinh(form.tinh, '');
    if (u) { form.hoTen.value = u.hoTen || ''; form.sdt.value = u.sdt || ''; form.email.value = u.email || ''; }
    else {
      VN.$('#tt-khach').hidden = false; VN.$('#tt-tang').hidden = false;
      VN.$('#tt-dang-nhap').href = VN.url('taiKhoan', { tiep: VN.url('thanhToan') });
      VN.$('#tt-tang-chk').addEventListener('change', (e) => { VN.$('#tt-sdt-dat-truong').hidden = !e.target.checked; if (e.target.checked) form.sdtNguoiDat.focus(); });
    }
    if (ds.length) {
      VN.$('#tt-so-dia-chi').hidden = false;
      VN.$('#tt-ds-dia-chi').innerHTML = ds.map((d) => `
        <label class="the-chon the-chon--dia-chi"><input type="radio" name="chonDiaChi" value="${VN.thoat(d.id)}"${d === macDinh ? ' checked' : ''}>
          <span class="the-chon__noi-dung"><span class="the-chon__ten">${VN.thoat(d.hoTen)} · <span class="so-deu">${VN.thoat(d.sdt)}</span>${d.macDinh ? ' <span class="nhan nhan--ngoc">Mặc định</span>' : ''}</span>
          <span class="the-chon__mo-ta">${VN.thoat(VN.diaChiDay(d))}</span></span></label>`).join('')
        + `<label class="the-chon the-chon--dia-chi"><input type="radio" name="chonDiaChi" value="moi">
          <span class="the-chon__noi-dung"><span class="the-chon__ten">${VN.bt('cong', 'bt--nho')} Giao đến địa chỉ khác</span><span class="the-chon__mo-ta">Nhập người nhận và địa chỉ mới.</span></span></label>`;
      tt.diaChi = macDinh.id;
    }
    capNhatKhuDiaChi();
    VN.$('#tt-so-dia-chi').addEventListener('change', (e) => { tt.diaChi = e.target.value; capNhatKhuDiaChi(); veTomTat(); vePhuongThucGiao(); });
    form.tinh.addEventListener('change', () => { vePhuongThucGiao(); veTomTat(); });
  };
  const capNhatKhuDiaChi = () => {
    const moi = tt.diaChi === 'moi';
    VN.$('#tt-dia-chi-moi').hidden = !moi;
    VN.$('#tt-luu-dc-nhan').hidden = !moi || !u;
  };
  const diaChiDaChon = () => (tt.diaChi === 'moi' || !u ? null : (u.diaChi || []).find((d) => d.id === tt.diaChi));
  const tinhNhan = () => { const d = diaChiDaChon(); return d ? d.tinh : form.tinh.value; };

  /* ================= 2 & 3. GIAO HÀNG, THANH TOÁN ================= */
  const ngayDuKien = (pt) => {
    if (pt.ma === 'hoa-toc') return new Date().getHours() < 16 ? 'Nhận trong hôm nay' : 'Nhận trong ngày mai';
    const cong = (n) => { const d = new Date(); let them = 0; while (them < n) { d.setDate(d.getDate() + 1); if (d.getDay() !== 0) them++; } return d; };
    return `Dự kiến ${VN.thu(cong(2)).toLowerCase()} ${VN.ngay(cong(2)).slice(0, 5)} – ${VN.thu(cong(4)).toLowerCase()} ${VN.ngay(cong(4)).slice(0, 5)}`;
  };
  const maGiaoDangChon = () => { const r = VN.$('input[name="maGiao"]:checked', form); return r ? r.value : 'tieu-chuan'; };
  const vePhuongThucGiao = () => {
    const khung = VN.$('#tt-ds-giao'); const tinh = tinhNhan();
    let dangChon = maGiaoDangChon();
    if (!duocGiaoMa(dangChon, tinh)) dangChon = 'tieu-chuan';
    const tam = VN.tinhTien(tt.dong, tt.ch, { maUuDai: tt.tc.maUuDai, maGiao: 'tieu-chuan' });
    khung.innerHTML = '<legend class="an-chu">Chọn phương thức giao hàng</legend>' + tt.ch.giaoHang.phuongThuc.map((pt) => {
      const duocGiao = duocGiaoMa(pt.ma, tinh);
      const mienPhi = (pt.mienPhiTheoDon && tam.duMienPhi) || (tam.uuDai && tam.uuDai.loai === 'mien-phi-giao');
      return `<label class="the-chon"><input type="radio" name="maGiao" value="${pt.ma}"${pt.ma === dangChon ? ' checked' : ''}${duocGiao ? '' : ' disabled'}>
        <span class="the-chon__noi-dung"><span class="the-chon__ten">${VN.thoat(pt.ten)}</span>
        <span class="the-chon__gia">${mienPhi ? '<span class="chu-ngoc">Miễn phí</span>' : VN.tien(pt.phi)}</span>
        <span class="the-chon__mo-ta">${duocGiao ? `${VN.thoat(pt.thoiGian)} · ${ngayDuKien(pt)}` : `Chỉ áp dụng tại ${pt.apDung.map((x) => x.replace('Thành phố ', 'TP. ')).join(' và ')}`}</span></span></label>`;
    }).join('');
  };
  const duocGiaoMa = (ma, tinh) => { const pt = tt.ch.giaoHang.phuongThuc.find((p) => p.ma === ma); return !!pt && (pt.apDung === 'toan-quoc' || (!!tinh && pt.apDung.includes(tinh))); };

  const vePhuongThuc = () => {
    vePhuongThucGiao();
    VN.$('#tt-ds-thanh-toan').innerHTML = '<legend class="an-chu">Chọn phương thức thanh toán</legend>' + tt.ch.thanhToan.map((p, i) => `
      <label class="the-chon the-chon--tt"><input type="radio" name="phuongThuc" value="${p.ma}"${i === 0 ? ' checked' : ''}>
        <span class="the-chon__noi-dung"><span class="the-chon__ten">${VN.thoat(p.ten)}</span>
        <span class="the-chon__gia the-chon__bt">${VN.bt(BIEU_TUONG[p.ma] || 'the')}</span>
        <span class="the-chon__mo-ta">${VN.thoat(p.moTa)}</span></span></label>`).join('');
    form.addEventListener('change', (e) => { if (e.target.name === 'maGiao') veTomTat(); });
  };

  /* ================= 4. QUÀ TẶNG ================= */
  const khoiTaoQuaTang = () => {
    form.goiQua.checked = !!tt.tc.goiQua; form.loiNhan.value = tt.tc.loiNhan || '';
    const dem = () => { VN.$('#tt-dem-loi-nhan').textContent = `${form.loiNhan.value.length}/150`; };
    dem(); form.loiNhan.addEventListener('input', dem);
  };

  /* ================= TÓM TẮT ĐƠN ================= */
  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  const tinhHienTai = () => VN.tinhTien(tt.dong, tt.ch, { maUuDai: tt.tc.maUuDai, maGiao: maGiaoDangChon() });
  const veTomTat = () => {
    const t = tinhHienTai();
    const sl = tt.dong.reduce((a, d) => a + d.soLuong, 0);
    VN.$('#tt-so-sp').textContent = `(${sl})`;
    VN.$('#tt-ds-sp').innerHTML = tt.dong.map((d) => `
      <li class="tt-sp">
        <span class="tt-sp__anh"><img src="${VN.anh(d.sp.anh[0])}" alt="" width="72" height="72"${VN.laAnhChup(d.sp.anh[0]) ? ' class="la-anh-chup"' : ''}><span class="tt-sp__sl so-deu" aria-label="Số lượng">${d.soLuong}</span></span>
        <span class="tt-sp__chu"><strong>${VN.thoat(d.sp.ten)}</strong>
          <small>${[d.ma, d.mau, d.size ? 'Size ' + d.size : ''].filter(Boolean).map(VN.thoat).join(' · ')}</small>
          ${d.khacChu ? `<small class="tt-sp__khac">Khắc “<span class="kieu-${VN.thoat(d.kieuChu || 'co-dien')}">${VN.thoat(d.khacChu)}</span>” · ${TEN_KIEU[d.kieuChu] || 'Cổ điển'}</small>` : ''}</span>
        <span class="tt-sp__gia so-deu">${VN.tien(d.thanhTien)}</span>
      </li>`).join('');
    VN.$('#tt-tien').innerHTML = `
      <div><dt>Tạm tính</dt><dd class="so-deu">${VN.tien(t.tamTinh)}</dd></div>
      ${t.uuDai && t.giam ? `<div class="dong-tien__giam"><dt>Ưu đãi <span class="nhan nhan--vang nhan--tron">${VN.thoat(t.uuDai.ma)}</span></dt><dd class="so-deu">−${VN.tien(t.giam)}</dd></div>` : ''}
      <div><dt>${VN.thoat(t.pt.ten)}</dt><dd class="so-deu">${t.phiGiao ? VN.tien(t.phiGiao) : '<span class="chu-ngoc">Miễn phí</span>'}</dd></div>
      <div class="dong-tien__tong"><dt>Tổng thanh toán</dt><dd class="so-deu">${VN.tien(t.tong)}</dd></div>`;
    const loi = VN.$('#tt-loi-ma');
    loi.innerHTML = tt.tc.maUuDai && t.loi ? `${VN.bt('canh-bao', 'bt--nho')}<span>${t.loi}</span>`
      : t.uuDai ? `<span class="chu-ngoc">${VN.bt('dau-tich', 'bt--nho')} ${VN.thoat(t.uuDai.moTa)} · <button type="button" class="lien-ket" id="tt-bo-ma">Bỏ mã</button></span>` : '';
    VN.$('#tt-ma').closest('.truong').classList.toggle('co-loi', !!(tt.tc.maUuDai && t.loi));
    VN.$('#nut-dat-hang').textContent = `Đặt hàng · ${VN.tien(t.tong)}`;
    return t;
  };
  VN.$('#tt-ap-ma').addEventListener('click', () => {
    const ma = VN.$('#tt-ma').value.trim().toUpperCase();
    VN.$('#tt-ma').value = ma;
    if (ma && !tt.ch.maUuDai.some((x) => x.ma === ma)) {
      VN.$('#tt-loi-ma').innerHTML = `${VN.bt('canh-bao', 'bt--nho')}<span>Mã ưu đãi không tồn tại hoặc đã hết hạn.</span>`;
      VN.$('#tt-ma').closest('.truong').classList.add('co-loi'); return;
    }
    tt.tc = VN.tuyChonGio.ghi({ maUuDai: ma });
    vePhuongThucGiao(); veTomTat();
  });
  VN.$('#tt-ma').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); VN.$('#tt-ap-ma').click(); } });
  VN.$('#tt-loi-ma').addEventListener('click', (e) => {
    if (e.target.id !== 'tt-bo-ma') return;
    tt.tc = VN.tuyChonGio.ghi({ maUuDai: '' }); VN.$('#tt-ma').value = ''; vePhuongThucGiao(); veTomTat();
  });

  /* ================= KIỂM TRA & ĐẶT HÀNG ================= */
  const kiemTra = (input, dk, thongDiep) => { VN.baoLoiTruong(input, dk ? '' : thongDiep); return dk; };
  form.addEventListener('input', (e) => { if (e.target.closest('.truong.co-loi') && e.target.matches('.o-nhap, .o-chon')) VN.baoLoiTruong(e.target, ''); });

  const kiemTraForm = () => {
    const ketQua = [];
    if (tt.diaChi === 'moi') {
      ketQua.push(
        kiemTra(form.hoTen, form.hoTen.value.trim().length >= 2, 'Vui lòng nhập họ tên người nhận.'),
        kiemTra(form.sdt, VN.sdtHopLe(form.sdt.value), 'Số điện thoại gồm 10 số, bắt đầu bằng 03, 05, 07, 08 hoặc 09.'),
        kiemTra(form.tinh, !!form.tinh.value, 'Vui lòng chọn tỉnh / thành phố.'),
        kiemTra(form.phuongXa, form.phuongXa.value.trim().length >= 3, 'Vui lòng nhập phường / xã.'),
        kiemTra(form.diaChi, form.diaChi.value.trim().length >= 3, 'Vui lòng nhập số nhà, tên đường.'),
      );
    }
    ketQua.push(kiemTra(form.email, !form.email.value.trim() || VN.emailHopLe(form.email.value), 'Email chưa hợp lệ, ví dụ: ten@gmail.com (có thể để trống).'));
    if (!u && form.tangNguoiKhac.checked) ketQua.push(kiemTra(form.sdtNguoiDat, VN.sdtHopLe(form.sdtNguoiDat.value), 'Nhập số điện thoại của bạn để tra cứu đơn và bảo hành.'));
    const coGiao = !!VN.$('input[name="maGiao"]:checked', form);
    if (!coGiao) VN.thongBao({ tieuDe: 'Chưa chọn phương thức giao hàng', loai: 'loi' });
    ketQua.push(!!coGiao);
    ketQua.push(kiemTra(form.dongY, form.dongY.checked, 'Vui lòng xác nhận đã kiểm tra đơn hàng và đồng ý chính sách.'));
    const ok = ketQua.every(Boolean);
    if (!ok) {
      const dau = VN.$('.truong.co-loi input, .truong.co-loi select, .truong.co-loi textarea', form);
      if (dau) { dau.scrollIntoView({ behavior: 'smooth', block: 'center' }); setTimeout(() => dau.focus({ preventScroll: true }), 350); }
    }
    return ok;
  };

  const thongBaoChung = (html) => {
    const hop = VN.$('#tt-loi-chung');
    hop.hidden = !html; hop.innerHTML = html ? `${VN.bt('canh-bao')}<span>${html}</span>` : '';
    if (html) hop.scrollIntoView({ behavior: 'smooth', block: 'center' });
  };

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (tt.dangGui || !tt.ch) return;
    thongBaoChung('');
    if (!kiemTraForm()) return;
    const nut = VN.$('#nut-dat-hang');
    tt.dangGui = true; nut.disabled = true; nut.classList.add('dang-xu-ly'); nut.textContent = 'Đang kiểm tra đơn hàng';

    // FR10: kiểm tra lại giá & khả năng bán ngay trước khi tạo đơn
    const dongMoi = await VN.gioHang.chiTiet();
    const doiGia = dongMoi.length !== tt.dong.length || dongMoi.some((d, i) => !tt.dong[i] || d.donGia !== tt.dong[i].donGia || d.soLuong !== tt.dong[i].soLuong);
    if (!dongMoi.length) { location.replace(VN.url('gioHang')); return; }
    if (doiGia) {
      tt.dong = dongMoi; veTomTat();
      thongBaoChung('Giá hoặc số lượng trong giỏ vừa thay đổi. Vui lòng kiểm tra lại tổng tiền trước khi đặt hàng.');
      tt.dangGui = false; nut.disabled = false; nut.classList.remove('dang-xu-ly'); veTomTat();
      return;
    }
    const t = tinhHienTai();
    const ma = t.uuDai ? t.uuDai.ma : '';
    const dc = diaChiDaChon();
    const nguoiNhan = dc
      ? { hoTen: dc.hoTen, sdt: dc.sdt, email: form.email.value.trim(), tinh: dc.tinh, phuongXa: dc.phuongXa, diaChi: dc.diaChi, ghiChu: form.ghiChu.value.trim() }
      : { hoTen: form.hoTen.value.trim(), sdt: form.sdt.value.replace(/[\s.]/g, ''), email: form.email.value.trim(), tinh: form.tinh.value, phuongXa: form.phuongXa.value.trim(), diaChi: form.diaChi.value.trim(), ghiChu: form.ghiChu.value.trim() };
    const phuongThuc = (VN.$('input[name="phuongThuc"]:checked', form) || {}).value || 'COD';
    // Mã khách hàng = số điện thoại: tài khoản -> số trong hồ sơ; khách mua tặng -> số người đặt; còn lại -> số người nhận
    const sdtKhach = u ? (u.sdt || nguoiNhan.sdt) : (form.tangNguoiKhac.checked ? form.sdtNguoiDat.value : nguoiNhan.sdt);

    const don = VN.donHang.tao({
      sanPham: dongMoi.map((d) => ({
        ma: d.ma, ten: d.sp.ten, anh: d.sp.anh[0], chatLieu: d.sp.chatLieu, mau: d.mau || '', size: d.size || null,
        khacChu: d.khacChu || '', kieuChu: d.khacChu ? (d.kieuChu || 'co-dien') : '', soLuong: d.soLuong, donGia: d.donGia, laNhan: !!d.sp.canChonSize,
      })),
      tamTinh: t.tamTinh, giamGia: t.giam, maUuDai: ma, phiGiao: t.phiGiao, tongTien: t.tong,
      giaoHang: { ma: t.pt.ma, ten: t.pt.ten }, nguoiNhan,
      goiQua: form.goiQua.checked, loiNhan: form.loiNhan.value.trim(),
      thanhToan: { phuongThuc, trangThai: 'Pending', maGiaoDich: null },
      sdtKhach,
    });

    // Lưu địa chỉ mới vào sổ địa chỉ nếu khách chọn
    if (u && !dc && form.luuDiaChi.checked) {
      const ds = (VN.taiKhoan.hienTai().diaChi || []).slice();
      const trung = ds.some((x) => VN.diaChiDay(x) === VN.diaChiDay(nguoiNhan) && x.sdt === nguoiNhan.sdt);
      if (!trung) {
        ds.push({ id: 'DC' + Date.now().toString(36).toUpperCase(), hoTen: nguoiNhan.hoTen, sdt: nguoiNhan.sdt, tinh: nguoiNhan.tinh, phuongXa: nguoiNhan.phuongXa, diaChi: nguoiNhan.diaChi, macDinh: !ds.length });
        VN.taiKhoan.capNhat({ diaChi: ds });
      }
    }
    VN.gioHang.xoaHet();
    VN.tuyChonGio.xoa();

    if (phuongThuc === 'VNPAY' || phuongThuc === 'MOMO') {
      nut.textContent = 'Đang chuyển đến cổng thanh toán';
      await VN.congThanhToan.mo(don);
    }
    location.href = VN.url('ketQuaDatHang', { ma: don.ma });
  });
})();
