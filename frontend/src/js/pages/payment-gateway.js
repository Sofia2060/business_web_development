/* =====================================================================
   CỔNG THANH TOÁN SANDBOX (MÔ PHỎNG) – FR11
   VN.congThanhToan.mo(don) -> Promise<{ok, lyDo}>: ok = true khi giao dịch thành công.
   Kết quả được ghi vào đơn bằng VN.donHang.ghiThanhToan (Pending -> Success / Failed).
   VN.qrMinhHoa(chuoi): vẽ mã QR minh họa (SVG) – KHÔNG phải mã QR thanh toán thật.
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;

  /* Mã QR minh họa: lưới 29×29 sinh giả ngẫu nhiên từ nội dung + 3 ô định vị như QR thật */
  VN.qrMinhHoa = (chuoi, coDau = true) => {
    const n = 29; let h = 2166136261;
    for (let i = 0; i < chuoi.length; i++) { h ^= chuoi.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
    const ngauNhien = () => { h ^= h << 13; h >>>= 0; h ^= h >> 17; h ^= h << 5; h >>>= 0; return h / 4294967296; };
    const laDinhVi = (x, y) => [[0, 0], [n - 7, 0], [0, n - 7]].some(([a, b]) => x >= a - 1 && x <= a + 7 && y >= b - 1 && y <= b + 7);
    let o = '';
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
      if (laDinhVi(x, y)) continue;
      if (coDau && x > 10 && x < 18 && y > 10 && y < 18) continue;   // chừa chỗ logo ở giữa
      if (ngauNhien() > 0.52) o += `M${x} ${y}h1v1h-1z`;
    }
    const dinhVi = [[0, 0], [n - 7, 0], [0, n - 7]].map(([a, b]) => `<path d="M${a} ${b}h7v7h-7z M${a + 1} ${b + 1}v5h5v-5z" fill-rule="evenodd"/><path d="M${a + 2} ${b + 2}h3v3h-3z"/>`).join('');
    const logo = coDau ? `<rect x="11.5" y="11.5" width="6" height="6" fill="#fff"/><path d="M14.5 12.4l1.9 2.1-1.9 2.1-1.9-2.1z" fill="#B08D57"/>` : '';
    return `<svg viewBox="-2 -2 ${n + 4} ${n + 4}" shape-rendering="crispEdges" aria-hidden="true"><rect x="-2" y="-2" width="${n + 4}" height="${n + 4}" fill="#fff"/><g fill="#1A1714"><path d="${o}"/>${dinhVi}</g>${logo}</svg>`;
  };

  const hop = VN.$('#cong-tt');
  if (!hop) return;
  const buoc = (ten) => VN.$$('[data-ct-buoc]', hop).forEach((b) => { b.hidden = b.dataset.ctBuoc !== ten; });
  const THONG_TIN = {
    VNPAY: { ten: 'Cổng VNPay', logo: 'VP', mau: '#005BAA' },
    MOMO: { ten: 'Ví MoMo', logo: 'Mo', mau: '#A50064' },
  };
  let henGio = null; let ketThuc = null; let donDangTT = null;

  const dong = (thanhCong, lyDo = '') => {
    if (!ketThuc) return;
    const xong = ketThuc; ketThuc = null;
    clearInterval(henGio);
    let ok = thanhCong;
    try { VN.donHang.ghiThanhToan(donDangTT.ma, thanhCong); } catch (loi) { ok = false; lyDo = loi.message; }   // đơn đã quá hạn và tự hủy
    if (hop.open) hop.close(ok ? 'thanh-cong' : 'that-bai');
    xong({ ok, lyDo });
  };
  // Cổng thanh toán không đóng khi bấm ra ngoài (tránh mất giao dịch); đóng bằng Esc = hủy giao dịch
  hop.dataset.daGan = '1';
  hop.addEventListener('close', () => { document.documentElement.classList.remove('khoa-cuon'); dong(false, 'Khách hàng đóng cổng thanh toán'); });
  const xuLy = (thanhCong) => {
    buoc('xu-ly');
    setTimeout(() => dong(thanhCong, thanhCong ? '' : 'Giao dịch không thành công'), 1300);
  };

  VN.$('[data-ct-buoc="the"]', hop).addEventListener('submit', (e) => {
    e.preventDefault();
    const soThe = e.target.soThe.value.replace(/\s/g, '');
    const f = e.target;
    const okSo = /^\d{16,19}$/.test(soThe); const okTen = f.chuThe.value.trim().length >= 3; const okNgay = /^(0[1-9]|1[0-2])\/\d{2}$/.test(f.ngay.value.trim());
    VN.baoLoiTruong(f.soThe, okSo ? '' : 'Số thẻ gồm 16 – 19 chữ số.');
    VN.baoLoiTruong(f.chuThe, okTen ? '' : 'Nhập tên in trên thẻ (không dấu).');
    VN.baoLoiTruong(f.ngay, okNgay ? '' : 'Ngày phát hành dạng MM/YY.');
    if (!okSo || !okTen || !okNgay) return;
    buoc('otp');
    setTimeout(() => VN.$('#ct-otp').focus(), 50);
  });
  VN.$('[data-ct-buoc="otp"]', hop).addEventListener('submit', (e) => {
    e.preventDefault();
    const otp = e.target.otp.value.trim();
    if (otp !== '123456') { VN.baoLoiTruong(e.target.otp, 'Mã OTP chưa đúng, vui lòng kiểm tra tin nhắn từ ngân hàng.'); e.target.otp.select(); return; }
    VN.baoLoiTruong(e.target.otp, '');
    xuLy(true);
  });
  VN.$('[data-ct-xac-nhan-qr]', hop).addEventListener('click', () => xuLy(true));
  VN.$('[data-ct-huy]', hop).addEventListener('click', () => dong(false, 'Khách hàng hủy giao dịch'));
  hop.addEventListener('cancel', (e) => { e.preventDefault(); dong(false, 'Khách hàng hủy giao dịch'); });

  VN.congThanhToan = {
    mo(don) {
      return new Promise((xong) => {
        donDangTT = don; ketThuc = xong;
        const tt = THONG_TIN[don.thanhToan.phuongThuc] || THONG_TIN.VNPAY;
        VN.$('[data-ct-ten]', hop).textContent = tt.ten;
        const logo = VN.$('[data-ct-logo]', hop); logo.textContent = tt.logo; logo.style.background = tt.mau;
        VN.$('[data-ct-ma]', hop).textContent = don.ma;
        VN.$('[data-ct-tien]', hop).textContent = VN.tien(don.tongTien);
        VN.$$('form', hop).forEach((f) => { f.otp && (f.otp.value = ''); VN.$$('.truong', f).forEach((t) => t.classList.remove('co-loi')); VN.$$('.loi-truong', f).forEach((p) => { p.textContent = ''; }); });
        if (don.thanhToan.phuongThuc === 'MOMO') {
          VN.$('[data-ct-qr]', hop).innerHTML = VN.qrMinhHoa('MOMO|' + don.ma + '|' + don.tongTien);
          buoc('qr');
        } else buoc('the');
        // Đồng hồ đếm ngược 15 phút như cổng thật
        let con = 15 * 60;
        const dem = VN.$('[data-ct-dem]', hop);
        const ve = () => { dem.textContent = `${String(Math.floor(con / 60)).padStart(2, '0')}:${String(con % 60).padStart(2, '0')}`; };
        ve(); clearInterval(henGio);
        henGio = setInterval(() => { con -= 1; ve(); if (con <= 0) dong(false, 'Hết thời gian thanh toán'); }, 1000);
        VN.moHopThoai(hop);
      });
    },
  };
})();
