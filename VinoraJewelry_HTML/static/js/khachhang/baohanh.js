/* =====================================================================
   5.2.8 CỔNG BẢO HÀNH ĐIỆN TỬ & ĐẶT LỊCH HẬU MÃI (FR15, FR16, FR17)
   - Thẻ bảo hành dạng thẻ ATM, quyền lợi & số lượt còn lại, lịch sử dịch vụ
   - Đặt lịch: thẻ hợp lệ, dịch vụ (làm sạch / đánh bóng & xi mới / chỉnh size), showroom đọc từ XML (AJAX),
     ngày trong 30 ngày tới, khung giờ, ảnh tình trạng (xem trước bằng FileReader)
   - Lịch hẹn: Chờ xác nhận -> Đã xác nhận -> Hoàn tất (chỉ lúc này mới trừ lượt) / Đã hủy (không mất lượt)
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const khu = VN.$('#khu-bh');
  if (!khu) return;
  const u = VN.taiKhoan.hienTai();
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
  const conLaiChu = (the, q) => { const n = VN.baoHanh.conLai(the, tt.ch, q.ma); return n === Infinity ? q.hienThi : `${n}/${q.luot} lượt`; };
  const veDsThe = () => {
    const ds = VN.baoHanh.cuaToi();
    VN.$$('[data-dem-the]').forEach((x) => { x.textContent = ds.length || ''; });
    const khung = VN.$('#bh-ds-the');
    if (!ds.length) {
      khung.innerHTML = `<div class="trong-rong khoi-tk"><div class="trong-rong__bieu-tuong">${VN.bt('khien')}</div><h2 class="t-3">Bạn chưa có thẻ bảo hành nào</h2>
        <p>Thẻ được kích hoạt tự động cho từng sản phẩm khi bạn bấm “Đã nhận được hàng” trong mục Đơn hàng của tôi.</p><a class="nut nut--chinh nut--nho" href="${VN.url('donHang')}">Đơn hàng của tôi</a></div>`;
      VN.$('#bh-ct-the').innerHTML = ''; VN.$('#dat-lich').hidden = true; return;
    }
    if (!tt.the || !ds.some((t) => t.ma === tt.the)) tt.the = ds[0].ma;
    khung.innerHTML = `<p class="nhan-truong">${ds.length} thẻ của bạn</p><div class="ds-the-nho__luoi">${ds.map((t) => `
      <button type="button" class="the-nho${t.ma === tt.the ? ' dang-chon' : ''}" data-chon-the="${VN.thoat(t.ma)}" aria-pressed="${t.ma === tt.the}">
        <span class="the-nho__anh"><img src="${VN.anh(t.anh)}" alt="" width="56" height="56" loading="lazy"></span>
        <span class="the-nho__chu"><strong>${VN.thoat(t.tenSP)}</strong><small class="so-deu">${VN.soTheDep(t.ma)}</small><small>Kích hoạt ${VN.ngay(t.ngayKichHoat)}${t.size ? ' · Size ' + t.size : ''}</small></span>
      </button>`).join('')}</div>`;
    veCtThe();
    veFormThe();
  };

  const veCtThe = () => {
    const the = VN.baoHanh.lay(tt.the); if (!the) return;
    const ql = tt.ch.baoHanh.quyenLoi;
    const lich = VN.lichHen.tatCa().filter((l) => l.maBaoHanh === the.ma && ['Pending', 'Confirmed'].includes(l.trangThai));
    VN.$('#bh-ct-the').innerHTML = `
      <section class="khoi-tk ct-the__khung" aria-labelledby="td-ct-the">
        <div class="ct-the__the">${VN.htmlTheBaoHanh(the, tt.ch, u ? u.hoTen : '')}<p class="chu-rat-nho chu-phu">Bấm vào thẻ để lật mặt sau</p></div>
        <div class="ct-the__chu">
          <p class="nhan-tren">Chi tiết thẻ</p>
          <h2 class="t-3" id="td-ct-the">${VN.thoat(the.tenSP)}</h2>
          <dl class="tt-the">
            <div><dt>Mã thẻ</dt><dd class="so-deu">${VN.soTheDep(the.ma)}</dd></div>
            <div><dt>Sản phẩm</dt><dd><a class="lien-ket" href="${VN.urlSanPham(the.maSP)}">${VN.thoat(the.maSP)}</a> · ${VN.thoat(the.chatLieu)}${the.mau ? ' · ' + VN.thoat(the.mau) : ''}${the.size ? ' · Size ' + the.size : ''}</dd></div>
            ${the.khacChu ? `<div><dt>Chữ khắc</dt><dd>“${VN.thoat(the.khacChu)}”</dd></div>` : ''}
            <div><dt>Đơn hàng</dt><dd><a class="lien-ket" href="${VN.url('donHang', { ma: the.donHang })}">${VN.thoat(the.donHang)}</a></dd></div>
            <div><dt>Kích hoạt</dt><dd>${VN.ngay(the.ngayKichHoat)} · Hiệu lực ${VN.thoat(the.hieuLuc)}</dd></div>
          </dl>
          ${lich.length ? `<p class="hop-bao hop-bao--ngoc">${VN.bt('lich')}<span>Có ${lich.length} lịch hẹn sắp tới cho thẻ này – <button type="button" class="lien-ket" data-di-lich>xem lịch hẹn</button>.</span></p>` : ''}
          <a class="nut nut--chinh nut--nho" href="#dat-lich" data-cuon-dat-lich>${VN.bt('lich')} Đặt lịch cho thẻ này</a>
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

  /* ================= ĐẶT LỊCH ================= */
  const form = VN.$('#form-dat-lich');
  const capNhatDichVu = () => {
    const the = VN.baoHanh.lay(form.maBaoHanh.value); if (!the) return;
    const dangChon = (VN.$('input[name="loai"]:checked', form) || {}).value;
    VN.$('#dl-dich-vu').innerHTML = tt.ch.baoHanh.quyenLoi.filter((q) => q.datLich && VN.TEN_DICH_VU[q.ma]).map((q) => {
      const khong = q.chiChoNhan && !the.laNhan; const n = VN.baoHanh.conLai(the, tt.ch, q.ma);
      const het = !khong && n <= 0;
      return `<label class="the-chon"><input type="radio" name="loai" value="${q.ma}"${khong || het ? ' disabled' : ''}${q.ma === dangChon && !khong && !het ? ' checked' : ''}>
        <span class="the-chon__noi-dung"><span class="the-chon__ten">${VN.thoat(VN.TEN_DICH_VU[q.ma])}</span>
        <span class="the-chon__gia">${khong ? 'Chỉ cho nhẫn' : het ? 'Hết lượt' : n === Infinity ? 'Miễn phí' : `Còn ${n} lượt`}</span>
        <span class="the-chon__mo-ta">${VN.thoat(q.ten)}</span></span></label>`;
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
  };
  const veGio = () => {
    VN.$('#dl-gio').innerHTML = tt.ch.baoHanh.khungGio.map((g) => `<label><input class="an-chu" type="radio" name="khungGio" value="${g}"><span class="chip so-deu">${g}</span></label>`).join('');
  };
  const khoiTaoNgay = () => {
    const mai = new Date(); mai.setDate(mai.getDate() + 1);
    const cuoi = new Date(); cuoi.setDate(cuoi.getDate() + tt.ch.baoHanh.datTruocToiDaNgay);
    form.ngayHen.min = VN.ngayIso(mai); form.ngayHen.max = VN.ngayIso(cuoi);
    VN.$('#dl-ngay-chu').textContent = `Từ ngày mai đến ${VN.ngay(cuoi)} (đặt trước tối đa ${tt.ch.baoHanh.datTruocToiDaNgay} ngày).`;
  };
  form.addEventListener('change', (e) => {
    if (e.target === form.maBaoHanh) { tt.the = form.maBaoHanh.value; capNhatDichVu(); }
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

  form.addEventListener('submit', (e) => {
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
    if (VN.baoHanh.conLai(the, tt.ch, loai) <= 0) { VN.thongBao({ tieuDe: 'Đã hết lượt miễn phí cho dịch vụ này', loai: 'loi' }); return; }
    const trung = VN.lichHen.cuaToi().some((l) => l.maBaoHanh === the.ma && l.ngayHen === ngay && l.khungGio === gio && ['Pending', 'Confirmed'].includes(l.trangThai));
    if (trung) { VN.thongBao({ tieuDe: 'Bạn đã có lịch hẹn vào khung giờ này', noiDung: 'Vui lòng chọn ngày hoặc khung giờ khác.', loai: 'loi' }); return; }
    const ch = tt.cuaHang.find((x) => x.ma === form.cuaHang.value);
    const lich = VN.lichHen.tao({
      maBaoHanh: the.ma, loai, ngayHen: ngay, khungGio: gio, cuaHang: ch.ma, tenCuaHang: ch.ten, sdt: form.sdt.value.replace(/[\s.]/g, ''),
      ghiChu: form.ghiChu.value.trim(), sizeMoi: loai === 'Resizing' ? Number(form.sizeMoi.value) : null, soAnh: VN.$$('#dl-xem-anh img').length,
    });
    form.reset();
    VN.thongBao({ tieuDe: 'Đã gửi yêu cầu đặt lịch', noiDung: `Mã lịch ${lich.ma} · ${VN.TEN_DICH_VU[loai]} ngày ${VN.ngay(ngay + 'T00:00')} lúc ${gio}. Trạng thái: Chờ xác nhận.`, loai: 'thanh-cong', thoiGian: 6000 });
    tt.moiTao = lich.ma;
    veDsLich(); moTab('lich-hen');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });

  /* ================= LỊCH HẸN ================= */
  const veDsLich = () => {
    const ds = VN.lichHen.cuaToi();
    const sapToi = ds.filter((l) => ['Pending', 'Confirmed'].includes(l.trangThai)).sort((a, b) => (a.ngayHen + a.khungGio).localeCompare(b.ngayHen + b.khungGio));
    const khac = ds.filter((l) => !['Pending', 'Confirmed'].includes(l.trangThai));
    VN.$$('[data-dem-lich]').forEach((x) => { x.textContent = sapToi.length || ''; });
    const the = (ma) => VN.baoHanh.lay(ma) || {};
    const htmlLich = (l) => {
      const t = VN.TRANG_THAI_LICH[l.trangThai]; const tb = the(l.maBaoHanh);
      const d = new Date(l.ngayHen + 'T00:00');
      const nut = [];
      if (l.trangThai === 'Pending') nut.push(`<button type="button" class="nut nut--chu nut-mo-phong" data-lich="xac-nhan" data-ma="${l.ma}">Mô phỏng: showroom xác nhận</button>`);
      if (l.trangThai === 'Confirmed') nut.push(`<button type="button" class="nut nut--chu nut-mo-phong" data-lich="hoan-tat" data-ma="${l.ma}">Mô phỏng: showroom hoàn tất dịch vụ</button>`);
      if (['Pending', 'Confirmed'].includes(l.trangThai)) nut.push(`<button type="button" class="nut nut--chu nut-huy-lich" data-lich="huy" data-ma="${l.ma}">Hủy lịch</button>`);
      return `<article class="the-lich the-lich--${l.trangThai.toLowerCase()}${l.ma === tt.moiTao ? ' moi-tao' : ''}">
        <div class="the-lich__ngay"><span>${VN.thu(d)}</span><strong class="so-deu">${String(d.getDate()).padStart(2, '0')}</strong><span class="so-deu">Th${d.getMonth() + 1}/${d.getFullYear()}</span><em class="so-deu">${VN.thoat(l.khungGio)}</em></div>
        <div class="the-lich__chu">
          <div class="the-lich__dau"><h3 class="t-4">${VN.thoat(VN.TEN_DICH_VU[l.loai] || l.loai)}${l.sizeMoi ? ` → size ${l.sizeMoi}` : ''}</h3><span class="nhan ${t.lop}">${t.ten}</span></div>
          <p>${VN.bt('cua-hang', 'bt--nho')} ${VN.thoat(l.tenCuaHang)}</p>
          <p>${VN.bt('khien', 'bt--nho')} ${VN.thoat(tb.tenSP || '')} · <span class="so-deu">${VN.soTheDep(l.maBaoHanh)}</span></p>
          ${l.ghiChu ? `<p class="chu-phu">“${VN.thoat(l.ghiChu)}”</p>` : ''}
          <p class="chu-rat-nho chu-phu">Mã lịch ${VN.thoat(l.ma)} · Gửi ${VN.ngayGio(l.taoLuc)}${l.trangThai === 'Completed' ? ' · Đã trừ 1 lượt (nếu có giới hạn)' : l.trangThai === 'Cancelled' ? ' · Không bị trừ lượt' : ''}</p>
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
    if (b.dataset.lich === 'huy') {
      const ok = await VN.xacNhan({ nhan: 'Lịch hẹn ' + l.ma, tieuDe: 'Hủy lịch hẹn này?', noiDung: 'Lượt dịch vụ miễn phí được giữ nguyên, bạn có thể đặt lịch khác bất cứ lúc nào.', chuDongY: 'Hủy lịch', chuHuy: 'Giữ lịch', nguy: true });
      if (!ok) return;
      VN.lichHen.capNhat(l.ma, 'Cancelled', 'Khách hàng hủy lịch hẹn.', 'Khách hàng');
      VN.thongBao({ tieuDe: 'Đã hủy lịch hẹn', noiDung: 'Lượt miễn phí không bị trừ.' });
    } else if (b.dataset.lich === 'xac-nhan') {
      VN.lichHen.capNhat(l.ma, 'Confirmed', `Showroom ${l.tenCuaHang} xác nhận lịch hẹn.`, 'Showroom (mô phỏng)');
      VN.thongBao({ tieuDe: 'Showroom đã xác nhận lịch', loai: 'thanh-cong' });
    } else if (b.dataset.lich === 'hoan-tat') {
      VN.lichHen.capNhat(l.ma, 'Completed', `Hoàn tất ${VN.TEN_DICH_VU[l.loai]} tại ${l.tenCuaHang}.`, 'Showroom (mô phỏng)');
      if (l.loai === 'Resizing' && l.sizeMoi) {   // cập nhật size mới cho thẻ sau khi chỉnh size
        const ds = VN.baoHanh.tatCa(); const t = ds.find((x) => x.ma === l.maBaoHanh); if (t) { t.size = l.sizeMoi; VN.baoHanh.luuTatCa(ds); }
      }
      VN.thongBao({ tieuDe: 'Dịch vụ đã hoàn tất', noiDung: 'Số lượt còn lại trên thẻ đã được cập nhật.', loai: 'thanh-cong' });
    }
    veDsLich(); veDsThe();
  });

  /* ================= TRA CỨU ================= */
  VN.$('#form-tra-cuu').addEventListener('submit', (e) => {
    e.preventDefault();
    const ma = e.target.ma.value.replace(/\s/g, '').toUpperCase();
    const kq = VN.$('#kq-tra-cuu');
    if (!/^VNRA\d{12}$/.test(ma)) { kq.innerHTML = `<p class="hop-bao hop-bao--do">${VN.bt('canh-bao')}<span>Mã thẻ gồm “VNRA” và 12 chữ số, ví dụ VNRA 2608 1234 5678.</span></p>`; return; }
    const the = VN.baoHanh.lay(ma);
    if (!the) { kq.innerHTML = `<p class="hop-bao hop-bao--cam">${VN.bt('thong-tin')}<span>Không tìm thấy thẻ <strong>${VN.soTheDep(ma)}</strong>. Thẻ chỉ có sau khi đơn hàng được xác nhận đã nhận.</span></p>`; return; }
    const cuaToi = u && the.khachHang === u.id;
    kq.innerHTML = `<div class="kq-tra-cuu">${VN.htmlTheBaoHanh(the, tt.ch, cuaToi ? u.hoTen : '***')}
      <div><p class="nhan nhan--ngoc">Thẻ hợp lệ · ${VN.thoat(the.hieuLuc)}</p><h3 class="t-3">${VN.thoat(the.tenSP)}</h3>
      <p class="chu-phu">Mã ${VN.thoat(the.maSP)} · Kích hoạt ${VN.ngay(the.ngayKichHoat)}</p>
      ${cuaToi ? `<button type="button" class="nut nut--chinh nut--nho" data-chon-the="${VN.thoat(the.ma)}">Xem chi tiết &amp; đặt lịch</button>` : '<p class="chu-rat-nho chu-phu">Đăng nhập bằng tài khoản chủ thẻ để xem lịch sử và đặt lịch.</p>'}</div></div>`;
  });

  /* ================= KHỞI TẠO ================= */
  const batDau = async () => {
    const [ch, cuaHang] = await Promise.all([VN.duLieu.cauHinh(), VN.duLieu.cuaHang()]);
    tt.ch = ch; tt.cuaHang = cuaHang;
    form.cuaHang.innerHTML = '<option value="">Chọn showroom</option>' + cuaHang.map((c) => `<option value="${VN.thoat(c.ma)}">${VN.thoat(c.ten)} – ${VN.thoat(c.khuVuc)}</option>`).join('');
    veGio(); khoiTaoNgay();
    if (u) form.sdt.value = u.sdt || '';
    const traMa = VN.thamSo('ma');
    if (!u) {
      VN.$('.menu-tk').hidden = true; khu.classList.add('khu-tk--khach');
      VN.$('#bh-can-dn').hidden = false; VN.$('#bh-nut-dn').href = VN.url('taiKhoan', { tiep: location.pathname + location.search });
      VN.$('#tab-lich').hidden = true;
      moTab(VN.thamSo('tab') === 'tra-cuu' ? 'tra-cuu' : 'the', false);
    } else {
      tt.the = VN.thamSo('the') || null;
      veDsThe(); veDsLich();
      moTab(VN.thamSo('tab') || 'the', false);
      if (VN.thamSo('the')) setTimeout(() => VN.$('#bh-ct-the').scrollIntoView({ behavior: 'smooth' }), 200);
    }
    if (traMa) { VN.$('#o-tra-cuu').value = traMa; moTab('tra-cuu', false); VN.$('#form-tra-cuu').requestSubmit(); }
  };
  if (u && u.email === VN.DEMO.email) VN.demo.damBaoDuLieu(u.id).then(batDau); else batDau();
})();
