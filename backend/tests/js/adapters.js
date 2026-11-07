// Runs the page-side adapters of frontend/src/js/core/api.js on real API answers, without a browser.
// Usage: node adapters.js <path to api.js> <path to samples.json>   (prints the adapted data as JSON)
// The test backend/tests/test_frontend_adapters.py writes samples.json from the live API and checks this output.
const fs = require('fs');
const vm = require('vm');

const [, , apiFile, samplesFile] = process.argv;
const samples = JSON.parse(fs.readFileSync(samplesFile, 'utf8'));

// The little of common.js that api.js touches while it loads
const VN = { tien: (n) => Math.round(Number(n) || 0).toLocaleString('vi-VN') + ' ₫', phatSuKien() {},
  // dd/mm/yyyy, as in common.js (the warranty card adapter writes the end date of the workmanship warranty)
  ngay: (d) => { d = new Date(d); const h = (n) => String(n).padStart(2, '0'); return `${h(d.getDate())}/${h(d.getMonth() + 1)}/${d.getFullYear()}`; }, danhGia: { theoDon: () => null }, duongDan: {} };
const answer = (body) => ({ ok: true, status: 200, json: async () => body });
const fakeFetch = async (url) => {
  const failure = /^\/api\/error\/(\d+)$/.exec(url);
  if (failure) { const e = samples.errors[Number(failure[1])]; return { ok: false, status: e.status, json: async () => e.body }; }
  const page = /^\/api\/products\?limit=100&page=(\d+)$/.exec(url);
  if (page) return answer(samples.productPages[Number(page[1]) - 1]);
  if (url === '/api/categories') return answer(samples.categories);
  if (url === '/api/collections') return answer(samples.collections);
  if (url.startsWith('/api/products/')) return answer(samples.detail);
  throw new Error('unexpected request ' + url);
};
const sandbox = { window: { Vinora: VN }, console, fetch: fakeFetch, sessionStorage: { getItem: () => null, setItem() {} }, URLSearchParams };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(apiFile, 'utf8'), sandbox);

(async () => {
  const products = await VN.duLieu.sanPham();
  const out = {
    products: products.ds,
    detail: await VN.duLieu.chiTietSanPham(samples.detail.SKU),
    categories: (await VN.duLieu.danhMuc()).ds,
    collections: (await VN.duLieu.boSuuTap()).ds,
    cartLines: samples.cart.items.map(VN.dongGioTuApi),
    customer: VN.khachTuApi(samples.me, samples.profile, samples.addresses),
    orders: samples.orders.map((o) => VN.donHangTuApi(o, { khachId: samples.me.id })),
    orderDetails: samples.orderDetails.map((o) => VN.donHangTuApi(o, { khachId: samples.me.id })),
    guestOrder: VN.donHangTuApi(samples.guestOrder, { sdtKhach: '0912345678' }),
    cards: samples.warranties.map(VN.theBaoHanhTuApi),
    services: samples.services.map(VN.lichHenTuApi),
    reviewedOrder: VN.donHangTuApi(samples.reviewedOrder, { khachId: samples.me.id }),
    reviewedRow: VN.donHangTuApi(samples.reviewedRow, { khachId: samples.me.id }),
    errors: [],
  };
  // What a page writes into the note of an appointment must read back the same
  const note = out.services[0];
  out.noteRoundTrip = VN.ghiChuLich({ tenCuaHang: note.tenCuaHang, sdt: note.sdt, soAnh: note.soAnh, ghiChu: note.ghiChu });
  for (let i = 0; i < (samples.errors || []).length; i += 1) {
    try { await VN.api.get('/api/error/' + i); out.errors.push(null); } catch (e) { out.errors.push({ message: e.message, status: e.trangThai, reason: e.lyDo, code: e.maLoi }); }
  }
  console.log(JSON.stringify(out));
})().catch((e) => { console.error(e); process.exit(1); });
