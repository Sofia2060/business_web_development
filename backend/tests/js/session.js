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
const server = { up: true, me: null, cart: [], services: [], listDown: false, viewed: [], delDown: false, reviews: [] };
const loi = (trangThai) => new VN.LoiApi('x', { trangThai });
VN.api.get = async (url) => {
  if (!server.up) throw loi(0);
  if (url === '/api/after-sales') { if (server.listDown) throw loi(0); return server.services; }
  if (url.startsWith('/api/recently-viewed')) return server.viewed.slice().reverse().map((sku, i) => ({ SKU: sku, LastViewedAt: new Date(1e12 - i * 1000).toISOString() }));
  if (url === '/api/auth/me') { if (!server.me) throw loi(401); return server.me; }
  if (url === '/api/profile') return { fullName: 'Khách A', email: 'a@example.test', phone: '0911000111' };
  if (url === '/api/addresses') return [];
  if (url === '/api/cart') return { items: server.cart };
  throw new Error('unexpected GET ' + url);
};
VN.api.post = async (url, body) => {
  if (!server.up) throw loi(0);
  if (url === '/api/auth/login') { server.me = { role: 'Customer', id: 5 }; return server.me; }
  if (url === '/api/auth/logout') return {};
  if (url === '/api/recently-viewed' && server.postFails != null) throw loi(server.postFails);
  if (url === '/api/recently-viewed' && (server.gone || []).includes(body.sku)) throw loi(404);
  if (url === '/api/recently-viewed') { server.viewed = server.viewed.filter((x) => x !== body.sku).concat(body.sku); return null; }
  if (/^\/api\/orders\/[^/]+\/feedback$/.test(url)) {
    server.reviews.push(body);
    return { FeedbackID: 7, RatingStar: body.rating, ReviewText: body.text, CreatedAt: '2030-01-01T09:00:00', aspects: body.topics.map((t) => ({ AspectName: t, Polarity: 'Positive' })) };
  }
  if (url === '/api/after-sales') {
    const row = { ServiceID: 11, ServiceType: body.serviceType, PreferredDate: body.preferredDate, Status: 'Pending', WarrantyCode: body.warrantyCode, CustomerNote: body.note, CreatedAt: '2030-01-01T09:00:00' };
    server.services.push(row); return row;
  }
  if (url === '/api/after-sales/11/cancel') { server.services[0].Status = 'Cancelled'; return server.services[0]; }
  if (url === '/api/cart') { server.cart.push({ CartItemID: server.cart.length + 1, VariantSKU: body.variantSku, SKU: 'SP1', ProductName: 'Nhẫn', Quantity: body.quantity, UnitPrice: 1000, StockQuantity: 9 }); return {}; }
  throw new Error('unexpected POST ' + url);
};
// The catalog: SP1 is on sale, STOP is not in it (stopped), QUOTE is quote only
const theoMa = { SP1: { ma: 'SP1', coTheMua: true, giaBan: 1000 }, QUOTE: { ma: 'QUOTE', coTheMua: false } };
VN.duLieu.coBan = async () => ({ sp: { theoMa } });
VN.duLieu.chiTietSanPham = async () => ({ coTheMua: true, canChonSize: false, bienThe: [{ ma: 'SP1-V', mau: 'Vàng', size: null, tonKho: 9 }] });

VN.api.del = async (url) => {
  if (server.delDown) throw loi(0);
  if (server.delDelay) await new Promise((r) => setTimeout(r, server.delDelay));
  if (url === '/api/recently-viewed') server.viewed = [];
  else server.viewed = server.viewed.filter((x) => x !== decodeURIComponent(url.split('/').pop()));
};
const tick = () => new Promise((r) => setTimeout(r, 30));      // lets the background requests finish
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

  // 7. A booking or a cancellation that went through is not reported as failed when the list cannot be reloaded after it
  VN.taiKhoan.nguoi = { id: 5 }; VN.taiKhoan.khongRo = false; VN.gioHang.khongTai = false;
  server.up = true; server.listDown = true;
  const booked = await attempt(() => VN.lichHen.tao({ maBaoHanh: 'VNW26110000001-1', loai: 'Cleaning', ngay: '2030-02-01', gio: '10:00', tenCuaHang: 'Showroom A', sdt: '0911000111', soAnh: 0, ghiChu: '' }));
  out.bookedWhileListDown = { ok: booked.ok, id: booked.ok ? booked.value.id : null, listed: VN.lichHen.ds.map((l) => l.id) };
  const cancelled = await attempt(() => VN.lichHen.huy('LH11'));
  out.cancelledWhileListDown = { ok: cancelled.ok, status: VN.lichHen.ds.map((l) => l.trangThai) };

  // 8. Logging out empties the cards and appointments of the account that left
  server.listDown = false; VN.baoHanh.ds = [{ ma: 'VNW26110000001-1' }];
  await VN.taiKhoan.dangXuat();
  out.afterLogout = { cards: VN.baoHanh.ds.length, services: VN.lichHen.ds.length };

  // 9. Recently viewed: a visitor's list stays here; at login it joins the account's; a customer's list is on the server
  const ma = () => VN.daXem.ds().map((x) => x.ma);
  VN.taiKhoan.nguoi = null; server.me = null;
  VN.daXem.ghi('A'); VN.daXem.ghi('B');
  out.visitorViewed = { list: ma(), server: server.viewed.slice() };
  VN.kho.ghi('daXem', [{ ma: 'B', luc: 2000 }, { ma: 'A', luc: 1000 }]);
  server.viewed = ['X']; VN.taiKhoan.nguoi = { id: 5 };
  await VN.daXem.gopKhach();
  out.viewedMerged = { server: server.viewed.slice(), list: ma(), local: VN.kho.doc('daXem', []).length };
  VN.daXem.ghi('A');
  out.viewedAtOnce = ma(); await tick();
  out.viewedOnServer = server.viewed.slice();
  VN.daXem.xoa('B');
  out.removedAtOnce = ma(); await tick();
  out.removedOnServer = server.viewed.slice();
  server.delDown = true; VN.daXem.xoa('X');
  out.failedRemoveAtOnce = ma(); await tick();
  out.failedRemoveAfterReload = ma();                       // the server still has X, so the list shows it again
  server.delDown = false; VN.daXem.xoaHet();
  out.clearedAtOnce = ma(); await tick();
  VN.daXem.khoiPhuc([{ ma: 'X', luc: 3000 }, { ma: 'A', luc: 5000 }]);
  out.restoredAtOnce = ma(); await tick();
  out.restoredOnServer = server.viewed.slice();
  VN.daXem.xoa('X'); await tick();
  VN.daXem.khoiPhuc([{ ma: 'X', luc: 1 }]); await tick();      // an old entry comes back as the newest, on the page and on the server
  out.restoredOneAfter = { list: ma(), server: server.viewed.slice() };
  await VN.daXem.nap();
  out.restoredOneReload = ma();

  // 9b. The merge at login: a product that is gone (404) is skipped; any other failure keeps this browser's list and still shows the account's
  server.viewed = ['X']; server.gone = ['GONE']; VN.kho.ghi('daXem', [{ ma: 'GONE', luc: 2 }, { ma: 'A', luc: 1 }]);
  await VN.daXem.gopKhach();
  out.mergeSkipsGone = { server: server.viewed.slice(), local: VN.kho.doc('daXem', []).length };
  out.mergeFailures = [];
  for (const status of [500, 401, 0]) {
    server.postFails = status; VN.kho.ghi('daXem', [{ ma: 'B', luc: 1 }]);
    const merged = await attempt(() => VN.daXem.gopKhach());
    out.mergeFailures.push({ status, rejected: !merged.ok, local: VN.kho.doc('daXem', []).length, list: ma() });
  }
  server.postFails = null; VN.kho.ghi('daXem', []);

  // 9c. A removal followed at once by its undo must reach the server in that order, even when the removal is slow
  server.viewed = ['A']; VN.daXem.luu = [{ ma: 'A', luc: Date.now() }]; server.delDelay = 40;
  VN.daXem.xoa('A'); VN.daXem.khoiPhuc([{ ma: 'A', luc: 1 }]);
  await new Promise((r) => setTimeout(r, 200)); server.delDelay = 0;
  out.removeThenUndo = { list: ma(), server: server.viewed.slice() };

  // 10. A review goes to the server as the API wants it, and comes back in the shape the pages use
  const review = await attempt(() => VN.danhGia.tao({ donHang: 'VN123', soSao: 4, noiDung: 'Đẹp', chuDe: ['Đúng size'] }));
  out.review = { sent: server.reviews[0], ok: review.ok, result: review.value };

  // 11. Ticks of a visitor's cart: an un-ticked line stays un-ticked after "undo", after a change of its choices, and a
  //     line merged into another one does not change the tick of that line
  VN.taiKhoan.nguoi = null; VN.taiKhoan.khongRo = false; VN.gioHang.khongTai = false;
  VN.kho.ghi('gioHang', []); VN.kho.ghi('gioBoChon', []);
  await VN.gioHang.them({ ma: 'SP1', mau: 'Vàng', soLuong: 1 });
  await VN.gioHang.them({ ma: 'SP1', mau: 'Vàng', soLuong: 1, khacChu: 'AB', kieuChu: 'co-dien' });
  const kPlain = VN.gioHang.khoa({ ma: 'SP1', mau: 'Vàng' });
  const kAB = VN.gioHang.khoa({ ma: 'SP1', mau: 'Vàng', khacChu: 'AB', kieuChu: 'co-dien' });
  VN.gioHang.datChon(kPlain, false);
  const removedPlain = await VN.gioHang.xoa(kPlain);
  VN.gioHang.donBoChon();                       // the cart page tidies the ticks of lines that left the cart
  await VN.gioHang.khoiPhuc(removedPlain);
  const removedAB = await VN.gioHang.xoa(kAB);
  VN.gioHang.donBoChon();
  await VN.gioHang.khoiPhuc(removedAB);
  out.undoKeepsTicks = { plainTicked: VN.gioHang.daChon(kPlain), abTicked: VN.gioHang.daChon(kAB), stored: gioKhach().map((d) => d.ma).length };
  const kXY = VN.gioHang.khoa({ ma: 'SP1', mau: 'Vàng', khacChu: 'XY', kieuChu: 'co-dien' });
  const changed = await VN.gioHang.capNhatDong(kPlain, { khacChu: 'XY', kieuChu: 'co-dien' });
  VN.gioHang.donBoChon();
  out.changedKeepsUntick = { newKey: changed === kXY, xyTicked: VN.gioHang.daChon(kXY), plainTicked: VN.gioHang.daChon(kPlain) };
  await VN.gioHang.capNhatDong(kXY, { khacChu: 'AB', kieuChu: 'co-dien' });      // the same choices as the ticked line: they merge
  out.mergedKeepsTargetTick = { abTicked: VN.gioHang.daChon(kAB), lines: gioKhach().length, quantity: gioKhach()[0].soLuong };

  console.log(JSON.stringify(out));
})().catch((e) => { console.error(e); process.exit(1); });
