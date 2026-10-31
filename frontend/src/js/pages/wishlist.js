/* =====================================================================
   SẢN PHẨM YÊU THÍCH
   - Thêm / bỏ bằng nút trái tim trên mọi thẻ sản phẩm và trang chi tiết (VN.yeuThich trong chung.js)
   - Lọc theo loại, sắp xếp theo ngày thêm / giá; tổng giá trị tham khảo, số mẫu đang ưu đãi
   - Thêm nhanh vào giỏ (mẫu không cần chọn size); nhẫn chuyển sang trang chi tiết để chọn size
   - Bỏ tất cả (có xác nhận + hoàn tác); chia sẻ danh sách qua đường dẫn ?ds=MA1,MA2
   - Gợi ý mẫu tương tự dựa trên danh sách yêu thích
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const luoi = VN.$('#yt-luoi');
  if (!luoi) return;

  const tt = { tat: [], loc: 'tat-ca', sapXep: 'moi-them', chiaSe: [], sp: null, ch: null };
  let capNhatNutGoiY = null;
  luoi.innerHTML = VN.theXuong(4);

  const nhomCua = (s) => s.dm.nhom || s.dm.ten;

  /* Ghép danh sách yêu thích với dữ liệu sản phẩm mới nhất (bỏ qua mẫu ngừng kinh doanh) */
  const napLai = () => {
    tt.tat = VN.yeuThich.ds().map((x) => ({ sp: tt.sp.theoMa[x.ma], luc: x.luc })).filter((x) => x.sp);
    ve();
    veGoiY();
  };

  /* Nút hành động dưới thẻ: mua ngay -> Thêm vào giỏ; nhẫn -> Chọn size; giá công -> Nhận báo giá */
  const nutHanhDong = (sp) => {
    if (!sp.coTheMua) return `<a class="nut nut--vien nut--rat-nho" href="${VN.url('lienHe', { sanpham: sp.ma })}">${VN.bt('thu')} Nhận báo giá</a>`;
    if (sp.canChonSize) return `<a class="nut nut--vien nut--rat-nho" href="${VN.urlSanPham(sp.ma)}">${VN.bt('nhan-nhan')} Chọn size &amp; mua</a>`;
    return `<button type="button" class="nut nut--chinh nut--rat-nho" data-them-gio="${VN.thoat(sp.ma)}">${VN.bt('tui')} Thêm vào giỏ</button>`;
  };
  const theYeuThich = ({ sp, luc }) => {
    const the = VN.theSanPham(sp);
    the.classList.add('the-yt');
    the.dataset.ma = sp.ma;
    const chan = document.createElement('div');
    chan.className = 'the-yt__chan';
    chan.innerHTML = `<span class="the-yt__luc" title="Thêm lúc ${VN.ngayGio(luc)}">${VN.bt('yeu-thich', 'bt--nho')}Đã thích ${VN.thoiGianTruoc(luc)}</span>${nutHanhDong(sp)}`;
    the.appendChild(chan);
    return the;
  };

  /* ================= HIỂN THỊ ================= */
  const ve = () => {
    const tat = tt.tat; const co = tat.length > 0;
    VN.$('#yt-trong').hidden = co;
    ['#yt-cong-cu', '#yt-tong', '#yt-xoa-het', '#yt-chia-se', '#yt-ghi-chu'].forEach((id) => { VN.$(id).hidden = !co; });
    VN.$('#yt-tom-tat').textContent = co
      ? `Bạn đang lưu ${tat.length} mẫu trang sức. Bấm trái tim lần nữa để bỏ khỏi danh sách.`
      : 'Bấm biểu tượng trái tim trên sản phẩm để lưu những mẫu bạn ưng ý vào đây.';
    VN.$('#yt-ket-qua').removeAttribute('aria-busy');
    if (!co) { luoi.innerHTML = ''; return; }

    // Nút lọc theo loại trang sức
    const dem = {};
    tat.forEach(({ sp }) => { dem[nhomCua(sp)] = (dem[nhomCua(sp)] || 0) + 1; });
    if (tt.loc !== 'tat-ca' && !dem[tt.loc]) tt.loc = 'tat-ca';
    VN.$('#yt-loc').innerHTML = `<button type="button" class="chip chip--nho" data-loc="tat-ca" aria-pressed="${tt.loc === 'tat-ca'}">Tất cả <span class="dem">${tat.length}</span></button>`
      + Object.keys(dem).map((n) => `<button type="button" class="chip chip--nho" data-loc="${VN.thoat(n)}" aria-pressed="${tt.loc === n}">${VN.thoat(n)} <span class="dem">${dem[n]}</span></button>`).join('');

    // Tổng kết: tổng giá trị (chỉ tính mẫu có giá bán trực tuyến), số mẫu ưu đãi
    let tong = 0; let uuDai = 0; let baoGia = 0; let muaNgay = 0;
    tat.forEach(({ sp: s }) => {
      if (s.coTheMua) tong += s.giaBan; else baoGia++;
      if (s.giaCu) uuDai++;
      if (s.coTheMua && !s.canChonSize) muaNgay++;
    });
    VN.$('#yt-so-mau').textContent = `${tat.length} mẫu`;
    VN.$('#yt-tong-gia').textContent = VN.tien(tong);
    VN.$('#yt-ghi-chu-gia').textContent = baoGia ? `Chưa gồm ${baoGia} mẫu tính theo giá vàng ngày` : 'Theo giá bán hiện tại';
    VN.$('#yt-uu-dai').textContent = `${uuDai} mẫu`;
    const nut = VN.$('#yt-them-tat-ca');
    nut.hidden = muaNgay === 0;
    VN.$('span', nut).textContent = `Thêm ${muaNgay} mẫu mua ngay vào giỏ`;

    // Lọc + sắp xếp
    let ds = tat.filter((m) => tt.loc === 'tat-ca' || nhomCua(m.sp) === tt.loc);
    if (tt.sapXep !== 'moi-them') {
      const huong = tt.sapXep === 'gia-tang' ? 1 : -1;
      ds = ds.slice().sort((a, b) => {
        if (a.sp.coTheMua !== b.sp.coTheMua) return a.sp.coTheMua ? -1 : 1;
        return huong * ((a.sp.giaBan || a.sp.gia) - (b.sp.giaBan || b.sp.gia));
      });
    }
    const frag = document.createDocumentFragment();
    ds.forEach((m) => frag.appendChild(theYeuThich(m)));
    luoi.innerHTML = ''; luoi.appendChild(frag);
  };

  VN.$('#yt-loc').addEventListener('click', (e) => {
    const chip = e.target.closest('[data-loc]'); if (!chip) return;
    tt.loc = chip.dataset.loc; ve();
  });
  VN.$('#yt-sap-xep').addEventListener('change', (e) => { tt.sapXep = e.target.value; ve(); });

  /* ================= THÊM VÀO GIỎ ================= */
  const dongGio = (s) => (s.mau[0] ? { ma: s.ma, soLuong: 1, mau: s.mau[0] } : { ma: s.ma, soLuong: 1 });
  luoi.addEventListener('click', (e) => {
    const nut = e.target.closest('[data-them-gio]'); if (!nut) return;
    const { vuotMuc } = VN.gioHang.them(dongGio(tt.sp.theoMa[nut.dataset.themGio]), tt.ch.soLuongToiDaMoiDong);
    VN.moGioMini();
    if (vuotMuc) VN.thongBao({ tieuDe: `Tối đa ${tt.ch.soLuongToiDaMoiDong} sản phẩm cho mỗi lựa chọn`, noiDung: 'Số lượng trong giỏ đã ở mức tối đa.' });
  });
  VN.$('#yt-them-tat-ca').addEventListener('click', () => {
    let n = 0; let boQua = 0;
    tt.tat.forEach(({ sp: s }) => {
      if (s.coTheMua && !s.canChonSize) { VN.gioHang.them(dongGio(s), tt.ch.soLuongToiDaMoiDong); n++; } else boQua++;
    });
    VN.moGioMini();
    VN.thongBao({ tieuDe: `Đã thêm ${n} mẫu vào giỏ hàng`, noiDung: boQua ? `${boQua} mẫu cần chọn size hoặc báo giá nên chưa được thêm.` : '', loai: 'thanh-cong' });
  });

  /* ================= BỎ TẤT CẢ (có hoàn tác) ================= */
  VN.$('#yt-xoa-het').addEventListener('click', async () => {
    const n = tt.tat.length;
    const dongY = await VN.xacNhan({
      nhan: 'Sản phẩm yêu thích', tieuDe: 'Bỏ toàn bộ danh sách yêu thích?',
      noiDung: `${n} sản phẩm sẽ được bỏ khỏi danh sách. Bạn vẫn có thể hoàn tác ngay sau đó.`,
      chuDongY: 'Bỏ tất cả', chuHuy: 'Giữ lại', nguy: true,
    });
    if (!dongY) return;
    const cu = VN.yeuThich.xoaHet();
    VN.thongBao({ tieuDe: 'Đã bỏ danh sách yêu thích', noiDung: `${n} sản phẩm đã được bỏ.`, thoiGian: 6000, hanhDong: { chu: 'Hoàn tác', khiBam: () => VN.yeuThich.khoiPhuc(cu) } });
  });

  /* ================= CHIA SẺ DANH SÁCH QUA ĐƯỜNG DẪN ================= */
  VN.$('#yt-chia-se').addEventListener('click', async () => {
    const ma = tt.tat.slice(0, 30).map((m) => m.sp.ma);
    const url = location.href.split('?')[0].split('#')[0] + '?ds=' + encodeURIComponent(ma.join(','));
    if (navigator.share) { navigator.share({ title: 'Danh sách yêu thích – Vinora Jewelry', url }).catch(() => {}); return; }
    try { await navigator.clipboard.writeText(url); } catch (e) { /* trình duyệt chặn: vẫn báo để người dùng tự chép */ }
    VN.thongBao({ tieuDe: 'Đã sao chép đường dẫn danh sách', noiDung: 'Dán đường dẫn để gửi cho người thân hoặc bạn bè.', loai: 'thanh-cong' });
  });
  const veDanhSachChiaSe = () => {
    const ds = (VN.thamSo('ds') || '').split(',').map((x) => tt.sp.theoMa[x.trim()]).filter(Boolean);
    tt.chiaSe = ds;
    if (!ds.length) return false;
    VN.$('#yt-ds-chia-se').hidden = false;
    VN.$('#yt-chia-se-chu').textContent = `Danh sách gồm ${ds.length} mẫu trang sức. Lưu lại để xem và đặt hàng sau.`;
    VN.$('#yt-tieu-de').textContent = 'Danh sách được chia sẻ';
    VN.$('#yt-tom-tat').textContent = 'Bấm trái tim trên từng mẫu, hoặc lưu cả danh sách vào yêu thích của bạn.';
    ['#yt-cong-cu', '#yt-tong', '#yt-xoa-het', '#yt-chia-se', '#yt-trong'].forEach((id) => { VN.$(id).hidden = true; });
    VN.veLuoi(luoi, ds);
    VN.$('#yt-ket-qua').removeAttribute('aria-busy');
    return true;
  };
  VN.$('#yt-luu-chia-se').addEventListener('click', () => {
    const hienCo = VN.yeuThich.ds(); const co = new Set(hienCo.map((x) => x.ma));
    const luc = Date.now(); let them = 0;
    const moi = tt.chiaSe.filter((s) => !co.has(s.ma)).map((s, i) => { them++; return { ma: s.ma, luc: luc - i }; });
    VN.yeuThich.luu(moi.concat(hienCo));
    VN.thongBao({ tieuDe: them ? `Đã lưu ${them} mẫu vào yêu thích` : 'Các mẫu này đã có trong danh sách của bạn', noiDung: `<a href="${VN.url('yeuThich')}">Xem danh sách của tôi</a>`, loai: 'thanh-cong' });
  });

  /* ================= GỢI Ý ================= */
  const veGoiY = () => {
    const nguon = tt.tat.length ? tt.tat.map((m) => m.sp) : tt.chiaSe;
    const daCo = new Set(nguon.map((s) => s.ma));
    const coTheMua = tt.sp.ds.filter((s) => s.coTheMua && !daCo.has(s.ma));
    let ds;
    if (nguon.length) {
      // Cùng danh mục, cùng bộ sưu tập và gần khoảng giá của các mẫu đã thích
      const diemDm = {}; const diemBst = {};
      nguon.forEach((sp, i) => {
        const w = 1 / (1 + i * 0.2);
        diemDm[sp.danhMuc] = (diemDm[sp.danhMuc] || 0) + w;
        diemBst[sp.boSuuTap] = (diemBst[sp.boSuuTap] || 0) + w;
      });
      const gia = nguon.filter((s) => s.coTheMua).map((s) => s.giaBan);
      const giaTb = gia.length ? gia.reduce((a, b) => a + b, 0) / gia.length : 10000000;
      ds = coTheMua.map((s) => [(diemDm[s.danhMuc] || 0) * 2 + (diemBst[s.boSuuTap] || 0) * 1.5 - Math.abs(Math.log(s.giaBan / giaTb)) * 0.8, s])
        .sort((a, b) => b[0] - a[0]).slice(0, 12).map((x) => x[1]);
      VN.$('#goi-y-yt-nhan').textContent = 'Gợi ý từ danh sách yêu thích';
      VN.$('#td-goi-y-yt').textContent = 'Những mẫu hợp gu của bạn';
    } else {
      ds = coTheMua.filter((s) => s.giaCu).sort((a, b) => (b.giam || 0) - (a.giam || 0)).slice(0, 12);
      VN.$('#goi-y-yt-nhan').textContent = 'Gợi ý cho bạn';
      VN.$('#td-goi-y-yt').textContent = 'Đang ưu đãi – lưu lại kẻo lỡ';
    }
    const phan = VN.$('#phan-goi-y-yt'); const dai = VN.$('#dai-goi-y-yt');
    phan.hidden = !ds.length;
    VN.veLuoi(dai, ds);
    dai.scrollLeft = 0;
    if (!capNhatNutGoiY) capNhatNutGoiY = VN.ganDieuKhienTruot(dai, VN.$('[data-dieu-khien="dai-goi-y-yt"]'));
    if (capNhatNutGoiY) setTimeout(capNhatNutGoiY, 60);
  };

  /* ================= KHỞI TẠO ================= */
  VN.duLieu.coBan().then(({ sp, ch }) => {
    tt.sp = sp; tt.ch = ch;
    if (veDanhSachChiaSe()) { veGoiY(); return; }
    napLai();
    // Bấm trái tim ở bất kỳ đâu (kể cả thẻ trong danh sách) -> dựng lại danh sách
    window.addEventListener('vinora:yeu-thich', () => { if (!tt.chiaSe.length) napLai(); });
    window.addEventListener('storage', (e) => { if (e.key === 'vinora.yeuThich' && !tt.chiaSe.length) napLai(); });
  }).catch((loi) => {
    console.error(loi);
    luoi.innerHTML = '';
    VN.thongBao({ tieuDe: 'Chưa tải được dữ liệu sản phẩm', noiDung: 'Vui lòng kiểm tra kết nối mạng rồi tải lại trang.', loai: 'loi' });
  });
})();
