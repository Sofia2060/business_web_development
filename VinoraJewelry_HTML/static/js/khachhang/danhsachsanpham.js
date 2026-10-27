/* =====================================================================
   5.2.2 DANH SÁCH SẢN PHẨM
   Lọc theo loại, khoảng giá, chất liệu, màu vàng, bộ sưu tập, ưu đãi;
   tìm kiếm không dấu (?q=); sắp xếp; đếm số sản phẩm theo từng lựa chọn;
   đồng bộ bộ lọc lên URL (phương thức GET) để chia sẻ và quay lại được.
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const MOI_TRANG = 24;
  const form = VN.$('#form-loc'); const luoi = VN.$('#luoi-sp');
  if (!form || !luoi) return;

  const MAU = [
    { ma: 'vang-vang', ten: 'Vàng vàng', lop: 'cham-mau--vang', khop: (m) => m === 'Vàng Vàng' },
    { ma: 'vang-trang', ten: 'Vàng trắng', lop: 'cham-mau--trang', khop: (m) => m === 'Vàng Trắng' },
    { ma: 'vang-hong', ten: 'Vàng hồng', lop: 'cham-mau--hong', khop: (m) => m === 'Vàng Hồng' },
    { ma: 'bac', ten: 'Bạc', lop: 'cham-mau--bac', khop: (m) => m.startsWith('Bạc') },
  ];
  const CHAT_LIEU = [['10K', 'Vàng 10K'], ['14K', 'Vàng 14K'], ['18K', 'Vàng 18K'], ['22K', 'Vàng 22K'], ['24K', 'Vàng 24K'], ['BAC925', 'Bạc 925']];
  const NHOM_DM = [['Nhẫn', [1, 2, 3]], ['Trang sức', [4, 5, 6, 7, 8, 9]], ['Quà tài lộc', [10]]];
  const SAP_XEP = ['noi-bat', 'moi', 'gia-tang', 'gia-giam', 'giam-nhieu'];

  /* ---------- Trạng thái bộ lọc đọc từ URL ---------- */
  const ts = new URLSearchParams(location.search);
  const tachSo = (v) => new Set(String(v || '').split(',').map(Number).filter((x) => x > 0));
  const tachChu = (v) => new Set(String(v || '').split(',').filter(Boolean));
  const tt = {
    danhMuc: tachSo(ts.get('danhmuc')), boSuuTap: tachSo(ts.get('bst')), chatLieu: tachChu(ts.get('chatlieu')),
    mau: tachChu(ts.get('mau')), giaTu: null, giaDen: null, uuDai: ts.get('uudai') === '1',
    q: (ts.get('q') || '').trim(), sapXep: SAP_XEP.includes(ts.get('sapxep')) ? ts.get('sapxep') : 'noi-bat',
    soTrang: Math.max(1, Number(ts.get('trang')) || 1),
  };
  if (ts.get('nhom') === 'nhan') [1, 2, 3].forEach((i) => tt.danhMuc.add(i));
  if (ts.get('gia')) {
    const [a, b] = ts.get('gia').split('-');
    tt.giaTu = a !== '' && !isNaN(a) ? Number(a) : null; tt.giaDen = b !== undefined && b !== '' && !isNaN(b) ? Number(b) : null;
  }

  const ghiURL = () => {
    const q = new URLSearchParams();
    if (tt.q) q.set('q', tt.q);
    if (tt.danhMuc.size) q.set('danhmuc', [...tt.danhMuc].sort((a, b) => a - b).join(','));
    if (tt.boSuuTap.size) q.set('bst', [...tt.boSuuTap].join(','));
    if (tt.chatLieu.size) q.set('chatlieu', [...tt.chatLieu].join(','));
    if (tt.mau.size) q.set('mau', [...tt.mau].join(','));
    if (tt.giaTu !== null || tt.giaDen !== null) q.set('gia', `${tt.giaTu ?? ''}-${tt.giaDen ?? ''}`);
    if (tt.uuDai) q.set('uudai', '1');
    if (tt.sapXep !== 'noi-bat') q.set('sapxep', tt.sapXep);
    if (tt.soTrang > 1) q.set('trang', tt.soTrang);
    const chuoi = q.toString();
    history.replaceState(null, '', location.pathname + (chuoi ? '?' + chuoi : ''));
  };

  let DL = null; // dữ liệu: sp, dm, bst

  /** Sản phẩm có thỏa các bộ lọc không (bỏ qua 1 nhóm để đếm số lượng cho nhóm đó) */
  const khop = (sp, boQua) => {
    if (boQua !== 'dm' && tt.danhMuc.size && !tt.danhMuc.has(sp.danhMuc)) return false;
    if (boQua !== 'bst' && tt.boSuuTap.size && !tt.boSuuTap.has(sp.boSuuTap)) return false;
    if (boQua !== 'cl' && tt.chatLieu.size && !tt.chatLieu.has(sp.chatLieu)) return false;
    if (boQua !== 'mau' && tt.mau.size && !MAU.some((m) => tt.mau.has(m.ma) && sp.mau.some(m.khop))) return false;
    if (boQua !== 'gia' && (tt.giaTu !== null || tt.giaDen !== null)) {
      if (!sp.coTheMua) return false;
      if (tt.giaTu !== null && sp.giaBan < tt.giaTu) return false;
      if (tt.giaDen !== null && sp.giaBan > tt.giaDen) return false;
    }
    if (boQua !== 'ud' && tt.uuDai && !sp.giaCu) return false;
    return true;
  };

  const sapXep = (ds) => {
    const giaSx = (s) => (s.coTheMua ? s.giaBan : null);
    const cmpNgay = (a, b) => (b.ngayTao || '').localeCompare(a.ngayTao || '');
    const a = ds.slice();
    switch (tt.sapXep) {
      case 'moi': return a.sort(cmpNgay);
      case 'gia-tang': return a.sort((x, y) => (giaSx(x) ?? Infinity) - (giaSx(y) ?? Infinity));
      case 'gia-giam': return a.sort((x, y) => (giaSx(y) ?? -1) - (giaSx(x) ?? -1));
      case 'giam-nhieu': return a.sort((x, y) => (y.giam || 0) - (x.giam || 0) || (giaSx(y) ?? -1) - (giaSx(x) ?? -1));
      default: return tt.q ? a : a.sort((x, y) => Number(!!y.moTa) - Number(!!x.moTa) || cmpNgay(x, y));
    }
  };

  /* ---------- Dựng các nhóm lựa chọn của bộ lọc ---------- */
  const dungBoLoc = () => {
    VN.$('#loc-danh-muc').innerHTML = NHOM_DM.map(([ten, ids]) => `<p class="ds-chon__nhom">${ten}</p>` + ids.map((id) => {
      const d = DL.dm.theoId[id];
      return `<label class="lua-chon" data-dong-dm="${id}"><input type="checkbox" value="${id}" name="danhmuc"><span>${VN.thoat(d.ten)} <i class="dem" data-dem></i></span></label>`;
    }).join('')).join('');
    VN.$('#loc-bst').innerHTML = DL.bst.ds.slice().sort((a, b) => b.soLuong - a.soLuong).map((b) =>
      `<label class="lua-chon" data-dong-bst="${b.id}"><input type="checkbox" value="${b.id}" name="bst"><span>${VN.thoat(b.ten)} <i class="dem" data-dem></i></span></label>`).join('');
    VN.$('#loc-chat-lieu').innerHTML = CHAT_LIEU.map(([ma, ten]) =>
      `<button class="chip chip--nho" type="button" data-cl="${ma}" aria-pressed="false">${ten} <span class="dem" data-dem></span></button>`).join('');
    VN.$('#loc-mau').innerHTML = MAU.map((m) =>
      `<button class="chip chip--nho" type="button" data-mau="${m.ma}" aria-pressed="false"><i class="cham-mau ${m.lop}"></i>${m.ten} <span class="dem" data-dem></span></button>`).join('');
  };

  /** Đồng bộ trạng thái lên các ô nhập + cập nhật số đếm từng lựa chọn */
  const capNhatBoLoc = () => {
    const goc = DL.goc;
    VN.$$('[data-dong-dm]').forEach((nhan) => {
      const id = Number(nhan.dataset.dongDm); const n = goc.filter((s) => s.danhMuc === id && khop(s, 'dm')).length;
      nhan.querySelector('input').checked = tt.danhMuc.has(id); nhan.querySelector('[data-dem]').textContent = n;
      nhan.classList.toggle('het', n === 0 && !tt.danhMuc.has(id));
    });
    VN.$$('[data-dong-bst]').forEach((nhan) => {
      const id = Number(nhan.dataset.dongBst); const n = goc.filter((s) => s.boSuuTap === id && khop(s, 'bst')).length;
      nhan.querySelector('input').checked = tt.boSuuTap.has(id); nhan.querySelector('[data-dem]').textContent = n;
      nhan.classList.toggle('het', n === 0 && !tt.boSuuTap.has(id));
    });
    VN.$$('[data-cl]').forEach((b) => {
      const n = goc.filter((s) => s.chatLieu === b.dataset.cl && khop(s, 'cl')).length;
      b.setAttribute('aria-pressed', tt.chatLieu.has(b.dataset.cl)); b.querySelector('[data-dem]').textContent = `(${n})`;
      b.classList.toggle('het', n === 0 && !tt.chatLieu.has(b.dataset.cl));
    });
    VN.$$('[data-mau]').forEach((b) => {
      const m = MAU.find((x) => x.ma === b.dataset.mau); const n = goc.filter((s) => s.mau.some(m.khop) && khop(s, 'mau')).length;
      b.setAttribute('aria-pressed', tt.mau.has(m.ma)); b.querySelector('[data-dem]').textContent = `(${n})`;
      b.classList.toggle('het', n === 0 && !tt.mau.has(m.ma));
    });
    VN.$('#loc-uu-dai').checked = tt.uuDai;
    VN.$('#dem-uu-dai').textContent = `(${goc.filter((s) => s.giaCu && khop(s, 'ud')).length})`;
    // Giá
    VN.$$('#loc-gia-nhanh [data-gia]').forEach((b) => {
      const [a, c] = b.dataset.gia.split('-');
      const tu = Number(a); const den = c === '' ? null : Number(c);
      b.setAttribute('aria-pressed', tt.giaTu === tu && tt.giaDen === den);
    });
    const truotTu = VN.$('#gia-tu-truot'); const truotDen = VN.$('#gia-den-truot');
    truotTu.value = tt.giaTu ?? 0; truotDen.value = tt.giaDen ?? truotDen.max;
    VN.$('#gia-tu').value = tt.giaTu ?? ''; VN.$('#gia-den').value = tt.giaDen ?? '';
    veDoanTruot();
    VN.$('#gia-hien-thi').textContent = (tt.giaTu !== null || tt.giaDen !== null)
      ? `Đang lọc: ${VN.tien(tt.giaTu || 0)} – ${tt.giaDen !== null ? VN.tien(tt.giaDen) : 'không giới hạn'}` : 'Kéo hoặc nhập khoảng giá mong muốn.';
    VN.$('#sap-xep').value = tt.sapXep;
  };

  const veDoanTruot = () => {
    const tu = VN.$('#gia-tu-truot'); const den = VN.$('#gia-den-truot'); const max = Number(den.max);
    const doan = VN.$('.truot-kep__doan');
    doan.style.left = (Number(tu.value) / max * 100) + '%';
    doan.style.right = (100 - Number(den.value) / max * 100) + '%';
  };

  /* ---------- Tiêu đề, đường dẫn theo bộ lọc ---------- */
  const capNhatTieuDe = (n) => {
    let nhan = 'Vinora Jewelry'; let tieuDe = 'Tất cả trang sức'; let moTa = 'Minh bạch tuổi vàng, trọng lượng và thông tin đá trên từng sản phẩm.';
    const dms = [...tt.danhMuc]; const bsts = [...tt.boSuuTap];
    if (tt.q) { nhan = 'Kết quả tìm kiếm'; tieuDe = `“${tt.q}”`; moTa = `${n} sản phẩm phù hợp với từ khóa của bạn.`; }
    else if (dms.length === 3 && [1, 2, 3].every((i) => tt.danhMuc.has(i))) { nhan = 'Danh mục'; tieuDe = 'Nhẫn'; moTa = 'Nhẫn cầu hôn, nhẫn cưới và nhẫn thời trang – chọn size dễ dàng, khắc tên laser miễn phí.'; }
    else if (dms.length === 1) { const d = DL.dm.theoId[dms[0]]; nhan = d.nhom === d.ten ? 'Danh mục' : d.nhom; tieuDe = d.ten; moTa = d.moTa + '.'; }
    else if (bsts.length === 1 && !dms.length) { const b = DL.bst.theoId[bsts[0]]; nhan = 'Bộ sưu tập'; tieuDe = b.ten; moTa = `${b.loaiSanPham.join(' · ')} – chất liệu ${b.chatLieu.map((c) => (c === 'BAC925' ? 'Bạc 925' : c)).join(', ')}.`; }
    else if (tt.uuDai && !dms.length && !bsts.length) { nhan = 'Ưu đãi'; tieuDe = 'Trang sức đang ưu đãi'; moTa = 'Giá ưu đãi đã hiển thị trực tiếp, không cần nhập mã.'; }
    else if (tt.giaTu !== null || tt.giaDen !== null) { nhan = 'Gợi ý quà tặng'; tieuDe = 'Quà tặng theo ngân sách'; }
    VN.$('#ds-nhan').textContent = nhan; VN.$('#ds-tieu-de').textContent = tieuDe; VN.$('#ds-mo-ta').textContent = moTa;
    VN.$('#duong-dan-ds').innerHTML = `<li><a href="${VN.url('trangChu')}">Trang chủ</a></li>`
      + (tieuDe !== 'Tất cả trang sức' ? `<li><a href="${VN.url('sanPham')}">Trang sức</a></li>` : '')
      + `<li aria-current="page">${VN.thoat(tieuDe)}</li>`;
    document.title = `${tieuDe.replace(/[“”]/g, '')} – Vinora Jewelry`;
  };

  /* ---------- Chip bộ lọc đang áp dụng ---------- */
  const veChipDangLoc = () => {
    const chip = [];
    const them = (nhan, xoa) => chip.push({ nhan, xoa });
    if (tt.q) them(`Từ khóa: ${tt.q}`, () => { tt.q = ''; VN.$('#o-tim-nhap') && (VN.$('#o-tim-nhap').value = ''); });
    tt.danhMuc.forEach((id) => them(DL.dm.theoId[id].ten, () => tt.danhMuc.delete(id)));
    tt.boSuuTap.forEach((id) => them(DL.bst.theoId[id].ten, () => tt.boSuuTap.delete(id)));
    tt.chatLieu.forEach((c) => them(CHAT_LIEU.find((x) => x[0] === c)?.[1] || c, () => tt.chatLieu.delete(c)));
    tt.mau.forEach((m) => them(MAU.find((x) => x.ma === m)?.ten || m, () => tt.mau.delete(m)));
    if (tt.giaTu !== null || tt.giaDen !== null) them(`${VN.tien(tt.giaTu || 0)} – ${tt.giaDen !== null ? VN.tien(tt.giaDen) : 'trở lên'}`, () => { tt.giaTu = null; tt.giaDen = null; });
    if (tt.uuDai) them('Đang ưu đãi', () => { tt.uuDai = false; });
    const khung = VN.$('#chip-dang-loc');
    khung.innerHTML = chip.map((c, i) => `<button type="button" class="chip" data-bo-chip="${i}" aria-label="Bỏ lọc ${VN.thoat(c.nhan)}">${VN.thoat(c.nhan)} ${VN.bt('dong')}</button>`).join('')
      + (chip.length > 1 ? '<button type="button" class="xoa-het" data-xoa-loc>Xóa tất cả</button>' : '');
    VN.$$('[data-bo-chip]', khung).forEach((b) => b.addEventListener('click', () => { chip[Number(b.dataset.boChip)].xoa(); apDung(); }));
    VN.$$('[data-xoa-loc]', khung).forEach((b) => b.addEventListener('click', xoaTatCa));
    const dem = chip.length; const nhanDem = VN.$('[data-dem-loc]');
    nhanDem.hidden = !dem; nhanDem.textContent = dem;
  };

  /* ---------- Hiển thị kết quả ---------- */
  let ketQua = [];
  const ve = (giuTrang = false) => {
    const goc = DL.goc;
    ketQua = sapXep(goc.filter((s) => khop(s)));
    if (!giuTrang) tt.soTrang = 1;
    const n = ketQua.length; const hien = Math.min(n, tt.soTrang * MOI_TRANG);
    VN.veLuoi(luoi, ketQua.slice(0, hien));
    luoi.removeAttribute('aria-busy');
    VN.$('#ds-trong').hidden = n > 0; luoi.hidden = n === 0;
    if (!n) VN.$('#ds-trong-chu').textContent = tt.q ? `Không có sản phẩm nào khớp với “${tt.q}” và bộ lọc hiện tại. Hãy thử từ khóa khác hoặc bỏ bớt bộ lọc.` : 'Hãy thử bỏ bớt bộ lọc để xem nhiều sản phẩm hơn.';
    VN.$('#ds-dem').innerHTML = n ? `Hiển thị <strong>${hien}</strong> / <strong>${n}</strong> sản phẩm` : 'Không có sản phẩm phù hợp';
    VN.$$('[data-so-ket-qua]').forEach((el) => { el.textContent = n; });
    capNhatXemThem(hien, n);
    capNhatTieuDe(n); veChipDangLoc(); capNhatBoLoc(); ghiURL();
  };
  const capNhatXemThem = (hien, n) => {
    const khung = VN.$('#xem-them'); khung.hidden = n <= MOI_TRANG && hien >= n;
    VN.$('#xem-them-chu').textContent = `Bạn đã xem ${hien} trên ${n} sản phẩm`;
    VN.$('#xem-them-thanh').style.width = (n ? hien / n * 100 : 0) + '%';
    const nut = VN.$('#nut-xem-them'); nut.hidden = hien >= n;
    nut.textContent = `Xem thêm ${Math.min(MOI_TRANG, n - hien)} sản phẩm`;
  };
  VN.$('#nut-xem-them').addEventListener('click', () => {
    const tu = tt.soTrang * MOI_TRANG; tt.soTrang += 1;
    const them = ketQua.slice(tu, tt.soTrang * MOI_TRANG);
    const frag = document.createDocumentFragment(); them.forEach((s) => frag.appendChild(VN.theSanPham(s))); luoi.appendChild(frag);
    const hien = Math.min(ketQua.length, tt.soTrang * MOI_TRANG);
    VN.$('#ds-dem').innerHTML = `Hiển thị <strong>${hien}</strong> / <strong>${ketQua.length}</strong> sản phẩm`;
    capNhatXemThem(hien, ketQua.length); ghiURL();
    const dau = luoi.children[tu]; if (dau) dau.querySelector('a').focus({ preventScroll: true });
  });

  const apDung = VN.chongDoi(() => ve(false), 60);
  const xoaTatCa = () => {
    tt.danhMuc.clear(); tt.boSuuTap.clear(); tt.chatLieu.clear(); tt.mau.clear();
    tt.giaTu = null; tt.giaDen = null; tt.uuDai = false; tt.q = '';
    const o = VN.$('#o-tim-nhap'); if (o) o.value = '';
    ve(false);
  };

  /* ---------- Sự kiện trên bộ lọc ---------- */
  form.addEventListener('submit', (e) => e.preventDefault());
  form.addEventListener('reset', (e) => { e.preventDefault(); xoaTatCa(); });
  form.addEventListener('change', (e) => {
    const t = e.target;
    if (t.name === 'danhmuc') { const id = Number(t.value); t.checked ? tt.danhMuc.add(id) : tt.danhMuc.delete(id); apDung(); }
    if (t.name === 'bst') { const id = Number(t.value); t.checked ? tt.boSuuTap.add(id) : tt.boSuuTap.delete(id); apDung(); }
    if (t.id === 'loc-uu-dai') { tt.uuDai = t.checked; apDung(); }
    if (t.id === 'gia-tu' || t.id === 'gia-den') {
      const tu = VN.$('#gia-tu').value; const den = VN.$('#gia-den').value;
      tt.giaTu = tu === '' ? null : Math.max(0, Number(tu)); tt.giaDen = den === '' ? null : Math.max(0, Number(den));
      if (tt.giaTu !== null && tt.giaDen !== null && tt.giaTu > tt.giaDen) [tt.giaTu, tt.giaDen] = [tt.giaDen, tt.giaTu];
      apDung();
    }
  });
  form.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-cl], button[data-mau], button[data-gia]'); if (!b) return;
    if (b.dataset.cl) { tt.chatLieu.has(b.dataset.cl) ? tt.chatLieu.delete(b.dataset.cl) : tt.chatLieu.add(b.dataset.cl); }
    if (b.dataset.mau) { tt.mau.has(b.dataset.mau) ? tt.mau.delete(b.dataset.mau) : tt.mau.add(b.dataset.mau); }
    if (b.dataset.gia) {
      const [a, c] = b.dataset.gia.split('-'); const tu = Number(a); const den = c === '' ? null : Number(c);
      if (tt.giaTu === tu && tt.giaDen === den) { tt.giaTu = null; tt.giaDen = null; } else { tt.giaTu = tu; tt.giaDen = den; }
    }
    apDung();
  });
  // Thanh trượt kép: hai input type="range" chồng lên nhau, không cho vượt qua nhau
  const truotTu = VN.$('#gia-tu-truot'); const truotDen = VN.$('#gia-den-truot');
  const khiTruot = (e) => {
    let tu = Number(truotTu.value); let den = Number(truotDen.value); const buoc = Number(truotTu.step);
    if (tu > den - buoc) { if (e.target === truotTu) tu = den - buoc; else den = tu + buoc; truotTu.value = tu; truotDen.value = den; }
    VN.$('#gia-tu').value = tu || ''; VN.$('#gia-den').value = den >= Number(truotDen.max) ? '' : den;
    veDoanTruot();
    VN.$('#gia-hien-thi').textContent = `${VN.tien(tu)} – ${den >= Number(truotDen.max) ? 'không giới hạn' : VN.tien(den)}`;
  };
  const xongTruot = () => {
    const tu = Number(truotTu.value); const den = Number(truotDen.value);
    tt.giaTu = tu > 0 ? tu : null; tt.giaDen = den < Number(truotDen.max) ? den : null; apDung();
  };
  [truotTu, truotDen].forEach((r) => { r.addEventListener('input', khiTruot); r.addEventListener('change', xongTruot); });
  VN.$('#sap-xep').addEventListener('change', (e) => { tt.sapXep = e.target.value; ve(false); });

  /* ---------- Bộ lọc dạng ngăn kéo trên điện thoại ---------- */
  const nganKeo = VN.$('#ngan-keo-loc'); const cot = VN.$('#cot-loc');
  VN.$$('[data-mo-loc]').forEach((b) => b.addEventListener('click', () => { nganKeo.appendChild(form); VN.moHopThoai(nganKeo); }));
  nganKeo.addEventListener('close', () => cot.appendChild(form));
  form.addEventListener('click', (e) => { if (e.target.closest('[data-dong-loc]')) VN.dongHopThoai(nganKeo); });
  VN.$$('#ds-trong [data-xoa-loc]').forEach((b) => b.addEventListener('click', xoaTatCa));

  /* ---------- Giữ vị trí cuộn khi quay lại từ trang chi tiết ---------- */
  const KHOA_CUON = 'vinora.cuon.' + location.pathname;
  luoi.addEventListener('click', (e) => { if (e.target.closest('a')) { try { sessionStorage.setItem(KHOA_CUON, JSON.stringify({ y: scrollY, url: location.search })); } catch (er) { /* bỏ qua */ } } });

  /* ---------- Khởi động ---------- */
  luoi.innerHTML = VN.theXuong(6);
  VN.duLieu.coBan().then(({ sp, dm, bst }) => {
    DL = { sp, dm, bst, goc: tt.q ? VN.timSanPham(sp.ds, tt.q) : sp.ds };
    const giaMax = Math.ceil(Math.max(...sp.ds.filter((s) => s.coTheMua).map((s) => s.giaBan)) / 1e6) * 1e6;
    [truotTu, truotDen].forEach((r) => { r.max = giaMax; }); truotDen.value = giaMax;
    dungBoLoc();
    ve(true);
    try {
      const cu = JSON.parse(sessionStorage.getItem(KHOA_CUON) || 'null');
      if (cu && cu.url === location.search) { requestAnimationFrame(() => window.scrollTo({ top: cu.y, behavior: 'instant' })); }
      sessionStorage.removeItem(KHOA_CUON);
    } catch (er) { /* bỏ qua */ }
  }).catch((loi) => {
    console.error(loi);
    luoi.innerHTML = '';
    VN.$('#ds-dem').textContent = 'Chưa tải được dữ liệu sản phẩm. Hãy chạy website bằng máy chủ (python app.py).';
  });
})();
