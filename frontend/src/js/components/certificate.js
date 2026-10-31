/* =====================================================================
   GIẤY CHỨNG NHẬN KIỂM ĐỊNH – trình bày giống phiếu bảo hành, dùng ở:
   - Trang chi tiết sản phẩm: huy hiệu "Đã kiểm định" -> xem mẫu giấy chứng nhận của sản phẩm
   - Cổng bảo hành: mỗi thẻ bảo hành có giấy chứng nhận riêng (số chứng nhận theo mã thẻ)
   VN.htmlGiayChungNhan(sp, ch, tuyChon) -> chuỗi HTML
   VN.moGiayChungNhan(sp, ch, tuyChon)   -> mở hộp thoại (tự tạo một lần)
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;

  /** Số chứng nhận suy từ mã thẻ bảo hành: VNRA260812345678 -> VNCN 2608 1234 5678 */
  VN.soChungNhan = (maThe) => String(maThe || '').replace(/^VNRA(\d{4})(\d{4})(\d{4})$/, 'VNCN $1 $2 $3');

  /**
   * tuyChon: { so, ngay, mau, size, khacChu } – khi xem từ thẻ bảo hành sẽ có số và ngày cấp thật;
   * khi xem ở trang sản phẩm là bản mẫu (số chứng nhận cấp kèm sản phẩm lúc giao hàng)
   */
  VN.htmlGiayChungNhan = (sp, ch, tuyChon = {}) => {
    const logo = (VN.duongDan.hinh || '') + 'logo/logo-vinora.svg';
    const hl = VN.hamLuong(sp, ch);
    const da = sp.da ? `${VN.loaiDa(sp.ten)[0]} · ${VN.kichThuocDa(sp.da.kichThuoc)} × ${sp.da.soVien} viên`
      : VN.coDa(sp) ? `${VN.loaiDa(sp.ten)[0]} · kiểm đếm theo sản phẩm thực tế` : 'Không đính đá';
    const mau = tuyChon.mau || (sp.mau || []).join(' / ') || '—';
    const dong = [
      ['Số chứng nhận', tuyChon.so ? `<span class="so-deu">${VN.thoat(tuyChon.so)}</span>` : '<em>Cấp riêng cho từng sản phẩm khi giao hàng</em>'],
      ['Sản phẩm', VN.thoat(sp.ten)],
      ['Mã sản phẩm', `<span class="so-deu">${VN.thoat(sp.ma)}</span>`],
      ['Chất liệu', VN.thoat(sp.tenChatLieu || sp.chatLieu) + (hl ? ` <small>(${VN.thoat(hl)})</small>` : '')],
      ['Màu kim loại', VN.thoat(mau)],
      ['Trọng lượng', sp.trongLuong ? `≈ ${VN.so(sp.trongLuong)} gram${tuyChon.so ? '' : ' <small>(tham khảo)</small>'}` : '<em>Cân thực tế khi xuất kho</em>'],
      ['Thông tin đá', da],
    ];
    if (tuyChon.size) dong.push(['Size nhẫn', 'Size ' + VN.thoat(tuyChon.size)]);
    if (tuyChon.khacChu) dong.push(['Chữ khắc', `“${VN.thoat(tuyChon.khacChu)}”`]);
    dong.push(['Ngày cấp', tuyChon.ngay ? VN.ngay(tuyChon.ngay) : '<em>Ngày xuất kho</em>']);
    return `
      <article class="gcn${tuyChon.so ? '' : ' gcn--mau'}" aria-label="Giấy chứng nhận kiểm định ${VN.thoat(sp.ma)}">
        <div class="gcn__vien">
          <header class="gcn__dau">
            <img src="${logo}" alt="Vinora Jewelry" width="132" height="38">
            <div><p class="gcn__phu">Certificate of Authenticity</p><h3 class="gcn__tieu-de">Giấy chứng nhận kiểm định</h3></div>
          </header>
          <div class="gcn__than">
            <figure class="gcn__anh"><img src="${VN.anh(sp.anh[0])}" alt="" width="200" height="200" loading="lazy"></figure>
            <dl class="gcn__ds">${dong.map(([dt, dd]) => `<div><dt>${dt}</dt><dd>${dd}</dd></div>`).join('')}</dl>
          </div>
          <footer class="gcn__chan">
            <p>Kiểm định tại phòng kiểm tra chất lượng Vinora: phân tích hàm lượng kim loại quý, cân điện tử độ chính xác 0,01 g, soi đá bằng kính lúp 10×. Sản phẩm đạt chuẩn đúng như thông số công bố.</p>
            <span class="gcn__dau-moc" aria-hidden="true"><b>VINORA</b><i>QC</i><b>ĐẠT CHUẨN</b></span>
          </footer>
        </div>
      </article>`;
  };

  /** Hộp thoại xem giấy chứng nhận (tạo một lần, dùng lại) */
  let hop = null;
  const taoHop = () => {
    hop = document.createElement('dialog');
    hop.className = 'hop-thoai hop-thoai--rong hop-gcn';
    hop.setAttribute('aria-labelledby', 'gcn-td');
    hop.innerHTML = `<div class="hop-thoai__than">
        <button class="nut-bt hop-thoai__dong" type="button" data-dong-gcn aria-label="Đóng">${VN.bt('dong')}</button>
        <div class="hop-thoai__dau"><p class="nhan-tren">${VN.bt('chung-nhan', 'bt--nho')} Đã kiểm định chất lượng</p><h2 class="hop-thoai__tieu-de" id="gcn-td">Giấy chứng nhận sản phẩm</h2></div>
        <p class="hop-bao hop-bao--vang" data-gcn-ghi-chu>${VN.bt('thong-tin')}<span></span></p>
        <div data-gcn-noi-dung></div>
        <div class="hop-thoai__hanh-dong"><button class="nut nut--vien nut--nho" type="button" data-in-gcn>${VN.bt('in')} In giấy chứng nhận</button><button class="nut nut--chinh nut--nho" type="button" data-dong-gcn>Đóng</button></div>
      </div>`;
    document.body.appendChild(hop);
    hop.addEventListener('click', (e) => {
      if (e.target.closest('[data-dong-gcn]')) VN.dongHopThoai(hop);
      if (e.target.closest('[data-in-gcn]')) { document.documentElement.classList.add('dang-in-gcn'); window.print(); }
    });
    window.addEventListener('afterprint', () => document.documentElement.classList.remove('dang-in-gcn'));
  };
  VN.moGiayChungNhan = (sp, ch, tuyChon = {}) => {
    if (!hop) taoHop();
    VN.$('[data-gcn-noi-dung]', hop).innerHTML = VN.htmlGiayChungNhan(sp, ch, tuyChon);
    VN.$('[data-gcn-ghi-chu] span', hop).textContent = tuyChon.so
      ? 'Giấy chứng nhận điện tử gắn với thẻ bảo hành này. Bản giấy được giao kèm sản phẩm; khi mất bản giấy, bạn vẫn dùng bản điện tử này để bảo hành.'
      : 'Đây là mẫu giấy chứng nhận của sản phẩm. Mỗi sản phẩm khi giao sẽ kèm bản chính có số chứng nhận riêng, đồng thời được lưu trong thẻ bảo hành điện tử.';
    VN.moHopThoai(hop);
  };
})();
