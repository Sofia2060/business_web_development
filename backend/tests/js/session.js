// Runs the account and cart code of frontend/src/js/core/session.js against a scripted fake server, without a browser.
// Usage: node session.js <path to api.js> <path to session.js>   (prints what happened as JSON)
// The test backend/tests/test_frontend_session.py checks this output.
const fs = require('fs');
const vm = require('vm');

const [, , apiFile, sessionFile] = process.argv;

// The little of common.js that api.js and session.js touch
const store = {};
const events = []; const notices = [];
const VN = {
  tien: (n) => String(n), phatSuKien: (ten) => events.push(ten), danhGia: { theoDon: () => null }, duongDan: {},
  url: (ten) => '/' + ten, thongBao: (n) => notices.push(n.tieuDe), quanTri: { datPhien() {}, xoaPhien() {} },
  kho: { doc: (k, mac) => (k in store ? JSON.parse(store[k]) : mac), ghi: (k, v) => { store[k] = JSON.stringify(v); }, xoa: (k) => { delete store[k]; } },
  chuanSdt: (s) => s,
};
const location = { href: '/trang-hien-tai', pathname: '/trang-hien-tai', search: '' };
const sandbox = {
  window: { Vinora: VN, addEventListener() {} }, console, location, setTimeout, URLSearchParams,
  fetch: async () => ({ ok: false, status: 401, json: async () => ({}) }),       // the page loads as a visitor
  sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(apiFile, 'utf8'), sandbox);
vm.runInContext(fs.readFileSync(sessionFile, 'utf8'), sandbox);

// The scripted server: up/down, who is logged in, the account cart
const server = { up: true, me: null, cart: [] };
const loi = (trangThai) => new VN.LoiApi('x', { trangThai });
VN.api.get = async (url) => {
  if (!server.up) throw loi(0);
  if (url === '/api/auth/me') { if (!server.me) throw loi(401); return server.me; }
  if (url === '/api/profile') return { fullName: 'Khách A', email: 'a@example.test', phone: '0911000111' };
  if (url === '/api/addresses') return [];
  if (url === '/api/cart') return { items: server.cart };
  throw new Error('unexpected GET ' + url);
};
VN.api.post = async (url, body) => {
  if (!server.up) throw loi(0);
  if (url === '/api/auth/login') { server.me = { role: 'Customer', id: 5 }; return server.me; }
  if (url === '/api/cart') { server.cart.push({ CartItemID: server.cart.length + 1, VariantSKU: body.variantSku, SKU: 'SP1', ProductName: 'Nhẫn', Quantity: body.quantity, UnitPrice: 1000, StockQuantity: 9 }); return {}; }
  throw new Error('unexpected POST ' + url);
};
// The catalog: SP1 is on sale, STOP is not in it (stopped), QUOTE is quote only
const theoMa = { SP1: { ma: 'SP1', coTheMua: true, giaBan: 1000 }, QUOTE: { ma: 'QUOTE', coTheMua: false } };
VN.duLieu.coBan = async () => ({ sp: { theoMa } });
VN.duLieu.chiTietSanPham = async () => ({ coTheMua: true, canChonSize: false, bienThe: [{ ma: 'SP1-V', mau: 'Vàng', size: null, tonKho: 9 }] });

const attempt = async (ham) => { try { return { ok: true, value: await ham() }; } catch (e) { return { ok: false, message: e.message, status: e.trangThai }; } };
const gioKhach = () => VN.kho.doc('gioHang', []);

(async () => {
  const out = {};
  await VN.sanSang;
  out.loadedAsVisitor = { me: VN.taiKhoan.hienTai(), khongRo: VN.taiKhoan.khongRo, notices: notices.length };

  // 1. The server cannot be reached while a customer is logged in: not a visitor, and the page says so
  server.me = { role: 'Customer', id: 5 }; server.up = false;
  out.networkDown = await attempt(() => VN.taiKhoan.nap());
  out.networkDownFlags = { me: VN.taiKhoan.hienTai(), khongRo: VN.taiKhoan.khongRo, matKetNoi: VN.matKetNoi() };
  const redirect = location.href;
  VN.taiKhoan.yeuCau('/don-hang');
  out.pageStaysWhenUnknown = location.href === redirect;

  // 2. While it is unknown, a change to the cart is refused and nothing lands in this browser
  out.addWhileDown = await attempt(() => VN.gioHang.them({ ma: 'SP1', mau: 'Vàng', soLuong: 1 }));
  out.localCartAfterRefusal = gioKhach().length;

  // 3. The server is back: the next change heals the state and goes to the account cart
  server.up = true;
  out.addAfterRecovery = await attempt(() => VN.gioHang.them({ ma: 'SP1', mau: 'Vàng', soLuong: 2 }));
  out.afterRecovery = { me: VN.taiKhoan.hienTai() && VN.taiKhoan.hienTai().email, serverCart: server.cart.map((l) => l.Quantity), localCart: gioKhach().length, matKetNoi: VN.matKetNoi() };

  // 4. A 401 is an honest visitor
  server.me = null; server.cart = [];
  out.visitor = { me: await VN.taiKhoan.nap(), khongRo: VN.taiKhoan.khongRo };
  const before = location.href;
  VN.taiKhoan.yeuCau('/don-hang');
  out.visitorGoesToLogin = location.href !== before;

  // 5. Login accepted but the account cannot be read afterwards: say so (it takes the retries, about 2 seconds)
  server.me = null; server.up = true;
  const nap = VN.api.get;
  VN.api.get = async (url) => { if (url === '/api/auth/me') throw loi(0); return nap(url); };
  out.loginThenDown = await attempt(() => VN.taiKhoan.dangNhap('a@example.test', 'x'));
  VN.api.get = nap;

  // 6. Lines of products that are not on sale are left out of what a visitor sends, and can be listed
  VN.taiKhoan.nguoi = null; VN.taiKhoan.khongRo = false; VN.gioHang.khongTai = false;
  VN.kho.ghi('gioHang', [
    { ma: 'SP1', mau: 'Vàng', soLuong: 1, bienThe: 'SP1-V' },
    { ma: 'STOP', mau: 'Vàng', soLuong: 1, bienThe: 'STOP-V' },
    { ma: 'QUOTE', soLuong: 1, bienThe: 'QUOTE-V' },
  ]);
  await VN.gioHang.nap();
  out.sentToServer = (await VN.gioHang.dongGuiLen()).map((l) => l.variantSku);
  out.notOnSale = (await VN.gioHang.dongKhongBan()).map((d) => d.ma);
  out.detailLines = (await VN.gioHang.chiTiet()).map((d) => d.ma);
  console.log(JSON.stringify(out));
})().catch((e) => { console.error(e); process.exit(1); });
