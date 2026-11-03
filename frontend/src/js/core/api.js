/* =====================================================================
   VINORA JEWELRY - api.js (loaded after common.js on every shop page)
   Talks to the Flask API with fetch (AJAX) and turns what the server sends into the shapes the pages already use,
   so a page does not need to know the database column names.
   1. Client: VN.api.get / post / patch / del. A failed call throws VN.LoiApi whose message is Vietnamese.
   2. Codes: payment methods and engraving styles (page codes <-> server codes)
   3. Adapters: server rows -> product, cart line, order, customer as the pages use them
   4. Shop data: VN.duLieu (products, categories, collections, ring sizes, config files)
   The only place that knows both names of a thing is this file (see docs/database/doi-chieu-giao-dien.md).
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;

  /* ================= 1. CLIENT ================= */
  /** Error of a failed API call. message is ready to show to the customer. */
  class LoiApi extends Error {
    constructor(thongDiep, { trangThai = 0, lyDo = '', maLoi = null, duLieu = null } = {}) {
      super(thongDiep);
      this.name = 'LoiApi';
      this.trangThai = trangThai;   // HTTP status, 0 = no answer from the server
      this.lyDo = lyDo;             // "reason" sent by the API, for example phone_in_use
      this.maLoi = maLoi;           // number thrown by a stored procedure (50029 = cancel by hotline), when there is one
      this.duLieu = duLieu;         // the whole JSON body of the answer
    }
  }
  VN.LoiApi = LoiApi;

  // Messages by the "reason" field of the API
  const THEO_LY_DO = {
    phone_in_use: 'Số điện thoại này đã thuộc về một tài khoản khác. Vui lòng đăng nhập bằng tài khoản đó.',
    phone_has_account: 'Số điện thoại này đã có tài khoản. Vui lòng đăng nhập để đặt hàng.',
    otp_required: 'Số điện thoại này đã có đơn hàng đặt trước đó. Nhập mã xác minh gửi về số điện thoại để liên kết các đơn đó vào tài khoản.',
    otp_invalid: 'Mã xác minh chưa đúng.',
    quote_only: 'Sản phẩm này chỉ báo giá, không bán trực tuyến. Vui lòng liên hệ cửa hàng để được báo giá.',
    not_found: 'Mã ưu đãi không tồn tại hoặc đã hết hạn.',
    expired: 'Mã ưu đãi đã hết hạn.',
    used_up: 'Mã ưu đãi đã hết lượt sử dụng.',
    min_order: (d) => `Mã ưu đãi áp dụng cho đơn từ ${VN.tien(d.minOrderValue)}.`,
  };
  // Messages by the exact English text of the API
  const THEO_CHU = {
    'Invalid email or password': 'Email hoặc mật khẩu chưa đúng. Vui lòng kiểm tra lại.',
    'Account is disabled': 'Tài khoản đang bị khóa. Vui lòng liên hệ hotline để được hỗ trợ.',
    'Email already registered': 'Email này đã được dùng để đăng ký. Vui lòng đăng nhập hoặc dùng email khác.',
    'Current password is wrong': 'Mật khẩu hiện tại chưa đúng.',
    'Login required': 'Vui lòng đăng nhập để tiếp tục.',
    'Order not found': 'Không tìm thấy đơn hàng khớp với mã đơn và số điện thoại này. Vui lòng kiểm tra lại.',
    'Not enough stock': 'Số lượng trong kho không đủ cho lựa chọn này.',
    'Variant not found': 'Mẫu, màu hoặc size này hiện không có.',
    'Product not found': 'Không tìm thấy sản phẩm.',
    'Cart item not found': 'Dòng này không còn trong giỏ hàng.',
    'The cart is empty': 'Giỏ hàng đang trống.',
    'This product cannot be engraved': 'Sản phẩm này không hỗ trợ khắc chữ.',
    'The cart has this item with a very similar engraving text. Change that line instead.': 'Giỏ hàng đã có sản phẩm này với chữ khắc gần giống (chỉ khác dấu hoặc chữ hoa). Vui lòng sửa dòng đó trong giỏ.',
    'Invalid checkoutToken': 'Phiên đặt hàng không hợp lệ. Vui lòng tải lại trang rồi đặt hàng lại.',
    'Another request for the same customer is still running. Please try again.': 'Hệ thống đang xử lý một yêu cầu khác của bạn. Vui lòng thử lại sau vài giây.',
  };
  const THEO_TRANG_THAI = {
    400: 'Thông tin chưa hợp lệ. Vui lòng kiểm tra lại.',
    401: 'Vui lòng đăng nhập để tiếp tục.',
    403: 'Bạn không có quyền thực hiện thao tác này.',
    404: 'Không tìm thấy dữ liệu yêu cầu.',
    409: 'Dữ liệu vừa thay đổi hoặc bị trùng. Vui lòng thử lại.',
    413: 'Dữ liệu gửi lên quá lớn.',
  };
  const KHONG_KET_NOI = 'Không kết nối được máy chủ. Vui lòng kiểm tra mạng rồi thử lại.';

  const thongDiepLoi = (trangThai, d) => {
    d = d && typeof d === 'object' ? d : {};
    // A stored procedure answers with its own Vietnamese text and a numeric code: show it as it is
    if (d.code && d.error) return d.error;
    const lyDo = THEO_LY_DO[d.reason];
    if (lyDo) return typeof lyDo === 'function' ? lyDo(d) : lyDo;
    if (THEO_CHU[d.error]) return THEO_CHU[d.error];
    let m = /^Item (\d+): (.*)$/.exec(d.error || '');   // an error inside a guest order line
    if (m) return `Sản phẩm thứ ${m[1]}: ${THEO_CHU[m[2]] || THEO_LY_DO[d.reason] || 'dòng này chưa hợp lệ.'}`;
    m = /^At most (\d+) of one item per order$/.exec(d.error || '');
    if (m) return `Mỗi lựa chọn chỉ mua tối đa ${m[1]} sản phẩm.`;
    m = /^Engraving text is limited to (\d+) characters$/.exec(d.error || '');
    if (m) return `Chữ khắc tối đa ${m[1]} ký tự.`;
    return THEO_TRANG_THAI[trangThai] || (trangThai >= 500 ? 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau ít phút.' : 'Có lỗi xảy ra. Vui lòng thử lại.');
  };

  const goi = async (phuongThuc, duongDan, thanBody) => {
    let phanHoi;
    try {
      phanHoi = await fetch(duongDan, {
        method: phuongThuc,
        credentials: 'same-origin',               // the login is a cookie
        headers: { Accept: 'application/json', ...(thanBody === undefined ? {} : { 'Content-Type': 'application/json' }) },
        body: thanBody === undefined ? undefined : JSON.stringify(thanBody),
      });
    } catch (e) {
      throw new LoiApi(KHONG_KET_NOI);
    }
    let duLieu = null;
    if (phanHoi.status !== 204) { try { duLieu = await phanHoi.json(); } catch (e) { duLieu = null; } }
    if (!phanHoi.ok) {
      // The login cookie ran out while the page still shows a customer: tell the session module
      if (phanHoi.status === 401 && !duongDan.startsWith('/api/auth/')) VN.phatSuKien('het-phien');
      throw new LoiApi(thongDiepLoi(phanHoi.status, duLieu), { trangThai: phanHoi.status, lyDo: (duLieu && duLieu.reason) || '', maLoi: (duLieu && duLieu.code) || null, duLieu });
    }
    return duLieu;
  };
  VN.api = {
    get: (duongDan) => goi('GET', duongDan),
    post: (duongDan, thanBody = {}) => goi('POST', duongDan, thanBody),
    patch: (duongDan, thanBody = {}) => goi('PATCH', duongDan, thanBody),
    del: (duongDan) => goi('DELETE', duongDan),
    /** Query string from an object, leaving out empty values: tuKhoa({q: 'nhan', page: 2}) -> "?q=nhan&page=2" */
    tuKhoa: (doiTuong) => {
      const q = new URLSearchParams();
      Object.entries(doiTuong).forEach(([k, v]) => { if (v !== undefined && v !== null && v !== '') q.set(k, v); });
      return q.toString() ? '?' + q.toString() : '';
    },
  };

  /* ================= 2. CODES ================= */
  /** Payment method: page code <-> server code */
  VN.PT_THANH_TOAN = { COD: 'COD', BANK: 'BankTransfer', VNPAY: 'VNPay', MOMO: 'MoMo' };
  const PT_TU_MAY_CHU = Object.fromEntries(Object.entries(VN.PT_THANH_TOAN).map(([a, b]) => [b, a]));
  /** Engraving style: page code <-> server code */
  const KIEU_CHU = { 'co-dien': 'Classic', 'hien-dai': 'Modern', 'viet-tay': 'Handwritten' };
  const KIEU_TU_MAY_CHU = Object.fromEntries(Object.entries(KIEU_CHU).map(([a, b]) => [b, a]));
  VN.kieuChuMayChu = (kieu) => KIEU_CHU[kieu] || 'Classic';

  /* ================= 3. ADAPTERS (server -> page shape) ================= */
  const ngayCuaChuoi = (s) => String(s || '').slice(0, 10);

  /** One row of GET /api/products (or of the detail without the extra parts) -> the product the pages use */
  const sanPhamTuApi = (r) => {
    const baoGia = !!r.IsQuoteOnly;              // priced by the gold price of the day: no online price, the shop gives a quote
    const gia = baoGia ? null : r.CurrentPrice;
    const giaCu = !baoGia && r.OriginalPrice && r.OriginalPrice > r.CurrentPrice ? r.OriginalPrice : null;
    return {
      ma: r.SKU, id: r.ProductID, ten: r.ProductName, danhMuc: r.CategoryID, boSuuTap: r.CollectionID,
      chatLieu: r.Material, trongLuong: r.WeightGram, loaiGia: r.PricingMethod === 'GoldRate' ? 'gia_cong' : 'co_dinh',
      coTheMua: !baoGia, giaBan: gia, gia, giaCu, giam: giaCu ? Math.round((giaCu - gia) * 100 / giaCu) : null,
      mau: r.Colors || [], anh: r.Images || [], coMoTa: !!r.HasDescription, moTa: '', da: null,
      canChonSize: !!r.RequiresRingSize, ngayTao: ngayCuaChuoi(r.CreatedAt), conHang: !!r.IsInStock, tonKho: r.TotalStock || 0,
    };
  };

  /** GET /api/products/<sku> -> the product plus description, all images, stones and variants */
  const chiTietTuApi = (r) => {
    const sp = sanPhamTuApi(r);
    const chinh = (r.stones || []).find((s) => s.IsMainStone) || (r.stones || [])[0];
    const bienThe = (r.variants || []).map((v) => ({ ma: v.VariantSKU, mau: v.GoldColor || '', size: v.RingSize, tonKho: v.StockQuantity }));
    return Object.assign(sp, {
      moTa: r.Description || '', coMoTa: !!r.Description, anh: (r.images || []).map((i) => i.ImageUrl),
      da: chinh ? { kichThuoc: chinh.SizeMm ? `${chinh.SizeMm} mm` : '', soVien: chinh.Quantity, ten: chinh.StoneName } : null,
      dsDa: (r.stones || []).map((s) => ({ loai: s.StoneType, ten: s.StoneName, kichThuoc: s.SizeMm, soVien: s.Quantity, chinh: !!s.IsMainStone })),
      bienThe, mau: [...new Set(bienThe.map((v) => v.mau).filter(Boolean))], khacDuoc: !!r.IsEngravable,
    });
  };

  /** A cart line of GET /api/cart -> the line the pages use */
  VN.dongGioTuApi = (i) => {
    const d = { id: i.CartItemID, bienThe: i.VariantSKU, ma: i.SKU, ten: i.ProductName, soLuong: i.Quantity, donGia: i.UnitPrice, tonKho: i.StockQuantity };
    if (i.GoldColor) d.mau = i.GoldColor;
    if (i.RingSize) d.size = i.RingSize;
    if (i.EngravingText) { d.khacChu = i.EngravingText; d.kieuChu = KIEU_TU_MAY_CHU[i.EngravingStyle] || 'co-dien'; }
    return d;
  };

  /** The customer: user + profile + address book -> the account the pages use */
  VN.khachTuApi = (nguoi, ho, diaChi) => ({
    id: nguoi.id, vaiTro: 'customer', hoTen: ho.fullName, email: ho.email, sdt: ho.phone || '',
    ngaySinh: ho.dateOfBirth || '', sizeNhan: ho.defaultRingSize || null,
    diaChi: (diaChi || []).map((a) => ({ id: a.AddressID, hoTen: a.RecipientName, sdt: a.Phone, tinh: a.Province, phuongXa: a.Ward, diaChi: a.AddressLine, macDinh: !!a.IsDefault })),
  });

  const TEN_THANH_TOAN_LS = { COD: 'thanh toán khi nhận hàng', BANK: 'chuyển khoản', VNPAY: 'VNPay', MOMO: 'MoMo' };
  /**
   * An order of the API (list row or detail) -> the order the pages use.
   * The list has no addresses or times, so those parts are only filled when the detail is given.
   */
  VN.donHangTuApi = (r, { sdtKhach = '', khachId = null } = {}) => {
    const pt = PT_TU_MAY_CHU[r.PaymentMethod || ((r.payments || [])[0] || {}).PaymentMethod] || 'COD';
    const thanhToanCuoi = (r.payments || []).slice(-1)[0] || {};
    const trangThaiTT = r.PaymentStatus || thanhToanCuoi.Status || 'Pending';
    const choTraOnline = r.OrderStatus === 'Pending' && pt !== 'COD' && trangThaiTT !== 'Success';
    const sp = VN.duLieuDaTai && VN.duLieuDaTai.theoMa;
    const don = {
      ma: r.OrderCode, khachHang: khachId, sdtKhach, ngayDat: r.CreatedAt, trangThai: r.OrderStatus,
      sanPham: (r.items || []).map((i) => ({
        ma: i.ProductSKU, maBienThe: i.SKUSnap, ten: i.ProductNameSnap, anh: sp && sp[i.ProductSKU] ? sp[i.ProductSKU].anh[0] : '',
        chatLieu: i.MaterialSnap, mau: i.GoldColor || '', size: i.RingSize || null,
        khacChu: i.EngravingText || '', kieuChu: i.EngravingText ? (KIEU_TU_MAY_CHU[i.EngravingStyle] || 'co-dien') : '',
        soLuong: i.Quantity, donGia: i.UnitPrice, laNhan: !!i.RingSize,
      })),
      tamTinh: r.Subtotal, giamGia: r.DiscountAmount || 0, maUuDai: r.VoucherCode || '', phiGiao: r.ShippingFee, tongTien: r.TotalAmount,
      giaoHang: { ma: 'tieu-chuan', ten: 'Giao tiêu chuẩn có bảo hiểm' },
      thanhToan: { phuongThuc: pt, trangThai: trangThaiTT, maGiaoDich: thanhToanCuoi.TransactionID || null, luc: thanhToanCuoi.PaidAt || null },
      hanThanhToan: choTraOnline ? r.PaymentDeadline : null,
      kenhHuy: r.CancelChannel || null,            // "Web" = can cancel here, "Hotline" = call the shop, null = cannot cancel
      coKhacChu: !!r.HasEngraving,
      daDanhGia: !!(VN.danhGia && VN.danhGia.theoDon(r.OrderCode)), lichSu: [],
    };
    if (r.ShipRecipientName !== undefined) {   // the detail of one order
      don.nguoiNhan = { hoTen: r.ShipRecipientName, sdt: r.ShipPhone, tinh: '', phuongXa: '', diaChi: r.ShipAddress, ghiChu: r.Note || '', email: '' };
      don.ngayGiao = r.ShippedAt || null; don.ngayNhan = r.DeliveredAt || null; don.ngayXacNhan = r.ConfirmedAt || null;
      don.daBatDauCheTac = !!r.ProductionStartedAt;
      don.yeuCauHuy = r.OrderStatus === 'Cancelled'
        ? { luc: r.CancelledAt, lyDo: r.CancelReason || '', tuDong: trangThaiTT === 'Expired', daHuy: true } : null;
      don.huyDangCho = r.pendingCancelRequest ? { maYeuCau: r.pendingCancelRequest.RequestID, maUuDai: r.pendingCancelRequest.VoucherCode, tienGiam: r.pendingCancelRequest.VoucherDiscount, giaGoc: r.pendingCancelRequest.Subtotal, tongTien: r.pendingCancelRequest.TotalAmount } : null;
      don.daApDungGiuChan = !!r.IsRetentionApplied;
      don.lichSu = lichSuTuApi(r, pt);
    }
    return don;
  };

  /** The order has no event log in the API, so the history is made from the times stored on the order */
  const lichSuTuApi = (r, pt) => {
    const ls = [];
    const them = (luc, noiDung, boi, trangThai) => { if (luc) ls.push({ luc, noiDung, boi, trangThai }); };
    them(r.CreatedAt, 'Đặt hàng thành công, đơn chờ cửa hàng xác nhận.', 'Khách hàng', 'Pending');
    (r.payments || []).forEach((p) => { if (p.Status === 'Success') them(p.PaidAt, `Thanh toán thành công qua ${TEN_THANH_TOAN_LS[PT_TU_MAY_CHU[p.PaymentMethod]] || p.PaymentMethod}.`, 'Cổng thanh toán', 'Pending'); });
    them(r.ConfirmedAt, 'Cửa hàng xác nhận đơn hàng.', 'Cửa hàng', 'Confirmed');
    them(r.ProductionStartedAt, 'Cửa hàng bắt đầu chế tác đơn hàng.', 'Cửa hàng', 'Confirmed');
    them(r.ShippedAt, 'Cửa hàng bàn giao đơn hàng cho đơn vị vận chuyển.', 'Cửa hàng', 'Shipping');
    them(r.DeliveredAt, 'Khách hàng xác nhận đã nhận hàng.', 'Khách hàng', 'Delivered');
    them(r.CancelledAt, `Đơn hàng đã hủy${r.CancelReason ? '. Lý do: ' + r.CancelReason : ''}.`, 'Hệ thống', 'Cancelled');
    return ls.sort((a, b) => new Date(a.luc) - new Date(b.luc));
  };

  /* ================= 4. SHOP DATA (VN.duLieu) ================= */
  const tepDuLieu = (ten) => (VN.duongDan.duLieu || '../../../mock-data/') + ten;
  const cache = {};
  /** Keep the promise of `tao()` under `khoa`; a failed load is forgotten so the next call tries again */
  const nhoLai = (khoa, tao) => {
    if (!cache[khoa]) { cache[khoa] = tao(); cache[khoa].catch(() => { delete cache[khoa]; }); }
    return cache[khoa];
  };
  const KHOA_KHO = 'vinora.catalog.v1';
  const TUOI_KHO_MS = 5 * 60 * 1000;     // the catalog may be up to 5 minutes old on a page; the server checks prices again at checkout

  /** Reads the whole catalog: page 1 first (it says how many pages there are), then the other pages at the same time */
  const taiTatCaSanPham = async () => {
    try {
      const luu = JSON.parse(sessionStorage.getItem(KHOA_KHO) || 'null');
      if (luu && Date.now() - luu.luc < TUOI_KHO_MS) return luu.ds;
    } catch (e) { /* storage blocked or damaged: read from the server */ }
    const dau = await VN.api.get('/api/products?limit=100&page=1');
    const soTrang = Math.ceil(dau.total / dau.limit);
    const conLai = await Promise.all(Array.from({ length: Math.max(0, soTrang - 1) }, (_, i) => VN.api.get(`/api/products?limit=100&page=${i + 2}`)));
    const ds = dau.items.concat(...conLai.map((t) => t.items));
    try { sessionStorage.setItem(KHOA_KHO, JSON.stringify({ luc: Date.now(), ds })); } catch (e) { /* too big or blocked: fine */ }
    return ds;
  };

  VN.duLieu = {
    /** All products on sale + an index by code (SKU). ds / theoMa / tatCa hold the same products. */
    sanPham() {
      if (cache.sp) return cache.sp;
      cache.sp = taiTatCaSanPham().then((hang) => {
        const ds = hang.map(sanPhamTuApi);
        const theoMa = {}; ds.forEach((sp) => { theoMa[sp.ma] = sp; });
        VN.duLieuDaTai = { theoMa };
        return { ds, theoMa, tatCa: ds };
      });
      cache.sp.catch(() => { delete cache.sp; });
      return cache.sp;
    },
    /** One product with description, all images, stones and the variants (colour, size, stock) */
    chiTietSanPham(ma) {
      cache.ct = cache.ct || {};
      if (!cache.ct[ma]) {
        cache.ct[ma] = VN.api.get('/api/products/' + encodeURIComponent(ma)).then(chiTietTuApi);
        cache.ct[ma].catch(() => { delete cache.ct[ma]; });
      }
      return cache.ct[ma];
    },
    danhMuc() {
      return nhoLai('dm', () => VN.api.get('/api/categories').then((ds) => {
        const dm = ds.map((c) => ({ id: c.CategoryID, ten: c.CategoryName, nhom: c.CategoryGroup, duongDan: c.Slug, moTa: c.Description || '', soLuong: c.ProductCount, canChonSize: !!c.RequiresRingSize }));
        const theoId = {}; dm.forEach((x) => { theoId[x.id] = x; });
        return { ds: dm, theoId };
      }));
    },
    boSuuTap() {
      return nhoLai('bst', () => VN.api.get('/api/collections').then((ds) => {
        const bst = ds.map((b) => ({ id: b.CollectionID, ten: b.CollectionName, duongDan: b.Slug, moTa: b.Description || '', soLuong: b.ProductCount, loaiSanPham: b.Categories || [], chatLieu: b.Materials || [] }));
        const theoId = {}; bst.forEach((x) => { theoId[x.id] = x; });
        return { ds: bst, theoId };
      }));
    },
    // These stay files: labels and rules of the pages (config), the size chart text, the provinces and the shop addresses
    cauHinh() { return cache.ch || (cache.ch = VN.taiJSON(tepDuLieu('config.json'))); },
    bangSize() { return cache.size || (cache.size = VN.taiJSON(tepDuLieu('size-chart.json'))); },
    tinhThanh() { return cache.tinh || (cache.tinh = VN.taiJSON(tepDuLieu('provinces.json'))); },
    /** Shop list read from an XML file with the DOM (getElementsByTagName) */
    cuaHang() {
      return cache.ch_xml || (cache.ch_xml = VN.taiXML(tepDuLieu('stores.xml')).then((xml) => {
        const lay = (nut, the) => (nut.getElementsByTagName(the)[0] || {}).textContent || '';
        return Array.from(xml.getElementsByTagName('cuahang')).map((n) => ({
          ma: n.getAttribute('ma'), ten: lay(n, 'ten'), diaChi: lay(n, 'diachi'), khuVuc: lay(n, 'khuvuc'),
          dienThoai: lay(n, 'dienthoai'), gioMoCua: lay(n, 'giomocua'), banDo: lay(n, 'bando'),
        }));
      }));
    },
    /** Products, categories, collections and config in one go; names of the category and collection are put on each product */
    coBan() {
      return nhoLai('coBan', () => Promise.all([this.sanPham(), this.danhMuc(), this.boSuuTap(), this.cauHinh()])
        .then(([sp, dm, bst, ch]) => {
          sp.tatCa.forEach((s) => {
            s.dm = dm.theoId[s.danhMuc] || { ten: '', nhom: '' };
            s.bst = bst.theoId[s.boSuuTap] || { ten: '' };
            s.tenChatLieu = (ch.tenChatLieu || {})[s.chatLieu] || s.chatLieu;
            s.tuKhoa = VN.khongDau([s.ten, s.ma, s.dm.ten, s.dm.nhom, s.bst.ten, s.tenChatLieu, s.mau.join(' ')].join(' '));
          });
          return { sp, dm, bst, ch };
        }));
    },
  };
})();
