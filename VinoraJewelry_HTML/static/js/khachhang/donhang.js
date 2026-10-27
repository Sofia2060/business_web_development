/* =====================================================================
   5.2.7 QUẢN LÝ ĐƠN HÀNG (FR12, FR13, FR14)
   - Danh sách theo trạng thái (Chờ xử lý / Đang giao / Đã nhận / Đã hủy), tìm theo mã hoặc tên
   - Chi tiết đơn (?ma=): tiến trình, sản phẩm, size, chữ khắc, tiền, thanh toán, nhật ký (NFR8)
   - Hủy đơn -> popup giữ chân 5.2.6 (huydon.js)
   - "Đã nhận được hàng" (chỉ đơn Đang giao) -> chuyển sang trang Kích hoạt thẻ bảo hành & Đánh giá
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const khuDs = VN.$('#dh-danh-sach'); const khuCt = VN.$('#dh-chi-tiet');
  if (!khuDs) return;
  const u = VN.taiKhoan.yeuCau(); if (!u) return;

  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  const TAB = [['tat-ca', 'Tất cả'], ['Pending', 'Chờ xử lý'], ['Shipping', 'Đang giao'], ['Delivered', 'Đã nhận'], ['Cancelled', 'Đã hủy']];
  const tt = { tab: VN.thamSo('tab') || 'tat-ca', tim: '' };
  if (!TAB.some(([k]) => k === tt.tab)) tt.tab = 'tat-ca';

  const nhanTT = (don) => { const t = VN.TRANG_THAI_DON[don.trangThai]; return `<span class="nhan ${t.lop}">${t.ten}</span>`; };
  const nhanThanhToan = (don) => {
    const t = VN.TRANG_THAI_TT[don.thanhToan.trangThai];
    if (don.thanhToan.phuongThuc === 'COD' && don.thanhToan.trangThai === 'Pending') return '<span class="nhan">Thanh toán khi nhận</span>';
    return `<span class="nhan ${t.lop}">${t.ten}</span>`;
  };
  const chuaThanhToanOnline = (d) => d.trangThai === 'Pending' && d.thanhToan.phuongThuc !== 'COD' && d.thanhToan.trangThai !== 'Success';
  const chiTietDong = (d) => [d.ma, d.mau, d.size ? 'Size ' + d.size : ''].filter(Boolean).map(VN.thoat).join(' · ');
  const khacHtml = (d) => (d.khacChu ? `<span class="dh-khac">Khắc “<span class="kieu-${VN.thoat(d.kieuChu || 'co-dien')}">${VN.thoat(d.khacChu)}</span>” · ${TEN_KIEU[d.kieuChu] || 'Cổ điển'}</span>` : '');

  /* Nút thao tác theo trạng thái đơn */
  const nutThaoTac = (don, chiTiet = false) => {
    const n = [];
    if (don.trangThai === 'Shipping') n.push(`<button type="button" class="nut nut--chinh nut--nho" data-tac="da-nhan" data-ma="${don.ma}">${VN.bt('xac-nhan')} Đã nhận được hàng</button>`);
    if (chuaThanhToanOnline(don)) n.push(`<a class="nut nut--chinh nut--nho" href="${VN.url('ketQuaDatHang', { ma: don.ma })}">${VN.bt('the')} Hoàn tất thanh toán</a>`);
    if (don.trangThai === 'Delivered') {
      n.push(don.daDanhGia
        ? `<a class="nut nut--vien nut--nho" href="${VN.url('kichHoatBaoHanh', { don: don.ma })}">${VN.bt('khien')} Thẻ bảo hành</a>`
        : `<a class="nut nut--chinh nut--nho" href="${VN.url('kichHoatBaoHanh', { don: don.ma })}#danh-gia">${VN.bt('sao')} Đánh giá &amp; xem thẻ</a>`);
    }
    if (!chiTiet) n.push(`<a class="nut nut--vien nut--nho" href="${VN.url('donHang', { ma: don.ma })}" data-xem="${don.ma}">Xem chi tiết</a>`);
    if (['Delivered', 'Cancelled'].includes(don.trangThai)) n.push(`<button type="button" class="nut nut--vien nut--nho" data-tac="mua-lai" data-ma="${don.ma}">${VN.bt('doi-tra')} Mua lại</button>`);
    if (VN.donHang.coTheHuy(don)) n.push(`<button type="button" class="nut nut--chu nut-huy-don" data-tac="huy" data-ma="${don.ma}">Hủy đơn</button>`);
    if (don.trangThai === 'Pending') n.push(`<button type="button" class="nut nut--chu nut-mo-phong" data-tac="mo-phong" data-ma="${don.ma}" title="Chỉ dùng khi trình diễn">Mô phỏng: cửa hàng giao hàng</button>`);
    return n.join('');
  };

  /* ================= DANH SÁCH ================= */
  const veDanhSach = () => {
    const tat = VN.donHang.cuaToi();
    const dem = (k) => (k === 'tat-ca' ? tat.length : tat.filter((d) => d.trangThai === k).length);
    VN.$('#dh-tab').innerHTML = TAB.map(([k, ten]) => `<button type="button" role="tab" data-tab="${k}" aria-selected="${k === tt.tab}">${ten}<span class="dem">${dem(k)}</span></button>`).join('');
    const tu = VN.khongDau(tt.tim.trim());
    const ds = tat.filter((d) => (tt.tab === 'tat-ca' || d.trangThai === tt.tab)
      && (!tu || VN.khongDau(d.ma + ' ' + d.sanPham.map((s) => s.ten + ' ' + s.ma).join(' ')).includes(tu)));
    VN.$('#dh-demo').hidden = !tat.some((d) => d.trangThai === 'Pending');
    const khung = VN.$('#dh-ds');
    if (!tat.length) {
      khung.innerHTML = `<div class="trong-rong khoi-tk"><div class="trong-rong__bieu-tuong">${VN.bt('hop-hang')}</div><h2 class="t-3">Bạn chưa có đơn hàng nào</h2>
        <p>Khi đặt hàng, đơn sẽ xuất hiện tại đây để bạn theo dõi giao hàng và kích hoạt thẻ bảo hành.</p><a class="nut nut--chinh" href="${VN.url('sanPham')}">Khám phá trang sức</a></div>`;
      return;
    }
    if (!ds.length) { khung.innerHTML = `<div class="trong-rong khoi-tk"><p>Không có đơn hàng phù hợp${tu ? ` với “${VN.thoat(tt.tim)}”` : ''}.</p></div>`; return; }
    khung.innerHTML = ds.map((don) => {
      const sl = don.sanPham.reduce((a, d) => a + d.soLuong, 0);
      return `<article class="the-don the-don--${don.trangThai.toLowerCase()}">
        <header class="the-don__dau">
          <div><p class="the-don__ma">Đơn <a href="${VN.url('donHang', { ma: don.ma })}" data-xem="${don.ma}">${VN.thoat(don.ma)}</a></p><p class="chu-rat-nho chu-phu">Đặt ${VN.ngayGio(don.ngayDat)}</p></div>
          <div class="the-don__nhan">${nhanTT(don)}${nhanThanhToan(don)}</div>
        </header>
        <ul class="the-don__sp">${don.sanPham.map((d) => `<li>
          <span class="the-don__anh"><img src="${VN.anh(d.anh)}" alt="" width="72" height="72" loading="lazy"${VN.laAnhChup(d.anh) ? ' class="la-anh-chup"' : ''}></span>
          <span class="the-don__chu"><a href="${VN.urlSanPham(d.ma)}">${VN.thoat(d.ten)}</a><small>${chiTietDong(d)} · SL ${d.soLuong}</small>${khacHtml(d)}</span>
          <span class="the-don__gia so-deu">${VN.tien(d.donGia * d.soLuong)}</span></li>`).join('')}</ul>
        ${don.giuChan && don.giuChan.daApDung && don.trangThai !== 'Cancelled' ? `<p class="the-don__giu">${VN.bt('qua', 'bt--nho')} Bạn đã giữ lại đơn và nhận voucher ${VN.thoat(don.giuChan.maVoucher)} (−${VN.tien(don.giuChan.giam)})</p>` : ''}
        <footer class="the-don__chan">
          <p>${sl} sản phẩm · Tổng <strong class="so-deu">${VN.tien(don.tongTien)}</strong></p>
          <div class="the-don__nut">${nutThaoTac(don)}</div>
        </footer>
      </article>`;
    }).join('');
  };
  VN.$('#dh-tab').addEventListener('click', (e) => {
    const b = e.target.closest('[data-tab]'); if (!b) return;
    tt.tab = b.dataset.tab;
    history.replaceState(null, '', VN.url('donHang', tt.tab === 'tat-ca' ? {} : { tab: tt.tab }));
    veDanhSach();
  });
  VN.$('#dh-tim').addEventListener('submit', (e) => e.preventDefault());
  VN.$('#dh-o-tim').addEventListener('input', VN.chongDoi((e) => { tt.tim = e.target.value; veDanhSach(); }, 150));

  /* ================= CHI TIẾT ================= */
  const BUOC = [['Pending', 'Đặt hàng', 'hop-hang'], ['Shipping', 'Đang giao', 'xe-giao'], ['Delivered', 'Đã nhận hàng', 'xac-nhan'], ['BaoHanh', 'Kích hoạt bảo hành', 'khien']];
  const veChiTiet = (ma) => {
    const don = VN.donHang.lay(ma);
    khuDs.hidden = true; khuCt.hidden = false;
    VN.$('#dh-tieu-de').textContent = don ? `Đơn hàng ${don.ma}` : 'Không tìm thấy đơn hàng';
    VN.$('#dh-duong-dan').innerHTML = `<li><a href="${VN.url('trangChu')}">Trang chủ</a></li><li><a href="${VN.url('donHang')}" data-ve-ds>Đơn hàng của tôi</a></li><li aria-current="page">${VN.thoat(ma)}</li>`;
    if (!don) {
      khuCt.innerHTML = `<div class="trong-rong khoi-tk"><p>Đơn <strong>${VN.thoat(ma)}</strong> không thuộc tài khoản đang đăng nhập.</p><a class="nut nut--chinh nut--nho" href="${VN.url('donHang')}" data-ve-ds>Về danh sách đơn</a></div>`;
      return;
    }
    VN.$('#dh-mo-ta').innerHTML = `Đặt lúc ${VN.ngayGio(don.ngayDat)} · ${nhanTT(don)} ${nhanThanhToan(don)}`;
    const huy = don.trangThai === 'Cancelled';
    const coThe = VN.baoHanh.theoDon(don.ma).length > 0;
    const moc = { Pending: don.ngayDat, Shipping: don.ngayGiao || (don.lichSu.find((l) => l.trangThai === 'Shipping') || {}).luc, Delivered: don.ngayNhan, BaoHanh: coThe ? don.ngayNhan : null };
    const thuTu = ['Pending', 'Shipping', 'Delivered'].indexOf(don.trangThai) + (coThe ? 1 : 0);
    const tienTrinh = huy
      ? `<div class="tien-trinh tien-trinh--huy"><span class="tien-trinh__bt">${VN.bt('huy')}</span><div><strong>Đơn hàng đã hủy</strong><p>${VN.ngayGio(don.yeuCauHuy && don.yeuCauHuy.luc || don.ngayDat)} · Lý do: ${VN.thoat((don.yeuCauHuy && don.yeuCauHuy.lyDo) || '—')}${don.yeuCauHuy && don.yeuCauHuy.ghiChu ? ` – ${VN.thoat(don.yeuCauHuy.ghiChu)}` : ''}</p>${don.thanhToan.trangThai === 'Refunded' ? `<p>Đã hoàn ${VN.tien(don.tongTien)} về ${VN.thoat(VN.TEN_THANH_TOAN[don.thanhToan.phuongThuc])}.</p>` : ''}</div></div>`
      : `<ol class="tien-trinh">${BUOC.map(([k, ten, bt], i) => `<li class="${i < thuTu ? 'da-xong' : i === thuTu ? 'dang-o' : ''}">
          <span class="tien-trinh__bt">${VN.bt(bt)}</span><strong>${ten}</strong><small>${moc[k] && i <= thuTu ? VN.ngayGio(moc[k]) : i === thuTu + 1 && k === 'Shipping' ? 'Chờ cửa hàng xác nhận' : ''}</small></li>`).join('')}</ol>`;
    const nn = don.nguoiNhan;
    khuCt.innerHTML = `
      <div class="dh-ct__dau"><a class="nut nut--chu" href="${VN.url('donHang')}" data-ve-ds>${VN.bt('mui-ten-trai', 'bt--nho')} Tất cả đơn hàng</a><div class="the-don__nut">${nutThaoTac(don, true)}</div></div>
      <section class="khoi-tk">${tienTrinh}</section>
      <div class="dh-ct__luoi">
        <section class="khoi-tk" aria-labelledby="td-sp-dh">
          <div class="khoi-tk__dau"><div><p class="nhan-tren">Sản phẩm</p><h2 id="td-sp-dh">${don.sanPham.reduce((a, d) => a + d.soLuong, 0)} sản phẩm</h2></div></div>
          <ul class="the-don__sp the-don__sp--ct">${don.sanPham.map((d) => `<li>
            <a class="the-don__anh" href="${VN.urlSanPham(d.ma)}"><img src="${VN.anh(d.anh)}" alt="" width="96" height="96"${VN.laAnhChup(d.anh) ? ' class="la-anh-chup"' : ''}></a>
            <span class="the-don__chu"><a href="${VN.urlSanPham(d.ma)}">${VN.thoat(d.ten)}</a><small>${chiTietDong(d)} · ${VN.thoat(d.chatLieu)}</small><small>${VN.tien(d.donGia)} × ${d.soLuong}</small>${khacHtml(d)}</span>
            <span class="the-don__gia so-deu">${VN.tien(d.donGia * d.soLuong)}</span></li>`).join('')}</ul>
          <dl class="dong-tien">
            <div><dt>Tạm tính</dt><dd class="so-deu">${VN.tien(don.tamTinh)}</dd></div>
            ${don.giamGia ? `<div class="dong-tien__giam"><dt>Mã ưu đãi <span class="nhan nhan--vang nhan--tron">${VN.thoat(don.maUuDai)}</span></dt><dd class="so-deu">−${VN.tien(don.giamGia)}</dd></div>` : ''}
            ${don.giuChan && don.giuChan.daApDung ? `<div class="dong-tien__giam"><dt>Ưu đãi giữ đơn <span class="nhan nhan--vang nhan--tron">${VN.thoat(don.giuChan.maVoucher)}</span></dt><dd class="so-deu">−${VN.tien(don.giuChan.giam)}</dd></div>` : ''}
            <div><dt>${VN.thoat(don.giaoHang.ten)}</dt><dd class="so-deu">${don.phiGiao ? VN.tien(don.phiGiao) : '<span class="chu-ngoc">Miễn phí</span>'}</dd></div>
            <div class="dong-tien__tong"><dt>Tổng thanh toán</dt><dd class="so-deu">${VN.tien(don.tongTien)}</dd></div>
          </dl>
        </section>
        <div class="dh-ct__phai">
          <section class="khoi-tk">
            <p class="nhan-tren">Giao hàng</p>
            <dl class="kq-thong-tin kq-thong-tin--gon">
              <div><dt>Người nhận</dt><dd>${VN.thoat(nn.hoTen)}<br><span class="so-deu">${VN.thoat(nn.sdt)}</span></dd></div>
              <div><dt>Địa chỉ</dt><dd>${VN.thoat(VN.diaChiDay(nn))}</dd></div>
              <div><dt>Hình thức</dt><dd>${VN.thoat(don.giaoHang.ten)}</dd></div>
              ${nn.ghiChu ? `<div><dt>Ghi chú</dt><dd>${VN.thoat(nn.ghiChu)}</dd></div>` : ''}
              ${don.goiQua ? `<div><dt>Quà tặng</dt><dd>Gói quà Vinora${don.loiNhan ? `<br>Thiệp: “${VN.thoat(don.loiNhan)}”` : ''}</dd></div>` : ''}
            </dl>
          </section>
          <section class="khoi-tk">
            <p class="nhan-tren">Thanh toán</p>
            <dl class="kq-thong-tin kq-thong-tin--gon">
              <div><dt>Phương thức</dt><dd>${VN.thoat(VN.TEN_THANH_TOAN[don.thanhToan.phuongThuc])}</dd></div>
              <div><dt>Trạng thái</dt><dd>${nhanThanhToan(don)}</dd></div>
              ${don.thanhToan.maGiaoDich ? `<div><dt>Mã giao dịch</dt><dd class="so-deu">${VN.thoat(don.thanhToan.maGiaoDich)}</dd></div>` : ''}
            </dl>
          </section>
        </div>
      </div>
      <section class="khoi-tk" aria-labelledby="td-nhat-ky">
        <div class="khoi-tk__dau"><div><p class="nhan-tren">Nhật ký đơn hàng</p><h2 id="td-nhat-ky">Lịch sử xử lý</h2><p>Mọi thay đổi trạng thái, thanh toán và ưu đãi đều được ghi lại kèm thời điểm và người thực hiện.</p></div></div>
        <ol class="nhat-ky">${don.lichSu.slice().reverse().map((l) => `<li><time datetime="${l.luc}">${VN.ngayGio(l.luc)}</time><div><p>${VN.thoat(l.noiDung)}</p><small>${VN.thoat(l.boi)} · ${VN.TRANG_THAI_DON[l.trangThai] ? VN.TRANG_THAI_DON[l.trangThai].ten : ''}</small></div></li>`).join('')}</ol>
      </section>`;
  };

  /* ================= ĐIỀU HƯỚNG & THAO TÁC ================= */
  const veTheoUrl = () => {
    const ma = VN.thamSo('ma');
    if (ma) veChiTiet(ma);
    else {
      khuCt.hidden = true; khuDs.hidden = false;
      VN.$('#dh-tieu-de').textContent = 'Đơn hàng của tôi';
      VN.$('#dh-mo-ta').textContent = 'Theo dõi trạng thái, thanh toán, hủy đơn khi còn chờ xử lý và xác nhận đã nhận hàng để kích hoạt thẻ bảo hành.';
      VN.$('#dh-duong-dan').innerHTML = `<li><a href="${VN.url('trangChu')}">Trang chủ</a></li><li><a href="${VN.url('taiKhoan')}">Tài khoản</a></li><li aria-current="page">Đơn hàng của tôi</li>`;
      veDanhSach();
    }
  };
  const lamMoi = () => { if (VN.thamSo('ma')) veChiTiet(VN.thamSo('ma')); else veDanhSach(); };
  window.addEventListener('popstate', veTheoUrl);

  document.addEventListener('click', async (e) => {
    const xem = e.target.closest('[data-xem]');
    if (xem) { e.preventDefault(); history.pushState(null, '', VN.url('donHang', { ma: xem.dataset.xem })); veTheoUrl(); window.scrollTo({ top: 0 }); return; }
    const ve = e.target.closest('[data-ve-ds]');
    if (ve) { e.preventDefault(); history.pushState(null, '', VN.url('donHang', tt.tab === 'tat-ca' ? {} : { tab: tt.tab })); veTheoUrl(); return; }
    const b = e.target.closest('[data-tac]'); if (!b) return;
    const ma = b.dataset.ma; const don = VN.donHang.lay(ma);
    if (b.dataset.tac === 'huy') {
      const kq = await VN.moHuyDon(ma);
      if (kq) lamMoi();
    } else if (b.dataset.tac === 'da-nhan') {
      const dongY = await VN.xacNhan({
        nhan: `Đơn ${ma}`, tieuDe: 'Bạn đã nhận đủ sản phẩm?', chuDongY: 'Đã nhận được hàng', chuHuy: 'Chưa nhận',
        noiDung: `Xác nhận khi bạn đã kiểm tra ${don.sanPham.reduce((a, d) => a + d.soLuong, 0)} sản phẩm còn nguyên niêm phong, đúng size và chữ khắc. Hệ thống sẽ kích hoạt thẻ bảo hành điện tử trọn đời cho từng sản phẩm.`,
      });
      if (!dongY) return;
      try {
        VN.donHang.xacNhanDaNhan(ma);
        location.href = VN.url('kichHoatBaoHanh', { don: ma });
      } catch (loi) { VN.thongBao({ tieuDe: 'Không xác nhận được', noiDung: loi.message, loai: 'loi' }); }
    } else if (b.dataset.tac === 'mo-phong') {
      VN.donHang.moPhongGiaoHang(ma);
      VN.thongBao({ tieuDe: 'Đơn đã chuyển sang Đang giao', noiDung: 'Bây giờ có thể trình diễn nút “Đã nhận được hàng”.', loai: 'thanh-cong' });
      lamMoi();
    } else if (b.dataset.tac === 'mua-lai') {
      const { sp } = await VN.duLieu.coBan();
      let them = 0;
      don.sanPham.forEach((d) => {
        const s = sp.theoMa[d.ma]; if (!s || !s.coTheMua) return;
        const dong = { ma: d.ma, soLuong: d.soLuong };
        if (d.mau) dong.mau = d.mau; if (d.size) dong.size = d.size;
        if (d.khacChu) { dong.khacChu = d.khacChu; dong.kieuChu = d.kieuChu; }
        VN.gioHang.them(dong); them += d.soLuong;
      });
      if (them) VN.moGioMini();
      else VN.thongBao({ tieuDe: 'Sản phẩm hiện không còn bán trực tuyến', loai: 'loi' });
    }
  });

  const batDau = () => veTheoUrl();
  if (u.email === VN.DEMO.email) VN.demo.damBaoDuLieu(u.id).then(batDau); else batDau();
})();
