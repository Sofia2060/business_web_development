/* =====================================================================
   5.2.1 TRANG CHỦ – trình chiếu banner, danh mục, tab sản phẩm, bộ sưu tập,
   xem trước khắc chữ, quà theo ngân sách, sản phẩm đã xem.
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;

  /* ---------- 1. Banner trình chiếu (tự chạy 7 giây, dừng khi rê chuột / focus) ---------- */
  const banner = VN.$('.banner');
  if (banner) {
    const trang = VN.$$('.banner__trang', banner);
    const cham = VN.$$('.banner__cham button', banner);
    const nutDung = VN.$('[data-banner="tam-dung"]', banner);
    const giamChuyenDong = matchMedia('(prefers-reduced-motion: reduce)').matches;
    let hienTai = 0; let hen = null; let tamDung = giamChuyenDong;
    const THOI_GIAN = 7000;
    banner.style.setProperty('--thoi-gian-banner', THOI_GIAN / 1000 + 's');

    const chuyen = (i) => {
      hienTai = (i + trang.length) % trang.length;
      trang.forEach((t, k) => { t.classList.toggle('dang-hien', k === hienTai); t.setAttribute('aria-hidden', k === hienTai ? 'false' : 'true'); t.inert = k !== hienTai; });
      cham.forEach((c, k) => c.setAttribute('aria-selected', k === hienTai ? 'true' : 'false'));
      chay();
    };
    const chay = () => {
      clearTimeout(hen);
      banner.classList.remove('dang-chay'); void banner.offsetWidth;
      if (tamDung) return;
      banner.classList.add('dang-chay');
      hen = setTimeout(() => chuyen(hienTai + 1), THOI_GIAN);
    };
    cham.forEach((c, k) => c.addEventListener('click', () => chuyen(k)));
    VN.$('[data-banner="truoc"]', banner).addEventListener('click', () => chuyen(hienTai - 1));
    VN.$('[data-banner="sau"]', banner).addEventListener('click', () => chuyen(hienTai + 1));
    nutDung.addEventListener('click', () => {
      tamDung = !tamDung; nutDung.setAttribute('aria-pressed', tamDung ? 'true' : 'false');
      nutDung.setAttribute('aria-label', tamDung ? 'Tiếp tục trình chiếu' : 'Tạm dừng trình chiếu'); chay();
    });
    banner.addEventListener('mouseenter', () => { clearTimeout(hen); banner.classList.remove('dang-chay'); });
    banner.addEventListener('mouseleave', chay);
    banner.addEventListener('focusin', () => { clearTimeout(hen); banner.classList.remove('dang-chay'); });
    banner.addEventListener('keydown', (e) => { if (e.key === 'ArrowLeft') chuyen(hienTai - 1); if (e.key === 'ArrowRight') chuyen(hienTai + 1); });
    document.addEventListener('visibilitychange', () => { if (document.hidden) clearTimeout(hen); else chay(); });
    // Vuốt trên điện thoại
    let x0 = null;
    banner.addEventListener('touchstart', (e) => { x0 = e.touches[0].clientX; }, { passive: true });
    banner.addEventListener('touchend', (e) => { if (x0 === null) return; const dx = e.changedTouches[0].clientX - x0; if (Math.abs(dx) > 50) chuyen(hienTai + (dx < 0 ? 1 : -1)); x0 = null; });
    chuyen(0);
  }

  /* ---------- 2. Cuộn dải sản phẩm bằng nút mũi tên (VN.ganDieuKhienTruot trong chung.js) ---------- */
  const ganDieuKhienTruot = VN.ganDieuKhienTruot;

  const anhNen = (sp) => sp.anh.find((a) => !VN.laAnhChup(a)) || sp.anh[0];

  VN.duLieu.coBan().then(({ sp, dm, bst }) => {
    const coTheMua = sp.ds.filter((s) => s.coTheMua);
    const moiNhat = coTheMua.slice().sort((a, b) => (b.ngayTao || '').localeCompare(a.ngayTao || ''));

    /* Ảnh & giá trên banner theo mã sản phẩm */
    VN.$$('.banner [data-anh-ma]').forEach((img) => {
      const s = sp.theoMa[img.dataset.anhMa]; if (!s) return;
      const duong = s.anh[Number(img.dataset.anhThu) || 0] || s.anh[0];
      img.src = VN.anh(duong); img.alt = s.ten;
      if (img.closest('.banner__anh-nho') && !VN.laAnhChup(duong)) img.classList.add('la-anh-nen');
    });
    VN.$$('.banner [data-gia-ma]').forEach((el) => {
      const s = sp.theoMa[el.dataset.giaMa]; if (!s) return;
      el.innerHTML = `${VN.thoat(s.ma)} · ${VN.thoat(s.bst.ten)}<strong>${s.coTheMua ? VN.tien(s.giaBan) : 'Giá theo ngày'}</strong>`;
    });

    /* ---------- 3. Lưới danh mục ---------- */
    const luoiDm = VN.$('#luoi-danh-muc');
    const thuTuDm = [1, 2, 3, 4, 5, 6, 8, 9];
    luoiDm.innerHTML = thuTuDm.map((id) => {
      const d = dm.theoId[id]; if (!d) return '';
      const daiDien = moiNhat.find((s) => s.danhMuc === id && !VN.laAnhChup(s.anh[0])) || coTheMua.find((s) => s.danhMuc === id);
      return `<li class="o-danh-muc hien-dan"><a href="${VN.url('sanPham', { danhmuc: id })}">
        <span class="o-danh-muc__anh">${daiDien ? `<img src="${VN.anh(anhNen(daiDien))}" alt="" loading="lazy" width="400" height="400">` : ''}</span>
        <span class="o-danh-muc__ten">${VN.thoat(d.ten)}</span><span class="o-danh-muc__dem">${d.soLuong} mẫu</span></a></li>`;
    }).join('');
    luoiDm.removeAttribute('aria-busy');

    /* ---------- 4. Tab sản phẩm nổi bật ---------- */
    const dai = VN.$('#dai-noi-bat');
    const capNhatNut = ganDieuKhienTruot(dai, VN.$('[data-dieu-khien="dai-noi-bat"]'));
    const nhomTab = {
      moi: { ds: moiNhat.slice(0, 12), url: VN.url('sanPham', { sapxep: 'moi' }), chu: 'Xem tất cả sản phẩm mới' },
      'uu-dai': { ds: coTheMua.filter((s) => s.giaCu).sort((a, b) => (b.giam || 0) - (a.giam || 0) || b.giaBan - a.giaBan).slice(0, 12), url: VN.url('sanPham', { uudai: 1 }), chu: 'Xem tất cả ưu đãi' },
      'cau-hon': { ds: moiNhat.filter((s) => s.danhMuc === 1).slice(0, 12), url: VN.url('sanPham', { danhmuc: 1 }), chu: 'Xem tất cả nhẫn cầu hôn' },
      qua: { ds: moiNhat.filter((s) => s.giaBan < 5000000).slice(0, 12), url: VN.url('sanPham', { gia: '0-5000000' }), chu: 'Xem quà dưới 5 triệu' },
    };
    const nutXem = VN.$('[data-xem-tat-ca]');
    const moTab = (ma) => {
      VN.$$('.tab-noi-bat [role="tab"]').forEach((t) => t.setAttribute('aria-selected', t.dataset.tab === ma ? 'true' : 'false'));
      const n = nhomTab[ma];
      VN.veLuoi(dai, n.ds); dai.scrollLeft = 0;
      nutXem.href = n.url; nutXem.textContent = n.chu;
      if (capNhatNut) setTimeout(capNhatNut, 50);
    };
    VN.$$('.tab-noi-bat [role="tab"]').forEach((t) => {
      t.addEventListener('click', () => moTab(t.dataset.tab));
      t.addEventListener('keydown', (e) => {
        if (!['ArrowLeft', 'ArrowRight'].includes(e.key)) return;
        const ds = VN.$$('.tab-noi-bat [role="tab"]'); const i = ds.indexOf(t);
        const k = ds[(i + (e.key === 'ArrowRight' ? 1 : -1) + ds.length) % ds.length]; k.focus(); k.click();
      });
    });
    moTab('moi');

    /* ---------- 5. Bộ sưu tập nổi bật ---------- */
    const dsBst = [1, 2, 3, 4, 9].map((id) => bst.theoId[id]).filter(Boolean);
    VN.$('#luoi-bst').innerHTML = dsBst.map((b) => {
      const daiDien = moiNhat.find((s) => s.boSuuTap === b.id && !VN.laAnhChup(s.anh[0])) || sp.ds.find((s) => s.boSuuTap === b.id);
      return `<a class="o-bst hien-dan" href="${VN.url('sanPham', { bst: b.id })}">
        <span class="o-bst__anh">${daiDien ? `<img src="${VN.anh(anhNen(daiDien))}" alt="" loading="lazy" width="600" height="600">` : ''}</span>
        <span class="o-bst__chu"><span class="nhan-tren">${b.soLuong} thiết kế</span><span class="o-bst__ten">${VN.thoat(b.ten)}</span>
        <span class="o-bst__mo-ta">${VN.thoat(b.loaiSanPham.join(' · '))} – ${VN.thoat(b.chatLieu.map((c) => c === 'BAC925' ? 'Bạc 925' : c).join(', '))}</span>
        <span class="nut nut--chu">Khám phá</span></span></a>`;
    }).join('');

    /* ---------- 7. Đếm sản phẩm theo ngân sách ---------- */
    VN.$$('#luoi-ngan-sach [data-khoang]').forEach((a) => {
      const [tu, den] = a.dataset.khoang.split('-').map((x) => (x === '' ? Infinity : Number(x)));
      const n = coTheMua.filter((s) => s.giaBan >= tu && s.giaBan < (den || Infinity)).length;
      VN.$('[data-dem]', a).textContent = `${n} sản phẩm`;
    });

    /* ---------- 8. Sản phẩm đã xem ---------- */
    const daXem = VN.daXem.ds().map((x) => sp.theoMa[x.ma]).filter(Boolean).slice(0, 8);
    if (daXem.length) { VN.$('#phan-da-xem').hidden = false; VN.veLuoi(VN.$('#dai-da-xem'), daXem); }

    VN.hienDan();
  }).catch((loi) => {
    console.error(loi);
    VN.thongBao({ tieuDe: 'Chưa tải được dữ liệu sản phẩm', noiDung: 'Hãy chạy website bằng máy chủ (python app.py) thay vì mở trực tiếp tệp HTML.', loai: 'loi' });
  });

  /* ---------- 6. Xem trước khắc chữ ---------- */
  const form = VN.$('#form-khac-thu');
  if (form) {
    const xem = VN.$('#khac-thu-xem');
    const ve = () => VN.veKhacChu(xem, form.querySelector('#khac-thu-chu').value.trim(), form['kieu-thu'].value, form['mau-thu'].value);
    form.addEventListener('input', ve); form.addEventListener('change', ve);
    form.addEventListener('submit', (e) => e.preventDefault());
    // Chờ phông chữ tải xong để bản xem trước đúng kiểu chữ
    (document.fonts ? document.fonts.ready : Promise.resolve()).then(ve); ve();
  }
})();
