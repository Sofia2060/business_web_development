/* =====================================================================
   5.2.5 THANH TOÁN (FR10, FR11)
   - Không bắt buộc đăng nhập: khách mua bằng số điện thoại (mã khách hàng), có tài khoản thì chọn địa chỉ trong sổ
   - Nhập địa chỉ mới theo 34 tỉnh, thành; mua tặng thì ghi thêm số điện thoại người đặt
   - Giao tiêu chuẩn có bảo hiểm (miễn phí từ mức quy định); máy chủ tính lại phí và tổng tiền khi đặt hàng
   - COD, chuyển khoản VietQR, VNPay & MoMo (mô phỏng); mã ưu đãi do máy chủ kiểm tra
   - Đơn thanh toán trực tuyến phải trả trong 15 phút, quá hạn máy chủ tự hủy đơn
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const form = VN.$('#form-thanh-toan');
  if (!form) return;
  let u = null;       // khách có tài khoản (gán khi đã tải phiên đăng nhập); null = đặt hàng không cần tài khoản

  const BIEU_TUONG = { COD: 'hop-hang', BANK: 'qr', VNPAY: 'the', MOMO: 'dien-thoai' };
  /** Mã của lần đặt hàng này: gửi kèm đơn để bấm đặt hai lần vẫn chỉ ra một đơn (crypto.randomUUID chỉ có ở trang bảo mật) */
  const taoMa = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID()
    : '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)));
  const tt = { ch: null, dong: [], tc: VN.tuyChonGio.doc(), diaChi: 'moi', dangGui: false, uuDai: null, loiMa: '', token: taoMa() };

  Promise.all([VN.duLieu.coBan(), VN.sanSang]).then(async ([{ ch }]) => {
    u = VN.taiKhoan.hienTai();
    tt.ch = ch; tt.dong = await VN.gioHang.chiTiet();
    if (!tt.dong.length) { location.replace(VN.url('gioHang')); return; }
    await khoiTaoDiaChi();
    vePhuongThuc();
    khoiTaoQuaTang();
    VN.$('#tt-ma').value = tt.tc.maUuDai || '';
    await kiemTraMa(tt.tc.maUuDai);
    vePhuongThucGiao();
    veTomTat();
    form.removeAttribute('aria-busy');
  }).catch((loi) => {
    console.error(loi);
    VN.thongBao({ tieuDe: 'Chưa tải được dữ liệu', noiDung: 'Vui lòng kiểm tra kết nối mạng rồi tải lại trang.', loai: 'loi' });
  });

  /** Kiểm tra mã ưu đãi với máy chủ; ghi tt.uuDai (dùng được, có số tiền giảm) hoặc tt.loiMa (lý do chưa dùng được) */
  const kiemTraMa = async (ma) => {
    tt.uuDai = null; tt.loiMa = '';
    if (!ma) return;
    try { tt.uuDai = await VN.uuDai.kiemTra(ma); } catch (loi) { tt.loiMa = loi.message; }
  };

  /* ================= 1. ĐỊA CHỈ ================= */
  const khoiTaoDiaChi = async () => {
    const ds = (u && u.diaChi) || [];
    const macDinh = ds.find((d) => d.macDinh) || ds[0];
    await VN.dienChonTinh(form.tinh, '');
    if (u) { form.hoTen.value = u.hoTen || ''; form.sdt.value = u.sdt || ''; }
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
      tt.diaChi = String(macDinh.id);
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
  const diaChiDaChon = () => (tt.diaChi === 'moi' || !u ? null : (u.diaChi || []).find((d) => String(d.id) === String(tt.diaChi)) || null);
  const tinhNhan = () => { const d = diaChiDaChon(); return d ? d.tinh : form.tinh.value; };
  /** Địa chỉ đang nhập trong biểu mẫu (khi giao đến địa chỉ mới) */
  const layDiaChiMoi = () => ({
    hoTen: form.hoTen.value.trim(), sdt: VN.chuanSdt(form.sdt.value), tinh: form.tinh.value,
    phuongXa: form.phuongXa.value.trim(), diaChi: form.diaChi.value.trim(), macDinh: false,
  });

  /* ================= 2 & 3. GIAO HÀNG, THANH TOÁN ================= */
  const ngayDuKien = (pt) => {
    const cong = (n) => { const d = new Date(); let them = 0; while (them < n) { d.setDate(d.getDate() + 1); if (d.getDay() !== 0) them++; } return d; };
    return `Dự kiến ${VN.thu(cong(2)).toLowerCase()} ${VN.ngay(cong(2)).slice(0, 5)} – ${VN.thu(cong(4)).toLowerCase()} ${VN.ngay(cong(4)).slice(0, 5)}`;
  };
  const maGiaoDangChon = () => { const r = VN.$('input[name="maGiao"]:checked', form); return r ? r.value : 'tieu-chuan'; };
  const vePhuongThucGiao = () => {
    const khung = VN.$('#tt-ds-giao'); const tinh = tinhNhan();
    let dangChon = maGiaoDangChon();
    if (!duocGiaoMa(dangChon, tinh)) dangChon = 'tieu-chuan';
    const tam = tinhHienTai();
    khung.innerHTML = '<legend class="an-chu">Chọn phương thức giao hàng</legend>' + tt.ch.giaoHang.phuongThuc.map((pt) => {
      const duocGiao = duocGiaoMa(pt.ma, tinh);
      const mienPhi = pt.mienPhiTheoDon && tam.duMienPhi;
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
  /** Cửa hàng chưa có cột riêng cho quà tặng, nên gói quà, lời nhắn thiệp và ghi chú được ghép vào ghi chú của đơn (tối đa 500 ký tự) */
  const ghepGhiChu = () => {
    const phan = [];
    if (form.goiQua.checked) phan.push('Gói quà Vinora' + (form.loiNhan.value.trim() ? `, thiệp: “${form.loiNhan.value.trim()}”` : ''));
    if (form.ghiChu.value.trim()) phan.push(form.ghiChu.value.trim());
    return phan.join(' | ').slice(0, 500);
  };

  /* ================= TÓM TẮT ĐƠN ================= */
  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  const tinhHienTai = () => VN.tinhTien(tt.dong, tt.ch, { giam: tt.uuDai ? tt.uuDai.discount : 0 });
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
      ${tt.uuDai && t.giam ? `<div class="dong-tien__giam"><dt>Ưu đãi <span class="nhan nhan--vang nhan--tron">${VN.thoat(tt.uuDai.code)}</span></dt><dd class="so-deu">−${VN.tien(t.giam)}</dd></div>` : ''}
      <div><dt>${VN.thoat(t.pt.ten)}</dt><dd class="so-deu">${t.phiGiao ? VN.tien(t.phiGiao) : '<span class="chu-ngoc">Miễn phí</span>'}</dd></div>
      <div class="dong-tien__tong"><dt>Tổng thanh toán</dt><dd class="so-deu">${VN.tien(t.tong)}</dd></div>`;
    const loi = VN.$('#tt-loi-ma');
    loi.innerHTML = tt.tc.maUuDai && tt.loiMa ? `${VN.bt('canh-bao', 'bt--nho')}<span>${VN.thoat(tt.loiMa)}</span>`
      : tt.uuDai ? `<span class="chu-ngoc">${VN.bt('dau-tich', 'bt--nho')} ${VN.thoat(tt.uuDai.name)} · <button type="button" class="lien-ket" id="tt-bo-ma">Bỏ mã</button></span>` : '';
    VN.$('#tt-ma').closest('.truong').classList.toggle('co-loi', !!(tt.tc.maUuDai && tt.loiMa));
    VN.$('#nut-dat-hang').textContent = `Đặt hàng · ${VN.tien(t.tong)}`;
    return t;
  };
  VN.$('#tt-ap-ma').addEventListener('click', async () => {
    if (!tt.ch) return;
    const ma = VN.$('#tt-ma').value.trim().toUpperCase();
    VN.$('#tt-ma').value = ma;
    tt.tc = VN.tuyChonGio.ghi({ maUuDai: ma });
    await kiemTraMa(ma);
    if (tt.uuDai) tt.tc = VN.tuyChonGio.ghi({ maUuDai: tt.uuDai.code });
    vePhuongThucGiao(); veTomTat();
  });
  VN.$('#tt-ma').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); VN.$('#tt-ap-ma').click(); } });
  VN.$('#tt-loi-ma').addEventListener('click', (e) => {
    if (e.target.id !== 'tt-bo-ma') return;
    tt.tc = VN.tuyChonGio.ghi({ maUuDai: '' }); tt.uuDai = null; tt.loiMa = ''; VN.$('#tt-ma').value = ''; vePhuongThucGiao(); veTomTat();
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
    if (tt.tc.maUuDai && tt.loiMa) { thongBaoChung('Mã ưu đãi chưa dùng được. Vui lòng bỏ mã hoặc nhập mã khác trước khi đặt hàng.'); return; }
    const nut = VN.$('#nut-dat-hang');
    const moLai = () => { tt.dangGui = false; nut.disabled = false; nut.classList.remove('dang-xu-ly'); veTomTat(); };
    tt.dangGui = true; nut.disabled = true; nut.classList.add('dang-xu-ly'); nut.textContent = 'Đang kiểm tra đơn hàng';
    let diaChiTam = null;     // địa chỉ vừa thêm trong lần đặt này: bị xóa nếu đặt hàng lỗi (thử lại không sinh địa chỉ trùng), hoặc khách không muốn lưu vào sổ
    try {
      // FR10: kiểm tra lại giá & số lượng ngay trước khi tạo đơn (máy chủ vẫn tính lại khi đặt)
      await VN.gioHang.nap();
      const dongMoi = await VN.gioHang.chiTiet();
      if (!dongMoi.length) { location.replace(VN.url('gioHang')); return; }
      const doiGia = dongMoi.length !== tt.dong.length || dongMoi.some((d, i) => !tt.dong[i] || d.donGia !== tt.dong[i].donGia || d.soLuong !== tt.dong[i].soLuong);
      if (doiGia) {
        tt.dong = dongMoi; await kiemTraMa(tt.tc.maUuDai);
        thongBaoChung('Giá hoặc số lượng trong giỏ vừa thay đổi. Vui lòng kiểm tra lại tổng tiền trước khi đặt hàng.');
        moLai();
        return;
      }
      const phuongThuc = (VN.$('input[name="phuongThuc"]:checked', form) || {}).value || 'COD';
      const chung = { phuongThuc, maUuDai: tt.uuDai ? tt.uuDai.code : '', ghiChu: ghepGhiChu(), token: tt.token };
      let don;
      if (u) {
        const dc = diaChiDaChon();
        let diaChiId = dc ? dc.id : null;
        if (!diaChiId) {
          diaChiId = await VN.taiKhoan.luuDiaChi(layDiaChiMoi(), null);
          diaChiTam = diaChiId;
        }
        nut.textContent = 'Đang tạo đơn hàng';
        don = await VN.donHang.tao(Object.assign({ diaChiId }, chung));
        if (form.luuDiaChi.checked) diaChiTam = null;       // the order exists: an address the customer wants to keep stays
      } else {
        const nn = layDiaChiMoi();
        nut.textContent = 'Đang tạo đơn hàng';
        // Mã khách hàng = số điện thoại: người đặt (khi mua tặng) hoặc chính người nhận
        don = await VN.donHang.tao(Object.assign({
          hoTen: nn.hoTen, sdt: form.tangNguoiKhac.checked ? VN.chuanSdt(form.sdtNguoiDat.value) : nn.sdt, sdtNguoiNhan: nn.sdt,
          diaChi: nn.diaChi, phuongXa: nn.phuongXa, tinh: nn.tinh, dong: await VN.gioHang.dongGuiLen(),
        }, chung));
        await VN.gioHang.xoaHet();
      }
      if (diaChiTam) await VN.taiKhoan.xoaDiaChi(diaChiTam).catch(() => {});   // chờ xong rồi mới chuyển trang, không thì yêu cầu xóa bị hủy
      VN.tuyChonGio.xoa();

      if (phuongThuc === 'VNPAY' || phuongThuc === 'MOMO') {
        nut.textContent = 'Đang chuyển đến cổng thanh toán';
        await VN.congThanhToan.mo({ ma: don.ma, tongTien: don.tongTien, thanhToan: { phuongThuc } });
      }
      location.href = VN.url('ketQuaDatHang', { ma: don.ma });
    } catch (loi) {
      if (diaChiTam) VN.taiKhoan.xoaDiaChi(diaChiTam).catch(() => {});
      thongBaoChung(loi.lyDo === 'phone_has_account'
        ? `${VN.thoat(loi.message)} <a class="lien-ket" href="${VN.url('taiKhoan', { tiep: VN.url('thanhToan') })}">Đăng nhập</a>`
        : VN.thoat(loi.message));
      moLai();
    }
  });
})();
