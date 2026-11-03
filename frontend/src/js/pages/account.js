/* =====================================================================
   TÀI KHOẢN – Đăng ký / Đăng nhập (FR1, FR2), hồ sơ, sổ địa chỉ, size nhẫn mặc định,
   đổi mật khẩu. Dữ liệu lấy từ API qua VN.taiKhoan (session.js).
   Đơn hàng đặt không cần tài khoản được liên kết lúc đăng ký (số điện thoại + mã xác minh).
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const khuXacThuc = VN.$('#khu-xac-thuc');
  const khuTaiKhoan = VN.$('#khu-tai-khoan');
  if (!khuXacThuc || !khuTaiKhoan) return;

  /* Chỉ chuyển tiếp đến đường dẫn nội bộ (chống chuyển hướng mở) */
  const tiep = (() => {
    const t = VN.thamSo('tiep');
    return t && /^\/(?![\/\\])/.test(t) ? t : '';     // "/\host" is read as "//host" by browsers
  })();
  /* Ô đăng nhập dùng chung: trang quản trị chuyển về đây khi chưa đăng nhập quản trị */
  const tiepQuanTri = /quan-?tri|\/admin\//.test(tiep);

  /* ================= TIỆN ÍCH BIỂU MẪU ================= */
  const loiForm = (form, thongDiep) => {
    const hop = VN.$('[data-loi-form]', form);
    if (!hop) return;
    hop.hidden = !thongDiep;
    hop.innerHTML = thongDiep ? `${VN.bt('canh-bao')}<span>${VN.thoat(thongDiep)}</span>` : '';
  };
  const kiemTra = (input, dieuKien, thongDiep) => {
    const sai = !dieuKien;
    VN.baoLoiTruong(input, sai ? thongDiep : '');
    return !sai;
  };
  const xoaLoiKhiNhap = (form) => form.addEventListener('input', (e) => {
    if (e.target.matches('.o-nhap, .o-chon') && e.target.closest('.truong.co-loi')) VN.baoLoiTruong(e.target, '');
  });
  const dangXuLy = (nut, bat, chu) => {
    nut.disabled = bat; nut.classList.toggle('dang-xu-ly', bat);
    if (chu) nut.textContent = chu;
  };
  VN.$$('[data-hien-mk]').forEach((b) => b.addEventListener('click', () => {
    const o = VN.$('#' + b.dataset.hienMk); const hien = o.type === 'password';
    o.type = hien ? 'text' : 'password';
    b.setAttribute('aria-pressed', String(hien));
    b.setAttribute('aria-label', hien ? 'Ẩn mật khẩu' : 'Hiện mật khẩu');
  }));
  VN.$$('[data-chon-size-nhan]').forEach((s) => VN.dienChonSize(s));

  /* ================= ĐĂNG NHẬP / ĐĂNG KÝ ================= */
  const veXacThuc = () => {
    khuXacThuc.hidden = false; khuTaiKhoan.hidden = true;
    document.title = 'Đăng nhập – Vinora Jewelry';
    if (tiep) {
      VN.$('#tk-tiep').hidden = false;
      VN.$('#tk-tiep-chu').textContent = tiepQuanTri ? 'Vui lòng đăng nhập để tiếp tục.' : /thanh-?toan/.test(tiep)
        ? 'Đăng nhập để dùng sổ địa chỉ đã lưu – giỏ hàng vẫn được giữ nguyên. Bạn cũng có thể quay lại và đặt hàng không cần tài khoản.'
        : 'Vui lòng đăng nhập để tiếp tục.';
    }
    if (VN.thamSo('dangky')) moTab('dang-ky', false);
    const sdt = VN.thamSo('sdt'); if (sdt && VN.sdtHopLe(sdt)) VN.$('#dk-sdt').value = sdt;
  };

  const tab = { 'dang-nhap': VN.$('#tab-dang-nhap'), 'dang-ky': VN.$('#tab-dang-ky') };
  const moTab = (ten, focus = true) => {
    Object.entries(tab).forEach(([k, b]) => {
      const chon = k === ten;
      b.setAttribute('aria-selected', String(chon)); b.tabIndex = chon ? 0 : -1;
      VN.$('#form-' + k).hidden = !chon;
    });
    if (focus) VN.$(`#form-${ten} .o-nhap`).focus();
  };
  Object.entries(tab).forEach(([k, b]) => {
    b.addEventListener('click', () => moTab(k));
    b.addEventListener('keydown', (e) => {
      if (!['ArrowLeft', 'ArrowRight'].includes(e.key)) return;
      const khac = k === 'dang-nhap' ? 'dang-ky' : 'dang-nhap';
      tab[khac].focus(); moTab(khac, false);
    });
  });

  const sauKhiVao = (nguoi, laMoi) => {
    VN.thongBao({ tieuDe: laMoi ? 'Tạo tài khoản thành công' : `Chào mừng ${VN.taiKhoan.tenGoi(nguoi)} trở lại`, loai: 'thanh-cong' });
    setTimeout(() => { if (tiep && !tiepQuanTri) location.href = tiep; else location.replace(VN.url('taiKhoan')); }, 450);
  };

  const formDn = VN.$('#form-dang-nhap');
  xoaLoiKhiNhap(formDn);
  formDn.addEventListener('submit', async (e) => {
    e.preventDefault(); loiForm(formDn, '');
    const ok = [
      kiemTra(formDn.email, VN.emailHopLe(formDn.email.value), 'Email chưa hợp lệ, ví dụ: ten@gmail.com'),
      kiemTra(formDn.matKhau, formDn.matKhau.value.length > 0, 'Vui lòng nhập mật khẩu.'),
    ].every(Boolean);
    if (!ok) { VN.$('.co-loi .o-nhap', formDn).focus(); return; }
    const nut = VN.$('[type="submit"]', formDn);
    dangXuLy(nut, true, 'Đang đăng nhập');
    try {
      // Máy chủ cho biết vai trò: quản trị -> trang quản trị, còn lại -> tài khoản khách hàng
      const nguoi = await VN.taiKhoan.dangNhap(formDn.email.value, formDn.matKhau.value, formDn.ghiNho.checked);
      if (nguoi.vaiTro === 'admin') {
        VN.thongBao({ tieuDe: 'Đăng nhập quản trị thành công', loai: 'thanh-cong' });
        setTimeout(() => { location.href = tiepQuanTri ? tiep : VN.url('qtTongQuan'); }, 400);
        return;
      }
      sauKhiVao(nguoi, false);
    } catch (loi) {
      loiForm(formDn, loi.message);
      dangXuLy(nut, false, 'Đăng nhập');
      formDn.matKhau.select();
    }
  });
  VN.$('[data-sang-dang-ky]').addEventListener('click', () => moTab('dang-ky'));
  VN.$('[data-quen-mk]').addEventListener('click', () => VN.thongBao({
    tieuDe: 'Khôi phục mật khẩu', noiDung: 'Vui lòng liên hệ hotline 1900 0000 để được hỗ trợ đặt lại mật khẩu.', thoiGian: 6000,
  }));

  const formDk = VN.$('#form-dang-ky');
  xoaLoiKhiNhap(formDk);
  const veQuyTac = () => {
    const mk = formDk.matKhau.value;
    const dat = { 'do-dai': mk.length >= 8, hoa: /[A-Z]/.test(mk), thuong: /[a-z]/.test(mk), so: /\d/.test(mk) };
    VN.$$('[data-quy-tac]', formDk).forEach((li) => li.classList.toggle('dat', dat[li.dataset.quyTac]));
  };
  formDk.matKhau.addEventListener('input', veQuyTac);
  formDk.addEventListener('submit', async (e) => {
    e.preventDefault(); loiForm(formDk, '');
    const mk = formDk.matKhau.value; const loiMk = VN.kiemTraMatKhau(mk);
    const ok = [
      kiemTra(formDk.hoTen, formDk.hoTen.value.trim().split(/\s+/).length >= 2, 'Vui lòng nhập đầy đủ họ và tên.'),
      kiemTra(formDk.email, VN.emailHopLe(formDk.email.value), 'Email chưa hợp lệ, ví dụ: ten@gmail.com'),
      kiemTra(formDk.sdt, VN.sdtHopLe(formDk.sdt.value), 'Số điện thoại gồm 10 số, bắt đầu bằng 03, 05, 07, 08 hoặc 09.'),
      kiemTra(formDk.matKhau, !loiMk.length, 'Mật khẩu cần ' + loiMk.join(', ') + '.'),
      kiemTra(formDk.nhapLai, formDk.nhapLai.value === mk && mk.length > 0, 'Mật khẩu nhập lại chưa khớp.'),
      kiemTra(formDk.dongY, formDk.dongY.checked, 'Vui lòng đồng ý với chính sách để tạo tài khoản.'),
    ].every(Boolean);
    if (!ok) { const dau = VN.$('.co-loi input, .co-loi select', formDk); if (dau) dau.focus(); return; }
    const nut = VN.$('[type="submit"]', formDk);
    dangXuLy(nut, true, 'Đang tạo tài khoản');
    try {
      const nguoi = await VN.taiKhoan.dangKy({
        hoTen: formDk.hoTen.value.trim(), email: formDk.email.value, matKhau: mk, sdt: VN.chuanSdt(formDk.sdt.value),
        otp: formDk.otp.value.trim(), sizeNhan: formDk.sizeNhan.value ? Number(formDk.sizeNhan.value) : null,
      });
      // Số điện thoại này từng đặt hàng không cần tài khoản: máy chủ đã chuyển các đơn đó vào tài khoản mới
      if (nguoi.donDaLienKet) {
        VN.thongBao({ tieuDe: 'Tạo tài khoản thành công', noiDung: `Đã liên kết ${nguoi.donDaLienKet} đơn hàng đặt bằng số điện thoại này vào tài khoản.`, loai: 'thanh-cong', thoiGian: 7000 });
        setTimeout(() => location.replace(VN.url('donHang')), 900);
        return;
      }
      sauKhiVao(nguoi, true);
    } catch (loi) {
      if (loi.lyDo === 'otp_required' || loi.lyDo === 'otp_invalid') {
        VN.$('#dk-khung-otp').hidden = false;
        VN.$('#dk-otp-goi-y').textContent = `Cửa hàng chưa gửi tin nhắn thật: bản demo dùng mã 123456 cho số ${VN.anSdt(formDk.sdt.value)}.`;
        VN.baoLoiTruong(formDk.otp, loi.lyDo === 'otp_invalid' ? loi.message : '');
        loiForm(formDk, loi.lyDo === 'otp_required' ? loi.message : '');
        formDk.otp.focus();
      } else loiForm(formDk, loi.message);
      dangXuLy(nut, false, 'Tạo tài khoản');
    }
  });

  /* ================= KHU TÀI KHOẢN ================= */
  const veTaiKhoan = (u) => {
    khuXacThuc.hidden = true; khuTaiKhoan.hidden = false;
    document.title = 'Tài khoản của tôi – Vinora Jewelry';
    VN.$$('[data-ten-goi]').forEach((el) => { el.textContent = VN.taiKhoan.tenGoi(u); });
    // Hồ sơ
    const f = VN.$('#form-ho-so');
    f.hoTen.value = u.hoTen || ''; f.sdt.value = u.sdt || ''; f.email.value = u.email; f.ngaySinh.value = u.ngaySinh || '';
    f.ngaySinh.max = VN.ngayIso(new Date());
    VN.dienChonSize(f.sizeNhan, u.sizeNhan);
    veDiaChi();
  };

  const formHs = VN.$('#form-ho-so');
  xoaLoiKhiNhap(formHs);
  formHs.addEventListener('submit', async (e) => {
    e.preventDefault();
    const ok = [
      kiemTra(formHs.hoTen, formHs.hoTen.value.trim().split(/\s+/).length >= 2, 'Vui lòng nhập đầy đủ họ và tên.'),
      kiemTra(formHs.sdt, VN.sdtHopLe(formHs.sdt.value), 'Số điện thoại gồm 10 số, bắt đầu bằng 03, 05, 07, 08 hoặc 09.'),
    ].every(Boolean);
    if (!ok) return;
    try {
      const u = await VN.taiKhoan.capNhat({
        hoTen: formHs.hoTen.value.trim(), sdt: VN.chuanSdt(formHs.sdt.value), ngaySinh: formHs.ngaySinh.value,
        sizeNhan: formHs.sizeNhan.value ? Number(formHs.sizeNhan.value) : null,
      });
      VN.$$('[data-ten-goi]').forEach((el) => { el.textContent = VN.taiKhoan.tenGoi(u); });
      VN.thongBao({ tieuDe: 'Đã lưu hồ sơ', noiDung: u.sizeNhan ? `Size nhẫn mặc định: ${u.sizeNhan}.` : '', loai: 'thanh-cong' });
    } catch (loi) { VN.thongBao({ tieuDe: 'Chưa lưu được hồ sơ', noiDung: VN.thoat(loi.message), loai: 'loi' }); }
  });

  /* ---------- Sổ địa chỉ ---------- */
  const hopDc = VN.$('#hop-dia-chi'); const formDc = VN.$('#form-dia-chi');
  xoaLoiKhiNhap(formDc);
  const veDiaChi = () => {
    const u = VN.taiKhoan.hienTai(); const ds = u.diaChi || [];
    VN.$('#ds-dia-chi').innerHTML = ds.length ? ds.map((d) => `
      <article class="the-dia-chi${d.macDinh ? ' la-mac-dinh' : ''}">
        <div class="the-dia-chi__dau"><strong>${VN.thoat(d.hoTen)}</strong>${d.macDinh ? '<span class="nhan nhan--ngoc">Mặc định</span>' : ''}</div>
        <p class="so-deu">${VN.thoat(d.sdt)}</p>
        <p>${VN.thoat(VN.diaChiDay(d))}</p>
        <div class="the-dia-chi__nut">
          <button type="button" class="nut nut--chu" data-sua-dc="${d.id}">Sửa</button>
          ${d.macDinh ? '' : `<button type="button" class="nut nut--chu" data-mac-dinh-dc="${d.id}">Đặt mặc định</button><button type="button" class="nut nut--chu nut-xoa-dc" data-xoa-dc="${d.id}">Xóa</button>`}
        </div>
      </article>`).join('')
      : '<div class="trong-rong trong-rong--nho"><div class="trong-rong__bieu-tuong">' + VN.bt('ghim') + '</div><p>Chưa có địa chỉ nào. Thêm địa chỉ để thanh toán nhanh hơn.</p></div>';
  };
  const moHopDiaChi = async (dc) => {
    formDc.reset();
    VN.$$('.truong.co-loi', formDc).forEach((t) => t.classList.remove('co-loi'));
    VN.$$('.loi-truong', formDc).forEach((p) => { p.textContent = ''; });
    const u = VN.taiKhoan.hienTai();
    VN.$('#hop-dia-chi-td').textContent = dc ? 'Sửa địa chỉ' : 'Thêm địa chỉ mới';
    formDc.id.value = dc ? dc.id : '';
    formDc.hoTen.value = dc ? dc.hoTen : u.hoTen; formDc.sdt.value = dc ? dc.sdt : (u.sdt || '');
    formDc.phuongXa.value = dc ? dc.phuongXa : ''; formDc.diaChi.value = dc ? dc.diaChi : '';
    formDc.macDinh.checked = dc ? !!dc.macDinh : !(u.diaChi || []).length;
    await VN.dienChonTinh(formDc.tinh, dc ? dc.tinh : '');
    VN.moHopThoai(hopDc);
    formDc.hoTen.focus();
  };
  VN.$('#nut-them-dia-chi').addEventListener('click', () => moHopDiaChi(null));
  const baoLoi = (tieuDe, loi) => VN.thongBao({ tieuDe, noiDung: VN.thoat(loi.message), loai: 'loi' });
  VN.$('#ds-dia-chi').addEventListener('click', async (e) => {
    const ds = VN.taiKhoan.hienTai().diaChi || [];
    const sua = e.target.closest('[data-sua-dc]'); const md = e.target.closest('[data-mac-dinh-dc]'); const xoa = e.target.closest('[data-xoa-dc]');
    if (sua) moHopDiaChi(ds.find((d) => String(d.id) === sua.dataset.suaDc));
    if (md) {
      try { await VN.taiKhoan.datDiaChiMacDinh(md.dataset.macDinhDc); veDiaChi(); VN.thongBao({ tieuDe: 'Đã đặt địa chỉ mặc định', loai: 'thanh-cong' }); } catch (loi) { baoLoi('Chưa đặt được địa chỉ mặc định', loi); }
    }
    if (xoa) {
      const dongY = await VN.xacNhan({ nhan: 'Sổ địa chỉ', tieuDe: 'Xóa địa chỉ này?', noiDung: 'Địa chỉ đã dùng cho các đơn trước vẫn được giữ trong đơn hàng.', chuDongY: 'Xóa', nguy: true });
      if (dongY) { try { await VN.taiKhoan.xoaDiaChi(xoa.dataset.xoaDc); veDiaChi(); VN.thongBao({ tieuDe: 'Đã xóa địa chỉ' }); } catch (loi) { baoLoi('Chưa xóa được địa chỉ', loi); } }
    }
  });
  hopDc.addEventListener('click', (e) => { if (e.target.closest('[data-dong]')) VN.dongHopThoai(hopDc); });
  formDc.addEventListener('submit', async (e) => {
    e.preventDefault();
    const ok = [
      kiemTra(formDc.hoTen, formDc.hoTen.value.trim().length >= 2, 'Vui lòng nhập tên người nhận.'),
      kiemTra(formDc.sdt, VN.sdtHopLe(formDc.sdt.value), 'Số điện thoại gồm 10 số, bắt đầu bằng 03, 05, 07, 08 hoặc 09.'),
      kiemTra(formDc.tinh, !!formDc.tinh.value, 'Vui lòng chọn tỉnh / thành phố.'),
      kiemTra(formDc.phuongXa, formDc.phuongXa.value.trim().length >= 3, 'Vui lòng nhập phường / xã.'),
      kiemTra(formDc.diaChi, formDc.diaChi.value.trim().length >= 3, 'Vui lòng nhập số nhà, tên đường.'),
    ].every(Boolean);
    if (!ok) { VN.$('.co-loi input, .co-loi select', formDc).focus(); return; }
    const id = formDc.id.value ? Number(formDc.id.value) : null;
    const dc = { hoTen: formDc.hoTen.value.trim(), sdt: VN.chuanSdt(formDc.sdt.value), tinh: formDc.tinh.value, phuongXa: formDc.phuongXa.value.trim(), diaChi: formDc.diaChi.value.trim(), macDinh: formDc.macDinh.checked };
    try {
      await VN.taiKhoan.luuDiaChi(dc, id);
      veDiaChi();
      VN.dongHopThoai(hopDc);
      VN.thongBao({ tieuDe: id ? 'Đã cập nhật địa chỉ' : 'Đã thêm địa chỉ mới', loai: 'thanh-cong' });
    } catch (loi) { baoLoi('Chưa lưu được địa chỉ', loi); }
  });

  /* ---------- Đổi mật khẩu ---------- */
  const formMk = VN.$('#form-mat-khau');
  xoaLoiKhiNhap(formMk);
  formMk.addEventListener('submit', async (e) => {
    e.preventDefault();
    const loiMk = VN.kiemTraMatKhau(formMk.moi.value);
    const ok = [
      kiemTra(formMk.cu, formMk.cu.value.length > 0, 'Vui lòng nhập mật khẩu hiện tại.'),
      kiemTra(formMk.moi, !loiMk.length, 'Mật khẩu mới cần ' + loiMk.join(', ') + '.'),
      kiemTra(formMk.nhapLai, formMk.nhapLai.value === formMk.moi.value, 'Mật khẩu nhập lại chưa khớp.'),
    ].every(Boolean);
    if (!ok) return;
    try {
      await VN.taiKhoan.doiMatKhau(formMk.cu.value, formMk.moi.value);
      formMk.reset();
      VN.thongBao({ tieuDe: 'Đã đổi mật khẩu', noiDung: 'Lần đăng nhập sau hãy dùng mật khẩu mới.', loai: 'thanh-cong' });
    } catch (loi) { VN.baoLoiTruong(formMk.cu, loi.message); formMk.cu.focus(); }
  });


  /* ================= KHỞI TẠO ================= */
  VN.sanSang.then(() => {
    const u = VN.taiKhoan.hienTai();
    if (tiepQuanTri) {
      if (VN.quanTri.hienTai()) { location.replace(tiep); return; }
      veXacThuc();                        // cần đăng nhập quản trị, kể cả khi đang đăng nhập tài khoản khách
    } else if (u) {
      if (tiep) { location.replace(tiep); return; }
      veTaiKhoan(u);
    } else veXacThuc();
  });
})();
