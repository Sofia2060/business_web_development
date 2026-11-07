/* =====================================================================
   5.2.5 GIỎ HÀNG (FR9, FR10)
   - Mỗi dòng phân biệt theo mã + màu + size + chữ khắc; đổi size / màu / chữ khắc ngay trong giỏ
   - Ô tick từng dòng + "Chọn tất cả": chỉ dòng được tick mới tính tiền và đi tới thanh toán,
     dòng bỏ tick vẫn nằm trong giỏ (không phải xóa sản phẩm khỏi giỏ khi chỉ muốn mua một phần)
   - Tăng giảm số lượng (tối đa theo cấu hình), xóa có hoàn tác
   - Kiểm tra lại giá & khả năng bán trước khi thanh toán (FR10)
   - Mã ưu đãi (máy chủ kiểm tra và tính tiền giảm), tiến độ miễn phí giao hàng, gói quà & thiệp – tính tiền bằng VN.tinhTien (NFR5)
   - Khách có tài khoản: giỏ nằm trong database; khách chưa đăng nhập: giỏ nằm trên trình duyệt này
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const trang = VN.$('#trang-gio');
  if (!trang) return;

  const KY_TU_KHAC = /^[\p{L}\p{M}\p{N} &.,\-♥∞+'’]*$/u;
  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  const tt = { ch: null, sp: null, dong: [], tc: VN.tuyChonGio.doc(), uuDai: null, loiMa: '', daKiemTra: '' };
  const dsDong = VN.$('#ds-dong-gio');

  Promise.all([VN.duLieu.coBan(), VN.sanSang]).then(([{ sp, ch }]) => {
    tt.sp = sp; tt.ch = ch;
    veMaUuDai();
    khoiTaoGoiQua();
    ve();
    window.addEventListener('vinora:gio', () => ve());
    window.addEventListener('vinora:tai-khoan', () => ve());
  }).catch((loi) => {
    console.error(loi);
    VN.thongBao({ tieuDe: 'Chưa tải được dữ liệu sản phẩm', noiDung: 'Vui lòng kiểm tra kết nối mạng rồi tải lại trang.', loai: 'loi' });
  });

  /* ================= HIỂN THỊ ================= */
  /** Các dòng đang được tick (được tính tiền) */
  const dongChon = () => tt.dong.filter((d) => VN.gioHang.daChon(d.khoa));
  /** Mã ưu đãi đang dùng: hỏi máy chủ khi mã hoặc tiền hàng đổi (máy chủ tính số tiền giảm và cho biết lý do nếu mã không dùng được) */
  const kiemTraMaDangDung = async () => {
    const ma = tt.tc.maUuDai;
    const chon = dongChon();
    const tamTinh = chon.reduce((t, d) => t + d.donGia * d.soLuong, 0);
    if (!ma || !chon.length) { tt.uuDai = null; tt.loiMa = ''; tt.daKiemTra = ''; return; }
    const dau = `${ma}|${tamTinh}`;
    if (dau === tt.daKiemTra) return;
    tt.daKiemTra = dau;
    try { tt.uuDai = await VN.uuDai.kiemTra(ma); tt.loiMa = ''; } catch (loi) { tt.uuDai = null; tt.loiMa = loi.message; }
  };

  let dangVe = false; let veLai = false;
  const ve = async () => {
    if (dangVe) { veLai = true; return; }     // đang vẽ: vẽ lại một lần nữa khi xong, để không mất thay đổi mới
    dangVe = true;
    try {
      // Ghi nhớ phần tử đang được focus để trả lại sau khi vẽ lại
      const dangFocus = document.activeElement && document.activeElement.closest('.dong-gio')
        ? { khoa: document.activeElement.closest('.dong-gio').dataset.khoa, vaiTro: document.activeElement.dataset.vaiTro } : null;

      const goc = VN.gioHang.ds();
      tt.dong = await VN.gioHang.chiTiet();
      // FR10: gỡ các dòng không còn bán trực tuyến
      if (tt.dong.length < goc.length) {
        const conLai = new Set(tt.dong.map((d) => d.khoa));
        const bo = goc.filter((d) => !conLai.has(VN.gioHang.khoa(d)));
        VN.gioHang.goBo(bo.map((d) => VN.gioHang.khoa(d))).catch(() => {});
        const hop = VN.$('#gh-thong-bao');
        hop.hidden = false;
        hop.innerHTML = `${VN.bt('canh-bao')}<span>${bo.length} sản phẩm (${bo.map((d) => VN.thoat(d.ma)).join(', ')}) không còn bán trực tuyến hoặc đổi sang giá theo ngày nên đã được gỡ khỏi giỏ.</span>`;
      }
      VN.gioHang.donBoChon();
      // Màu, size còn lại và khả năng khắc chữ của từng sản phẩm nằm ở trang chi tiết của máy chủ
      await Promise.all(tt.dong.map((d) => VN.duLieu.chiTietSanPham(d.ma).then((ct) => { d.ct = ct; }).catch(() => {})));
      await kiemTraMaDangDung();
      const co = tt.dong.length > 0;
      trang.hidden = !co;
      VN.$('#gio-trong').hidden = co;
      const tong = tt.dong.reduce((t, d) => t + d.soLuong, 0);
      VN.$('#gh-dem').textContent = co ? `(${tong})` : '';
      trang.removeAttribute('aria-busy');

      dsDong.innerHTML = tt.dong.map(htmlDong).join('');
      veTien();
      veGoiY();
      if (dangFocus) {
        const el = VN.$(`.dong-gio[data-khoa="${CSS.escape(dangFocus.khoa)}"] [data-vai-tro="${dangFocus.vaiTro}"]`);
        if (el && !el.disabled) el.focus();
      }
    } finally {
      dangVe = false;
      if (veLai) { veLai = false; ve(); }
    }
  };

  const htmlDong = (d) => {
    const s = d.sp; const ch = tt.ch;
    const laNhan = s.canChonSize;
    const ct = d.ct;
    const coKhac = !!(ct && ct.khacDuoc);
    const k = VN.thoat(d.khoa);
    const chon = VN.gioHang.daChon(d.khoa);
    let tuyChon = '';
    if (s.mau.length > 1) {
      tuyChon += `<label class="dong-gio__chon"><span>Màu</span><select class="o-chon" data-doi-mau data-vai-tro="mau" aria-label="Đổi màu vàng cho ${VN.thoat(s.ten)}">
        ${s.mau.map((m) => `<option${m === d.mau ? ' selected' : ''}>${VN.thoat(m)}</option>`).join('')}</select></label>`;
    }
    if (laNhan) {
      // Chỉ các size có trong kho cho màu của dòng này (size đang chọn luôn có trong danh sách)
      const dsSize = ct ? ct.bienThe.filter((v) => v.size && (!d.mau || v.mau === d.mau)).map((v) => v.size) : [];
      if (d.size && !dsSize.includes(Number(d.size))) dsSize.push(Number(d.size));
      const opt = dsSize.sort((a, b) => a - b).map((n) => `<option value="${n}"${Number(d.size) === n ? ' selected' : ''}>${n}</option>`).join('');
      tuyChon += `<label class="dong-gio__chon"><span>Size</span><select class="o-chon" data-doi-size data-vai-tro="size" aria-label="Đổi size nhẫn cho ${VN.thoat(s.ten)}">${opt}</select></label>`;
    }
    let khac = '';
    if (d.khacChu) {
      khac = `<div class="dong-gio__khac"><span class="dong-gio__khac-chu kieu-${VN.thoat(d.kieuChu || 'co-dien')}">“${VN.thoat(d.khacChu)}”</span>
        <span class="chu-rat-nho chu-phu">Khắc laser · ${TEN_KIEU[d.kieuChu] || 'Cổ điển'}</span>
        <button type="button" class="nut nut--chu" data-sua-khac data-vai-tro="sua-khac">Sửa</button>
        <button type="button" class="nut nut--chu" data-bo-khac data-vai-tro="bo-khac">Bỏ khắc</button></div>`;
    } else if (coKhac) {
      khac = `<button type="button" class="nut nut--chu dong-gio__them-khac" data-sua-khac data-vai-tro="sua-khac">${VN.bt('but', 'bt--nho')} Thêm chữ khắc miễn phí</button>`;
    }
    return `
      <li class="dong-gio${chon ? '' : ' bo-chon'}" data-khoa="${k}" role="row">
        <label class="lua-chon dong-gio__chon-dong" role="cell"><input type="checkbox" data-chon-dong data-vai-tro="chon"${chon ? ' checked' : ''} aria-label="Chọn ${VN.thoat(s.ten)} để thanh toán"></label>
        <a class="dong-gio__anh" href="${VN.urlSanPham(s.ma)}" tabindex="-1" aria-hidden="true"><img src="${VN.anh(s.anh[0])}" alt="" width="160" height="160" loading="lazy"${VN.laAnhChup(s.anh[0]) ? ' class="la-anh-chup"' : ''}></a>
        <div class="dong-gio__thong-tin" role="cell">
          ${s.bst && s.bst.ten ? `<p class="nhan-tren">${VN.thoat(s.bst.ten)}</p>` : ''}
          <h3 class="dong-gio__ten"><a href="${VN.urlSanPham(s.ma)}">${VN.thoat(s.ten)}</a></h3>
          <p class="dong-gio__phu">${VN.thoat(s.ma)} · ${VN.thoat(s.tenChatLieu)}${d.mau && s.mau.length <= 1 ? ' · ' + VN.thoat(d.mau) : ''}</p>
          <div class="dong-gio__don-gia"><span class="an-chu">Đơn giá</span>${VN.giaHtml(s)}</div>
          ${tuyChon ? `<div class="dong-gio__tuy-chon">${tuyChon}</div>` : ''}
          ${khac}
          ${d.tonKho !== undefined && d.soLuong > d.tonKho ? `<p class="loi-truong" role="alert">${d.tonKho > 0 ? `Chỉ còn ${d.tonKho} sản phẩm, vui lòng giảm số lượng.` : 'Lựa chọn này tạm hết hàng.'}</p>` : ''}
        </div>
        <div class="dong-gio__sl" role="cell">
          <span class="nhan-o">Số lượng</span>
          <div class="bo-dem bo-dem--nho" role="group" aria-label="Số lượng ${VN.thoat(s.ten)}">
            <button type="button" data-sl="-1" data-vai-tro="giam" aria-label="Giảm số lượng"${d.soLuong <= 1 ? ' disabled' : ''}>${VN.bt('tru', 'bt--nho')}</button>
            <input type="number" min="1" max="${tt.ch.soLuongToiDaMoiDong}" value="${d.soLuong}" data-o-sl data-vai-tro="o-sl" inputmode="numeric" aria-label="Số lượng">
            <button type="button" data-sl="1" data-vai-tro="tang" aria-label="Tăng số lượng"${d.soLuong >= tt.ch.soLuongToiDaMoiDong ? ' disabled' : ''}>${VN.bt('cong', 'bt--nho')}</button>
          </div>
        </div>
        <div class="dong-gio__tong so-deu" role="cell"><span class="nhan-o">Thành tiền</span>${VN.tien(d.thanhTien)}</div>
        <button type="button" class="nut-bt dong-gio__xoa" data-xoa data-vai-tro="xoa" aria-label="Xóa ${VN.thoat(s.ten)} khỏi giỏ hàng" title="Xóa khỏi giỏ">${VN.bt('thung-rac', 'bt--nho')}</button>
      </li>`;
  };

  /* Tóm tắt tiền – dùng chung công thức VN.tinhTien; số tiền giảm của mã do máy chủ tính */
  const veTien = () => {
    const ch = tt.ch; const chon = dongChon();
    const t = VN.tinhTien(chon, ch, { giam: tt.uuDai ? tt.uuDai.discount : 0 });
    const sl = chon.reduce((a, d) => a + d.soLuong, 0);
    veChon(chon);
    VN.$('#gh-tien').innerHTML = `
      <div><dt>Tạm tính <span>(${sl} sản phẩm đã chọn)</span></dt><dd class="so-deu">${VN.tien(t.tamTinh)}</dd></div>
      ${tt.uuDai && t.giam ? `<div class="dong-tien__giam"><dt>Ưu đãi <span class="nhan nhan--vang nhan--tron">${VN.thoat(tt.uuDai.code)}</span></dt><dd class="so-deu">−${VN.tien(t.giam)}</dd></div>` : ''}
      <div><dt>Phí giao hàng <span>(tiêu chuẩn, ước tính)</span></dt><dd class="so-deu">${!chon.length ? '—' : t.phiGiao ? VN.tien(t.phiGiao) : '<span class="chu-ngoc">Miễn phí</span>'}</dd></div>
      <div class="dong-tien__tong"><dt>Tổng cộng</dt><dd class="so-deu">${VN.tien(chon.length ? t.tong : 0)}</dd></div>`;
    // Mã ưu đãi đang áp dụng
    const loi = VN.$('#loi-ma');
    if (tt.tc.maUuDai && tt.loiMa) { loi.innerHTML = `${VN.bt('canh-bao', 'bt--nho')}<span>${VN.thoat(tt.loiMa)}</span>`; }
    else if (tt.uuDai) { loi.innerHTML = `<span class="chu-ngoc">${VN.bt('dau-tich', 'bt--nho')} Đã áp dụng ${VN.thoat(tt.uuDai.code)}: ${VN.thoat(tt.uuDai.name)}. <button type="button" class="lien-ket" data-bo-ma>Bỏ mã</button></span>`; }
    else loi.innerHTML = '';
    VN.$('#o-ma').closest('.truong').classList.toggle('co-loi', !!(tt.tc.maUuDai && tt.loiMa));
    VN.$$('#ds-ma [data-ma]').forEach((b) => {
      const u = ch.maUuDai.find((x) => x.ma === b.dataset.ma);
      const du = chon.length > 0 && t.tamTinh >= (u.donToiThieu || 0);
      b.classList.toggle('chua-du', !du);
      b.setAttribute('aria-pressed', String(tt.tc.maUuDai === u.ma));
      VN.$('small', b).textContent = du ? u.moTa : !chon.length ? 'Chọn sản phẩm để dùng mã' : `Mua thêm ${VN.tien(u.donToiThieu - t.tamTinh)} để dùng mã`;
    });
    // Tiến độ miễn phí giao hàng
    const pt = Math.min(100, Math.round(t.tamTinh * 100 / ch.giaoHang.mienPhiTu));
    VN.$('#gh-mien-phi').innerHTML = t.duMienPhi
      ? `<p>${VN.bt('xe-giao')}<span>Đơn hàng được <strong>miễn phí giao hàng có bảo hiểm</strong> toàn quốc.</span></p><div class="thanh-tien-do thanh-tien-do--ngoc"><span style="width:100%"></span></div>`
      : `<p>${VN.bt('xe-giao')}<span>Mua thêm <strong>${VN.tien(t.conThieu)}</strong> để được miễn phí giao hàng có bảo hiểm.</span></p><div class="thanh-tien-do"><span style="width:${pt}%"></span></div>`;
    // Không bắt buộc đăng nhập: khách chưa có tài khoản đặt hàng bằng số điện thoại
    VN.$('#gh-ghi-chu-dn').hidden = !!VN.taiKhoan.hienTai();
  };

  /* ================= CHỌN DÒNG ĐỂ THANH TOÁN ================= */
  /** Ô "Chọn tất cả" (đầu bảng và thanh trên điện thoại), số dòng đã chọn, nút thanh toán */
  const veChon = (chon = dongChon()) => {
    const tatCa = chon.length === tt.dong.length && tt.dong.length > 0; const motPhan = chon.length > 0 && !tatCa;
    ['#gh-chon-het', '#gh-chon-het-nho'].forEach((id) => { const o = VN.$(id); o.checked = tatCa; o.indeterminate = motPhan; });
    VN.$('[data-dem-chon]').textContent = `(${chon.length}/${tt.dong.length})`;
    const nut = VN.$('#nut-thanh-toan');
    nut.setAttribute('aria-disabled', String(!chon.length));
    nut.firstChild.textContent = chon.length && chon.length < tt.dong.length ? `Thanh toán ${chon.length} sản phẩm đã chọn ` : 'Tiến hành thanh toán ';
    if (chon.length) VN.$('#gh-loi-chon').textContent = '';
  };
  /** Đổi tick: vẽ lại tiền ngay, rồi hỏi máy chủ số tiền giảm của mã (tiền hàng đã đổi) */
  const sauKhiDoiChon = async () => {
    VN.$$('.dong-gio', dsDong).forEach((li) => {
      const c = VN.gioHang.daChon(li.dataset.khoa);
      li.classList.toggle('bo-chon', !c); VN.$('[data-chon-dong]', li).checked = c;
    });
    veTien();
    await kiemTraMaDangDung();
    veTien();
  };
  dsDong.addEventListener('change', (e) => {
    if (!e.target.matches('[data-chon-dong]')) return;
    VN.gioHang.datChon(khoaCua(e.target), e.target.checked);
    sauKhiDoiChon();
  });
  ['#gh-chon-het', '#gh-chon-het-nho'].forEach((id) => VN.$(id).addEventListener('change', (e) => {
    VN.gioHang.chonTatCa(e.target.checked);
    sauKhiDoiChon();
  }));
  VN.$('#nut-thanh-toan').addEventListener('click', (e) => {
    if (dongChon().length) return;
    e.preventDefault();
    VN.$('#gh-loi-chon').innerHTML = `${VN.bt('canh-bao', 'bt--nho')}<span>Vui lòng chọn ít nhất một sản phẩm để thanh toán.</span>`;
  });

  /* ================= THAO TÁC TRÊN DÒNG ================= */
  const khoaCua = (el) => el.closest('.dong-gio').dataset.khoa;
  const dongTheoKhoa = (k) => tt.dong.find((d) => d.khoa === k);
  /** Thực hiện một thao tác trên giỏ; lỗi (hết hàng, mất mạng…) được báo rồi giỏ được tải lại cho khớp với máy chủ */
  const thucHien = async (viec) => {
    try { await viec(); } catch (loi) {
      VN.thongBao({ tieuDe: 'Chưa cập nhật được giỏ hàng', noiDung: VN.thoat(loi.message), loai: 'loi' });
      VN.gioHang.nap().catch(() => {});
    }
  };
  dsDong.addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    const k = khoaCua(b); const d = dongTheoKhoa(k); if (!d) return;
    if (b.dataset.sl) {
      thucHien(() => VN.gioHang.datSoLuong(k, Math.max(1, Math.min(tt.ch.soLuongToiDaMoiDong, d.soLuong + Number(b.dataset.sl)))));
    } else if (b.hasAttribute('data-xoa')) {
      b.closest('.dong-gio').classList.add('dang-xoa');
      setTimeout(() => thucHien(async () => {
        const da = await VN.gioHang.xoa(k);
        if (da) VN.thongBao({ tieuDe: 'Đã xóa khỏi giỏ hàng', noiDung: VN.thoat(d.sp.ten), hanhDong: { chu: 'Hoàn tác', khiBam: () => thucHien(() => VN.gioHang.khoiPhuc(da)) } });
      }), 200);
    } else if (b.hasAttribute('data-sua-khac')) moHopKhac(d);
    else if (b.hasAttribute('data-bo-khac')) {
      thucHien(async () => {
        await VN.gioHang.capNhatDong(k, { khacChu: '', kieuChu: '' }, tt.ch.soLuongToiDaMoiDong);
        VN.thongBao({ tieuDe: 'Đã bỏ chữ khắc', noiDung: VN.thoat(d.sp.ten) });
      });
    }
  });
  dsDong.addEventListener('change', (e) => {
    const el = e.target; if (el.matches('[data-chon-dong]')) return;
    const k = khoaCua(el); const d = dongTheoKhoa(k); if (!d) return;
    if (el.matches('[data-o-sl]')) {
      const n = Math.max(1, Math.min(tt.ch.soLuongToiDaMoiDong, Math.round(Number(el.value) || 1)));
      if (Number(el.value) > tt.ch.soLuongToiDaMoiDong) VN.thongBao({ tieuDe: `Tối đa ${tt.ch.soLuongToiDaMoiDong} sản phẩm cho mỗi lựa chọn`, noiDung: 'Liên hệ hotline nếu bạn cần đặt số lượng lớn.' });
      thucHien(() => VN.gioHang.datSoLuong(k, n));
    } else if (el.matches('[data-doi-size]')) {
      thucHien(async () => {
        await VN.gioHang.capNhatDong(k, { size: Number(el.value) }, tt.ch.soLuongToiDaMoiDong);
        VN.thongBao({ tieuDe: `Đã đổi sang size ${el.value}`, loai: 'thanh-cong', thoiGian: 2200 });
      });
    } else if (el.matches('[data-doi-mau]')) {
      thucHien(() => VN.gioHang.capNhatDong(k, { mau: el.value }, tt.ch.soLuongToiDaMoiDong));
    }
  });

  /* ================= SỬA CHỮ KHẮC (xem trước trực tiếp) ================= */
  const hopKhac = VN.$('#hop-khac'); const formKhac = VN.$('#form-khac'); const oChu = VN.$('#hk-chu');
  let dongDangSua = null;
  const veXemKhac = () => {
    const chu = oChu.value.normalize('NFC').replace(/\s+/g, ' ').trim();
    VN.$('#hk-dem').textContent = `${Array.from(oChu.value).length}/${tt.ch.khacChu.toiDaKyTu}`;
    VN.veKhacChu(VN.$('#xem-khac'), chu, formKhac.kieu.value, dongDangSua.mau || dongDangSua.sp.mau[0] || 'Vàng Vàng');
  };
  const moHopKhac = (d) => {
    dongDangSua = d;
    oChu.value = d.khacChu || '';
    oChu.maxLength = tt.ch.khacChu.toiDaKyTu;
    formKhac.kieu.value = d.kieuChu || 'co-dien';
    VN.baoLoiTruong(oChu, '');
    veXemKhac();
    VN.moHopThoai(hopKhac);
    oChu.focus();
  };
  formKhac.addEventListener('input', veXemKhac);
  formKhac.addEventListener('change', veXemKhac);
  hopKhac.addEventListener('click', (e) => { if (e.target.closest('[data-dong]')) VN.dongHopThoai(hopKhac); });
  formKhac.addEventListener('submit', (e) => {
    e.preventDefault();
    const chu = oChu.value.normalize('NFC').replace(/\s+/g, ' ').trim();
    if (!chu) { VN.baoLoiTruong(oChu, 'Vui lòng nhập nội dung khắc (hoặc chọn “Bỏ khắc” trong giỏ hàng).'); return; }
    if (!KY_TU_KHAC.test(chu)) { VN.baoLoiTruong(oChu, 'Có ký tự không khắc được. Chỉ dùng chữ, số, khoảng trắng và & . , - ♥ ∞'); return; }
    VN.dongHopThoai(hopKhac);
    thucHien(async () => {
      await VN.gioHang.capNhatDong(dongDangSua.khoa, { khacChu: chu, kieuChu: formKhac.kieu.value }, tt.ch.soLuongToiDaMoiDong);
      VN.thongBao({ tieuDe: 'Đã lưu chữ khắc', noiDung: `“${VN.thoat(chu)}” · ${TEN_KIEU[formKhac.kieu.value]}`, loai: 'thanh-cong' });
    });
  });

  /* ================= MÃ ƯU ĐÃI ================= */
  const veMaUuDai = () => {
    VN.$('#ds-ma').innerHTML = '<p class="chu-rat-nho chu-phu">Mã dành cho bạn</p>' + tt.ch.maUuDai.map((u) => `
      <button type="button" class="the-ma" data-ma="${VN.thoat(u.ma)}" aria-pressed="false">
        <strong>${VN.thoat(u.ma)}</strong><small>${VN.thoat(u.moTa)}</small></button>`).join('');
    if (tt.tc.maUuDai) VN.$('#o-ma').value = tt.tc.maUuDai;
  };
  const apDungMa = async (ma) => {
    ma = String(ma || '').trim().toUpperCase();
    VN.$('#o-ma').value = ma;
    if (!ma) { VN.baoLoiTruong(VN.$('#o-ma'), 'Vui lòng nhập mã ưu đãi.'); return; }
    if (!dongChon().length) { VN.baoLoiTruong(VN.$('#o-ma'), 'Chọn ít nhất một sản phẩm trước khi áp dụng mã.'); return; }
    try {
      const kq = await VN.uuDai.kiemTra(ma);           // máy chủ kiểm tra mã và tính số tiền giảm
      tt.tc = VN.tuyChonGio.ghi({ maUuDai: kq.code });
      tt.uuDai = kq; tt.loiMa = ''; tt.daKiemTra = `${kq.code}|${kq.subtotal}`;
      veTien();
      VN.thongBao({ tieuDe: `Đã áp dụng mã ${kq.code}`, noiDung: `Bạn được giảm ${VN.tien(kq.discount)}.`, loai: 'thanh-cong' });
    } catch (loi) {
      VN.$('#loi-ma').innerHTML = `${VN.bt('canh-bao', 'bt--nho')}<span>${VN.thoat(loi.message)}</span>`;
      VN.$('#o-ma').closest('.truong').classList.add('co-loi');
    }
  };
  VN.$('#form-ma').addEventListener('submit', (e) => { e.preventDefault(); apDungMa(VN.$('#o-ma').value); });
  VN.$('#form-ma').addEventListener('click', (e) => {
    const the = e.target.closest('[data-ma]'); if (the) { apDungMa(the.dataset.ma); return; }
    if (e.target.closest('[data-bo-ma]')) { tt.tc = VN.tuyChonGio.ghi({ maUuDai: '' }); tt.uuDai = null; tt.loiMa = ''; tt.daKiemTra = ''; VN.$('#o-ma').value = ''; veTien(); }
  });
  VN.$('#o-ma').addEventListener('input', () => { VN.$('#o-ma').closest('.truong').classList.remove('co-loi'); });

  /* ================= GÓI QUÀ & THIỆP ================= */
  const khoiTaoGoiQua = () => {
    const goi = VN.$('#gh-goi-qua'); const loiNhan = VN.$('#gh-loi-nhan');
    goi.checked = !!tt.tc.goiQua; loiNhan.value = tt.tc.loiNhan || '';
    const dem = () => { VN.$('#gh-dem-loi-nhan').textContent = `${loiNhan.value.length}/150`; };
    dem();
    goi.addEventListener('change', () => { tt.tc = VN.tuyChonGio.ghi({ goiQua: goi.checked }); });
    loiNhan.addEventListener('input', VN.chongDoi(() => { tt.tc = VN.tuyChonGio.ghi({ loiNhan: loiNhan.value.trim() }); }, 250));
    loiNhan.addEventListener('input', dem);
  };

  /* ================= GỢI Ý MUA KÈM ================= */
  let capNhatNut = null;
  const veGoiY = () => {
    const trongGio = new Set(tt.dong.map((d) => d.ma));
    const nguon = tt.sp.ds.filter((s) => s.coTheMua && !trongGio.has(s.ma));
    let ds;
    if (tt.dong.length) {
      // Ưu tiên cùng bộ sưu tập nhưng khác loại trang sức để "hoàn thiện bộ"
      const bst = new Set(tt.dong.map((d) => d.sp.boSuuTap)); const dm = new Set(tt.dong.map((d) => d.sp.danhMuc));
      ds = nguon.map((s) => [(bst.has(s.boSuuTap) ? 3 : 0) + (dm.has(s.danhMuc) ? 0 : 2) + (VN.laHangMoi(s) ? 0.5 : 0), s])
        .sort((a, b) => b[0] - a[0] || a[1].giaBan - b[1].giaBan).slice(0, 12).map((x) => x[1]);
      VN.$('#goi-y-gio-nhan').textContent = 'Hoàn thiện bộ trang sức';
      VN.$('#td-goi-y-gio').textContent = 'Thường được chọn cùng';
    } else {
      ds = nguon.sort((a, b) => (b.ngayTao || '').localeCompare(a.ngayTao || '')).slice(0, 12);
      VN.$('#goi-y-gio-nhan').textContent = 'Gợi ý cho bạn';
      VN.$('#td-goi-y-gio').textContent = 'Thiết kế mới nhất';
    }
    const phan = VN.$('#phan-goi-y-gio'); const dai = VN.$('#dai-goi-y-gio');
    phan.hidden = !ds.length;
    VN.veLuoi(dai, ds);
    if (!capNhatNut) capNhatNut = VN.ganDieuKhienTruot(dai, VN.$('[data-dieu-khien="dai-goi-y-gio"]'));
    if (capNhatNut) setTimeout(capNhatNut, 60);
  };
})();
