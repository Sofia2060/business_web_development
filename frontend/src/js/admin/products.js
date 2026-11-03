/* =====================================================================
   QUẢN TRỊ – SẢN PHẨM (nối API /api/admin/products)
   Danh sách có cả sản phẩm đã ẩn và ngừng bán. Sửa giá bán, giá trước giảm (để hiện giảm giá) và trạng thái,
   lưu thẳng vào database. Cửa hàng giữ danh mục 5 phút trong trình duyệt nên thấy giá mới sau thời gian đó (hoặc khi mở tab mới).
   Sản phẩm giá theo giá vàng chỉ báo giá, không có giá bán để sửa: chỉ đổi được trạng thái.
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-sp-bang')) return;
  const tt = { tatCa: [], dm: {}, locDm: '', locTt: '', tim: '', trang: 1 };
  const TEN_TT = { Active: ['Đang bán', 'nhan--ngoc'], Hidden: ['Đã ẩn', 'nhan--cam'], Discontinued: ['Ngừng bán', 'nhan--do'] };
  const ten = (s) => (tt.dm[s.danhMuc] || {}).ten || '';

  /** Một sản phẩm của API -> sản phẩm dạng trang dùng */
  const sanPhamTuApi = (p) => {
    const giaCu = p.OriginalPrice && p.Price && p.OriginalPrice > p.Price ? p.OriginalPrice : null;
    return {
      ma: p.SKU, ten: p.ProductName, danhMuc: p.CategoryID, chatLieu: p.Material, coDinh: p.PricingMethod === 'Fixed', baoGia: !!p.IsQuoteOnly,
      gia: p.Price, giaCu, giam: giaCu ? Math.round((giaCu - p.Price) * 100 / giaCu) : null, trangThai: p.Status, anh: p.ImageUrl, daBan: p.SoldQuantity,
    };
  };
  const dangBan = (s) => s.trangThai === 'Active';

  const ve = () => {
    const ds = tt.tatCa;
    VN.$('#qt-sp-so').innerHTML = [
      ['', 'Tổng mẫu', ds.length, `${Object.keys(tt.dm).length} danh mục`],
      ['ngoc', 'Đang bán', ds.filter(dangBan).length, `${ds.filter((s) => dangBan(s) && s.baoGia).length} mẫu chỉ báo giá`],
      ['do', 'Ẩn hoặc ngừng bán', ds.filter((s) => !dangBan(s)).length, 'Không hiện ở cửa hàng'],
      ['cam', 'Đang giảm giá', ds.filter((s) => dangBan(s) && s.giaCu).length, 'Có giá trước giảm'],
    ].map(([lop, t, so, phu]) => `<div class="qt-o-so${lop ? ' qt-o-so--' + lop : ''}"><span>${t}</span><strong>${so}</strong><small>${phu}</small></div>`).join('');
    const tu = VN.khongDau(tt.tim);
    const loc = ds.filter((s) => (!tt.locDm || String(s.danhMuc) === tt.locDm)
      && (!tt.locTt || (tt.locTt === 'ban' && dangBan(s)) || (tt.locTt === 'ngung' && !dangBan(s)) || (tt.locTt === 'giam' && s.giaCu) || (tt.locTt === 'cong' && s.baoGia))
      && (!tu || VN.khongDau(s.ma + ' ' + s.ten).includes(tu)));
    const p = qt.phanTrang(loc, tt.trang, 20); tt.trang = p.trang;
    VN.$('#qt-sp-bang').innerHTML = loc.length ? `<thead><tr><th>Sản phẩm</th><th>Danh mục</th><th>Chất liệu</th><th class="so">Giá bán</th><th class="so">Giá gốc</th><th class="so">Đã bán</th><th>Trạng thái</th><th></th></tr></thead><tbody>${p.muc.map((s) => `<tr>
      <td><span class="qt-sp-nho"><img src="${VN.anh(s.anh)}" alt="" loading="lazy"><span>${VN.thoat(s.ten)}<small>${VN.thoat(s.ma)}</small></span></span></td>
      <td>${VN.thoat(ten(s))}</td><td>${VN.thoat(s.chatLieu)}</td>
      <td class="so">${s.baoGia ? '<small>Chỉ báo giá</small>—' : VN.tien(s.gia)}</td>
      <td class="so">${s.giaCu ? `<del>${VN.tien(s.giaCu)}</del><small>−${s.giam}%</small>` : '—'}</td>
      <td class="so">${s.daBan}</td>
      <td><span class="nhan ${TEN_TT[s.trangThai][1]}">${TEN_TT[s.trangThai][0]}</span></td>
      <td><div class="qt-hanh-dong"><button type="button" class="nut nut--vien nut--rat-nho" data-sua="${VN.thoat(s.ma)}">Sửa</button>${dangBan(s) ? `<a class="nut nut--chu" href="${VN.urlSanPham(s.ma)}" target="_blank" rel="noopener">Xem</a>` : ''}</div></td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td>${qt.trong('Không có sản phẩm phù hợp.')}</td></tr></tbody>`;
    VN.$('#qt-sp-trang').innerHTML = loc.length ? qt.htmlPhanTrang(p) : '';
  };

  const moSua = (ma) => {
    const s = tt.tatCa.find((x) => x.ma === ma); if (!s) return;
    const truongGia = s.coDinh ? `<div class="luoi-truong">
          <div class="truong"><label class="nhan-truong" for="qt-sp-gia">Giá bán (₫)</label>
            <input class="o-nhap so-deu" id="qt-sp-gia" name="gia" inputmode="numeric" value="${s.gia}"></div>
          <div class="truong"><label class="nhan-truong" for="qt-sp-gia-cu">Giá trước giảm (₫)</label>
            <input class="o-nhap so-deu" id="qt-sp-gia-cu" name="giaCu" inputmode="numeric" value="${s.giaCu || ''}" placeholder="Để trống nếu không giảm giá"><p class="goi-y-truong">Lớn hơn giá bán thì cửa hàng hiện nhãn giảm giá.</p></div>
        </div>` : '<p class="chu-nho chu-phu">Sản phẩm giá theo giá vàng chỉ báo giá, không có giá bán để sửa.</p>';
    qt.moChiTiet(s.ten, `<div class="qt-ct__muc"><div class="qt-sp-nho"><img src="${VN.anh(s.anh)}" alt=""><span>${VN.thoat(s.ten)}<small>${VN.thoat(s.ma)} · ${VN.thoat(ten(s))} · ${VN.thoat(s.chatLieu)}</small></span></div></div>
      <form class="qt-form qt-ct__muc" data-form-sp="${VN.thoat(ma)}" novalidate>
        ${truongGia}
        <div class="truong"><label class="nhan-truong" for="qt-sp-tt-sua">Trạng thái</label>
          <select class="o-chon" id="qt-sp-tt-sua" name="trangThai">${Object.entries(TEN_TT).map(([k, [t]]) => `<option value="${k}"${k === s.trangThai ? ' selected' : ''}>${t}</option>`).join('')}</select>
          <p class="goi-y-truong">Đã ẩn hoặc ngừng bán: sản phẩm biến mất khỏi cửa hàng, tìm kiếm và giỏ hàng.</p></div>
        <div class="hang hang--quan"><button class="nut nut--chinh nut--nho" type="submit">Lưu thay đổi</button></div>
      </form>`, 'Chỉnh sửa sản phẩm');
  };

  document.addEventListener('submit', async (e) => {
    const f = e.target.closest('[data-form-sp]'); if (!f) return;
    e.preventDefault();
    const ma = f.dataset.formSp; const s = tt.tatCa.find((x) => x.ma === ma);
    // Send only what changed, so a price another admin set meanwhile is not written back by a status-only edit
    const thayDoi = {};
    if (f.trangThai.value !== s.trangThai) thayDoi.status = f.trangThai.value;
    if (s.coDinh) {
      const gia = Number(String(f.gia.value).replace(/\D/g, ''));
      const giaCu = Number(String(f.giaCu.value).replace(/\D/g, '')) || null;
      const okGia = gia >= 1000; const okCu = !giaCu || giaCu >= gia;
      VN.baoLoiTruong(f.gia, okGia ? '' : 'Nhập giá hợp lệ (từ 1.000 ₫).');
      VN.baoLoiTruong(f.giaCu, okCu ? '' : 'Giá trước giảm không được thấp hơn giá bán.');
      if (!okGia || !okCu) return;
      if (gia !== s.gia) thayDoi.price = gia;
      if (giaCu !== (s.giaCu || null)) thayDoi.originalPrice = giaCu;
    }
    if (!Object.keys(thayDoi).length) { qt.dongChiTiet(); return; }      // nothing changed
    const ok = await qt.lam(() => VN.api.patch('/api/admin/products/' + encodeURIComponent(ma), thayDoi), 'Đã lưu sản phẩm ' + ma);
    if (!ok) return;
    // Read the saved row back; if that fails the change is saved all the same, so show it from the form
    const moi = (await VN.api.get('/api/admin/products').catch(() => [])).find((p) => p.SKU === ma);
    if (moi) tt.tatCa[tt.tatCa.findIndex((x) => x.ma === ma)] = sanPhamTuApi(moi);
    else {
      if ('status' in thayDoi) s.trangThai = thayDoi.status;
      if ('price' in thayDoi) s.gia = thayDoi.price;
      if ('originalPrice' in thayDoi) s.giaCu = thayDoi.originalPrice || 0;
    }
    qt.dongChiTiet(); ve();
  });
  VN.$('#qt-sp-bang').addEventListener('click', (e) => { const b = e.target.closest('[data-sua]'); if (b) moSua(b.dataset.sua); });
  VN.$('#qt-sp-dm').addEventListener('change', (e) => { tt.locDm = e.target.value; tt.trang = 1; ve(); });
  VN.$('#qt-sp-tt').addEventListener('change', (e) => { tt.locTt = e.target.value; tt.trang = 1; ve(); });
  VN.$('#qt-sp-tim').addEventListener('input', VN.chongDoi((e) => { tt.tim = e.target.value; tt.trang = 1; ve(); }, 150));
  VN.$('#qt-sp-trang').addEventListener('click', (e) => { const b = e.target.closest('[data-trang]'); if (b) { tt.trang = Number(b.dataset.trang); ve(); window.scrollTo({ top: 0 }); } });

  VN.$('#qt-sp-bang').innerHTML = `<tbody><tr><td>${qt.trong('Đang tải sản phẩm…')}</td></tr></tbody>`;
  Promise.all([VN.api.get('/api/admin/products'), VN.duLieu.danhMuc()]).then(([ds, dm]) => {
    tt.tatCa = ds.map(sanPhamTuApi); tt.dm = dm.theoId;
    VN.$('#qt-sp-dm').insertAdjacentHTML('beforeend', dm.ds.map((x) => `<option value="${x.id}">${VN.thoat(x.ten)}</option>`).join(''));
    ve();
  }).catch(qt.baoLoiTai);
})();
