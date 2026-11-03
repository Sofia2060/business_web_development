/* =====================================================================
   VINORA JEWELRY - session.js (loaded after api.js on every shop page)
   What the server knows about the visitor: the account, the cart and the orders.
   A page reads it with plain calls (VN.taiKhoan.hienTai(), VN.gioHang.ds(), VN.donHang.lay(ma)) once
   `await VN.sanSang` is done, and changes it with async calls that go to the API.
   1. VN.taiKhoan  - login, register, profile, address book
   2. VN.gioHang   - the cart: in the database for a customer, in this browser for a visitor without an account
   3. VN.uuDai     - voucher check
   4. VN.donHang   - orders: place, look up, pay, cancel, confirm receipt
   5. VN.baoHanh, VN.lichHen - warranty cards and after-sales appointments
   6. VN.sanSang   - done when the account and the cart are loaded
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const LoiApi = VN.LoiApi;

  /* ================= 1. ACCOUNT ================= */
  const MAT_KET_NOI = 'Chưa kết nối được máy chủ nên chưa lưu được thay đổi. Vui lòng thử lại sau ít giây.';
  /** Run `ham` up to `lan` times with a short wait between tries (a network blip or a busy server often passes in a second) */
  const thuLai = async (ham, lan = 3) => {
    for (let i = 1; ; i++) {
      try { return await ham(); } catch (loi) { if (i >= lan) throw loi; await new Promise((xong) => setTimeout(xong, 700 * i)); }
    }
  };

  VN.taiKhoan = {
    nguoi: null,     // the logged-in customer as the pages know them, or null
    // true when the server could not say who is logged in (network or server error). That is not the same as a
    // visitor: a customer must not be treated as a visitor, whose cart lives in this browser and is never merged.
    khongRo: false,
    hienTai() { return this.nguoi; },
    tenGoi(nguoi) { const p = String(nguoi?.hoTen || '').trim().split(/\s+/); return p[p.length - 1] || ''; },
    /** Go to the login page unless a customer is logged in; returns the customer when there is one.
     *  When the server could not be reached we do not know, so the page stays (the pages show a notice). */
    yeuCau(quayLai = location.pathname + location.search) {
      if (!this.nguoi) { if (!this.khongRo) location.href = VN.url('taiKhoan', { tiep: quayLai }); return null; }
      return this.nguoi;
    },
    /** Ask the server who is logged in (the login is a cookie) and load the profile and the address book.
     *  A visitor (401) is a normal answer; any other failure throws and sets khongRo. */
    async nap() {
      this.nguoi = null; this.khongRo = false;
      try {
        const ai = await VN.api.get('/api/auth/me');
        if (ai && ai.role === 'Customer') {
          const [ho, diaChi] = await Promise.all([VN.api.get('/api/profile'), VN.api.get('/api/addresses')]);
          this.nguoi = VN.khachTuApi(ai, ho, diaChi);
        }
      } catch (loi) {
        this.nguoi = null;
        if (loi.trangThai !== 401) { this.khongRo = true; throw loi; }
      }
      return this.nguoi;
    },
    /** Load the account right after the server accepted a login or a registration. If the server cannot be reached the
     *  person is logged in already, so say that clearly instead of a failed login. */
    async napSauKhiVao(thongDiep) {
      try { await thuLai(() => this.nap()); } catch (loi) { throw new LoiApi(thongDiep, { trangThai: 0 }); }
    },
    async napDiaChi() {
      this.nguoi.diaChi = VN.khachTuApi({}, { fullName: '', email: '' }, await VN.api.get('/api/addresses')).diaChi;
      VN.phatSuKien('tai-khoan', this.nguoi);
      return this.nguoi.diaChi;
    },
    /** Log in. A customer gets the cart of this browser merged into the account cart. The shop admin is told apart by "vaiTro". */
    async dangNhap(email, matKhau, ghiNho = true) {
      const u = await VN.api.post('/api/auth/login', { email: String(email).trim(), password: matKhau, remember: !!ghiNho });
      if (u.role !== 'Customer') {
        this.nguoi = null;
        VN.quanTri.datPhien({ email: u.email, hoTen: u.fullName });
        await VN.gioHang.nap();
        VN.phatSuKien('tai-khoan', null);
        return { vaiTro: 'admin', hoTen: u.fullName, email: u.email };
      }
      VN.quanTri.xoaPhien();
      await this.napSauKhiVao('Đã đăng nhập nhưng chưa tải được thông tin tài khoản. Vui lòng tải lại trang.');
      await VN.gioHang.gopGioKhach();
      VN.phatSuKien('tai-khoan', this.nguoi);
      return this.nguoi;
    },
    /** Create an account and log in. otp is only needed when the phone number has earlier orders made without an account. */
    async dangKy({ hoTen, email, matKhau, sdt = '', otp = '', sizeNhan = null }) {
      const r = await VN.api.post('/api/auth/register', { fullName: hoTen, email, password: matKhau, phone: sdt, otp });
      VN.quanTri.xoaPhien();
      await this.napSauKhiVao('Tài khoản đã được tạo nhưng chưa tải được thông tin. Vui lòng tải lại trang.');
      if (sizeNhan) await this.capNhat({ sizeNhan }).catch(() => {});   // the account exists already: a refused size must not look like a failed sign up
      await VN.gioHang.gopGioKhach();
      this.nguoi.donDaLienKet = r.linkedOrders || 0;
      VN.phatSuKien('tai-khoan', this.nguoi);
      return this.nguoi;
    },
    async dangXuat() {
      try { await VN.api.post('/api/auth/logout'); } catch (loi) { console.error(loi); }
      this.nguoi = null;
      VN.quanTri.xoaPhien();
      await VN.gioHang.nap();
      VN.phatSuKien('tai-khoan', null);
    },
    /** Change the profile. Only the given keys change: hoTen, sdt, ngaySinh, sizeNhan. */
    async capNhat(thayDoi) {
      const gui = {};
      if ('hoTen' in thayDoi) gui.fullName = thayDoi.hoTen;
      if ('sdt' in thayDoi) gui.phone = thayDoi.sdt;
      if ('ngaySinh' in thayDoi) gui.dateOfBirth = thayDoi.ngaySinh || null;
      if ('sizeNhan' in thayDoi) gui.defaultRingSize = thayDoi.sizeNhan || null;
      const ho = await VN.api.patch('/api/profile', gui);
      const moi = VN.khachTuApi({ id: this.nguoi.id }, ho, []);
      this.nguoi = Object.assign({}, this.nguoi, moi, { diaChi: this.nguoi.diaChi });
      VN.phatSuKien('tai-khoan', this.nguoi);
      return this.nguoi;
    },
    async doiMatKhau(cu, moi) { await VN.api.post('/api/auth/change-password', { currentPassword: cu, newPassword: moi }); },
    /** Address book: d = { hoTen, sdt, tinh, phuongXa, diaChi, macDinh } in the page shape. Returns the id of the address. */
    async luuDiaChi(d, id = null) {
      const gui = { recipientName: d.hoTen, phone: d.sdt, addressLine: d.diaChi, ward: d.phuongXa, province: d.tinh };
      let ma = id;
      if (id) await VN.api.patch('/api/addresses/' + id, Object.assign(gui, d.macDinh ? { isDefault: true } : {}));
      else ma = (await VN.api.post('/api/addresses', Object.assign(gui, { isDefault: !!d.macDinh }))).id;
      await this.napDiaChi();
      return ma;
    },
    async datDiaChiMacDinh(id) { await VN.api.patch('/api/addresses/' + id, { isDefault: true }); await this.napDiaChi(); },
    async xoaDiaChi(id) { await VN.api.del('/api/addresses/' + id); await this.napDiaChi(); },
  };
  // The login cookie ran out while a page was open: act as logged out
  window.addEventListener('vinora:het-phien', () => {
    if (!VN.taiKhoan.nguoi) return;
    VN.taiKhoan.nguoi = null;
    VN.gioHang.nap().catch(() => {});
    VN.phatSuKien('tai-khoan', null);
  });

  /* ================= 2. CART ================= */
  const luuGioKhach = (ds) => VN.kho.ghi('gioHang', ds);
  const dongTrungKhoa = (ds, khoa, d) => ds.find((x) => khoa(x) === khoa(d));

  /** The variant (colour + size) of a product as the server knows it. Throws when there is no such variant. */
  const timBienThe = async (ma, mau, size) => {
    const ct = await VN.duLieu.chiTietSanPham(ma);
    if (!ct.coTheMua) throw new LoiApi('Sản phẩm này chỉ báo giá, không bán trực tuyến. Vui lòng liên hệ cửa hàng để được báo giá.', { trangThai: 409, lyDo: 'quote_only' });
    if (ct.canChonSize && !size) throw new LoiApi('Vui lòng chọn size nhẫn.', { trangThai: 400 });
    const v = ct.bienThe.find((x) => (!mau || x.mau === mau) && (!size || x.size === Number(size)));
    if (!v) throw new LoiApi(size ? `Mẫu này hiện chưa có size ${size}${mau ? ' màu ' + mau : ''}. Vui lòng chọn size khác.` : 'Mẫu này hiện không có lựa chọn bạn chọn.', { trangThai: 404 });
    return v;
  };
  VN.timBienThe = timBienThe;

  VN.gioHang = {
    dong: [],        // lines of the cart now: from the database for a customer, from this browser for a visitor
    imLang: false,   // true while one change takes several calls (change size = remove + add): the pages hear about it once at the end
    khongTai: false, // true when the account cart could not be read from the server
    ds() { return this.dong; },
    coMayChu() { return !!VN.taiKhoan.hienTai(); },
    /** Before a change: when the account or the cart could not be loaded, try once more. If the server is still out of
     *  reach, stop with a clear message, so nothing is written to the wrong place (a customer's line into this browser). */
    async canKetNoi() {
      if (!VN.taiKhoan.khongRo && !this.khongTai) return;
      try {
        await VN.taiKhoan.nap();
        await this.nap();
        VN.phatSuKien('tai-khoan', VN.taiKhoan.hienTai());
      } catch (loi) { throw new LoiApi(MAT_KET_NOI, { trangThai: 0 }); }
    },
    /** A line is told apart by code + colour + size + engraving text + style */
    khoa(d) { return [d.ma, d.mau || '', d.size || '', d.khacChu || '', d.kieuChu || ''].join('|'); },
    tongSoLuong() { return this.dong.reduce((t, d) => t + (d.soLuong || 0), 0); },
    /** Load the cart: the account cart from the server, or the cart kept in this browser. nhay = make the cart badge blink. */
    async nap(nhay = false) {
      try {
        this.dong = this.coMayChu() ? (await VN.api.get('/api/cart')).items.map(VN.dongGioTuApi) : VN.kho.doc('gioHang', []);
        this.khongTai = false;
      } catch (loi) { this.khongTai = true; throw loi; }
      if (!this.imLang) VN.phatSuKien('gio', { nhay, dong: this.dong });
      return this.dong;
    },
    async guiLenMayChu(d, soLuong) {
      const v = d.bienThe ? { ma: d.bienThe } : await timBienThe(d.ma, d.mau, d.size);
      return VN.api.post('/api/cart', { variantSku: v.ma, quantity: soLuong, engravingText: d.khacChu || '', engravingStyle: d.khacChu ? VN.kieuChuMayChu(d.kieuChu) : '' });
    },
    /** Add a line (d = { ma, mau, size, khacChu, kieuChu, soLuong }). Resolves to { ds, vuotMuc }: vuotMuc = the cap per line stopped it. */
    async them(d, toiDa = 5) {
      await this.canKetNoi();
      const sl = Math.max(1, Number(d.soLuong) || 1);
      const co = dongTrungKhoa(this.dong, (x) => this.khoa(x), d);
      const coSan = co ? co.soLuong : 0;
      const duocThem = Math.min(sl, Math.max(0, toiDa - coSan));
      const vuotMuc = coSan + sl > toiDa;
      if (this.coMayChu()) {
        if (duocThem > 0) await this.guiLenMayChu(d, duocThem);
        await this.nap(duocThem > 0);
      } else {
        const v = await timBienThe(d.ma, d.mau, d.size);          // a visitor's cart is checked here, so a wrong choice shows at once
        if (coSan + duocThem > v.tonKho) throw new LoiApi('Số lượng trong kho không đủ cho lựa chọn này.', { trangThai: 409 });
        const ds = VN.kho.doc('gioHang', []);
        const dong = dongTrungKhoa(ds, (x) => this.khoa(x), d);
        if (dong) dong.soLuong = coSan + duocThem;
        else ds.unshift(Object.assign({}, d, { soLuong: duocThem, bienThe: v.ma, themLuc: Date.now() }));
        luuGioKhach(ds);
        await this.nap(true);
      }
      return { ds: this.dong, vuotMuc };
    },
    async datSoLuong(khoa, sl) {
      await this.canKetNoi();
      const d = this.dong.find((x) => this.khoa(x) === khoa); if (!d) return;
      if (this.coMayChu()) {
        try { await VN.api.patch('/api/cart/' + d.id, { quantity: sl }); } finally { await this.nap(); }
      } else {
        const ds = VN.kho.doc('gioHang', []); const dong = ds.find((x) => this.khoa(x) === khoa);
        if (dong) { dong.soLuong = sl; luuGioKhach(ds); }
        await this.nap();
      }
    },
    /** Remove a line; resolves to the removed line so the page can offer "undo" */
    async xoa(khoa) {
      await this.canKetNoi();
      const d = this.dong.find((x) => this.khoa(x) === khoa); if (!d) return null;
      if (this.coMayChu()) await VN.api.del('/api/cart/' + d.id).catch((loi) => { if (loi.trangThai !== 404) throw loi; });
      else luuGioKhach(VN.kho.doc('gioHang', []).filter((x) => this.khoa(x) !== khoa));
      await this.nap();
      return d;
    },
    async khoiPhuc(dong) { await this.them(dong); },
    /** Remove several lines at once (lines of products the shop no longer sells online) */
    async goBo(dsKhoa) {
      for (const khoa of dsKhoa) await this.xoa(khoa);
    },
    /** Change colour, size or engraving of a line. The line becomes the line with the new choices (merged when it already exists). Resolves to its key. */
    async capNhatDong(khoaCu, thayDoi, toiDa = 5) {
      const cu = this.dong.find((x) => this.khoa(x) === khoaCu); if (!cu) return null;
      const moi = Object.assign({}, cu, thayDoi);
      ['mau', 'size', 'khacChu', 'kieuChu'].forEach((k) => { if (moi[k] === '' || moi[k] === null || moi[k] === undefined) delete moi[k]; });
      if (!moi.khacChu) delete moi.kieuChu;
      delete moi.bienThe; delete moi.id; delete moi.tonKho;
      const khoaMoi = this.khoa(moi);
      if (khoaMoi === khoaCu) return khoaCu;
      await timBienThe(moi.ma, moi.mau, moi.size);                 // fails early when the new choice does not exist
      this.imLang = true;
      try {
        await this.xoa(khoaCu);
        try { await this.them(moi, Math.max(toiDa, moi.soLuong)); }
        catch (loi) { await this.them(cu, Math.max(toiDa, cu.soLuong)).catch(() => {}); throw loi; }   // put the old line back
      } finally {
        this.imLang = false;
        VN.phatSuKien('gio', { nhay: false, dong: this.dong });
      }
      return khoaMoi;
    },
    async xoaHet() {
      await this.canKetNoi();
      if (this.coMayChu()) { for (const d of this.dong.slice()) await VN.api.del('/api/cart/' + d.id).catch(() => {}); }
      else VN.kho.xoa('gioHang');
      await this.nap();
    },
    /** After login: the lines kept in this browser join the account cart. A line is clamped to the 5 per line the pages allow,
     *  a line that cannot be added is dropped, and each line leaves this browser as soon as it is merged (a closed tab never doubles it). */
    async gopGioKhach() {
      const khach = VN.kho.doc('gioHang', []);
      await this.nap();                   // now the account cart (the lines held so far are the visitor's)
      for (let i = 0; i < khach.length; i++) {
        const d = khach[i];
        const co = dongTrungKhoa(this.dong, (x) => this.khoa(x), d);
        const them = Math.min(d.soLuong, 5 - (co ? co.soLuong : 0));
        try { if (them > 0) await this.guiLenMayChu(d, them); } catch (loi) { console.warn('Bỏ qua dòng giỏ không thêm được', d.ma, loi.message); }
        luuGioKhach(khach.slice(i + 1));
      }
      VN.kho.xoa('gioHang');
      await this.nap();
    },
    /** Lines of products the shop does not sell online any more (stopped, hidden or quote only). They cannot be ordered. */
    async dongKhongBan() {
      const { sp } = await VN.duLieu.coBan();
      return this.dong.filter((d) => { const s = sp.theoMa[d.ma]; return !s || !s.coTheMua; });
    },
    /** Lines with their product, unit price and line total. Lines of products that are not sold online any more are left out. */
    async chiTiet() {
      const { sp } = await VN.duLieu.coBan();
      return this.dong.map((d) => {
        const s = sp.theoMa[d.ma];
        if (!s || !s.coTheMua) return null;
        const donGia = d.donGia || s.giaBan;                       // a customer's price comes from the server
        return Object.assign({}, d, { sp: s, donGia, thanhTien: donGia * d.soLuong, khoa: this.khoa(d) });
      }).filter(Boolean);
    },
    /** The cart lines of a visitor in the form the API takes (guest order, voucher check) */
    async dongGuiLen() {
      const { sp } = await VN.duLieu.coBan();
      const ds = VN.kho.doc('gioHang', []); let doi = false;
      // A product that is not on sale any more would make the whole order or voucher check fail, so those lines are left out
      const ban = ds.filter((d) => { const s = sp.theoMa[d.ma]; return s && s.coTheMua; });
      for (const d of ban) if (!d.bienThe) { d.bienThe = (await timBienThe(d.ma, d.mau, d.size)).ma; doi = true; }
      if (doi) luuGioKhach(ds);
      return ban.map((d) => ({ variantSku: d.bienThe, quantity: d.soLuong, engravingText: d.khacChu || '', engravingStyle: d.khacChu ? VN.kieuChuMayChu(d.kieuChu) : '' }));
    },
  };

  /* ================= 3. VOUCHER ================= */
  VN.uuDai = {
    /** Check a code against the cart. Resolves to { code, name, discount, subtotal } or throws a LoiApi that says why not. */
    async kiemTra(ma) {
      const gui = { code: ma };
      if (!VN.taiKhoan.hienTai()) gui.items = await VN.gioHang.dongGuiLen();
      return VN.api.post('/api/vouchers/check', gui);
    },
  };

  /* ================= 4. ORDERS ================= */
  /** A visitor without an account has no list on the server: the browser remembers the orders it placed or looked up */
  const docDonKhach = () => VN.kho.doc('donKhach', []);   // [{ ma, sdt }]
  const KHONG_THAY_DON = 'Không tìm thấy đơn hàng khớp với mã đơn và số điện thoại này. Vui lòng kiểm tra lại.';

  VN.donHang = {
    ds: [],          // orders of this customer, or the remembered orders of this browser (newest first)
    chiTietTheoMa: {},
    coQuyen(ma) { return docDonKhach().some((x) => x.ma === ma); },
    sdtCua(ma) { const m = docDonKhach().find((x) => x.ma === ma); return m ? m.sdt : ''; },
    ghiNho(ma, sdt) { VN.kho.ghi('donKhach', [{ ma, sdt }].concat(docDonKhach().filter((x) => x.ma !== ma)).slice(0, 20)); },
    quen(ma) { VN.kho.ghi('donKhach', docDonKhach().filter((x) => x.ma !== ma)); },
    /** Extra body / query for a visitor: the phone proves who they are together with the order code */
    soDienThoai(ma) { return VN.taiKhoan.hienTai() ? '' : this.sdtCua(ma); },

    cuaToi() { return this.ds; },
    /** The order loaded on this page (sync). Call napMot(ma) first to have all the details. */
    lay(ma) { return this.chiTietTheoMa[ma] || this.ds.find((d) => d.ma === ma) || null; },
    conLaiThanhToan(don) { return don && don.hanThanhToan ? new Date(don.hanThanhToan).getTime() - Date.now() : Infinity; },
    /** Shows the cancel button: "Web" = cancel here, "Hotline" = the button explains how to call; no channel = cannot cancel */
    coTheHuy(don) { return !!don && !!don.kenhHuy; },

    /** Load the list of orders */
    async nap() {
      await VN.duLieu.sanPham().catch(() => {});               // product images for the order lines
      const u = VN.taiKhoan.hienTai();
      if (u) {
        this.ds = (await VN.api.get('/api/orders')).map((r) => VN.donHangTuApi(r, { khachId: u.id }));
      } else {
        const kq = await Promise.all(docDonKhach().map((m) => this.napMot(m.ma, m.sdt).catch((loi) => { if (loi.trangThai === 404) this.quen(m.ma); return null; })));
        this.ds = kq.filter(Boolean);
      }
      this.ds.sort((a, b) => new Date(b.ngayDat) - new Date(a.ngayDat));
      VN.phatSuKien('don-hang', this.ds);
      return this.ds;
    },
    /** Load one order with all its details. A visitor needs the phone used for the order (kept in this browser after ordering). */
    async napMot(ma, sdt = '') {
      const u = VN.taiKhoan.hienTai();
      const dung = u ? '' : (sdt || this.sdtCua(ma));
      if (!u && !dung) throw new LoiApi(KHONG_THAY_DON, { trangThai: 404 });
      await VN.duLieu.sanPham().catch(() => {});
      const r = await VN.api.get(`/api/orders/${encodeURIComponent(ma)}${dung ? VN.api.tuKhoa({ phone: dung }) : ''}`);
      const don = VN.donHangTuApi(r, { sdtKhach: dung, khachId: u ? u.id : null });
      this.chiTietTheoMa[ma] = don;
      const i = this.ds.findIndex((x) => x.ma === ma);
      if (i >= 0) this.ds[i] = don;
      return don;
    },
    /** Look an order up with the order code and the phone used for it (no account needed). Resolves to { don } or { loi }. */
    async traCuu(ma, sdt) {
      ma = String(ma || '').trim().toUpperCase(); sdt = VN.chuanSdt(sdt);
      const u = VN.taiKhoan.hienTai();
      try {
        const don = await this.napMot(ma, sdt);
        if (!u) { this.ghiNho(ma, sdt); if (!this.ds.some((d) => d.ma === ma)) this.ds.unshift(don); }
        return { don };
      } catch (loi) {
        if (loi.trangThai === 404 || loi.trangThai === 401) return { loi: u ? 'Đơn hàng này không thuộc tài khoản đang đăng nhập.' : KHONG_THAY_DON };
        throw loi;
      }
    },
    /**
     * Place an order. For a customer: d = { diaChiId, phuongThuc, maUuDai, ghiChu, token }.
     * For a visitor: d also has hoTen, sdt (the buyer), sdtNguoiNhan, diaChi, phuongXa, tinh, dong (lines of the browser cart).
     * Resolves to { ma, tongTien, phiGiao }.
     */
    async tao(d) {
      await VN.gioHang.canKetNoi();
      const chung = { paymentMethod: VN.PT_THANH_TOAN[d.phuongThuc], checkoutToken: d.token, voucherCode: d.maUuDai || '', note: d.ghiChu || '' };
      let r;
      if (VN.taiKhoan.hienTai()) r = await VN.api.post('/api/orders', Object.assign({ addressId: d.diaChiId }, chung));
      else {
        r = await VN.api.post('/api/orders/guest', Object.assign({
          fullName: d.hoTen, phone: d.sdt, recipientPhone: d.sdtNguoiNhan && d.sdtNguoiNhan !== d.sdt ? d.sdtNguoiNhan : '',
          addressLine: d.diaChi, ward: d.phuongXa, province: d.tinh, items: d.dong,
        }, chung));
        this.ghiNho(r.OrderCode, VN.chuanSdt(d.sdt));
      }
      await VN.gioHang.nap().catch(() => {});
      return { ma: r.OrderCode, tongTien: r.TotalAmount, phiGiao: r.ShippingFee };
    },
    /** Pay an online order (simulated gateway: always succeeds while the order is within the time limit) */
    async thanhToan(ma) {
      const sdt = this.soDienThoai(ma);
      await VN.api.post(`/api/orders/${encodeURIComponent(ma)}/pay`, sdt ? { phone: sdt } : {});
      return this.napMot(ma);
    },
    /** Press "cancel": resolves to what the reminder popup shows, or throws (403 + maLoi 50029 = call the hotline) */
    async yeuCauHuy(ma, lyDo = '') {
      const sdt = this.soDienThoai(ma);
      const r = await VN.api.post(`/api/orders/${encodeURIComponent(ma)}/cancel`, Object.assign({ reason: lyDo }, sdt ? { phone: sdt } : {}));
      return { maYeuCau: r.RequestID, maUuDai: r.VoucherCode, tienGiam: r.VoucherDiscount, giaGoc: r.Subtotal, tongTien: r.TotalAmount };
    },
    /** The answer in the popup: giuDon = keep the order, otherwise cancel it */
    async traLoiHuy(ma, giuDon) {
      const sdt = this.soDienThoai(ma);
      await VN.api.post(`/api/orders/${encodeURIComponent(ma)}/cancel/respond`, Object.assign({ keepOrder: !!giuDon }, sdt ? { phone: sdt } : {}));
      return this.napMot(ma);
    },
    /** "I received the parcel" (only an order that is shipping) */
    async xacNhanDaNhan(ma) {
      const sdt = this.soDienThoai(ma);
      await VN.api.post(`/api/orders/${encodeURIComponent(ma)}/confirm-received`, sdt ? { phone: sdt } : {});
      return this.napMot(ma);
    },
    /** The payment time ran out on a page that is open: the server cancels the order on the next call, so load again */
    async heHan() {
      await Promise.all(Object.keys(this.chiTietTheoMa).map((ma) => this.napMot(ma).catch(() => {})));
      await this.nap().catch(() => {});
    },
  };

  /* ================= 5. WARRANTY CARDS AND APPOINTMENTS ================= */
  const chuanMaThe = (ma) => String(ma || '').replace(/\s/g, '').toUpperCase();
  /** The warranty cards of this visitor: a customer's account, or (a guest) the orders opened on this browser.
   *  The database makes the cards when an order is delivered. Pages call nap() or napDon(ma), then read with the plain calls. */
  VN.baoHanh = {
    ds: [],
    tatCa() { return this.ds; },
    cuaToi() { return VN.taiKhoan.hienTai() ? this.ds : []; },
    lay(ma) { ma = chuanMaThe(ma); return this.ds.find((t) => t.ma === ma) || null; },
    theoDon(maDon) { return this.ds.filter((t) => t.donHang === maDon); },
    /** Free turns left of a service (Infinity = no limit): the card's turns minus the used ones and the ones held by an open appointment */
    conLai(the, ch, loai) {
      const han = the.hanMuc[loai];
      if (han === null || han === undefined) return Infinity;
      const dangHen = VN.lichHen.ds.filter((l) => l.maBaoHanh === the.ma && l.loai === loai && l.dangMo).length;
      return Math.max(0, han - (the.daDung[loai] || 0) - dangHen);
    },
    /** The services done on each card, from the completed appointments */
    ghiLichSu() {
      this.ds.forEach((t) => {
        t.lichSuDichVu = VN.lichHen.ds.filter((l) => l.maBaoHanh === t.ma && l.trangThai === 'Completed')
          .map((l) => ({ luc: l.hoanTatLuc, loai: l.loai, noiDung: l.mienPhi ? 'Miễn phí' : `Tính phí ${VN.tien(l.phi)}`, maLich: l.ma }));
      });
    },
    async nap() {
      await VN.duLieu.sanPham().catch(() => {});                 // product images for the cards
      const u = VN.taiKhoan.hienTai();
      if (u) {
        const [cards] = await Promise.all([VN.api.get('/api/warranties'), VN.lichHen.nap()]);
        this.ds = cards.map((r) => Object.assign(VN.theBaoHanhTuApi(r), { chuThe: u.hoTen }));
      } else {
        const nhom = await Promise.all(docDonKhach().map(async ({ ma, sdt }) => {
          try {
            const [cards, don] = await Promise.all([
              VN.api.get(`/api/orders/${encodeURIComponent(ma)}/warranties?phone=${encodeURIComponent(sdt)}`), VN.donHang.napMot(ma).catch(() => null)]);
            return cards.map((r) => Object.assign(VN.theBaoHanhTuApi(r), { sdtKhach: sdt, chuThe: don && don.nguoiNhan ? don.nguoiNhan.hoTen : '' }));
          } catch (loi) { return []; }                            // an order that cannot be read is simply left out
        }));
        this.ds = nhom.flat();
      }
      this.ds.sort((a, b) => new Date(b.ngayKichHoat) - new Date(a.ngayKichHoat));
      this.ghiLichSu();
      VN.phatSuKien('bao-hanh');
      return this.ds;
    },
    /** The cards of one order (a customer's, or a guest's with the phone of the order); they join the cards already loaded */
    async napDon(maDon) {
      await VN.duLieu.sanPham().catch(() => {});
      const sdt = VN.donHang.soDienThoai(maDon); const u = VN.taiKhoan.hienTai();
      const r = await VN.api.get(`/api/orders/${encodeURIComponent(maDon)}/warranties${sdt ? '?phone=' + encodeURIComponent(sdt) : ''}`);
      const moi = r.map((x) => Object.assign(VN.theBaoHanhTuApi(x), { sdtKhach: sdt, chuThe: u ? u.hoTen : '' }));
      this.ds = moi.concat(this.ds.filter((t) => t.donHang !== maDon));
      this.ghiLichSu();
      return moi;
    },
    /** Look a card up by its code (anyone can). Resolves to { WarrantyCode, IssueDate, Status, ProductName, ProductSKU, PolicyName } or throws a 404. */
    traCuu(ma) { return VN.api.get('/api/warranties/' + encodeURIComponent(chuanMaThe(ma))); },
  };

  /** The after-sales appointments of the logged-in customer. A customer books and cancels; the shop confirms and completes. */
  VN.lichHen = {
    ds: [],
    tatCa() { return this.ds; },
    cuaToi() { return this.ds; },
    async nap() {
      this.ds = VN.taiKhoan.hienTai() ? (await VN.api.get('/api/after-sales')).map(VN.lichHenTuApi) : [];
      VN.baoHanh.ghiLichSu();
      VN.phatSuKien('lich-hen');
      return this.ds;
    },
    /** d = { maBaoHanh, loai, ngay ('2026-12-01'), gio ('14:00'), sizeMoi, tenCuaHang, sdt, soAnh, ghiChu }. Resolves to the new appointment. */
    async tao(d) {
      const r = await VN.api.post('/api/after-sales', {
        warrantyCode: d.maBaoHanh, serviceType: d.loai, preferredDate: `${d.ngay}T${d.gio}:00`, newRingSize: d.sizeMoi || null, note: VN.ghiChuLich(d),
      });
      await this.nap();
      return this.ds.find((l) => l.id === r.ServiceID) || VN.lichHenTuApi(r);
    },
    /** Cancel an appointment that is not completed (the card loses no turn) */
    async huy(ma) {
      const l = this.ds.find((x) => x.ma === ma); if (!l) return;
      await VN.api.post(`/api/after-sales/${l.id}/cancel`);
      await this.nap();
    },
  };

  /* ================= 6. READY ================= */
  /** True while the account or the cart could not be loaded from the server (and has not been loaded since) */
  VN.matKetNoi = () => VN.taiKhoan.khongRo || VN.gioHang.khongTai;
  /** Done when the account and the cart are loaded. Pages that need them start with `await VN.sanSang`. */
  VN.sanSang = (async () => {
    try { await thuLai(() => VN.taiKhoan.nap()); } catch (loi) { console.error(loi); }
    // The cart of a visitor is read from this browser, so it is only worth reading when we know the visitor is one
    if (!VN.taiKhoan.khongRo) { try { await thuLai(() => VN.gioHang.nap()); } catch (loi) { console.error(loi); } }
    if (VN.matKetNoi()) {
      // Stays on screen (an error notice does not close by itself) until the person reloads
      VN.thongBao({ tieuDe: 'Chưa kết nối được máy chủ', noiDung: 'Đăng nhập và giỏ hàng chưa tải được nên tạm thời chưa thay đổi được giỏ hàng.', loai: 'loi', hanhDong: { chu: 'Tải lại', khiBam: () => location.reload() } });
    }
    VN.phatSuKien('tai-khoan', VN.taiKhoan.hienTai());
  })();
})();
