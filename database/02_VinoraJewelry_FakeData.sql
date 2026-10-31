/* =====================================================================
   VINORA JEWELRY – SINH DỮ LIỆU GIẢ LẬP (chạy SAU file 01_init_schema.sql)
   ---------------------------------------------------------------------
   - Thông tin tự do (họ tên, số điện thoại, địa chỉ, ngày giờ...) được sinh
     ngẫu nhiên từ các danh sách gợi ý.
   - Thông tin có quy tắc (chất liệu, màu vàng, size, trạng thái, phương thức
     thanh toán, loại dịch vụ...) được chọn ngẫu nhiên trong miền giá trị hợp
     lệ hoặc lấy từ dữ liệu đã có (sản phẩm, biến thể) để nhất quán.
   - Đơn hàng đi qua đúng quy trình trạng thái nên trigger tự tạo thẻ bảo hành
     và nhật ký; số tiền, thanh toán, ưu đãi giữ chân, đánh giá đều khớp nhau.
   Số dòng sinh thêm:
     100: Users, Customers, CustomerAddresses, ProductCertificates, GoldPrices,
          Vouchers, CartItems, RecentlyViewedProducts, OrderCancellationRequests,
          CustomerFeedbacks, FeedbackAspects, AfterSalesServices
     300: Orders (cần >= 100 đơn đã nhận để có 100 đánh giá, và 100 đơn có
          yêu cầu hủy); OrderItems, Payments, WarrantyRecords, AuditLogs sinh
          theo đơn hàng.
   Script chạy trong một transaction: lỗi ở bất kỳ bước nào sẽ hoàn tác toàn bộ.
   ===================================================================== */
USE VinoraJewelry;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS (SELECT 1 FROM dbo.Orders WHERE OrderCode LIKE 'VN______F%')
BEGIN
    RAISERROR(N'Dữ liệu giả lập đã tồn tại. Hãy chạy lại file 01_init_schema.sql trước khi sinh lại.', 16, 1);
    RETURN;
END

EXEC sp_set_session_context @key = N'Actor', @value = N'System:FakeDataGenerator';
EXEC sp_set_session_context @key = N'UserID', @value = NULL;

/* ---------- Danh sách giá trị gợi ý ---------- */
DECLARE @Ho TABLE (i INT PRIMARY KEY, v NVARCHAR(20), a VARCHAR(20));
INSERT INTO @Ho VALUES (1,N'Nguyễn','nguyen'),(2,N'Trần','tran'),(3,N'Lê','le'),(4,N'Phạm','pham'),(5,N'Hoàng','hoang'),
(6,N'Huỳnh','huynh'),(7,N'Phan','phan'),(8,N'Vũ','vu'),(9,N'Võ','vo'),(10,N'Đặng','dang'),(11,N'Bùi','bui'),(12,N'Đỗ','do'),
(13,N'Hồ','ho'),(14,N'Ngô','ngo'),(15,N'Dương','duong'),(16,N'Lý','ly');
DECLARE @Dem TABLE (i INT PRIMARY KEY, v NVARCHAR(20));
INSERT INTO @Dem VALUES (1,N'Văn'),(2,N'Thị'),(3,N'Minh'),(4,N'Ngọc'),(5,N'Gia'),(6,N'Thanh'),(7,N'Hoàng'),(8,N'Bảo'),
(9,N'Khánh'),(10,N'Thu'),(11,N'Anh'),(12,N'Quốc'),(13,N'Hải'),(14,N'Phương');
DECLARE @Ten TABLE (i INT PRIMARY KEY, v NVARCHAR(20), a VARCHAR(20));
INSERT INTO @Ten VALUES (1,N'An','an'),(2,N'Bình','binh'),(3,N'Châu','chau'),(4,N'Dung','dung'),(5,N'Giang','giang'),
(6,N'Hà','ha'),(7,N'Hân','han'),(8,N'Huy','huy'),(9,N'Khoa','khoa'),(10,N'Linh','linh'),(11,N'Long','long'),(12,N'Mai','mai'),
(13,N'My','my'),(14,N'Nam','nam'),(15,N'Ngân','ngan'),(16,N'Nhi','nhi'),(17,N'Phúc','phuc'),(18,N'Quân','quan'),
(19,N'Quyên','quyen'),(20,N'Sơn','son'),(21,N'Tâm','tam'),(22,N'Thảo','thao'),(23,N'Trang','trang'),(24,N'Trinh','trinh'),
(25,N'Tú','tu'),(26,N'Uyên','uyen'),(27,N'Vy','vy'),(28,N'Yến','yen'),(29,N'Duy','duy'),(30,N'Khôi','khoi');
DECLARE @Street TABLE (i INT PRIMARY KEY, v NVARCHAR(50));
INSERT INTO @Street VALUES (1,N'Lê Lợi'),(2,N'Nguyễn Huệ'),(3,N'Trần Hưng Đạo'),(4,N'Hai Bà Trưng'),(5,N'Lý Thường Kiệt'),
(6,N'Điện Biên Phủ'),(7,N'Võ Văn Tần'),(8,N'Nguyễn Thị Minh Khai'),(9,N'Pasteur'),(10,N'Cách Mạng Tháng Tám'),
(11,N'Phan Đình Phùng'),(12,N'Hoàng Văn Thụ'),(13,N'Nguyễn Văn Linh'),(14,N'Lê Duẩn'),(15,N'Quang Trung');
DECLARE @Loc TABLE (i INT PRIMARY KEY, ward NVARCHAR(100), province NVARCHAR(100));
INSERT INTO @Loc VALUES
(1,N'Phường Sài Gòn',N'Thành phố Hồ Chí Minh'),(2,N'Phường Bến Thành',N'Thành phố Hồ Chí Minh'),(3,N'Phường Tân Định',N'Thành phố Hồ Chí Minh'),
(4,N'Phường Thủ Đức',N'Thành phố Hồ Chí Minh'),(5,N'Phường Linh Xuân',N'Thành phố Hồ Chí Minh'),(6,N'Phường Gò Vấp',N'Thành phố Hồ Chí Minh'),
(7,N'Phường Hoàn Kiếm',N'Thành phố Hà Nội'),(8,N'Phường Ba Đình',N'Thành phố Hà Nội'),(9,N'Phường Cầu Giấy',N'Thành phố Hà Nội'),
(10,N'Phường Đống Đa',N'Thành phố Hà Nội'),(11,N'Phường Hải Châu',N'Thành phố Đà Nẵng'),(12,N'Phường Sơn Trà',N'Thành phố Đà Nẵng'),
(13,N'Phường Ninh Kiều',N'Thành phố Cần Thơ'),(14,N'Phường Biên Hòa',N'Tỉnh Đồng Nai'),(15,N'Phường Trấn Biên',N'Tỉnh Đồng Nai');
DECLARE @Prefix TABLE (i INT PRIMARY KEY, v VARCHAR(3));
INSERT INTO @Prefix VALUES (1,'090'),(2,'091'),(3,'093'),(4,'094'),(5,'096'),(6,'097'),(7,'098'),(8,'086'),(9,'088'),(10,'089'),
(11,'070'),(12,'079'),(13,'077'),(14,'081'),(15,'083'),(16,'085'),(17,'032'),(18,'033'),(19,'035'),(20,'038');
DECLARE @Domain TABLE (i INT PRIMARY KEY, v VARCHAR(20));
INSERT INTO @Domain VALUES (1,'gmail.com'),(2,'gmail.com'),(3,'yahoo.com'),(4,'outlook.com'),(5,'icloud.com');
DECLARE @Engrave TABLE (i INT PRIMARY KEY, v NVARCHAR(30));
INSERT INTO @Engrave VALUES (1,N'Mãi bên nhau'),(2,N'Forever'),(3,N'Love'),(4,N'H & L'),(5,N'Kỷ niệm 1 năm'),(6,N'Always'),
(7,N'T ♥ A'),(8,N'14.02.2026'),(9,N'My Love'),(10,N'N & K');
DECLARE @Reason TABLE (i INT PRIMARY KEY, v NVARCHAR(200));
INSERT INTO @Reason VALUES (1,N'Muốn chọn mẫu khác'),(2,N'Phân vân về ngân sách'),(3,N'Đặt nhầm size'),(4,N'Thời gian giao không kịp dịp tặng'),
(5,N'Tìm được nơi bán giá tốt hơn'),(6,N'Đổi ý, chưa cần mua'),(7,N'Muốn đổi sang chất liệu khác');
DECLARE @Note TABLE (i INT PRIMARY KEY, v NVARCHAR(200));
INSERT INTO @Note VALUES (1,N'Nhờ shop gói quà giúp'),(2,N'Giao giờ hành chính'),(3,N'Gọi trước khi giao'),(4,N'Quà tặng sinh nhật, đừng để hóa đơn trong hộp'),(5,N'Giao buổi tối sau 18h');
-- Mẫu nhận xét: nhóm 1 = tích cực (4–5 sao), 2 = tiêu cực (1–2 sao), 3 = trung tính (3 sao)
DECLARE @Tpl TABLE (i INT PRIMARY KEY, grp TINYINT, txt NVARCHAR(300), label VARCHAR(10), aspect NVARCHAR(50), polarity VARCHAR(10));
INSERT INTO @Tpl VALUES
(1,1,N'Nhẫn sáng bóng, đúng như hình, rất hài lòng.','Positive',N'Độ sáng bóng','Positive'),
(2,1,N'Hộp đóng gói sang trọng, tặng quà rất ưng.','Positive',N'Đóng gói','Positive'),
(3,1,N'Giao hàng nhanh, nhân viên tư vấn nhiệt tình.','Positive',N'Giao hàng','Positive'),
(4,1,N'Đeo vừa size, hướng dẫn đo size rất dễ làm theo.','Positive',N'Size nhẫn','Positive'),
(5,1,N'Thông tin tuổi vàng và giấy kiểm định rõ ràng, yên tâm khi mua.','Positive',N'Minh bạch thông tin','Positive'),
(6,1,N'Thẻ bảo hành điện tử tiện, đặt lịch đánh bóng nhanh.','Positive',N'Dịch vụ hậu mãi','Positive'),
(7,1,N'Thiết kế tinh tế, đeo hằng ngày rất đẹp.','Positive',N'Thiết kế','Positive'),
(8,2,N'Nhẫn bị rộng so với size đã chọn, phải đi chỉnh lại.','Negative',N'Size nhẫn','Negative'),
(9,2,N'Giao trễ so với ngày kỷ niệm, khá thất vọng.','Negative',N'Giao hàng','Negative'),
(10,2,N'Hộp bị móp nhẹ khi nhận hàng.','Negative',N'Đóng gói','Negative'),
(11,2,N'Sản phẩm nhỏ hơn hình mẫu, độ sáng chưa như kỳ vọng.','Negative',N'Độ sáng bóng','Negative'),
(12,2,N'Liên hệ hỗ trợ đổi lịch bảo hành hơi lâu.','Negative',N'Dịch vụ hậu mãi','Negative'),
(13,3,N'Sản phẩm đẹp nhưng giao hàng chậm hơn dự kiến.','Negative',N'Giao hàng','Negative'),
(14,3,N'Chất lượng ổn, giá hơi cao so với trọng lượng.','Negative',N'Giá cả','Negative'),
(15,3,N'Đóng gói đẹp, tuy nhiên size hơi chật một chút.','Positive',N'Đóng gói','Positive');

DECLARE @AdminID INT = (SELECT TOP (1) UserID FROM dbo.Users WHERE Role = 'Admin' ORDER BY UserID);
DECLARE @RetentionVoucherID INT = (SELECT VoucherID FROM dbo.Vouchers WHERE VoucherCode = 'GIUDON30');
DECLARE @Now DATETIME2(0) = SYSDATETIME();
DECLARE @Today DATETIME2(0) = CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME2(0));

BEGIN TRY
    BEGIN TRANSACTION;

    IF @AdminID IS NULL
    BEGIN
        INSERT INTO dbo.Users (Username, FullName, Email, PasswordHash, Role)
        VALUES ('admin', N'Quản trị viên Vinora', 'admin@vinora.vn', '$2b$12$DemoHashAdmin.OnlyForSampleData.xxxxxxxxxxxxxxxxxxxxxxxx', 'Admin');
        SET @AdminID = SCOPE_IDENTITY();
    END
    IF @RetentionVoucherID IS NULL
        THROW 51000, N'Không tìm thấy voucher GIUDON30 – hãy chạy file 01_init_schema.sql trước.', 1;

    /* =================================================================
       1. GoldPrices – 100 dòng: 20 mốc giá (2 tuần/lần) x 5 tuổi vàng
       ================================================================= */
    DECLARE @GD TABLE (k INT PRIMARY KEY, r1 INT);
    INSERT INTO @GD (k, r1)
    SELECT TOP (20) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, CHECKSUM(NEWID()) & 2147483647 FROM sys.all_objects;
    DECLARE @Mat TABLE (Material VARCHAR(10) PRIMARY KEY, k DECIMAL(6,4));
    INSERT INTO @Mat VALUES ('24K',1.0000),('22K',0.9161),('18K',0.7501),('14K',0.5831),('10K',0.4160);

    INSERT INTO dbo.GoldPrices (Material, BuyPricePerChi, SellPricePerChi, EffectiveFrom, UpdatedByUserID)
    SELECT m.Material,
           ROUND((12000000 + g.k * 130000 + g.r1 % 200000 - 300000) * m.k, -4),
           ROUND((12000000 + g.k * 130000 + g.r1 % 200000) * m.k, -4),
           DATEADD(MINUTE, 510, CAST(DATEADD(WEEK, 2 * g.k, CAST('2025-11-03' AS DATE)) AS DATETIME2(0))),
           @AdminID
    FROM @GD g CROSS JOIN @Mat m;

    /* =================================================================
       2. Vouchers – 100 dòng (90 khuyến mãi, 10 giữ chân)
       ================================================================= */
    DECLARE @Vc TABLE (n INT PRIMARY KEY, r1 INT, r2 INT, r3 INT, r4 INT, r5 INT, r6 INT, r7 INT, r8 INT, r9 INT,
                       VType VARCHAR(15), DType VARCHAR(10), DValue DECIMAL(15,0), DMax DECIMAL(15,0), MinOrder DECIMAL(15,0),
                       StartAt DATETIME2(0), EndAt DATETIME2(0), UsageLimit INT, UsedCount INT, IsActive BIT, VName NVARCHAR(150));
    INSERT INTO @Vc (n, r1, r2, r3, r4, r5, r6, r7, r8, r9)
    SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647,
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647,
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647
    FROM sys.all_objects;

    UPDATE @Vc SET VType = CASE WHEN n % 10 = 0 THEN 'Retention' ELSE 'Promotion' END;
    UPDATE @Vc SET DType = CASE WHEN VType = 'Retention' OR r1 % 2 = 0 THEN 'Percent' ELSE 'Amount' END;
    UPDATE @Vc SET
        DValue   = CASE WHEN DType = 'Percent' THEN CHOOSE(r2 % 5 + 1, 5, 8, 10, 15, 20)
                        ELSE CHOOSE(r2 % 5 + 1, 100000, 200000, 300000, 500000, 1000000) END,
        DMax     = CASE WHEN DType = 'Percent' THEN CHOOSE(r3 % 4 + 1, 300000, 500000, 1000000, 2000000) END,
        StartAt  = DATEADD(DAY, r5 % 150, CAST('2026-01-01' AS DATETIME2(0))),
        UsageLimit = CHOOSE(r7 % 5 + 1, 50, 100, 200, 500, NULL),
        IsActive = CASE WHEN r9 % 10 = 0 THEN 0 ELSE 1 END;
    UPDATE @Vc SET
        MinOrder = CASE WHEN VType = 'Retention' THEN 5000000
                        WHEN DType = 'Amount' THEN DValue * 10
                        ELSE CHOOSE(r4 % 4 + 1, 0, 1000000, 2000000, 5000000) END,
        EndAt    = DATEADD(DAY, 60 + r6 % 300, StartAt),
        UsedCount = CASE WHEN UsageLimit IS NULL THEN r8 % 100 ELSE r8 % (UsageLimit / 2) END;
    UPDATE @Vc SET VName = CASE
        WHEN VType = 'Retention' THEN CONCAT(N'Ưu đãi giữ đơn – giảm thêm ', DValue, N'%')
        WHEN DType = 'Percent'   THEN CONCAT(N'Giảm ', DValue, N'% (tối đa ', FORMAT(DMax, 'N0', 'vi-VN'), N'đ) – tháng ', MONTH(StartAt))
        ELSE CONCAT(N'Giảm ', FORMAT(DValue, 'N0', 'vi-VN'), N'đ cho đơn từ ', FORMAT(MinOrder, 'N0', 'vi-VN'), N'đ') END;

    INSERT INTO dbo.Vouchers (VoucherCode, VoucherName, VoucherType, DiscountType, DiscountValue, MaxDiscountAmount,
                              MinOrderValue, StartAt, EndAt, UsageLimit, UsedCount, IsActive)
    SELECT CONCAT('VNR', RIGHT(CONCAT('000', n), 3)), VName, VType, DType, DValue, DMax, MinOrder, StartAt, EndAt, UsageLimit, UsedCount, IsActive
    FROM @Vc;

    /* =================================================================
       3. ProductCertificates – 100 dòng cho 100 sản phẩm ngẫu nhiên
          Loại chứng nhận suy ra từ loại đá của sản phẩm
       ================================================================= */
    DECLARE @Pc TABLE (n INT IDENTITY(1,1) PRIMARY KEY, ProductID INT, r1 INT, r2 INT, r3 INT, CType VARCHAR(20));
    INSERT INTO @Pc (ProductID, r1, r2, r3)
    SELECT TOP (100) ProductID, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647
    FROM dbo.Products
    WHERE ProductID NOT IN (SELECT ProductID FROM dbo.ProductCertificates)
    ORDER BY NEWID();
    UPDATE pc SET CType = CASE
        WHEN EXISTS (SELECT 1 FROM dbo.ProductStones s WHERE s.ProductID = pc.ProductID AND s.StoneType IN ('NaturalDiamond', 'LabDiamond')) THEN 'Diamond'
        WHEN EXISTS (SELECT 1 FROM dbo.ProductStones s WHERE s.ProductID = pc.ProductID AND s.StoneType = 'Gemstone') THEN 'Gemstone'
        ELSE 'GoldPurity' END
    FROM @Pc pc;

    INSERT INTO dbo.ProductCertificates (ProductID, CertificateType, IssuingOrganization, CertificateNo, IssueDate, DocumentUrl, Note)
    SELECT ProductID, CType,
           CASE CType WHEN 'Diamond' THEN CHOOSE(r1 % 3 + 1, N'GIA', N'IGI', N'HRD')
                      WHEN 'Gemstone' THEN N'Trung tâm Kiểm định Đá quý (giả lập)'
                      ELSE N'Trung tâm Kiểm định Vàng (giả lập)' END,
           CONCAT(CASE CType WHEN 'Diamond' THEN 'DM' WHEN 'Gemstone' THEN 'GS' ELSE 'AU' END, '-F', RIGHT(CONCAT('000', n), 3), '-', RIGHT(CONCAT('000000', r2 % 1000000), 6)),
           DATEADD(DAY, r3 % 600, CAST('2025-01-01' AS DATE)),
           CONCAT('/static/certificates/', CASE CType WHEN 'Diamond' THEN 'DM' WHEN 'Gemstone' THEN 'GS' ELSE 'AU' END, '-F', RIGHT(CONCAT('000', n), 3), '.pdf'),
           N'Dữ liệu giả lập'
    FROM @Pc;

    /* =================================================================
       4. Users, Customers, CustomerAddresses – mỗi bảng 100 dòng
       ================================================================= */
    DECLARE @U TABLE (n INT PRIMARY KEY, r1 INT, r2 INT, r3 INT, r4 INT, r5 INT, r6 INT, r7 INT, r8 INT, r9 INT, r10 INT, r11 INT, r12 INT,
                      FullName NVARCHAR(100), Email VARCHAR(255), Username VARCHAR(50), Phone VARCHAR(15),
                      UserID INT, CustomerID INT, AddrIdx INT);
    INSERT INTO @U (n, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12)
    SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647,
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647,
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647,
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647
    FROM sys.all_objects;

    UPDATE u SET
        FullName = CONCAT(h.v, N' ', d.v, N' ', t.v),
        Email    = CONCAT(t.a, '.', h.a, u.n + 100, '@', dm.v),
        Username = CASE WHEN u.r4 % 2 = 0 THEN CONCAT(t.a, h.a, u.n + 100) END,
        Phone    = CONCAT(pf.v, RIGHT(CONCAT('0000000', u.r5 % 10000000), 7))
    FROM @U u
    JOIN @Ho h      ON h.i  = u.r1 % 16 + 1
    JOIN @Dem d     ON d.i  = u.r2 % 14 + 1
    JOIN @Ten t     ON t.i  = u.r3 % 30 + 1
    JOIN @Domain dm ON dm.i = u.r6 % 5 + 1
    JOIN @Prefix pf ON pf.i = u.r7 % 20 + 1;

    INSERT INTO dbo.Users (Username, FullName, Email, PasswordHash, Role, IsActive, LastLoginAt, CreatedAt)
    SELECT Username, FullName, Email,
           CONCAT('$2b$12$', LEFT(CONVERT(VARCHAR(100), HASHBYTES('SHA2_256', CONCAT('vinora-fake-', n)), 2), 53)),
           'Customer',
           CASE WHEN r8 % 20 = 0 THEN 0 ELSE 1 END,
           DATEADD(MINUTE, -(r9 % 86400), @Now),
           DATEADD(MINUTE, r10 % 400000, CAST('2025-06-01T08:00:00' AS DATETIME2(0)))
    FROM @U;
    UPDATE u SET UserID = us.UserID FROM @U u JOIN dbo.Users us ON us.Email = u.Email;

    INSERT INTO dbo.Customers (UserID, Phone, DateOfBirth, DefaultRingSize, CreatedAt)
    SELECT u.UserID, u.Phone,
           DATEADD(DAY, u.r11 % (365 * 36), CAST('1970-01-01' AS DATE)),
           CASE WHEN u.r12 % 10 < 3 THEN NULL ELSE 6 + u.r12 % 15 END,
           us.CreatedAt
    FROM @U u JOIN dbo.Users us ON us.UserID = u.UserID;
    UPDATE u SET CustomerID = c.CustomerID FROM @U u JOIN dbo.Customers c ON c.UserID = u.UserID;

    INSERT INTO dbo.CustomerAddresses (CustomerID, RecipientName, Phone, AddressLine, Ward, Province, IsDefault, CreatedAt)
    SELECT u.CustomerID, u.FullName, u.Phone,
           CONCAT(u.r1 % 300 + 1, N' ', st.v), lc.ward, lc.province, 1, c.CreatedAt
    FROM @U u
    JOIN dbo.Customers c ON c.CustomerID = u.CustomerID
    JOIN @Street st ON st.i = u.r2 % 15 + 1
    JOIN @Loc lc    ON lc.i = u.r3 % 15 + 1;

    /* ---------- Biến thể đang bán dùng để chọn ngẫu nhiên ---------- */
    DECLARE @V TABLE (rn INT IDENTITY(1,1) PRIMARY KEY, VariantID INT, ProductID INT, RingSize TINYINT);
    INSERT INTO @V (VariantID, ProductID, RingSize)
    SELECT v.VariantID, v.ProductID, v.RingSize
    FROM dbo.ProductVariants v JOIN dbo.Products p ON p.ProductID = v.ProductID
    WHERE v.IsActive = 1 AND p.Status = 'Active' AND dbo.fn_GetCurrentPrice(p.ProductID) IS NOT NULL;
    DECLARE @nV INT = (SELECT COUNT(*) FROM @V);

    /* =================================================================
       5. CartItems – 100 dòng (khách hàng, biến thể không trùng)
       ================================================================= */
    DECLARE @Cart TABLE (CustomerID INT, VariantID INT, r1 INT, r2 INT, r3 INT, r4 INT);
    INSERT INTO @Cart (CustomerID, VariantID, r1, r2, r3, r4)
    SELECT u.CustomerID, v.VariantID, x.r2, x.r3, x.r4, x.r5
    FROM (SELECT TOP (160) CHECKSUM(NEWID()) & 2147483647 AS r0, CHECKSUM(NEWID()) & 2147483647 AS r1,
                 CHECKSUM(NEWID()) & 2147483647 AS r2, CHECKSUM(NEWID()) & 2147483647 AS r3,
                 CHECKSUM(NEWID()) & 2147483647 AS r4, CHECKSUM(NEWID()) & 2147483647 AS r5
          FROM sys.all_objects) x
    JOIN @U u ON u.n = x.r0 % 100 + 1
    JOIN @V v ON v.rn = x.r1 % @nV + 1;

    INSERT INTO dbo.CartItems (CustomerID, VariantID, Quantity, EngravingText, AddedAt)
    SELECT TOP (100) c.CustomerID, c.VariantID,
           CASE WHEN c.r1 % 5 = 0 THEN 2 ELSE 1 END,
           CASE WHEN v.RingSize IS NOT NULL AND c.r2 % 4 = 0 THEN e.v END,
           DATEADD(MINUTE, -(c.r3 % 43200), @Now)
    FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY CustomerID, VariantID ORDER BY r4) AS dup FROM @Cart) c
    JOIN dbo.ProductVariants v ON v.VariantID = c.VariantID
    JOIN @Engrave e ON e.i = c.r4 % 10 + 1
    WHERE c.dup = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.CartItems ci WHERE ci.CustomerID = c.CustomerID AND ci.VariantID = c.VariantID);

    /* =================================================================
       6. RecentlyViewedProducts – 100 dòng
       ================================================================= */
    DECLARE @View TABLE (CustomerID INT, ProductID INT, r1 INT, r2 INT, r3 INT);
    INSERT INTO @View (CustomerID, ProductID, r1, r2, r3)
    SELECT u.CustomerID, p.ProductID, x.r2, x.r3, x.r4
    FROM (SELECT TOP (160) CHECKSUM(NEWID()) & 2147483647 AS r0, CHECKSUM(NEWID()) & 2147483647 AS r1,
                 CHECKSUM(NEWID()) & 2147483647 AS r2, CHECKSUM(NEWID()) & 2147483647 AS r3,
                 CHECKSUM(NEWID()) & 2147483647 AS r4
          FROM sys.all_objects) x
    JOIN @U u ON u.n = x.r0 % 100 + 1
    JOIN (SELECT ProductID, ROW_NUMBER() OVER (ORDER BY ProductID) AS rn FROM dbo.Products) p
      ON p.rn = x.r1 % (SELECT COUNT(*) FROM dbo.Products) + 1;

    INSERT INTO dbo.RecentlyViewedProducts (CustomerID, ProductID, LastViewedAt, ViewCount)
    SELECT TOP (100) CustomerID, ProductID, DATEADD(MINUTE, -(r1 % 86400), @Now), 1 + r2 % 8
    FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY CustomerID, ProductID ORDER BY r3) AS dup FROM @View) v
    WHERE dup = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.RecentlyViewedProducts r WHERE r.CustomerID = v.CustomerID AND r.ProductID = v.ProductID);

    /* =================================================================
       7. Orders (300) + OrderItems
          Phân bố trạng thái: 210 Delivered, 15 Shipping, 15 Confirmed,
          15 Pending, 45 Cancelled
       ================================================================= */
    DECLARE @O TABLE (n INT PRIMARY KEY, CustomerID INT,
                      r1 INT, r2 INT, r3 INT, r4 INT, r5 INT, r6 INT, r7 INT, r8 INT, r9 INT, r10 INT,
                      PlanStatus VARCHAR(15), LineCount INT, PayMethod VARCHAR(20), CancelFromConfirmed BIT,
                      CreatedAt DATETIME2(0), ConfirmedAt DATETIME2(0), ShippedAt DATETIME2(0), DeliveredAt DATETIME2(0), CancelledAt DATETIME2(0),
                      Subtotal DECIMAL(15,0), VoucherID INT, DType VARCHAR(10), DValue DECIMAL(15,0), DMax DECIMAL(15,0),
                      Discount DECIMAL(15,0) DEFAULT 0, IsRetention BIT DEFAULT 0, RetentionAmt DECIMAL(15,0) DEFAULT 0,
                      ShipFee DECIMAL(15,0), OrderID INT, OrderCode VARCHAR(20));
    INSERT INTO @O (n, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10)
    SELECT TOP (300) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647,
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647,
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647,
           CHECKSUM(NEWID()) & 2147483647
    FROM sys.all_objects;

    UPDATE o SET CustomerID = u.CustomerID FROM @O o JOIN @U u ON u.n = o.r1 % 100 + 1;

    ;WITH s AS (SELECT n, ROW_NUMBER() OVER (ORDER BY r2) AS k FROM @O)
    UPDATE o SET PlanStatus = CASE WHEN s.k <= 210 THEN 'Delivered' WHEN s.k <= 225 THEN 'Shipping'
                                   WHEN s.k <= 240 THEN 'Confirmed' WHEN s.k <= 255 THEN 'Pending' ELSE 'Cancelled' END
    FROM @O o JOIN s ON s.n = o.n;

    UPDATE @O SET
        LineCount = CASE WHEN r8 % 100 < 65 THEN 1 WHEN r8 % 100 < 92 THEN 2 ELSE 3 END,
        PayMethod = CASE WHEN r7 % 100 < 40 THEN 'COD' WHEN r7 % 100 < 65 THEN 'VNPay' WHEN r7 % 100 < 85 THEN 'MoMo' ELSE 'BankTransfer' END,
        CancelFromConfirmed = CASE WHEN PlanStatus = 'Cancelled' AND r9 % 2 = 0 THEN 1 ELSE 0 END;

    -- Mốc thời gian theo trạng thái (đơn đã nhận/đã hủy trải đều từ 05/01/2026 đến 15/10/2026)
    UPDATE @O SET CreatedAt = CASE
        WHEN PlanStatus IN ('Delivered', 'Cancelled') THEN DATEADD(MINUTE, 480 + r3 % 407000, CAST('2026-01-05' AS DATETIME2(0)))
        WHEN PlanStatus = 'Shipping'  THEN DATEADD(MINUTE, -(2880 + r3 % 2880), @Now)
        WHEN PlanStatus = 'Confirmed' THEN DATEADD(MINUTE, -(600 + r3 % 1440), @Now)
        ELSE DATEADD(MINUTE, -(10 + r3 % 600), @Now) END;
    UPDATE @O SET ConfirmedAt = CASE
        WHEN PlanStatus IN ('Delivered', 'Shipping', 'Confirmed') OR CancelFromConfirmed = 1 THEN DATEADD(MINUTE, 30 + r4 % 300, CreatedAt) END;
    UPDATE @O SET ShippedAt = CASE WHEN PlanStatus IN ('Delivered', 'Shipping') THEN DATEADD(MINUTE, 600 + r5 % 1200, ConfirmedAt) END;
    UPDATE @O SET DeliveredAt = CASE WHEN PlanStatus = 'Delivered' THEN DATEADD(MINUTE, 1440 + r6 % 4320, ShippedAt) END,
                  CancelledAt = CASE WHEN PlanStatus = 'Cancelled' THEN DATEADD(MINUTE, 400 + r6 % 1500, CreatedAt) END;

    -- Dòng hàng: 1–3 dòng/đơn, biến thể chọn ngẫu nhiên trong biến thể đang bán
    DECLARE @I TABLE (id INT IDENTITY(1,1) PRIMARY KEY, n INT, r1 INT, r2 INT, r3 INT, r4 INT,
                      VariantID INT, ProductID INT, Quantity SMALLINT, UnitPrice DECIMAL(15,0), Engraving NVARCHAR(30));
    INSERT INTO @I (n, r1, r2, r3, r4)
    SELECT o.n, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647
    FROM @O o JOIN (VALUES (1), (2), (3)) k(k) ON k.k <= o.LineCount;

    UPDATE i SET VariantID = v.VariantID, ProductID = v.ProductID,
                 Quantity = CASE WHEN i.r2 % 10 = 0 THEN 2 ELSE 1 END,
                 Engraving = CASE WHEN v.RingSize IS NOT NULL AND i.r3 % 10 < 3 THEN e.v END
    FROM @I i JOIN @V v ON v.rn = i.r1 % @nV + 1
    JOIN @Engrave e ON e.i = i.r4 % 10 + 1;
    UPDATE @I SET UnitPrice = dbo.fn_GetCurrentPrice(ProductID);

    UPDATE o SET Subtotal = s.Sub, ShipFee = CASE WHEN s.Sub >= 2000000 THEN 0 ELSE 30000 END
    FROM @O o JOIN (SELECT n, SUM(Quantity * UnitPrice) AS Sub FROM @I GROUP BY n) s ON s.n = o.n;

    -- 30% đơn dùng mã khuyến mãi còn hiệu lực tại thời điểm đặt và đủ giá trị tối thiểu
    UPDATE o SET VoucherID = vc.VoucherID, DType = vc.DiscountType, DValue = vc.DiscountValue, DMax = vc.MaxDiscountAmount
    FROM @O o
    CROSS APPLY (SELECT TOP (1) v.VoucherID, v.DiscountType, v.DiscountValue, v.MaxDiscountAmount
                 FROM dbo.Vouchers v
                 WHERE v.VoucherType = 'Promotion' AND v.IsActive = 1
                   AND o.CreatedAt BETWEEN v.StartAt AND v.EndAt AND v.MinOrderValue <= o.Subtotal
                 ORDER BY CHECKSUM(v.VoucherID, o.n, o.r10)) vc
    WHERE o.r5 % 100 < 30;
    UPDATE @O SET Discount = CASE WHEN DType = 'Percent' THEN ROUND(Subtotal * DValue / 100, -3) ELSE DValue END WHERE VoucherID IS NOT NULL;
    UPDATE @O SET Discount = DMax WHERE DMax IS NOT NULL AND Discount > DMax;
    UPDATE @O SET Discount = Subtotal WHERE Discount > Subtotal;

    -- 55 đơn (không bị hủy, tiền hàng >= 5 triệu) đã chấp nhận ưu đãi giữ chân GIUDON30
    ;WITH r AS (SELECT TOP (55) n FROM @O
                WHERE PlanStatus <> 'Cancelled' AND Subtotal - Discount >= 5000000 ORDER BY r10)
    UPDATE o SET IsRetention = 1,
                 RetentionAmt = CASE WHEN ROUND((o.Subtotal - o.Discount) * 30 / 100, -3) > 3000000 THEN 3000000
                                     ELSE ROUND((o.Subtotal - o.Discount) * 30 / 100, -3) END
    FROM @O o JOIN r ON r.n = o.n;

    UPDATE @O SET OrderCode = CONCAT('VN', FORMAT(CreatedAt, 'yyMMdd'), 'F', RIGHT(CONCAT('0000', n), 4));

    INSERT INTO dbo.Orders (OrderCode, CustomerID, ShipRecipientName, ShipPhone, ShipAddress, Subtotal, VoucherID, DiscountAmount,
                            IsRetentionApplied, RetentionDiscountAmount, ShippingFee, OrderStatus, CheckoutToken, Note, CreatedAt, UpdatedAt)
    SELECT o.OrderCode, o.CustomerID, a.RecipientName, a.Phone, CONCAT(a.AddressLine, N', ', a.Ward, N', ', a.Province),
           o.Subtotal, o.VoucherID, o.Discount, o.IsRetention, o.RetentionAmt, o.ShipFee, 'Pending', NEWID(),
           CASE WHEN o.r9 % 4 = 0 THEN nt.v END, o.CreatedAt, o.CreatedAt
    FROM @O o
    JOIN dbo.CustomerAddresses a ON a.CustomerID = o.CustomerID AND a.IsDefault = 1
    JOIN @Note nt ON nt.i = o.r8 % 5 + 1;
    UPDATE o SET OrderID = d.OrderID FROM @O o JOIN dbo.Orders d ON d.OrderCode = o.OrderCode;

    INSERT INTO dbo.OrderItems (OrderID, ProductID, VariantID, ProductNameSnap, SKUSnap, MaterialSnap, GoldColor, RingSize,
                                EngravingText, Quantity, UnitPrice)
    SELECT o.OrderID, i.ProductID, i.VariantID, p.ProductName, v.VariantSKU, p.Material, v.GoldColor, v.RingSize,
           i.Engraving, i.Quantity, i.UnitPrice
    FROM @I i
    JOIN @O o ON o.n = i.n
    JOIN dbo.ProductVariants v ON v.VariantID = i.VariantID
    JOIN dbo.Products p ON p.ProductID = i.ProductID;

    -- Chuyển trạng thái đúng quy trình (trigger kiểm tra, ghi nhật ký, tự tạo thẻ bảo hành)
    UPDATE d SET OrderStatus = 'Confirmed', ConfirmedAt = o.ConfirmedAt, UpdatedAt = o.ConfirmedAt
    FROM dbo.Orders d JOIN @O o ON o.OrderID = d.OrderID
    WHERE o.ConfirmedAt IS NOT NULL;
    UPDATE d SET OrderStatus = 'Shipping', ShippedAt = o.ShippedAt, UpdatedAt = o.ShippedAt
    FROM dbo.Orders d JOIN @O o ON o.OrderID = d.OrderID
    WHERE o.PlanStatus IN ('Delivered', 'Shipping');
    UPDATE d SET OrderStatus = 'Delivered', DeliveredAt = o.DeliveredAt, UpdatedAt = o.DeliveredAt
    FROM dbo.Orders d JOIN @O o ON o.OrderID = d.OrderID
    WHERE o.PlanStatus = 'Delivered';
    UPDATE d SET OrderStatus = 'Cancelled', CancelledAt = o.CancelledAt, CancelReason = rs.v, UpdatedAt = o.CancelledAt
    FROM dbo.Orders d JOIN @O o ON o.OrderID = d.OrderID
    JOIN @Reason rs ON rs.i = o.r4 % 7 + 1
    WHERE o.PlanStatus = 'Cancelled';

    -- Thẻ bảo hành được kích hoạt tại thời điểm nhận hàng
    UPDATE w SET IssueDate = o.DeliveredAt
    FROM dbo.WarrantyRecords w JOIN @O o ON o.OrderID = w.OrderID;

    -- Trừ tồn kho cho đơn không bị hủy (không để âm)
    UPDATE v SET StockQuantity = CASE WHEN v.StockQuantity >= x.Qty THEN v.StockQuantity - x.Qty ELSE 0 END, UpdatedAt = @Now
    FROM dbo.ProductVariants v
    JOIN (SELECT i.VariantID, SUM(i.Quantity) AS Qty FROM @I i JOIN @O o ON o.n = i.n
          WHERE o.PlanStatus <> 'Cancelled' GROUP BY i.VariantID) x ON x.VariantID = v.VariantID;

    /* =================================================================
       8. Payments – 1 giao dịch/đơn + một số lần thanh toán thất bại trước đó
       ================================================================= */
    INSERT INTO dbo.Payments (OrderID, PaymentMethod, Amount, Status, TransactionID, ResponseCode, IsSandbox, CreatedAt, PaidAt)
    SELECT o.OrderID, o.PayMethod, d.TotalAmount, 'Failed',
           CONCAT(CASE o.PayMethod WHEN 'VNPay' THEN 'VNP' WHEN 'MoMo' THEN 'MOMO' ELSE 'BANK' END, '-SBX-F', o.n, '-0'),
           '24', 1, DATEADD(MINUTE, 1, o.CreatedAt), NULL
    FROM @O o JOIN dbo.Orders d ON d.OrderID = o.OrderID
    WHERE o.PayMethod <> 'COD' AND o.PlanStatus = 'Delivered' AND o.r10 % 10 = 0;

    INSERT INTO dbo.Payments (OrderID, PaymentMethod, Amount, Status, TransactionID, ResponseCode, IsSandbox, CreatedAt, PaidAt)
    SELECT o.OrderID, o.PayMethod, d.TotalAmount, x.Status,
           CASE WHEN o.PayMethod <> 'COD' AND x.Status <> 'Pending'
                THEN CONCAT(CASE o.PayMethod WHEN 'VNPay' THEN 'VNP' WHEN 'MoMo' THEN 'MOMO' ELSE 'BANK' END, '-SBX-F', o.n, '-1') END,
           CASE WHEN o.PayMethod <> 'COD' AND x.Status IN ('Success', 'Refunded') THEN '00'
                WHEN o.PayMethod <> 'COD' AND x.Status = 'Failed' THEN '24' END,
           CASE WHEN o.PayMethod = 'COD' THEN 0 ELSE 1 END,
           DATEADD(MINUTE, 3, o.CreatedAt),
           CASE WHEN x.Status IN ('Success', 'Refunded')
                THEN CASE WHEN o.PayMethod = 'COD' THEN o.DeliveredAt ELSE DATEADD(MINUTE, 5, o.CreatedAt) END END
    FROM @O o
    JOIN dbo.Orders d ON d.OrderID = o.OrderID
    CROSS APPLY (SELECT CASE
        WHEN o.PayMethod = 'COD' AND o.PlanStatus = 'Delivered' THEN 'Success'
        WHEN o.PayMethod = 'COD' AND o.PlanStatus = 'Cancelled' THEN 'Failed'
        WHEN o.PayMethod = 'COD' THEN 'Pending'
        WHEN o.PlanStatus IN ('Delivered', 'Shipping', 'Confirmed') THEN 'Success'
        WHEN o.PlanStatus = 'Cancelled' AND o.r9 % 3 = 0 THEN 'Refunded'
        WHEN o.PlanStatus = 'Cancelled' THEN 'Failed'
        ELSE 'Pending' END AS Status) x;

    /* =================================================================
       9. OrderCancellationRequests – 100 dòng
          45 đơn bị hủy (ConfirmedCancel) + 55 đơn được giữ lại (AcceptedOffer)
       ================================================================= */
    INSERT INTO dbo.OrderCancellationRequests (OrderID, Reason, RequestedAt, OfferShown, OfferVoucherID, OfferDiscountAmount, Decision, DecidedAt)
    SELECT o.OrderID, rs.v, DATEADD(MINUTE, -8, o.CancelledAt),
           CASE WHEN o.Subtotal - o.Discount >= 5000000 THEN 1 ELSE 0 END,
           CASE WHEN o.Subtotal - o.Discount >= 5000000 THEN @RetentionVoucherID END,
           CASE WHEN o.Subtotal - o.Discount >= 5000000 THEN
                CASE WHEN ROUND((o.Subtotal - o.Discount) * 30 / 100, -3) > 3000000 THEN 3000000
                     ELSE ROUND((o.Subtotal - o.Discount) * 30 / 100, -3) END END,
           'ConfirmedCancel', o.CancelledAt
    FROM @O o JOIN @Reason rs ON rs.i = o.r4 % 7 + 1
    WHERE o.PlanStatus = 'Cancelled';

    INSERT INTO dbo.OrderCancellationRequests (OrderID, Reason, RequestedAt, OfferShown, OfferVoucherID, OfferDiscountAmount, Decision, DecidedAt)
    SELECT o.OrderID, rs.v, DATEADD(MINUTE, 5 + o.r5 % 20, o.CreatedAt), 1, @RetentionVoucherID, o.RetentionAmt,
           'AcceptedOffer', DATEADD(MINUTE, 7 + o.r5 % 20, o.CreatedAt)
    FROM @O o JOIN @Reason rs ON rs.i = o.r4 % 7 + 1
    WHERE o.IsRetention = 1;

    UPDATE dbo.Vouchers SET UsedCount = UsedCount + (SELECT COUNT(*) FROM @O WHERE IsRetention = 1)
    WHERE VoucherID = @RetentionVoucherID;

    UPDATE v SET UsedCount = CASE WHEN v.UsageLimit IS NULL OR v.UsedCount + c.Cnt <= v.UsageLimit THEN v.UsedCount + c.Cnt ELSE v.UsageLimit END
    FROM dbo.Vouchers v JOIN (SELECT VoucherID, COUNT(*) AS Cnt FROM @O WHERE VoucherID IS NOT NULL GROUP BY VoucherID) c ON c.VoucherID = v.VoucherID;

    /* =================================================================
       10. CustomerFeedbacks + FeedbackAspects – mỗi bảng 100 dòng
           Số sao: 5★ 45%, 4★ 25%, 3★ 12%, 2★ 10%, 1★ 8%
       ================================================================= */
    DECLARE @F TABLE (n INT PRIMARY KEY, OrderID INT, CustomerID INT, DeliveredAt DATETIME2(0),
                      r1 INT, r2 INT, r3 INT, r4 INT, Rating TINYINT, TplID INT, CreatedAt DATETIME2(0));
    INSERT INTO @F (n, OrderID, CustomerID, DeliveredAt, r1, r2, r3, r4)
    SELECT TOP (100) o.n, o.OrderID, o.CustomerID, o.DeliveredAt,
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647
    FROM @O o WHERE o.PlanStatus = 'Delivered' ORDER BY o.r7;
    UPDATE @F SET Rating = CASE WHEN r1 % 100 < 45 THEN 5 WHEN r1 % 100 < 70 THEN 4 WHEN r1 % 100 < 82 THEN 3
                                WHEN r1 % 100 < 92 THEN 2 ELSE 1 END;
    UPDATE @F SET TplID = CASE WHEN Rating >= 4 THEN 1 + r2 % 7 WHEN Rating <= 2 THEN 8 + r2 % 5 ELSE 13 + r2 % 3 END,
                  CreatedAt = DATEADD(MINUTE, 60 + r4 % 10080, DeliveredAt);
    UPDATE @F SET CreatedAt = @Now WHERE CreatedAt > @Now;

    INSERT INTO dbo.CustomerFeedbacks (OrderID, CustomerID, RatingStar, ReviewText, SentimentLabel, SentimentScore,
                                       IsSentimentSimulated, CreatedAt, AnalyzedAt)
    SELECT f.OrderID, f.CustomerID, f.Rating, t.txt, t.label, CAST(0.600 + (f.r3 % 400) / 1000.0 AS DECIMAL(4,3)),
           1, f.CreatedAt, f.CreatedAt
    FROM @F f JOIN @Tpl t ON t.i = f.TplID;

    INSERT INTO dbo.FeedbackAspects (FeedbackID, AspectName, Polarity)
    SELECT cf.FeedbackID, t.aspect, t.polarity
    FROM @F f
    JOIN dbo.CustomerFeedbacks cf ON cf.OrderID = f.OrderID
    JOIN @Tpl t ON t.i = f.TplID;

    /* =================================================================
       11. AfterSalesServices – 100 lịch hẹn trên 100 thẻ bảo hành khác nhau
           Loại: Cleaning 35%, Polishing 30%, Replating 15%, Resizing 20% (chỉ nhẫn)
           Trạng thái: Completed 55%, Confirmed 12%, Rescheduled 8%, Pending 15%, Cancelled 10%
       ================================================================= */
    DECLARE @S TABLE (n INT IDENTITY(1,1) PRIMARY KEY, WarrantyID INT, IssueDate DATETIME2(0), ItemRingSize TINYINT,
                      r1 INT, r2 INT, r3 INT, r4 INT, r5 INT, r6 INT,
                      SType VARCHAR(15), SStatus VARCHAR(15), PreferredDate DATETIME2(0), AppointmentDate DATETIME2(0),
                      NewRingSize TINYINT, MaxDays INT);
    INSERT INTO @S (WarrantyID, IssueDate, ItemRingSize, r1, r2, r3, r4, r5, r6)
    SELECT TOP (100) w.WarrantyID, w.IssueDate, oi.RingSize,
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647,
           CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647, CHECKSUM(NEWID()) & 2147483647
    FROM dbo.WarrantyRecords w
    JOIN @O o ON o.OrderID = w.OrderID
    JOIN dbo.OrderItems oi ON oi.OrderItemID = w.OrderItemID
    ORDER BY NEWID();

    UPDATE @S SET SType = CASE WHEN r1 % 100 < 35 THEN 'Cleaning' WHEN r1 % 100 < 65 THEN 'Polishing'
                               WHEN r1 % 100 < 80 THEN 'Replating' ELSE 'Resizing' END,
                  SStatus = CASE WHEN r2 % 100 < 55 THEN 'Completed' WHEN r2 % 100 < 67 THEN 'Confirmed'
                                 WHEN r2 % 100 < 75 THEN 'Rescheduled' WHEN r2 % 100 < 90 THEN 'Pending' ELSE 'Cancelled' END,
                  MaxDays = DATEDIFF(DAY, IssueDate, @Now) - 2;
    UPDATE @S SET SType = 'Cleaning' WHERE SType = 'Resizing' AND ItemRingSize IS NULL;          -- chỉ nhẫn mới chỉnh size
    UPDATE @S SET SStatus = 'Pending' WHERE SStatus IN ('Completed', 'Cancelled') AND MaxDays < 2; -- thẻ quá mới thì lịch ở tương lai
    UPDATE @S SET NewRingSize = CASE WHEN SType <> 'Resizing' THEN NULL
                                     WHEN r5 % 2 = 0 AND ItemRingSize < 25 THEN ItemRingSize + 1
                                     WHEN ItemRingSize > 5 THEN ItemRingSize - 1 ELSE ItemRingSize + 1 END;
    -- Lịch đã xử lý xong nằm trong quá khứ (sau ngày kích hoạt thẻ); lịch đang chờ nằm trong 1–20 ngày tới
    UPDATE @S SET PreferredDate = CASE
        WHEN SStatus IN ('Completed', 'Cancelled')
            THEN DATEADD(HOUR, 9 + r4 % 8, CAST(CAST(DATEADD(DAY, 2 + r3 % MaxDays, IssueDate) AS DATE) AS DATETIME2(0)))
        ELSE DATEADD(HOUR, 9 + r4 % 8, DATEADD(DAY, 1 + r3 % 20, @Today)) END;
    UPDATE @S SET AppointmentDate = CASE WHEN SStatus IN ('Completed', 'Confirmed') THEN PreferredDate
                                         WHEN SStatus = 'Rescheduled' THEN DATEADD(DAY, 1, PreferredDate) END;

    INSERT INTO dbo.AfterSalesServices (WarrantyID, ServiceType, PreferredDate, AppointmentDate, NewRingSize, Status,
                                        CustomerNote, ResultNote, HandledByUserID, IsFreeOfCharge, ServiceFee, IsQuotaDeducted,
                                        CreatedAt, CompletedAt)
    SELECT s.WarrantyID, s.SType, s.PreferredDate, s.AppointmentDate, s.NewRingSize, s.SStatus,
           CASE WHEN s.r6 % 3 = 0 THEN CHOOSE(s.r6 % 4 + 1, N'Làm trước dịp kỷ niệm', N'Ghé cửa hàng buổi chiều', N'Nhẫn hơi xỉn màu', N'Nhờ kiểm tra lại chấu giữ đá') END,
           CASE WHEN s.SStatus = 'Completed' THEN
                CASE s.SType WHEN 'Cleaning' THEN N'Đã làm sạch, kiểm tra chấu đá'
                             WHEN 'Polishing' THEN N'Đã đánh bóng'
                             WHEN 'Replating' THEN N'Đã xi mới'
                             ELSE CONCAT(N'Đã chỉnh size từ ', s.ItemRingSize, N' sang ', s.NewRingSize) END END,
           CASE WHEN s.SStatus IN ('Confirmed', 'Rescheduled', 'Completed') THEN @AdminID END,
           CASE WHEN s.SStatus = 'Completed' THEN 1 END,
           0,
           CASE WHEN s.SStatus = 'Completed' THEN 1 ELSE 0 END,
           CASE WHEN s.SStatus IN ('Completed', 'Cancelled') THEN DATEADD(DAY, -1, s.PreferredDate)
                ELSE DATEADD(MINUTE, -(s.r5 % 2880), @Now) END,
           CASE WHEN s.SStatus = 'Completed' THEN DATEADD(HOUR, 2, s.AppointmentDate) END
    FROM @S s;

    -- Cập nhật quyền lợi trên thẻ theo dịch vụ đã hoàn tất
    UPDATE w SET
        PolishingCountLeft = w.PolishingCountLeft - x.Polish,
        CleaningCount = w.CleaningCount + x.Clean,
        ResizingCount = w.ResizingCount + x.Resize
    FROM dbo.WarrantyRecords w
    JOIN (SELECT WarrantyID,
                 SUM(CASE WHEN SType IN ('Polishing', 'Replating') THEN 1 ELSE 0 END) AS Polish,
                 SUM(CASE WHEN SType = 'Cleaning' THEN 1 ELSE 0 END) AS Clean,
                 SUM(CASE WHEN SType = 'Resizing' THEN 1 ELSE 0 END) AS Resize
          FROM @S WHERE SStatus = 'Completed' GROUP BY WarrantyID) x ON x.WarrantyID = w.WarrantyID;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    EXEC sp_set_session_context @key = N'Actor', @value = NULL;
    THROW;
END CATCH

EXEC sp_set_session_context @key = N'Actor', @value = NULL;

/* ---------- Kiểm tra số dòng sau khi sinh ---------- */
SELECT 'Users' AS TableName, COUNT(*) AS RowCnt FROM dbo.Users UNION ALL
SELECT 'Customers', COUNT(*) FROM dbo.Customers UNION ALL
SELECT 'CustomerAddresses', COUNT(*) FROM dbo.CustomerAddresses UNION ALL
SELECT 'ProductCertificates', COUNT(*) FROM dbo.ProductCertificates UNION ALL
SELECT 'GoldPrices', COUNT(*) FROM dbo.GoldPrices UNION ALL
SELECT 'Vouchers', COUNT(*) FROM dbo.Vouchers UNION ALL
SELECT 'CartItems', COUNT(*) FROM dbo.CartItems UNION ALL
SELECT 'RecentlyViewedProducts', COUNT(*) FROM dbo.RecentlyViewedProducts UNION ALL
SELECT 'Orders', COUNT(*) FROM dbo.Orders UNION ALL
SELECT 'OrderItems', COUNT(*) FROM dbo.OrderItems UNION ALL
SELECT 'Payments', COUNT(*) FROM dbo.Payments UNION ALL
SELECT 'OrderCancellationRequests', COUNT(*) FROM dbo.OrderCancellationRequests UNION ALL
SELECT 'WarrantyRecords', COUNT(*) FROM dbo.WarrantyRecords UNION ALL
SELECT 'AfterSalesServices', COUNT(*) FROM dbo.AfterSalesServices UNION ALL
SELECT 'CustomerFeedbacks', COUNT(*) FROM dbo.CustomerFeedbacks UNION ALL
SELECT 'FeedbackAspects', COUNT(*) FROM dbo.FeedbackAspects UNION ALL
SELECT 'AuditLogs', COUNT(*) FROM dbo.AuditLogs;

SELECT * FROM dbo.vw_RevenueByMonth ORDER BY [Year], [Month];
SELECT * FROM dbo.vw_RevenueByMaterial ORDER BY NetRevenue DESC;
SELECT * FROM dbo.vw_RetentionStats;
SELECT * FROM dbo.vw_SentimentSummary;
SELECT * FROM dbo.vw_FeedbackAspectSummary ORDER BY MentionCount DESC;
GO
