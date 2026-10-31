/* =====================================================================
   QUẢN TRỊ – SẢN PHẨM
   Danh mục gốc đọc từ ../../../mock-data/products.json (AJAX). Chỉnh giá bán, giá gốc (để hiện giảm giá)
   và ngừng bán được lưu thành bản ghi đè 'qtSanPham' – cửa hàng áp dụng ngay khi tải dữ liệu
   (VN.duLieu.sanPham trong chung.js). Back-end thật sẽ cập nhật thẳng vào cơ sở dữ liệu.
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-sp-bang')) return;
  const tt = { tatCa: [], dm: {}, bst: {}, locDm: '', locTt: '', tim: '', trang: 1, banRa: {} };
  const sua = () => VN.kho.doc('qtSanPham', {});
  const ten = (s) => (tt.dm[s.danhMuc] || {}).ten || '';

  const ve = () => {
    const ghiDe = sua();
    const ds = tt.tatCa;
    VN.$('#qt-sp-so').innerHTML = [
      ['', 'Tổng mẫu', ds.length, `${Object.keys(tt.dm).length} danh mục`],
      ['ngoc', 'Đang bán', ds.filter((s) => !s.ngungBan).length, `${ds.filter((s) => !s.ngungBan && s.loaiGia === 'gia_cong').length} mẫu báo giá theo giá vàng`],
      ['do', 'Ngừng bán', ds.filter((s) => s.ngungBan).length, 'Ẩn khỏi cửa hàng'],
      ['cam', 'Đang giảm giá', ds.filter((s) => !s.ngungBan && s.giaCu).length, `${Object.keys(ghiDe).length} mẫu đã chỉnh sửa`],
    ].map(([lop, t, so, phu]) => `<div class="qt-o-so${lop ? ' qt-o-so--' + lop : ''}"><span>${t}</span><strong>${so}</strong><small>${phu}</small></div>`).join('');
    const tu = VN.khongDau(tt.tim);
    const loc = ds.filter((s) => (!tt.locDm || String(s.danhMuc) === tt.locDm)
      && (!tt.locTt || (tt.locTt === 'ban' && !s.ngungBan) || (tt.locTt === 'ngung' && s.ngungBan) || (tt.locTt === 'giam' && s.giaCu) || (tt.locTt === 'cong' && s.loaiGia === 'gia_cong') || (tt.locTt === 'sua' && ghiDe[s.ma]))
      && (!tu || VN.khongDau(s.ma + ' ' + s.ten).includes(tu)));
    const p = qt.phanTrang(loc, tt.trang, 20); tt.trang = p.trang;
    VN.$('#qt-sp-bang').innerHTML = loc.length ? `<thead><tr><th>Sản phẩm</th><th>Danh mục</th><th>Chất liệu</th><th class="so">Giá bán</th><th class="so">Giá gốc</th><th class="so">Đã bán</th><th>Trạng thái</th><th></th></tr></thead><tbody>${p.muc.map((s) => `<tr>
      <td><span class="qt-sp-nho"><img src="${VN.anh(s.anh[0])}" alt="" loading="lazy"><span>${VN.thoat(s.ten)}<small>${VN.thoat(s.ma)}${ghiDe[s.ma] ? ' · <span class="chu-vang">đã chỉnh</span>' : ''}</small></span></span></td>
      <td>${VN.thoat(ten(s))}</td><td>${VN.thoat(s.chatLieu)}</td>
      <td class="so">${s.loaiGia === 'gia_cong' ? `<small>Tiền công</small>${VN.tien(s.gia)}` : VN.tien(s.gia)}</td>
      <td class="so">${s.giaCu ? `<del>${VN.tien(s.giaCu)}</del><small>−${s.giam}%</small>` : '—'}</td>
      <td class="so">${tt.banRa[s.ma] || 0}</td>
      <td>${s.ngungBan ? '<span class="nhan nhan--do">Ngừng bán</span>' : '<span class="nhan nhan--ngoc">Đang bán</span>'}</td>
      <td><div class="qt-hanh-dong"><button type="button" class="nut nut--vien nut--rat-nho" data-sua="${VN.thoat(s.ma)}">Sửa</button>${s.ngungBan ? '' : `<a class="nut nut--chu" href="${VN.urlSanPham(s.ma)}" target="_blank" rel="noopener">Xem</a>`}</div></td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td>${qt.trong('Không có sản phẩm phù hợp.')}</td></tr></tbody>`;
    VN.$('#qt-sp-trang').innerHTML = loc.length ? qt.htmlPhanTrang(p) : '';
  };

  const moSua = (ma) => {
    const s = tt.tatCa.find((x) => x.ma === ma); if (!s) return;
    const goc = tt.goc[ma];
    qt.moChiTiet(s.ten, `<div class="qt-ct__muc"><div class="qt-sp-nho"><img src="${VN.anh(s.anh[0])}" alt=""><span>${VN.thoat(s.ten)}<small>${VN.thoat(s.ma)} · ${VN.thoat(ten(s))} · ${VN.thoat(s.chatLieu)}</small></span></div></div>
      <form class="qt-form qt-ct__muc" data-form-sp="${VN.thoat(ma)}" novalidate>
        <div class="luoi-truong">
          <div class="truong"><label class="nhan-truong" for="qt-sp-gia">${s.loaiGia === 'gia_cong' ? 'Tiền công (₫)' : 'Giá bán (₫)'}</label>
            <input class="o-nhap so-deu" id="qt-sp-gia" name="gia" inputmode="numeric" value="${s.gia}"><p class="goi-y-truong">Giá gốc trong dữ liệu: ${VN.tien(goc.gia)}</p></div>
          <div class="truong"><label class="nhan-truong" for="qt-sp-gia-cu">Giá trước giảm (₫)</label>
            <input class="o-nhap so-deu" id="qt-sp-gia-cu" name="giaCu" inputmode="numeric" value="${s.giaCu || ''}" placeholder="Để trống nếu không giảm giá"><p class="goi-y-truong">Lớn hơn giá bán thì cửa hàng hiện nhãn giảm giá.</p></div>
        </div>
        <label class="lua-chon"><input type="checkbox" name="ngungBan"${s.ngungBan ? ' checked' : ''}> <span>Ngừng bán – ẩn khỏi cửa hàng, tìm kiếm và giỏ hàng</span></label>
        <div class="hang hang--quan"><button class="nut nut--chinh nut--nho" type="submit">Lưu thay đổi</button>${sua()[ma] ? '<button class="nut nut--chu" type="button" data-khoi-phuc-sp>Khôi phục dữ liệu gốc</button>' : ''}</div>
      </form>`, 'Chỉnh sửa sản phẩm');
  };
  const apDung = (ma, ghi) => {
    const ds = sua();
    if (ghi) ds[ma] = ghi; else delete ds[ma];
    VN.kho.ghi('qtSanPham', ds);
    // Cập nhật bản đang hiển thị (dữ liệu đã nạp vào bộ nhớ)
    const s = tt.tatCa.find((x) => x.ma === ma); const g = tt.goc[ma];
    Object.assign(s, { gia: g.gia, giaCu: g.giaCu, giam: g.giam, ngungBan: false });
    if (ghi) {
      if (ghi.gia) s.gia = ghi.gia;
      if ('giaCu' in ghi) s.giaCu = ghi.giaCu || null;
      s.giam = s.giaCu && s.giaCu > s.gia ? Math.round((s.giaCu - s.gia) * 100 / s.giaCu) : null;
      if (!s.giam) s.giaCu = null;
      s.ngungBan = !!ghi.ngungBan;
    }
  };

  document.addEventListener('submit', (e) => {
    const f = e.target.closest('[data-form-sp]'); if (!f) return;
    e.preventDefault();
    const ma = f.dataset.formSp;
    const gia = Number(String(f.gia.value).replace(/\D/g, ''));
    const giaCu = Number(String(f.giaCu.value).replace(/\D/g, '')) || 0;
    const okGia = gia >= 1000; const okCu = !giaCu || giaCu > gia;
    VN.baoLoiTruong(f.gia, okGia ? '' : 'Nhập giá hợp lệ (từ 1.000 ₫).');
    VN.baoLoiTruong(f.giaCu, okCu ? '' : 'Giá trước giảm phải lớn hơn giá bán.');
    if (!okGia || !okCu) return;
    apDung(ma, { gia, giaCu: giaCu || null, ngungBan: f.ngungBan.checked, luc: new Date().toISOString(), boi: qt.nguoi.hoTen });
    VN.thongBao({ tieuDe: 'Đã lưu sản phẩm ' + ma, noiDung: 'Cửa hàng hiển thị giá mới ở lần tải trang tiếp theo.', loai: 'thanh-cong' });
    qt.dongChiTiet(); ve();
  });
  document.addEventListener('click', (e) => {
    if (e.target.closest('[data-khoi-phuc-sp]')) {
      const f = e.target.closest('form'); apDung(f.dataset.formSp, null);
      VN.thongBao({ tieuDe: 'Đã khôi phục dữ liệu gốc', loai: 'thanh-cong' }); qt.dongChiTiet(); ve();
    }
  });
  VN.$('#qt-sp-bang').addEventListener('click', (e) => { const b = e.target.closest('[data-sua]'); if (b) moSua(b.dataset.sua); });
  VN.$('#qt-sp-dm').addEventListener('change', (e) => { tt.locDm = e.target.value; tt.trang = 1; ve(); });
  VN.$('#qt-sp-tt').addEventListener('change', (e) => { tt.locTt = e.target.value; tt.trang = 1; ve(); });
  VN.$('#qt-sp-tim').addEventListener('input', VN.chongDoi((e) => { tt.tim = e.target.value; tt.trang = 1; ve(); }, 150));
  VN.$('#qt-sp-trang').addEventListener('click', (e) => { const b = e.target.closest('[data-trang]'); if (b) { tt.trang = Number(b.dataset.trang); ve(); window.scrollTo({ top: 0 }); } });

  Promise.all([VN.duLieu.sanPham(), VN.duLieu.danhMuc(), VN.taiJSON((VN.duongDan.duLieu || '../../../mock-data/') + 'products.json?goc=1')]).then(([sp, dm, goc]) => {
    tt.tatCa = sp.tatCa; tt.dm = dm.theoId;
    tt.goc = {}; goc.sanPham.forEach((s) => { tt.goc[s.ma] = { gia: s.gia, giaCu: s.giaCu, giam: s.giam }; });
    VN.donHang.tatCa().filter((d) => d.trangThai !== 'Cancelled').forEach((d) => d.sanPham.forEach((x) => { tt.banRa[x.ma] = (tt.banRa[x.ma] || 0) + x.soLuong; }));
    VN.$('#qt-sp-dm').insertAdjacentHTML('beforeend', dm.ds.map((x) => `<option value="${x.id}">${VN.thoat(x.ten)}</option>`).join(''));
    ve();
  });
})();
