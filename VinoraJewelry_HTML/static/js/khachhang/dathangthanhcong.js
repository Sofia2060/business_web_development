/* =====================================================================
   KẾT QUẢ ĐẶT HÀNG (?ma=mã đơn) – FR10, FR11
   - COD: đặt hàng thành công, thanh toán khi nhận
   - VietQR: hiển thị thông tin chuyển khoản (minh họa) + mô phỏng ngân hàng báo có
   - VNPay / MoMo: thành công, hoặc thất bại -> thanh toán lại / đổi sang COD
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const khung = VN.$('#ket-qua');
  if (!khung) return;
  const u = VN.taiKhoan.yeuCau(); if (!u) return;
  const maDon = (VN.thamSo('ma') || '').trim();

  const TEN_KIEU = { 'co-dien': 'Cổ điển', 'hien-dai': 'Hiện đại', 'viet-tay': 'Viết tay' };
  const NGAN_HANG = { ten: 'Ngân hàng TMCP Ngoại thương (minh họa)', soTk: '0000 2026 1027', chuTk: 'CONG TY VINORA JEWELRY' };

  const ve = () => {
    const don = VN.donHang.lay(maDon);
    khung.removeAttribute('aria-busy');
    if (!don) {
      khung.innerHTML = `<div class="trong-rong"><div class="trong-rong__bieu-tuong">${VN.bt('hop-hang')}</div><h1 class="t-2">Không tìm thấy đơn hàng</h1>
        <p>Mã đơn ${maDon ? `<strong>${VN.thoat(maDon)}</strong> ` : ''}không thuộc tài khoản đang đăng nhập hoặc chưa được tạo.</p>
        <div class="hang hang--giua hang--quan"><a class="nut nut--chinh" href="${VN.url('donHang')}">Đơn hàng của tôi</a><a class="nut nut--vien" href="${VN.url('sanPham')}">Tiếp tục mua sắm</a></div></div>`;
      return;
    }
    const pt = don.thanhToan.phuongThuc; const tts = don.thanhToan.trangThai;
    const daHuy = don.trangThai === 'Cancelled';
    let trangThai; // [kiểu, biểu tượng, tiêu đề, mô tả]
    if (daHuy) trangThai = ['do', 'huy', 'Đơn hàng đã được hủy', 'Đơn hàng này đã hủy. Bạn có thể xem lại chi tiết trong mục Đơn hàng của tôi.'];
    else if (pt === 'COD') trangThai = ['ngoc', 'dau-tich', 'Đặt hàng thành công!', `Cảm ơn ${VN.thoat(VN.taiKhoan.tenGoi(u))}. Vinora sẽ xác nhận và đóng gói đơn hàng trong 24 giờ; bạn thanh toán khi nhận hàng.`];
    else if (tts === 'Success') trangThai = ['ngoc', 'dau-tich', 'Thanh toán thành công!', `Giao dịch <strong>${VN.thoat(don.thanhToan.maGiaoDich)}</strong> qua ${VN.thoat(VN.TEN_THANH_TOAN[pt])} đã được ghi nhận. Vinora đang chuẩn bị đơn hàng của bạn.`];
    else if (pt === 'BANK') trangThai = ['vang', 'qr', 'Hoàn tất chuyển khoản để xác nhận đơn', 'Đơn hàng đã được tạo và giữ hàng cho bạn. Vui lòng chuyển khoản theo thông tin bên dưới.'];
    else trangThai = ['do', 'canh-bao', 'Thanh toán chưa thành công', `Giao dịch qua ${VN.thoat(VN.TEN_THANH_TOAN[pt])} bị hủy hoặc không thành công. Đơn hàng vẫn được giữ – bạn có thể thanh toán lại hoặc chuyển sang thanh toán khi nhận hàng.`];
    const [kieu, bt, tieuDe, moTa] = trangThai;
    const nn = don.nguoiNhan;
    const ttTT = VN.TRANG_THAI_TT[tts] || { ten: tts, lop: '' };

    khung.innerHTML = `
      <section class="kq-dau kq-dau--${kieu}">
        <span class="kq-dau__bt">${VN.bt(bt, 'bt--lon')}</span>
        <h1>${tieuDe}</h1>
        <p>${moTa}</p>
        <div class="kq-dau__ma">
          <span>Mã đơn hàng</span><strong class="so-deu">${VN.thoat(don.ma)}</strong>
          <button type="button" class="nut-bt" data-sao="${VN.thoat(don.ma)}" aria-label="Sao chép mã đơn hàng">${VN.bt('sao-chep', 'bt--nho')}</button>
        </div>
        <p class="chu-nho chu-phu">Đặt lúc ${VN.ngayGio(don.ngayDat)} · ${don.sanPham.reduce((a, d) => a + d.soLuong, 0)} sản phẩm · ${VN.tien(don.tongTien)}</p>
      </section>

      ${!daHuy && pt === 'BANK' && tts !== 'Success' ? `
      <section class="kq-chuyen-khoan" aria-labelledby="td-ck">
        <div class="kq-chuyen-khoan__qr">${VN.qrMinhHoa('BANK|' + don.ma + '|' + don.tongTien)}<span class="chu-rat-nho chu-phu">Mã VietQR minh họa</span></div>
        <div class="kq-chuyen-khoan__chu">
          <h2 class="t-3" id="td-ck">Thông tin chuyển khoản</h2>
          <dl class="kq-ck">
            <div><dt>Ngân hàng</dt><dd>${NGAN_HANG.ten}</dd></div>
            <div><dt>Số tài khoản</dt><dd class="so-deu">${NGAN_HANG.soTk} <button type="button" class="nut-bt" data-sao="${NGAN_HANG.soTk.replace(/\s/g, '')}" aria-label="Sao chép số tài khoản">${VN.bt('sao-chep', 'bt--nho')}</button></dd></div>
            <div><dt>Chủ tài khoản</dt><dd>${NGAN_HANG.chuTk}</dd></div>
            <div><dt>Số tiền</dt><dd class="so-deu"><strong>${VN.tien(don.tongTien)}</strong></dd></div>
            <div><dt>Nội dung</dt><dd class="so-deu"><strong>${VN.thoat(don.ma)}</strong> <button type="button" class="nut-bt" data-sao="${VN.thoat(don.ma)}" aria-label="Sao chép nội dung chuyển khoản">${VN.bt('sao-chep', 'bt--nho')}</button></dd></div>
          </dl>
          <p class="hop-bao hop-bao--vang">${VN.bt('thong-tin')}<span>Thông tin ngân hàng là dữ liệu minh họa cho đồ án. Trong buổi trình diễn, bấm nút bên dưới để mô phỏng ngân hàng gửi thông báo đã nhận tiền.</span></p>
          <button type="button" class="nut nut--chinh" data-mo-phong-bao-co>Mô phỏng: ngân hàng báo đã nhận tiền</button>
        </div>
      </section>` : ''}

      ${!daHuy && ['VNPAY', 'MOMO'].includes(pt) && tts !== 'Success' ? `
      <section class="kq-thu-lai">
        <button type="button" class="nut nut--chinh" data-thanh-toan-lai>${VN.bt('the')} Thanh toán lại qua ${VN.thoat(VN.TEN_THANH_TOAN[pt])}</button>
        <button type="button" class="nut nut--vien" data-doi-cod>Chuyển sang thanh toán khi nhận hàng</button>
      </section>` : ''}

      <div class="kq-luoi">
        <section class="kq-khoi" aria-labelledby="td-tiep-theo">
          <h2 class="t-4" id="td-tiep-theo">Tiếp theo sẽ diễn ra</h2>
          <ol class="kq-buoc">
            <li class="${daHuy ? '' : 'dang-o'}"><strong>Cửa hàng xác nhận &amp; đóng gói</strong><span>Trong vòng 24 giờ, đơn ở trạng thái Chờ xử lý – bạn vẫn có thể tự hủy đơn.</span></li>
            <li><strong>${VN.thoat(don.giaoHang.ten)}</strong><span>Đóng gói niêm phong, bảo hiểm toàn bộ giá trị đơn hàng.</span></li>
            <li><strong>Bấm “Đã nhận được hàng”</strong><span>Trong mục Đơn hàng của tôi sau khi kiểm tra sản phẩm.</span></li>
            <li><strong>Thẻ bảo hành điện tử tự kích hoạt</strong><span>Mỗi sản phẩm một thẻ trọn đời, đặt lịch hậu mãi ngay trên website.</span></li>
          </ol>
        </section>

        <section class="kq-khoi" aria-labelledby="td-tom-tat-dh">
          <h2 class="t-4" id="td-tom-tat-dh">Tóm tắt đơn hàng</h2>
          <ul class="ds-tt-sp">${don.sanPham.map((d) => `
            <li class="tt-sp">
              <span class="tt-sp__anh"><img src="${VN.anh(d.anh)}" alt="" width="72" height="72"${VN.laAnhChup(d.anh) ? ' class="la-anh-chup"' : ''}><span class="tt-sp__sl so-deu">${d.soLuong}</span></span>
              <span class="tt-sp__chu"><strong>${VN.thoat(d.ten)}</strong><small>${[d.ma, d.mau, d.size ? 'Size ' + d.size : ''].filter(Boolean).map(VN.thoat).join(' · ')}</small>
              ${d.khacChu ? `<small class="tt-sp__khac">Khắc “<span class="kieu-${VN.thoat(d.kieuChu || 'co-dien')}">${VN.thoat(d.khacChu)}</span>” · ${TEN_KIEU[d.kieuChu] || 'Cổ điển'}</small>` : ''}</span>
              <span class="tt-sp__gia so-deu">${VN.tien(d.donGia * d.soLuong)}</span>
            </li>`).join('')}</ul>
          <dl class="dong-tien">
            <div><dt>Tạm tính</dt><dd class="so-deu">${VN.tien(don.tamTinh)}</dd></div>
            ${don.giamGia ? `<div class="dong-tien__giam"><dt>Ưu đãi <span class="nhan nhan--vang nhan--tron">${VN.thoat(don.maUuDai)}</span></dt><dd class="so-deu">−${VN.tien(don.giamGia)}</dd></div>` : ''}
            ${don.giuChan && don.giuChan.daApDung ? `<div class="dong-tien__giam"><dt>Ưu đãi giữ đơn <span class="nhan nhan--vang nhan--tron">${VN.thoat(don.giuChan.maVoucher)}</span></dt><dd class="so-deu">−${VN.tien(don.giuChan.giam)}</dd></div>` : ''}
            <div><dt>${VN.thoat(don.giaoHang.ten)}</dt><dd class="so-deu">${don.phiGiao ? VN.tien(don.phiGiao) : '<span class="chu-ngoc">Miễn phí</span>'}</dd></div>
            <div class="dong-tien__tong"><dt>Tổng thanh toán</dt><dd class="so-deu">${VN.tien(don.tongTien)}</dd></div>
          </dl>
          <dl class="kq-thong-tin">
            <div><dt>Người nhận</dt><dd>${VN.thoat(nn.hoTen)} · <span class="so-deu">${VN.thoat(nn.sdt)}</span><br>${VN.thoat(VN.diaChiDay(nn))}</dd></div>
            <div><dt>Thanh toán</dt><dd>${VN.thoat(VN.TEN_THANH_TOAN[pt])} <span class="nhan ${ttTT.lop}">${ttTT.ten}</span></dd></div>
            ${don.goiQua ? `<div><dt>Quà tặng</dt><dd>Gói quà Vinora${don.loiNhan ? ` · Thiệp: “${VN.thoat(don.loiNhan)}”` : ''}</dd></div>` : ''}
          </dl>
        </section>
      </div>

      <div class="hang hang--giua hang--quan kq-nut">
        <a class="nut nut--chinh" href="${VN.url('donHang', { ma: don.ma })}">Xem chi tiết đơn hàng</a>
        <a class="nut nut--vien" href="${VN.url('sanPham')}">Tiếp tục mua sắm</a>
      </div>`;
  };

  const saoChep = async (chu) => {
    try { await navigator.clipboard.writeText(chu); } catch (e) { /* trình duyệt chặn: vẫn báo để người dùng tự chép */ }
    VN.thongBao({ tieuDe: 'Đã sao chép', noiDung: VN.thoat(chu), loai: 'thanh-cong', thoiGian: 2200 });
  };

  khung.addEventListener('click', async (e) => {
    const sao = e.target.closest('[data-sao]');
    if (sao) { saoChep(sao.dataset.sao); return; }
    if (e.target.closest('[data-mo-phong-bao-co]')) {
      VN.donHang.ghiThanhToan(maDon, true);
      VN.thongBao({ tieuDe: 'Đã nhận tiền chuyển khoản', noiDung: 'Đơn hàng chuyển sang chờ cửa hàng xác nhận.', loai: 'thanh-cong' });
      ve(); window.scrollTo({ top: 0, behavior: 'smooth' });
      return;
    }
    if (e.target.closest('[data-thanh-toan-lai]')) {
      const don = VN.donHang.lay(maDon);
      VN.donHang.capNhat(maDon, (d) => { d.thanhToan.trangThai = 'Pending'; });
      const kq = await VN.congThanhToan.mo(don);
      ve();
      VN.thongBao(kq.ok ? { tieuDe: 'Thanh toán thành công', loai: 'thanh-cong' } : { tieuDe: 'Thanh toán chưa thành công', noiDung: VN.thoat(kq.lyDo), loai: 'loi' });
      return;
    }
    if (e.target.closest('[data-doi-cod]')) {
      const dongY = await VN.xacNhan({ nhan: 'Đổi phương thức thanh toán', tieuDe: 'Chuyển sang thanh toán khi nhận hàng?', noiDung: 'Bạn sẽ thanh toán bằng tiền mặt hoặc chuyển khoản khi nhận hàng. Đơn hàng giữ nguyên sản phẩm và tổng tiền.', chuDongY: 'Chuyển sang COD' });
      if (!dongY) return;
      VN.donHang.doiSangCOD(maDon);
      ve();
      VN.thongBao({ tieuDe: 'Đã chuyển sang thanh toán khi nhận hàng', loai: 'thanh-cong' });
    }
  });

  ve();
})();
