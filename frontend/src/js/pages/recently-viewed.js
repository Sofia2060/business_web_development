/* =====================================================================
   5.2.4 SẢN PHẨM ĐÃ XEM (FR8) – tham khảo cách trình bày của LiLi
   - Ghi nhận ở trang chi tiết (VN.daXem.ghi), hiển thị theo lần xem gần nhất
   - Nhóm theo thời gian: Hôm nay / Hôm qua / 7 ngày qua / Trước đó
   - Lọc theo loại trang sức, sắp xếp theo giá
   - Xóa từng sản phẩm (có hoàn tác), xóa toàn bộ lịch sử (có xác nhận + hoàn tác)
   - So sánh tối đa 3 mẫu: chất liệu, tuổi vàng, trọng lượng, đá, giá (mục 3.3 – bảng tính năng)
   - Gợi ý sản phẩm dựa trên danh mục / bộ sưu tập / khoảng giá đã xem
   ===================================================================== */
(function () {
  'use strict';
  const VN = window.Vinora;
  const ketQua = VN.$('#dx-ket-qua');
  if (!ketQua) return;

  const TOI_DA_SS = 3;
  const KHOA_SS = 'vinora.soSanh';
  const tt = { tat: [], loc: 'tat-ca', sapXep: 'gan-nhat', soSanh: [], sp: null, ch: null, anDi: 0 };
  try { tt.soSanh = JSON.parse(sessionStorage.getItem(KHOA_SS) || '[]'); } catch (e) { tt.soSanh = []; }
  const luuSoSanh = () => { try { sessionStorage.setItem(KHOA_SS, JSON.stringify(tt.soSanh)); } catch (e) { /* bỏ qua */ } };

  VN.$('.luoi-sp', ketQua).innerHTML = VN.theXuong(8);

  VN.duLieu.coBan().then(({ sp, ch }) => {
    tt.sp = sp; tt.ch = ch;
    napLai();
  }).catch((loi) => {
    console.error(loi);
    ketQua.innerHTML = '';
    VN.thongBao({ tieuDe: 'Chưa tải được dữ liệu sản phẩm', noiDung: 'Vui lòng kiểm tra kết nối mạng rồi tải lại trang.', loai: 'loi' });
  });

  /* Đọc lịch sử xem, ghép dữ liệu sản phẩm mới nhất (bỏ qua mẫu đã ngừng kinh doanh) */
  const napLai = () => {
    const ds = VN.daXem.ds();
    tt.tat = ds.map((x) => ({ sp: tt.sp.theoMa[x.ma], luc: x.luc })).filter((x) => x.sp);
    tt.anDi = ds.length - tt.tat.length;
    ve();
    veGoiY();
  };

  /* ================= HIỂN THỊ DANH SÁCH ================= */
  const nhomCua = (s) => s.dm.nhom || s.dm.ten;
  const theDaXem = ({ sp, luc }) => {
    const the = VN.theSanPham(sp);
    the.classList.add('the-dx');
    the.dataset.ma = sp.ma;
    const xoa = document.createElement('button');
    xoa.type = 'button';
    xoa.className = 'nut-bt nut-bt--nen the-dx__xoa';
    xoa.dataset.xoa = sp.ma;
    xoa.setAttribute('aria-label', `Xóa ${sp.ten} (${sp.ma}) khỏi lịch sử xem`);
    xoa.title = 'Xóa khỏi lịch sử xem';
    xoa.innerHTML = VN.bt('dong', 'bt--nho');
    const chan = document.createElement('div');
    chan.className = 'the-dx__chan';
    const daChon = tt.soSanh.includes(sp.ma);
    chan.innerHTML = `<span class="the-dx__luc" title="Xem lúc ${VN.ngayGio(luc)}">${VN.bt('dong-ho', 'bt--nho')}${VN.thoiGianTruoc(luc)}</span>
      <label class="lua-chon the-dx__ss"><input type="checkbox" data-ss="${VN.thoat(sp.ma)}"${daChon ? ' checked' : ''} aria-label="So sánh ${VN.thoat(sp.ten)} (${VN.thoat(sp.ma)})"> <span>So sánh</span></label>`;
    the.append(xoa, chan);
    the.classList.toggle('dang-ss', daChon);
    return the;
  };
  const luoiTu = (ds) => {
    const luoi = document.createElement('div');
    luoi.className = 'luoi-sp';
    ds.forEach((m) => luoi.appendChild(theDaXem(m)));
    return luoi;
  };

  const ve = () => {
    const tat = tt.tat; const co = tat.length > 0;
    VN.$('#dx-trong').hidden = co;
    VN.$('#dx-cong-cu').hidden = !co;
    VN.$('#dx-xoa-het').hidden = !co;
    VN.$('#dx-ghi-chu').hidden = !co;
    VN.$('#dx-meo').hidden = tat.length < 2;
    VN.$('#dx-tom-tat').textContent = co
      ? `Bạn đã xem ${tat.length} mẫu trang sức${tt.anDi ? ` (${tt.anDi} mẫu ngừng kinh doanh đã được ẩn)` : ''}. Danh sách sắp xếp theo lần xem gần nhất.`
      : 'Những mẫu trang sức bạn mở xem sẽ được lưu tại đây.';
    ketQua.removeAttribute('aria-busy');
    if (!co) { ketQua.innerHTML = ''; capNhatKhay(); return; }

    // Nút lọc theo loại trang sức (đếm trên toàn bộ lịch sử)
    const dem = {};
    tat.forEach(({ sp }) => { const n = nhomCua(sp); dem[n] = (dem[n] || 0) + 1; });
    if (tt.loc !== 'tat-ca' && !dem[tt.loc]) tt.loc = 'tat-ca';
    VN.$('#dx-loc').innerHTML = [['tat-ca', 'Tất cả', tat.length]]
      .concat(Object.entries(dem).sort((a, b) => b[1] - a[1]).map(([k, v]) => [k, k, v]))
      .map(([k, ten, n]) => `<button type="button" class="chip chip--nho" data-loc="${VN.thoat(k)}" aria-pressed="${k === tt.loc}">${VN.thoat(ten)} <span class="dem">${n}</span></button>`).join('');

    let ds = tat.filter(({ sp }) => tt.loc === 'tat-ca' || nhomCua(sp) === tt.loc);
    ketQua.innerHTML = '';
    if (tt.sapXep === 'gan-nhat') {
      // Nhóm theo mốc thời gian xem (như trang lịch sử xem của LiLi)
      const homNay = new Date().setHours(0, 0, 0, 0);
      const moc = [['Hôm nay', homNay], ['Hôm qua', homNay - 864e5], ['7 ngày qua', homNay - 6 * 864e5], ['Trước đó', -Infinity]];
      const nhom = moc.map(([ten]) => [ten, []]);
      ds.forEach((m) => { nhom[moc.findIndex(([, tu]) => m.luc >= tu)][1].push(m); });
      nhom.filter(([, d]) => d.length).forEach(([ten, d], i) => {
        const phan = document.createElement('section');
        phan.className = 'nhom-dx';
        phan.setAttribute('aria-labelledby', 'nhom-dx-' + i);
        phan.innerHTML = `<h2 class="nhom-dx__tieu-de" id="nhom-dx-${i}">${ten}<span>${d.length} sản phẩm</span></h2>`;
        phan.appendChild(luoiTu(d));
        ketQua.appendChild(phan);
      });
    } else {
      const huong = tt.sapXep === 'gia-tang' ? 1 : -1;
      ds = ds.slice().sort((a, b) => {
        if (a.sp.coTheMua !== b.sp.coTheMua) return a.sp.coTheMua ? -1 : 1;   // sản phẩm báo giá xếp cuối
        return huong * ((a.sp.giaBan || a.sp.gia) - (b.sp.giaBan || b.sp.gia));
      });
      const phan = document.createElement('section');
      phan.className = 'nhom-dx';
      phan.appendChild(luoiTu(ds));
      ketQua.appendChild(phan);
    }
    capNhatKhay();
  };

  VN.$('#dx-loc').addEventListener('click', (e) => {
    const b = e.target.closest('[data-loc]'); if (!b) return;
    tt.loc = b.dataset.loc; ve();
  });
  VN.$('#dx-sap-xep').addEventListener('change', (e) => { tt.sapXep = e.target.value; ve(); });

  /* ================= XÓA TỪNG MỤC / XÓA TẤT CẢ (CÓ HOÀN TÁC) ================= */
  ketQua.addEventListener('click', (e) => {
    const b = e.target.closest('[data-xoa]'); if (!b) return;
    const ma = b.dataset.xoa;
    const muc = VN.daXem.ds().find((x) => x.ma === ma);
    const the = b.closest('.the-sp');
    const ten = tt.sp.theoMa[ma] ? tt.sp.theoMa[ma].ten : ma;
    the.classList.add('dang-xoa');
    setTimeout(() => {
      VN.daXem.xoa(ma);
      tt.soSanh = tt.soSanh.filter((x) => x !== ma);
      napLai();
      VN.thongBao({
        tieuDe: 'Đã xóa khỏi lịch sử xem', noiDung: VN.thoat(ten),
        hanhDong: { chu: 'Hoàn tác', khiBam: () => { if (muc) VN.daXem.khoiPhuc(muc); napLai(); } },
      });
    }, 220);
  });

  VN.$('#dx-xoa-het').addEventListener('click', async () => {
    const n = tt.tat.length;
    const dongY = await VN.xacNhan({
      nhan: 'Lịch sử xem', tieuDe: 'Xóa toàn bộ lịch sử xem?',
      noiDung: `${n} sản phẩm sẽ được xóa khỏi danh sách này. Bạn vẫn có thể hoàn tác ngay sau khi xóa.`,
      chuDongY: 'Xóa tất cả', chuHuy: 'Giữ lại', nguy: true,
    });
    if (!dongY) return;
    const cu = VN.daXem.ds();
    VN.daXem.xoaHet();
    tt.soSanh = [];
    napLai();
    VN.thongBao({ tieuDe: 'Đã xóa lịch sử xem', noiDung: `${n} sản phẩm đã được xóa.`, hanhDong: { chu: 'Hoàn tác', khiBam: () => { VN.daXem.khoiPhuc(cu); napLai(); } }, thoiGian: 6000 });
  });

  /* ================= SO SÁNH TỐI ĐA 3 SẢN PHẨM ================= */
  const khay = VN.$('#khay-so-sanh');
  const capNhatKhay = () => {
    tt.soSanh = tt.soSanh.filter((ma) => tt.tat.some((m) => m.sp.ma === ma));
    luuSoSanh();
    const n = tt.soSanh.length;
    khay.classList.toggle('dang-hien', n > 0);
    khay.setAttribute('aria-hidden', String(n === 0));
    khay.inert = n === 0;
    document.body.classList.toggle('co-khay-ss', n > 0);
    VN.$('#ss-dem').textContent = `${n}/${TOI_DA_SS} sản phẩm`;
    const nutMo = VN.$('#ss-mo');
    nutMo.disabled = n < 2;
    nutMo.textContent = n < 2 ? 'Chọn thêm 1 mẫu' : `So sánh ${n} mẫu`;
    VN.$('#ss-ds').innerHTML = Array.from({ length: TOI_DA_SS }, (_, i) => {
      const s = tt.soSanh[i] && tt.sp.theoMa[tt.soSanh[i]];
      if (!s) return '<li class="khay-so-sanh__muc khay-so-sanh__muc--trong"><span>Thêm mẫu để so sánh</span></li>';
      return `<li class="khay-so-sanh__muc"><img src="${VN.anh(s.anh[0])}" alt=""${VN.laAnhChup(s.anh[0]) ? ' class="la-anh-chup"' : ''}><span>${VN.thoat(s.ten)}<small>${VN.thoat(s.ma)}</small></span>
        <button type="button" class="nut-bt" data-bo-ss="${VN.thoat(s.ma)}" aria-label="Bỏ ${VN.thoat(s.ten)} khỏi so sánh">${VN.bt('dong', 'bt--nho')}</button></li>`;
    }).join('');
    VN.$$('[data-ss]', ketQua).forEach((o) => {
      o.checked = tt.soSanh.includes(o.dataset.ss);
      o.closest('.the-sp').classList.toggle('dang-ss', o.checked);
    });
  };

  ketQua.addEventListener('change', (e) => {
    const o = e.target.closest('[data-ss]'); if (!o) return;
    const ma = o.dataset.ss;
    if (o.checked) {
      if (tt.soSanh.length >= TOI_DA_SS) {
        o.checked = false;
        VN.thongBao({ tieuDe: `Chỉ so sánh tối đa ${TOI_DA_SS} sản phẩm`, noiDung: 'Bỏ chọn một mẫu trong khay so sánh để thêm mẫu khác.' });
        return;
      }
      tt.soSanh.push(ma);
    } else tt.soSanh = tt.soSanh.filter((x) => x !== ma);
    capNhatKhay();
  });
  VN.$('#ss-ds').addEventListener('click', (e) => {
    const b = e.target.closest('[data-bo-ss]'); if (!b) return;
    tt.soSanh = tt.soSanh.filter((x) => x !== b.dataset.boSs);
    capNhatKhay();
  });
  VN.$('#ss-bo').addEventListener('click', () => { tt.soSanh = []; capNhatKhay(); });

  const hop = VN.$('#hop-so-sanh'); const bang = VN.$('#ss-bang');
  const moSoSanh = () => {
    const ds = tt.soSanh.map((ma) => tt.sp.theoMa[ma]).filter(Boolean);
    if (ds.length < 2) return;
    const ch = tt.ch;
    const coGia = ds.filter((s) => s.coTheMua);
    const giaThap = coGia.length > 1 ? Math.min(...coGia.map((s) => s.giaBan)) : null;
    const nhe = ds.filter((s) => s.trongLuong);
    const khacChu = (s) => (ch.khacChu.apDungDanhMuc || []).includes(s.danhMuc);
    // [tên thông số, cách hiển thị, giá trị dùng để nhận biết khác nhau]
    const hang = [
      ['Giá', (s) => (s.coTheMua ? VN.giaHtml(s) + (s.giaBan === giaThap ? '<span class="nhan nhan--ngoc">Giá tốt nhất</span>' : '') : `Giá vàng theo ngày<small>Tiền công ${VN.tien(s.gia)}</small>`), (s) => (s.coTheMua ? s.giaBan : 'cong' + s.gia)],
      ['Chất liệu', (s) => `${VN.thoat(s.tenChatLieu)}<small>${VN.hamLuong(s, ch)}</small>`, (s) => s.chatLieu],
      ['Màu sắc', (s) => (s.mau.length ? VN.thoat(s.mau.join(', ')) : '—'), (s) => s.mau.join(',')],
      ['Trọng lượng', (s) => (s.trongLuong ? `≈ ${VN.so(s.trongLuong)} gram${nhe.length > 1 && s.trongLuong === Math.max(...nhe.map((x) => x.trongLuong)) ? '<small>Nặng nhất trong nhóm so sánh</small>' : ''}` : '—'), (s) => s.trongLuong || ''],
      ['Thông tin đá', (s) => (s.da ? `${VN.loaiDa(s.ten)[0]}<small>${VN.kichThuocDa(s.da.kichThuoc)} × ${s.da.soVien} viên</small>` : VN.coDa(s) ? `${VN.loaiDa(s.ten)[0]}<small>Thông số đang cập nhật</small>` : 'Không đính đá'), (s) => (s.da ? VN.loaiDa(s.ten)[0] + s.da.kichThuoc + s.da.soVien : VN.coDa(s) ? VN.loaiDa(s.ten)[0] : '')],
      ['Loại trang sức', (s) => VN.thoat(s.dm.ten), (s) => s.danhMuc],
      ['Bộ sưu tập', (s) => VN.thoat(s.bst.ten || '—'), (s) => s.boSuuTap],
      ['Chọn size', (s) => (s.canChonSize ? `Bắt buộc, size ${ch.sizeNhan.nhoNhat} – ${ch.sizeNhan.lonNhat}` : 'Không cần chọn size'), (s) => s.canChonSize],
      ['Khắc chữ laser', (s) => (khacChu(s) ? `Miễn phí<small>Tối đa ${ch.khacChu.toiDaKyTu} ký tự</small>` : 'Không áp dụng'), (s) => khacChu(s)],
      ['Bảo hành', () => 'Thẻ bảo hành điện tử trọn đời', () => 'bh'],
    ];
    bang.innerHTML = `
      <caption class="an-chu">So sánh ${ds.length} sản phẩm đã xem</caption>
      <colgroup><col class="ss-cot-ten">${ds.map(() => '<col>').join('')}</colgroup>
      <thead><tr><th scope="col"><span class="an-chu">Thông số</span></th>${ds.map((s) => `<th scope="col">
        <div class="ss-sp"><a class="ss-sp__anh" href="${VN.urlSanPham(s.ma)}" tabindex="-1" aria-hidden="true"><img src="${VN.anh(s.anh[0])}" alt=""${VN.laAnhChup(s.anh[0]) ? ' class="la-anh-chup"' : ''}></a>
        <a class="ss-sp__ten" href="${VN.urlSanPham(s.ma)}">${VN.thoat(s.ten)}</a><span class="ss-sp__ma">${VN.thoat(s.ma)}</span></div></th>`).join('')}</tr></thead>
      <tbody>${hang.map(([ten, hien, giaTri]) => {
        const khac = new Set(ds.map((s) => String(giaTri(s)))).size > 1;
        return `<tr data-khac="${khac}"><th scope="row">${ten}</th>${ds.map((s) => `<td>${hien(s)}</td>`).join('')}</tr>`;
      }).join('')}</tbody>
      <tfoot><tr><th scope="row"><span class="an-chu">Thao tác</span></th>${ds.map((s) => `<td><div class="ss-nut">
        ${s.coTheMua && !s.canChonSize ? `<button type="button" class="nut nut--chinh nut--rat-nho" data-them="${VN.thoat(s.ma)}">${VN.bt('tui')} Thêm vào giỏ</button>` : ''}
        <a class="nut nut--vien nut--rat-nho" href="${VN.urlSanPham(s.ma)}">${s.canChonSize && s.coTheMua ? 'Chọn size & mua' : s.coTheMua ? 'Xem chi tiết' : 'Nhận báo giá'}</a></div></td>`).join('')}</tr></tfoot>`;
    bang.classList.toggle('chi-khac', VN.$('#ss-khac-biet').checked);
    VN.moHopThoai(hop);
  };
  VN.$('#ss-mo').addEventListener('click', moSoSanh);
  VN.$('#ss-khac-biet').addEventListener('change', (e) => bang.classList.toggle('chi-khac', e.target.checked));
  hop.addEventListener('click', (e) => {
    if (e.target.closest('[data-dong]')) { VN.dongHopThoai(hop); return; }
    const b = e.target.closest('[data-them]'); if (!b) return;
    const s = tt.sp.theoMa[b.dataset.them];
    const dong = { ma: s.ma, soLuong: 1 };
    if (s.mau[0]) dong.mau = s.mau[0];
    VN.gioHang.them(dong, tt.ch.soLuongToiDaMoiDong);
    VN.dongHopThoai(hop);
    VN.moGioMini();
  });

  /* ================= GỢI Ý TỪ LỊCH SỬ XEM ================= */
  let capNhatNutGoiY = null;
  const veGoiY = () => {
    const daXem = new Set(tt.tat.map((m) => m.sp.ma));
    const coTheMua = tt.sp.ds.filter((s) => s.coTheMua && !daXem.has(s.ma));
    let ds;
    if (tt.tat.length) {
      // Điểm gợi ý: cùng danh mục, cùng bộ sưu tập (mẫu xem gần đây có trọng số cao hơn) và gần khoảng giá đã xem
      const diemDm = {}; const diemBst = {};
      tt.tat.forEach(({ sp }, i) => {
        const w = 1 / (1 + i * 0.2);
        diemDm[sp.danhMuc] = (diemDm[sp.danhMuc] || 0) + w;
        diemBst[sp.boSuuTap] = (diemBst[sp.boSuuTap] || 0) + w;
      });
      const gia = tt.tat.filter((m) => m.sp.coTheMua).map((m) => m.sp.giaBan);
      const giaTb = gia.length ? gia.reduce((a, b) => a + b, 0) / gia.length : 10000000;
      ds = coTheMua.map((s) => [(diemDm[s.danhMuc] || 0) * 2 + (diemBst[s.boSuuTap] || 0) * 1.5 - Math.abs(Math.log(s.giaBan / giaTb)) * 0.8, s])
        .sort((a, b) => b[0] - a[0]).slice(0, 12).map((x) => x[1]);
      VN.$('#goi-y-dx-nhan').textContent = 'Gợi ý từ lịch sử xem';
      VN.$('#td-goi-y-dx').textContent = 'Có thể bạn sẽ thích';
    } else {
      ds = coTheMua.slice().sort((a, b) => (b.ngayTao || '').localeCompare(a.ngayTao || '')).slice(0, 12);
      VN.$('#goi-y-dx-nhan').textContent = 'Gợi ý cho bạn';
      VN.$('#td-goi-y-dx').textContent = 'Thiết kế mới nhất';
    }
    const phan = VN.$('#phan-goi-y-dx'); const dai = VN.$('#dai-goi-y-dx');
    phan.hidden = !ds.length;
    VN.veLuoi(dai, ds);
    dai.scrollLeft = 0;
    if (!capNhatNutGoiY) capNhatNutGoiY = VN.ganDieuKhienTruot(dai, VN.$('[data-dieu-khien="dai-goi-y-dx"]'));
    if (capNhatNutGoiY) setTimeout(capNhatNutGoiY, 60);
  };

  // Đồng bộ khi lịch sử xem thay đổi ở thẻ trình duyệt khác
  window.addEventListener('storage', (e) => { if (e.key === 'vinora.daXem' && tt.sp) napLai(); });
})();
