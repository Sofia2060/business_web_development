/* =====================================================================
   QUẢN TRỊ – TỔNG QUAN: chỉ số chính, doanh thu 14 ngày (SVG), việc cần xử lý,
   đơn mới nhất, sản phẩm bán chạy
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora; const qt = VN.qt;
  if (!qt || qt.chan || !VN.$('#qt-so-lieu')) return;

  /** Doanh thu ghi nhận: đơn đã thanh toán và không bị hoàn tiền */
  const daThu = (d) => d.thanhToan.trangThai === 'Success';
  const ngayThu = (d) => new Date(d.thanhToan.luc || d.ngayNhan || d.ngayDat);

  const veBieuDo = (dsDon) => {
    const ngay = Array.from({ length: 14 }, (_, i) => { const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - 13 + i); return d; });
    const tien = ngay.map((n) => dsDon.filter((d) => daThu(d) && VN.ngayIso(ngayThu(d)) === VN.ngayIso(n)).reduce((t, d) => t + d.tongTien, 0));
    const max = Math.max(...tien, 1); const W = 700; const H = 230; const le = 40; const cot = (W - le) / 14;
    VN.$('#qt-tong-14').textContent = VN.tien(tien.reduce((a, b) => a + b, 0));
    VN.$('#qt-bieu-do').innerHTML = `<svg class="qt-bieu-do" viewBox="0 0 ${W} ${H + 30}" role="img" aria-label="Biểu đồ doanh thu 14 ngày">
      ${[0, 0.5, 1].map((k) => `<line x1="${le}" x2="${W}" y1="${H - k * (H - 10)}" y2="${H - k * (H - 10)}"></line><text x="0" y="${H - k * (H - 10) + 4}">${k ? (max * k / 1e6).toLocaleString('vi-VN', { maximumFractionDigits: 1 }) + 'tr' : '0'}</text>`).join('')}
      ${tien.map((t, i) => { const h = t / max * (H - 10); return `<rect class="cot" x="${le + i * cot + cot * 0.18}" y="${H - h}" width="${cot * 0.64}" height="${Math.max(h, t ? 2 : 0)}"><title>${VN.ngay(ngay[i])}: ${VN.tien(t)}</title></rect>
        ${i % 2 === 0 || i === 13 ? `<text x="${le + i * cot + cot / 2}" y="${H + 20}" text-anchor="middle">${VN.ngay(ngay[i]).slice(0, 5)}</text>` : ''}`; }).join('')}
    </svg>`;
  };

  const ve = async () => {
    VN.donHang.tuHuyQuaHan();
    const don = VN.donHang.tatCa(); const pa = VN.hoTro.tatCa(); const lich = VN.lichHen.tatCa(); const dg = VN.danhGia.tatCa();
    VN.$('#qt-chua-co-du-lieu').hidden = don.length > 0;
    VN.$('#qt-hom-nay').textContent = `${VN.thu(new Date())}, ${VN.ngay(new Date())}`;
    const bayNgay = Date.now() - 7 * 86400000;
    const doanhThu = don.filter(daThu).reduce((t, d) => t + d.tongTien, 0);
    const choXuLy = don.filter((d) => d.trangThai === 'Pending');
    const diemTb = dg.length ? dg.reduce((t, x) => t + x.soSao, 0) / dg.length : 0;
    const o = [
      ['', 'Doanh thu đã thu', VN.tien(doanhThu), `${don.filter(daThu).length} đơn đã thanh toán`, VN.url('qtDonHang')],
      ['xanh', 'Đơn mới 7 ngày', don.filter((d) => new Date(d.ngayDat) >= bayNgay).length, `${don.length} đơn từ trước đến nay`, VN.url('qtDonHang')],
      ['cam', 'Đơn chờ xử lý', choXuLy.length, `${choXuLy.filter(qt.chuaTra).length} đơn đang chờ khách thanh toán`, VN.url('qtDonHang', { tt: 'Pending' })],
      ['do', 'Phản ánh đang mở', pa.filter((x) => x.trangThai !== 'Resolved').length, `${pa.length} phản ánh đã nhận`, VN.url('qtPhanAnh')],
      ['ngoc', 'Điểm đánh giá', dg.length ? diemTb.toLocaleString('vi-VN', { maximumFractionDigits: 1 }) + ' / 5' : '—', `${dg.length} đánh giá`, VN.url('qtDanhGia')],
    ];
    VN.$('#qt-so-lieu').innerHTML = o.map(([lop, ten, so, phu, url]) => `<a class="qt-o-so${lop ? ' qt-o-so--' + lop : ''}" href="${url}"><span>${ten}</span><strong>${so}</strong><small>${phu}</small></a>`).join('');
    veBieuDo(don);

    const viec = [
      ['qr', 'Đơn chuyển khoản chờ xác nhận tiền', choXuLy.filter((d) => d.thanhToan.phuongThuc === 'BANK' && d.thanhToan.trangThai !== 'Success').length, VN.url('qtDonHang', { tt: 'Pending' })],
      ['xe-giao', 'Đơn sẵn sàng giao (COD / đã thanh toán)', choXuLy.filter((d) => !qt.chuaTra(d)).length, VN.url('qtDonHang', { tt: 'Pending' })],
      ['doi-tra', 'Yêu cầu hoàn tiền chờ chuyển khoản', don.filter((d) => d.thanhToan.trangThai === 'RefundPending').length, VN.url('qtDonHang', { tt: 'hoan-tien' })],
      ['chat', 'Phản ánh chưa xử lý xong', pa.filter((x) => x.trangThai !== 'Resolved').length, VN.url('qtPhanAnh')],
      ['lich', 'Lịch hẹn chờ xác nhận', lich.filter((l) => l.trangThai === 'Pending').length, VN.url('qtBaoHanh')],
      ['sao', 'Đánh giá chưa phản hồi', dg.filter((x) => !x.phanHoi).length, VN.url('qtDanhGia')],
    ];
    VN.$('#qt-viec').innerHTML = viec.map(([bt, ten, n, url]) => `<li><a href="${url}">${VN.bt(bt)}<span>${ten}</span><b class="${n ? '' : 'khong'}">${n}</b></a></li>`).join('');

    const moi = don.slice().sort((a, b) => new Date(b.ngayDat) - new Date(a.ngayDat)).slice(0, 6);
    VN.$('#qt-don-moi').innerHTML = moi.length
      ? `<thead><tr><th>Mã đơn</th><th>Khách</th><th class="so">Tổng</th><th>Trạng thái</th></tr></thead><tbody>${moi.map((d) => { const k = qt.khach(d); return `<tr>
        <td><a class="ma lien-ket" href="${VN.url('qtDonHang', { ma: d.ma })}">${VN.thoat(d.ma)}</a><small>${VN.ngayGio(d.ngayDat)}</small></td>
        <td>${VN.thoat(k.ten)}<small>${VN.thoat(k.sdt)}</small></td><td class="so">${VN.tien(d.tongTien)}</td><td>${qt.nhanDon(d)}</td></tr>`; }).join('')}</tbody>`
      : `<tbody><tr><td>${qt.trong('Chưa có đơn hàng.')}</td></tr></tbody>`;

    const { theoMa } = await VN.duLieu.sanPham();
    const dem = {};
    don.filter((d) => d.trangThai !== 'Cancelled').forEach((d) => d.sanPham.forEach((s) => { dem[s.ma] = dem[s.ma] || { ten: s.ten, anh: s.anh, sl: 0, tien: 0 }; dem[s.ma].sl += s.soLuong; dem[s.ma].tien += s.soLuong * s.donGia; }));
    const top = Object.entries(dem).sort((a, b) => b[1].sl - a[1].sl || b[1].tien - a[1].tien).slice(0, 6);
    VN.$('#qt-ban-chay').innerHTML = top.length
      ? `<thead><tr><th>Sản phẩm</th><th class="so">Đã bán</th><th class="so">Doanh số</th></tr></thead><tbody>${top.map(([ma, x]) => `<tr>
        <td><span class="qt-sp-nho"><img src="${VN.anh((theoMa[ma] && theoMa[ma].anh[0]) || x.anh)}" alt=""><span>${VN.thoat(x.ten)}<small>${VN.thoat(ma)}</small></span></span></td>
        <td class="so">${x.sl}</td><td class="so">${VN.tien(x.tien)}</td></tr>`).join('')}</tbody>`
      : `<tbody><tr><td>${qt.trong('Chưa có sản phẩm nào được bán.')}</td></tr></tbody>`;
  };

  VN.$('#qt-tao-mau').addEventListener('click', async () => {
    await VN.demo.khoiPhuc();
    VN.thongBao({ tieuDe: 'Đã tạo dữ liệu mẫu', noiDung: 'Tài khoản demo@vinora.vn / Vinora@2026 đã có 5 đơn hàng.', loai: 'thanh-cong' });
    ve(); qt.veKhung();
  });
  ['vinora:don-hang', 'vinora:ho-tro', 'vinora:lich-hen'].forEach((ten) => window.addEventListener(ten, VN.chongDoi(ve, 80)));
  window.addEventListener('storage', VN.chongDoi((e) => { if (/^vinora\./.test(e.key || '')) ve(); }, 120));
  ve();
})();
