/* =====================================================================
   5.2.3 CHI TIẾT SẢN PHẨM
   - Mã sản phẩm lấy từ Flask (data-ma-san-pham) hoặc tham số ?ma= (bản tĩnh)
   - Thư viện ảnh: ảnh nhỏ, phóng to theo con trỏ, xem ảnh lớn, vuốt trên điện thoại
   - Thông số chuẩn hóa: tuổi vàng, trọng lượng, đá (BRD1, FR6)
   - Chọn màu, chọn size bắt buộc với nhẫn (FR7), khắc chữ xem trước trên ảnh (Bảng 3.6)
   - Thêm vào giỏ / mua ngay (FR9); sản phẩm giá công -> nhận báo giá
   - Bảng hướng dẫn đo size + máy tính size, bảng cam kết chính sách bảo hành
   - Gợi ý cùng bộ sưu tập, ghi nhận & hiển thị sản phẩm đã xem (FR8)
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const goc = VN.$('#chi-tiet');
  if (!goc) return;

  const maYeuCau = (goc.dataset.maSanPham || VN.thamSo('ma') || '').trim();
  /* Ký tự khắc được bằng laser: chữ (kể cả tiếng Việt có dấu), số, khoảng trắng và vài ký hiệu */
  const KY_TU_KHAC = /^[\p{L}\p{M}\p{N} &.,\-♥∞+'’]*$/u;
  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  const so = VN.so;
  const kichThuocDa = VN.kichThuocDa;
  const demKyTu = (chu) => Array.from(chu).length;

  const tt = { sp: null, ch: null, bangSize: null, anh: [], viTri: 0, dangKhac: false, size: null, mau: '', soLuong: 1, toiDa: 5, toiDaKhac: 15 };
  const el = {
    noiDung: VN.$('#ct-noi-dung'), khung: VN.$('#tv-khung'), anh: VN.$('#tv-anh'),
    nho: VN.$('#tv-nho .thu-vien__nho-cuon'), cham: VN.$('#tv-cham'), dem: VN.$('#tv-dem'),
    khac: VN.$('#tv-khac'), chuyen: VN.$('#tv-chuyen'), phong: VN.$('#tv-phong'),
    form: VN.$('#form-mua'), oKhac: VN.$('#o-khac'), batKhac: VN.$('#bat-khac'), soLuong: VN.$('#so-luong'),
  };

  /* ================= 1. TẢI DỮ LIỆU (AJAX) ================= */
  Promise.all([VN.duLieu.coBan(), VN.duLieu.bangSize()]).then(([coBan, bangSize]) => {
    const { sp, ch } = coBan;
    const s = sp.theoMa[maYeuCau] || sp.ds.find((x) => x.ma.toLowerCase() === maYeuCau.toLowerCase());
    if (!s) { khongTimThay(sp.ds); return; }
    Object.assign(tt, { sp: s, ch, bangSize, toiDa: ch.soLuongToiDaMoiDong || 5, toiDaKhac: ch.khacChu.toiDaKyTu || 15 });

    VN.daXem.ghi(s.ma);
    veDauTrang(s);
    veGia(s, ch);
    veThongSo(s, ch);
    veYeuThichChungNhan(s, ch);
    veMoTa(s, ch);
    veThuVien(s);
    veLuaChon(s, ch);
    if (s.canChonSize) {
      VN.$('#phan-size').hidden = false;
      veBangSize(VN.$('#bang-size-ct'), 'ct', s.coTheMua);
    }
    veCamKet(s, ch);
    veGoiY(s, sp.ds);
    veDaXem(s, sp.theoMa);
    ganThanhMua(s);
    el.noiDung.removeAttribute('aria-busy');
  }).catch((loi) => {
    console.error(loi);
    VN.thongBao({ tieuDe: 'Chưa tải được dữ liệu sản phẩm', noiDung: 'Vui lòng kiểm tra kết nối mạng rồi tải lại trang.', loai: 'loi' });
  });

  /* Sản phẩm không tồn tại -> trạng thái rỗng + gợi ý sản phẩm mới */
  const khongTimThay = (ds) => {
    el.noiDung.hidden = true;
    VN.$('.chi-tiet__duong-dan').hidden = true;
    VN.$('#ct-khong-thay').hidden = false;
    VN.$('#phan-cam-ket').hidden = true;
    if (maYeuCau) VN.$('#ct-khong-thay-chu').innerHTML = `Không có sản phẩm nào mang mã <strong>${VN.thoat(maYeuCau)}</strong>. Sản phẩm có thể đã ngừng kinh doanh hoặc đường dẫn chưa chính xác.`;
    document.title = 'Không tìm thấy sản phẩm – Vinora Jewelry';
    const moi = ds.filter((x) => x.coTheMua).sort((a, b) => (b.ngayTao || '').localeCompare(a.ngayTao || '')).slice(0, 12);
    VN.$('#lien-quan-nhan').textContent = 'Gợi ý cho bạn';
    VN.$('#td-lien-quan').textContent = 'Thiết kế mới nhất';
    VN.$('#lien-quan-xem').href = VN.url('sanPham', { sapxep: 'moi' });
    hienDai(VN.$('#phan-lien-quan'), VN.$('#dai-lien-quan'), moi);
  };

  /* ================= 2. TIÊU ĐỀ, GIÁ, THÔNG SỐ, MÔ TẢ ================= */
  const veDauTrang = (s) => {
    document.title = `${s.ten} · ${s.ma} – Vinora Jewelry`;
    const meta = VN.$('meta[name="description"]');
    if (meta) meta.setAttribute('content', `${s.ten} (${s.ma}) – ${s.tenChatLieu}${s.coTheMua ? ', giá ' + VN.tien(s.giaBan) : ''}. Khắc tên laser, thẻ bảo hành điện tử trọn đời tại Vinora Jewelry.`);
    VN.$('#duong-dan-ct').innerHTML = [
      `<li><a href="${VN.url('trangChu')}">Trang chủ</a></li>`,
      `<li><a href="${VN.url('sanPham')}">Trang sức</a></li>`,
      s.dm.ten ? `<li><a href="${VN.url('sanPham', { danhmuc: s.danhMuc })}">${VN.thoat(s.dm.ten)}</a></li>` : '',
      `<li aria-current="page"><span class="duong-dan__cuoi" title="${VN.thoat(s.ten)}">${VN.thoat(s.ten)}</span></li>`,
    ].join('');
    const bst = VN.$('#ct-bst');
    if (s.bst && s.bst.ten) { bst.textContent = 'Bộ sưu tập ' + s.bst.ten; bst.href = VN.url('sanPham', { bst: s.boSuuTap }); }
    else { bst.textContent = s.dm.ten || 'Vinora Jewelry'; bst.href = VN.url('sanPham', { danhmuc: s.danhMuc }); }
    VN.$('#ct-ten').textContent = s.ten;
    VN.$('#ct-ma').textContent = s.ma;
    const tinhTrang = VN.$('#ct-tinh-trang');
    tinhTrang.hidden = false;
    if (!s.coTheMua) { tinhTrang.textContent = 'Báo giá theo ngày'; tinhTrang.className = 'nhan nhan--cam'; }
  };

  const veGia = (s, ch) => {
    const khung = VN.$('#ct-gia');
    if (s.coTheMua) {
      khung.innerHTML = VN.giaHtml(s, true)
        + (s.giaCu ? `<span class="nhan nhan--do">Tiết kiệm ${VN.tien(s.giaCu - s.giaBan)}${s.giam ? ` · −${s.giam}%` : ''}</span>` : '')
        + `<p class="thong-tin__gia-phu">${s.canChonSize ? `Giá áp dụng cho mọi size từ ${ch.sizeNhan.nhoNhat} đến ${ch.sizeNhan.lonNhat} · ` : ''}Miễn phí giao hàng cho đơn từ <strong>${VN.tien(ch.giaoHang.mienPhiTu)}</strong></p>`;
    } else {
      khung.innerHTML = `<p class="gia-cong-lon"><span>Giá vàng theo ngày</span><small>+ tiền công</small><strong>${VN.tien(s.gia)}</strong></p>
        <p class="thong-tin__gia-phu">Trang sức vàng ${VN.thoat(s.chatLieu)} được tính theo giá vàng niêm yết tại thời điểm mua và trọng lượng thực tế, cộng tiền công chế tác.</p>`;
    }
    VN.$$('[data-mien-phi]').forEach((x) => { x.textContent = VN.tien(ch.giaoHang.mienPhiTu); });
  };

  const loaiDa = VN.loaiDa;
  const moTaHamLuong = VN.hamLuong;

  const veThongSo = (s, ch) => {
    const muc = [['Chất liệu', VN.thoat(s.tenChatLieu), moTaHamLuong(s, ch)]];
    if (s.mau.length) muc.push(['Màu sắc', VN.thoat(s.mau.join(' · ')), s.mau.length > 1 ? `${s.mau.length} lựa chọn màu` : '']);
    if (s.trongLuong) muc.push(['Trọng lượng', `≈ ${so(s.trongLuong)} gram`, s.canChonSize ? 'Tham khảo, chênh lệch nhẹ theo size' : 'Trọng lượng tham khảo']);
    if (s.da) muc.push(['Thông tin đá', loaiDa(s.ten)[0], `${kichThuocDa(s.da.kichThuoc)} × ${s.da.soVien} viên`]);
    else if (VN.coDa(s)) muc.push(['Thông tin đá', loaiDa(s.ten)[0], 'Thông số viên đá đang được cập nhật']);
    muc.push(['Loại trang sức', `<a href="${VN.url('sanPham', { danhmuc: s.danhMuc })}">${VN.thoat(s.dm.ten)}</a>`, '']);
    if (s.bst && s.bst.ten) muc.push(['Bộ sưu tập', `<a href="${VN.url('sanPham', { bst: s.boSuuTap })}">${VN.thoat(s.bst.ten)}</a>`, `${s.bst.soLuong} thiết kế`]);
    VN.$('#ct-thong-so').innerHTML = muc.map(([dt, dd, phu]) => `<div class="thong-so__muc"><dt>${dt}</dt><dd>${dd}${phu ? `<small>${phu}</small>` : ''}</dd></div>`).join('');
  };

  /* Nút yêu thích (chung.js xử lý thêm / bỏ) và huy hiệu kiểm định mở giấy chứng nhận */
  const veYeuThichChungNhan = (s, ch) => {
    const tim = VN.$('#ct-yeu-thich');
    tim.dataset.yeuThich = s.ma; tim.dataset.ten = s.ten; tim.hidden = false;
    VN.capNhatNutTim(tim.parentElement);
    const huyHieu = VN.$('#ct-giay-cn');
    huyHieu.hidden = false;
    huyHieu.addEventListener('click', () => VN.moGiayChungNhan(s, ch, { mau: tt.mau || '' }));
  };

  const veMoTa = (s, ch) => {
    const doan = [];
    if (s.moTa) s.moTa.split(/\n+/).filter((p) => p.trim()).forEach((p) => doan.push(`<p>${VN.thoat(p.trim())}</p>`));
    // Đoạn tóm tắt dựng từ thông số chuẩn hóa – luôn khớp dữ liệu sản phẩm
    const hl = (ch.hamLuongVang || {})[s.chatLieu];
    let tom = `${VN.thoat(s.ten)}${s.bst && s.bst.ten ? ` thuộc bộ sưu tập <strong>${VN.thoat(s.bst.ten)}</strong>` : ''}, chế tác từ <strong>${VN.thoat(s.tenChatLieu)}</strong>`;
    if (hl) tom += s.chatLieu === 'BAC925' ? ` (${hl} nguyên chất)` : ` (hàm lượng vàng ${hl})`;
    if (s.da) tom += `, đính ${s.da.soVien} viên ${loaiDa(s.ten)[1]} kích thước ${kichThuocDa(s.da.kichThuoc)}`;
    if (s.trongLuong) tom += `; trọng lượng tham khảo ≈ ${so(s.trongLuong)} gram`;
    doan.push(`<p>${tom}.</p>`);
    doan.push(`<p>Sản phẩm đi kèm thẻ bảo hành điện tử trọn đời, tự kích hoạt khi bạn xác nhận đã nhận hàng${s.canChonSize ? '; nhẫn được chỉnh size và khắc tên miễn phí trọn đời tại showroom' : ''}.</p>`);
    VN.$('#ct-mo-ta').innerHTML = doan.join('');
  };

  /* ================= 3. THƯ VIỆN ẢNH ================= */
  let demDoi = 0;
  const cuonVaoKhung = (con, cha) => {
    if (!con || !cha) return;
    const a = con.getBoundingClientRect(); const b = cha.getBoundingClientRect();
    if (a.top < b.top) cha.scrollTop -= b.top - a.top; else if (a.bottom > b.bottom) cha.scrollTop += a.bottom - b.bottom;
    if (a.left < b.left) cha.scrollLeft -= b.left - a.left; else if (a.right > b.right) cha.scrollLeft += a.right - b.right;
  };
  const ganAnh = (img, duong) => {
    delete img.dataset.daThay;                 // cho phép xử lý ảnh lỗi lại khi đổi ảnh
    img.classList.toggle('la-anh-chup', VN.laAnhChup(duong));
    img.src = duong ? VN.anh(duong) : VN.anhTam();
  };

  const veThuVien = (s) => {
    tt.anh = s.anh.length ? s.anh.slice() : [''];
    const n = tt.anh.length;
    el.nho.innerHTML = `<button type="button" class="anh-nho anh-nho--khac" data-xem-khac aria-label="Xem trước chữ khắc" aria-current="false" hidden>${VN.bt('but')}<span>Khắc chữ</span></button>`
      + tt.anh.map((a, i) => `<button type="button" class="anh-nho" data-anh="${i}" aria-label="Ảnh ${i + 1} trên ${n}" aria-current="${i === 0}">
        <img src="${a ? VN.anh(a) : VN.anhTam()}" alt="" width="120" height="120" loading="${i < 7 ? 'eager' : 'lazy'}"${VN.laAnhChup(a) ? ' class="la-anh-chup"' : ''}></button>`).join('');
    el.cham.innerHTML = n > 1 ? tt.anh.map((_, i) => `<span${i === 0 ? ' class="dang-hien"' : ''}></span>`).join('') : '';
    el.khung.classList.remove('xuong');
    el.anh.hidden = false;
    chonAnh(0, true);
    // Ảnh nền cho lớp khắc chữ: ưu tiên ảnh nền trơn (png) của sản phẩm
    const nen = tt.anh.find((a) => a && !VN.laAnhChup(a)) || tt.anh[0];
    ganAnh(VN.$('.thu-vien__khac-anh', el.khac), nen);
  };

  const chonAnh = (i, ngay = false) => {
    const n = tt.anh.length;
    tt.viTri = (i + n) % n;
    if (tt.dangKhac) datCheDoKhac(false);
    const duong = tt.anh[tt.viTri];
    const ma = ++demDoi;
    const doi = () => { ganAnh(el.anh, duong); el.anh.alt = `${tt.sp.ten} – ảnh ${tt.viTri + 1}`; };
    if (ngay) doi();
    else {
      el.khung.classList.add('dang-doi');
      setTimeout(() => {
        if (ma !== demDoi) return;
        const xong = () => { if (ma === demDoi) el.khung.classList.remove('dang-doi'); };
        el.anh.addEventListener('load', xong, { once: true });
        el.anh.addEventListener('error', xong, { once: true });
        setTimeout(xong, 900);
        doi();
      }, 130);
    }
    VN.$$('[data-anh]', el.nho).forEach((b) => b.setAttribute('aria-current', String(Number(b.dataset.anh) === tt.viTri)));
    VN.$$('span', el.cham).forEach((c, k) => c.classList.toggle('dang-hien', k === tt.viTri));
    el.dem.textContent = n > 1 ? `${tt.viTri + 1} / ${n}` : '';
    if (!ngay) cuonVaoKhung(VN.$(`[data-anh="${tt.viTri}"]`, el.nho), el.nho);
    // Tải trước ảnh kế tiếp để chuyển ảnh mượt
    [tt.viTri + 1, tt.viTri - 1].forEach((k) => { const d = tt.anh[(k + n) % n]; if (d) { const im = new Image(); im.src = VN.anh(d); } });
  };

  el.nho.addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.hasAttribute('data-xem-khac')) { datCheDoKhac(true); return; }
    chonAnh(Number(b.dataset.anh));
  });
  el.nho.addEventListener('keydown', (e) => {
    if (!['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) return;
    const ds = VN.$$('button:not([hidden])', el.nho); const i = ds.indexOf(document.activeElement);
    if (i < 0) return;
    e.preventDefault();
    const k = ds[(i + (['ArrowDown', 'ArrowRight'].includes(e.key) ? 1 : -1) + ds.length) % ds.length];
    k.focus(); k.click();
  });

  /* Phóng to theo vị trí con trỏ (chỉ với chuột) */
  const coChuot = matchMedia('(hover: hover) and (pointer: fine)');
  el.khung.addEventListener('mousemove', (e) => {
    if (!coChuot.matches || tt.dangKhac || !tt.sp) return;
    const r = el.khung.getBoundingClientRect();
    el.anh.style.transformOrigin = `${((e.clientX - r.left) / r.width) * 100}% ${((e.clientY - r.top) / r.height) * 100}%`;
    el.khung.classList.add('dang-phong');
  });
  el.khung.addEventListener('mouseleave', () => el.khung.classList.remove('dang-phong'));
  el.khung.addEventListener('click', () => { if (!tt.dangKhac && tt.sp) moAnhLon(); });
  el.phong.addEventListener('click', () => { if (tt.sp) moAnhLon(); });

  /* Vuốt ngang để chuyển ảnh trên màn hình cảm ứng */
  const ganVuot = (vung, khiVuot) => {
    let x0 = null; let y0 = null;
    vung.addEventListener('touchstart', (e) => { x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; }, { passive: true });
    vung.addEventListener('touchend', (e) => {
      if (x0 === null) return;
      const dx = e.changedTouches[0].clientX - x0; const dy = e.changedTouches[0].clientY - y0; x0 = null;
      if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) * 1.3) khiVuot(dx < 0 ? 1 : -1);
    }, { passive: true });
  };
  ganVuot(el.khung, (huong) => { if (!tt.dangKhac && tt.anh.length > 1) chonAnh(tt.viTri + huong); });

  /* Hộp thoại xem ảnh lớn */
  const hopAnh = VN.$('#hop-anh'); const imgLon = VN.$('#hop-anh-img');
  let viTriLon = 0;
  const veAnhLon = () => {
    const duong = tt.anh[viTriLon];
    ganAnh(imgLon, duong);
    imgLon.alt = `${tt.sp.ten} – ảnh ${viTriLon + 1} trên ${tt.anh.length}`;
    VN.$('#hop-anh-dem').textContent = `${viTriLon + 1} / ${tt.anh.length}`;
    VN.$$('[data-anh]', hopAnh).forEach((b) => { b.hidden = tt.anh.length < 2; });
  };
  const doiAnhLon = (huong) => { viTriLon = (viTriLon + huong + tt.anh.length) % tt.anh.length; veAnhLon(); };
  const moAnhLon = () => { viTriLon = tt.viTri; veAnhLon(); VN.moHopThoai(hopAnh); };
  hopAnh.addEventListener('click', (e) => {
    const b = e.target.closest('[data-anh]');
    if (b) { doiAnhLon(Number(b.dataset.anh)); return; }
    if (e.target.closest('[data-dong]')) VN.dongHopThoai(hopAnh);
  });
  hopAnh.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowRight') { e.preventDefault(); doiAnhLon(1); }
    if (e.key === 'ArrowLeft') { e.preventDefault(); doiAnhLon(-1); }
  });
  hopAnh.addEventListener('close', () => { if (viTriLon !== tt.viTri) chonAnh(viTriLon, true); });
  ganVuot(VN.$('.hop-anh__than', hopAnh), doiAnhLon);

  /* ================= 4. KHẮC CHỮ – XEM TRƯỚC TRỰC TIẾP TRÊN ẢNH ================= */
  const layChuKhac = () => el.oKhac.value.normalize('NFC').replace(/\s+/g, ' ').trim();
  const kieuChu = () => (el.form.elements['kieu-chu'] ? el.form.elements['kieu-chu'].value : 'co-dien');
  const mauKhac = () => tt.mau || (tt.sp && tt.sp.mau[0]) || (tt.sp && tt.sp.chatLieu === 'BAC925' ? 'Bạc Trắng' : 'Vàng Vàng');
  const xemNho = document.createElement('div');
  xemNho.className = 'khac-chu__xem-nho';
  xemNho.setAttribute('aria-hidden', 'true');

  const veKhac = () => {
    if (!tt.sp) return;
    const chu = layChuKhac(); const kieu = kieuChu(); const mau = mauKhac();
    VN.veKhacChu(VN.$('.thu-vien__khac-ve', el.khac), chu, kieu, mau);
    VN.veKhacChu(xemNho, chu, kieu, mau);
    VN.$('.thu-vien__khac-chu', el.khac).innerHTML = `${VN.bt('but', 'bt--nho')}<span>Mặt trong đai nhẫn · <strong>${TEN_KIEU[kieu]}</strong> · ${VN.thoat(mau)}</span>`;
  };
  const datCheDoKhac = (bat) => {
    tt.dangKhac = bat;
    el.khung.classList.toggle('dang-khac', bat);
    el.khung.classList.remove('dang-phong');
    el.chuyen.setAttribute('aria-pressed', String(bat));
    VN.$('span', el.chuyen).textContent = bat ? 'Xem ảnh sản phẩm' : 'Xem chữ khắc';
    const nutKhac = VN.$('[data-xem-khac]', el.nho);
    if (nutKhac) nutKhac.setAttribute('aria-current', String(bat));
    VN.$$('[data-anh]', el.nho).forEach((b) => b.setAttribute('aria-current', String(!bat && Number(b.dataset.anh) === tt.viTri)));
    el.phong.hidden = bat;
    el.dem.hidden = bat;
    if (bat) veKhac();
  };
  const hienLoiKhac = (loi) => {
    const truong = el.oKhac.closest('.truong');
    truong.classList.toggle('co-loi', !!loi);
    VN.$('#loi-khac').innerHTML = loi ? `${VN.bt('canh-bao', 'bt--nho')}<span>${loi}</span>` : '';
    el.oKhac.setAttribute('aria-invalid', loi ? 'true' : 'false');
  };
  const kiemTraKhac = () => {
    const chu = layChuKhac(); let loi = '';
    if (!chu) loi = 'Vui lòng nhập nội dung khắc hoặc bỏ chọn khắc chữ.';
    else if (!KY_TU_KHAC.test(chu)) loi = 'Có ký tự không khắc được. Chỉ dùng chữ, số, khoảng trắng và &amp; . , - ♥ ∞';
    else if (demKyTu(chu) > tt.toiDaKhac) loi = `Nội dung khắc tối đa ${tt.toiDaKhac} ký tự.`;
    hienLoiKhac(loi);
    return !loi;
  };

  el.batKhac.addEventListener('change', () => {
    const bat = el.batKhac.checked;
    VN.$('#khac-noi-dung').hidden = !bat;
    el.chuyen.hidden = !bat;
    const nutKhac = VN.$('[data-xem-khac]', el.nho); if (nutKhac) { nutKhac.hidden = !bat; if (bat) { el.nho.scrollTop = 0; el.nho.scrollLeft = 0; } }
    datCheDoKhac(bat);
    if (bat) el.oKhac.focus({ preventScroll: true }); else hienLoiKhac('');
  });
  el.oKhac.addEventListener('input', () => {
    const chu = el.oKhac.value.normalize('NFC');
    if (chu !== el.oKhac.value) el.oKhac.value = chu;
    VN.$('#dem-khac').textContent = `${demKyTu(chu)}/${tt.toiDaKhac}`;
    const gon = layChuKhac();
    if (gon && !KY_TU_KHAC.test(gon)) hienLoiKhac('Có ký tự không khắc được. Chỉ dùng chữ, số, khoảng trắng và &amp; . , - ♥ ∞');
    else if (gon || el.oKhac.closest('.truong').classList.contains('co-loi')) hienLoiKhac('');
    if (!tt.dangKhac) datCheDoKhac(true); else veKhac();
  });
  VN.$('#ds-kieu-chu').addEventListener('change', () => { if (!tt.dangKhac) datCheDoKhac(true); else veKhac(); });
  VN.$$('[data-chen]', el.form).forEach((b) => b.addEventListener('click', () => {
    const kt = b.dataset.chen; const v = el.oKhac.value;
    if (demKyTu(v) >= tt.toiDaKhac) { hienLoiKhac(`Nội dung khắc tối đa ${tt.toiDaKhac} ký tự.`); return; }
    const a = el.oKhac.selectionStart ?? v.length; const z = el.oKhac.selectionEnd ?? v.length;
    el.oKhac.value = v.slice(0, a) + kt + v.slice(z);
    el.oKhac.focus();
    el.oKhac.setSelectionRange(a + kt.length, a + kt.length);
    el.oKhac.dispatchEvent(new Event('input'));
  }));
  el.chuyen.addEventListener('click', () => datCheDoKhac(!tt.dangKhac));
  // Vẽ lại khi phông chữ đã tải xong để bản xem trước đúng kiểu chữ
  if (document.fonts) document.fonts.ready.then(() => { if (tt.dangKhac) veKhac(); });

  /* ================= 5. MÀU, SIZE, SỐ LƯỢNG ================= */
  const chonSize = (k) => {
    tt.size = k;
    const r = VN.$(`#ds-size input[value="${k}"]`); if (r) r.checked = true;
    const dong = (tt.bangSize.bangSize || []).find((d) => d.size === k);
    VN.$('#ten-size-chon').textContent = dong ? `· Size ${k} – chu vi ${so(dong.chuVi, 1)} mm` : `· Size ${k}`;
    VN.$('#loi-size').innerHTML = '';
    VN.$('#nhom-size').classList.remove('co-loi');
    VN.$$('.bang-size tbody tr').forEach((tr) => tr.classList.toggle('dang-chon', Number(tr.dataset.size) === k));
  };
  const datSoLuong = (n) => {
    n = Math.max(1, Math.min(tt.toiDa, Math.round(Number(n) || 1)));
    tt.soLuong = n; el.soLuong.value = n;
    VN.$('[data-dem="-1"]', el.form).disabled = n <= 1;
    VN.$('[data-dem="1"]', el.form).disabled = n >= tt.toiDa;
  };

  const veLuaChon = (s, ch) => {
    // Màu vàng
    if (s.mau.length) {
      VN.$('#nhom-mau').hidden = false;
      const mauUrl = VN.thamSo('mau');
      tt.mau = s.mau.includes(mauUrl) ? mauUrl : s.mau[0];
      VN.$('#ds-mau').innerHTML = s.mau.map((m) => `<label><input class="an-chu" type="radio" name="mau" value="${VN.thoat(m)}"${m === tt.mau ? ' checked' : ''}><span class="chip"><span class="cham-mau ${VN.lopMau(m)}"></span>${VN.thoat(m)}</span></label>`).join('');
      VN.$('#ten-mau-chon').textContent = tt.mau;
      VN.$('#ds-mau').addEventListener('change', (e) => { tt.mau = e.target.value; VN.$('#ten-mau-chon').textContent = tt.mau; if (el.batKhac.checked) veKhac(); });
    }
    if (!s.coTheMua) {
      // Sản phẩm tính theo giá vàng ngày: không đặt trực tuyến, chuyển sang nhận báo giá
      const kq = VN.$('#khu-bao-gia'); kq.hidden = false;
      const hotline = ch.thuongHieu.hotline;
      kq.innerHTML = `<div class="hop-bao hop-bao--vang">${VN.bt('thong-tin')}<p>Sản phẩm vàng ${VN.thoat(s.chatLieu)} tính theo <strong>giá vàng niêm yết trong ngày</strong> nên chưa hỗ trợ đặt hàng trực tuyến. Gửi yêu cầu, chuyên viên Vinora sẽ báo giá chính xác trong giờ làm việc (${VN.thoat(ch.thuongHieu.gioLamViec)}).</p></div>
        <div class="hang"><a class="nut nut--chinh" href="${VN.url('lienHe', { sanpham: s.ma })}">${VN.bt('thu')} Nhận báo giá</a><a class="nut nut--vien" href="tel:${hotline.replace(/\s/g, '')}">${VN.bt('dien-thoai')} Gọi ${VN.thoat(hotline)}</a></div>`;
      return;
    }
    VN.$('#khu-mua').hidden = false;
    // Size nhẫn (FR7)
    if (s.canChonSize) {
      VN.$('#nhom-size').hidden = false;
      const { nhoNhat, lonNhat } = ch.sizeNhan;
      const u = VN.taiKhoan.hienTai();
      const sizeLuu = u && u.sizeNhan ? Number(u.sizeNhan) : null;
      let html = '';
      for (let k = nhoNhat; k <= lonNhat; k++) {
        html += `<label><input class="an-chu" type="radio" name="size" value="${k}" aria-label="Size ${k}${k === sizeLuu ? ' (size đã lưu)' : ''}"><span class="chip${k === sizeLuu ? ' la-size-luu' : ''}"${k === sizeLuu ? ' title="Size đã lưu trong tài khoản"' : ''}>${k}</span></label>`;
      }
      VN.$('#ds-size').innerHTML = html;
      if (sizeLuu) VN.$('#goi-y-size').innerHTML = `Size đã lưu trong tài khoản: <button type="button" class="lien-ket" data-chon-size="${sizeLuu}">chọn size ${sizeLuu}</button> · Chỉnh size miễn phí trọn đời tại cửa hàng.`;
      VN.$('#ds-size').addEventListener('change', (e) => chonSize(Number(e.target.value)));
      const sizeUrl = Number(VN.thamSo('size'));
      if (sizeUrl >= nhoNhat && sizeUrl <= lonNhat) chonSize(sizeUrl);
    }
    // Khắc chữ: chỉ áp dụng cho danh mục nhẫn trong cấu hình
    if ((ch.khacChu.apDungDanhMuc || []).includes(s.danhMuc)) {
      VN.$('#nhom-khac').hidden = false;
      el.oKhac.maxLength = tt.toiDaKhac;
      VN.$('#dem-khac').textContent = `0/${tt.toiDaKhac}`;
      VN.$('#khac-noi-dung').prepend(xemNho);
    }
    el.soLuong.max = tt.toiDa;
    datSoLuong(1);
  };

  VN.$$('[data-dem]', el.form).forEach((b) => b.addEventListener('click', () => datSoLuong(tt.soLuong + Number(b.dataset.dem))));
  el.soLuong.addEventListener('change', () => datSoLuong(el.soLuong.value));

  /* ================= 6. THÊM VÀO GIỎ / MUA NGAY ================= */
  const kiemTraLuaChon = () => {
    let vungLoi = null;
    if (tt.sp.canChonSize && !tt.size) {
      VN.$('#loi-size').innerHTML = `${VN.bt('canh-bao', 'bt--nho')}<span>Vui lòng chọn size nhẫn. Chưa rõ size? Xem <button type="button" class="lien-ket" data-mo-size>hướng dẫn đo size</button>.</span>`;
      VN.$('#nhom-size').classList.add('co-loi');
      vungLoi = VN.$('#nhom-size');
    }
    if (el.batKhac.checked && !kiemTraKhac()) vungLoi = vungLoi || VN.$('#nhom-khac');
    if (!vungLoi) return true;
    vungLoi.scrollIntoView({ behavior: 'smooth', block: 'center' });
    const dau = vungLoi.id === 'nhom-size' ? VN.$('#ds-size input') : el.oKhac;
    setTimeout(() => dau && dau.focus({ preventScroll: true }), 420);
    return false;
  };

  let henNut;
  const themVaoGio = (muaNgay) => {
    if (!tt.sp || !tt.sp.coTheMua || !kiemTraLuaChon()) return;
    const dong = { ma: tt.sp.ma, soLuong: tt.soLuong };
    if (tt.mau) dong.mau = tt.mau;
    if (tt.sp.canChonSize) dong.size = tt.size;
    if (el.batKhac.checked) { dong.khacChu = layChuKhac(); dong.kieuChu = kieuChu(); }
    const { vuotMuc } = VN.gioHang.them(dong, tt.toiDa);
    if (muaNgay) { location.href = VN.url('thanhToan'); return; }
    const nut = VN.$('#nut-them-gio');
    nut.classList.add('da-them'); VN.$('span', nut).textContent = 'Đã thêm vào giỏ'; VN.$('use', nut).setAttribute('href', '#i-dau-tich');
    clearTimeout(henNut);
    henNut = setTimeout(() => { nut.classList.remove('da-them'); VN.$('span', nut).textContent = 'Thêm vào giỏ hàng'; VN.$('use', nut).setAttribute('href', '#i-tui'); }, 2400);
    VN.moGioMini();
    if (vuotMuc) VN.thongBao({ tieuDe: `Tối đa ${tt.toiDa} sản phẩm cho mỗi lựa chọn`, noiDung: 'Số lượng trong giỏ đã được điều chỉnh về mức tối đa. Liên hệ hotline nếu bạn cần đặt nhiều hơn.' });
  };
  el.form.addEventListener('submit', (e) => { e.preventDefault(); themVaoGio(false); });
  VN.$('#nut-mua-ngay').addEventListener('click', () => themVaoGio(true));

  /* Thanh mua nhanh xuất hiện khi nút mua đã cuộn khỏi màn hình */
  const ganThanhMua = (s) => {
    const thanh = VN.$('#thanh-mua'); const nut = VN.$('#thanh-mua-nut');
    VN.$('#thanh-mua-ten').textContent = s.ten;
    VN.$('#thanh-mua-gia').textContent = s.coTheMua ? VN.tien(s.giaBan) : 'Giá vàng theo ngày';
    nut.textContent = s.coTheMua ? 'Thêm vào giỏ' : 'Nhận báo giá';
    nut.addEventListener('click', () => { if (s.coTheMua) themVaoGio(false); else location.href = VN.url('lienHe', { sanpham: s.ma }); });
    // Theo dõi bằng sự kiện cuộn (gộp theo khung hình) để bắt cả khi người dùng cuộn rất nhanh
    const moc = s.coTheMua ? VN.$('#khu-mua') : VN.$('#khu-bao-gia');
    let cho = false; let dangHien = false;
    const capNhat = () => {
      cho = false;
      const hien = moc.getBoundingClientRect().bottom < 0;
      if (hien === dangHien) return;
      dangHien = hien;
      thanh.classList.toggle('dang-hien', hien);
      thanh.setAttribute('aria-hidden', String(!hien));
      nut.tabIndex = hien ? 0 : -1;
    };
    window.addEventListener('scroll', () => { if (!cho) { cho = true; requestAnimationFrame(capNhat); } }, { passive: true });
    capNhat();
  };

  /* ================= 7. BẢNG HƯỚNG DẪN ĐO SIZE + MÁY TÍNH SIZE ================= */
  const veBangSize = (khung, tien, coChon) => {
    const bs = tt.bangSize; const ds = bs.bangSize;
    khung.innerHTML = `
      <div class="bang-size-khung">
        <div class="bang-size-khung__trai">
          <ol class="cach-do">
            <li><span class="cach-do__so"><span>1</span></span><div><h3>Quấn quanh ngón tay</h3><p>Dùng sợi chỉ hoặc dải giấy nhỏ quấn sát quanh đốt ngón tay định đeo nhẫn, đánh dấu điểm giao nhau.</p></div></li>
            <li><span class="cach-do__so"><span>2</span></span><div><h3>Đo chiều dài</h3><p>Duỗi thẳng và đo bằng thước đến điểm đánh dấu – đó là chu vi ngón tay (mm). Hoặc đo đường kính trong của chiếc nhẫn đang đeo vừa.</p></div></li>
            <li><span class="cach-do__so"><span>3</span></span><div><h3>Đối chiếu size</h3><p>Size (ni) ≈ chu vi − 40. Nên đo vào cuối ngày; nếu số đo nằm giữa hai size, hãy chọn size lớn hơn.</p></div></li>
          </ol>
          <form class="may-tinh-size" data-may-tinh novalidate>
            <div class="may-tinh-size__dau">${VN.bt('thuoc')}<h3 class="t-4">Gợi ý size từ số đo của bạn</h3></div>
            <div class="may-tinh-size__o">
              <label class="an-chu" for="${tien}-kieu-do">Loại số đo</label>
              <select class="o-chon" id="${tien}-kieu-do"><option value="chu-vi">Chu vi ngón tay</option><option value="duong-kinh">Đường kính trong nhẫn</option></select>
              <label class="an-chu" for="${tien}-so-do">Số đo (mm)</label>
              <input class="o-nhap" id="${tien}-so-do" type="number" min="10" max="90" step="0.1" inputmode="decimal" placeholder="Số đo (mm), ví dụ 52">
            </div>
            <p class="may-tinh-size__kq" aria-live="polite">Nhập số đo theo milimét để xem size gợi ý.</p>
          </form>
          <div class="bang-size-ghi-chu">
            <p class="goi-y-truong">${VN.thoat(bs.ghiChu)}</p>
            ${bs.goiYSize ? `<p class="goi-y-truong">Tham khảo: ${VN.thoat(bs.goiYSize.nu)}; ${VN.thoat(bs.goiYSize.nam)}.</p>` : ''}
          </div>
        </div>
        <div class="bang-boc bang-size-cuon">
          <table class="bang bang--gon bang-size">
            <caption class="an-chu">Bảng quy đổi size nhẫn</caption>
            <thead><tr><th scope="col">Size<br>(ni)</th><th scope="col" class="so">Chu vi<br>(mm)</th><th scope="col" class="so">Đường kính<br>(mm)</th><th scope="col" class="so">Size<br>Mỹ</th>${coChon ? '<th scope="col"><span class="an-chu">Chọn size</span></th>' : ''}</tr></thead>
            <tbody>${ds.map((d) => `<tr data-size="${d.size}"${d.size === tt.size ? ' class="dang-chon"' : ''}><td>${d.size}</td><td class="so">${so(d.chuVi, 1)}</td><td class="so">${so(d.duongKinh, 1)}</td><td class="so">${so(d.sizeMy, 1)}</td>${coChon ? `<td class="so"><button type="button" class="nut nut--chu" data-chon-size="${d.size}" aria-label="Chọn size ${d.size}">Chọn</button></td>` : ''}</tr>`).join('')}</tbody>
          </table>
        </div>
      </div>`;
    const form = VN.$('[data-may-tinh]', khung);
    const kq = VN.$('.may-tinh-size__kq', form);
    const cuonBang = VN.$('.bang-size-cuon', khung);
    // Chỉ vẽ lại khi kết quả thay đổi: tránh nút "Chọn size" bị thay mới đúng lúc người dùng bấm
    let htmlCu = '';
    const datKq = (html) => { if (html !== htmlCu) { kq.innerHTML = html; htmlCu = html; } };
    const tinh = () => {
      VN.$$('tbody tr', khung).forEach((tr) => tr.classList.remove('goi-y'));
      const kieu = VN.$('select', form).value;
      const v = parseFloat(String(VN.$('input', form).value).replace(',', '.'));
      if (!v) { datKq('Nhập số đo theo milimét để xem size gợi ý.'); return; }
      const chuVi = kieu === 'chu-vi' ? v : v * 3.14;
      if (chuVi < 35 || chuVi > 80) { datKq('Số đo chưa hợp lý – hãy kiểm tra lại đơn vị milimét (mm).'); return; }
      if (chuVi < ds[0].chuVi - 1) { datKq(`Số đo nhỏ hơn size ${ds[0].size}. Vui lòng liên hệ Vinora để đặt size riêng.`); return; }
      const dong = ds.find((d) => d.chuVi >= chuVi - 0.3);
      if (!dong) { datKq(`Số đo lớn hơn size ${ds[ds.length - 1].size}. Vui lòng liên hệ Vinora để đặt size riêng.`); return; }
      datKq(`<span>Size gợi ý</span><strong>${dong.size}</strong><span>chu vi ${so(dong.chuVi, 1)} mm · đường kính ${so(dong.duongKinh, 1)} mm</span>`
        + (coChon ? `<button type="button" class="nut nut--vien nut--rat-nho" data-chon-size="${dong.size}">Chọn size ${dong.size}</button>` : ''));
      const tr = VN.$(`tbody tr[data-size="${dong.size}"]`, khung);
      if (tr) { tr.classList.add('goi-y'); cuonVaoKhung(tr, cuonBang); }
    };
    form.addEventListener('input', tinh);
    form.addEventListener('change', tinh);
    form.addEventListener('submit', (e) => { e.preventDefault(); tinh(); });
  };

  const hopSize = VN.$('#hop-size');
  const moHopSize = () => {
    if (!tt.bangSize) return;
    const khung = VN.$('#bang-size-hop');
    if (!khung.children.length) veBangSize(khung, 'hop', !!(tt.sp && tt.sp.canChonSize && tt.sp.coTheMua));
    VN.moHopThoai(hopSize);
  };
  VN.$('#mo-bang-size').addEventListener('click', moHopSize);
  hopSize.addEventListener('click', (e) => { if (e.target.closest('[data-dong]')) VN.dongHopThoai(hopSize); });

  // Chọn size từ bảng / máy tính size / gợi ý size đã lưu; mở hướng dẫn từ thông báo lỗi
  document.addEventListener('click', (e) => {
    if (e.target.closest('[data-mo-size]')) { moHopSize(); return; }
    const b = e.target.closest('[data-chon-size]');
    if (!b || !tt.sp || !tt.sp.canChonSize) return;
    const k = Number(b.dataset.chonSize);
    chonSize(k);
    const hop = b.closest('dialog');
    if (hop) VN.dongHopThoai(hop);
    if (hop || b.closest('#phan-size')) {
      VN.thongBao({ tieuDe: `Đã chọn size ${k}`, noiDung: 'Bạn có thể đổi size bất cứ lúc nào trước khi đặt hàng.', loai: 'thanh-cong', thoiGian: 2600 });
      if (b.closest('#phan-size')) VN.$('#nhom-size').scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  });

  /* ================= 8. BẢNG CAM KẾT CHÍNH SÁCH BẢO HÀNH ================= */
  const veCamKet = (s, ch) => {
    const bh = ch.baoHanh;
    VN.$('#bang-cam-ket').innerHTML = `
      <div class="cam-ket-bh__khoi">
        <div class="cam-ket-bh__dau"><span class="nhan nhan--ngoc">Miễn phí</span><h3>Dịch vụ bảo hành miễn phí</h3><p>Áp dụng cho từng sản phẩm; số lượt còn lại được theo dõi trong Cổng bảo hành điện tử.</p></div>
        <div class="bang-boc"><table class="bang bang--gon">
          <caption class="an-chu">Dịch vụ bảo hành miễn phí</caption>
          <thead><tr><th scope="col">Nội dung</th><th scope="col" class="so">Thời gian</th></tr></thead>
          <tbody>${bh.quyenLoi.map((q) => {
            const khongAp = q.chiChoNhan && !s.canChonSize;
            const ghiChu = khongAp ? 'Chỉ áp dụng cho nhẫn' : (q.datLich ? 'Đặt lịch trực tuyến' : 'Thực hiện tại showroom');
            return `<tr${khongAp ? ' class="khong-ap-dung"' : ''}><td>${VN.thoat(q.ten)}<small>${ghiChu}</small></td><td class="so">${VN.thoat(q.hienThi)}</td></tr>`;
          }).join('')}</tbody>
        </table></div>
      </div>
      <div class="cam-ket-bh__khoi">
        <div class="cam-ket-bh__dau"><span class="nhan nhan--cam">Có tính phí</span><h3>Dịch vụ bảo hành tính phí</h3><p>Áp dụng cho các hạng mục ngoài phạm vi miễn phí.</p></div>
        <div class="bang-boc"><table class="bang bang--gon">
          <caption class="an-chu">Dịch vụ bảo hành tính phí</caption>
          <thead><tr><th scope="col">Nội dung</th><th scope="col" class="so">Chi phí</th></tr></thead>
          <tbody>${bh.tinhPhi.map((p) => `<tr><td>${VN.thoat(p.ten)}</td><td class="so">${VN.thoat(p.chiPhi)}</td></tr>`).join('')}</tbody>
        </table></div>
        <ul class="cam-ket-bh__luu-y">
          <li>Thẻ bảo hành điện tử tự kích hoạt khi bạn bấm “Đã nhận được hàng”; mỗi sản phẩm có một mã thẻ riêng.</li>
          <li>Lượt dịch vụ chỉ được trừ khi dịch vụ hoàn tất; lịch hẹn đã hủy không bị tính lượt.</li>
          <li>Đặt lịch trước tối đa ${bh.datTruocToiDaNgay} ngày, chọn showroom và khung giờ phù hợp.</li>
        </ul>
      </div>`;
  };

  /* ================= 9. GỢI Ý & SẢN PHẨM ĐÃ XEM ================= */
  const hienDai = (phan, dai, ds) => {
    if (!ds.length) return;
    phan.hidden = false;
    VN.veLuoi(dai, ds);
    const khungNut = VN.$(`[data-dieu-khien="${dai.id}"]`);
    const capNhat = VN.ganDieuKhienTruot(dai, khungNut);
    if (capNhat) setTimeout(capNhat, 60);
  };
  const veGoiY = (s, ds) => {
    const khac = ds.filter((x) => x.ma !== s.ma);
    const gan = (a, b) => Math.abs(a.gia - s.gia) - Math.abs(b.gia - s.gia);
    const cungBst = khac.filter((x) => x.boSuuTap === s.boSuuTap).sort((a, b) => (b.danhMuc === s.danhMuc) - (a.danhMuc === s.danhMuc) || gan(a, b));
    const cungLoai = khac.filter((x) => x.danhMuc === s.danhMuc && x.boSuuTap !== s.boSuuTap).sort(gan);
    const coBst = cungBst.length >= 4 && s.bst && s.bst.ten;
    VN.$('#lien-quan-nhan').textContent = coBst ? `Cùng bộ sưu tập ${s.bst.ten}` : `Cùng loại ${s.dm.ten.toLowerCase()}`;
    VN.$('#lien-quan-xem').href = coBst ? VN.url('sanPham', { bst: s.boSuuTap }) : VN.url('sanPham', { danhmuc: s.danhMuc });
    hienDai(VN.$('#phan-lien-quan'), VN.$('#dai-lien-quan'), cungBst.concat(cungLoai).slice(0, 12));
  };
  const veDaXem = (s, theoMa) => {
    const ds = VN.daXem.ds().filter((x) => x.ma !== s.ma).map((x) => theoMa[x.ma]).filter(Boolean).slice(0, 12);
    hienDai(VN.$('#phan-da-xem-ct'), VN.$('#dai-da-xem-ct'), ds);
  };

  /* ================= 10. SAO CHÉP MÃ & CHIA SẺ ================= */
  const saoChep = async (chu, tieuDe, noiDung) => {
    try {
      await navigator.clipboard.writeText(chu);
    } catch (e) {
      const o = document.createElement('textarea');
      o.value = chu; o.setAttribute('readonly', ''); o.style.cssText = 'position:fixed;opacity:0';
      document.body.appendChild(o); o.select();
      try { document.execCommand('copy'); } catch (e2) { o.remove(); VN.thongBao({ tieuDe: 'Chưa sao chép được', noiDung: VN.thoat(chu), loai: 'loi' }); return; }
      o.remove();
    }
    VN.thongBao({ tieuDe, noiDung, loai: 'thanh-cong', thoiGian: 2600 });
  };
  VN.$('#ct-sao-ma').addEventListener('click', () => { if (tt.sp) saoChep(tt.sp.ma, 'Đã sao chép mã sản phẩm', VN.thoat(tt.sp.ma)); });
  VN.$('#ct-chia-se').addEventListener('click', async () => {
    if (!tt.sp) return;
    if (navigator.share) {
      try { await navigator.share({ title: tt.sp.ten, text: `${tt.sp.ten} – Vinora Jewelry`, url: location.href }); } catch (e) { /* người dùng đóng hộp chia sẻ */ }
      return;
    }
    saoChep(location.href, 'Đã sao chép liên kết sản phẩm', 'Dán liên kết để gửi cho người thân hoặc bạn bè.');
  });
})();
