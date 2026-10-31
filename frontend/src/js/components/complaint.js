/* =====================================================================
   PHẢN ÁNH VẤN ĐỀ ĐƠN HÀNG
   VN.moPhanAnh(maDon, { loai }) -> Promise<phản ánh vừa tạo | null>
   - Loại vấn đề lọc theo trạng thái đơn (lỗi sản phẩm chỉ khi đã nhận, điều chỉnh đơn chỉ khi chờ xử lý)
   - Ảnh minh chứng: đọc bằng FileReader, thu nhỏ bằng canvas (tối đa 640px) trước khi lưu
   - Lưu bằng VN.hoTro.tao, ghi nhật ký vào đơn hàng
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const hop = VN.$('#hop-phan-anh');
  if (!hop) return;
  const form = VN.$('#form-phan-anh');
  let ch = null; let don = null; let anh = []; let ketQua = null; let xong = null;

  const loaiHopLe = (l) => (!l.sauKhiNhan || don.trangThai === 'Delivered') && (!l.chiKhiChoXuLy || don.trangThai === 'Pending');

  /* Thu nhỏ ảnh để lưu gọn (data URL JPEG) */
  const thuNho = (tep) => new Promise((xongAnh, loi) => {
    const r = new FileReader();
    r.onerror = loi;
    r.onload = () => {
      const img = new Image();
      img.onerror = loi;
      img.onload = () => {
        const tl = Math.min(1, 640 / Math.max(img.width, img.height));
        const cv = document.createElement('canvas');
        cv.width = Math.round(img.width * tl); cv.height = Math.round(img.height * tl);
        cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
        xongAnh(cv.toDataURL('image/jpeg', 0.72));
      };
      img.src = r.result;
    };
    r.readAsDataURL(tep);
  });
  const veAnh = () => {
    VN.$('[data-pa-chu-anh]', hop).textContent = anh.length ? `Thêm ảnh (${anh.length}/3)` : 'Chọn ảnh';
    VN.$('.pa-chon-anh', hop).hidden = anh.length >= 3;
    VN.$('[data-pa-xem-anh]', hop).innerHTML = anh.map((a, i) => `<span class="pa-anh"><img src="${a}" alt="Ảnh minh chứng ${i + 1}"><button type="button" class="nut-bt nut-bt--nen" data-bo-anh="${i}" aria-label="Bỏ ảnh ${i + 1}">${VN.bt('dong', 'bt--nho')}</button></span>`).join('');
  };
  form.anh.addEventListener('change', async (e) => {
    const tep = Array.from(e.target.files || []);
    let loi = '';
    if (anh.length + tep.length > 3) loi = 'Chỉ đính kèm tối đa 3 ảnh.';
    else if (tep.some((f) => !f.type.startsWith('image/'))) loi = 'Chỉ nhận tệp ảnh.';
    else if (tep.some((f) => f.size > 8 * 1024 * 1024)) loi = 'Mỗi ảnh tối đa 8 MB.';
    VN.baoLoiTruong(form.anh, loi);
    if (!loi) { try { anh = anh.concat(await Promise.all(tep.map(thuNho))); } catch (x) { VN.baoLoiTruong(form.anh, 'Không đọc được ảnh, vui lòng chọn ảnh khác.'); } }
    form.anh.value = '';
    veAnh();
  });

  const luuY = () => {
    const chon = VN.$('input[name="loai"]:checked', form);
    const l = chon && ch.hoTro.loaiVanDe.find((x) => x.ma === chon.value);
    const hopLuuY = VN.$('[data-pa-luu-y]', hop);
    let chu = '';
    if (l && l.sauKhiNhan && don.ngayNhan) {
      const ngay = Math.floor((Date.now() - new Date(don.ngayNhan)) / 86400000);
      if (ngay > ch.hoTro.phanAnhTrongNgay) chu = `Đơn đã nhận ${ngay} ngày (quá ${ch.hoTro.phanAnhTrongNgay} ngày đổi trả). Vinora vẫn tiếp nhận và xử lý theo chính sách bảo hành trọn đời.`;
    }
    hopLuuY.hidden = !chu; hopLuuY.innerHTML = chu ? `${VN.bt('thong-tin')}<span>${chu}</span>` : '';
  };

  hop.addEventListener('click', (e) => {
    if (e.target.closest('[data-dong-pa]')) { VN.dongHopThoai(hop); return; }
    const bo = e.target.closest('[data-bo-anh]');
    if (bo) { anh.splice(Number(bo.dataset.boAnh), 1); veAnh(); }
  });
  form.addEventListener('change', (e) => { if (e.target.name === 'loai') { VN.$('[data-loi-pa-loai]', hop).textContent = ''; luuY(); } });
  form.moTa.addEventListener('input', () => { VN.$('[data-pa-dem]', hop).textContent = `${form.moTa.value.length}/500`; if (form.moTa.value.trim().length >= 10) VN.baoLoiTruong(form.moTa, ''); });

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const loai = VN.$('input[name="loai"]:checked', form);
    const ok = [];
    VN.$('[data-loi-pa-loai]', hop).textContent = loai ? '' : 'Vui lòng chọn vấn đề bạn gặp.'; ok.push(!!loai);
    const moTaDu = form.moTa.value.trim().length >= 10;
    VN.baoLoiTruong(form.moTa, moTaDu ? '' : 'Vui lòng mô tả rõ hơn (ít nhất 10 ký tự).'); ok.push(moTaDu);
    const sdtDung = VN.sdtHopLe(form.sdt.value);
    VN.baoLoiTruong(form.sdt, sdtDung ? '' : 'Số điện thoại gồm 10 số, bắt đầu bằng 03, 05, 07, 08 hoặc 09.'); ok.push(sdtDung);
    if (!ok.every(Boolean)) { const dau = loai ? VN.$('.co-loi textarea, .co-loi input', form) : VN.$('input[name="loai"]', form); if (dau) dau.focus(); return; }
    const l = ch.hoTro.loaiVanDe.find((x) => x.ma === loai.value);
    const sanPham = don.sanPham.length === 1 ? [don.sanPham[0].ma] : VN.$$('input[name="sanPham"]:checked', form).map((x) => x.value);
    try {
      ketQua = VN.hoTro.tao({ donHang: don.ma, loai: l.ma, tenLoai: l.ten, sanPham, moTa: form.moTa.value.trim(), anh, lienHe: { cach: form.cach.value, sdt: VN.chuanSdt(form.sdt.value) } });
    } catch (loi) {
      VN.thongBao({ tieuDe: 'Chưa gửi được phản ánh', noiDung: /quota/i.test(loi.message) ? 'Ảnh quá lớn, vui lòng bớt ảnh rồi gửi lại.' : VN.thoat(loi.message), loai: 'loi' });
      return;
    }
    VN.dongHopThoai(hop);
    VN.thongBao({ tieuDe: `Đã gửi phản ánh ${ketQua.ma}`, noiDung: `Vinora sẽ liên hệ bạn qua ${VN.thoat(form.cach.value.toLowerCase())} trong ${ch.hoTro.phanHoiTrongGio} giờ.`, loai: 'thanh-cong', thoiGian: 6000 });
  });
  hop.addEventListener('close', () => { if (xong) { const f = xong; xong = null; f(ketQua); } });

  VN.moPhanAnh = async (maDon, { loai = '' } = {}) => {
    ch = ch || await VN.duLieu.cauHinh();
    don = VN.donHang.lay(maDon);
    if (!don) return null;
    ketQua = null; anh = [];
    form.reset();
    VN.$$('.truong.co-loi', form).forEach((t) => t.classList.remove('co-loi'));
    VN.$$('.loi-truong', form).forEach((p) => { p.textContent = ''; });
    VN.$('[data-pa-ma]', hop).textContent = don.ma;
    VN.$('[data-pa-cam-ket]', hop).textContent = `Chuyên viên chăm sóc khách hàng sẽ liên hệ bạn trong ${ch.hoTro.phanHoiTrongGio} giờ. Lỗi do sản xuất hoặc giao sai được đổi mới / sửa miễn phí.`;
    VN.$('[data-pa-loai]', hop).innerHTML = ch.hoTro.loaiVanDe.filter(loaiHopLe).map((l) => `<label class="the-chon"><input type="radio" name="loai" value="${l.ma}"${l.ma === loai ? ' checked' : ''}>
      <span class="the-chon__noi-dung"><span class="the-chon__ten">${VN.thoat(l.ten)}</span></span></label>`).join('');
    VN.$('[data-pa-sp-khung]', hop).hidden = don.sanPham.length < 2;
    VN.$('[data-pa-sp]', hop).innerHTML = don.sanPham.map((d) => `<label class="pa-sp__muc"><input type="checkbox" name="sanPham" value="${VN.thoat(d.ma)}">
      <img src="${VN.anh(d.anh)}" alt="" width="44" height="44"><span>${VN.thoat(d.ten)}<small>${VN.thoat(d.ma)}${d.size ? ' · Size ' + d.size : ''}</small></span></label>`).join('');
    const u = VN.taiKhoan.hienTai();
    form.sdt.value = (u && u.sdt) || don.sdtKhach || don.nguoiNhan.sdt || '';
    if (loai === 'dieu-chinh') form.moTa.placeholder = 'Ví dụ: Đổi size nhẫn từ 12 sang 13 và giao vào thứ bảy.';
    else form.moTa.placeholder = 'Ví dụ: Bông tai bên trái bị lỏng chốt, viên đá nhỏ bị lệch so với ảnh.';
    VN.$('[data-pa-dem]', hop).textContent = '0/500';
    veAnh(); luuY();
    return new Promise((r) => { xong = r; VN.moHopThoai(hop); });
  };
})();
