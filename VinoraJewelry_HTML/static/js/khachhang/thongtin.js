/* =====================================================================
   TRANG THÔNG TIN & HỖ TRỢ – liên hệ (showroom XML + biểu mẫu), hướng dẫn size,
   chính sách giao hàng, chính sách bảo hành (đọc cấu hình tập trung cauhinh.json – NFR7)
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const trang = document.body.dataset.trang;

  /* ---------- Liên hệ ---------- */
  if (trang === 'lien-he') {
    const banDo = VN.$('#ban-do');
    const datBanDo = (c) => { banDo.src = 'https://maps.google.com/maps?q=' + encodeURIComponent(c.banDo) + '&z=15&output=embed'; };
    Promise.all([VN.duLieu.cuaHang(), VN.duLieu.cauHinh()]).then(([ds, ch]) => {
      VN.$('#lh-mo-ta').textContent = `Hotline ${ch.thuongHieu.hotline} · ${ch.thuongHieu.email} · ${ch.thuongHieu.gioLamViec}. ${ch.thuongHieu.ghiChu}`;
      VN.$('#ds-showroom').innerHTML = ds.map((c, i) => `<button type="button" class="the-showroom${i === 0 ? ' dang-chon' : ''}" data-cua-hang="${VN.thoat(c.ma)}" aria-pressed="${i === 0}">
        <strong>${VN.thoat(c.ten)}</strong><span>${VN.bt('ghim', 'bt--nho')} ${VN.thoat(c.diaChi)}</span><span>${VN.bt('dong-ho', 'bt--nho')} ${VN.thoat(c.gioMoCua)} · ${VN.bt('dien-thoai', 'bt--nho')} ${VN.thoat(c.dienThoai)}</span></button>`).join('');
      if (ds[0]) datBanDo(ds[0]);
      VN.$('#ds-showroom').addEventListener('click', (e) => {
        const b = e.target.closest('[data-cua-hang]'); if (!b) return;
        VN.$$('.the-showroom').forEach((x) => { const chon = x === b; x.classList.toggle('dang-chon', chon); x.setAttribute('aria-pressed', String(chon)); });
        datBanDo(ds.find((c) => c.ma === b.dataset.cuaHang));
      });
    });
    const f = VN.$('#form-lien-he');
    const u = VN.taiKhoan.hienTai();
    if (u) { f.hoTen.value = u.hoTen; f.sdt.value = u.sdt || ''; f.email.value = u.email; }
    const sp = VN.thamSo('sanpham');
    if (sp) { f.maSanPham.value = sp; f.chuDe.value = 'bao-gia'; f.noiDung.value = `Tôi muốn nhận báo giá sản phẩm ${sp} theo giá vàng hôm nay.`; }
    f.addEventListener('input', (e) => { if (e.target.closest('.co-loi')) VN.baoLoiTruong(e.target, ''); });
    f.addEventListener('submit', (e) => {
      e.preventDefault();
      const kt = (o, dk, m) => { VN.baoLoiTruong(o, dk ? '' : m); return dk; };
      const ok = [kt(f.hoTen, f.hoTen.value.trim().length >= 2, 'Vui lòng nhập họ tên.'), kt(f.sdt, VN.sdtHopLe(f.sdt.value), 'Số điện thoại gồm 10 số, bắt đầu bằng 03, 05, 07, 08 hoặc 09.'),
        kt(f.email, VN.emailHopLe(f.email.value), 'Email chưa hợp lệ.'), kt(f.chuDe, !!f.chuDe.value, 'Vui lòng chọn chủ đề.'), kt(f.noiDung, f.noiDung.value.trim().length >= 10, 'Lời nhắn tối thiểu 10 ký tự.')].every(Boolean);
      if (!ok) { VN.$('.co-loi input, .co-loi select, .co-loi textarea', f).focus(); return; }
      const ds = VN.kho.doc('lienHe', []);
      const ma = 'LHE' + Date.now().toString(36).toUpperCase();
      ds.push({ ma, luc: new Date().toISOString(), hoTen: f.hoTen.value.trim(), sdt: f.sdt.value, email: f.email.value.trim(), chuDe: f.chuDe.value, maSanPham: f.maSanPham.value.trim(), noiDung: f.noiDung.value.trim(), kenh: f.kenh.value });
      VN.kho.ghi('lienHe', ds); f.noiDung.value = '';
      VN.thongBao({ tieuDe: 'Đã gửi yêu cầu ' + ma, noiDung: 'Chuyên viên Vinora sẽ liên hệ lại trong giờ làm việc (mô phỏng – lưu trên trình duyệt).', loai: 'thanh-cong', thoiGian: 6000 });
    });
  }

  /* ---------- Hướng dẫn chọn size ---------- */
  if (trang === 'huong-dan-size') {
    VN.duLieu.bangSize().then((bs) => {
      const ds = bs.bangSize; const so = VN.so;
      VN.$('#bang-size-tt').insertAdjacentHTML('beforeend', `<thead><tr><th scope="col">Size (ni)</th><th scope="col" class="so">Chu vi (mm)</th><th scope="col" class="so">Đường kính (mm)</th><th scope="col" class="so">Size Mỹ (tham khảo)</th></tr></thead>
        <tbody>${ds.map((d) => `<tr data-size="${d.size}"><td>${d.size}</td><td class="so">${so(d.chuVi, 1)}</td><td class="so">${so(d.duongKinh, 1)}</td><td class="so">${so(d.sizeMy, 1)}</td></tr>`).join('')}</tbody>`);
      VN.$('#ghi-chu-size').textContent = `${bs.ghiChu} ${bs.goiYSize.nu}; ${bs.goiYSize.nam}.`;
      const f = VN.$('#may-tinh-size'); const kq = VN.$('#mt-kq');
      const tinh = () => {
        VN.$$('#bang-size-tt tr').forEach((tr) => tr.classList.remove('goi-y'));
        const v = parseFloat(String(f['mt-so'].value).replace(',', '.'));
        if (!v) { kq.textContent = 'Nhập số đo để xem size gợi ý.'; return; }
        const cv = f['mt-kieu'].value === 'chu-vi' ? v : v * 3.14;
        const d = ds.find((x) => x.chuVi >= cv - 0.3);
        if (cv < ds[0].chuVi - 1 || !d) { kq.textContent = 'Số đo nằm ngoài size 6 – 24. Vui lòng liên hệ để đặt size riêng.'; return; }
        kq.innerHTML = `Size gợi ý <strong>${d.size}</strong> · chu vi ${so(d.chuVi, 1)} mm`;
        VN.$(`#bang-size-tt tr[data-size="${d.size}"]`).classList.add('goi-y');
      };
      f.addEventListener('input', tinh); f.addEventListener('submit', (e) => { e.preventDefault(); tinh(); });
    });
  }

  /* ---------- Chính sách giao hàng ---------- */
  if (trang === 'chinh-sach-giao-hang') {
    VN.duLieu.cauHinh().then((ch) => {
      VN.$('#bang-giao').insertAdjacentHTML('beforeend', `<thead><tr><th scope="col">Phương thức</th><th scope="col">Thời gian</th><th scope="col">Khu vực</th><th scope="col" class="so">Phí</th></tr></thead><tbody>${ch.giaoHang.phuongThuc.map((p) => `<tr><td>${VN.thoat(p.ten)}</td><td>${VN.thoat(p.thoiGian)}</td><td>${p.apDung === 'toan-quoc' ? 'Toàn quốc' : p.apDung.map(VN.thoat).join(', ')}</td><td class="so">${VN.tien(p.phi)}${p.mienPhiTheoDon ? '<br><small>Miễn phí từ ' + VN.tien(ch.giaoHang.mienPhiTu) + '</small>' : ''}</td></tr>`).join('')}</tbody>`);
      VN.$('#mien-phi-chu').innerHTML = `Đơn từ <strong>${VN.tien(ch.giaoHang.mienPhiTu)}</strong> được miễn phí giao tiêu chuẩn có bảo hiểm. Mã <strong>FREESHIP</strong> miễn phí mọi phương thức.`;
      VN.$('#ds-thanh-toan').innerHTML = ch.thanhToan.map((t) => `<li><strong>${VN.thoat(t.ten)}</strong> – ${VN.thoat(t.moTa)}</li>`).join('');
      VN.$('#giu-chan-chu').textContent = `giảm ${ch.giuChanDon.phanTram}% giá trị hàng, tối đa ${VN.tien(ch.giuChanDon.toiDa)}`;
    });
  }

  /* ---------- Chính sách bảo hành ---------- */
  if (trang === 'chinh-sach-bao-hanh') {
    VN.duLieu.cauHinh().then((ch) => {
      VN.$('#bang-ql').insertAdjacentHTML('beforeend', `<thead><tr><th scope="col">Nội dung</th><th scope="col" class="so">Thời gian</th></tr></thead><tbody>${ch.baoHanh.quyenLoi.map((q) => `<tr><td>${VN.thoat(q.ten)}${q.chiChoNhan ? ' <small class="chu-phu">(áp dụng cho nhẫn)</small>' : ''}</td><td class="so">${VN.thoat(q.hienThi)}</td></tr>`).join('')}</tbody>`);
      VN.$('#bang-phi').insertAdjacentHTML('beforeend', `<thead><tr><th scope="col">Nội dung bảo hành</th><th scope="col" class="so">Chi phí</th></tr></thead><tbody>${ch.baoHanh.tinhPhi.map((p) => `<tr><td>${VN.thoat(p.ten)}</td><td class="so">${VN.thoat(p.chiPhi)}</td></tr>`).join('')}</tbody>`);
      VN.$('#so-ngay-dat').textContent = ch.baoHanh.datTruocToiDaNgay;
    });
  }
})();
