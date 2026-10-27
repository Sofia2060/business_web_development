/* =====================================================================
   TÀI KHOẢN – Đăng ký / Đăng nhập (FR1, FR2), hồ sơ, sổ địa chỉ, size nhẫn mặc định,
   đổi mật khẩu, khôi phục dữ liệu trải nghiệm.
   Ghi chú tích hợp: VN.taiKhoan.* đang lưu bằng localStorage, back-end thay bằng API.
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
    return t && /^\/(?!\/)/.test(t) ? t : '';
  })();

  /* ================= TIỆN ÍCH BIỂU MẪU ================= */
  const loiForm = (form, thongDiep) => {
    const hop = VN.$('[data-loi-form]', form);
    if (!hop) return;
    hop.hidden = !thongDiep;
    hop.innerHTML = thongDiep ? `${VN.bt('canh-bao')}<span>${thongDiep}</span>` : '';
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
      VN.$('#tk-tiep-chu').textContent = tiep.includes('thanh-toan')
        ? 'Vui lòng đăng nhập để tiếp tục thanh toán – giỏ hàng của bạn vẫn được giữ nguyên.'
        : 'Vui lòng đăng nhập để tiếp tục.';
    }
    if (VN.thamSo('dangky')) moTab('dang-ky', false);
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
    setTimeout(() => { if (tiep) location.href = tiep; else location.reload(); }, 450);
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
      const nguoi = await VN.taiKhoan.dangNhap(formDn.email.value, formDn.matKhau.value, formDn.ghiNho.checked);
      sauKhiVao(nguoi, false);
    } catch (loi) {
      loiForm(formDn, loi.message);
      dangXuLy(nut, false, 'Đăng nhập');
      formDn.matKhau.select();
    }
  });
  VN.$('[data-dang-nhap-demo]').addEventListener('click', () => {
    formDn.email.value = VN.DEMO.email; formDn.matKhau.value = VN.DEMO.matKhau;
    formDn.requestSubmit();
  });
  VN.$('[data-quen-mk]').addEventListener('click', () => VN.thongBao({
    tieuDe: 'Khôi phục mật khẩu', noiDung: 'Bản đồ án chưa gửi email thật. Vui lòng liên hệ hotline 1900 0000 (minh họa) để được hỗ trợ đặt lại mật khẩu.', thoiGian: 6000,
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
      const nguoi = await VN.taiKhoan.dangKy({ hoTen: formDk.hoTen.value, email: formDk.email.value, matKhau: mk, sdt: formDk.sdt.value.replace(/[\s.]/g, '') });
      if (formDk.sizeNhan.value) VN.taiKhoan.capNhat({ sizeNhan: Number(formDk.sizeNhan.value) });
      sauKhiVao(nguoi, true);
    } catch (loi) {
      loiForm(formDk, loi.message);
      dangXuLy(nut, false, 'Tạo tài khoản');
    }
  });

  /* ================= KHU TÀI KHOẢN ================= */
  const veTaiKhoan = (u) => {
    khuXacThuc.hidden = true; khuTaiKhoan.hidden = false;
    document.title = 'Tài khoản của tôi – Vinora Jewelry';
    VN.$$('[data-ten-goi]').forEach((el) => { el.textContent = VN.taiKhoan.tenGoi(u); });
    veTongQuan();
    // Hồ sơ
    const f = VN.$('#form-ho-so');
    f.hoTen.value = u.hoTen || ''; f.sdt.value = u.sdt || ''; f.email.value = u.email; f.ngaySinh.value = u.ngaySinh || '';
    f.ngaySinh.max = VN.ngayIso(new Date());
    VN.dienChonSize(f.sizeNhan, u.sizeNhan);
    veDiaChi();
    VN.$('#khoi-demo').hidden = u.email !== VN.DEMO.email;
  };

  const veTongQuan = () => {
    const don = VN.donHang.cuaToi(); const the = VN.baoHanh.cuaToi();
    const lich = VN.lichHen.cuaToi().filter((l) => ['Pending', 'Confirmed'].includes(l.trangThai));
    const o = [
      ['hop-hang', 'Đơn đang xử lý', don.filter((d) => ['Pending', 'Shipping'].includes(d.trangThai)).length, VN.url('donHang')],
      ['xac-nhan', 'Đơn đã nhận', don.filter((d) => d.trangThai === 'Delivered').length, VN.url('donHang', { tab: 'Delivered' })],
      ['khien', 'Thẻ bảo hành', the.length, VN.url('congBaoHanh')],
      ['lich', 'Lịch hẹn sắp tới', lich.length, VN.url('congBaoHanh', { tab: 'lich-hen' })],
    ];
    VN.$('#tong-quan-tk').innerHTML = o.map(([bt, ten, n, url]) => `<a class="o-tong-quan" href="${url}">${VN.bt(bt)}<strong class="so-deu">${n}</strong><span>${ten}</span></a>`).join('');
  };

  const formHs = VN.$('#form-ho-so');
  xoaLoiKhiNhap(formHs);
  formHs.addEventListener('submit', (e) => {
    e.preventDefault();
    const ok = [
      kiemTra(formHs.hoTen, formHs.hoTen.value.trim().split(/\s+/).length >= 2, 'Vui lòng nhập đầy đủ họ và tên.'),
      kiemTra(formHs.sdt, VN.sdtHopLe(formHs.sdt.value), 'Số điện thoại gồm 10 số, bắt đầu bằng 03, 05, 07, 08 hoặc 09.'),
    ].every(Boolean);
    if (!ok) return;
    const u = VN.taiKhoan.capNhat({
      hoTen: formHs.hoTen.value.trim(), sdt: formHs.sdt.value.replace(/[\s.]/g, ''), ngaySinh: formHs.ngaySinh.value,
      sizeNhan: formHs.sizeNhan.value ? Number(formHs.sizeNhan.value) : null,
    });
    VN.$$('[data-ten-goi]').forEach((el) => { el.textContent = VN.taiKhoan.tenGoi(u); });
    VN.thongBao({ tieuDe: 'Đã lưu hồ sơ', noiDung: u.sizeNhan ? `Size nhẫn mặc định: ${u.sizeNhan}.` : '', loai: 'thanh-cong' });
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
  const luuDs = (ds) => {
    if (ds.length && !ds.some((d) => d.macDinh)) ds[0].macDinh = true;
    VN.taiKhoan.capNhat({ diaChi: ds }); veDiaChi();
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
  VN.$('#ds-dia-chi').addEventListener('click', async (e) => {
    const u = VN.taiKhoan.hienTai(); const ds = (u.diaChi || []).slice();
    const sua = e.target.closest('[data-sua-dc]'); const md = e.target.closest('[data-mac-dinh-dc]'); const xoa = e.target.closest('[data-xoa-dc]');
    if (sua) moHopDiaChi(ds.find((d) => d.id === sua.dataset.suaDc));
    if (md) { ds.forEach((d) => { d.macDinh = d.id === md.dataset.macDinhDc; }); luuDs(ds); VN.thongBao({ tieuDe: 'Đã đặt địa chỉ mặc định', loai: 'thanh-cong' }); }
    if (xoa) {
      const dongY = await VN.xacNhan({ nhan: 'Sổ địa chỉ', tieuDe: 'Xóa địa chỉ này?', noiDung: 'Địa chỉ đã dùng cho các đơn trước vẫn được giữ trong đơn hàng.', chuDongY: 'Xóa', nguy: true });
      if (dongY) { luuDs(ds.filter((d) => d.id !== xoa.dataset.xoaDc)); VN.thongBao({ tieuDe: 'Đã xóa địa chỉ' }); }
    }
  });
  hopDc.addEventListener('click', (e) => { if (e.target.closest('[data-dong]')) VN.dongHopThoai(hopDc); });
  formDc.addEventListener('submit', (e) => {
    e.preventDefault();
    const ok = [
      kiemTra(formDc.hoTen, formDc.hoTen.value.trim().length >= 2, 'Vui lòng nhập tên người nhận.'),
      kiemTra(formDc.sdt, VN.sdtHopLe(formDc.sdt.value), 'Số điện thoại gồm 10 số, bắt đầu bằng 03, 05, 07, 08 hoặc 09.'),
      kiemTra(formDc.tinh, !!formDc.tinh.value, 'Vui lòng chọn tỉnh / thành phố.'),
      kiemTra(formDc.phuongXa, formDc.phuongXa.value.trim().length >= 3, 'Vui lòng nhập phường / xã.'),
      kiemTra(formDc.diaChi, formDc.diaChi.value.trim().length >= 3, 'Vui lòng nhập số nhà, tên đường.'),
    ].every(Boolean);
    if (!ok) { VN.$('.co-loi input, .co-loi select', formDc).focus(); return; }
    const u = VN.taiKhoan.hienTai(); let ds = (u.diaChi || []).slice();
    const dc = { id: formDc.id.value || 'DC' + Date.now().toString(36).toUpperCase(), hoTen: formDc.hoTen.value.trim(), sdt: formDc.sdt.value.replace(/[\s.]/g, ''), tinh: formDc.tinh.value, phuongXa: formDc.phuongXa.value.trim(), diaChi: formDc.diaChi.value.trim(), macDinh: formDc.macDinh.checked };
    if (dc.macDinh) ds.forEach((d) => { d.macDinh = false; });
    const i = ds.findIndex((d) => d.id === dc.id);
    if (i > -1) ds[i] = dc; else ds.push(dc);
    luuDs(ds);
    VN.dongHopThoai(hopDc);
    VN.thongBao({ tieuDe: i > -1 ? 'Đã cập nhật địa chỉ' : 'Đã thêm địa chỉ mới', loai: 'thanh-cong' });
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

  /* ---------- Khôi phục dữ liệu trải nghiệm ---------- */
  VN.$('#nut-khoi-phuc-demo').addEventListener('click', async () => {
    const dongY = await VN.xacNhan({ nhan: 'Dữ liệu trải nghiệm', tieuDe: 'Khôi phục dữ liệu demo?', noiDung: 'Đơn hàng, thẻ bảo hành, lịch hẹn và đánh giá của tài khoản demo sẽ trở về trạng thái ban đầu.', chuDongY: 'Khôi phục' });
    if (!dongY) return;
    await VN.demo.khoiPhuc();
    veTongQuan();
    VN.thongBao({ tieuDe: 'Đã khôi phục dữ liệu demo', noiDung: 'Mở “Đơn hàng của tôi” để trình diễn lại toàn bộ luồng.', loai: 'thanh-cong' });
  });

  /* ================= KHỞI TẠO ================= */
  const u = VN.taiKhoan.hienTai();
  if (u) {
    if (tiep) { location.replace(tiep); return; }
    if (u.email === VN.DEMO.email) VN.demo.damBaoDuLieu(u.id).then(veTongQuan);
    veTaiKhoan(u);
  } else veXacThuc();
})();
