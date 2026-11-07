/* =====================================================================
   5.2.8 CỔNG BẢO HÀNH ĐIỆN TỬ & ĐẶT LỊCH HẬU MÃI (FR15, FR16, FR17) – nối API /api/warranties, /api/after-sales
   - Thẻ bảo hành dạng thẻ ATM, quyền lợi & số lượt còn lại, lịch sử dịch vụ (thẻ do database tạo khi đơn giao xong)
   - Đặt lịch: thẻ hợp lệ, dịch vụ (làm sạch / đánh bóng & xi mới / chỉnh size), showroom đọc từ XML (AJAX),
     ngày bất kỳ sau ngày nhận hàng (trong giới hạn 1 năm của database), khung giờ (ghi vào giờ hẹn), ảnh tình trạng (BẢN DEMO: chỉ xem trước bằng FileReader,
     không gửi đi; số ảnh đã chọn ghi vào ghi chú để cửa hàng biết)
   - Lịch hẹn: Chờ xác nhận -> Đã xác nhận / Đã đổi giờ -> Hoàn tất (database trừ lượt) / Đã hủy (không mất lượt)
   - Hết lượt miễn phí (đánh bóng & xi mới) vẫn đặt lịch được: dịch vụ tính phí, trả tại showroom
   - Đơn đang giao hiện ngay đầu trang với nút "Đã nhận được hàng": bấm là thẻ bảo hành được kích hoạt tại chỗ
   - Hiệu lực thẻ: lỗi chế tác 12 tháng từ ngày nhận hàng, dịch vụ hậu mãi trọn đời (không có ngày hết hạn)
   - Khách đặt hàng không cần tài khoản: xem thẻ của các đơn đã mở trên trình duyệt này (mã đơn + số điện thoại), tra cứu thẻ;
     đặt lịch cần tài khoản (tạo bằng số điện thoại đã đặt hàng để thẻ tự liên kết)
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const khu = VN.$('#khu-bh');
  if (!khu) return;
  let u = null;      // khách có tài khoản (gán khi đã tải phiên đăng nhập)
  const tt = { ch: null, cuaHang: [], the: null, tab: 'the' };
  const TAB = { the: 'bang-the', 'lich-hen': 'bang-lich', 'tra-cuu': 'bang-tra' };

  /* ================= TAB ================= */
  const moTab = (ten, ghiUrl = true) => {
    if (!TAB[ten]) ten = 'the';
    tt.tab = ten;
    VN.$$('[data-tab-bh]').forEach((b) => { const chon = b.dataset.tabBh === ten; b.setAttribute('aria-selected', String(chon)); b.tabIndex = chon ? 0 : -1; });
    Object.entries(TAB).forEach(([k, id]) => { VN.$('#' + id).hidden = k !== ten; });
    VN.$$('.menu-tk__ds a').forEach((a) => {
      const laLich = a.href.includes('tab=lich-hen'); const laBh = !laLich && a.pathname === location.pathname;
      if (laLich || laBh) { if ((ten === 'lich-hen') === laLich) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current'); }
    });
    if (ghiUrl) history.replaceState(null, '', VN.url('congBaoHanh', Object.assign(ten === 'the' ? {} : { tab: ten }, tt.the && ten === 'the' ? { the: tt.the } : {})));
  };
  VN.$$('[data-tab-bh]').forEach((b) => {
    b.addEventListener('click', () => moTab(b.dataset.tabBh));
    b.addEventListener('keydown', (e) => {
      if (!['ArrowLeft', 'ArrowRight'].includes(e.key)) return;
      const ds = VN.$$('[data-tab-bh]'); const i = ds.indexOf(b);
      const k = ds[(i + (e.key === 'ArrowRight' ? 1 : -1) + ds.length) % ds.length]; k.focus(); moTab(k.dataset.tabBh);
    });
  });

  /* ================= THẺ BẢO HÀNH ================= */
  const phiSauHetLuot = (ma) => (tt.ch.baoHanh.phiSauHetLuot || {})[ma] || 0;
  const conLaiChu = (the, q) => {
    const n = VN.baoHanh.conLai(the, tt.ch, q.ma);
    if (n === Infinity) return q.hienThi;
    return `${n}/${the.hanMuc[q.ma]} lượt${n <= 0 && phiSauHetLuot(q.ma) ? ` · sau đó ${VN.tien(phiSauHetLuot(q.ma))}/lần` : ''}`;
  };
  /** Thẻ hiển thị: của tài khoản, hoặc (khách chưa đăng nhập) thẻ của các đơn đã mở trên trình duyệt này (VN.baoHanh.nap chọn sẵn) */
  const dsThe = () => VN.baoHanh.tatCa();
  const chuTheCua = (the) => the.chuThe || '';
  const veDsThe = () => {
    const ds = dsThe();
    VN.$$('[data-dem-the]').forEach((x) => { x.textContent = ds.length || ''; });
    const khung = VN.$('#bh-ds-the');
    if (!ds.length && !u) { khung.innerHTML = ''; VN.$('#bh-ct-the').innerHTML = ''; VN.$('#dat-lich').hidden = true; return; }
    if (!ds.length) {
      khung.innerHTML = `<div class="trong-rong khoi-tk"><div class="trong-rong__bieu-tuong">${VN.bt('khien')}</div><h2 class="t-3">Bạn chưa có thẻ bảo hành nào</h2>
        <p>Thẻ được kích hoạt tự động cho từng sản phẩm khi bạn bấm “Đã nhận được hàng” trong mục Đơn hàng của tôi.</p><a class="nut nut--chinh nut--nho" href="${VN.url('donHang')}">Đơn hàng của tôi</a></div>`;
      VN.$('#bh-ct-the').innerHTML = ''; VN.$('#dat-lich').hidden = true; return;
    }
    if (!tt.the || !ds.some((t) => t.ma === tt.the)) tt.the = ds[0].ma;
    khung.innerHTML = `<p class="nhan-truong">${ds.length} thẻ ${u ? 'của bạn' : 'của đơn hàng trên thiết bị này'}</p><div class="ds-the-nho__luoi">${ds.map((t) => `
      <button type="button" class="the-nho${t.ma === tt.the ? ' dang-chon' : ''}" data-chon-the="${VN.thoat(t.ma)}" aria-pressed="${t.ma === tt.the}">
        <span class="the-nho__anh"><img src="${VN.anh(t.anh)}" alt="" width="56" height="56" loading="lazy"></span>
        <span class="the-nho__chu"><strong>${VN.thoat(t.tenSP)}</strong><small class="so-deu">${VN.soTheDep(t.ma)}</small><small>Kích hoạt ${VN.ngay(t.ngayKichHoat)}${t.size ? ' · Size ' + t.size : ''}</small></span>
      </button>`).join('')}</div>`;
    veCtThe();
    if (u) veFormThe(); else VN.$('#dat-lich').hidden = true;
  };

  const veCtThe = () => {
    const the = VN.baoHanh.lay(tt.the); if (!the) return;
    const ql = tt.ch.baoHanh.quyenLoi;
    const lich = VN.lichHen.tatCa().filter((l) => l.maBaoHanh === the.ma && l.dangMo);
    VN.$('#bh-ct-the').innerHTML = `
      <section class="khoi-tk ct-the__khung" aria-labelledby="td-ct-the">
        <div class="ct-the__the">${VN.htmlTheBaoHanh(the, tt.ch, chuTheCua(the))}<p class="chu-rat-nho chu-phu">Bấm vào thẻ để lật mặt sau</p></div>
        <div class="ct-the__chu">
          <p class="nhan-tren">Chi tiết thẻ</p>
          <h2 class="t-3" id="td-ct-the">${VN.thoat(the.tenSP)}</h2>
          <dl class="tt-the">
            <div><dt>Mã thẻ</dt><dd class="so-deu">${VN.soTheDep(the.ma)}</dd></div>
            <div><dt>Sản phẩm</dt><dd><a class="lien-ket" href="${VN.urlSanPham(the.maSP)}">${VN.thoat(the.maSP)}</a> · ${VN.thoat(the.chatLieu)}${the.mau ? ' · ' + VN.thoat(the.mau) : ''}${the.size ? ' · Size ' + the.size : ''}</dd></div>
            ${the.khacChu ? `<div><dt>Chữ khắc</dt><dd>“${VN.thoat(the.khacChu)}”</dd></div>` : ''}
            <div><dt>Đơn hàng</dt><dd><a class="lien-ket" href="${VN.url('donHang', { ma: the.donHang })}">${VN.thoat(the.donHang)}</a></dd></div>
            ${the.sdtKhach ? `<div><dt>SĐT chủ thẻ</dt><dd class="so-deu">${VN.thoat(VN.anSdt(the.sdtKhach))}</dd></div>` : ''}
            <div><dt>Kích hoạt</dt><dd>${VN.ngay(the.ngayKichHoat)} (ngày nhận hàng)</dd></div>
            <div><dt>Hiệu lực</dt><dd>${VN.thoat(the.hieuLucDay)} · <a class="lien-ket" href="${VN.url('chinhSachBaoHanh')}#hieu-luc">Giải thích</a></dd></div>
          </dl>
          ${lich.length ? `<p class="hop-bao hop-bao--ngoc">${VN.bt('lich')}<span>Có ${lich.length} lịch hẹn sắp tới cho thẻ này – <button type="button" class="lien-ket" data-di-lich>xem lịch hẹn</button>.</span></p>` : ''}
          <div class="hang hang--quan">
            ${u ? `<a class="nut nut--chinh nut--nho" href="#dat-lich" data-cuon-dat-lich>${VN.bt('lich')} Đặt lịch cho thẻ này</a>`
              : `<a class="nut nut--chinh nut--nho" href="${VN.url('taiKhoan', { dangky: 1, sdt: the.sdtKhach })}">${VN.bt('tai-khoan')} Tạo tài khoản để đặt lịch</a>`}
            <button type="button" class="nut nut--vien nut--nho" data-xem-gcn="${VN.thoat(the.ma)}">${VN.bt('chung-nhan')} Giấy chứng nhận</button>
          </div>
        </div>
      </section>
      <div class="ct-the__luoi">
        <section class="khoi-tk" aria-labelledby="td-ql">
          <div class="khoi-tk__dau"><div><p class="nhan-tren">Quyền lợi</p><h2 id="td-ql">Dịch vụ miễn phí còn lại</h2></div></div>
          <div class="bang-boc"><table class="bang bang--gon">
            <caption class="an-chu">Quyền lợi bảo hành của thẻ ${VN.thoat(the.ma)}</caption>
            <thead><tr><th scope="col">Dịch vụ</th><th scope="col" class="so">Đã dùng</th><th scope="col" class="so">Còn lại</th></tr></thead>
            <tbody>${ql.map((q) => {
              const khong = q.chiChoNhan && !the.laNhan;
              return `<tr${khong ? ' class="khong-ap-dung"' : ''}><td>${VN.thoat(q.ten)}<small>${khong ? 'Chỉ áp dụng cho nhẫn' : q.datLich ? 'Đặt lịch trực tuyến' : 'Thực hiện tại showroom'}</small></td>
                <td class="so">${the.daDung[q.ma] || 0}</td><td class="so">${khong ? '—' : conLaiChu(the, q)}</td></tr>`;
            }).join('')}</tbody></table></div>
        </section>
        <section class="khoi-tk" aria-labelledby="td-ls">
          <div class="khoi-tk__dau"><div><p class="nhan-tren">Lịch sử dịch vụ</p><h2 id="td-ls">Đã thực hiện</h2></div></div>
          ${the.lichSuDichVu.length ? `<ol class="nhat-ky-bh">${the.lichSuDichVu.slice().reverse().map((l) => `<li><time>${VN.ngay(l.luc)}</time><div><strong>${VN.thoat(VN.TEN_DICH_VU[l.loai] || l.loai)}</strong><small>${VN.thoat(l.noiDung)}${l.maLich ? ' · ' + VN.thoat(l.maLich) : ''}</small></div></li>`).join('')}</ol>`
            : '<p class="chu-phu chu-nho">Chưa có dịch vụ nào được thực hiện cho thẻ này.</p>'}
        </section>
      </div>`;
  };

  khu.addEventListener('click', (e) => {
    const c = e.target.closest('[data-chon-the]');
    if (c) { tt.the = c.dataset.chonThe; moTab('the'); veDsThe(); return; }
    if (e.target.closest('[data-di-lich]')) { moTab('lich-hen'); return; }
    if (e.target.closest('[data-cuon-dat-lich]')) { e.preventDefault(); VN.$('#dl-the').value = tt.the; capNhatDichVu(); VN.$('#dat-lich').scrollIntoView({ behavior: 'smooth' }); }
  });

  /* ================= ĐƠN ĐANG GIAO: XÁC NHẬN ĐÃ NHẬN HÀNG NGAY TẠI ĐÂY ================= */
  /** Thẻ bảo hành chỉ có sau khi khách bấm "Đã nhận được hàng". Đơn đang giao được đưa lên đầu trang để khách
   *  xác nhận và thấy thẻ được kích hoạt ngay, không phải đi tìm trong Đơn hàng của tôi. */
  const veChoNhan = () => {
    const khung = VN.$('#bh-cho-nhan');
    const ds = (VN.donHang.cuaToi() || []).filter((d) => d.trangThai === 'Shipping');
    khung.hidden = !ds.length;
    khung.innerHTML = ds.length ? `<p class="nhan-tren">${VN.bt('xe-giao', 'bt--nho')} Đơn đang giao đến bạn</p>${ds.map((d) => {
      const sl = d.sanPham.reduce((a, x) => a + x.soLuong, 0); const tuDong = VN.ngayTuXacNhan(d);
      return `<div class="cho-nhan-hang__don">
        <div><strong>Đơn <a class="lien-ket" href="${VN.url('donHang', { ma: d.ma })}">${VN.thoat(d.ma)}</a></strong>
          <small>${VN.thoat(d.sanPham[0] ? d.sanPham[0].ten : '')}${d.sanPham.length > 1 ? ` và ${d.sanPham.length - 1} mẫu khác` : ''} · ${sl} sản phẩm</small>
          <small>Bấm khi đã nhận và kiểm tra hàng: mỗi sản phẩm được kích hoạt một thẻ bảo hành.${tuDong ? ` Chưa bấm thì hệ thống tự xác nhận vào ${VN.ngay(tuDong)}.` : ''}</small></div>
        <button type="button" class="nut nut--chinh nut--nho" data-nhan-hang="${VN.thoat(d.ma)}">${VN.bt('xac-nhan')} Đã nhận được hàng</button>
      </div>`;
    }).join('')}` : '';
  };
  VN.$('#bh-cho-nhan').addEventListener('click', async (e) => {
    const b = e.target.closest('[data-nhan-hang]'); if (!b) return;
    const ma = b.dataset.nhanHang; const don = VN.donHang.lay(ma);
    const sl = don ? don.sanPham.reduce((a, x) => a + x.soLuong, 0) : 0;
    const dongY = await VN.xacNhan({
      nhan: `Đơn ${ma}`, tieuDe: 'Bạn đã nhận đủ sản phẩm?', chuDongY: 'Đã nhận được hàng', chuHuy: 'Chưa nhận',
      noiDung: `Xác nhận khi bạn đã kiểm tra ${sl} sản phẩm còn nguyên niêm phong, đúng size và chữ khắc. Thẻ bảo hành điện tử của từng sản phẩm sẽ được kích hoạt ngay. Nếu có vấn đề, hãy mở đơn hàng và chọn “Phản ánh vấn đề”.`,
    });
    if (!dongY) return;
    b.disabled = true;
    try {
      await VN.donHang.xacNhanDaNhan(ma);
      const truoc = new Set(VN.baoHanh.tatCa().map((t) => t.ma));
      if (u) await VN.baoHanh.nap(); else await VN.baoHanh.napDon(ma);
      const moi = VN.baoHanh.tatCa().filter((t) => !truoc.has(t.ma));
      await VN.donHang.nap().catch(() => {});
      if (moi[0]) tt.the = moi[0].ma;
      veChoNhan(); veDsThe(); moTab('the');
      VN.thongBao({ tieuDe: `Đã kích hoạt ${moi.length || ''} thẻ bảo hành`.replace('  ', ' '), noiDung: `Đơn ${VN.thoat(ma)} đã chuyển sang Đã nhận. Bạn có thể đặt lịch hậu mãi ngay.`, loai: 'thanh-cong' });
      VN.$('#bh-ct-the').scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (loi) {
      b.disabled = false;
      VN.thongBao({ tieuDe: 'Không xác nhận được', noiDung: VN.thoat(loi.message), loai: 'loi' });
    }
  });

  /* ================= ĐẶT LỊCH ================= */
  const form = VN.$('#form-dat-lich');
  const capNhatDichVu = () => {
    const the = VN.baoHanh.lay(form.maBaoHanh.value); if (!the) return;
    const dangChon = (VN.$('input[name="loai"]:checked', form) || {}).value;
    VN.$('#dl-dich-vu').innerHTML = tt.ch.baoHanh.quyenLoi.filter((q) => q.datLich && VN.TEN_DICH_VU[q.ma]).map((q) => {
      const khong = q.chiChoNhan && !the.laNhan; const n = VN.baoHanh.conLai(the, tt.ch, q.ma);
      // Hết lượt miễn phí thì vẫn chọn được, dịch vụ chuyển sang tính phí (không để mất ô dịch vụ)
      const het = !khong && n <= 0; const phi = phiSauHetLuot(q.ma);
      return `<label class="the-chon${het ? ' the-chon--tinh-phi' : ''}"><input type="radio" name="loai" value="${q.ma}"${khong ? ' disabled' : ''}${q.ma === dangChon && !khong ? ' checked' : ''}>
        <span class="the-chon__noi-dung"><span class="the-chon__ten">${VN.thoat(VN.TEN_DICH_VU[q.ma])}</span>
        <span class="the-chon__gia">${khong ? 'Chỉ cho nhẫn' : het ? `${phi ? VN.tien(phi) : 'Tính phí'}/lần` : n === Infinity ? 'Miễn phí' : `Còn ${n} lượt miễn phí`}</span>
        <span class="the-chon__mo-ta">${het ? `Đã dùng hết ${the.hanMuc[q.ma]} lượt miễn phí. Vẫn đặt lịch được, phí thanh toán tại showroom khi hoàn tất.` : VN.thoat(q.ten)}</span></span></label>`;
    }).join('');
    capNhatSize();
  };
  const capNhatSize = () => {
    const the = VN.baoHanh.lay(form.maBaoHanh.value);
    const laResize = (VN.$('input[name="loai"]:checked', form) || {}).value === 'Resizing';
    VN.$('#dl-size-moi-truong').hidden = !laResize;
    if (laResize && the) {
      VN.dienChonSize(form.sizeMoi, null, 'Chọn size mới').then(() => { VN.$$('option', form.sizeMoi).forEach((o) => { if (Number(o.value) === Number(the.size)) o.disabled = true; }); });
      VN.$('#dl-size-hien-tai').textContent = the.size ? `Size hiện tại: ${the.size}. Showroom sẽ đo lại tay trước khi chỉnh.` : 'Chưa có thông tin size hiện tại.';
    }
  };
  const veFormThe = () => {
    VN.$('#dat-lich').hidden = false;
    const ds = VN.baoHanh.cuaToi();
    form.maBaoHanh.innerHTML = ds.map((t) => `<option value="${VN.thoat(t.ma)}"${t.ma === tt.the ? ' selected' : ''}>${VN.soTheDep(t.ma)} – ${VN.thoat(t.tenSP)}${t.size ? ' (size ' + t.size + ')' : ''}</option>`).join('');
    capNhatDichVu();
    khoiTaoNgay();
  };
  const veGio = () => {
    VN.$('#dl-gio').innerHTML = tt.ch.baoHanh.khungGio.map((g) => `<label><input class="an-chu" type="radio" name="khungGio" value="${g}"><span class="chip so-deu">${g}</span></label>`).join('');
  };
  /** Ngày hẹn: bất kỳ ngày nào sau ngày nhận hàng (thẻ chỉ có sau khi nhận hàng, nên sớm nhất là ngày mai).
   *  Không giới hạn trong 1 tháng; mốc xa nhất chỉ để lịch showroom không vượt 1 năm (giới hạn của database). */
  const khoiTaoNgay = () => {
    const the = VN.baoHanh.lay(form.maBaoHanh.value);
    const mai = new Date(); mai.setDate(mai.getDate() + 1);
    if (the && the.ngayKichHoat) { const sauNhan = new Date(the.ngayKichHoat); sauNhan.setDate(sauNhan.getDate() + 1); if (sauNhan > mai) mai.setTime(sauNhan.getTime()); }
    const cuoi = new Date(); cuoi.setDate(cuoi.getDate() + Math.max(1, (tt.ch.baoHanh.datTruocToiDaNgay || 365) - 1));
    form.ngayHen.min = VN.ngayIso(mai); form.ngayHen.max = VN.ngayIso(cuoi);
    VN.$('#dl-ngay-chu').textContent = the
      ? `Thẻ dùng được bất cứ lúc nào sau ngày nhận hàng (${VN.ngay(the.ngayKichHoat)}). Chọn ngày hẹn từ ${VN.ngay(mai)}.`
      : `Chọn ngày hẹn từ ${VN.ngay(mai)}.`;
  };
  form.addEventListener('change', (e) => {
    if (e.target === form.maBaoHanh) { tt.the = form.maBaoHanh.value; capNhatDichVu(); khoiTaoNgay(); }
    if (e.target.name === 'loai') { capNhatSize(); VN.$('#loi-dich-vu').textContent = ''; }
    if (e.target.name === 'khungGio') VN.$('#loi-gio').textContent = '';
    if (e.target === form.cuaHang) { const c = tt.cuaHang.find((x) => x.ma === form.cuaHang.value); VN.$('#dl-cua-hang-chu').textContent = c ? `${c.diaChi} · Mở cửa ${c.gioMoCua} · ${c.dienThoai}` : ''; }
    if (e.target === form.ngayHen && form.ngayHen.value) VN.$('#dl-ngay-chu').textContent = `${VN.thu(form.ngayHen.value + 'T00:00')} ${VN.ngay(form.ngayHen.value + 'T00:00')}`;
  });
  form.addEventListener('input', (e) => { if (e.target.closest('.truong.co-loi') && e.target.matches('.o-nhap,.o-chon,.o-van-ban')) VN.baoLoiTruong(e.target, ''); });

  // Xem trước ảnh tình trạng bằng FileReader (không tải lên máy chủ)
  VN.$('#dl-anh').addEventListener('change', (e) => {
    const xem = VN.$('#dl-xem-anh'); xem.innerHTML = '';
    const tep = Array.from(e.target.files || []);
    const loi = tep.length > 3 ? 'Chỉ chọn tối đa 3 ảnh.' : tep.some((f) => f.size > 5 * 1024 * 1024) ? 'Mỗi ảnh tối đa 5 MB.' : tep.some((f) => !f.type.startsWith('image/')) ? 'Chỉ nhận tệp ảnh.' : '';
    VN.baoLoiTruong(e.target, loi);
    if (loi) { e.target.value = ''; return; }
    tep.forEach((f) => { const r = new FileReader(); r.onload = () => { const img = document.createElement('img'); img.src = r.result; img.alt = f.name; xem.appendChild(img); }; r.readAsDataURL(f); });
  });
  form.addEventListener('reset', () => setTimeout(() => { VN.$('#dl-xem-anh').innerHTML = ''; veFormThe(); khoiTaoNgay(); VN.$('#dl-cua-hang-chu').textContent = ''; form.sdt.value = u ? u.sdt || '' : ''; }, 0));

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const the = VN.baoHanh.lay(form.maBaoHanh.value);
    const loai = (VN.$('input[name="loai"]:checked', form) || {}).value;
    const gio = (VN.$('input[name="khungGio"]:checked', form) || {}).value;
    const ok = [];
    VN.$('#loi-dich-vu').textContent = loai ? '' : 'Vui lòng chọn dịch vụ.'; ok.push(!!loai);
    if (loai === 'Resizing') { const v = form.sizeMoi.value; VN.baoLoiTruong(form.sizeMoi, v ? '' : 'Vui lòng chọn size mới.'); ok.push(!!v); }
    VN.baoLoiTruong(form.cuaHang, form.cuaHang.value ? '' : 'Vui lòng chọn showroom.'); ok.push(!!form.cuaHang.value);
    const ngay = form.ngayHen.value; const hopLe = ngay && ngay >= form.ngayHen.min && ngay <= form.ngayHen.max;
    VN.baoLoiTruong(form.ngayHen, hopLe ? '' : `Chọn ngày từ ${VN.ngay(form.ngayHen.min + 'T00:00')} đến ${VN.ngay(form.ngayHen.max + 'T00:00')}.`); ok.push(!!hopLe);
    VN.$('#loi-gio').textContent = gio ? '' : 'Vui lòng chọn khung giờ.'; ok.push(!!gio);
    VN.baoLoiTruong(form.sdt, VN.sdtHopLe(form.sdt.value) ? '' : 'Số điện thoại gồm 10 số, bắt đầu bằng 03, 05, 07, 08 hoặc 09.'); ok.push(VN.sdtHopLe(form.sdt.value));
    if (!ok.every(Boolean)) { const dau = VN.$('.co-loi, .loi-truong:not(:empty)', form); if (dau) dau.scrollIntoView({ behavior: 'smooth', block: 'center' }); return; }
    if (VN.baoHanh.conLai(the, tt.ch, loai) <= 0) {
      const phi = phiSauHetLuot(loai);
      const dongY = await VN.xacNhan({
        nhan: VN.TEN_DICH_VU[loai], tieuDe: 'Dịch vụ này đã hết lượt miễn phí', chuDongY: 'Đặt lịch có tính phí', chuHuy: 'Để sau',
        noiDung: `Thẻ đã dùng hết ${the.hanMuc[loai]} lượt miễn phí. Lần này tính phí <strong>${phi ? VN.tien(phi) : 'theo bảng giá'}</strong>, bạn thanh toán tại showroom khi dịch vụ hoàn tất.`,
      });
      if (!dongY) return;
    }
    // Mỗi thẻ chỉ có một lịch đang mở cho mỗi loại dịch vụ (database cũng chặn)
    if (VN.lichHen.tatCa().some((l) => l.maBaoHanh === the.ma && l.loai === loai && l.dangMo)) {
      VN.thongBao({ tieuDe: 'Thẻ đã có lịch hẹn cho dịch vụ này', noiDung: 'Hãy hủy lịch cũ hoặc đợi cửa hàng xử lý xong rồi đặt lịch mới.', loai: 'loi' }); return;
    }
    const ch = tt.cuaHang.find((x) => x.ma === form.cuaHang.value);
    const nut = VN.$('[type="submit"]', form); nut.disabled = true;
    try {
      const lich = await VN.lichHen.tao({
        maBaoHanh: the.ma, loai, ngay, gio, sizeMoi: loai === 'Resizing' ? Number(form.sizeMoi.value) : null, tenCuaHang: ch.ten,
        sdt: form.sdt.value.replace(/[\s.]/g, ''), soAnh: VN.$$('#dl-xem-anh img').length, ghiChu: form.ghiChu.value.trim(),
      });
      form.reset();
      VN.thongBao({ tieuDe: 'Đã gửi yêu cầu đặt lịch', noiDung: `Mã lịch ${VN.thoat(lich.ma)} · ${VN.thoat(VN.TEN_DICH_VU[loai])} ngày ${VN.ngay(ngay + 'T00:00')} lúc ${VN.thoat(gio)}. Trạng thái: Chờ xác nhận.`, loai: 'thanh-cong', thoiGian: 6000 });
      tt.moiTao = lich.ma;
      veDsLich(); veDsThe(); moTab('lich-hen');
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (loi) {
      VN.thongBao({ tieuDe: 'Chưa đặt được lịch', noiDung: VN.thoat(loi.message), loai: 'loi' });
    } finally { nut.disabled = false; }
  });

  /* ================= LỊCH HẸN ================= */
  const veDsLich = () => {
    const ds = VN.lichHen.cuaToi();
    const sapToi = ds.filter((l) => l.dangMo).sort((a, b) => (a.ngayHen + a.khungGio).localeCompare(b.ngayHen + b.khungGio));
    const khac = ds.filter((l) => !l.dangMo);
    VN.$$('[data-dem-lich]').forEach((x) => { x.textContent = sapToi.length || ''; });
    const the = (ma) => VN.baoHanh.lay(ma) || {};
    // Chỉ nói tới "lượt" với dịch vụ có giới hạn số lần (vd. đánh bóng & xi mới); dịch vụ trọn đời không nhắc lượt
    const ghiChuLuot = (l, tb) => {
      const han = tb.hanMuc ? tb.hanMuc[l.loai] : null;
      const coGioiHan = han !== null && han !== undefined;
      if (l.trangThai === 'Completed') {
        const phi = l.mienPhi === false ? ` · Đã hết lượt miễn phí, tính phí ${VN.tien(l.phi)}` : '';
        if (!coGioiHan) return ' · Dịch vụ trọn đời, không giới hạn số lần' + phi;
        return ` · Đã dùng 1 lượt, còn ${VN.baoHanh.conLai(tb, tt.ch, l.loai)}/${han} lượt${phi}`;
      }
      if (l.trangThai === 'Cancelled' && coGioiHan) return ' · Không bị trừ lượt';
      return '';
    };
    const htmlLich = (l) => {
      const t = VN.TRANG_THAI_LICH[l.trangThai]; const tb = the(l.maBaoHanh);
      const d = new Date(l.ngayHen + 'T00:00');
      const nut = [];
      if (l.dangMo) nut.push(`<button type="button" class="nut nut--chu nut-huy-lich" data-lich="huy" data-ma="${l.ma}">Hủy lịch</button>`);
      return `<article class="the-lich the-lich--${l.trangThai.toLowerCase()}${l.ma === tt.moiTao ? ' moi-tao' : ''}">
        <div class="the-lich__ngay"><span>${VN.thu(d)}</span><strong class="so-deu">${String(d.getDate()).padStart(2, '0')}</strong><span class="so-deu">Th${d.getMonth() + 1}/${d.getFullYear()}</span><em class="so-deu">${VN.thoat(l.khungGio)}</em></div>
        <div class="the-lich__chu">
          <div class="the-lich__dau"><h3 class="t-4">${VN.thoat(VN.TEN_DICH_VU[l.loai] || l.loai)}${l.sizeMoi ? ` → size ${l.sizeMoi}` : ''}</h3><span class="nhan ${t.lop}">${t.ten}</span></div>
          ${l.tenCuaHang ? `<p>${VN.bt('cua-hang', 'bt--nho')} ${VN.thoat(l.tenCuaHang)}</p>` : ''}
          <p>${VN.bt('khien', 'bt--nho')} ${VN.thoat(l.tenSP || tb.tenSP || '')} · <span class="so-deu">${VN.soTheDep(l.maBaoHanh)}</span></p>
          ${l.trangThai === 'Rescheduled' ? `<p class="hop-bao hop-bao--vang">${VN.bt('thong-tin')}<span>Cửa hàng đã đổi giờ hẹn (bạn chọn ${VN.ngayGio(l.gioKhachChon)}). Nếu giờ mới chưa phù hợp, bạn hủy lịch và đặt lại.</span></p>` : ''}
          ${l.ghiChu ? `<p class="chu-phu">“${VN.thoat(l.ghiChu)}”</p>` : ''}
          ${l.ketQua ? `<p class="chu-phu">Kết quả: ${VN.thoat(l.ketQua)}</p>` : ''}
          <p class="chu-rat-nho chu-phu">Mã lịch ${VN.thoat(l.ma)} · Gửi ${VN.ngayGio(l.taoLuc)}${ghiChuLuot(l, tb)}</p>
          ${nut.length ? `<div class="the-lich__nut">${nut.join('')}</div>` : ''}
        </div></article>`;
    };
    VN.$('#bh-ds-lich').innerHTML = !ds.length
      ? `<div class="trong-rong khoi-tk"><div class="trong-rong__bieu-tuong">${VN.bt('lich')}</div><h2 class="t-3">Chưa có lịch hẹn</h2><p>Chọn một thẻ bảo hành và đặt lịch làm sạch, đánh bóng hoặc chỉnh size.</p><button type="button" class="nut nut--chinh nut--nho" data-tab-di="the">Đặt lịch ngay</button></div>`
      : `${sapToi.length ? `<h2 class="nhom-lich">Sắp tới <span>${sapToi.length}</span></h2>${sapToi.map(htmlLich).join('')}` : ''}${khac.length ? `<h2 class="nhom-lich">Lịch sử dịch vụ <span>${khac.length}</span></h2>${khac.map(htmlLich).join('')}` : ''}`;
  };
  VN.$('#bh-ds-lich').addEventListener('click', async (e) => {
    if (e.target.closest('[data-tab-di]')) { moTab('the'); return; }
    const b = e.target.closest('[data-lich]'); if (!b) return;
    const l = VN.lichHen.tatCa().find((x) => x.ma === b.dataset.ma);
    if (b.dataset.lich === 'huy' && l) {
      const han = (VN.baoHanh.lay(l.maBaoHanh) || { hanMuc: {} }).hanMuc[l.loai]; const coGioiHan = han !== null && han !== undefined;
      const ok = await VN.xacNhan({ nhan: 'Lịch hẹn ' + l.ma, tieuDe: 'Hủy lịch hẹn này?', noiDung: `${coGioiHan ? 'Lượt dịch vụ miễn phí được giữ nguyên. ' : ''}Bạn có thể đặt lịch khác bất cứ lúc nào.`, chuDongY: 'Hủy lịch', chuHuy: 'Giữ lịch', nguy: true });
      if (!ok) return;
      try {
        await VN.lichHen.huy(l.ma);
        VN.thongBao({ tieuDe: 'Đã hủy lịch hẹn', noiDung: coGioiHan ? 'Lượt miễn phí không bị trừ.' : '' });
      } catch (loi) { VN.thongBao({ tieuDe: 'Chưa hủy được lịch hẹn', noiDung: VN.thoat(loi.message), loai: 'loi' }); }
    }
    veDsLich(); veDsThe();
  });

  /* ================= GIẤY CHỨNG NHẬN CỦA THẺ ================= */
  khu.addEventListener('click', async (e) => {
    const nut = e.target.closest('[data-xem-gcn]'); if (!nut) return;
    const the = VN.baoHanh.lay(nut.dataset.xemGcn); if (!the) return;
    const { sp } = await VN.duLieu.coBan();
    // Mẫu đã ngừng kinh doanh vẫn có giấy chứng nhận: dựng lại từ thông tin lưu trên thẻ
    const s = sp.theoMa[the.maSP] || { ma: the.maSP, ten: the.tenSP, anh: [the.anh], chatLieu: the.chatLieu, tenChatLieu: (tt.ch.tenChatLieu || {})[the.chatLieu] || the.chatLieu, mau: the.mau ? [the.mau] : [] };
    VN.moGiayChungNhan(s, tt.ch, { so: VN.soChungNhan(the.ma), ngay: the.ngayKichHoat, mau: the.mau, size: the.size, khacChu: the.khacChu });
  });

  /* ================= TRA CỨU ================= */
  VN.$('#form-tra-cuu').addEventListener('submit', async (e) => {
    e.preventDefault();
    const ma = e.target.ma.value.replace(/\s/g, '').toUpperCase();
    const kq = VN.$('#kq-tra-cuu');
    if (!/^VNW\d{11}-\d{1,3}$/.test(ma)) { kq.innerHTML = `<p class="hop-bao hop-bao--do">${VN.bt('canh-bao')}<span>Mã thẻ gồm “VNW”, 11 chữ số, dấu gạch ngang và số thứ tự, ví dụ VNW 2608 0001234-1.</span></p>`; return; }
    const the = VN.baoHanh.lay(ma);                 // thẻ của chính khách (hoặc của đơn đã mở trên trình duyệt này)
    if (the) {
      kq.innerHTML = `<div class="kq-tra-cuu">${VN.htmlTheBaoHanh(the, tt.ch, chuTheCua(the))}
        <div><p class="nhan nhan--ngoc">Thẻ hợp lệ · ${VN.thoat(the.hieuLuc)}</p><h3 class="t-3">${VN.thoat(the.tenSP)}</h3>
        <p class="chu-phu">Mã ${VN.thoat(the.maSP)} · Kích hoạt ${VN.ngay(the.ngayKichHoat)}</p>
        ${u ? `<button type="button" class="nut nut--chinh nut--nho" data-chon-the="${VN.thoat(the.ma)}">Xem chi tiết &amp; đặt lịch</button>`
          : `<div class="hang hang--quan"><button type="button" class="nut nut--chinh nut--nho" data-chon-the="${VN.thoat(the.ma)}">Xem chi tiết thẻ</button><button type="button" class="nut nut--vien nut--nho" data-xem-gcn="${VN.thoat(the.ma)}">${VN.bt('chung-nhan')} Giấy chứng nhận</button></div>`}</div></div>`;
      return;
    }
    // Thẻ của người khác: máy chủ chỉ cho biết thẻ có thật và là sản phẩm nào, không cho biết chủ thẻ
    try {
      const r = await VN.baoHanh.traCuu(ma);
      kq.innerHTML = `<div class="kq-tra-cuu"><div><p class="nhan ${r.Status === 'Active' ? 'nhan--ngoc' : 'nhan--do'}">${r.Status === 'Active' ? `Thẻ hợp lệ · ${VN.thoat(VN.hieuLucThe(r.IssueDate).hieuLuc)}` : 'Thẻ đã hết hiệu lực'}</p><h3 class="t-3">${VN.thoat(r.ProductName)}</h3>
        <p class="chu-phu">Mã ${VN.thoat(r.ProductSKU)} · Kích hoạt ${VN.ngay(r.IssueDate)}</p>
        <p class="chu-rat-nho chu-phu">Đăng nhập bằng tài khoản chủ thẻ (hoặc tạo tài khoản bằng số điện thoại đã đặt hàng) để xem lịch sử và đặt lịch.</p></div></div>`;
    } catch (loi) {
      kq.innerHTML = loi.trangThai === 404
        ? `<p class="hop-bao hop-bao--cam">${VN.bt('thong-tin')}<span>Không tìm thấy thẻ <strong>${VN.soTheDep(ma)}</strong>. Thẻ chỉ có sau khi đơn hàng được xác nhận đã nhận.</span></p>`
        : `<p class="hop-bao hop-bao--do">${VN.bt('canh-bao')}<span>${VN.thoat(loi.message)}</span></p>`;
    }
  });

  /* ================= KHỞI TẠO ================= */
  const batDau = async () => {
    const [ch, cuaHang] = await Promise.all([VN.duLieu.cauHinh(), VN.duLieu.cuaHang()]);
    tt.ch = ch; tt.cuaHang = cuaHang;
    await VN.baoHanh.nap().catch((loi) => VN.thongBao({ tieuDe: 'Chưa tải được thẻ bảo hành', noiDung: VN.thoat(loi.message), loai: 'loi' }));
    await VN.donHang.nap().catch(() => {});        // đơn đang giao: nút "Đã nhận được hàng" ngay trên trang này
    veChoNhan();
    form.cuaHang.innerHTML = '<option value="">Chọn showroom</option>' + cuaHang.map((c) => `<option value="${VN.thoat(c.ma)}">${VN.thoat(c.ten)} – ${VN.thoat(c.khuVuc)}</option>`).join('');
    veGio(); khoiTaoNgay();
    if (u) form.sdt.value = u.sdt || '';
    const traMa = VN.thamSo('ma');
    if (!u) {
      VN.$('.menu-tk').hidden = true; khu.classList.add('khu-tk--khach');
      VN.$('#bh-can-dn').hidden = false; VN.$('#bh-nut-dn').href = VN.url('taiKhoan', { tiep: location.pathname + location.search });
      VN.$('#tab-lich').hidden = true;
      tt.the = VN.thamSo('the') || null;
      veDsThe();
      moTab(VN.thamSo('tab') === 'tra-cuu' ? 'tra-cuu' : 'the', false);
    } else {
      tt.the = VN.thamSo('the') || null;
      veDsThe(); veDsLich();
      moTab(VN.thamSo('tab') || 'the', false);
      if (VN.thamSo('the')) setTimeout(() => VN.$('#bh-ct-the').scrollIntoView({ behavior: 'smooth' }), 200);
    }
    if (traMa) { VN.$('#o-tra-cuu').value = traMa; moTab('tra-cuu', false); VN.$('#form-tra-cuu').requestSubmit(); }
  };
  VN.sanSang.then(() => { u = VN.taiKhoan.hienTai(); return batDau(); })
    .catch((loi) => VN.thongBao({ tieuDe: 'Chưa tải được trang bảo hành', noiDung: VN.thoat(loi.message), loai: 'loi' }));
})();
