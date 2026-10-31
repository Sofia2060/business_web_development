/* =====================================================================
   ĐỒ ÁN: XÂY DỰNG WEBSITE THƯƠNG MẠI ĐIỆN TỬ KINH DOANH TRANG SỨC CAO CẤP
          VINORA JEWELRY
   CHƯƠNG 4 – THIẾT KẾ VÀ CÀI ĐẶT CƠ SỞ DỮ LIỆU VẬT LÝ (MS SQL SERVER)
   ---------------------------------------------------------------------
   Hệ quản trị : Microsoft SQL Server 2019 trở lên (khuyến nghị 2022)
   Công cụ chạy: SQL Server Management Studio (SSMS) – mở file, nhấn F5
   Cấu trúc file:
     PHẦN 0. Khởi tạo cơ sở dữ liệu
     PHẦN 1. Tạo bảng (26 bảng) + ràng buộc PK, FK, UNIQUE, CHECK, DEFAULT
     PHẦN 2. Chỉ mục (index) phục vụ tìm kiếm, lọc và thống kê
     PHẦN 3. Hàm, trigger, thủ tục nghiệp vụ (stored procedure)
     PHẦN 4. View phục vụ trang khách hàng và dashboard quản trị
     PHẦN 5. Dữ liệu danh mục, bộ sưu tập, sản phẩm (từ dữ liệu crawl)
     PHẦN 6. Dữ liệu mẫu minh họa luồng nghiệp vụ
     PHẦN 7. Truy vấn kiểm tra nhanh
   Quy ước đặt tên: bảng dạng số nhiều PascalCase (Users, Orders...) để tránh
   trùng từ khóa dành riêng USER/ORDER của SQL Server; khóa chính <Tên>ID.
   ===================================================================== */

/* =====================================================================
   PHẦN 0. KHỞI TẠO CƠ SỞ DỮ LIỆU
   Collation Vietnamese_100_CI_AI: không phân biệt hoa/thường và dấu, giúp
   tìm kiếm "nhan cau hon" vẫn khớp "Nhẫn cầu hôn" (FR5).
   ===================================================================== */
USE master;
GO
IF DB_ID(N'VinoraJewelry') IS NOT NULL
BEGIN
    ALTER DATABASE VinoraJewelry SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE VinoraJewelry;
END
GO
CREATE DATABASE VinoraJewelry COLLATE Vietnamese_100_CI_AI;
GO
USE VinoraJewelry;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* =====================================================================
   PHẦN 1. TẠO BẢNG
   ===================================================================== */

/* ---------- 1.1. PHÂN HỆ TÀI KHOẢN ---------- */

-- (1) Users: tài khoản đăng nhập của khách hàng và quản trị viên (FR1, FR2, NFR1)
CREATE TABLE dbo.Users (
    UserID        INT IDENTITY(1,1)  NOT NULL,
    Username      VARCHAR(50)        NULL,                 -- tên hiển thị/đăng nhập phụ, không bắt buộc
    FullName      NVARCHAR(100)      NOT NULL,
    Email         VARCHAR(255)       NOT NULL,
    PasswordHash  VARCHAR(255)       NOT NULL,             -- chuỗi băm bcrypt/argon2 (đã gồm salt), không lưu mật khẩu rõ
    Role          VARCHAR(10)        NOT NULL CONSTRAINT DF_Users_Role DEFAULT ('Customer'),
    IsActive      BIT                NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT (1),
    LastLoginAt   DATETIME2(0)       NULL,
    CreatedAt     DATETIME2(0)       NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSDATETIME()),
    UpdatedAt     DATETIME2(0)       NULL,
    CONSTRAINT PK_Users PRIMARY KEY (UserID),
    CONSTRAINT UQ_Users_Email UNIQUE (Email),
    CONSTRAINT CK_Users_Role CHECK (Role IN ('Customer', 'Admin')),
    CONSTRAINT CK_Users_Email CHECK (Email LIKE '%_@_%._%')
);
GO
-- Username duy nhất nhưng cho phép NULL nhiều dòng -> filtered unique index
CREATE UNIQUE INDEX UX_Users_Username ON dbo.Users(Username) WHERE Username IS NOT NULL;
GO

-- (2) RingSizeChart: bảng quy đổi size nhẫn dùng cho hướng dẫn đo size (BRD2, FR7)
CREATE TABLE dbo.RingSizeChart (
    SizeVN           TINYINT       NOT NULL,
    CircumferenceMm  DECIMAL(4,1)  NOT NULL,              -- chu vi trong của nhẫn (mm)
    InnerDiameterMm  DECIMAL(4,1)  NOT NULL,              -- đường kính trong (mm)
    SizeUS           DECIMAL(3,1)  NULL,                  -- size Mỹ tương đương (tham khảo)
    CONSTRAINT PK_RingSizeChart PRIMARY KEY (SizeVN),
    CONSTRAINT CK_RingSizeChart_Size CHECK (SizeVN BETWEEN 1 AND 40),
    CONSTRAINT CK_RingSizeChart_Value CHECK (CircumferenceMm > 0 AND InnerDiameterMm > 0)
);
GO

-- (3) Customers: hồ sơ khách hàng, quan hệ 1-1 với Users (FR3)
CREATE TABLE dbo.Customers (
    CustomerID       INT IDENTITY(1,1) NOT NULL,
    UserID           INT               NOT NULL,
    Phone            VARCHAR(15)       NULL,
    DateOfBirth      DATE              NULL,
    DefaultRingSize  TINYINT           NULL,               -- size nhẫn mặc định của khách
    CreatedAt        DATETIME2(0)      NOT NULL CONSTRAINT DF_Customers_CreatedAt DEFAULT (SYSDATETIME()),
    UpdatedAt        DATETIME2(0)      NULL,
    CONSTRAINT PK_Customers PRIMARY KEY (CustomerID),
    CONSTRAINT UQ_Customers_User UNIQUE (UserID),          -- đảm bảo quan hệ 1-1
    CONSTRAINT FK_Customers_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID),
    CONSTRAINT FK_Customers_RingSize FOREIGN KEY (DefaultRingSize) REFERENCES dbo.RingSizeChart(SizeVN),
    CONSTRAINT CK_Customers_Phone CHECK (Phone IS NULL OR (LEN(Phone) BETWEEN 9 AND 15 AND Phone NOT LIKE '%[^0-9+]%')),
    CONSTRAINT CK_Customers_DOB CHECK (DateOfBirth IS NULL OR DateOfBirth < CAST(GETDATE() AS DATE))
);
GO

-- (4) CustomerAddresses: sổ địa chỉ nhận hàng, một khách có nhiều địa chỉ (FR3, FR10)
--     Địa chỉ theo mô hình hành chính 2 cấp (phường/xã – tỉnh/thành phố).
CREATE TABLE dbo.CustomerAddresses (
    AddressID      INT IDENTITY(1,1) NOT NULL,
    CustomerID     INT               NOT NULL,
    RecipientName  NVARCHAR(100)     NOT NULL,
    Phone          VARCHAR(15)       NOT NULL,
    AddressLine    NVARCHAR(255)     NOT NULL,             -- số nhà, tên đường
    Ward           NVARCHAR(100)     NOT NULL,             -- phường/xã
    Province       NVARCHAR(100)     NOT NULL,             -- tỉnh/thành phố
    IsDefault      BIT               NOT NULL CONSTRAINT DF_CustomerAddresses_IsDefault DEFAULT (0),
    CreatedAt      DATETIME2(0)      NOT NULL CONSTRAINT DF_CustomerAddresses_CreatedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_CustomerAddresses PRIMARY KEY (AddressID),
    CONSTRAINT FK_CustomerAddresses_Customers FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID) ON DELETE CASCADE,
    CONSTRAINT CK_CustomerAddresses_Phone CHECK (LEN(Phone) BETWEEN 9 AND 15 AND Phone NOT LIKE '%[^0-9+]%')
);
GO
-- Mỗi khách hàng chỉ có tối đa một địa chỉ mặc định
CREATE UNIQUE INDEX UX_CustomerAddresses_Default ON dbo.CustomerAddresses(CustomerID) WHERE IsDefault = 1;
GO

/* ---------- 1.2. PHÂN HỆ SẢN PHẨM ---------- */

-- (5) Categories: danh mục sản phẩm (FR4, FR20)
CREATE TABLE dbo.Categories (
    CategoryID        INT IDENTITY(1,1) NOT NULL,
    CategoryName      NVARCHAR(100)     NOT NULL,
    CategoryGroup     NVARCHAR(50)      NOT NULL,          -- nhóm lớn: Nhẫn, Bông tai, Dây chuyền...
    Slug              VARCHAR(100)      NOT NULL,
    Description       NVARCHAR(500)     NULL,
    RequiresRingSize  BIT               NOT NULL CONSTRAINT DF_Categories_RequiresRingSize DEFAULT (0), -- 1 = bắt buộc chọn size (nhẫn)
    DisplayOrder      SMALLINT          NOT NULL CONSTRAINT DF_Categories_DisplayOrder DEFAULT (0),
    IsActive          BIT               NOT NULL CONSTRAINT DF_Categories_IsActive DEFAULT (1),
    CreatedAt         DATETIME2(0)      NOT NULL CONSTRAINT DF_Categories_CreatedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Categories PRIMARY KEY (CategoryID),
    CONSTRAINT UQ_Categories_Name UNIQUE (CategoryName),
    CONSTRAINT UQ_Categories_Slug UNIQUE (Slug)
);
GO

-- (6) Collections: bộ sưu tập (FR4, FR20)
CREATE TABLE dbo.Collections (
    CollectionID    INT IDENTITY(1,1) NOT NULL,
    CollectionName  NVARCHAR(100)     NOT NULL,
    Slug            VARCHAR(100)      NOT NULL,
    Description     NVARCHAR(500)     NULL,
    BannerImage     VARCHAR(500)      NULL,
    DisplayOrder    SMALLINT          NOT NULL CONSTRAINT DF_Collections_DisplayOrder DEFAULT (0),
    IsActive        BIT               NOT NULL CONSTRAINT DF_Collections_IsActive DEFAULT (1),
    CreatedAt       DATETIME2(0)      NOT NULL CONSTRAINT DF_Collections_CreatedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Collections PRIMARY KEY (CollectionID),
    CONSTRAINT UQ_Collections_Name UNIQUE (CollectionName),
    CONSTRAINT UQ_Collections_Slug UNIQUE (Slug)
);
GO

-- (7) WarrantyPolicies: chính sách bảo hành/hậu mãi được cấu hình tập trung (BRD6, BRD7, NFR7)
CREATE TABLE dbo.WarrantyPolicies (
    WarrantyPolicyID  INT IDENTITY(1,1) NOT NULL,
    PolicyName        NVARCHAR(150)     NOT NULL,
    PolicyContent     NVARCHAR(MAX)     NOT NULL,          -- nội dung công bố trên trang sản phẩm
    CleaningQuota     TINYINT           NULL,              -- NULL = không giới hạn (làm sạch trọn đời)
    PolishingQuota    TINYINT           NOT NULL CONSTRAINT DF_WarrantyPolicies_Polishing DEFAULT (5), -- số lượt đánh bóng/xi mới miễn phí
    ResizingQuota     TINYINT           NULL,              -- NULL = không giới hạn (chỉnh size trọn đời)
    IsLifetime        BIT               NOT NULL CONSTRAINT DF_WarrantyPolicies_IsLifetime DEFAULT (1),
    IsActive          BIT               NOT NULL CONSTRAINT DF_WarrantyPolicies_IsActive DEFAULT (1),
    CreatedAt         DATETIME2(0)      NOT NULL CONSTRAINT DF_WarrantyPolicies_CreatedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_WarrantyPolicies PRIMARY KEY (WarrantyPolicyID),
    CONSTRAINT UQ_WarrantyPolicies_Name UNIQUE (PolicyName)
);
GO

-- (8) Products: thông tin sản phẩm minh bạch (BRD1, FR6, FR19)
--     Tồn kho được quản lý ở cấp biến thể (ProductVariants) để theo dõi theo size (FR21).
CREATE TABLE dbo.Products (
    ProductID         INT IDENTITY(1,1) NOT NULL,
    SKU               VARCHAR(30)       NOT NULL,
    ProductName       NVARCHAR(200)     NOT NULL,
    ShortName         NVARCHAR(200)     NULL,
    Slug              VARCHAR(150)      NOT NULL,
    CategoryID        INT               NOT NULL,
    WarrantyPolicyID  INT               NOT NULL,
    Material          VARCHAR(10)       NOT NULL,          -- tuổi vàng / chất liệu
    WeightGram        DECIMAL(8,3)      NULL,              -- trọng lượng tham khảo (gram)
    PricingMethod     VARCHAR(10)       NOT NULL CONSTRAINT DF_Products_PricingMethod DEFAULT ('Fixed'),
    LaborPrice        DECIMAL(15,0)     NULL,              -- tiền công chế tác (VNĐ)
    Price             DECIMAL(15,0)     NULL,              -- giá bán niêm yết (VNĐ) với sản phẩm giá cố định
    OriginalPrice     DECIMAL(15,0)     NULL,              -- giá gốc trước khuyến mãi
    Description       NVARCHAR(MAX)     NULL,
    IsEngravable      BIT               NOT NULL CONSTRAINT DF_Products_IsEngravable DEFAULT (0), -- hỗ trợ khắc tên laser
    Status            VARCHAR(15)       NOT NULL CONSTRAINT DF_Products_Status DEFAULT ('Active'),
    CreatedAt         DATETIME2(0)      NOT NULL CONSTRAINT DF_Products_CreatedAt DEFAULT (SYSDATETIME()),
    UpdatedAt         DATETIME2(0)      NULL,
    CONSTRAINT PK_Products PRIMARY KEY (ProductID),
    CONSTRAINT UQ_Products_SKU UNIQUE (SKU),
    CONSTRAINT UQ_Products_Slug UNIQUE (Slug),
    CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryID) REFERENCES dbo.Categories(CategoryID),
    CONSTRAINT FK_Products_WarrantyPolicies FOREIGN KEY (WarrantyPolicyID) REFERENCES dbo.WarrantyPolicies(WarrantyPolicyID),
    CONSTRAINT CK_Products_Material CHECK (Material IN ('10K', '14K', '18K', '22K', '24K', 'BAC925')),
    CONSTRAINT CK_Products_PricingMethod CHECK (PricingMethod IN ('Fixed', 'GoldRate')),
    CONSTRAINT CK_Products_Weight CHECK (WeightGram IS NULL OR WeightGram > 0),
    CONSTRAINT CK_Products_PriceNonNegative CHECK ((Price IS NULL OR Price >= 0) AND (LaborPrice IS NULL OR LaborPrice >= 0)),
    -- Giá cố định phải có Price; giá theo vàng phải có trọng lượng để tính
    CONSTRAINT CK_Products_PriceByMethod CHECK ((PricingMethod = 'Fixed' AND Price IS NOT NULL)
                                             OR (PricingMethod = 'GoldRate' AND WeightGram IS NOT NULL)),
    CONSTRAINT CK_Products_OriginalPrice CHECK (OriginalPrice IS NULL OR Price IS NULL OR OriginalPrice >= Price),
    CONSTRAINT CK_Products_Status CHECK (Status IN ('Active', 'Hidden', 'Discontinued'))
);
GO

-- (9) ProductCollections: bảng trung gian quan hệ N-M giữa sản phẩm và bộ sưu tập (FR20)
CREATE TABLE dbo.ProductCollections (
    ProductID     INT  NOT NULL,
    CollectionID  INT  NOT NULL,
    IsPrimary     BIT  NOT NULL CONSTRAINT DF_ProductCollections_IsPrimary DEFAULT (0),
    CONSTRAINT PK_ProductCollections PRIMARY KEY (ProductID, CollectionID),
    CONSTRAINT FK_ProductCollections_Products FOREIGN KEY (ProductID) REFERENCES dbo.Products(ProductID) ON DELETE CASCADE,
    CONSTRAINT FK_ProductCollections_Collections FOREIGN KEY (CollectionID) REFERENCES dbo.Collections(CollectionID) ON DELETE CASCADE
);
GO
CREATE UNIQUE INDEX UX_ProductCollections_Primary ON dbo.ProductCollections(ProductID) WHERE IsPrimary = 1;
GO

-- (10) ProductVariants: biến thể bán được theo màu vàng và size nhẫn, mang số lượng tồn (FR7, FR9, FR21)
CREATE TABLE dbo.ProductVariants (
    VariantID      INT IDENTITY(1,1) NOT NULL,
    ProductID      INT               NOT NULL,
    VariantSKU     VARCHAR(60)       NOT NULL,
    GoldColor      NVARCHAR(20)      NULL,                 -- Vàng Vàng / Vàng Trắng / Vàng Hồng / Bạc Trắng / Bạc Vàng
    RingSize       TINYINT           NULL,                 -- bắt buộc với nhẫn, NULL với sản phẩm khác
    StockQuantity  INT               NOT NULL CONSTRAINT DF_ProductVariants_Stock DEFAULT (0),
    IsActive       BIT               NOT NULL CONSTRAINT DF_ProductVariants_IsActive DEFAULT (1),
    UpdatedAt      DATETIME2(0)      NULL,
    CONSTRAINT PK_ProductVariants PRIMARY KEY (VariantID),
    CONSTRAINT UQ_ProductVariants_SKU UNIQUE (VariantSKU),
    CONSTRAINT UQ_ProductVariants_Option UNIQUE (ProductID, GoldColor, RingSize),
    CONSTRAINT UQ_ProductVariants_VariantProduct UNIQUE (VariantID, ProductID),  -- phục vụ FK kép từ OrderItems
    CONSTRAINT FK_ProductVariants_Products FOREIGN KEY (ProductID) REFERENCES dbo.Products(ProductID),
    CONSTRAINT FK_ProductVariants_RingSize FOREIGN KEY (RingSize) REFERENCES dbo.RingSizeChart(SizeVN),
    CONSTRAINT CK_ProductVariants_Stock CHECK (StockQuantity >= 0),       -- tồn kho không được âm
    CONSTRAINT CK_ProductVariants_Color CHECK (GoldColor IS NULL OR GoldColor IN (N'Vàng Vàng', N'Vàng Trắng', N'Vàng Hồng', N'Bạc Trắng', N'Bạc Vàng'))
);
GO

-- (11) ProductImages: nhiều hình ảnh cho một sản phẩm (FR4, FR6)
CREATE TABLE dbo.ProductImages (
    ImageID      INT IDENTITY(1,1) NOT NULL,
    ProductID    INT               NOT NULL,
    ImageUrl     VARCHAR(500)      NOT NULL,
    SortOrder    TINYINT           NOT NULL CONSTRAINT DF_ProductImages_SortOrder DEFAULT (0),
    IsThumbnail  BIT               NOT NULL CONSTRAINT DF_ProductImages_IsThumbnail DEFAULT (0),
    CONSTRAINT PK_ProductImages PRIMARY KEY (ImageID),
    CONSTRAINT FK_ProductImages_Products FOREIGN KEY (ProductID) REFERENCES dbo.Products(ProductID) ON DELETE CASCADE
);
GO
CREATE UNIQUE INDEX UX_ProductImages_Thumbnail ON dbo.ProductImages(ProductID) WHERE IsThumbnail = 1;
GO

-- (12) ProductStones: thông tin đá gắn trên sản phẩm (BRD1, FR6)
CREATE TABLE dbo.ProductStones (
    StoneID      INT IDENTITY(1,1) NOT NULL,
    ProductID    INT               NOT NULL,
    StoneType    VARCHAR(20)       NOT NULL,
    StoneName    NVARCHAR(50)      NULL,                   -- tên đá cụ thể: Sapphire, Ruby, Mã não...
    SizeMm       VARCHAR(20)       NULL,                   -- kích thước: "1.25" hoặc "7x11" (mm)
    Quantity     SMALLINT          NOT NULL,
    IsMainStone  BIT               NOT NULL CONSTRAINT DF_ProductStones_IsMain DEFAULT (0),
    CONSTRAINT PK_ProductStones PRIMARY KEY (StoneID),
    CONSTRAINT FK_ProductStones_Products FOREIGN KEY (ProductID) REFERENCES dbo.Products(ProductID) ON DELETE CASCADE,
    CONSTRAINT CK_ProductStones_Type CHECK (StoneType IN ('NaturalDiamond', 'LabDiamond', 'Moissanite', 'CZ', 'Pearl', 'MotherOfPearl', 'Gemstone', 'Other')),
    CONSTRAINT CK_ProductStones_Qty CHECK (Quantity > 0)
);
GO

-- (13) ProductCertificates: giấy chứng nhận/kiểm định (tuổi vàng, kim cương, đá quý) (BRD1, FR6, FR19)
CREATE TABLE dbo.ProductCertificates (
    CertificateID        INT IDENTITY(1,1) NOT NULL,
    ProductID            INT               NOT NULL,
    CertificateType      VARCHAR(20)       NOT NULL,
    IssuingOrganization  NVARCHAR(100)     NOT NULL,       -- GIA, IGI, trung tâm kiểm định vàng...
    CertificateNo        VARCHAR(50)       NULL,
    IssueDate            DATE              NULL,
    DocumentUrl          VARCHAR(500)      NULL,
    Note                 NVARCHAR(255)     NULL,
    CONSTRAINT PK_ProductCertificates PRIMARY KEY (CertificateID),
    CONSTRAINT FK_ProductCertificates_Products FOREIGN KEY (ProductID) REFERENCES dbo.Products(ProductID) ON DELETE CASCADE,
    CONSTRAINT CK_ProductCertificates_Type CHECK (CertificateType IN ('GoldPurity', 'Diamond', 'Gemstone'))
);
GO
CREATE UNIQUE INDEX UX_ProductCertificates_No ON dbo.ProductCertificates(IssuingOrganization, CertificateNo) WHERE CertificateNo IS NOT NULL;
GO

-- (14) GoldPrices: bảng giá vàng theo tuổi vàng, dùng cho sản phẩm tính giá theo trọng lượng
--      (Giá bán = Trọng lượng (chỉ) x Giá vàng thời điểm + Tiền công) – bổ sung từ dữ liệu crawl
CREATE TABLE dbo.GoldPrices (
    GoldPriceID      INT IDENTITY(1,1) NOT NULL,
    Material         VARCHAR(10)       NOT NULL,
    BuyPricePerChi   DECIMAL(15,0)     NOT NULL,           -- giá mua vào / 1 chỉ (3,75 g)
    SellPricePerChi  DECIMAL(15,0)     NOT NULL,           -- giá bán ra / 1 chỉ
    EffectiveFrom    DATETIME2(0)      NOT NULL,
    UpdatedByUserID  INT               NULL,
    CONSTRAINT PK_GoldPrices PRIMARY KEY (GoldPriceID),
    CONSTRAINT UQ_GoldPrices_MaterialTime UNIQUE (Material, EffectiveFrom),
    CONSTRAINT FK_GoldPrices_Users FOREIGN KEY (UpdatedByUserID) REFERENCES dbo.Users(UserID),
    CONSTRAINT CK_GoldPrices_Material CHECK (Material IN ('10K', '14K', '18K', '22K', '24K')),
    CONSTRAINT CK_GoldPrices_Value CHECK (BuyPricePerChi > 0 AND SellPricePerChi >= BuyPricePerChi)
);
GO

/* ---------- 1.3. PHÂN HỆ MUA SẮM ---------- */

-- (15) Vouchers: mã ưu đãi khuyến mãi và ưu đãi giữ chân đơn hàng (BRD4, BRD5, NFR7)
CREATE TABLE dbo.Vouchers (
    VoucherID          INT IDENTITY(1,1) NOT NULL,
    VoucherCode        VARCHAR(30)       NOT NULL,
    VoucherName        NVARCHAR(150)     NOT NULL,
    VoucherType        VARCHAR(15)       NOT NULL,         -- Promotion: mã nhập khi đặt hàng; Retention: ưu đãi giữ đơn
    DiscountType       VARCHAR(10)       NOT NULL,         -- Percent / Amount
    DiscountValue      DECIMAL(15,0)     NOT NULL,
    MaxDiscountAmount  DECIMAL(15,0)     NULL,
    MinOrderValue      DECIMAL(15,0)     NOT NULL CONSTRAINT DF_Vouchers_MinOrder DEFAULT (0),
    StartAt            DATETIME2(0)      NOT NULL,
    EndAt              DATETIME2(0)      NOT NULL,
    UsageLimit         INT               NULL,             -- NULL = không giới hạn
    UsedCount          INT               NOT NULL CONSTRAINT DF_Vouchers_UsedCount DEFAULT (0),
    IsActive           BIT               NOT NULL CONSTRAINT DF_Vouchers_IsActive DEFAULT (1),
    CONSTRAINT PK_Vouchers PRIMARY KEY (VoucherID),
    CONSTRAINT UQ_Vouchers_Code UNIQUE (VoucherCode),
    CONSTRAINT CK_Vouchers_Type CHECK (VoucherType IN ('Promotion', 'Retention')),
    CONSTRAINT CK_Vouchers_DiscountType CHECK (DiscountType IN ('Percent', 'Amount')),
    CONSTRAINT CK_Vouchers_Value CHECK (DiscountValue > 0 AND (DiscountType = 'Amount' OR DiscountValue <= 100)),
    CONSTRAINT CK_Vouchers_Period CHECK (EndAt > StartAt),
    CONSTRAINT CK_Vouchers_Usage CHECK (UsedCount >= 0 AND (UsageLimit IS NULL OR UsedCount <= UsageLimit))
);
GO

-- (16) CartItems: giỏ hàng lưu theo khách hàng và biến thể (phân biệt size) (FR9)
CREATE TABLE dbo.CartItems (
    CartItemID     INT IDENTITY(1,1) NOT NULL,
    CustomerID     INT               NOT NULL,
    VariantID      INT               NOT NULL,
    Quantity       SMALLINT          NOT NULL,
    EngravingText  NVARCHAR(30)      NULL,
    AddedAt        DATETIME2(0)      NOT NULL CONSTRAINT DF_CartItems_AddedAt DEFAULT (SYSDATETIME()),
    UpdatedAt      DATETIME2(0)      NULL,
    CONSTRAINT PK_CartItems PRIMARY KEY (CartItemID),
    CONSTRAINT UQ_CartItems_Line UNIQUE (CustomerID, VariantID, EngravingText),
    CONSTRAINT FK_CartItems_Customers FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID) ON DELETE CASCADE,
    CONSTRAINT FK_CartItems_Variants FOREIGN KEY (VariantID) REFERENCES dbo.ProductVariants(VariantID),
    CONSTRAINT CK_CartItems_Qty CHECK (Quantity BETWEEN 1 AND 10)
);
GO

-- (17) RecentlyViewedProducts: lịch sử sản phẩm đã xem (FR8)
CREATE TABLE dbo.RecentlyViewedProducts (
    CustomerID    INT           NOT NULL,
    ProductID     INT           NOT NULL,
    LastViewedAt  DATETIME2(0)  NOT NULL CONSTRAINT DF_RecentlyViewed_LastViewed DEFAULT (SYSDATETIME()),
    ViewCount     INT           NOT NULL CONSTRAINT DF_RecentlyViewed_ViewCount DEFAULT (1),
    CONSTRAINT PK_RecentlyViewedProducts PRIMARY KEY (CustomerID, ProductID),
    CONSTRAINT FK_RecentlyViewed_Customers FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID) ON DELETE CASCADE,
    CONSTRAINT FK_RecentlyViewed_Products FOREIGN KEY (ProductID) REFERENCES dbo.Products(ProductID) ON DELETE CASCADE,
    CONSTRAINT CK_RecentlyViewed_Count CHECK (ViewCount >= 1)
);
GO

/* ---------- 1.4. PHÂN HỆ ĐƠN HÀNG ---------- */

CREATE SEQUENCE dbo.seq_OrderNo AS INT START WITH 1 INCREMENT BY 1;
GO

-- (18) Orders: đơn hàng (BRD4, BRD5, FR10–FR14, FR22)
CREATE TABLE dbo.Orders (
    OrderID                  INT IDENTITY(1,1) NOT NULL,
    OrderCode                VARCHAR(20)       NOT NULL,
    CustomerID               INT               NOT NULL,
    -- Ảnh chụp địa chỉ giao hàng tại thời điểm đặt (không đổi khi khách sửa sổ địa chỉ)
    ShipRecipientName        NVARCHAR(100)     NOT NULL,
    ShipPhone                VARCHAR(15)       NOT NULL,
    ShipAddress              NVARCHAR(400)     NOT NULL,
    Subtotal                 DECIMAL(15,0)     NOT NULL,   -- tổng tiền hàng
    VoucherID                INT               NULL,       -- mã khuyến mãi áp dụng khi đặt
    DiscountAmount           DECIMAL(15,0)     NOT NULL CONSTRAINT DF_Orders_Discount DEFAULT (0),
    IsRetentionApplied       BIT               NOT NULL CONSTRAINT DF_Orders_IsRetention DEFAULT (0),
    RetentionDiscountAmount  DECIMAL(15,0)     NOT NULL CONSTRAINT DF_Orders_RetentionDiscount DEFAULT (0),
    ShippingFee              DECIMAL(15,0)     NOT NULL CONSTRAINT DF_Orders_ShippingFee DEFAULT (0),
    TotalAmount              AS (Subtotal - DiscountAmount - RetentionDiscountAmount + ShippingFee) PERSISTED,
    OrderStatus              VARCHAR(15)       NOT NULL CONSTRAINT DF_Orders_Status DEFAULT ('Pending'),
    CheckoutToken            UNIQUEIDENTIFIER  NOT NULL,   -- khóa chống gửi lặp, mỗi lần thanh toán sinh 1 token
    Note                     NVARCHAR(500)     NULL,
    CancelReason             NVARCHAR(500)     NULL,
    CreatedAt                DATETIME2(0)      NOT NULL CONSTRAINT DF_Orders_CreatedAt DEFAULT (SYSDATETIME()),
    ConfirmedAt              DATETIME2(0)      NULL,
    ShippedAt                DATETIME2(0)      NULL,
    DeliveredAt              DATETIME2(0)      NULL,
    CancelledAt              DATETIME2(0)      NULL,
    UpdatedAt                DATETIME2(0)      NULL,
    CONSTRAINT PK_Orders PRIMARY KEY (OrderID),
    CONSTRAINT UQ_Orders_Code UNIQUE (OrderCode),
    CONSTRAINT UQ_Orders_CheckoutToken UNIQUE (CheckoutToken),
    CONSTRAINT UQ_Orders_OrderCustomer UNIQUE (OrderID, CustomerID),     -- phục vụ FK kép đảm bảo đúng chủ đơn
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID),
    CONSTRAINT FK_Orders_Vouchers FOREIGN KEY (VoucherID) REFERENCES dbo.Vouchers(VoucherID),
    CONSTRAINT CK_Orders_Status CHECK (OrderStatus IN ('Pending', 'Confirmed', 'Shipping', 'Delivered', 'Cancelled')),
    CONSTRAINT CK_Orders_Amounts CHECK (Subtotal >= 0 AND DiscountAmount >= 0 AND RetentionDiscountAmount >= 0 AND ShippingFee >= 0
                                        AND DiscountAmount + RetentionDiscountAmount <= Subtotal),
    CONSTRAINT CK_Orders_Retention CHECK (IsRetentionApplied = 1 OR RetentionDiscountAmount = 0),
    CONSTRAINT CK_Orders_DeliveredAt CHECK (OrderStatus <> 'Delivered' OR DeliveredAt IS NOT NULL),
    CONSTRAINT CK_Orders_CancelledAt CHECK (OrderStatus <> 'Cancelled' OR CancelledAt IS NOT NULL)
);
GO

-- (19) OrderItems: chi tiết đơn hàng, lưu "ảnh chụp" sản phẩm tại thời điểm mua (FR10, FR12, FR19)
CREATE TABLE dbo.OrderItems (
    OrderItemID      INT IDENTITY(1,1) NOT NULL,
    OrderID          INT               NOT NULL,
    ProductID        INT               NOT NULL,
    VariantID        INT               NOT NULL,
    ProductNameSnap  NVARCHAR(200)     NOT NULL,           -- tên sản phẩm lúc mua
    SKUSnap          VARCHAR(60)       NOT NULL,           -- mã biến thể lúc mua
    MaterialSnap     VARCHAR(10)       NOT NULL,           -- tuổi vàng lúc mua (thống kê doanh thu theo nhóm vàng)
    GoldColor        NVARCHAR(20)      NULL,
    RingSize         TINYINT           NULL,
    EngravingText    NVARCHAR(30)      NULL,
    Quantity         SMALLINT          NOT NULL,
    UnitPrice        DECIMAL(15,0)     NOT NULL,           -- đơn giá đã kiểm tra lại khi tạo đơn
    LineTotal        AS (CAST(Quantity * UnitPrice AS DECIMAL(15,0))) PERSISTED,
    CONSTRAINT PK_OrderItems PRIMARY KEY (OrderItemID),
    CONSTRAINT UQ_OrderItems_Ref UNIQUE (OrderItemID, OrderID, ProductID), -- phục vụ FK kép từ WarrantyRecords
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID),
    CONSTRAINT FK_OrderItems_Products FOREIGN KEY (ProductID) REFERENCES dbo.Products(ProductID),
    -- FK kép: VariantID phải thuộc đúng ProductID
    CONSTRAINT FK_OrderItems_Variants FOREIGN KEY (VariantID, ProductID) REFERENCES dbo.ProductVariants(VariantID, ProductID),
    CONSTRAINT FK_OrderItems_RingSize FOREIGN KEY (RingSize) REFERENCES dbo.RingSizeChart(SizeVN),
    CONSTRAINT CK_OrderItems_Qty CHECK (Quantity BETWEEN 1 AND 10),
    CONSTRAINT CK_OrderItems_Price CHECK (UnitPrice >= 0),
    CONSTRAINT CK_OrderItems_Material CHECK (MaterialSnap IN ('10K', '14K', '18K', '22K', '24K', 'BAC925'))
);
GO

-- (20) Payments: các lần thanh toán của đơn (một đơn có thể thử thanh toán nhiều lần) (FR11)
CREATE TABLE dbo.Payments (
    PaymentID      INT IDENTITY(1,1) NOT NULL,
    OrderID        INT               NOT NULL,
    PaymentMethod  VARCHAR(20)       NOT NULL,
    Amount         DECIMAL(15,0)     NOT NULL,
    Status         VARCHAR(10)       NOT NULL CONSTRAINT DF_Payments_Status DEFAULT ('Pending'),
    TransactionID  VARCHAR(100)      NULL,                 -- mã giao dịch do cổng thanh toán trả về
    ResponseCode   VARCHAR(20)       NULL,
    IsSandbox      BIT               NOT NULL CONSTRAINT DF_Payments_IsSandbox DEFAULT (1),
    CreatedAt      DATETIME2(0)      NOT NULL CONSTRAINT DF_Payments_CreatedAt DEFAULT (SYSDATETIME()),
    PaidAt         DATETIME2(0)      NULL,
    CONSTRAINT PK_Payments PRIMARY KEY (PaymentID),
    CONSTRAINT FK_Payments_Orders FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID),
    CONSTRAINT CK_Payments_Method CHECK (PaymentMethod IN ('COD', 'BankTransfer', 'VNPay', 'MoMo')),
    CONSTRAINT CK_Payments_Status CHECK (Status IN ('Pending', 'Success', 'Failed', 'Refunded')),
    CONSTRAINT CK_Payments_Amount CHECK (Amount >= 0),
    CONSTRAINT CK_Payments_PaidAt CHECK (Status <> 'Success' OR PaidAt IS NOT NULL)
);
GO
-- Không ghi nhận trùng một mã giao dịch; mỗi đơn chỉ có tối đa một lần thanh toán thành công (NFR5)
CREATE UNIQUE INDEX UX_Payments_Transaction ON dbo.Payments(TransactionID) WHERE TransactionID IS NOT NULL;
CREATE UNIQUE INDEX UX_Payments_OneSuccess ON dbo.Payments(OrderID) WHERE Status = 'Success';
GO

-- (21) OrderCancellationRequests: yêu cầu hủy và đề nghị giữ lại đơn (BRD5, FR13, FR26)
CREATE TABLE dbo.OrderCancellationRequests (
    RequestID            INT IDENTITY(1,1) NOT NULL,
    OrderID              INT               NOT NULL,
    Reason               NVARCHAR(500)     NULL,
    RequestedAt          DATETIME2(0)      NOT NULL CONSTRAINT DF_CancelReq_RequestedAt DEFAULT (SYSDATETIME()),
    OfferShown           BIT               NOT NULL CONSTRAINT DF_CancelReq_OfferShown DEFAULT (0),
    OfferVoucherID       INT               NULL,
    OfferDiscountAmount  DECIMAL(15,0)     NULL,
    Decision             VARCHAR(20)       NOT NULL CONSTRAINT DF_CancelReq_Decision DEFAULT ('Pending'),
    DecidedAt            DATETIME2(0)      NULL,
    CONSTRAINT PK_OrderCancellationRequests PRIMARY KEY (RequestID),
    CONSTRAINT FK_CancelReq_Orders FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID),
    CONSTRAINT FK_CancelReq_Vouchers FOREIGN KEY (OfferVoucherID) REFERENCES dbo.Vouchers(VoucherID),
    CONSTRAINT CK_CancelReq_Decision CHECK (Decision IN ('Pending', 'AcceptedOffer', 'ConfirmedCancel')),
    CONSTRAINT CK_CancelReq_Offer CHECK ((OfferShown = 0 AND OfferVoucherID IS NULL AND OfferDiscountAmount IS NULL AND Decision <> 'AcceptedOffer')
                                      OR (OfferShown = 1 AND OfferVoucherID IS NOT NULL AND OfferDiscountAmount >= 0)),
    CONSTRAINT CK_CancelReq_DecidedAt CHECK (Decision = 'Pending' OR DecidedAt IS NOT NULL)
);
GO
-- Mỗi đơn chỉ được hiển thị đề nghị giữ chân tối đa 1 lần, và chỉ có 1 yêu cầu đang chờ
CREATE UNIQUE INDEX UX_CancelReq_OneOffer ON dbo.OrderCancellationRequests(OrderID) WHERE OfferShown = 1;
CREATE UNIQUE INDEX UX_CancelReq_OnePending ON dbo.OrderCancellationRequests(OrderID) WHERE Decision = 'Pending';
GO

/* ---------- 1.5. PHÂN HỆ BẢO HÀNH ĐIỆN TỬ & HẬU MÃI ---------- */

-- (22) WarrantyRecords: thẻ bảo hành điện tử, mỗi đơn vị sản phẩm đã nhận có 1 thẻ (BRD6, FR15)
CREATE TABLE dbo.WarrantyRecords (
    WarrantyID          INT IDENTITY(1,1) NOT NULL,
    WarrantyCode        VARCHAR(20)       NOT NULL,
    CustomerID          INT               NOT NULL,
    ProductID           INT               NOT NULL,
    OrderID             INT               NOT NULL,
    OrderItemID         INT               NOT NULL,
    UnitNo              TINYINT           NOT NULL CONSTRAINT DF_Warranty_UnitNo DEFAULT (1), -- thứ tự đơn vị khi số lượng > 1
    WarrantyPolicyID    INT               NOT NULL,
    IssueDate           DATETIME2(0)      NOT NULL CONSTRAINT DF_Warranty_IssueDate DEFAULT (SYSDATETIME()), -- ngày kích hoạt
    CleaningCount       INT               NOT NULL CONSTRAINT DF_Warranty_Cleaning DEFAULT (0),  -- số lần đã làm sạch
    PolishingCountLeft  TINYINT           NOT NULL,                                               -- số lượt đánh bóng/xi mới còn lại
    ResizingCount       INT               NOT NULL CONSTRAINT DF_Warranty_Resizing DEFAULT (0),  -- số lần đã chỉnh size
    Status              VARCHAR(10)       NOT NULL CONSTRAINT DF_Warranty_Status DEFAULT ('Active'),
    CONSTRAINT PK_WarrantyRecords PRIMARY KEY (WarrantyID),
    CONSTRAINT UQ_WarrantyRecords_Code UNIQUE (WarrantyCode),
    CONSTRAINT UQ_WarrantyRecords_Unit UNIQUE (OrderItemID, UnitNo),       -- chống tạo trùng thẻ (FR15, NFR5)
    CONSTRAINT FK_Warranty_Customers FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID),
    CONSTRAINT FK_Warranty_Products FOREIGN KEY (ProductID) REFERENCES dbo.Products(ProductID),
    CONSTRAINT FK_Warranty_Orders FOREIGN KEY (OrderID, CustomerID) REFERENCES dbo.Orders(OrderID, CustomerID),
    CONSTRAINT FK_Warranty_OrderItems FOREIGN KEY (OrderItemID, OrderID, ProductID) REFERENCES dbo.OrderItems(OrderItemID, OrderID, ProductID),
    CONSTRAINT FK_Warranty_Policies FOREIGN KEY (WarrantyPolicyID) REFERENCES dbo.WarrantyPolicies(WarrantyPolicyID),
    CONSTRAINT CK_Warranty_Counts CHECK (CleaningCount >= 0 AND ResizingCount >= 0),
    CONSTRAINT CK_Warranty_Status CHECK (Status IN ('Active', 'Voided'))
);
GO

-- (23) AfterSalesServices: lịch hẹn dịch vụ hậu mãi đặt bằng thẻ bảo hành (BRD7, FR16, FR17, FR23)
CREATE TABLE dbo.AfterSalesServices (
    ServiceID         INT IDENTITY(1,1) NOT NULL,
    WarrantyID        INT               NOT NULL,
    ServiceType       VARCHAR(15)       NOT NULL,
    PreferredDate     DATETIME2(0)      NOT NULL,          -- thời gian khách mong muốn
    AppointmentDate   DATETIME2(0)      NULL,              -- thời gian được xác nhận/đề xuất
    NewRingSize       TINYINT           NULL,              -- size mới khi chỉnh size
    Status            VARCHAR(15)       NOT NULL CONSTRAINT DF_AfterSales_Status DEFAULT ('Pending'),
    CustomerNote      NVARCHAR(500)     NULL,
    ResultNote        NVARCHAR(500)     NULL,
    HandledByUserID   INT               NULL,              -- quản trị viên xử lý
    IsFreeOfCharge    BIT               NULL,              -- xác định khi hoàn tất
    ServiceFee        DECIMAL(15,0)     NOT NULL CONSTRAINT DF_AfterSales_Fee DEFAULT (0),
    IsQuotaDeducted   BIT               NOT NULL CONSTRAINT DF_AfterSales_Deducted DEFAULT (0),
    CreatedAt         DATETIME2(0)      NOT NULL CONSTRAINT DF_AfterSales_CreatedAt DEFAULT (SYSDATETIME()),
    CompletedAt       DATETIME2(0)      NULL,
    CONSTRAINT PK_AfterSalesServices PRIMARY KEY (ServiceID),
    CONSTRAINT FK_AfterSales_Warranty FOREIGN KEY (WarrantyID) REFERENCES dbo.WarrantyRecords(WarrantyID),
    CONSTRAINT FK_AfterSales_Users FOREIGN KEY (HandledByUserID) REFERENCES dbo.Users(UserID),
    CONSTRAINT FK_AfterSales_RingSize FOREIGN KEY (NewRingSize) REFERENCES dbo.RingSizeChart(SizeVN),
    CONSTRAINT CK_AfterSales_Type CHECK (ServiceType IN ('Cleaning', 'Polishing', 'Replating', 'Resizing')),
    CONSTRAINT CK_AfterSales_Status CHECK (Status IN ('Pending', 'Confirmed', 'Rescheduled', 'Completed', 'Cancelled')),
    CONSTRAINT CK_AfterSales_Resize CHECK ((ServiceType = 'Resizing' AND NewRingSize IS NOT NULL) OR (ServiceType <> 'Resizing' AND NewRingSize IS NULL)),
    CONSTRAINT CK_AfterSales_Completed CHECK (Status <> 'Completed' OR (CompletedAt IS NOT NULL AND IsFreeOfCharge IS NOT NULL)),
    CONSTRAINT CK_AfterSales_Fee CHECK (ServiceFee >= 0)
);
GO

/* ---------- 1.6. PHÂN HỆ PHẢN HỒI KHÁCH HÀNG ---------- */

-- (24) CustomerFeedbacks: đánh giá sau mua, mỗi đơn đã nhận tối đa 1 đánh giá (BRD8, FR18, FR25)
CREATE TABLE dbo.CustomerFeedbacks (
    FeedbackID            INT IDENTITY(1,1) NOT NULL,
    OrderID               INT               NOT NULL,
    CustomerID            INT               NOT NULL,
    RatingStar            TINYINT           NOT NULL,
    ReviewText            NVARCHAR(2000)    NULL,
    SentimentLabel        VARCHAR(10)       NULL,          -- Positive / Negative (NULL khi chưa phân tích)
    SentimentScore        DECIMAL(4,3)      NULL,          -- độ tin cậy 0..1
    IsSentimentSimulated  BIT               NOT NULL CONSTRAINT DF_Feedback_Simulated DEFAULT (1), -- nhận diện kết quả mô phỏng (FR25)
    CreatedAt             DATETIME2(0)      NOT NULL CONSTRAINT DF_Feedback_CreatedAt DEFAULT (SYSDATETIME()),
    AnalyzedAt            DATETIME2(0)      NULL,
    CONSTRAINT PK_CustomerFeedbacks PRIMARY KEY (FeedbackID),
    CONSTRAINT UQ_CustomerFeedbacks_Order UNIQUE (OrderID),
    -- FK kép: người đánh giá phải là chủ đơn hàng
    CONSTRAINT FK_Feedback_Orders FOREIGN KEY (OrderID, CustomerID) REFERENCES dbo.Orders(OrderID, CustomerID),
    CONSTRAINT FK_Feedback_Customers FOREIGN KEY (CustomerID) REFERENCES dbo.Customers(CustomerID),
    CONSTRAINT CK_Feedback_Rating CHECK (RatingStar BETWEEN 1 AND 5),
    CONSTRAINT CK_Feedback_Sentiment CHECK (SentimentLabel IS NULL OR SentimentLabel IN ('Positive', 'Negative')),
    CONSTRAINT CK_Feedback_Score CHECK (SentimentScore IS NULL OR SentimentScore BETWEEN 0 AND 1)
);
GO

-- (25) FeedbackAspects: các yếu tố khách hàng đề cập trong nhận xét (FR25)
CREATE TABLE dbo.FeedbackAspects (
    AspectID    INT IDENTITY(1,1) NOT NULL,
    FeedbackID  INT               NOT NULL,
    AspectName  NVARCHAR(50)      NOT NULL,                -- Độ sáng bóng, Đóng gói, Giao hàng, Size nhẫn...
    Polarity    VARCHAR(10)       NOT NULL,
    CONSTRAINT PK_FeedbackAspects PRIMARY KEY (AspectID),
    CONSTRAINT UQ_FeedbackAspects UNIQUE (FeedbackID, AspectName),
    CONSTRAINT FK_FeedbackAspects_Feedback FOREIGN KEY (FeedbackID) REFERENCES dbo.CustomerFeedbacks(FeedbackID) ON DELETE CASCADE,
    CONSTRAINT CK_FeedbackAspects_Polarity CHECK (Polarity IN ('Positive', 'Negative'))
);
GO

/* ---------- 1.7. NHẬT KÝ HỆ THỐNG ---------- */

-- (26) AuditLogs: nhật ký thay đổi quan trọng (NFR8) – không chứa mật khẩu/thông tin thẻ
CREATE TABLE dbo.AuditLogs (
    LogID              BIGINT IDENTITY(1,1) NOT NULL,
    EntityName         VARCHAR(50)          NOT NULL,      -- Orders, Payments, AfterSalesServices...
    EntityID           INT                  NOT NULL,
    Action             VARCHAR(50)          NOT NULL,      -- StatusChanged, RetentionApplied, ServiceCompleted...
    OldValue           NVARCHAR(200)        NULL,
    NewValue           NVARCHAR(200)        NULL,
    PerformedByUserID  INT                  NULL,
    PerformedBy        NVARCHAR(100)        NOT NULL,      -- người dùng hoặc tiến trình hệ thống
    CreatedAt          DATETIME2(0)         NOT NULL CONSTRAINT DF_AuditLogs_CreatedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_AuditLogs PRIMARY KEY (LogID),
    CONSTRAINT FK_AuditLogs_Users FOREIGN KEY (PerformedByUserID) REFERENCES dbo.Users(UserID)
);
GO

/* =====================================================================
   PHẦN 2. CHỈ MỤC
   ===================================================================== */
CREATE INDEX IX_Products_Category       ON dbo.Products(CategoryID, Status) INCLUDE (Price, Material);
CREATE INDEX IX_Products_Name           ON dbo.Products(ProductName);
CREATE INDEX IX_Products_Price          ON dbo.Products(Status, Price);
CREATE INDEX IX_ProductCollections_Coll ON dbo.ProductCollections(CollectionID);
CREATE INDEX IX_ProductVariants_Product ON dbo.ProductVariants(ProductID) INCLUDE (StockQuantity, IsActive);
CREATE INDEX IX_ProductImages_Product   ON dbo.ProductImages(ProductID, SortOrder);
CREATE INDEX IX_ProductStones_Product   ON dbo.ProductStones(ProductID);
CREATE INDEX IX_GoldPrices_Lookup       ON dbo.GoldPrices(Material, EffectiveFrom DESC);
CREATE INDEX IX_RecentlyViewed_Customer ON dbo.RecentlyViewedProducts(CustomerID, LastViewedAt DESC);
CREATE INDEX IX_Orders_Customer         ON dbo.Orders(CustomerID, CreatedAt DESC);
CREATE INDEX IX_Orders_Status           ON dbo.Orders(OrderStatus, DeliveredAt);
CREATE INDEX IX_OrderItems_Order        ON dbo.OrderItems(OrderID);
CREATE INDEX IX_OrderItems_Variant      ON dbo.OrderItems(VariantID);
CREATE INDEX IX_Payments_Order          ON dbo.Payments(OrderID, Status);
CREATE INDEX IX_Warranty_Customer       ON dbo.WarrantyRecords(CustomerID);
CREATE INDEX IX_AfterSales_Warranty     ON dbo.AfterSalesServices(WarrantyID, Status);
CREATE INDEX IX_AfterSales_Schedule     ON dbo.AfterSalesServices(Status, AppointmentDate);
CREATE INDEX IX_Feedback_Sentiment      ON dbo.CustomerFeedbacks(SentimentLabel);
CREATE INDEX IX_AuditLogs_Entity        ON dbo.AuditLogs(EntityName, EntityID, CreatedAt);
GO

/* =====================================================================
   PHẦN 3. HÀM, TRIGGER VÀ THỦ TỤC NGHIỆP VỤ
   Ghi chú: ứng dụng back-end gọi EXEC sp_set_session_context N'UserID', <id>
   ở đầu mỗi phiên để trigger ghi nhận đúng người thực hiện vào AuditLogs.
   ===================================================================== */

-- 3.1. Hàm tính giá bán hiện hành của sản phẩm (dùng chung cho view và đặt hàng – NFR5)
CREATE OR ALTER FUNCTION dbo.fn_GetCurrentPrice (@ProductID INT)
RETURNS DECIMAL(15,0)
AS
BEGIN
    DECLARE @Price DECIMAL(15,0);
    SELECT @Price =
        CASE WHEN p.PricingMethod = 'Fixed' THEN p.Price
             ELSE CAST(ROUND(p.WeightGram / 3.75 * gp.SellPricePerChi + ISNULL(p.LaborPrice, 0), -3) AS DECIMAL(15,0))
        END
    FROM dbo.Products p
    OUTER APPLY (SELECT TOP (1) g.SellPricePerChi
                 FROM dbo.GoldPrices g
                 WHERE g.Material = p.Material AND g.EffectiveFrom <= SYSDATETIME()
                 ORDER BY g.EffectiveFrom DESC) gp
    WHERE p.ProductID = @ProductID;
    RETURN @Price;   -- NULL nếu sản phẩm tính theo giá vàng nhưng chưa có bảng giá
END
GO

-- 3.2. Hàm lấy người thực hiện từ SESSION_CONTEXT để ghi nhật ký
CREATE OR ALTER FUNCTION dbo.fn_CurrentActorID ()
RETURNS INT
AS
BEGIN
    RETURN TRY_CAST(SESSION_CONTEXT(N'UserID') AS INT);
END
GO

/* ---------- TRIGGER ---------- */

-- 3.3. Biến thể nhẫn bắt buộc có size; sản phẩm không phải nhẫn không được có size (FR7)
CREATE OR ALTER TRIGGER dbo.trg_ProductVariants_RingSize
ON dbo.ProductVariants
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN dbo.Products p   ON p.ProductID = i.ProductID
               JOIN dbo.Categories c ON c.CategoryID = p.CategoryID
               WHERE (c.RequiresRingSize = 1 AND i.RingSize IS NULL)
                  OR (c.RequiresRingSize = 0 AND i.RingSize IS NOT NULL))
        THROW 50040, N'Biến thể không hợp lệ: sản phẩm nhẫn phải có size, sản phẩm khác không dùng size.', 1;
END
GO

-- 3.4. Trigger trung tâm của đơn hàng:
--      (a) chặn chuyển trạng thái sai quy trình và sửa đơn đã hoàn tất/đã hủy (FR22)
--      (b) ghi nhật ký thay đổi trạng thái, áp dụng ưu đãi giữ chân (NFR8)
--      (c) tự động kích hoạt thẻ bảo hành khi đơn chuyển sang Delivered (BRD6, FR15)
CREATE OR ALTER TRIGGER dbo.trg_Orders_AfterUpdate
ON dbo.Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    -- (a1) Đơn đã Delivered/Cancelled là bất biến về trạng thái và số tiền
    IF EXISTS (SELECT 1 FROM inserted i JOIN deleted d ON d.OrderID = i.OrderID
               WHERE d.OrderStatus IN ('Delivered', 'Cancelled')
                 AND (i.OrderStatus <> d.OrderStatus OR i.Subtotal <> d.Subtotal OR i.DiscountAmount <> d.DiscountAmount
                      OR i.RetentionDiscountAmount <> d.RetentionDiscountAmount OR i.ShippingFee <> d.ShippingFee
                      OR i.CustomerID <> d.CustomerID))
        THROW 50001, N'Không được chỉnh sửa đơn hàng đã hoàn tất hoặc đã hủy.', 1;

    -- (a2) Chỉ cho phép: Pending->Confirmed/Cancelled, Confirmed->Shipping/Cancelled, Shipping->Delivered
    IF EXISTS (SELECT 1 FROM inserted i JOIN deleted d ON d.OrderID = i.OrderID
               WHERE i.OrderStatus <> d.OrderStatus
                 AND NOT ((d.OrderStatus = 'Pending'   AND i.OrderStatus IN ('Confirmed', 'Cancelled'))
                       OR (d.OrderStatus = 'Confirmed' AND i.OrderStatus IN ('Shipping', 'Cancelled'))
                       OR (d.OrderStatus = 'Shipping'  AND i.OrderStatus = 'Delivered')))
        THROW 50002, N'Chuyển trạng thái đơn hàng không đúng quy trình.', 1;

    -- (a3) Ưu đãi giữ chân chỉ được áp dụng một lần, không được gỡ bỏ
    IF EXISTS (SELECT 1 FROM inserted i JOIN deleted d ON d.OrderID = i.OrderID
               WHERE d.IsRetentionApplied = 1 AND (i.IsRetentionApplied = 0 OR i.RetentionDiscountAmount <> d.RetentionDiscountAmount))
        THROW 50003, N'Ưu đãi giữ chân đã áp dụng cho đơn này, không thể thay đổi.', 1;

    DECLARE @ActorID INT = dbo.fn_CurrentActorID();
    DECLARE @Actor NVARCHAR(100) = ISNULL(CAST(SESSION_CONTEXT(N'Actor') AS NVARCHAR(100)), ORIGINAL_LOGIN());

    -- (b) Nhật ký đổi trạng thái
    INSERT INTO dbo.AuditLogs (EntityName, EntityID, Action, OldValue, NewValue, PerformedByUserID, PerformedBy)
    SELECT 'Orders', i.OrderID, 'StatusChanged', d.OrderStatus, i.OrderStatus, @ActorID, @Actor
    FROM inserted i JOIN deleted d ON d.OrderID = i.OrderID
    WHERE i.OrderStatus <> d.OrderStatus;

    INSERT INTO dbo.AuditLogs (EntityName, EntityID, Action, OldValue, NewValue, PerformedByUserID, PerformedBy)
    SELECT 'Orders', i.OrderID, 'RetentionApplied', '0', CONCAT(N'Giảm ', i.RetentionDiscountAmount), @ActorID, @Actor
    FROM inserted i JOIN deleted d ON d.OrderID = i.OrderID
    WHERE i.IsRetentionApplied = 1 AND d.IsRetentionApplied = 0;

    -- (c) Kích hoạt thẻ bảo hành: mỗi đơn vị sản phẩm 1 thẻ, chạy lặp không tạo trùng
    INSERT INTO dbo.WarrantyRecords (WarrantyCode, CustomerID, ProductID, OrderID, OrderItemID, UnitNo,
                                     WarrantyPolicyID, IssueDate, PolishingCountLeft)
    SELECT CONCAT('VNW', FORMAT(SYSDATETIME(), 'yyMM'), RIGHT(CONCAT('0000000', oi.OrderItemID), 7), '-', u.UnitNo),
           i.CustomerID, oi.ProductID, i.OrderID, oi.OrderItemID, u.UnitNo,
           p.WarrantyPolicyID, SYSDATETIME(), wp.PolishingQuota
    FROM inserted i
    JOIN deleted d             ON d.OrderID = i.OrderID
    JOIN dbo.OrderItems oi     ON oi.OrderID = i.OrderID
    JOIN dbo.Products p        ON p.ProductID = oi.ProductID
    JOIN dbo.WarrantyPolicies wp ON wp.WarrantyPolicyID = p.WarrantyPolicyID
    CROSS APPLY (SELECT TOP (oi.Quantity) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS TINYINT) AS UnitNo
                 FROM sys.all_objects) u
    WHERE i.OrderStatus = 'Delivered' AND d.OrderStatus <> 'Delivered'
      AND NOT EXISTS (SELECT 1 FROM dbo.WarrantyRecords w WHERE w.OrderItemID = oi.OrderItemID AND w.UnitNo = u.UnitNo);

    INSERT INTO dbo.AuditLogs (EntityName, EntityID, Action, OldValue, NewValue, PerformedByUserID, PerformedBy)
    SELECT 'Orders', i.OrderID, 'WarrantyActivated', NULL,
           CONCAT((SELECT COUNT(*) FROM dbo.WarrantyRecords w WHERE w.OrderID = i.OrderID), N' thẻ'),
           NULL, N'System:trg_Orders_AfterUpdate'
    FROM inserted i JOIN deleted d ON d.OrderID = i.OrderID
    WHERE i.OrderStatus = 'Delivered' AND d.OrderStatus <> 'Delivered';
END
GO

-- 3.5. Nhật ký thay đổi trạng thái thanh toán (NFR8) – không ghi thông tin thẻ
CREATE OR ALTER TRIGGER dbo.trg_Payments_Audit
ON dbo.Payments
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.AuditLogs (EntityName, EntityID, Action, OldValue, NewValue, PerformedByUserID, PerformedBy)
    SELECT 'Payments', i.PaymentID,
           CASE WHEN d.PaymentID IS NULL THEN 'PaymentCreated' ELSE 'StatusChanged' END,
           d.Status, CONCAT(i.Status, N' | ', i.PaymentMethod, N' | ', i.Amount),
           dbo.fn_CurrentActorID(),
           ISNULL(CAST(SESSION_CONTEXT(N'Actor') AS NVARCHAR(100)), ORIGINAL_LOGIN())
    FROM inserted i
    LEFT JOIN deleted d ON d.PaymentID = i.PaymentID
    WHERE d.PaymentID IS NULL OR d.Status <> i.Status;
END
GO

-- 3.6. Chỉ đơn đã nhận thành công mới được đánh giá (FR18)
CREATE OR ALTER TRIGGER dbo.trg_CustomerFeedbacks_Validate
ON dbo.CustomerFeedbacks
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN dbo.Orders o ON o.OrderID = i.OrderID
               WHERE o.OrderStatus <> 'Delivered')
        THROW 50030, N'Chỉ được đánh giá đơn hàng đã nhận thành công.', 1;
END
GO

/* ---------- THỦ TỤC NGHIỆP VỤ ---------- */

-- 3.7. Đặt hàng từ giỏ hàng (FR10): kiểm tra lại giá, tồn kho; chống tạo trùng đơn (NFR5)
CREATE OR ALTER PROCEDURE dbo.sp_PlaceOrder
    @CustomerID     INT,
    @AddressID      INT,
    @PaymentMethod  VARCHAR(20),
    @CheckoutToken  UNIQUEIDENTIFIER,
    @ShippingFee    DECIMAL(15,0) = 0,
    @VoucherCode    VARCHAR(30)   = NULL,
    @Note           NVARCHAR(500) = NULL,
    @OrderID        INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @OrderID = NULL;
    -- Gửi lặp cùng token -> trả về đơn đã tạo, không tạo đơn mới
    SELECT @OrderID = OrderID FROM dbo.Orders WHERE CheckoutToken = @CheckoutToken;
    IF @OrderID IS NOT NULL RETURN;

    IF @PaymentMethod NOT IN ('COD', 'BankTransfer', 'VNPay', 'MoMo')
        THROW 50010, N'Phương thức thanh toán không được hỗ trợ.', 1;

    DECLARE @Recipient NVARCHAR(100), @Phone VARCHAR(15), @Address NVARCHAR(400);
    SELECT @Recipient = RecipientName, @Phone = Phone,
           @Address = CONCAT(AddressLine, N', ', Ward, N', ', Province)
    FROM dbo.CustomerAddresses
    WHERE AddressID = @AddressID AND CustomerID = @CustomerID;
    IF @Recipient IS NULL
        THROW 50011, N'Địa chỉ nhận hàng không hợp lệ.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Items TABLE (
            CartItemID INT PRIMARY KEY, VariantID INT, ProductID INT, Quantity SMALLINT,
            EngravingText NVARCHAR(30), UnitPrice DECIMAL(15,0), ProductName NVARCHAR(200),
            VariantSKU VARCHAR(60), Material VARCHAR(10), GoldColor NVARCHAR(20), RingSize TINYINT,
            ProductStatus VARCHAR(15), VariantActive BIT);

        INSERT INTO @Items
        SELECT ci.CartItemID, v.VariantID, p.ProductID, ci.Quantity, ci.EngravingText,
               dbo.fn_GetCurrentPrice(p.ProductID), p.ProductName, v.VariantSKU, p.Material,
               v.GoldColor, v.RingSize, p.Status, v.IsActive
        FROM dbo.CartItems ci
        JOIN dbo.ProductVariants v WITH (UPDLOCK, HOLDLOCK) ON v.VariantID = ci.VariantID
        JOIN dbo.Products p ON p.ProductID = v.ProductID
        WHERE ci.CustomerID = @CustomerID;

        IF NOT EXISTS (SELECT 1 FROM @Items)
            THROW 50012, N'Giỏ hàng đang trống.', 1;
        IF EXISTS (SELECT 1 FROM @Items WHERE ProductStatus <> 'Active' OR VariantActive = 0)
            THROW 50013, N'Có sản phẩm trong giỏ đã ngừng bán.', 1;
        IF EXISTS (SELECT 1 FROM @Items WHERE UnitPrice IS NULL)
            THROW 50014, N'Chưa xác định được giá bán của sản phẩm (thiếu bảng giá vàng).', 1;
        IF EXISTS (SELECT 1
                   FROM (SELECT VariantID, SUM(Quantity) AS Qty FROM @Items GROUP BY VariantID) x
                   JOIN dbo.ProductVariants v ON v.VariantID = x.VariantID
                   WHERE v.StockQuantity < x.Qty)
            THROW 50015, N'Số lượng tồn kho không đủ cho một hoặc nhiều sản phẩm.', 1;

        DECLARE @Subtotal DECIMAL(15,0) = (SELECT SUM(Quantity * UnitPrice) FROM @Items);
        DECLARE @VoucherID INT = NULL, @Discount DECIMAL(15,0) = 0, @MaxDiscount DECIMAL(15,0);

        IF @VoucherCode IS NOT NULL
        BEGIN
            SELECT @VoucherID = VoucherID,
                   @Discount = CASE WHEN DiscountType = 'Percent'
                                    THEN ROUND(@Subtotal * DiscountValue / 100, -3)
                                    ELSE DiscountValue END,
                   @MaxDiscount = MaxDiscountAmount
            FROM dbo.Vouchers WITH (UPDLOCK)
            WHERE VoucherCode = @VoucherCode AND VoucherType = 'Promotion' AND IsActive = 1
              AND SYSDATETIME() BETWEEN StartAt AND EndAt
              AND (UsageLimit IS NULL OR UsedCount < UsageLimit)
              AND @Subtotal >= MinOrderValue;
            IF @VoucherID IS NULL
                THROW 50016, N'Mã ưu đãi không hợp lệ hoặc không đủ điều kiện áp dụng.', 1;
            IF @MaxDiscount IS NOT NULL AND @Discount > @MaxDiscount SET @Discount = @MaxDiscount;
            IF @Discount > @Subtotal SET @Discount = @Subtotal;
            UPDATE dbo.Vouchers SET UsedCount = UsedCount + 1 WHERE VoucherID = @VoucherID;
        END

        DECLARE @OrderNo INT;
        SET @OrderNo = NEXT VALUE FOR dbo.seq_OrderNo;
        INSERT INTO dbo.Orders (OrderCode, CustomerID, ShipRecipientName, ShipPhone, ShipAddress,
                                Subtotal, VoucherID, DiscountAmount, ShippingFee, CheckoutToken, Note)
        VALUES (CONCAT('VN', FORMAT(SYSDATETIME(), 'yyMMdd'), RIGHT(CONCAT('000000', @OrderNo), 6)),
                @CustomerID, @Recipient, @Phone, @Address,
                @Subtotal, @VoucherID, @Discount, @ShippingFee, @CheckoutToken, @Note);
        SET @OrderID = SCOPE_IDENTITY();

        INSERT INTO dbo.OrderItems (OrderID, ProductID, VariantID, ProductNameSnap, SKUSnap, MaterialSnap,
                                    GoldColor, RingSize, EngravingText, Quantity, UnitPrice)
        SELECT @OrderID, ProductID, VariantID, ProductName, VariantSKU, Material,
               GoldColor, RingSize, EngravingText, Quantity, UnitPrice
        FROM @Items;

        -- Trừ tồn kho (CHECK StockQuantity >= 0 bảo vệ thêm một lớp)
        UPDATE v
        SET v.StockQuantity = v.StockQuantity - x.Qty, v.UpdatedAt = SYSDATETIME()
        FROM dbo.ProductVariants v
        JOIN (SELECT VariantID, SUM(Quantity) AS Qty FROM @Items GROUP BY VariantID) x ON x.VariantID = v.VariantID;

        INSERT INTO dbo.Payments (OrderID, PaymentMethod, Amount, Status, IsSandbox)
        SELECT @OrderID, @PaymentMethod, TotalAmount, 'Pending', CASE WHEN @PaymentMethod = 'COD' THEN 0 ELSE 1 END
        FROM dbo.Orders WHERE OrderID = @OrderID;

        DELETE FROM dbo.CartItems WHERE CustomerID = @CustomerID;

        INSERT INTO dbo.AuditLogs (EntityName, EntityID, Action, OldValue, NewValue, PerformedByUserID, PerformedBy)
        VALUES ('Orders', @OrderID, 'OrderCreated', NULL, 'Pending', dbo.fn_CurrentActorID(), N'Customer:' + CAST(@CustomerID AS NVARCHAR(10)));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @OrderID = NULL;
        THROW;
    END CATCH
END
GO

-- 3.8. Ghi nhận kết quả thanh toán từ cổng (sandbox) đã được xác thực chữ ký (FR11, NFR5)
CREATE OR ALTER PROCEDURE dbo.sp_RecordPaymentResult
    @PaymentID      INT,
    @IsSuccess      BIT,
    @TransactionID  VARCHAR(100),
    @ResponseCode   VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    -- Callback gửi lặp với cùng mã giao dịch -> bỏ qua
    IF EXISTS (SELECT 1 FROM dbo.Payments WHERE TransactionID = @TransactionID) RETURN;

    BEGIN TRANSACTION;
        UPDATE dbo.Payments
        SET Status = CASE WHEN @IsSuccess = 1 THEN 'Success' ELSE 'Failed' END,
            TransactionID = @TransactionID,
            ResponseCode = @ResponseCode,
            PaidAt = CASE WHEN @IsSuccess = 1 THEN SYSDATETIME() END
        WHERE PaymentID = @PaymentID AND Status = 'Pending';
        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 50017, N'Không tìm thấy giao dịch đang chờ thanh toán.', 1;
        END
    COMMIT TRANSACTION;
END
GO

-- 3.9. Hủy đơn (dùng nội bộ, gọi trong transaction của thủ tục khác):
--      cập nhật trạng thái, hoàn tồn kho, cập nhật thanh toán
CREATE OR ALTER PROCEDURE dbo.usp_CancelOrderInternal
    @OrderID  INT,
    @Reason   NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Orders
    SET OrderStatus = 'Cancelled', CancelledAt = SYSDATETIME(), CancelReason = @Reason, UpdatedAt = SYSDATETIME()
    WHERE OrderID = @OrderID AND OrderStatus IN ('Pending', 'Confirmed');
    IF @@ROWCOUNT = 0
        THROW 50020, N'Đơn hàng không còn đủ điều kiện hủy.', 1;

    -- Hoàn lại tồn kho đã trừ khi đặt hàng (FR13, FR21)
    UPDATE v
    SET v.StockQuantity = v.StockQuantity + x.Qty, v.UpdatedAt = SYSDATETIME()
    FROM dbo.ProductVariants v
    JOIN (SELECT VariantID, SUM(Quantity) AS Qty FROM dbo.OrderItems WHERE OrderID = @OrderID GROUP BY VariantID) x
      ON x.VariantID = v.VariantID;

    UPDATE dbo.Payments SET Status = 'Failed'   WHERE OrderID = @OrderID AND Status = 'Pending';
    UPDATE dbo.Payments SET Status = 'Refunded' WHERE OrderID = @OrderID AND Status = 'Success';
END
GO

-- 3.10. Khách yêu cầu hủy đơn (FR13): nếu đơn chưa từng nhận đề nghị giữ chân và có ưu đãi
--       Retention đang hiệu lực -> tạo đề nghị; ngược lại hủy ngay.
CREATE OR ALTER PROCEDURE dbo.sp_RequestCancelOrder
    @OrderID     INT,
    @CustomerID  INT,
    @Reason      NVARCHAR(500) = NULL,
    @RequestID   INT OUTPUT,
    @OfferShown  BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @OfferShown = 0;
    SET @RequestID = NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Status VARCHAR(15), @Goods DECIMAL(15,0), @RetentionUsed BIT;
        SELECT @Status = OrderStatus, @Goods = Subtotal - DiscountAmount, @RetentionUsed = IsRetentionApplied
        FROM dbo.Orders WITH (UPDLOCK)
        WHERE OrderID = @OrderID AND CustomerID = @CustomerID;

        IF @Status IS NULL THROW 50021, N'Không tìm thấy đơn hàng của khách hàng.', 1;
        IF @Status NOT IN ('Pending', 'Confirmed') THROW 50020, N'Đơn hàng không còn đủ điều kiện hủy.', 1;

        -- Đã có yêu cầu đang chờ -> trả về yêu cầu đó (chống gửi lặp)
        SELECT @RequestID = RequestID, @OfferShown = OfferShown
        FROM dbo.OrderCancellationRequests WHERE OrderID = @OrderID AND Decision = 'Pending';
        IF @RequestID IS NOT NULL
        BEGIN
            COMMIT TRANSACTION;
            RETURN;
        END

        DECLARE @VoucherID INT = NULL, @Offer DECIMAL(15,0) = NULL, @MaxOffer DECIMAL(15,0) = NULL;
        IF @RetentionUsed = 0
           AND NOT EXISTS (SELECT 1 FROM dbo.OrderCancellationRequests WHERE OrderID = @OrderID AND OfferShown = 1)
        BEGIN
            SELECT TOP (1) @VoucherID = VoucherID,
                   @Offer = CASE WHEN DiscountType = 'Percent' THEN ROUND(@Goods * DiscountValue / 100, -3) ELSE DiscountValue END,
                   @MaxOffer = MaxDiscountAmount
            FROM dbo.Vouchers
            WHERE VoucherType = 'Retention' AND IsActive = 1
              AND SYSDATETIME() BETWEEN StartAt AND EndAt
              AND (UsageLimit IS NULL OR UsedCount < UsageLimit)
              AND @Goods >= MinOrderValue
            ORDER BY DiscountValue DESC;
            IF @MaxOffer IS NOT NULL AND @Offer > @MaxOffer SET @Offer = @MaxOffer;
            IF @Offer > @Goods SET @Offer = @Goods;
        END

        IF @VoucherID IS NOT NULL
        BEGIN
            INSERT INTO dbo.OrderCancellationRequests (OrderID, Reason, OfferShown, OfferVoucherID, OfferDiscountAmount, Decision)
            VALUES (@OrderID, @Reason, 1, @VoucherID, @Offer, 'Pending');
            SET @OfferShown = 1;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.OrderCancellationRequests (OrderID, Reason, OfferShown, Decision, DecidedAt)
            VALUES (@OrderID, @Reason, 0, 'ConfirmedCancel', SYSDATETIME());
            EXEC dbo.usp_CancelOrderInternal @OrderID = @OrderID, @Reason = @Reason;
        END
        SET @RequestID = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- 3.11. Khách phản hồi đề nghị giữ đơn (FR13): đồng ý -> áp dụng ưu đãi 1 lần; từ chối -> hủy đơn
CREATE OR ALTER PROCEDURE dbo.sp_RespondRetentionOffer
    @RequestID    INT,
    @CustomerID   INT,
    @AcceptOffer  BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrderID INT, @Offer DECIMAL(15,0), @VoucherID INT, @Reason NVARCHAR(500);
        SELECT @OrderID = r.OrderID, @Offer = r.OfferDiscountAmount, @VoucherID = r.OfferVoucherID, @Reason = r.Reason
        FROM dbo.OrderCancellationRequests r WITH (UPDLOCK)
        JOIN dbo.Orders o ON o.OrderID = r.OrderID
        WHERE r.RequestID = @RequestID AND r.Decision = 'Pending' AND r.OfferShown = 1
          AND o.CustomerID = @CustomerID AND o.OrderStatus IN ('Pending', 'Confirmed');

        IF @OrderID IS NULL THROW 50022, N'Đề nghị giữ đơn không còn hiệu lực.', 1;

        IF @AcceptOffer = 1
        BEGIN
            UPDATE dbo.Orders
            SET IsRetentionApplied = 1, RetentionDiscountAmount = @Offer, UpdatedAt = SYSDATETIME()
            WHERE OrderID = @OrderID AND IsRetentionApplied = 0;
            IF @@ROWCOUNT = 0 THROW 50023, N'Đơn hàng đã được áp dụng ưu đãi giữ chân trước đó.', 1;

            UPDATE dbo.Vouchers SET UsedCount = UsedCount + 1 WHERE VoucherID = @VoucherID;
            -- Cập nhật số tiền cần thanh toán của giao dịch đang chờ
            UPDATE p SET p.Amount = o.TotalAmount
            FROM dbo.Payments p JOIN dbo.Orders o ON o.OrderID = p.OrderID
            WHERE p.OrderID = @OrderID AND p.Status = 'Pending';

            UPDATE dbo.OrderCancellationRequests
            SET Decision = 'AcceptedOffer', DecidedAt = SYSDATETIME()
            WHERE RequestID = @RequestID;
        END
        ELSE
        BEGIN
            UPDATE dbo.OrderCancellationRequests
            SET Decision = 'ConfirmedCancel', DecidedAt = SYSDATETIME()
            WHERE RequestID = @RequestID;
            EXEC dbo.usp_CancelOrderInternal @OrderID = @OrderID, @Reason = @Reason;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- 3.12. Quản trị viên cập nhật trạng thái đơn theo quy trình (FR22)
CREATE OR ALTER PROCEDURE dbo.sp_UpdateOrderStatus
    @OrderID      INT,
    @NewStatus    VARCHAR(15),
    @AdminUserID  INT,
    @Reason       NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserID = @AdminUserID AND Role = 'Admin' AND IsActive = 1)
        THROW 50024, N'Người thực hiện không có quyền quản trị.', 1;

    EXEC sp_set_session_context @key = N'UserID', @value = @AdminUserID;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF @NewStatus = 'Cancelled'
            EXEC dbo.usp_CancelOrderInternal @OrderID = @OrderID, @Reason = @Reason;
        ELSE
        BEGIN
            UPDATE dbo.Orders
            SET OrderStatus = @NewStatus,
                ConfirmedAt = CASE WHEN @NewStatus = 'Confirmed' THEN SYSDATETIME() ELSE ConfirmedAt END,
                ShippedAt   = CASE WHEN @NewStatus = 'Shipping'  THEN SYSDATETIME() ELSE ShippedAt END,
                DeliveredAt = CASE WHEN @NewStatus = 'Delivered' THEN SYSDATETIME() ELSE DeliveredAt END,
                UpdatedAt   = SYSDATETIME()
            WHERE OrderID = @OrderID;   -- trigger kiểm tra tính hợp lệ của bước chuyển
            IF @@ROWCOUNT = 0 THROW 50025, N'Không tìm thấy đơn hàng.', 1;

            IF @NewStatus = 'Delivered'   -- đơn COD được thu tiền khi giao thành công
                UPDATE dbo.Payments SET Status = 'Success', PaidAt = SYSDATETIME()
                WHERE OrderID = @OrderID AND PaymentMethod = 'COD' AND Status = 'Pending';
        END
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- 3.13. Khách xác nhận đã nhận hàng (FR14) -> Delivered; trigger tự kích hoạt thẻ bảo hành
CREATE OR ALTER PROCEDURE dbo.sp_ConfirmOrderReceived
    @OrderID     INT,
    @CustomerID  INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE dbo.Orders
        SET OrderStatus = 'Delivered', DeliveredAt = SYSDATETIME(), UpdatedAt = SYSDATETIME()
        WHERE OrderID = @OrderID AND CustomerID = @CustomerID AND OrderStatus = 'Shipping';
        IF @@ROWCOUNT = 0 THROW 50026, N'Chỉ xác nhận được đơn của bạn đang ở trạng thái đang giao.', 1;

        -- Đơn COD: tiền được thu khi giao hàng
        UPDATE dbo.Payments
        SET Status = 'Success', PaidAt = SYSDATETIME()
        WHERE OrderID = @OrderID AND PaymentMethod = 'COD' AND Status = 'Pending';
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- 3.14. Khách đặt lịch hậu mãi bằng thẻ bảo hành (FR16)
CREATE OR ALTER PROCEDURE dbo.sp_BookAfterSalesService
    @WarrantyCode   VARCHAR(20),
    @CustomerID     INT,
    @ServiceType    VARCHAR(15),
    @PreferredDate  DATETIME2(0),
    @NewRingSize    TINYINT       = NULL,
    @CustomerNote   NVARCHAR(500) = NULL,
    @ServiceID      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @WarrantyID INT, @IsRing BIT;
    SELECT @WarrantyID = w.WarrantyID, @IsRing = c.RequiresRingSize
    FROM dbo.WarrantyRecords w
    JOIN dbo.Products p   ON p.ProductID = w.ProductID
    JOIN dbo.Categories c ON c.CategoryID = p.CategoryID
    WHERE w.WarrantyCode = @WarrantyCode AND w.CustomerID = @CustomerID AND w.Status = 'Active';

    IF @WarrantyID IS NULL THROW 50031, N'Thẻ bảo hành không hợp lệ.', 1;
    IF @PreferredDate <= SYSDATETIME() THROW 50032, N'Thời gian hẹn phải ở tương lai.', 1;
    IF @ServiceType = 'Resizing' AND @IsRing = 0 THROW 50033, N'Dịch vụ chỉnh size chỉ áp dụng cho nhẫn.', 1;
    IF EXISTS (SELECT 1 FROM dbo.AfterSalesServices
               WHERE WarrantyID = @WarrantyID AND ServiceType = @ServiceType AND Status IN ('Pending', 'Confirmed', 'Rescheduled'))
        THROW 50034, N'Thẻ đã có lịch hẹn cùng loại dịch vụ đang xử lý.', 1;

    INSERT INTO dbo.AfterSalesServices (WarrantyID, ServiceType, PreferredDate, NewRingSize, CustomerNote)
    VALUES (@WarrantyID, @ServiceType, @PreferredDate, @NewRingSize, @CustomerNote);
    SET @ServiceID = SCOPE_IDENTITY();
END
GO

-- 3.15. Quản trị viên xác nhận lịch hoặc đề xuất đổi lịch (FR23)
CREATE OR ALTER PROCEDURE dbo.sp_ScheduleAfterSalesService
    @ServiceID        INT,
    @AdminUserID      INT,
    @AppointmentDate  DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserID = @AdminUserID AND Role = 'Admin' AND IsActive = 1)
        THROW 50024, N'Người thực hiện không có quyền quản trị.', 1;
    UPDATE dbo.AfterSalesServices
    SET AppointmentDate = @AppointmentDate,
        Status = CASE WHEN @AppointmentDate = PreferredDate THEN 'Confirmed' ELSE 'Rescheduled' END,
        HandledByUserID = @AdminUserID
    WHERE ServiceID = @ServiceID AND Status IN ('Pending', 'Confirmed', 'Rescheduled');
    IF @@ROWCOUNT = 0 THROW 50035, N'Lịch hẹn không ở trạng thái có thể xếp lịch.', 1;

    INSERT INTO dbo.AuditLogs (EntityName, EntityID, Action, OldValue, NewValue, PerformedByUserID, PerformedBy)
    VALUES ('AfterSalesServices', @ServiceID, 'Scheduled', NULL, CONVERT(NVARCHAR(30), @AppointmentDate, 120),
            @AdminUserID, N'Admin:' + CAST(@AdminUserID AS NVARCHAR(10)));
END
GO

-- 3.16. Hoàn tất dịch vụ: chỉ trừ lượt khi hoàn tất, mỗi lịch chỉ trừ một lần (FR17, FR23)
CREATE OR ALTER PROCEDURE dbo.sp_CompleteAfterSalesService
    @ServiceID    INT,
    @AdminUserID  INT,
    @ResultNote   NVARCHAR(500) = NULL,
    @PaidFee      DECIMAL(15,0) = 50000   -- phí áp dụng khi đã hết lượt miễn phí
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserID = @AdminUserID AND Role = 'Admin' AND IsActive = 1)
        THROW 50024, N'Người thực hiện không có quyền quản trị.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @WarrantyID INT, @Type VARCHAR(15), @NewSize TINYINT, @Free BIT = 1;

        SELECT @WarrantyID = WarrantyID, @Type = ServiceType, @NewSize = NewRingSize
        FROM dbo.AfterSalesServices WITH (UPDLOCK)
        WHERE ServiceID = @ServiceID AND Status IN ('Confirmed', 'Rescheduled') AND IsQuotaDeducted = 0;
        IF @WarrantyID IS NULL THROW 50036, N'Lịch hẹn chưa được xác nhận hoặc đã hoàn tất.', 1;

        IF @Type IN ('Polishing', 'Replating')
        BEGIN
            UPDATE dbo.WarrantyRecords SET PolishingCountLeft = PolishingCountLeft - 1
            WHERE WarrantyID = @WarrantyID AND PolishingCountLeft > 0;
            IF @@ROWCOUNT = 0 SET @Free = 0;           -- hết lượt -> dịch vụ tính phí
        END
        ELSE IF @Type = 'Cleaning'
            UPDATE dbo.WarrantyRecords SET CleaningCount = CleaningCount + 1 WHERE WarrantyID = @WarrantyID;
        ELSE IF @Type = 'Resizing'
            UPDATE dbo.WarrantyRecords SET ResizingCount = ResizingCount + 1 WHERE WarrantyID = @WarrantyID;

        UPDATE dbo.AfterSalesServices
        SET Status = 'Completed', CompletedAt = SYSDATETIME(), ResultNote = @ResultNote,
            HandledByUserID = @AdminUserID, IsFreeOfCharge = @Free,
            ServiceFee = CASE WHEN @Free = 1 THEN 0 ELSE @PaidFee END,
            IsQuotaDeducted = 1
        WHERE ServiceID = @ServiceID;

        INSERT INTO dbo.AuditLogs (EntityName, EntityID, Action, OldValue, NewValue, PerformedByUserID, PerformedBy)
        VALUES ('AfterSalesServices', @ServiceID, 'ServiceCompleted', @Type,
                CASE WHEN @Free = 1 THEN N'Miễn phí' ELSE N'Tính phí' END,
                @AdminUserID, N'Admin:' + CAST(@AdminUserID AS NVARCHAR(10)));
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- 3.17. Khách hủy lịch hẹn chưa hoàn tất: không làm mất lượt (FR17)
CREATE OR ALTER PROCEDURE dbo.sp_CancelAfterSalesService
    @ServiceID   INT,
    @CustomerID  INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE s SET s.Status = 'Cancelled'
    FROM dbo.AfterSalesServices s
    JOIN dbo.WarrantyRecords w ON w.WarrantyID = s.WarrantyID
    WHERE s.ServiceID = @ServiceID AND w.CustomerID = @CustomerID
      AND s.Status IN ('Pending', 'Confirmed', 'Rescheduled');
    IF @@ROWCOUNT = 0 THROW 50037, N'Không thể hủy lịch hẹn này.', 1;
END
GO

-- 3.18. Ghi nhận sản phẩm đã xem (FR8): cập nhật nếu đã có, thêm mới nếu chưa
CREATE OR ALTER PROCEDURE dbo.sp_TrackProductView
    @CustomerID  INT,
    @ProductID   INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.RecentlyViewedProducts
    SET LastViewedAt = SYSDATETIME(), ViewCount = ViewCount + 1
    WHERE CustomerID = @CustomerID AND ProductID = @ProductID;
    IF @@ROWCOUNT = 0
        INSERT INTO dbo.RecentlyViewedProducts (CustomerID, ProductID) VALUES (@CustomerID, @ProductID);
END
GO

/* =====================================================================
   PHẦN 4. VIEW
   ===================================================================== */

-- 4.1. Danh sách sản phẩm hiển thị cho khách (FR4, FR5): giá hiện hành, tồn kho, ảnh đại diện
CREATE OR ALTER VIEW dbo.vw_ProductCatalog
AS
SELECT p.ProductID, p.SKU, p.ProductName, p.ShortName, p.Slug,
       c.CategoryID, c.CategoryName, c.CategoryGroup, c.RequiresRingSize,
       col.CollectionID, col.CollectionName,
       p.Material, p.WeightGram, p.PricingMethod,
       dbo.fn_GetCurrentPrice(p.ProductID) AS CurrentPrice,
       p.OriginalPrice,
       ISNULL(st.TotalStock, 0) AS TotalStock,
       CAST(CASE WHEN ISNULL(st.TotalStock, 0) > 0 THEN 1 ELSE 0 END AS BIT) AS IsInStock,
       img.ImageUrl AS ThumbnailUrl,
       p.Status
FROM dbo.Products p
JOIN dbo.Categories c ON c.CategoryID = p.CategoryID
LEFT JOIN dbo.ProductCollections pc ON pc.ProductID = p.ProductID AND pc.IsPrimary = 1
LEFT JOIN dbo.Collections col ON col.CollectionID = pc.CollectionID
OUTER APPLY (SELECT SUM(v.StockQuantity) AS TotalStock
             FROM dbo.ProductVariants v WHERE v.ProductID = p.ProductID AND v.IsActive = 1) st
OUTER APPLY (SELECT TOP (1) i.ImageUrl FROM dbo.ProductImages i
             WHERE i.ProductID = p.ProductID ORDER BY i.IsThumbnail DESC, i.SortOrder) img;
GO

-- 4.2. Đơn hàng được ghi nhận doanh thu: đã nhận + thanh toán thành công; doanh thu = sau giảm giá, không gồm phí giao (FR24)
CREATE OR ALTER VIEW dbo.vw_RevenueOrders
AS
SELECT o.OrderID, o.OrderCode, o.CustomerID, o.DeliveredAt,
       o.Subtotal, o.DiscountAmount, o.RetentionDiscountAmount, o.ShippingFee,
       CAST(o.Subtotal - o.DiscountAmount - o.RetentionDiscountAmount AS DECIMAL(15,0)) AS NetRevenue
FROM dbo.Orders o
WHERE o.OrderStatus = 'Delivered'
  AND EXISTS (SELECT 1 FROM dbo.Payments p WHERE p.OrderID = o.OrderID AND p.Status = 'Success');
GO

-- 4.3. Doanh thu và xu hướng theo tháng (FR24)
CREATE OR ALTER VIEW dbo.vw_RevenueByMonth
AS
SELECT YEAR(DeliveredAt) AS [Year], MONTH(DeliveredAt) AS [Month],
       COUNT(*) AS OrderCount,
       SUM(NetRevenue) AS NetRevenue
FROM dbo.vw_RevenueOrders
GROUP BY YEAR(DeliveredAt), MONTH(DeliveredAt);
GO

-- 4.4. Doanh thu theo nhóm chất liệu vàng (FR24): phân bổ giảm giá của đơn theo tỷ trọng từng dòng hàng
CREATE OR ALTER VIEW dbo.vw_RevenueByMaterial
AS
SELECT oi.MaterialSnap AS Material,
       SUM(oi.Quantity) AS UnitsSold,
       CAST(SUM(oi.LineTotal * r.NetRevenue / NULLIF(r.Subtotal, 0)) AS DECIMAL(15,0)) AS NetRevenue
FROM dbo.vw_RevenueOrders r
JOIN dbo.OrderItems oi ON oi.OrderID = r.OrderID
GROUP BY oi.MaterialSnap;
GO

-- 4.5. Thống kê hiệu quả giữ chân đơn (FR26): mỗi đơn chỉ tính một lần trong mỗi chỉ số
CREATE OR ALTER VIEW dbo.vw_RetentionStats
AS
SELECT COUNT(DISTINCT r.OrderID) AS OrdersWithCancelRequest,
       COUNT(DISTINCT CASE WHEN r.OfferShown = 1 THEN r.OrderID END) AS OrdersOfferShown,
       COUNT(DISTINCT CASE WHEN r.Decision = 'AcceptedOffer' THEN r.OrderID END) AS OrdersAcceptedOffer,
       COUNT(DISTINCT CASE WHEN r.Decision = 'AcceptedOffer' AND o.OrderStatus = 'Delivered' THEN r.OrderID END) AS OrdersRetainedAndDelivered,
       COUNT(DISTINCT CASE WHEN o.OrderStatus = 'Cancelled' THEN r.OrderID END) AS OrdersCancelled
FROM dbo.OrderCancellationRequests r
JOIN dbo.Orders o ON o.OrderID = r.OrderID;
GO

-- 4.6. Tỷ lệ phản hồi tích cực/tiêu cực (FR25)
CREATE OR ALTER VIEW dbo.vw_SentimentSummary
AS
SELECT ISNULL(SentimentLabel, 'Unlabeled') AS SentimentLabel,
       IsSentimentSimulated,
       COUNT(*) AS FeedbackCount,
       CAST(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0) AS DECIMAL(5,2)) AS Percentage,
       CAST(AVG(CAST(RatingStar AS DECIMAL(3,2))) AS DECIMAL(3,2)) AS AvgRating
FROM dbo.CustomerFeedbacks
GROUP BY ISNULL(SentimentLabel, 'Unlabeled'), IsSentimentSimulated;
GO

-- 4.7. Các yếu tố khách hàng đề cập (FR25)
CREATE OR ALTER VIEW dbo.vw_FeedbackAspectSummary
AS
SELECT AspectName, Polarity, COUNT(*) AS MentionCount
FROM dbo.FeedbackAspects
GROUP BY AspectName, Polarity;
GO

-- 4.8. Thẻ bảo hành và quyền lợi còn lại của khách (FR15, FR17)
CREATE OR ALTER VIEW dbo.vw_CustomerWarranties
AS
SELECT w.WarrantyID, w.WarrantyCode, w.CustomerID, w.IssueDate, w.Status,
       o.OrderCode, oi.ProductNameSnap AS ProductName, oi.SKUSnap AS SKU, oi.RingSize,
       wp.PolicyName, wp.PolishingQuota, w.PolishingCountLeft, w.CleaningCount, w.ResizingCount,
       (SELECT COUNT(*) FROM dbo.AfterSalesServices s WHERE s.WarrantyID = w.WarrantyID AND s.Status = 'Completed') AS CompletedServices
FROM dbo.WarrantyRecords w
JOIN dbo.Orders o ON o.OrderID = w.OrderID
JOIN dbo.OrderItems oi ON oi.OrderItemID = w.OrderItemID
JOIN dbo.WarrantyPolicies wp ON wp.WarrantyPolicyID = w.WarrantyPolicyID;
GO

-- 4.9. Lịch sử đơn hàng của khách kèm trạng thái thanh toán mới nhất (FR12)
CREATE OR ALTER VIEW dbo.vw_CustomerOrderHistory
AS
SELECT o.OrderID, o.OrderCode, o.CustomerID, o.CreatedAt, o.OrderStatus,
       o.Subtotal, o.DiscountAmount, o.RetentionDiscountAmount, o.ShippingFee, o.TotalAmount,
       pay.PaymentMethod, pay.Status AS PaymentStatus
FROM dbo.Orders o
OUTER APPLY (SELECT TOP (1) p.PaymentMethod, p.Status FROM dbo.Payments p
             WHERE p.OrderID = o.OrderID ORDER BY p.PaymentID DESC) pay;
GO

/* =====================================================================
   PHẦN 5. DỮ LIỆU DANH MỤC, BỘ SƯU TẬP VÀ SẢN PHẨM
   Nguồn: file products_da_phan_loai.xlsx (443 sản phẩm, 10 danh mục,
   25 bộ sưu tập) do nhóm thu thập từ website thương hiệu gốc.
   - Giá, trọng lượng, chất liệu, thông tin đá, hình ảnh: lấy từ dữ liệu crawl.
   - Số lượng tồn kho: dữ liệu crawl không có -> gán số lượng minh họa.
   - Bảng giá vàng: giá minh họa, quản trị viên cập nhật theo thị trường.
   ===================================================================== */
USE VinoraJewelry;
GO
SET NOCOUNT ON;
GO

-- 5.1. Bảng quy đổi size nhẫn (chu vi = 40 + size, mm; size US quy đổi tham khảo)
INSERT INTO dbo.RingSizeChart (SizeVN, CircumferenceMm, InnerDiameterMm, SizeUS) VALUES
(5, 45.0, 14.3, 3.5),
(6, 46.0, 14.6, 3.5),
(7, 47.0, 15.0, 4.0),
(8, 48.0, 15.3, 4.5),
(9, 49.0, 15.6, 5.0),
(10, 50.0, 15.9, 5.5),
(11, 51.0, 16.2, 5.5),
(12, 52.0, 16.6, 6.0),
(13, 53.0, 16.9, 6.5),
(14, 54.0, 17.2, 7.0),
(15, 55.0, 17.5, 7.5),
(16, 56.0, 17.8, 7.5),
(17, 57.0, 18.1, 8.0),
(18, 58.0, 18.5, 8.5),
(19, 59.0, 18.8, 9.0),
(20, 60.0, 19.1, 9.0),
(21, 61.0, 19.4, 9.5),
(22, 62.0, 19.7, 10.0),
(23, 63.0, 20.1, 10.5),
(24, 64.0, 20.4, 11.0),
(25, 65.0, 20.7, 11.0);
GO

-- 5.2. Chính sách bảo hành (cấu hình số lượt tập trung – NFR7)
SET IDENTITY_INSERT dbo.WarrantyPolicies ON;
INSERT INTO dbo.WarrantyPolicies (WarrantyPolicyID, PolicyName, PolicyContent, CleaningQuota, PolishingQuota, ResizingQuota, IsLifetime) VALUES
(1, N'Bảo hành trọn đời Vinora', N'CHÍNH SÁCH BẢO HÀNH TRỌN ĐỜI VINORA JEWELRY
1. Dịch vụ miễn phí: làm sạch sản phẩm trọn đời; đánh bóng và xi mới tối đa 05 lần; chỉnh size nhẫn và khắc tên trọn đời; gắn lại đá CZ trọn đời; miễn phí công gắn kim cương, đá màu, ngọc trai (chưa bao gồm giá viên); hàn dây, sửa khóa 01 lần (không bao gồm thay mới).
2. Dịch vụ tính phí: nắn lại nhẫn, cắt/hàn dây, thay đai hoặc thêm chi tiết khi vượt phạm vi miễn phí; phí vàng bổ sung (nếu có) tính theo giá vàng thời điểm.
3. Điều kiện: khách hàng đặt lịch bằng mã thẻ bảo hành điện tử; thẻ được kích hoạt khi đơn hàng được xác nhận đã nhận; không áp dụng cho sản phẩm hư hỏng do tác động ngoại lực mạnh, cháy nổ hoặc đã sửa chữa tại nơi khác.', NULL, 5, NULL, 1);
SET IDENTITY_INSERT dbo.WarrantyPolicies OFF;
GO

-- 5.3. Danh mục sản phẩm (10 danh mục)
SET IDENTITY_INSERT dbo.Categories ON;
INSERT INTO dbo.Categories (CategoryID, CategoryName, CategoryGroup, Slug, Description, RequiresRingSize, DisplayOrder) VALUES
(1, N'Nhẫn cầu hôn', N'Nhẫn', 'nhan-cau-hon', N'Nhẫn đính hôn gắn viên chủ kim cương tự nhiên, kim cương lab-grown, moissanite hoặc đá CZ', 1, 1),
(2, N'Nhẫn cưới', N'Nhẫn', 'nhan-cuoi', N'Nhẫn cưới, nhẫn đôi dành cho cặp đôi', 1, 2),
(3, N'Nhẫn thời trang', N'Nhẫn', 'nhan-thoi-trang', N'Nhẫn nữ đeo hằng ngày', 1, 3),
(4, N'Bông tai', N'Bông tai', 'bong-tai', N'Bông tai, khuyên tai các loại', 0, 4),
(5, N'Dây chuyền', N'Dây chuyền', 'day-chuyen', N'Dây chuyền, vòng cổ (có thể kèm mặt)', 0, 5),
(6, N'Mặt dây chuyền', N'Mặt dây chuyền', 'mat-day-chuyen', N'Mặt dây bán rời, phối với dây chuyền', 0, 6),
(7, N'Lắc tay', N'Lắc tay', 'lac-tay', N'Lắc tay, vòng tay', 0, 7),
(8, N'Charm', N'Charm', 'charm', N'Charm xỏ vòng/lắc, bán lẻ hoặc theo bộ phối sẵn', 0, 8),
(9, N'Bộ trang sức', N'Bộ trang sức', 'bo-trang-suc', N'Bộ trang sức và combo nhiều món', 0, 9),
(10, N'Vàng lưu niệm', N'Vàng lưu niệm', 'vang-luu-niem', N'Vàng 24K lưu niệm, phonesticker, quà tài lộc', 0, 10);
SET IDENTITY_INSERT dbo.Categories OFF;
GO

-- 5.4. Bộ sưu tập (25 bộ sưu tập)
SET IDENTITY_INSERT dbo.Collections ON;
INSERT INTO dbo.Collections (CollectionID, CollectionName, Slug, Description, BannerImage, DisplayOrder) VALUES
(1, N'Evermore', 'evermore', N'Dòng sản phẩm: Nhẫn cầu hôn, Nhẫn cưới. Chất liệu: 14K, 18K, 10K.', '/static/images/collections/evermore.jpg', 1),
(2, N'Starlight', 'starlight', N'Dòng sản phẩm: Nhẫn thời trang, Mặt dây chuyền, Bông tai. Chất liệu: 14K, 10K, BAC925.', '/static/images/collections/starlight.jpg', 2),
(3, N'Promis', 'promis', N'Dòng sản phẩm: Nhẫn cầu hôn, Nhẫn cưới. Chất liệu: 14K, 10K.', '/static/images/collections/promis.jpg', 3),
(4, N'Gloria', 'gloria', N'Dòng sản phẩm: Bông tai, Dây chuyền, Mặt dây chuyền. Chất liệu: 14K, 10K, BAC925.', '/static/images/collections/gloria.jpg', 4),
(5, N'Beyond', 'beyond', N'Dòng sản phẩm: Nhẫn cầu hôn. Chất liệu: 14K.', '/static/images/collections/beyond.jpg', 5),
(6, N'Thần Tài Đại Cát', 'than-tai-dai-cat', N'Dòng sản phẩm: Charm. Chất liệu: 14K.', '/static/images/collections/than-tai-dai-cat.jpg', 6),
(7, N'Bunnie', 'bunnie', N'Dòng sản phẩm: Bông tai, Dây chuyền. Chất liệu: BAC925.', '/static/images/collections/bunnie.jpg', 7),
(8, N'Perlina', 'perlina', N'Dòng sản phẩm: Dây chuyền, Bông tai, Bộ trang sức. Chất liệu: 14K, 10K.', '/static/images/collections/perlina.jpg', 8),
(9, N'The Empress', 'the-empress', N'Dòng sản phẩm: Mặt dây chuyền, Bông tai. Chất liệu: 24K.', '/static/images/collections/the-empress.jpg', 9),
(10, N'Eternal', 'eternal', N'Dòng sản phẩm: Nhẫn cầu hôn, Nhẫn cưới. Chất liệu: 14K, 18K.', '/static/images/collections/eternal.jpg', 10),
(11, N'Rabbit Tales', 'rabbit-tales', N'Dòng sản phẩm: Dây chuyền, Bông tai. Chất liệu: 10K.', '/static/images/collections/rabbit-tales.jpg', 11),
(12, N'Lucky U', 'lucky-u', N'Dòng sản phẩm: Bông tai, Dây chuyền, Mặt dây chuyền. Chất liệu: 10K, 14K.', '/static/images/collections/lucky-u.jpg', 12),
(13, N'12 Con Giáp', '12-con-giap', N'Dòng sản phẩm: Charm. Chất liệu: 24K.', '/static/images/collections/12-con-giap.jpg', 13),
(14, N'Lasting Moment', 'lasting-moment', N'Dòng sản phẩm: Charm. Chất liệu: 14K.', '/static/images/collections/lasting-moment.jpg', 14),
(15, N'Moonlight', 'moonlight', N'Dòng sản phẩm: Mặt dây chuyền, Dây chuyền, Bông tai. Chất liệu: 10K, 14K.', '/static/images/collections/moonlight.jpg', 15),
(16, N'Haven Crystal', 'haven-crystal', N'Dòng sản phẩm: Mặt dây chuyền, Dây chuyền. Chất liệu: 10K, 14K.', '/static/images/collections/haven-crystal.jpg', 16),
(17, N'Phonesticker', 'phonesticker', N'Dòng sản phẩm: Vàng lưu niệm. Chất liệu: 24K, 10K.', '/static/images/collections/phonesticker.jpg', 17),
(18, N'Lumiere', 'lumiere', N'Dòng sản phẩm: Mặt dây chuyền, Dây chuyền. Chất liệu: 14K.', '/static/images/collections/lumiere.jpg', 18),
(19, N'Vàng Lưu Niệm Tài Lộc', 'vang-luu-niem-tai-loc', N'Dòng sản phẩm: Vàng lưu niệm. Chất liệu: 24K.', '/static/images/collections/vang-luu-niem-tai-loc.jpg', 19),
(20, N'Cát Trường', 'cat-truong', N'Dòng sản phẩm: Mặt dây chuyền. Chất liệu: 14K.', '/static/images/collections/cat-truong.jpg', 20),
(21, N'Kim Tiền', 'kim-tien', N'Dòng sản phẩm: Nhẫn thời trang. Chất liệu: 10K.', '/static/images/collections/kim-tien.jpg', 21),
(22, N'Lucena', 'lucena', N'Dòng sản phẩm: Nhẫn thời trang, Mặt dây chuyền. Chất liệu: 14K.', '/static/images/collections/lucena.jpg', 22),
(23, N'Vàng 22K', 'vang-22k', N'Dòng sản phẩm: Mặt dây chuyền. Chất liệu: 22K.', '/static/images/collections/vang-22k.jpg', 23),
(24, N'Soobin''s Queen', 'soobin-s-queen', N'Dòng sản phẩm: Dây chuyền. Chất liệu: 10K.', '/static/images/collections/soobin-s-queen.jpg', 24),
(25, N'Together', 'together', N'Dòng sản phẩm: Nhẫn cưới. Chất liệu: BAC925.', '/static/images/collections/together.jpg', 25);
SET IDENTITY_INSERT dbo.Collections OFF;
GO

-- 5.5. Bảng giá vàng (GIÁ MINH HỌA – cập nhật theo thị trường khi vận hành)
INSERT INTO dbo.GoldPrices (Material, BuyPricePerChi, SellPricePerChi, EffectiveFrom) VALUES
('24K', 14700000, 15000000, '2026-10-01T08:00:00'),
('22K', 13470000, 13740000, '2026-10-01T08:00:00'),
('18K', 11030000, 11250000, '2026-10-01T08:00:00'),
('14K', 8570000, 8750000, '2026-10-01T08:00:00'),
('10K', 6120000, 6240000, '2026-10-01T08:00:00');
GO

-- 5.6. Sản phẩm (443 sản phẩm). Sản phẩm 'GoldRate': giá = trọng lượng (chỉ) x giá vàng + tiền công
SET IDENTITY_INSERT dbo.Products ON;
INSERT INTO dbo.Products (ProductID, SKU, ProductName, ShortName, Slug, CategoryID, WarrantyPolicyID, Material, WeightGram, PricingMethod, LaborPrice, Price, OriginalPrice, Description, IsEngravable, Status) VALUES
(1, 'NDINO131LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO131LDIA', 'nhan-ndino-131ldia', 1, 1, '14K', 1.620, 'Fixed', 2150000, 25448000, NULL, NULL, 1, 'Active'),
(2, 'NDINO15LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO15LDIA', 'nhan-ndino-15ldia', 1, 1, '14K', 1.900, 'Fixed', 2150000, 26504000, NULL, NULL, 1, 'Active'),
(3, 'NDINO171LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO171LDIA', 'nhan-ndino-171ldia', 1, 1, '18K', 2.640, 'Fixed', 2150000, 20567000, NULL, NULL, 1, 'Active'),
(4, 'NDINO173LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO173LDIA', 'nhan-ndino-173ldia', 1, 1, '18K', 2.030, 'Fixed', 2150000, 18735000, NULL, NULL, 1, 'Active'),
(5, 'NDINO175LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO175LDIA', 'nhan-ndino-175ldia', 1, 1, '18K', 3.320, 'Fixed', 2150000, 38496000, NULL, NULL, 1, 'Active'),
(6, 'NDINO180LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO180LDIA', 'nhan-ndino-180ldia', 1, 1, '18K', 1.390, 'Fixed', NULL, 15466000, NULL, N'Dáng nhẫn Solitaire tối giản, tôn vinh vẻ đẹp rực rỡ của viên chủ kim cương lab-grown. Đai nhẫn thanh mảnh, tỉ lệ hoàn hảo với viên chủ, tạo nên tổng thể thiết kế thanh lịch, tinh tế. Thiết kế lấy cảm hứng từ biểu tượng vô cực, mang ý nghĩa ước mong về một tình yêu vĩnh cửu và hạnh phúc trọn vẹn.', 1, 'Active'),
(7, 'NDINO19LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO19LDIA', 'nhan-ndino-19ldia', 1, 1, '14K', 1.740, 'Fixed', 2150000, 24974000, NULL, N'Dáng nhẫn tinh tế, tối giản, mang vẻ đẹp vượt thời gian. Ổ nhẫn sáu chấu - với mỗi chấu tượng trưng cho một yếu tố quan trọng tạo nên tình yêu đẹp: tin tưởng, tôn trọng, cảm thông, chung thủy, cam kết và cân bằng. Ở Nhìn từ trên xuống, đai nhẫn thon dần và tập trung về phía kim cương chủ rực rỡ, mang ý nghĩa về sự hòa quyện của hai tâm hồn.', 1, 'Active'),
(8, 'NDINO20LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO20LDIA', 'nhan-ndino-20ldia', 1, 1, '14K', 1.240, 'Fixed', 2150000, 22052000, NULL, N'Ở góc nhìn ngang, ổ nhẫn rực rỡ như những cánh hoa tulip xếp chồng, biểu trưng cho tình yêu mãnh liệt, chân thành và lãng mạn. Đai nhẫn mảnh mai được đính kim cương chìm lấp lánh, kết hợp với ổ nhẫn dáng Halo tạo nên hiệu ứng tăng size viên chủ tối đa.', 1, 'Active'),
(9, 'NDINO23LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO23LDIA', 'nhan-ndino-23ldia', 1, 1, '14K', 1.620, 'Fixed', 2150000, 27324000, NULL, N'Ổ nhẫn cách điệu hình ảnh nụ hồng chớm nở, biểu tượng của tình yêu mãnh liệt, mang ý nghĩa về khởi đầu của hành trình mới tràn ngập hạnh phúc. 
Nhìn ở góc ngang, chi tiết cách điệu đài hoa hồng tôn vinh vẻ đẹp của viên kim cương chủ. Đai nhẫn đính dải kim cương tấm, cao dần về phía ổ nhẫn, như vòng tay muốn ôm ấp chở che, thể hiện sự bảo vệ và yêu thương suốt đời bạn muốn dành cho cô ấy.', 1, 'Active'),
(10, 'NDINO248LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO248LDIA', 'nhan-ndino-248ldia', 1, 1, '14K', 2.750, 'Fixed', 1900000, 32937000, NULL, N'Lấy cảm hứng từ đóa hoa hồng nở rộ, biểu tượng của tình yêu mãnh liệt và luôn cháy bỏng. Kim cương tấm đính trên ổ nhẫn kết hợp cùng viên kim cương chủ tạo nên một tổng thể rực rỡ, thu hút mọi ánh nhìn, lung linh ở mọi góc độ. Từng đường nét uốn lượn tinh xảo như vòng tay ôm ấp, thể hiện sự ấm áp, hòa quyện của hai trái tim.', 1, 'Active'),
(11, 'NDINO255LDIA-1', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO255LDIA-1', 'nhan-cau-hon-ndino255ldia-1', 1, 1, '14K', 1.840, 'Fixed', 2150000, 18614000, NULL, N'Dáng nhẫn Solitaire với viên kim cương lab-grown duy nhất, kiêu hãnh tỏa sáng trên đai nhẫn trơn tối giản, thay lời khẳng định rằng cô ấy giữ vị trí độc tôn trong trái tim bạn. 
Khi nhìn từ trên xuống, đai nhẫn được thắt lại ở ổ nhẫn, tựa như biểu tượng vô cực, mang ý nghĩa sâu sắc về tình yêu vĩnh cửu của hai bạn. Đây là thiết kế mang vẻ đẹp vượt thời gian.', 1, 'Active'),
(12, 'NDINO267LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO267LDIA', 'nhan-ndino-267ldia', 1, 1, '14K', 2.100, 'Fixed', NULL, 30334000, NULL, N'Đai nhẫn với bốn nhịp uốn lượn tựa như dòng chảy của tình yêu: gặp gỡ, tìm hiểu, yêu đương rồi kết hôn. Những viên kim cương lấp lánh được đính trên đai nhẫn làm tăng vẻ nổi bật, mỗi viên kim cương tựa như một kỷ niệm đẹp của cặp đôi. 
Ổ nhẫn 6 chấu, mỗi chấu đại diện cho một phẩm chất tốt đẹp trong tình yêu: chân thành, tin tưởng, chia sẻ, quan tâm và chung thủy.', 1, 'Active'),
(13, 'NDINO26LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO26LDIA', 'nhan-ndino-26ldia', 1, 1, '14K', 1.510, 'Fixed', 2150000, 16341000, NULL, N'Dáng nhẫn Solitaire với viên kim cương lab-grown tỏa sáng trên đai nhẫn trơn, đại diện cho tình yêu duy nhất. Đai nhẫn uốn lượn mềm mại, tinh xảo, khi nhìn từ trên xuống tựa như biểu tượng vô cực độc đáo, tượng trưng cho gắn kết bền chặt mãi mãi giữa hai bạn.', 1, 'Active'),
(14, 'NDINO271LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO271LDIA', 'nhan-ndino-271ldia', 1, 1, '14K', 2.340, 'Fixed', NULL, 31617000, NULL, N'Ổ nhẫn vàng hồng mang đến vẻ hiện đại, ngọt ngào, cách điệu nụ hoa hồng chớm nở, biểu tượng cho khởi đầu mới đầy hứa hẹn trong tình yêu. 
Khi nhìn từ trên xuống, đai nhẫn trơn giúp thu hút ánh nhìn vào viên kim cương lab-grown lấp lánh. Nhìn ở góc ngang, hai hàng kim cương chìm chạy dần về ổ nhẫn giúp tối đa hoá vẻ lộng lẫy.
Chiếc nhẫn mang ngôn ngữ của loài hoa hồng đỏ, là minh chứng cho tình yêu vĩnh cửu, thể hiện sự trân trọng bạn dành cho nửa kia của mình.', 1, 'Active'),
(15, 'NDINO274LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO274LDIA', 'nhan-ndino-274ldia', 1, 1, '14K', 1.900, 'Fixed', NULL, 25094000, NULL, N'Đai nhẫn trơn kết hợp hoàn hảo cùng ổ nhẫn vàng hồng, thu hút ánh nhìn vào viên chủ kim cương lấp lánh. Ổ nhẫn được cách điệu tinh tế cánh hoa mẫu đơn, biểu trưng cho tình yêu mãnh liệt và đầy đam mê. Thiết kế mở ở phần dưới ổ nhẫn giúp ánh sáng có thể chiếu vào, tăng khả năng phản sáng và độ lấp lánh cho viên kim cương, mang lại vẻ đẹp thu hút ánh nhìn.', 1, 'Active'),
(16, 'NDINO276LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO276LDIA', 'nhan-ndino-276ldia', 1, 1, '14K', 1.900, 'Fixed', 2150000, 19895000, NULL, N'Dáng nhẫn Solitaire với viên kim cương chủ duy nhất, như lời khẳng định về sự quý giá và tình yêu độc nhất của bạn dành cho cô ấy. Đai nhẫn trơn cùng tỉ lệ cân đối hoàn hảo với viên kim cương chủ, đem đến sự hài hòa cho thiết kế. Nhìn ở góc ngang, 6 chấu nhẫn có độ nghiêng đồng đều, tạo cảm giác đan vào nhau, tựa như các cánh hoa xếp lớp. Mỗi chấu trên ổ nhẫn đều tượng trưng cho một điều tốt đẹp trong tình yêu: chân thành, tin tưởng, chia sẻ, quan tâm và chung thủy.', 1, 'Active'),
(17, 'NDINO278LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO278LDIA', 'nhan-ndino-278ldia', 1, 1, '14K', 1.610, 'Fixed', NULL, 16434000, NULL, N'Dáng nhẫn Solitaire tối giản nhưng không bao giờ lỗi thời, biểu trưng cho tình yêu duy nhất và trọn vẹn. Ổ đá vàng hồng, tạo nên điểm nhấn trẻ trung và hiện đại. Đai nhẫn thắt lại ở vị trí viên chủ, mang đến vẻ đẹp mềm mại và thu hút sự chú ý ở viên chủ kim cương lab-grown lấp lánh.', 1, 'Active'),
(18, 'NDINO281LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO281LDIA', 'nhan-ndino-281ldia', 1, 1, '14K', 2.310, 'Fixed', 2150000, 26840000, NULL, NULL, 1, 'Active'),
(19, 'NDINO283LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO283LDIA', 'nhan-ndino-283ldia', 1, 1, '14K', 1.720, 'Fixed', 1900000, 29673000, NULL, NULL, 1, 'Active'),
(20, 'NDINO291LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO291LDIA', 'nhan-ndino-291ldia', 1, 1, '14K', 1.790, 'Fixed', 2150000, 25851000, NULL, N'Ổ nhẫn với thiết kế 2 tầng đầy sống động mềm mại, hai đường uốn lượn đan nhau như cánh hoa đang tôn vinh nhuỵ hoa rực rỡ – biểu tượng cho tình yêu đầy tự hào và đáng trân trọng. Đai nhẫn mảnh, được đính dọc những viên kim cương tấm tinh xảo, tạo hiệu ứng lấp lánh ấn tượng từ góc trên xuống, càng làm nổi bật vẻ đẹp thanh thoát và sang trọng của chiếc nhẫn.', 1, 'Active'),
(21, 'NDINO292LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO292LDIA', 'nhan-ndino-292ldia', 1, 1, '14K', 1.840, 'Fixed', 2150000, 25495000, NULL, N'Thiết kế ổ nhẫn cao, tôn vinh viên chủ kim cương Lab-grown lấp lánh, biểu tượng cho tình yêu được nâng niu và tỏa sáng. Thiết kế lấy cảm hứng từ lời hẹn ước thiêng liêng khi cùng nhau bước vào lễ đường, đánh dấu khởi đầu cho một hành trình hạnh phúc trọn đời. Dải kim cương tấm với nhiều kích thước khác nhau đính trên đai nhẫn làm tăng thêm vẻ lấp lánh.', 1, 'Active'),
(22, 'NDINO295LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO295LDIA', 'nhan-ndino-295ldia', 1, 1, '14K', 1.280, 'Fixed', NULL, 19469000, NULL, N'Đai nhẫn cách điệu từ những điểm thắt trên vai áo choàng nữ hoàng, mang lại cảm giác kiêu kỳ, kết hợp cùng kim cương tấm được đính ở cả 2 mặt tạo nên hiệu ứng lấp lánh ở đa góc độ. Ổ nhẫn được tôn cao vừa phải làm nổi bật viên chủ kim cương Lab-grown ở trung tâm, mang đến vẻ đẹp thanh thoát. Thiết kế này mang ý nghĩa cô gái ấy là người phụ nữ quý giá nhất trong trái tim bạn.', 1, 'Active'),
(23, 'NDINO300LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO300LDIA', 'nhan-ndino-300ldia', 1, 1, '14K', 1.530, 'Fixed', 2150000, 15309000, NULL, N'Bao quanh viên chủ kim cương Lab-grown một vòng kim cương tấm, tựa bông hoa hướng dương rực rỡ, tượng trưng cho tình yêu luôn hướng về nhau và tỏa sáng mãi theo thời gian. Dải kim cương tấm kết hợp cùng đường uốn lượn bên thân đai giúp ánh sáng phản chiếu từ nhiều góc độ, khiến chiếc nhẫn tỏa sáng rực rỡ ở mọi hướng.', 1, 'Active'),
(24, 'NDINO301LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO301LDIA', 'nhan-ndino-301ldia', 1, 1, '14K', 1.380, 'Fixed', 2150000, 15214000, NULL, N'Lấy cảm hứng từ truyền thuyết đôi tình nhân nếu cùng ngắm nhìn tuyết đầu mùa sẽ mãi hạnh phúc bên nhau, ổ nhẫn là bông hoa tuyết kim cương lấp lánh. Việc sử dụng các viên kim cương với kích cỡ khác nhau cùng tạo hình 3 tầng cánh hoa, giúp thiết kế này sống động và lung linh. Đai nhẫn mảnh mai đính kim cương tấm càng làm tăng thêm vẻ quyến rũ cho thiết kế.', 1, 'Active'),
(25, 'NDINO302LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO302LDIA', 'nhan-ndino-302ldia', 1, 1, '14K', 1.420, 'Fixed', 2150000, 14859000, NULL, N'Tạo hình ổ nhẫn lấy cảm hứng từ bông hoa tuyết đầu mùa. Viên kim cương trung tâm được bao quanh bởi vòng kim cương tấm tạo cảm giác ổ nhẫn lớn, lộng lẫy. Thiết kế mang ý nghĩa về tình yêu trong sáng và chân thành.', 1, 'Active'),
(26, 'NDINO305LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO305LDIA', 'nhan-cau-hon-ndino305ldia', 1, 1, '14K', 2.470, 'Fixed', NULL, 30816000, NULL, N'Ổ nhẫn tạo hình 6 cánh hoa tulip ôm trọm và nâng cao viên chủ, vừa thu hút điểm nhìn vào viên kim cương lab-grown - vừa mang ý nghĩa tôn vinh người con gái trong tình yêu. Khi nhìn ở góc ngang, đai nhẫn như đài hoa mềm mại, đính kim cương tấm lấp lánh, tăng thêm vẻ quyến rũ lộng lẫy cho sản phẩm', 1, 'Active'),
(27, 'NDINO306LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO306LDIA', 'nhan-cau-hon-ndino306ldia', 1, 1, '18K', 3.900, 'Fixed', NULL, 57851000, NULL, NULL, 1, 'Active'),
(28, 'NDINO307LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO307LDIA', 'nhan-cau-hon-ndino307ldia', 1, 1, '18K', 2.960, 'Fixed', NULL, 71569000, NULL, NULL, 1, 'Active'),
(29, 'NDINO308LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO308LDIA', 'nhan-cau-hon-ndino308ldia', 1, 1, '18K', 3.570, 'Fixed', NULL, 62913000, NULL, N'Dáng nhẫn Halo với viên chủ kim cương Lab-grown kết hợp với vòng kim cương bao quanh làm nổi bật kích thước và độ lấp lánh cho sản phẩm. Ổ nhẫn lấy cảm hứng từ hoa mặt trời, biểu tượng của sự chung thủy, tấm lòng luôn hướng về nhau trong tình yêu.
Dải kim cương tấm được gắn trên ba đai nhẫn tạo thêm điểm nhấn, tăng khả năng phản chiếu ánh sáng từ nhiều góc độ.', 1, 'Active'),
(30, 'NDINO309LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO309LDIA', 'nhan-cau-hon-ndino309ldia', 1, 1, '18K', 3.100, 'Fixed', NULL, 69392000, NULL, NULL, 1, 'Active'),
(31, 'NDINO310LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO310LDIA', 'nhan-cau-hon-ndino310ldia', 1, 1, '18K', 3.180, 'Fixed', NULL, 53537000, NULL, NULL, 1, 'Active'),
(32, 'NDINO311LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO311LDIA', 'nhan-cau-hon-ndino311ldia', 1, 1, '18K', 3.340, 'Fixed', NULL, 59137000, NULL, NULL, 1, 'Active'),
(33, 'NDINO312LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO312LDIA', 'nhan-cau-hon-ndino312ldia', 1, 1, '18K', 3.390, 'Fixed', NULL, 59320000, NULL, NULL, 1, 'Active'),
(34, 'NDINO313LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO313LDIA', 'nhan-cau-hon-ndino313ldia', 1, 1, '18K', 3.410, 'Fixed', NULL, 58330000, NULL, NULL, 1, 'Active'),
(35, 'NDINO314LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO314LDIA', 'nhan-cau-hon-ndino314ldia', 1, 1, '18K', 3.010, 'Fixed', NULL, 54690000, NULL, NULL, 1, 'Active'),
(36, 'NDINO315LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO315LDIA', 'nhan-cau-hon-ndino315ldia', 1, 1, '18K', 3.900, 'Fixed', 1840000, 62004000, NULL, N'Ổ nhẫn được nâng cao với thiết kế 3 tầng đá, tạo nên vẻ đẹp kiêu kỳ và lộng lẫy. Thiết kế dáng nhẫn Halo nổi bật với vòng kim cương bao quanh viên chủ lớn, tạo hiệu ứng tăng kích cỡ cho viên chủ, giúp chiếc nhẫn toả sáng lấp lánh tối đa. Nhìn từ trên xuống, thiết kế như bông hoa mặt trời, với ý nghĩa về tình yêu luôn toả sáng, rực rỡ.', 1, 'Active'),
(37, 'NDINO316LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO316LDIA', 'nhan-cau-hon-ndino316ldia', 1, 1, '18K', 3.950, 'Fixed', NULL, 54977000, NULL, NULL, 1, 'Active'),
(38, 'NDINO318LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO318LDIA', 'nhan-cau-hon-ndino318ldia', 1, 1, '18K', 3.990, 'Fixed', NULL, 80258000, NULL, NULL, 1, 'Active'),
(39, 'NDINO320LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO320LDIA', 'nhan-cau-hon-ndino320ldia', 1, 1, '18K', 3.530, 'Fixed', NULL, 67771000, NULL, NULL, 1, 'Active'),
(40, 'NDINO321LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO321LDIA', 'nhan-cau-hon-ndino321ldia', 1, 1, '18K', 3.330, 'Fixed', NULL, 61843000, NULL, NULL, 1, 'Active'),
(41, 'NDINO322LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO322LDIA', 'nhan-cau-hon-ndino322ldia', 1, 1, '18K', 3.860, 'Fixed', NULL, 75300000, NULL, NULL, 1, 'Active'),
(42, 'NDINO323LDIA', N'Nhẫn cầu hôn Vàng 18K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO323LDIA', 'nhan-cau-hon-ndino323ldia', 1, 1, '18K', 3.820, 'Fixed', NULL, 75140000, NULL, NULL, 1, 'Active'),
(43, 'NDINO324LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO324LDIA', 'nhan-cau-hon-ndino324ldia', 1, 1, '14K', NULL, 'Fixed', NULL, 25829000, NULL, N'Lấy cảm hứng từ bó hoa cưới linh lan, biểu trưng cho sự thuần khiết và tình yêu vĩnh cửu, chiếc nhẫn này không chỉ mang đến vẻ đẹp thanh nhã mà còn thể hiện hy vọng về hạnh phúc viên mãn của cặp đôi. Ổ nhẫn được cách điệu từ sợi dây tơ hồng, uốn lượn khéo léo thành hình trái tim, tỉ lệ hoàn hảo với viên đá chủ, tượng trưng cho sự kết nối và đồng điệu giữa hai trái tim yêu thương. Phiên bản nhẫn vàng trắng được kết hợp với ổ nhẫn vàng hồng, mang đến vẻ ngọt ngào, hiện đại. 
Đai nhẫn như những chiếc lá hoa linh lan, đính dải đá lấp lánh tựa như những giọt sương mai long lanh, tôn vinh vẻ đẹp của viên chủ trên ổ nhẫn tinh tế, hoàn thiện vẻ đẹp lộng lẫy của chiếc nhẫn.
Chiếc nhẫn là lời cầu hôn chân thành nhất, là "bó hoa cưới" mà bạn muốn cô ấy cầm trên tay trong ngày trọng đại của cả hai.', 1, 'Active'),
(44, 'NDINO325LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO325LDIA', 'nhan-cau-hon-ndino325ldia', 1, 1, '14K', NULL, 'Fixed', NULL, 23925000, NULL, N'Lấy cảm hứng từ hoa baby''s breath trong bó hoa cưới, loài hoa có nguồn gốc từ Đông Âu này là biểu trưng cho sự tinh khiết, niềm vui và tình yêu trong sáng. Chiếc nhẫn này như một bản giao hưởng của sắc đẹp và cảm xúc. 
Đai nhẫn được điểm xuyết bằng dải bi milgrain, mang đến vẻ đẹp cổ điển và nên thơ từ nhiều góc độ. Khi nhìn theo phương ngang, chiếc nhẫn nữ tính tựa như một nàng thơ Đông Âu, với tạo hình chiếc nơ ngọt ngào, tôn lên vẻ rực rỡ và lung linh của viên đá chủ. Còn khi nhìn từ trên xuống, dải bi milgrain tinh xảo trải dọc đai nhẫn như một bó hoa cưới baby''s breath trên tay cô dâu, đầy tinh tế nhưng không kém phần rực rỡ, khắc ghi những giây phút hạnh phúc trọn vẹn. Phiên bản vàng trắng được kết hợp ổ nhẫn vàng hồng mang đến nét hiện đại, trẻ trung.
Chiếc nhẫn là lời khẳng định rằng: Đối với anh, tình yêu của chúng ta là món quà quý giá, được buộc chặt bằng những sợi dây của hạnh phúc.', 1, 'Active'),
(45, 'NDINO326LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO326LDIA', 'nhan-cau-hon-ndino326ldia', 1, 1, '14K', NULL, 'Fixed', 1900000, 30652000, NULL, N'Lấy cảm hứng từ nữ hoàng của các loài hoa - hoa hồng nước Pháp quyến rũ trong bó hoa cưới của cô dâu, biểu trưng cho tình yêu sâu sắc, sự lãng mạn và niềm đam mê nồng nhiệt. Ổ nhẫn được tinh tế đính đá cách điệu bông hoa hồng, tạo nên vẻ đẹp sang trọng đầy quyền lực. Bệ đỡ ổ nhẫn gợi nhớ đến vai áo mềm mại của cô dâu, đặc biệt với phiên bản vàng trắng, chi tiết này được điểm tô màu vàng hồng, tạo nên nét trẻ trung và tinh tế.
Đai nhẫn được xếp tầng tựa như những cánh hoa hồng mềm mại, thể hiện sự nâng niu và trân trọng trong tình yêu. Khi nhìn từ trên xuống, các viên đá được đính kết khéo léo, đan xen với họa tiết milgrain tạo hiệu ứng lấp lánh tối đa, từng chi tiết đều phản chiếu ánh sáng rực rỡ.', 1, 'Active'),
(46, 'NDINO327LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO327LDIA', 'nhan-cau-hon-ndino327ldia', 1, 1, '14K', NULL, 'Fixed', NULL, 24709000, NULL, N'Hoa mộc lan là một trong những loài hoa cưới truyền thống và phổ biến, mang ý nghĩa về tình yêu thuần khiết và chung thủy.
Đai nhẫn trơn kết hợp cùng dải bi milgrain, tái hiện những cánh hoa mộc lan đang khẽ bung nở, toát lên vẻ thanh thoát và nhẹ nhàng. Những chi tiết này không chỉ giúp tạo nên sự hòa quyện giữa nét hiện đại và cổ điển mà còn làm nổi bật sự rực rỡ viên kim cương chủ.
Với thiết kế dáng Solitaire, ổ nhẫn cao kiêu hãnh với duy nhất một viên kim cương chủ, được nâng đỡ bởi các chấu tinh xảo hình cánh hoa tạo thêm sự "ngọt ngào" cho chiếc nhẫn.', 1, 'Active'),
(47, 'NDINO328LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO328LDIA', 'nhan-cau-hon-ndino328ldia', 1, 1, '14K', NULL, 'Fixed', NULL, 24551000, NULL, N'Lấy cảm hứng từ vẻ đẹp kiêu sa của hoa hải đường - loài hoa tượng trưng cho tình yêu chân thành và viên mãn. Đai nhẫn được thiết kế mềm mại như những cánh hoa xếp lớp, tạo nên sự hài hòa và tinh tế. Toàn bộ vẻ lộng lẫy và cầu kỳ được tập trung vào phần ổ nhẫn cao, được chế tác tinh xảo và điểm xuyết bằng những viên kim cương tấm, mang lại cảm giác thanh thoát và kiêu kỳ. Nhìn từ trên xuống, viên kim cương chủ càng thêm rực rỡ và nổi bật nhờ hiệu ứng ánh sáng từ những viên kim cương tấm trên đai nhẫn, tạo nên vẻ đẹp hoàn mỹ đầy cuốn hút.', 1, 'Active'),
(48, 'NDINO329LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO329LDIA', 'nhan-cau-hon-ndino329ldia', 1, 1, '14K', NULL, 'Fixed', NULL, 24961000, NULL, N'Lấy cảm hứng từ nét lộng lẫy của hoa mẫu đơn trong bó hoa cưới của cô dâu, tượng trưng cho tình yêu chân thành và hạnh phúc vĩnh cửu. Ổ nhẫn mang hình ảnh dây tơ hồng và nút thắt trái tim, là biểu trưng bất diệt cho tình yêu, định mệnh và sự giao hòa trọn vẹn giữa hai tâm hồn đồng điệu. Với phiên bản vàng trắng, ổ nhẫn được kết hợp màu vàng hồng, tạo điểm nhấn trẻ trung và hiện đại. 
Nhẫn cầu hôn mang vẻ đẹp rực rỡ từ nhiều góc độ. Ở hướng nhìn ngang, đai nhẫn cách điệu các lớp cánh hoa bồng bềnh mềm mại, viền bi milgrain mang đến vẻ đẹp hòa quyện hoàn hảo giữa cổ điển và hiện đại. Khi nhìn chính diện từ trên xuống, dải kim cương và đai nhẫn hòa quyện tạo nên sự lấp lánh tuyệt mỹ. Tỉ lệ hoàn hảo giữa ổ và đai nhẫn mang đến cảm giác thanh thoát và hài hòa, làm nổi bật vẻ đẹp của viên kim cương chủ giữa những cánh hoa tinh tế.', 1, 'Active'),
(49, 'NDINO331LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO331LDIA', 'nhan-cau-hon-ndino331ldia', 1, 1, '14K', NULL, 'Fixed', NULL, 28867000, NULL, N'Lấy cảm hứng từ vẻ đẹp của hoa lily tinh khôi, như một biểu tượng cho tình yêu thuần khiết và tấm lòng thủy chung vĩnh cửu trong bó hoa cưới của cô dâu. Chi tiết trên ổ nhẫn gợi liên tưởng đến chiếc vương miện lộng lẫy của công chúa cao quý, kết hợp hoàn hảo với bệ đỡ cách điệu từ hình ảnh hoa lily đính kim cương rực rỡ, mang đến vẻ đẹp kiêu sa và đầy nữ tính.
Đai nhẫn với dải kim cương lấp lánh trên cả ba mặt, tối đa hóa khả năng tán xạ ánh sáng, tạo nên hiệu ứng lấp lánh lung linh từ mọi góc độ, khiến cho chiếc nhẫn thêm phần thu hút ánh nhìn.', 1, 'Active'),
(50, 'NDINO333LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO333LDIA', 'nhan-cau-hon-ndino333ldia', 1, 1, '14K', NULL, 'Fixed', NULL, 26718000, NULL, N'Lấy cảm hứng từ bó hoa cưới uất kim hương, loài hoa biểu trưng cho tình yêu đôi lứa ngọt ngào và hoàn hảo. Ổ nhẫn 6 chấu như bông hoa uất kim hương tỏa sáng, mang đến vẻ đẹp thanh lịch đầy rực rỡ, tựa như những giây phút hạnh phúc trong ngày trọng đại. Con số 6 còn là biểu tượng của sự cân bằng và hài hòa trong tình yêu.
Nếu viên chủ là bông hoa uất kim hương rực rỡ, thì dải đá lấp lánh quấn quanh đai nhẫn như dải ruy-băng mềm mại tỏa sáng, ôm trọn vẻ đẹp tinh khôi của bó hoa cưới, làm bừng sáng thêm tình yêu của cặp đôi trong ngày trọng đại.
Chiếc nhẫn cầu hôn ở mỗi góc độ lại mang vẻ đẹp khác nhau. Khi nhìn từ trên xuống, dải đá tấm cân xứng với tỉ lệ hoàn hảo, tôn vinh trọn vẻ đẹp của viên chủ. Còn khi nhìn theo phương ngang, đai nhẫn tạo cảm giác sống động, như tùng váy bồng bềnh chuyển động theo từng bước chân của cô dâu khi tiến vào lễ đường.', 1, 'Active'),
(51, 'NDINO335LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO335LDIA', 'nhan-cau-hon-ndino335ldia', 1, 1, '18K', 1.910, 'Fixed', NULL, 36712000, NULL, N'Lấy cảm hứng từ hoa Camellia - loài hoa tượng trưng cho sự thanh tao, thiết kế nhẫn mang đến vẻ đẹp nhẹ nhàng và tinh tế. Ổ nhẫn halo tái hiện những cánh hoa xếp lớp, tôn vinh vẻ đẹp kiêu sa của viên kim cương chủ Lab-grown. Sự kết hợp giữa viên kim cương chủ lấp lánh cùng những viên kim cương tấm điểm xuyết trên trên cánh hoa tựa như những giọt sương mai long lanh. Dọc theo đai nhẫn, những viên kim cương tấm được sắp xếp tinh tế, tạo hiệu ứng ánh sáng lấp lánh đa chiều.', 1, 'Active'),
(52, 'NDINO344LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO344LDIA', 'nhan-cau-hon-ndino344ldia', 1, 1, '14K', 2.130, 'Fixed', NULL, 34691000, NULL, NULL, 1, 'Active'),
(53, 'NDINO345LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO345LDIA', 'nhan-cau-hon-ndino345ldia', 1, 1, '14K', 2.580, 'Fixed', 2150000, 36099000, NULL, NULL, 1, 'Active'),
(54, 'NDINO346LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO346LDIA', 'nhan-cau-hon-ndino346ldia', 1, 1, '14K', 2.380, 'Fixed', 2150000, 33323000, NULL, NULL, 1, 'Active'),
(55, 'NDINO347LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO347LDIA', 'nhan-cau-hon-ndino347ldia', 1, 1, '14K', 2.540, 'Fixed', 2150000, 33752000, NULL, NULL, 1, 'Active'),
(56, 'NDINO348LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO348LDIA', 'nhan-cau-hon-ndino348ldia', 1, 1, '14K', 2.550, 'Fixed', 2150000, 37864000, NULL, NULL, 1, 'Active'),
(57, 'NDINO349LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO349LDIA', 'nhan-cau-hon-ndino349ldia', 1, 1, '14K', 2.240, 'Fixed', 2150000, 36858000, NULL, NULL, 1, 'Active'),
(58, 'NDINO350LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO350LDIA', 'nhan-cau-hon-ndino350ldia', 1, 1, '14K', 2.420, 'Fixed', 2150000, 35460000, NULL, NULL, 1, 'Active'),
(59, 'NDINO351LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO351LDIA', 'nhan-cau-hon-ndino351ldia', 1, 1, '14K', 2.480, 'Fixed', 2150000, 36001000, NULL, NULL, 1, 'Active'),
(60, 'NDINO352LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO352LDIA', 'nhan-cau-hon-ndino352ldia', 1, 1, '14K', 2.180, 'Fixed', 2150000, 35851000, NULL, NULL, 1, 'Active'),
(61, 'NDINO353LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO353LDIA', 'nhan-cau-hon-ndino353ldia', 1, 1, '14K', 2.420, 'Fixed', 2150000, 39402000, NULL, NULL, 1, 'Active'),
(62, 'NDINO354LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO354LDIA', 'nhan-cau-hon-ndino354ldia', 1, 1, '14K', 2.080, 'Fixed', 2150000, 35320000, NULL, NULL, 1, 'Active'),
(63, 'NDINO355LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO355LDIA', 'nhan-cau-hon-ndino355ldia', 1, 1, '14K', 2.000, 'Fixed', 2150000, 35504000, NULL, NULL, 1, 'Active'),
(64, 'NDINO356LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO356LDIA', 'nhan-cau-hon-ndino356ldia', 1, 1, '14K', 2.860, 'Fixed', 690000, 35992000, NULL, NULL, 1, 'Active'),
(65, 'NDINO357LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO357LDIA', 'nhan-cau-hon-ndino357ldia', 1, 1, '14K', 3.240, 'Fixed', 690000, 37600000, NULL, NULL, 1, 'Active'),
(66, 'NDINO358LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO358LDIA', 'nhan-cau-hon-ndino358ldia', 1, 1, '14K', 2.980, 'Fixed', 690000, 35560000, NULL, NULL, 1, 'Active'),
(67, 'NDINO359LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO359LDIA', 'nhan-cau-hon-ndino359ldia', 1, 1, '14K', 2.730, 'Fixed', 1850000, 34972000, NULL, NULL, 1, 'Active'),
(68, 'NDINO360LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO360LDIA', 'nhan-cau-hon-ndino360ldia', 1, 1, '14K', 2.890, 'Fixed', 690000, 37027000, NULL, NULL, 1, 'Active'),
(69, 'NDINO361LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO361LDIA', 'nhan-cau-hon-ndino361ldia', 1, 1, '14K', 2.970, 'Fixed', 690000, 37198000, NULL, NULL, 1, 'Active'),
(70, 'NDINO362LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO362LDIA', 'nhan-cau-hon-ndino362ldia', 1, 1, '14K', 2.820, 'Fixed', 690000, 38635000, NULL, NULL, 1, 'Active'),
(71, 'NDINO363LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO363LDIA', 'nhan-cau-hon-ndino363ldia', 1, 1, '14K', 2.860, 'Fixed', 1850000, 36842000, NULL, NULL, 1, 'Active'),
(72, 'NDINO364LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO364LDIA', 'nhan-cau-hon-ndino364ldia', 1, 1, '14K', 3.050, 'Fixed', 690000, 36889000, NULL, NULL, 1, 'Active'),
(73, 'NDINO365LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO365LDIA', 'nhan-cau-hon-ndino365ldia', 1, 1, '14K', 2.930, 'Fixed', 1850000, 37491000, NULL, NULL, 1, 'Active'),
(74, 'NDINO366LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO366LDIA', 'nhan-cau-hon-ndino366ldia', 1, 1, '14K', 2.710, 'Fixed', 1850000, 36239000, NULL, NULL, 1, 'Active'),
(75, 'NDINO39LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NDINO39LDIA', 'nhan-ndino-39ldia', 1, 1, '14K', 1.470, 'Fixed', 2150000, 19892000, NULL, N'Đai nhẫn uốn lượn mềm mại, thanh thoát, đính kim cương tấm, tạo hiệu ứng lấp lánh ở nhiều góc độ. Nhìn từ trên xuống, đai nhẫn cách điệu biểu tượng vô cực tinh tế, mang ý nghĩa về một tình yêu luôn vĩnh cửu bền lâu.', 1, 'Active'),
(76, 'NKC312LDIA', N'Nhẫn cầu hôn Vàng 14K Kim cương Lab-grown', N'Nhẫn cầu hôn NKC312LDIA', 'nhan-dinh-hon-nkc-312ldia', 1, 1, '14K', 2.740, 'Fixed', NULL, 31528000, NULL, NULL, 1, 'Active'),
(77, 'NDINO163', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO163', 'nhan-cau-hon-ndino163', 1, 1, '14K', 1.540, 'Fixed', 1450000, 7289000, NULL, NULL, 1, 'Active'),
(78, 'NDINO198', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO198', 'nhan-dinh-hon-ndino-198', 1, 1, '14K', 1.640, 'Fixed', 1500000, 7962000, NULL, N'Đai nhẫn đính đá lấp lánh, tỉ lệ mảnh cân bằng hoàn hảo với viên chủ. Lấy cảm hứng từ nấc thang càng bước càng cao, tượng trưng cho những bước tiến quan trọng trong tình yêu. Mỗi viên đá tựa như một nấc thang mà bạn và cô ấy cùng nhau bước qua để tiến tới hạnh phúc viên mãn.', 1, 'Active'),
(79, 'NDINO231', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO231', 'nhan-ndino-231', 1, 1, '14K', 2.580, 'Fixed', NULL, 11258000, NULL, NULL, 1, 'Active'),
(80, 'NDINO259-1', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO259-1', 'nhan-cau-hon-ndino259-1', 1, 1, '14K', 1.540, 'Fixed', 1450000, 8506000, NULL, NULL, 1, 'Active'),
(81, 'NDINO260', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO260 (1 đôi)', 'nhan-cau-hon-ndino260-1-doi', 1, 1, '14K', NULL, 'Fixed', NULL, 12007000, NULL, NULL, 1, 'Active'),
(82, 'NDINO265', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO265', 'nhan-ndino-265', 1, 1, '14K', 4.270, 'Fixed', 1050000, 17617000, NULL, NULL, 1, 'Active'),
(83, 'NDINO266', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO266', 'nhan-cau-hon-ndino266', 1, 1, '14K', NULL, 'Fixed', NULL, 19113000, NULL, NULL, 1, 'Active'),
(84, 'NDINO268', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO268', 'nhan-cau-hon-ndino268', 1, 1, '14K', 2.010, 'Fixed', NULL, 9486000, NULL, NULL, 1, 'Active'),
(85, 'NDINO269', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO269', 'nhan-cau-hon-ndino269', 1, 1, '14K', 1.660, 'Fixed', NULL, 7335000, NULL, NULL, 1, 'Active'),
(86, 'NDINO270', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO270', 'nhan-cau-hon-ndino270', 1, 1, '14K', 2.300, 'Fixed', 250000, 10891000, NULL, NULL, 1, 'Active'),
(87, 'NDINO280', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO280', 'nhan-dinh-hon-dino-280', 1, 1, '14K', 1.540, 'Fixed', NULL, 6854000, NULL, N'Thiết kế theo phong cách tối giản với dải đá tấm chạy dọc theo đai nhẫn, tối ưu hóa vẻ lấp lánh khi nhìn từ trên xuống. Dải đá dẫn về viên đá chủ ở trung tâm – như tái hiện từng khoảnh khắc mà cặp đôi đã trải qua và mở ra một hành trình mới rực rỡ trong tình yêu.', 1, 'Active'),
(88, 'NDINO281', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO281', 'nhan-dinh-hon-dino281-1', 1, 1, '14K', 2.400, 'Fixed', 250000, 11395000, NULL, N'Dáng nhẫn Solitaire với viên đá chủ duy nhất được bao bọc bởi ổ nhẫn tạo hình cánh hoa, tượng trưng cho tình yêu "chỉ một mình em". Đai nhẫn thon gọn dần về phía viên đá chủ, tạo nên vẻ đẹp tinh tế và mềm mại. Dải đá tấm trên đai nhẫn làm tăng thêm vẻ lấp lánh khi nhìn từ góc chính diện.', 1, 'Active'),
(89, 'NDINO282', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO282', 'nhan-ndino-282', 1, 1, '14K', 1.820, 'Fixed', 1850000, 8536000, NULL, NULL, 1, 'Active'),
(90, 'NDINO285', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO285', 'nhan-ndino-285', 1, 1, '14K', 1.940, 'Fixed', NULL, 9056000, NULL, N'Được cách điệu từ hình ảnh hoa mẫu đơn, biểu tượng cho tình yêu và vẻ đẹp. Ổ nhẫn tạo hình cánh hoa đính đá chìm, tạo hiệu ứng lấp lánh từ nhiều góc độ.
Dải đá tấm đính chìm trên đai nhẫn với các điểm thắt tinh tế, làm tăng thêm vẻ rực rỡ cũng như đảm bảo sự thoải mái khi sử dụng hàng ngày.', 1, 'Active'),
(91, 'NDINO286', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO286', 'nhan-ndino-286', 1, 1, '14K', 1.900, 'Fixed', NULL, 8671000, NULL, N'Lấy cảm hứng từ hình ảnh bông hoa hồng, tượng trưng cho tình yêu ngọt ngào, nồng nàn. Đai nhẫn được đính một dải đá thanh mảnh, tỉ lệ hoàn hảo với ổ nhẫn, tạo nên tổng thể chiếc nhẫn tinh tế và đầy thu hút.', 1, 'Active'),
(92, 'NDINO288', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO288', 'nhan-ndino-288', 1, 1, '14K', 1.660, 'Fixed', NULL, 7780000, NULL, N'Thiết kế lấy cảm hứng từ biểu tượng vô cực với đai nhẫn đính dải đá tấm tạo thành những đường xoắn liên tiếp, tượng trưng cho mong ước về một hành trình tình yêu dài lâu. Ổ nhẫn nâng cao cách điệu đài hoa hồng kiêu sa và được đính đá viền, tạo nên hiệu ứng lấp lánh từ nhiều góc độ.', 1, 'Active'),
(93, 'NDINO289', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO289', 'nhan-ndino-289', 1, 1, '14K', 2.170, 'Fixed', NULL, 9449000, NULL, N'Đai nhẫn với những dải đá tấm đá tạo hình xoắn mềm mại, gợi liên tưởng đến hai tâm hồn yêu hoà quyện . Ổ nhẫn nâng cao cách điệu hoa hồng, biểu tượng của tình yêu và sự nồng nhiệt. Dáng nhẫn Halo với vòng đá nhỏ bao quanh đá chủ tạo hiệu ứng tối đa hóa kích thước và sự lấp lánh của viên chủ.', 1, 'Active'),
(94, 'NDINO293', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO293', 'nhan-ndino-293', 1, 1, '14K', 1.950, 'Fixed', 1850000, 8955000, NULL, N'Ổ đá Halo sở hữu vòng đá tấm bao quanh viên đá chủ, tạo hiệu ứng rực rỡ. Đai nhẫn được cách điệu như cầu nối tình yêu, mang ý nghĩa sâu sắc về sự kết nối giữa hai người - từ gặp gỡ, tìm hiểu, yêu đương rồi mãi mãi bên nhau.', 1, 'Active'),
(95, 'NDINO294', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO294', 'nhan-ndino-294', 1, 1, '14K', 1.820, 'Fixed', 1850000, 8574000, NULL, N'Ổ nhẫn được tạo hình từ bông hoa mẫu đơn - biểu tượng của tình yêu thuần khiết. Cánh hoa đính đá lấp lánh, tạo điểm nhấn rực rỡ, thu hút ánh nhìn. Đai nhẫn lấy cảm hứng từ vai áo choàng của công chúa, mang ý nghĩa về sự che chở và bảo vệ bạn dành cho cô ấy. Sự kết hợp hoàn hảo giữa ổ nhẫn cao kiêu hãnh và đai nhẫn độc đáo tạo nên một thiết kế cân đối hoàn mỹ.', 1, 'Active'),
(96, 'NDINO338', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO338', 'nhan-cau-hon-ndino338', 1, 1, '14K', 1.120, 'Fixed', 1020000, 6310000, NULL, N'Lấy cảm hứng từ dải ngân hà vô tận trong vũ trụ, tượng trưng cho tình yêu của hai bạn luôn tỏa sáng dù ở bất kỳ hoàn cảnh nào. Dải đá tấm trên đai nhẫn tựa như những vì sao nhỏ, tôn vinh vẻ đẹp của viên đá chủ - mang ý nghĩa cô ấy là ngôi sao duy nhất và đẹp nhất của bạn. Ổ nhẫn khi nhìn ở góc đứng là cách điệu bông hoa tulip - biểu tượng của tình yêu chân thành.', 1, 'Active'),
(97, 'NDINO339', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO339', 'nhan-cau-hon-ndino339', 1, 1, '14K', 1.460, 'Fixed', NULL, 7887000, NULL, N'Ổ nhẫn cao, tôn lên vẻ đẹp rực rỡ của viên đá chủ, được lấy cảm hứng từ bông hoa hồng nở rộ, tượng trưng cho tình yêu lãng mạn, cháy bỏng. Đai nhẫn được cách điệu hình ảnh vai áo choàng của nữ hoàng, mang ý nghĩa tôn vinh người phụ nữ, cô ấy là nữ hoàng của trái tim bạn.', 1, 'Active'),
(98, 'NDINO39', N'Nhẫn cầu hôn Vàng 14K đá CZ', N'Nhẫn cầu hôn NDINO39', 'nhan-dinh-hon-ndino-39', 1, 1, '14K', 1.580, 'Fixed', 1450000, 7413000, NULL, NULL, 1, 'Active'),
(99, 'NDINO206MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO206MO', 'nhan-ndino-206mo', 1, 1, '14K', 1.940, 'Fixed', NULL, 11940000, NULL, NULL, 1, 'Active'),
(100, 'NDINO208MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO208MO', 'nhan-dinh-hon-ndino-208mo', 1, 1, '14K', 1.740, 'Fixed', NULL, 10328000, NULL, NULL, 1, 'Active');
INSERT INTO dbo.Products (ProductID, SKU, ProductName, ShortName, Slug, CategoryID, WarrantyPolicyID, Material, WeightGram, PricingMethod, LaborPrice, Price, OriginalPrice, Description, IsEngravable, Status) VALUES
(101, 'NDINO20MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO20MO', 'nhan-cau-hon-ndino20mo', 1, 1, '14K', 1.160, 'Fixed', NULL, 8148000, NULL, NULL, 1, 'Active'),
(102, 'NDINO214MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO214MO', 'nhan-ndino-214mo', 1, 1, '14K', 2.220, 'Fixed', NULL, 14627000, NULL, NULL, 1, 'Active'),
(103, 'NDINO215MO-1', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO215MO-1', 'nhan-cau-hon-ndino215mo-1', 1, 1, '14K', 2.300, 'Fixed', 250000, 13250000, NULL, NULL, 1, 'Active'),
(104, 'NDINO217MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO217MO', 'nhan-ndino-217mo', 1, 1, '14K', 2.000, 'Fixed', NULL, 13885000, NULL, NULL, 1, 'Active'),
(105, 'NDINO249MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO249MO', 'nhan-ndino-249mo', 1, 1, '14K', 2.410, 'Fixed', 1850000, 14019000, NULL, NULL, 1, 'Active'),
(106, 'NDINO252MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO252MO', 'nhan-cau-hon-ndino-252mo', 1, 1, '14K', 2.100, 'Fixed', 1450000, 11796000, NULL, NULL, 1, 'Active'),
(107, 'NDINO253MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO253MO', 'nhan-dinh-hon-ndino-253mo', 1, 1, '14K', 2.300, 'Fixed', NULL, 13163000, NULL, NULL, 1, 'Active'),
(108, 'NDINO254MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO254MO', 'nhan-dinh-hon-ndino-254mo', 1, 1, '14K', 1.930, 'Fixed', NULL, 11703000, NULL, NULL, 1, 'Active'),
(109, 'NDINO256MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO256MO', 'nhan-dinh-hon-ndino-256mo', 1, 1, '14K', 2.100, 'Fixed', 1500000, 12505000, NULL, NULL, 1, 'Active'),
(110, 'NDINO257MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO257MO', 'nhan-dinh-hon-ndino-257mo', 1, 1, '14K', 2.090, 'Fixed', NULL, 12600000, NULL, NULL, 1, 'Active'),
(111, 'NDINO290MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO290MO', 'nhan-cau-hon-ndino-290mo', 1, 1, '14K', 1.520, 'Fixed', 250000, 10441000, NULL, NULL, 1, 'Active'),
(112, 'NDINO303MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO303MO', 'nhan-cau-hon-ndino-303mo', 1, 1, '14K', 1.430, 'Fixed', 1500000, 9386000, NULL, N'Ổ nhẫn được thiết kế tựa như vương miện, gửi gắm lời hứa về tình yêu vĩnh cửu và sự trân trọng suốt đời. Chấu đính đá tấm xếp uốn lượn hoàn hảo, giúp tăng khả năng phản sáng, khiến chiếc nhẫn thêm lấp lánh. Dải đá dẫn lối tới viên Moissanite chủ ở trung tâm – biểu tượng cho những khoảnh khắc quý giá mà cặp đôi đã cùng trải qua, đồng thời mở ra một hành trình mới đầy rực rỡ.', 1, 'Active'),
(113, 'NDINO304MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO304MO', 'nhan-cau-hon-ndino-304mo', 1, 1, '14K', 1.660, 'Fixed', 1050000, 10856000, NULL, NULL, 1, 'Active'),
(114, 'NDINO324MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO324MO', 'nhan-cau-hon-ndino324mo', 1, 1, '14K', NULL, 'Fixed', 1500000, 11359000, NULL, N'Lấy cảm hứng từ bó hoa cưới linh lan, biểu trưng cho sự thuần khiết và tình yêu vĩnh cửu, chiếc nhẫn này không chỉ mang đến vẻ đẹp thanh nhã mà còn thể hiện hy vọng về hạnh phúc viên mãn của cặp đôi. Ổ nhẫn được cách điệu từ sợi dây tơ hồng, uốn lượn khéo léo thành hình trái tim, tỉ lệ hoàn hảo với viên đá chủ, tượng trưng cho sự kết nối và đồng điệu giữa hai trái tim yêu thương. Phiên bản nhẫn vàng trắng được kết hợp với ổ nhẫn vàng hồng, mang đến vẻ ngọt ngào, hiện đại. 
Đai nhẫn như những chiếc lá hoa linh lan, đính dải đá lấp lánh tựa như những giọt sương mai long lanh, tôn vinh vẻ đẹp của viên chủ trên ổ nhẫn tinh tế, hoàn thiện vẻ đẹp lộng lẫy của chiếc nhẫn.
Chiếc nhẫn là lời cầu hôn chân thành nhất, là "bó hoa cưới" mà bạn muốn cô ấy cầm trên tay trong ngày trọng đại của cả hai.', 1, 'Active'),
(115, 'NDINO325MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO325MO', 'nhan-cau-hon-ndino325mo', 1, 1, '14K', NULL, 'Fixed', NULL, 10893000, NULL, N'Lấy cảm hứng từ hoa baby''s breath trong bó hoa cưới, loài hoa có nguồn gốc từ Đông Âu này là biểu trưng cho sự tinh khiết, niềm vui và tình yêu trong sáng. Chiếc nhẫn này như một bản giao hưởng của sắc đẹp và cảm xúc. 
Đai nhẫn được điểm xuyết bằng dải bi milgrain, mang đến vẻ đẹp cổ điển và nên thơ từ nhiều góc độ. Khi nhìn theo phương ngang, chiếc nhẫn nữ tính tựa như một nàng thơ Đông Âu, với tạo hình chiếc nơ ngọt ngào, tôn lên vẻ rực rỡ và lung linh của viên đá chủ. Còn khi nhìn từ trên xuống, dải bi milgrain tinh xảo trải dọc đai nhẫn như một bó hoa cưới baby''s breath trên tay cô dâu, đầy tinh tế nhưng không kém phần rực rỡ, khắc ghi những giây phút hạnh phúc trọn vẹn. Phiên bản vàng trắng được kết hợp ổ nhẫn vàng hồng mang đến nét hiện đại, trẻ trung.
Chiếc nhẫn là lời khẳng định rằng: Đối với anh, tình yêu của chúng ta là món quà quý giá, được buộc chặt bằng những sợi dây của hạnh phúc.', 1, 'Active'),
(116, 'NDINO326MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO326MO', 'nhan-cau-hon-ndino326mo', 1, 1, '14K', NULL, 'Fixed', 1500000, 11263000, NULL, N'Lấy cảm hứng từ nữ hoàng của các loài hoa - hoa hồng nước Pháp quyến rũ trong bó hoa cưới của cô dâu, biểu trưng cho tình yêu sâu sắc, sự lãng mạn và niềm đam mê nồng nhiệt. Ổ nhẫn được tinh tế đính đá cách điệu bông hoa hồng, tạo nên vẻ đẹp sang trọng đầy quyền lực. Bệ đỡ ổ nhẫn gợi nhớ đến vai áo mềm mại của cô dâu, đặc biệt với phiên bản vàng trắng, chi tiết này được điểm tô màu vàng hồng, tạo nên nét trẻ trung và tinh tế.
Đai nhẫn được xếp tầng tựa như những cánh hoa hồng mềm mại, thể hiện sự nâng niu và trân trọng trong tình yêu. Khi nhìn từ trên xuống, các viên đá được đính kết khéo léo, đan xen với họa tiết milgrain tạo hiệu ứng lấp lánh tối đa, từng chi tiết đều phản chiếu ánh sáng rực rỡ.', 1, 'Active'),
(117, 'NDINO327MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO327MO', 'nhan-cau-hon-ndino327mo', 1, 1, '14K', NULL, 'Fixed', 1500000, 11644000, NULL, N'Hoa mộc lan là một trong những loài hoa cưới truyền thống và phổ biến, mang ý nghĩa về tình yêu thuần khiết và chung thủy.
Đai nhẫn trơn kết hợp cùng dải bi milgrain, tái hiện những cánh hoa mộc lan đang khẽ bung nở, toát lên vẻ thanh thoát và nhẹ nhàng. Những chi tiết này không chỉ giúp tạo nên sự hòa quyện giữa nét hiện đại và cổ điển mà còn làm nổi bật sự rực rỡ viên đá moissanite chủ.
Với thiết kế dáng Solitaire, ổ nhẫn cao kiêu hãnh với duy nhất một viên moissanite chủ, được nâng đỡ bởi các chấu tinh xảo hình cánh hoa tạo thêm sự "ngọt ngào" cho chiếc nhẫn.', 1, 'Active'),
(118, 'NDINO329MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO329MO', 'nhan-cau-hon-ndino329mo', 1, 1, '14K', NULL, 'Fixed', 1500000, 10890000, NULL, N'Lấy cảm hứng từ nét lộng lẫy của hoa mẫu đơn trong bó hoa cưới của cô dâu, tượng trưng cho tình yêu chân thành và hạnh phúc vĩnh cửu. Ổ nhẫn mang hình ảnh dây tơ hồng và nút thắt trái tim, là biểu trưng bất diệt cho tình yêu, định mệnh và sự giao hòa trọn vẹn giữa hai tâm hồn đồng điệu. Với phiên bản vàng trắng, ổ nhẫn được kết hợp màu vàng hồng, tạo điểm nhấn trẻ trung và hiện đại. 
Nhẫn cầu hôn mang vẻ đẹp rực rỡ từ nhiều góc độ. Ở hướng nhìn ngang, đai nhẫn cách điệu các lớp cánh hoa bồng bềnh mềm mại, viền bi milgrain mang đến vẻ đẹp hòa quyện hoàn hảo giữa cổ điển và hiện đại. Khi nhìn chính diện từ trên xuống, dải kim cương và đai nhẫn hòa quyện tạo nên sự lấp lánh tuyệt mỹ. Tỉ lệ hoàn hảo giữa ổ và đai nhẫn mang đến cảm giác thanh thoát và hài hòa, làm nổi bật vẻ đẹp của viên moissanite chủ giữa những cánh hoa tinh tế.', 1, 'Active'),
(119, 'NDINO330MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO330MO', 'nhan-cau-hon-ndino330mo', 1, 1, '14K', NULL, 'Fixed', NULL, 10694000, NULL, N'Lấy cảm hứng từ hoa nguyệt quế – biểu tượng của vinh quang và tình yêu trường tồn. Ổ nhẫn được cách điệu như một bông nguyệt quế kiêu sa, với những đường nét mềm mại, tôn lên vẻ duyên dáng và tinh tế. Phần đai nhẫn trơn được nhấn nhá bởi dải bi milgrain uốn lượn, tạo nên sự hài hòa giữa vẻ đẹp cổ điển và hiện đại. Dải bi trải dài tượng trưng cho con đường hạnh phúc mà hai người cùng đồng hành. Chiếc nhẫn cầu hôn không chỉ là lời hứa yêu thương mãi mãi mà còn là sự khẳng định rằng bạn đã "chiến thắng" trái tim của cô ấy – kho báu quý giá nhất trong cuộc đời bạn.', 1, 'Active'),
(120, 'NDINO331MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO331MO', 'nhan-cau-hon-ndino331mo', 1, 1, '14K', NULL, 'Fixed', NULL, 12386000, NULL, N'Lấy cảm hứng từ vẻ đẹp của hoa lily tinh khôi, như một biểu tượng cho tình yêu thuần khiết và tấm lòng thủy chung vĩnh cửu trong bó hoa cưới của cô dâu. Chi tiết trên ổ nhẫn gợi liên tưởng đến chiếc vương miện lộng lẫy của công chúa cao quý, kết hợp hoàn hảo với bệ đỡ cách điệu từ hình ảnh hoa lily đính đá rực rỡ, mang đến vẻ đẹp kiêu sa và đầy nữ tính.
Đai nhẫn với dải đá moissanite lấp lánh trên cả ba mặt, tối đa hóa khả năng tán xạ ánh sáng, tạo nên hiệu ứng lấp lánh lung linh từ mọi góc độ, khiến cho chiếc nhẫn thêm phần thu hút ánh nhìn.', 1, 'Active'),
(121, 'NDINO333MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO333MO', 'nhan-cau-hon-ndino333mo', 1, 1, '14K', NULL, 'Fixed', NULL, 11467000, NULL, N'Lấy cảm hứng từ bó hoa cưới uất kim hương, loài hoa biểu trưng cho tình yêu đôi lứa ngọt ngào và hoàn hảo. Ổ nhẫn 6 chấu như bông hoa uất kim hương tỏa sáng, mang đến vẻ đẹp thanh lịch đầy rực rỡ, tựa như những giây phút hạnh phúc trong ngày trọng đại. Con số 6 còn là biểu tượng của sự cân bằng và hài hòa trong tình yêu.
Nếu viên chủ là bông hoa uất kim hương rực rỡ, thì dải đá lấp lánh quấn quanh đai nhẫn như dải ruy-băng mềm mại tỏa sáng, ôm trọn vẻ đẹp tinh khôi của bó hoa cưới, làm bừng sáng thêm tình yêu của cặp đôi trong ngày trọng đại.
Chiếc nhẫn cầu hôn ở mỗi góc độ lại mang vẻ đẹp khác nhau. Khi nhìn từ trên xuống, dải đá tấm cân xứng với tỉ lệ hoàn hảo, tôn vinh trọn vẻ đẹp của viên chủ. Còn khi nhìn theo phương ngang, đai nhẫn tạo cảm giác sống động, như tùng váy bồng bềnh chuyển động theo từng bước chân của cô dâu khi tiến vào lễ đường.', 1, 'Active'),
(122, 'NDINO334MO', N'Nhẫn cầu hôn Vàng 14K đá Moissanite', N'Nhẫn cầu hôn NDINO334MO', 'nhan-cau-hon-ndino334mo', 1, 1, '14K', NULL, 'Fixed', 1500000, 10470000, NULL, N'Lấy cảm hứng từ vẻ đẹp dịu dàng của của bông hoa lài, mang ý nghĩa về một tình yêu thuần khiết và sự gắn kết vững bền giữa hai tâm hồn được gửi gắm trong bó hoa của cô dâu. Ổ nhẫn được tôn cao đây kiêu hãnh, nâng niu viên đá chủ như một tác phẩm nghệ thuật quý giá.
Chiếc nhẫn sở hữu vẻ đẹp lộng lẫy từ nhiều góc độ. Khi chiêm ngưỡng ở hướng nhìn ngang, nhẫn cầu hôn mang vẻ tinh tế của hai sợi tơ hồng xoắn kết, mang ý nghĩa khẳng định mối giao hòa trọn vẹn giữa hai con người đang yêu. Ở góc nhìn từ trên xuống, viên moissanite chủ cùng đai nhẫn uốn lượn mềm mại, mang đến cảm giác tựa như những cánh hoa lài đang khẽ lay động trong làn gió, tạo nên vẻ đẹp tinh tế mà ấn tượng.', 1, 'Active'),
(123, 'NDINO172KC', N'Nhẫn cầu hôn Vàng 18K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO172KC', 'nhan-cau-hon-ndino172kc', 1, 1, '18K', 2.780, 'Fixed', NULL, 33012000, NULL, NULL, 1, 'Active'),
(124, 'NDINO173KC', N'Nhẫn cầu hôn Vàng 18K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO173KC', 'nhan-cau-hon-ndino173kc', 1, 1, '18K', 1.900, 'Fixed', NULL, 27745000, NULL, NULL, 1, 'Active'),
(125, 'NDINO174KC', N'Nhẫn cầu hôn Vàng 18K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO174KC', 'nhan-cau-hon-ndino174kc', 1, 1, '18K', 2.260, 'Fixed', NULL, 45641000, NULL, NULL, 1, 'Active'),
(126, 'NDINO175KC', N'Nhẫn cầu hôn Vàng 18K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO175KC', 'nhan-cau-hon-ndino175kc', 1, 1, '18K', 3.310, 'Fixed', NULL, 70691000, NULL, NULL, 1, 'Active'),
(127, 'NDINO176KC', N'Nhẫn cầu hôn Vàng 18K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO176KC', 'nhan-cau-hon-ndino176kc', 1, 1, '18K', 3.120, 'Fixed', NULL, 39983000, NULL, NULL, 1, 'Active'),
(128, 'NDINO177KC', N'Nhẫn cầu hôn Vàng 18K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO177KC', 'nhan-cau-hon-ndino177kc', 1, 1, '18K', 1.810, 'Fixed', NULL, 21671000, NULL, NULL, 1, 'Active'),
(129, 'NDINO179KC', N'Nhẫn cầu hôn Vàng 14K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO179KC', 'nhan-cau-hon-ndino179kc', 1, 1, '14K', 1.660, 'Fixed', NULL, 41423000, NULL, NULL, 1, 'Active'),
(130, 'NDINO180KC', N'Nhẫn cầu hôn Vàng 18K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO180KC', 'nhan-cau-hon-ndino180kc', 1, 1, '18K', 1.340, 'Fixed', NULL, 23155000, NULL, NULL, 1, 'Active'),
(131, 'NDINO198KC', N'Nhẫn cầu hôn Vàng 14K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO198KC', 'nhan-cau-hon-ndino198kc', 1, 1, '14K', 1.500, 'Fixed', NULL, 27554000, NULL, N'Đai nhẫn đính kim cương tấm lấp lánh, tỉ lệ mảnh cân bằng hoàn hảo với viên kim cương chủ rực rỡ. Lấy cảm hứng từ nấc thang càng bước càng cao, tượng trưng cho những bước tiến quan trọng trong tình yêu. Mỗi viên kim cương tựa như một nấc thang mà bạn và cô ấy cùng nhau bước qua để tiến tới hạnh phúc viên mãn.', 1, 'Active'),
(132, 'NDINO206CKC', N'Nhẫn cầu hôn Vàng 14K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO206CKC', 'nhan-cau-hon-ndino206ckc', 1, 1, '14K', 1.530, 'Fixed', NULL, 33224000, NULL, N'Ổ nhẫn tạo hình từ hai đường uốn lượn mềm mại đan vào nhau, như sợi dây tơ hồng của ông tơ bà nguyệt đã se duyên cho người gắn kết. Nhìn từ trên xuống, đai nhẫn thắt lại tại viên kim cương chủ, kết hợp dải kim cương lấp lánh giúp tối đa hóa khả năng tán sắc ánh sáng, mang đến vẻ lấp lánh thu hút ánh nhìn.', 1, 'Active'),
(133, 'NDINO235BKC', N'Nhẫn cầu hôn Vàng 14K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO235BKC', 'nhan-ndino-235bkc', 1, 1, '14K', 2.240, 'Fixed', NULL, 34165000, NULL, N'Dáng nhẫn tối giản nhưng chưa bao giờ lỗi thời, tôn vinh viên kim cương chủ lấp lánh, mang vẻ đẹp vượt thời gian. Nhìn từ trên xuống, đai nhẫn thon dần về phía viên kim cương chủ, tựa như chiếc nơ mềm mại và nữ tính, như lời khẳng định: Cô ấy là món quà mà bạn vô cùng trân quý, nâng niu.', 1, 'Active'),
(134, 'NDINO248KC', N'Nhẫn cầu hôn Vàng 14K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO248KC', 'nhan-cau-hon-ndino248kc', 1, 1, '14K', 2.660, 'Fixed', NULL, 78678000, NULL, NULL, 1, 'Active'),
(135, 'NDINO255KC-1', N'Nhẫn cầu hôn Vàng 14K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO255KC-1', 'nhan-cau-hon-ndino255kc-1', 1, 1, '14K', 2.000, 'Fixed', NULL, 29679000, NULL, N'Dáng nhẫn Solitaire với viên kim cương tự nhiên duy nhất, kiêu hãnh tỏa sáng trên đai nhẫn trơn tối giản, thay lời khẳng định rằng cô ấy giữ vị trí độc tôn trong trái tim bạn. 
Khi nhìn từ trên xuống, đai nhẫn được thắt lại ở ổ nhẫn, tựa như biểu tượng vô cực, mang ý nghĩa sâu sắc về tình yêu vĩnh cửu của hai bạn. Đây là thiết kế mang vẻ đẹp vượt thời gian.', 1, 'Active'),
(136, 'NDINO255KC-2', N'Nhẫn cầu hôn Vàng 14K Kim cương thiên nhiên', N'Nhẫn cầu hôn NDINO255KC-2', 'nhan-cau-hon-ndino255kc-2', 1, 1, '14K', 1.170, 'Fixed', NULL, 18138000, NULL, NULL, 1, 'Active'),
(137, 'NDINO258KC', N'Nhẫn cầu hôn Vàng 14K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO258KC', 'nhan-cau-hon-ndino258kc', 1, 1, '14K', 2.430, 'Fixed', NULL, 68606000, NULL, NULL, 1, 'Active'),
(138, 'NDINO26KC', N'Nhẫn cầu hôn Vàng 18K Kim cương tự nhiên', N'Nhẫn cầu hôn NDINO26KC', 'nhan-cau-hon-ndino26kc', 1, 1, '18K', 1.690, 'Fixed', NULL, 26146000, NULL, NULL, 1, 'Active'),
(139, 'NCZ032LDIA', N'Nhẫn cưới Vàng 14K Kim cương Lab-grown', N'Nhẫn cưới NCZ032LDIA', 'nhan-cuoi-ncz032ldia', 2, 1, '14K', 0.920, 'Fixed', NULL, 15000000, NULL, N'Bề mặt nhẫn tạo hình các nếp gấp mềm mại và sống động, giống như váy cưới của cô dâu, gợi cả hai về khoảnh khắc đẹp đẽ và thiêng liêng nhất. Viên kim cương đính chìm trong lòng nhẫn nam với ý nghĩa chỉ một mình em. Nhẫn nữ đầy mềm mại với đường kim cương tấm uốn lượn theo đai nhẫn.', 1, 'Active'),
(140, 'NCZ041LDIA', N'Nhẫn cưới Vàng 14K Kim cương Lab-grown', N'Nhẫn cưới NCZ041LDIA', 'nhan-cuoi-ncz041ldia', 2, 1, '14K', 1.740, 'Fixed', NULL, 18479000, NULL, NULL, 1, 'Active'),
(141, 'NCZ077LDIA', N'Nhẫn cưới Vàng 14K Kim cương Lab-grown', N'Nhẫn cưới NCZ077LDIA', 'nhan-cuoi-ncz077ldia', 2, 1, '14K', 1.660, 'Fixed', NULL, 19498000, NULL, N'Nhờ công nghệ chế tác hiện đại, hai mảnh nhẫn vàng trắng và vàng hồng được ghép nối, quyện vào nhau hoàn hảo tuyệt đối. Đường nét uốn lượn mượt mà gợi liên tưởng đến hai trái tim yêu khi đã hoà làm một, luôn hướng về nhau dù ở lúc nào - nơi đâu. Đai nhẫn nữ tô điểm bởi dải kim cương tấm lấp lánh, kiêu kỳ, quyến rũ.', 1, 'Active'),
(142, 'NCZ085LDIA', N'Nhẫn cưới Vàng 14K Kim cương Lab-grown', N'Nhẫn cưới NCZ085LDIA', 'nhan-cuoi-ncz085ldia', 2, 1, '14K', 1.000, 'Fixed', NULL, 10115000, NULL, NULL, 1, 'Active'),
(143, 'NCZ099LDIA', N'Nhẫn cưới Vàng 14K Kim cương Lab-grown', N'Nhẫn cưới NCZ099LDIA', 'ncz099ldia', 2, 1, '10K', NULL, 'Fixed', NULL, 12121000, NULL, NULL, 1, 'Active'),
(144, 'NCZ112LDIA', N'Nhẫn cưới Vàng 10K Kim cương Lab-grown', N'Nhẫn cưới NCZ112LDIA', 'nhan-cuoi-ncz112ldia', 2, 1, '10K', 1.060, 'Fixed', NULL, 7826000, NULL, NULL, 1, 'Active'),
(145, 'NCZ113', N'Nhẫn cưới Vàng 14K Kim cương Lab-grown', N'Nhẫn cưới NCZ113LDIA', 'nhan-cuoi-ncz113ldia', 2, 1, '14K', 1.160, 'Fixed', NULL, 13159000, NULL, NULL, 1, 'Active'),
(146, 'NCZ115LDIA', N'Nhẫn cưới Vàng 14K Kim cương Lab-grown', N'Nhẫn cưới NCZ115LDIA', 'nhan-cuoi-ncz115ldia', 2, 1, '14K', 1.310, 'Fixed', NULL, 13217000, NULL, NULL, 1, 'Active'),
(147, 'NCZ117LDIA', N'Nhẫn cưới Vàng 14K Kim cương Lab-grown', N'Nhẫn cưới NCZ117LDIA', 'nhan-cuoi-ncz117ldia', 2, 1, '14K', 1.100, 'Fixed', NULL, 13853000, NULL, NULL, 1, 'Active'),
(148, 'NCZ118LDIA', N'Nhẫn cưới Vàng 14K Kim cương Lab-grown', N'Nhẫn cưới NCZ118LDIA', 'nhan-cuoi-ncz118ldia', 2, 1, '14K', 1.160, 'Fixed', NULL, 11390000, NULL, NULL, 1, 'Active'),
(149, 'NCZ119LDIA', N'Nhẫn cưới Vàng 14K Kim cương Lab-grown', N'Nhẫn cưới NCZ119LDIA', 'nhan-cuoi-ncz119ldia', 2, 1, '14K', 1.060, 'Fixed', NULL, 11276000, NULL, NULL, 1, 'Active'),
(150, 'NC129', N'Nhẫn cưới Vàng 10K đá CZ', N'Nhẫn cưới NC129', 'nhan-cuoi-nc129', 2, 1, '10K', 1.410, 'Fixed', NULL, 10290000, NULL, N'Thiết kế nhẫn cưới mang phong cách tối giản với đai nhẫn trơn điểm nhấn là viên đá duy nhất ở trung tâm, tượng trưng rằng đối phương là duy nhất. Vạt cắt trên thân nhẫn tạo nên sự mềm mại thanh thoát. Bản nhẫn mảnh đặc biệt phù hợp với những đôi tay nhỏ nhắn, tôn lên vẻ sang trọng và duyên dáng của người đeo.', 1, 'Active'),
(151, 'NC130B', N'Nhẫn cưới Vàng 14K đá CZ', N'Nhẫn cưới NC130B', 'nhan-cuoi-nc-130', 2, 1, '14K', 2.680, 'Fixed', NULL, 28936000, NULL, NULL, 1, 'Active'),
(152, 'NC131', N'Nhẫn cưới Vàng 10K đá CZ', N'Nhẫn cưới Le Soleil NC131', 'nhan-cuoi-le-soleil-nc131', 2, 1, '10K', 2.340, 'Fixed', NULL, 12678000, NULL, N'Cặp nhẫn mang thiết kế hiện đại, đơn giản với chi tiết hình thoi ôm trọn viên đá trung tâm. Đường cắt phá cách cùng hiệu ứng đai dày dần lên trung tâm tạo chiều sâu cho nhẫn. Viên đá duy nhất nằm gọn trong khung hình thoi mang đến cảm giác an toàn, như cách hai người gìn giữ và che chở cho nhau trong hành trình chung đôi.', 1, 'Active'),
(153, 'NC206', N'Nhẫn cưới Vàng 10K đá CZ', N'Nhẫn cưới NC206', 'nhan-cuoi-nc206', 2, 1, '10K', NULL, 'Fixed', NULL, 8470000, NULL, N'Lấy cảm hứng từ biểu tượng vô cực mang ý nghĩa một tình yêu không giới hạn, bền vững theo thời gian. Đường nét mềm mại uốn lượn như hai dòng chảy hòa quyện, tượng trưng cho sự gắn kết trọn đời và sự đồng điệu giữa hai tâm hồn. Viên đá duy nhất được nâng niu trong vòng xoắn, như một sự che chở, trân trọng.', 1, 'Active'),
(154, 'NC215', N'Nhẫn cưới Vàng 10K đá CZ', N'Nhẫn cưới NC215', 'nhan-cuoi-nc215', 2, 1, '10K', NULL, 'Fixed', NULL, 11545000, NULL, N'Đai nhẫn như một dải lụa xếp lớp, tạo hiệu ứng uyển chuyển mềm mại. Dọc theo đai là ba viên đá nhỏ tượng trưng cho mong muốn Quá khứ - Hiện tại - Tương lai luôn có sự xuất hiện và đồng hành của đối phương.', 1, 'Active'),
(155, 'NC225', N'Nhẫn cưới Vàng 10K đá CZ', N'Nhẫn cưới Le Soleil NC225', 'nhan-cuoi-le-soleil-nc225', 2, 1, '10K', 1.320, 'Fixed', NULL, 10185000, NULL, N'Thiết kế đai nhẫn trơn kết hợp một viên đá trung tâm kinh điển được cách điệu hiện đại và tinh tế hơn. Thân nhẫn được làm nổi bật bởi vạt cắt tựa hình chiếc lá, vươn đến nơi viên đá chủ duy nhất được đặt, ánh lên vẻ lấp lánh nhẹ nhàng. Thiết kế đá chìm tượng trưng cho tình yêu thầm lặng nhưng luôn tỏa sáng theo cách riêng.', 1, 'Active'),
(156, 'NC274', N'Nhẫn cưới Vàng 10K đá CZ', N'Nhẫn cưới La Nuit NC274', 'nhan-cuoi-la-nuit-nc274', 2, 1, '10K', NULL, 'Fixed', NULL, 8864000, NULL, NULL, 1, 'Active'),
(157, 'NC411', N'Nhẫn cưới Vàng 10K đá CZ', N'Nhẫn cưới Le Soleil NC411', 'nhan-cuoi-le-soleil-nc411', 2, 1, '10K', 1.120, 'Fixed', NULL, 7597000, NULL, NULL, 1, 'Active'),
(158, 'NC558', N'Nhẫn cưới Vàng 10K đá CZ', N'Nhẫn cưới La Nuit NC558', 'nhan-cuoi-la-nuit-nc558', 2, 1, '10K', 1.440, 'Fixed', NULL, 10261000, NULL, N'Thiết kế nhẫn cưới thanh lịch với đai nhẫn trơn, điểm nhấn là những vát cắt tựa như dải lụa vắt ngang đai nhẫn. Viên đá duy nhất ở trung tâm tượng trưng cho tình yêu là độc nhất. Cặp nhẫn mang vẻ đẹp hiện đại, tinh tế, phù hợp với cặp đôi yêu thích sự đơn giản.', 1, 'Active'),
(159, 'NC784', N'Nhẫn cưới Vàng 14K đá CZ', N'Nhẫn cưới NC784', 'nhan-cuoi-nc-784', 2, 1, '14K', 1.470, 'Fixed', NULL, 17242000, NULL, NULL, 1, 'Active'),
(160, 'NC785', N'Nhẫn cưới Vàng 14K đá CZ', N'Nhẫn cưới NC785', 'nhan-cuoi-nc-785', 2, 1, '14K', 2.400, 'Fixed', NULL, 21678000, NULL, NULL, 1, 'Active'),
(161, 'NC787', N'Nhẫn cưới Vàng 14K đá CZ', N'Nhẫn cưới NC787', 'nhan-cuoi-nc-787', 2, 1, '14K', 1.530, 'Fixed', NULL, 19179000, NULL, NULL, 1, 'Active'),
(162, 'NC788', N'Nhẫn cưới Vàng 14K CZ', N'Nhẫn cưới NC788', 'nhan-cuoi-nc788', 2, 1, '14K', 1.700, 'Fixed', NULL, 29364000, NULL, NULL, 1, 'Active'),
(163, 'NC799', N'Nhẫn cưới Vàng 14K đá CZ', N'Nhẫn cưới NC799', 'nhan-cuoi-nc799', 2, 1, '14K', 1.780, 'Fixed', NULL, 20853000, NULL, NULL, 1, 'Active'),
(164, 'NC855', N'Nhẫn cưới Vàng 14K đá CZ', N'Nhẫn cưới NC855', 'nhan-cuoi-nc855', 2, 1, '14K', 2.180, 'Fixed', NULL, 24132000, NULL, NULL, 1, 'Active'),
(165, 'NC872', N'Nhẫn cưới Vàng 14K đá CZ', N'Nhẫn cưới NC872', 'nhan-cuoi-nc-872', 2, 1, '14K', 1.360, 'Fixed', NULL, 14868000, NULL, NULL, 1, 'Active'),
(166, 'NCZ114', N'Nhẫn cưới Vàng 14K', N'Nhẫn cưới NCZ114', 'nhan-cuoi-ncz114', 2, 1, '14K', 1.040, 'Fixed', NULL, 12799000, NULL, NULL, 1, 'Active'),
(167, 'NCZ116', N'Nhẫn cưới Vàng 14K', N'Nhẫn cưới NCZ116', 'nhan-cuoi-ncz116', 2, 1, '14K', 1.020, 'Fixed', NULL, 11985000, NULL, NULL, 1, 'Active'),
(168, 'NCZ120', N'Nhẫn cưới Vàng 10K', N'Nhẫn cưới NCZ120', 'nhan-cuoi-ncz120', 2, 1, '10K', 0.970, 'Fixed', NULL, 8253000, NULL, NULL, 1, 'Active'),
(169, 'NCZ121', N'Nhẫn cưới Vàng 10K', N'Nhẫn cưới NCZ121', 'nhan-cuoi-ncz121', 2, 1, '10K', 0.870, 'Fixed', NULL, 6137000, NULL, N'6137', 1, 'Active'),
(170, 'NCZ122', N'Nhẫn cưới Vàng 10K', N'Nhẫn cưới NCZ122', 'nhan-cuoi-ncz122', 2, 1, '10K', 1.120, 'Fixed', NULL, 7890000, NULL, NULL, 1, 'Active'),
(171, 'NC860KC', N'Nhẫn cưới Vàng 14K Kim cương tự nhiên', N'Nhẫn cưới NC860KC', 'nhan-cuoi-nc-860-kc', 2, 1, '14K', 2.610, 'Fixed', NULL, 37006000, NULL, NULL, 1, 'Active'),
(172, 'NC433', N'Nhẫn đôi BAC925', N'Nhẫn cưới Les Estoile NC433', 'nhan-cuoi-les-estoile-nc433', 2, 1, 'BAC925', NULL, 'Fixed', NULL, 1481000, NULL, NULL, 1, 'Active'),
(173, 'NLF424', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF424', 'nhan-nlf-424', 3, 1, '14K', 0.940, 'Fixed', NULL, 4698000, NULL, NULL, 1, 'Active'),
(174, 'NLF431', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF431', 'nhan-nlf-431', 3, 1, '14K', 0.820, 'Fixed', NULL, 3765000, NULL, NULL, 1, 'Active'),
(175, 'NLF433', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF433', 'nhan-nlf-433', 3, 1, '14K', 0.760, 'Fixed', NULL, 3455000, NULL, NULL, 1, 'Active'),
(176, 'NLF434', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF434', 'nhan-nlf-434', 3, 1, '14K', 0.750, 'Fixed', 600000, 3501000, NULL, NULL, 1, 'Active'),
(177, 'NLF449', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF449', 'nhan-nlf-449', 3, 1, '14K', 0.940, 'Fixed', NULL, 4411000, NULL, NULL, 1, 'Active'),
(178, 'NLF450', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF450', 'nhan-nlf-450', 3, 1, '14K', 1.220, 'Fixed', NULL, 5430000, NULL, NULL, 1, 'Active'),
(179, 'NLF453', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF453', 'nhan-nlf-453', 3, 1, '14K', 1.080, 'Fixed', NULL, 4436000, NULL, NULL, 1, 'Active'),
(180, 'NLF454', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF454', 'nhan-nlf-454', 3, 1, '14K', 2.340, 'Fixed', 850000, 7216000, NULL, NULL, 1, 'Active'),
(181, 'NLF455', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF455', 'nhan-nlf-455', 3, 1, '14K', 1.360, 'Fixed', NULL, 6807000, NULL, NULL, 1, 'Active'),
(182, 'NLF456', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF456', 'nhan-nlf-456', 3, 1, '14K', 0.820, 'Fixed', NULL, 5373000, NULL, NULL, 1, 'Active'),
(183, 'NLF457', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF457', 'nhan-nlf-457', 3, 1, '14K', 1.230, 'Fixed', 850000, 4383000, NULL, NULL, 1, 'Active'),
(184, 'NLF460', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF460', 'nhan-nlf-460', 3, 1, '14K', 2.240, 'Fixed', NULL, 6089000, NULL, NULL, 1, 'Active'),
(185, 'NLF465', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF465', 'nhan-nlf-465', 3, 1, '14K', 1.300, 'Fixed', 850000, 4976000, NULL, NULL, 1, 'Active'),
(186, 'NLF467', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF467', 'nhan-nlf-467', 3, 1, '14K', 0.870, 'Fixed', NULL, 4114000, NULL, NULL, 1, 'Active'),
(187, 'NLF468', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF468', 'nhan-nlf-468', 3, 1, '14K', 1.190, 'Fixed', NULL, 5322000, NULL, NULL, 1, 'Active'),
(188, 'NLF481', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF481', 'nhan-nlf-481', 3, 1, '14K', 0.760, 'Fixed', NULL, 3669000, NULL, NULL, 1, 'Active'),
(189, 'NLF484', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF484', 'nhan-nlf-484', 3, 1, '14K', 0.830, 'Fixed', NULL, 4029000, NULL, NULL, 1, 'Active'),
(190, 'NLF488', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF488', 'nhan-nlf-488', 3, 1, '14K', 0.860, 'Fixed', NULL, 3927000, NULL, NULL, 1, 'Active'),
(191, 'NLF489', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF489', 'nhan-nlf-489', 3, 1, '14K', 0.640, 'Fixed', 850000, 3092000, NULL, NULL, 1, 'Active'),
(192, 'NLF498', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NLF498', 'nhan-nlf-498', 3, 1, '14K', 0.870, 'Fixed', 850000, 4936000, NULL, NULL, 1, 'Active'),
(193, 'NPTB350', N'Nhẫn thời trang Vàng 14K đá CZ', N'Nhẫn thời trang NPTB350', 'nhan-cau-hon-nptb350', 3, 1, '14K', 1.560, 'Fixed', NULL, 8054000, NULL, NULL, 1, 'Active'),
(194, 'NZ081', N'Nhẫn thời trang Vàng 10K đá CZ', N'Nhẫn AM NZ081', 'nhan-am-nz081', 3, 1, '10K', NULL, 'Fixed', 690000, 5218000, NULL, NULL, 1, 'Active'),
(195, 'NBTCC90', N'Nhẫn thời trang vàng 14K Ngọc trai', N'Nhẫn NBTCC90', 'nhan-nbtcc90', 3, 1, '14K', 1.770, 'Fixed', NULL, 7334000, NULL, NULL, 1, 'Active'),
(196, 'NBTCC91', N'Nhẫn thời trang vàng 14K Ngọc trai', N'Nhẫn NBTCC91', 'nhan-nbtcc91', 3, 1, '14K', 1.960, 'Fixed', NULL, 8223000, NULL, NULL, 1, 'Active'),
(197, 'NBTCC98', N'Nhẫn thời trang vàng 14K Ngọc trai', N'Nhẫn NBTCC98', 'nhan-nbtcc98', 3, 1, '14K', 1.980, 'Fixed', NULL, 8519000, NULL, NULL, 1, 'Active'),
(198, 'NPTB423', N'Nhẫn thời trang Vàng 10K đá Xà cừ', N'Nhẫn Printemps NPTB423', 'nhan-printemps-nptb423', 3, 1, '10K', 1.090, 'Fixed', 250000, 4822000, NULL, NULL, 1, 'Active'),
(199, 'NZ042', N'Nhẫn thời trang Vàng 10K đá CZ', N'Nhẫn NZ042', 'nhan-nz042', 3, 1, '10K', 0.780, 'Fixed', 750000, 3067000, NULL, NULL, 1, 'Active'),
(200, 'NLF457MO', N'Nhẫn thời trang Vàng 14K đá Moissanite', N'NHẪN AM NLF457MO', 'nhan-am-nlf457mo', 3, 1, '14K', 0.740, 'Fixed', 1000000, 6229000, NULL, NULL, 1, 'Active');
INSERT INTO dbo.Products (ProductID, SKU, ProductName, ShortName, Slug, CategoryID, WarrantyPolicyID, Material, WeightGram, PricingMethod, LaborPrice, Price, OriginalPrice, Description, IsEngravable, Status) VALUES
(201, 'BT161B', N'Bông tai Vàng 10K đá CZ', N'Bông Tai BT161B', 'bong-tai-bt161b', 4, 1, '10K', 0.630, 'Fixed', 1540000, 2361000, NULL, NULL, 0, 'Active'),
(202, 'BT284', N'Bông tai Vàng 14K đá CZ', N'Bông tai BT284', 'bong-tai-bt-284', 4, 1, '14K', 1.300, 'Fixed', 750000, 5936000, NULL, N'Bông tai khoen cá tính với hai dải đá CZ lấp lánh chạy song song, tạo nên vẻ rực rỡ tối đa. Thiết kế tối giản tôn lên vẻ thanh lịch và sang trọng của người đeo. Sản phẩm có thể dễ dàng kết hợp với đa dạng trang phục và phong cách', 0, 'Active'),
(203, 'BT336', N'Bông tai Vàng 14K đá CZ', N'Bông tai BT336', 'bong-tai-bt-336', 4, 1, '14K', 1.440, 'Fixed', 1450000, 5883000, NULL, N'Hoạ tiết hoa bốn cánh với viên đá chủ nổi bật ở trung tâm tạo điểm nhấn rực rỡ. Viền đá tấm tinh xảo ôm lấy từng cánh hoa, vừa tôn lên sự mềm mại, vừa tăng hiệu ứng lấp lánh đầy cuốn hút.
Sản phẩm dễ dàng kết hợp với đa dạng trang phục, phong cách', 0, 'Active'),
(204, 'BT408', N'Bông tai Vàng 10K đá CZ', N'Bông tai BT408', 'bong-tai-bt-408', 4, 1, '10K', 0.980, 'Fixed', 650000, 1897000, NULL, N'Mang hình ảnh cỏ bốn lá - mỗi lá lại tượng trưng cho một điều tốt đẹp: sự tin tưởng, tình yêu, hy vọng và may mắn. Bông tai được đính đá tỉ mỉ với tỉ lệ cân đối hoàn hảo, tăng độ bắt sáng tối đa khi đeo. 
Sản phẩm dễ dàng kết hợp với đa dạng trang phục, phong cách.', 0, 'Active'),
(205, 'BT415', N'Bông tai Vàng 14K đá CZ', N'Bông tai BT415', 'bong-tai-bt415', 4, 1, '14K', 2.270, 'Fixed', 750000, 9216000, NULL, N'Bông tai kết hợp dáng khoen thanh lịch và chi tiết nơ rơi điệu đà, duyên dáng. Chiếc nơ đính đá lấp lánh, rung rinh theo từng chuyển động, tựa như ngôi sao băng lướt qua trên bầu trời đêm, giúp tôn lên từng đường nét gương mặt.
Sản phẩm dễ dàng kết hợp với đa dạng trang phục, phong cách.', 0, 'Active'),
(206, 'BT423', N'Bông tai Vàng 14K đá CZ', N'Bông tai BT423', 'bong-tai-bt-423', 4, 1, '14K', 1.380, 'Fixed', 750000, 6460000, NULL, NULL, 0, 'Active'),
(207, 'BT424', N'Bông tai Vàng 14K đá CZ', N'Bông tai BT424', 'bong-tai-bt424', 4, 1, '14K', 1.630, 'Fixed', 750000, 7120000, NULL, NULL, 0, 'Active'),
(208, 'BT426', N'Bông tai Vàng 14K đá CZ', N'Bông tai BT426', 'bong-tai-bt426', 4, 1, '14K', 1.650, 'Fixed', 1450000, 6704000, NULL, NULL, 0, 'Active'),
(209, 'BT432', N'Bông tai Vàng 14K đá CZ', N'Bông tai BT432', 'bong-tai-bt432', 4, 1, '14K', 1.700, 'Fixed', 650000, 7839000, NULL, NULL, 0, 'Active'),
(210, 'BT433', N'Bông tai Vàng 14K đá CZ', N'Bông tai BT433', 'bong-tai-bt433', 4, 1, '14K', 1.470, 'Fixed', 750000, 6510000, NULL, NULL, 0, 'Active'),
(211, 'BTAM42', N'Bông tai Vàng 14K đá CZ', N'Bông tai BTAM42', 'bong-tai-btam42', 4, 1, '14K', 0.330, 'Fixed', 750000, 3322000, NULL, NULL, 0, 'Active'),
(212, 'BTBZ044', N'Bông tai Vàng 10K đá CZ', N'Bông tai BTBZ044', 'bong-tai-btbz044', 4, 1, '10K', NULL, 'Fixed', 2550000, 2017000, NULL, NULL, 0, 'Active'),
(213, 'BTPTB299', N'Bông tai Vàng 14K đá CZ', N'Bông tai BTPTB299', 'bong-tai-btptb-299', 4, 1, '14K', 1.380, 'Fixed', 650000, 6126000, NULL, NULL, 0, 'Active'),
(214, 'BTPTB324', N'Bông tai Vàng 14K đá CZ', N'Bông tai BTPTB324', 'bong-tai-btptb-324', 4, 1, '14K', 0.860, 'Fixed', 1450000, 3818000, NULL, NULL, 0, 'Active'),
(215, 'BTPTB353', N'Bông tai Vàng 14K đá CZ', N'Bông tai BTPTB353', 'bong-tai-btptb-353', 4, 1, '14K', 2.260, 'Fixed', NULL, 9496000, NULL, NULL, 0, 'Active'),
(216, 'BTPTB418', N'Bông tai Bạc 925', N'Bông tai BTPTB418', 'bong-tai-btptb418', 4, 1, 'BAC925', 1.170, 'Fixed', NULL, 549000, NULL, NULL, 0, 'Active'),
(217, 'BT411', N'Bông tai Vàng 14K', N'Bông tai BT411', 'bong-tai-bt-411', 4, 1, '14K', 0.760, 'Fixed', 1450000, 3538000, NULL, N'Bông tai hình ngôi sao, được chế tác bằng công nghệ hiện đại, tạo bề mặt 2 lớp với lớp bên trong có hoạ tiết đa giác mang đến hiệu ứng gương lấp lánh. Thiết kế hiện đại, tinh tế, phù hợp cho những ai yêu thích phong cách tối giản. Sản phẩm dễ dàng kết hợp với đa dạng trang phục, phong cách', 0, 'Active'),
(218, 'BT412', N'Bông tai Vàng 14K', N'Bông tai BT412', 'bong-tai-bt-412', 4, 1, '14K', 0.920, 'Fixed', 750000, 4166000, NULL, N'Thiết kế bông tai hình cỏ 3 lá - biểu tượng cho sự may mắn. Được chế tác bằng công nghệ hiện đại, tạo bề mặt 2 lớp với lớp bên trong có hoạ tiết đa giác mang đến hiệu ứng gương lấp lánh. Sản phẩm dễ dàng kết hợp với đa dạng trang phục, phong cách', 0, 'Active'),
(219, 'BT413', N'Bông tai Vàng 14K', N'Bông tai BT413', 'bong-tai-bt-413', 4, 1, '14K', 0.940, 'Fixed', 2550000, 4366000, NULL, N'Thiết kế bông tai hình cỏ 4 lá - biểu tượng cho sự may mắn. Được chế tác bằng công nghệ hiện đại, tạo bề mặt 2 lớp với lớp bên trong có hoạ tiết đa giác mang đến hiệu ứng gương lấp lánh. Đường viền uốn lượn mềm mại tạo cảm giác nữ tính, thanh lịch. Sản phẩm dễ dàng kết hợp với đa dạng trang phục, phong cách', 0, 'Active'),
(220, 'BT414', N'Bông tai Vàng 14K', N'Bông tai BT414', 'bong-tai-bt-414', 4, 1, '14K', 1.020, 'Fixed', 2550000, 4594000, NULL, N'Lấy cảm hứng thiết kế từ bông hoa mai với những cánh hoa tròn đầy - tượng trưng cho sự khởi đầu mới may mắn. Được chế tác bằng công nghệ hiện đại, tạo bề mặt 2 lớp với lớp bên trong có hoạ tiết đa giác mang đến hiệu ứng gương lấp lánh. Sản phẩm dễ dàng kết hợp với đa dạng trang phục, phong cách', 0, 'Active'),
(221, 'BTAM44', N'Bông tai Vàng 14K', N'Bông tai BTAM44', 'bong-tai-btam44', 4, 1, '14K', 0.280, 'Fixed', 750000, 2550000, NULL, NULL, 0, 'Active'),
(222, 'BTBZ018', N'Bông tai Vàng 14K', N'Bông tai BTBZ018', 'bong-tai-btbz018', 4, 1, '14K', 1.090, 'Fixed', 2550000, 5721000, NULL, NULL, 0, 'Active'),
(223, 'BTZ007', N'Bông tai Vàng 10K', N'Bông tai BTZ007A', 'bong-tai-btz007a', 4, 1, '10K', 0.300, 'Fixed', 750000, 2260000, NULL, NULL, 0, 'Active'),
(224, 'BTZ008', N'Bông tai Vàng 10K', N'Bông tai BTZ008A', 'bong-tai-btz008a', 4, 1, '10K', 0.350, 'Fixed', 1540000, 2198000, NULL, NULL, 0, 'Active'),
(225, 'BTZ009', N'Bông tai Vàng 10K', N'Bông tai BTZ009', 'bong-tai-btz009', 4, 1, '10K', 0.330, 'Fixed', 750000, 1223000, NULL, NULL, 0, 'Active'),
(226, 'BTZ010', N'Bông tai Vàng 10K', N'Bông tai BTZ010A', 'bong-tai-btz010', 4, 1, '10K', 0.320, 'Fixed', 750000, 1109000, NULL, NULL, 0, 'Active'),
(227, 'BTBAC01', N'Bạc 925 mạ vàng', N'Bông tai BTBAC01', 'bong-tai-btbac01', 4, 1, 'BAC925', 0.350, 'Fixed', NULL, 329400, 366000, NULL, 0, 'Active'),
(228, 'BTBAC02', N'Bạc 925 mạ vàng', N'Bông tai BTBAC02', 'bong-tai-btbac02', 4, 1, 'BAC925', 0.340, 'Fixed', NULL, 294300, 327000, NULL, 0, 'Active'),
(229, 'BTBAC04', N'Bạc 925 mạ vàng', N'Bông tai BTBAC04', 'bong-tai-btbac04', 4, 1, 'BAC925', 0.320, 'Fixed', NULL, 299700, 333000, NULL, 0, 'Active'),
(230, 'BTBAC05', N'Bạc 925 mạ vàng', N'Bông tai BTBAC05', 'bong-tai-btbac05', 4, 1, 'BAC925', 0.330, 'Fixed', NULL, 289800, 322000, NULL, 0, 'Active'),
(231, 'BTBAC08', N'Bạc 925 mạ vàng', N'Bông tai BTBAC08', 'bong-tai-btbac08', 4, 1, 'BAC925', 0.360, 'Fixed', NULL, 360000, 400000, NULL, 0, 'Active'),
(232, 'BTBAC09', N'Bạc 925 mạ vàng', N'Bông tai BTBAC09', 'bong-tai-btbac09', 4, 1, 'BAC925', 0.500, 'Fixed', NULL, 488700, 543000, NULL, 0, 'Active'),
(233, 'BTBAC11', N'Bạc 925 mạ vàng', N'Bông tai BTBAC11', 'bong-tai-btbac11', 4, 1, 'BAC925', 0.540, 'Fixed', NULL, 414000, 460000, NULL, 0, 'Active'),
(234, 'BTBAC12', N'Bạc 925 mạ vàng', N'Bông tai BTBAC12', 'bong-tai-btbac12', 4, 1, 'BAC925', 0.460, 'Fixed', NULL, 392400, 436000, NULL, 0, 'Active'),
(235, 'BTBAC13', N'Bạc 925 mạ vàng', N'Bông tai BTBAC13', 'bong-tai-btbac13', 4, 1, 'BAC925', 0.530, 'Fixed', NULL, 418500, 465000, NULL, 0, 'Active'),
(236, 'BTBAC14', N'Bạc 925 mạ vàng', N'Bông Tai BTBAC14', 'btbac14', 4, 1, 'BAC925', NULL, 'Fixed', NULL, 422100, 469000, NULL, 0, 'Active'),
(237, 'BTBBAC01', N'Bạc 925 mạ vàng', N'Bông tai BTBBAC01', 'bong-tai-btbbac01', 4, 1, 'BAC925', 0.500, 'Fixed', NULL, 396900, 441000, NULL, 0, 'Active'),
(238, 'BTBBAC02', N'Bạc 925 mạ vàng', N'Bông tai BTBBAC02', 'bong-tai-btbbac02', 4, 1, 'BAC925', 0.520, 'Fixed', NULL, 449100, 499000, NULL, 0, 'Active'),
(239, 'BTBBAC03', N'Bạc 925 mạ vàng', N'Bông tai BTBBAC03', 'bong-tai-btbbac03', 4, 1, 'BAC925', 0.440, 'Fixed', NULL, 399600, 444000, NULL, 0, 'Active'),
(240, 'BTBBAC04', N'Bạc 925 mạ vàng', N'Bông tai BTBBAC04', 'bong-tai-btbbac04', 4, 1, 'BAC925', 0.610, 'Fixed', NULL, 510300, 567000, NULL, 0, 'Active'),
(241, 'BTBBAC05', N'Bạc 925 mạ vàng', N'Bông tai BTBBAC05', 'bong-tai-btbbac05', 4, 1, 'BAC925', 0.510, 'Fixed', NULL, 457200, 508000, NULL, 0, 'Active'),
(242, 'BTBTCC109', N'Bông tai Vàng 10K Ngọc trai', N'Bông tai BTBTCC109', 'bong-tai-btbtcc109', 4, 1, '10K', NULL, 'Fixed', 2550000, 5080000, NULL, NULL, 0, 'Active'),
(243, 'BTBTCC110', N'Bông tai Vàng 10K Ngọc trai', N'Bông Tai BTBTCC110', 'bong-tai-btbtcc110', 4, 1, '10K', 1.070, 'Fixed', 750000, 4971000, NULL, NULL, 0, 'Active'),
(244, 'BTBTCC83', N'Bông tai Vàng 14K Ngọc trai', N'Bông tai BTBTCC83', 'bong-tai-btbtcc-83', 4, 1, '14K', 1.450, 'Fixed', NULL, 4304000, NULL, NULL, 0, 'Active'),
(245, 'BTBTCC85', N'Bông tai Vàng 14K Ngọc trai', N'Bông tai BTBTCC85', 'bong-tai-btbtcc-85', 4, 1, '14K', 1.490, 'Fixed', 750000, 5565000, NULL, N'Thiết kế tối giản, kết hợp giữa vàng hồng và ngọc trai trắng. Sự tương phản giữa sắc vàng hồng ấm áp và sự thanh khiết của ngọc trai trắng, mang đến cảm giác hiện đại, trẻ trung. Bông tai này là lựa chọn lý tưởng cho những ai yêu thích phong cách tối giản và tinh tế. Sản phẩm phù hợp với đa dạng phong cách, khi đeo dây chuyền và bông tai theo bộ sẽ tôn lên vẻ đẹp hoàn hảo và cuốn hút nhất. Đặc biệt, sản phẩm phù hợp để cô dâu kết hợp cùng áo dài và váy cưới.', 0, 'Active'),
(246, 'BTBTCC86', N'Bông tai Vàng 14K Ngọc trai', N'Bông tai BTBTCC86', 'bong-tai-btbtcc-86', 4, 1, '14K', 2.040, 'Fixed', 2550000, 5892000, NULL, N'Lấy cảm hứng từ sự cân bằng hài hòa giữa thiên nhiên và biển cả, với hình ảnh mặt trời rực rỡ bên cạnh viên ngọc trai tròn. Viên đá chủ lấp lánh được bao quanh vòng đá tấm, làm điểm nhấn nổi bật cho chất liệu ngọc trai thanh lịch. 
Sản phẩm phù hợp với đa dạng phong cách, khi đeo dây chuyền và bông tai theo bộ sẽ tôn lên vẻ đẹp hoàn hảo và cuốn hút nhất.
Đặc biệt, sản phẩm phù hợp để cô dâu kết hợp cùng áo dài và váy cưới.', 0, 'Active'),
(247, 'BTBTCC88', N'Bông tai Vàng 14K Ngọc trai', N'Bông tai BTBTCC88', 'bong-tai-btbtcc-88', 4, 1, '14K', 1.860, 'Fixed', 2550000, 5987000, NULL, NULL, 0, 'Active'),
(248, 'BTBZ030', N'Bông tai Vàng 24K', N'Bông tai BTBZ030', 'bong-tai-btbz030', 4, 1, '24K', 1.600, 'GoldRate', 1000000, NULL, NULL, NULL, 0, 'Active'),
(249, 'BTBTCC112', N'Bông tai Vàng 10K Ngọc trai J-Rabbit', N'Bông Tai BTBTCC112', 'bong-tai-btbtcc112', 4, 1, '10K', 1.390, 'Fixed', 1450000, 6080000, NULL, NULL, 0, 'Active'),
(250, 'BTBZ050', N'Bông tai Vàng 10K đá Màu Magic Snow', N'Bông tai BTBZ050', 'bong-tai-btbz050', 4, 1, '10K', 1.300, 'Fixed', 2550000, 4484000, NULL, NULL, 0, 'Active'),
(251, 'BTBZ051', N'Bông tai Vàng 10K đá Màu Jingle Glow', N'Bông tai BTBZ051', 'bong-tai-btbz051', 4, 1, '10K', 0.920, 'Fixed', 2550000, 3205000, NULL, NULL, 0, 'Active'),
(252, 'BTBZ052', N'Bông tai Vàng 10K đá Màu Santa Gift', N'Bông tai BTBZ052', 'bong-tai-btbz052', 4, 1, '10K', 0.740, 'Fixed', 2550000, 2739000, NULL, NULL, 0, 'Active'),
(253, 'BTBZ053', N'Bông tai Vàng 10K đá Màu Twinkle Snow', N'Bông tai BTBZ053', 'bong-tai-btbz053', 4, 1, '10K', 1.000, 'Fixed', 2550000, 3139000, NULL, NULL, 0, 'Active'),
(254, 'BTBZ056', N'Bông tai Vàng 10K Little Aura', N'Bông tai BTBZ056', 'bong-tai-btbz056', 4, 1, '10K', 1.000, 'Fixed', 1450000, 3224000, NULL, NULL, 0, 'Active'),
(255, 'BTPTB421', N'Bông tai Vàng 10K đá CZ Bunny Treat', N'Bông tai Printemps BTPTB421', 'bong-tai-printemps-btptb421', 4, 1, '10K', 0.620, 'Fixed', 2550000, 2396000, NULL, NULL, 0, 'Active'),
(256, 'BTBKC033', N'Bông tai Vàng 10K Đá màu thiên nhiên', N'Bông Tai BTBKC033', 'bong-tai-btbkc033', 4, 1, '10K', 1.270, 'Fixed', 2550000, 7167000, NULL, NULL, 0, 'Active'),
(257, 'BTBKC034', N'Bông tai Vàng 10K Đá màu thiên nhiên', N'Bông Tai BTBKC034', 'bong-tai-btbkc034', 4, 1, '10K', 1.110, 'Fixed', 2550000, 6654000, NULL, NULL, 0, 'Active'),
(258, 'BTBKC035', N'Bông tai Vàng 10K Đá màu thiên nhiên', N'Bông Tai BTBKC035', 'bong-tai-btbkc035', 4, 1, '10K', 1.660, 'Fixed', 2550000, 8259000, NULL, NULL, 0, 'Active'),
(259, 'BTBKC036', N'Bông tai Vàng 10K Đá màu thiên nhiên', N'Bông Tai BTBKC036', 'bong-tai-btbkc036', 4, 1, '10K', 1.260, 'Fixed', 2550000, 5303000, NULL, NULL, 0, 'Active'),
(260, 'BTBKC037', N'Bông tai Vàng 10K Đá màu thiên nhiên', N'Bông Tai BTBKC037', 'bong-tai-btbkc037', 4, 1, '10K', 1.080, 'Fixed', 2550000, 6070000, NULL, NULL, 0, 'Active'),
(261, 'BTBKC038', N'Bông tai Vàng 10K Đá màu thiên nhiên', N'Bông Tai BTBKC038', 'bong-tai-btbkc038', 4, 1, '10K', 1.100, 'Fixed', 2550000, 4443000, NULL, NULL, 0, 'Active'),
(262, 'BTBKC039', N'Bông tai Vàng 10K Đá màu thiên nhiên', N'Bông Tai BTBKC039', 'bong-tai-btbkc039', 4, 1, '10K', 1.060, 'Fixed', 750000, 6672000, NULL, NULL, 0, 'Active'),
(263, 'BTBKC040', N'Bông tai Vàng 10K Đá màu thiên nhiên', N'Bông Tai BTBKC040', 'bong-tai-btbkc040', 4, 1, '10K', 1.040, 'Fixed', 2550000, 5850000, NULL, NULL, 0, 'Active'),
(264, 'BTBZ040', N'Bông tai Vàng 10K đá Màu', N'Bông tai BTBZ040', 'bong-tai-btbz040', 4, 1, '10K', 1.560, 'Fixed', 1450000, 5280000, NULL, NULL, 0, 'Active'),
(265, 'BTBZ041', N'Bông tai Vàng 10K đá Màu', N'Bông tai BTBZ041', 'bong-tai-btbz041', 4, 1, '10K', NULL, 'Fixed', 750000, 5705000, NULL, NULL, 0, 'Active'),
(266, 'BTBZ043', N'Bông tai Vàng 10K đá Màu', N'Bông tai BTBZ043', 'bong-tai-btbz043', 4, 1, '10K', NULL, 'Fixed', NULL, 2058000, NULL, N'2205', 0, 'Active'),
(267, 'BTAM140', N'Bông tai Vàng 10K đá Xà cừ', N'Bông tai BTAM140', 'bong-tai-am-btam140', 4, 1, '10K', 0.100, 'Fixed', 2550000, 836000, NULL, NULL, 0, 'Active'),
(268, 'BTPTB390', N'Bông tai Vàng 14K đá mother of pearl hình hoa 4 cánh', N'Bông tai Printemps BTPTB390', 'bong-tai-printemps-btptb390', 4, 1, '14K', 1.260, 'Fixed', 550000, 6697000, NULL, NULL, 0, 'Active'),
(269, 'BTPTB412', N'Bông tai Vàng 10K đá Xà cừ', N'Bông tai Printemps BTPTB412', 'bong-tai-printemps-btptb412', 4, 1, '10K', 1.530, 'Fixed', 750000, 4925000, NULL, NULL, 0, 'Active'),
(270, 'DCB02', N'Dây chuyền Vàng 14K', N'Dây chuyền DCB02', 'day-chuyen-dcb02', 5, 1, '14K', 8.980, 'Fixed', 2400000, 37710000, 41900000, NULL, 0, 'Active'),
(271, 'DCBZ067', N'Dây chuyền Vàng 10K đá CZ', N'Dây chuyền DCBZ067', 'day-chuyen-dcbz067', 5, 1, '10K', 1.390, 'Fixed', 2400000, 4337100, 4819000, NULL, 0, 'Active'),
(272, 'DCMAMD679', N'Dây chuyền Vàng 14K đá CZ', N'Dây chuyền DCMAMD679', 'day-chuyen-dcmamd679', 5, 1, '14K', 2.380, 'Fixed', NULL, 9725400, 10806000, N'Lấy cảm hứng từ hình tượng hồ ly - biểu tượng của sự thông minh, quyến rũ và bí ẩn. Các đường nét chế tác tinh xảo, Hình ảnh hồ ly đội vương miện tôn lên vẻ kiêu sa, quyền lực. Dải đá tấm bao quanh như cổ áo nữ hoàng, tạo điểm nhấn rực rỡ và thu hút. Sản phẩm phù hợp với những bộ trang phục cá tính và quyến rũ', 0, 'Active'),
(273, 'DCMAMD681', N'Dây chuyền Vàng 14K đá CZ', N'Dây chuyền DCMAMD681', 'day-chuyen-dcmamd-681', 5, 1, '14K', 1.940, 'Fixed', NULL, 9920700, 11023000, N'Thiết kế độc đáo với hai chú thiên nga chụm đầu tạo thành trái tim, biểu tượng cho tình yêu vĩnh cửu và sự chung thủy. Viên đá trung tâm lấp lánh làm điểm nhấn, tượng trưng cho tình yêu duy nhất, gắn kết trọn đời.
Sản phẩm dễ dàng kết hợp với đa dạng trang phục, phong cách.', 0, 'Active'),
(274, 'DCPTB345', N'Dây chuyền Vàng 14K đá CZ', N'Dây chuyền DCPTB345', 'day-chuyen-dcptb-345', 5, 1, '14K', 1.980, 'Fixed', 650000, 8106300, 9007000, NULL, 0, 'Active'),
(275, 'DCZ050', N'Dây chuyền Vàng 14K đá CZ', N'Dây chuyền DCZ050', 'day-chuyen-dcz050', 5, 1, '14K', NULL, 'Fixed', 2440000, 8010900, 8901000, NULL, 0, 'Active'),
(276, 'DCZ085', N'Dây chuyền Vàng 14K', N'Dây chuyền DCZ085', 'day-chuyen-dcz085', 5, 1, '14K', 1.690, 'Fixed', 2200000, 8090100, 8989000, NULL, 0, 'Active'),
(277, 'DCZ124', N'Dây chuyền Vàng 10K đá CZ', N'Dây chuyền DCZ124', 'day-chuyen-dcz124', 5, 1, '10K', 1.180, 'Fixed', 2400000, 3841200, 4268000, NULL, 0, 'Active'),
(278, 'DCBZ021', N'Dây chuyền Vàng 14K', N'Dây chuyền DCBZ021', 'day-chuyen-dcbz021', 5, 1, '14K', 1.650, 'Fixed', 2440000, 7139700, 7933000, NULL, 0, 'Active'),
(279, 'DCPTB417', N'Dây chuyền Vàng 10K', N'Dây chuyền DCPTB417', 'day-chuyen-dcptb417', 5, 1, '10K', NULL, 'Fixed', NULL, 6127000, NULL, NULL, 0, 'Active'),
(280, 'DCPTB418', N'Dây chuyền Vàng 10K', N'Dây chuyền DCPTB418', 'day-chuyen-dcptb418', 5, 1, '10K', NULL, 'Fixed', NULL, 7663000, NULL, NULL, 0, 'Active'),
(281, 'DCZ043', N'Dây chuyền Vàng 14K', N'Dây chuyền DCZ043', 'day-chuyen-dcz043', 5, 1, '14K', 1.980, 'Fixed', NULL, 8218800, 9132000, NULL, 0, 'Active'),
(282, 'DCZ058', N'Dây chuyền Vàng 14K', N'Dây chuyền DCZ058', 'day-chuyen-dcz058', 5, 1, '14K', 1.820, 'Fixed', NULL, 8642700, 9603000, NULL, 0, 'Active'),
(283, 'DCZ093', N'Dây chuyền Bạc 925', N'Dây chuyền DCZ093', 'day-chuyen-dcz093', 5, 1, 'BAC925', 1.390, 'Fixed', NULL, 518400, 576000, NULL, 0, 'Active'),
(284, 'DCZ096', N'Dây chuyền Bạc 925', N'Dây chuyền DCZ096', 'day-chuyen-dcz096', 5, 1, 'BAC925', 1.410, 'Fixed', NULL, 547200, 608000, NULL, 0, 'Active'),
(285, 'DCZ097', N'Dây chuyền Bạc 925', N'Dây chuyền DCZ097', 'day-chuyen-dcz097', 5, 1, 'BAC925', 1.460, 'Fixed', NULL, 554400, 616000, NULL, 0, 'Active'),
(286, 'DCZ122', N'Dây chuyền Vàng 10K', N'Dây chuyền DCZ122', 'day-chuyen-dcz122', 5, 1, '10K', 1.220, 'Fixed', 2400000, 3673800, 4082000, NULL, 0, 'Active'),
(287, 'DCBAC01', N'Bạc 925 mạ vàng', N'Dây chuyền DCBAC01', 'day-chuyen-dcbac01', 5, 1, 'BAC925', 0.860, 'Fixed', NULL, 556200, 618000, NULL, 0, 'Active'),
(288, 'DCBAC03', N'Bạc 925 mạ vàng', N'Dây chuyền DCBAC03', 'day-chuyen-dcbac03', 5, 1, 'BAC925', 0.890, 'Fixed', NULL, 563400, 626000, NULL, 0, 'Active'),
(289, 'DCBBAC11', N'Bạc 925 mạ vàng', N'Dây chuyền DCBBAC11', 'day-chuyen-dcbbac11', 5, 1, 'BAC925', 1.040, 'Fixed', NULL, 629100, 699000, NULL, 0, 'Active'),
(290, 'DCBBAC12', N'Bạc 925 mạ vàng', N'Dây chuyền DCBBAC12', 'day-chuyen-dcbbac12', 5, 1, 'BAC925', 1.040, 'Fixed', NULL, 619200, 688000, NULL, 0, 'Active'),
(291, 'DCBTCC83', N'Dây chuyền Vàng 14K Ngọc trai', N'Dây chuyền DCBTCC83', 'day-chuyen-dcbtcc-83', 5, 1, '14K', 1.890, 'Fixed', NULL, 6708600, 7454000, NULL, 0, 'Active'),
(292, 'DCBTCC84', N'Dây chuyền Vàng 14K Ngọc trai', N'Dây chuyền DCBTCC84', 'day-chuyen-dcbtcc-84', 5, 1, '14K', 1.740, 'Fixed', NULL, 6076800, 6752000, NULL, 0, 'Active'),
(293, 'DCBTCC85', N'Dây chuyền Vàng 14K Ngọc trai', N'Dây chuyền DCBTCC85', 'day-chuyen-dcbtcc-85', 5, 1, '14K', 1.870, 'Fixed', NULL, 6713100, 7459000, N'Thiết kế tối giản, kết hợp giữa vàng hồng và ngọc trai trắng. Sự tương phản giữa sắc vàng hồng ấm áp và sự thanh khiết của ngọc trai trắng, mang đến cảm giác hiện đại, trẻ trung. Dây chuyền này là lựa chọn lý tưởng cho những ai yêu thích phong cách tối giản và tinh tế. Sản phẩm phù hợp với đa dạng phong cách, khi đeo dây chuyền và bông tai theo bộ sẽ tôn lên vẻ đẹp hoàn hảo và cuốn hút nhất. Đặc biệt, sản phẩm phù hợp để cô dâu kết hợp cùng áo dài và váy cưới.', 0, 'Active'),
(294, 'DCBTCC86', N'Dây chuyền Vàng 14K Ngọc trai', N'Dây chuyền DCBTCC86', 'day-chuyen-dcbtcc-86', 5, 1, '14K', 2.140, 'Fixed', NULL, 8801100, 9779000, N'Lấy cảm hứng từ sự cân bằng hài hòa giữa thiên nhiên và biển cả, với hình ảnh mặt trời rực rỡ bên cạnh viên ngọc trai tròn. Viên đá chủ lấp lánh được bao quanh vòng đá tấm, làm điểm nhấn nổi bật cho chất liệu ngọc trai thanh lịch. 
Sản phẩm phù hợp với đa dạng phong cách, khi đeo dây chuyền và bông tai theo bộ sẽ tôn lên vẻ đẹp hoàn hảo và cuốn hút nhất.
Đặc biệt, sản phẩm phù hợp để cô dâu kết hợp cùng áo dài và váy cưới.', 0, 'Active'),
(295, 'DCBZ046', N'Dây chuyền Vàng 10K Ngọc Trai', N'Dây chuyền DCBZ046', 'day-chuyen-dcbz046', 5, 1, '10K', 1.310, 'Fixed', 2900000, 5277600, 5864000, NULL, 0, 'Active'),
(296, 'DCZ100', N'Dây chuyền Vàng 10K Ngọc Trai', N'Dây chuyền DCZ100', 'day-chuyen-dcz100', 5, 1, '10K', 1.330, 'Fixed', 2900000, 5120000, NULL, NULL, 0, 'Active'),
(297, 'DCBZ050', N'Dây chuyền Vàng 10K đá Màu Magic Snow', N'Dây chuyền DCBZ050', 'day-chuyen-dcbz050', 5, 1, '10K', 1.610, 'Fixed', 2440000, 5271300, 5857000, NULL, 0, 'Active'),
(298, 'DCBZ053', N'Dây chuyền Vàng 10K đá Màu Twinkle Snow', N'Dây chuyền DCBZ053', 'day-chuyen-dcbz053', 5, 1, '10K', 1.530, 'Fixed', 2440000, 4981500, 5535000, NULL, 0, 'Active'),
(299, 'DCBZ056', N'Dây chuyền Vàng 10K đá CZ Little Aura', N'Dây chuyền DCBZ056', 'day-chuyen-dcbz056', 5, 1, '10K', 1.860, 'Fixed', 2440000, 6355800, 7062000, NULL, 0, 'Active'),
(300, 'DCZ099', N'Dây chuyền Vàng 10K đá Màu Magic Glow', N'Dây chuyền DCZ099', 'day-chuyen-dcz099', 5, 1, '10K', 1.330, 'Fixed', 2440000, 4441500, 4935000, NULL, 0, 'Active');
INSERT INTO dbo.Products (ProductID, SKU, ProductName, ShortName, Slug, CategoryID, WarrantyPolicyID, Material, WeightGram, PricingMethod, LaborPrice, Price, OriginalPrice, Description, IsEngravable, Status) VALUES
(301, 'DCZ101', N'Dây chuyền Vàng 10K Twinkle Bun', N'Dây chuyền DCZ101', 'day-chuyen-dcz101', 5, 1, '10K', 1.250, 'Fixed', 450000, 4077900, 4531000, NULL, 0, 'Active'),
(302, 'DCZ102', N'Dây chuyền Vàng 10K Sweet Tokki', N'Dây chuyền DCZ102', 'day-chuyen-dcz102', 5, 1, '10K', 1.200, 'Fixed', 450000, 3909600, 4344000, NULL, 0, 'Active'),
(303, 'DCZ103', N'Dây chuyền Vàng 10K Candy Bell', N'Dây chuyền DCZ103', 'day-chuyen-dcz103', 5, 1, '10K', 1.170, 'Fixed', 450000, 3807000, 4230000, NULL, 0, 'Active'),
(304, 'DCZ104', N'Dây chuyền Vàng 10K đá CZ Snow Rabbit', N'Dây chuyền DCZ104', 'day-chuyen-dcz104', 5, 1, '10K', 1.550, 'Fixed', 2440000, 5253300, 5837000, NULL, 0, 'Active'),
(305, 'DCZ105', N'Dây chuyền Vàng 10K Carrot Pie', N'Dây chuyền DCZ105', 'day-chuyen-dcz105', 5, 1, '10K', 1.860, 'Fixed', NULL, 6149700, 6833000, NULL, 0, 'Active'),
(306, 'DCMAMD811', N'Dây chuyền Vàng 14K đá Màu', N'Dây chuyền DCMAMD811', 'day-chuyen-dcmamd811', 5, 1, '14K', NULL, 'Fixed', NULL, 7653600, 8504000, NULL, 0, 'Active'),
(307, 'DCMAMD813', N'Dây chuyền Vàng 14K đá Màu', N'Dây chuyền DCMAMD813', 'day-chuyen-dcmamd813', 5, 1, '14K', NULL, 'Fixed', NULL, 9284400, 10316000, NULL, 0, 'Active'),
(308, 'DCMAMD814', N'Dây chuyền Vàng 14K đá Màu', N'Dây chuyền DCMAMD814', 'day-chuyen-dcmamd814', 5, 1, '14K', NULL, 'Fixed', NULL, 8964000, 9960000, NULL, 0, 'Active'),
(309, 'DCMAMD829', N'Dây chuyền Vàng 10K đá Xà cừ', N'Dây chuyền DCMAMD829', 'day-chuyen-dcmamd829', 5, 1, '10K', 1.610, 'Fixed', 1000000, 5880000, NULL, NULL, 0, 'Active'),
(310, 'DCPTB405', N'Dây chuyền Vàng 14K đá Xà cừ', N'Dây chuyền DCPTB405', 'day-chuyen-dcptb405', 5, 1, '14K', NULL, 'Fixed', 1850000, 7755300, 8617000, NULL, 0, 'Active'),
(311, 'DCPTB413', N'Dây chuyền Vàng 10K đá Xà cừ', N'Dây chuyền DCPTB413', 'day-chuyen-dcptb413', 5, 1, '10K', 1.580, 'Fixed', 1850000, 5129100, 5699000, NULL, 0, 'Active'),
(312, 'DCMAMD827', N'Dây chuyền Vàng 10K đá Malachite', N'Dây chuyền DCMAMD827', 'day-chuyen-dcmamd827', 5, 1, '10K', 1.990, 'Fixed', 1000000, 7354000, NULL, NULL, 0, 'Active'),
(313, 'DCZ086LDIA', N'Dây chuyền Vàng 14K Kim cương Lab-grown', N'Dây chuyền DCZ086LDIA', 'day-chuyen-dcz086ldia', 5, 1, '14K', NULL, 'Fixed', 1850000, 8452000, NULL, NULL, 0, 'Active'),
(314, 'DCBZ033', N'Dây chuyền Vàng 10K Ngọc Trai Rina', N'Dây chuyền DCBZ033', 'day-chuyen-dcbz033', 5, 1, '10K', NULL, 'Fixed', 1850000, 4242600, 4714000, NULL, 0, 'Active'),
(315, 'MDBZ022', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây MDBZ022', 'mat-day-mdbz022', 6, 1, '14K', 0.560, 'Fixed', 850000, 2889000, 3210000, NULL, 0, 'Active'),
(316, 'MDMAMD657', N'Mặt dây Vàng 14K đá CZ', N'Mặt dây MDMAMD657', 'mat-day-mdmamd657', 6, 1, '14K', 0.540, 'Fixed', NULL, 2246400, 2496000, NULL, 0, 'Active'),
(317, 'MDMAMD659', N'Mặt dây Vàng 14K đá CZ', N'Mặt dây MDMAMD659', 'mat-day-mdmamd-659', 6, 1, '14K', 0.810, 'Fixed', NULL, 3412800, 3792000, NULL, 0, 'Active'),
(318, 'MDMAMD660', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây MDMAMD660', 'mat-day-mdmamd-660', 6, 1, '14K', 0.790, 'Fixed', 530000, 3464100, 3849000, NULL, 0, 'Active'),
(319, 'MDMAMD664', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây MDMAMD664', 'mat-day-mdmamd-664', 6, 1, '14K', 0.910, 'Fixed', 530000, 4221000, 4690000, NULL, 0, 'Active'),
(320, 'MDMAMD665', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây MDMAMD665', 'mat-day-mdmamd-665', 6, 1, '14K', 0.930, 'Fixed', 530000, 3990600, 4434000, NULL, 0, 'Active'),
(321, 'MDMAMD667', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây MDMAMD667', 'mat-day-mdmamd-667', 6, 1, '14K', 1.030, 'Fixed', 530000, 4270500, 4745000, NULL, 0, 'Active'),
(322, 'MDMAMD675B', N'Mặt dây chuyền Vàng 14K Đá tự nhiên Ruby', N'Mặt dây MDMAMD675B', 'mat-day-mdmamd675b', 6, 1, '14K', 0.700, 'Fixed', 530000, 4003200, 4448000, NULL, 0, 'Active'),
(323, 'MDMAMD676B', N'Mặt dây chuyền Vàng 14K Đá tự nhiên Sapphire', N'Mặt dây MDMAMD676B', 'mat-day-mdmamd-676b', 6, 1, '14K', 0.800, 'Fixed', 530000, 4332600, 4814000, NULL, 0, 'Active'),
(324, 'MDMAMD677B', N'Mặt dây chuyền Vàng 14K Đá tự nhiên Sapphire', N'Mặt dây MDMAMD677B', 'mat-day-mdmamd-677b', 6, 1, '14K', 0.730, 'Fixed', 530000, 3322800, 3692000, NULL, 0, 'Active'),
(325, 'MDMAMD680', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây MDMAMD680', 'mat-day-mdmamd-680', 6, 1, '14K', 1.360, 'Fixed', 530000, 5515200, 6128000, NULL, 0, 'Active'),
(326, 'MDMAMD688', N'Mặt dây chuyền Vàng 14K Đá tự nhiên Sapphire', N'Mặt dây MDMAMD688', 'mat-day-mdmamd-688', 6, 1, '14K', 0.700, 'Fixed', 530000, 5321700, 5913000, NULL, 0, 'Active'),
(327, 'MDMAMD689', N'Mặt dây chuyền Vàng 14K Đá tự nhiên Sapphire', N'Mặt dây MDMAMD689', 'mat-day-mdmamd-689', 6, 1, '14K', 0.740, 'Fixed', 530000, 4373100, 4859000, NULL, 0, 'Active'),
(328, 'MDMAMD690', N'Mặt dây chuyền Vàng 14K Đá tự nhiên Sapphire', N'Mặt dây MDMAMD690', 'mat-day-mdmamd-690', 6, 1, '14K', 0.740, 'Fixed', 530000, 4720500, 5245000, NULL, 0, 'Active'),
(329, 'MDMAMD691', N'Mặt dây chuyền Vàng 14K Đá tự nhiên Sapphire', N'Mặt dây MDMAMD691', 'mat-day-mdmamd-691', 6, 1, '14K', 0.700, 'Fixed', 560000, 5030100, 5589000, NULL, 0, 'Active'),
(330, 'MDMAMD692', N'Mặt dây chuyền Vàng 14K Đá tự nhiên Tsavorite', N'Mặt dây MDMAMD692', 'mat-day-mdmamd-692', 6, 1, '14K', 0.710, 'Fixed', 530000, 4854600, 5394000, NULL, 0, 'Active'),
(331, 'MDMAMD693', N'Mặt dây chuyền Vàng 14K Đá tự nhiên Ruby', N'Mặt dây MDMAMD693', 'mat-day-mdmamd-693', 6, 1, '14K', 0.740, 'Fixed', 530000, 5868000, 6520000, NULL, 0, 'Active'),
(332, 'MDPTB342', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây chuyền MDPTB342', 'mat-day-mdptb-342', 6, 1, '14K', 0.620, 'Fixed', 560000, 2770200, 3078000, NULL, 0, 'Active'),
(333, 'MDPTB349', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây chuyền MDPTB349', 'mat-day-mdptb-349', 6, 1, '14K', 0.660, 'Fixed', 560000, 2784600, 3094000, NULL, 0, 'Active'),
(334, 'MDPTB351', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây chuyền MDPTB351', 'mat-day-mdptb-351', 6, 1, '14K', 1.260, 'Fixed', 560000, 4698000, 5220000, NULL, 0, 'Active'),
(335, 'MDPTB352', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây chuyền MDPTB352', 'mat-day-mdptb-352', 6, 1, '14K', 1.140, 'Fixed', 560000, 3872700, 4303000, NULL, 0, 'Active'),
(336, 'MDZ059', N'Mặt dây chuyền Vàng 14K đá CZ', N'Mặt dây MDZ059', 'mat-day-mdz059', 6, 1, '14K', 0.940, 'Fixed', 850000, 4358700, 4843000, N'5.234.000', 0, 'Active'),
(337, 'MDZ033', N'Mặt dây chuyền Vàng 14K', N'Mặt dây MDZ033', 'mat-day-mdz033', 6, 1, '14K', 0.550, 'Fixed', 530000, 2567700, 2853000, NULL, 0, 'Active'),
(338, 'MDZ035', N'Mặt dây chuyền Vàng 14K', N'Mặt dây MDZ035', 'mat-day-mdz035', 6, 1, '14K', 1.150, 'Fixed', 530000, 4648500, 5165000, NULL, 0, 'Active'),
(339, 'MDZ057', N'Mặt dây chuyền Vàng 14K', N'Mặt dây MDZ057', 'mat-day-mdz057', 6, 1, '14K', 0.980, 'Fixed', 750000, 3261600, 3624000, NULL, 0, 'Active'),
(340, 'MDZ076', N'Mặt dây Vàng 22K', N'Mặt dây MDZ076', 'mat-day-mdz076', 6, 1, '22K', 1.770, 'GoldRate', 850000, NULL, NULL, NULL, 0, 'Active'),
(341, 'MDBZ036', N'Mặt dây Vàng 24K', N'Mặt dây MDBZ036', 'mat-day-mdbz036', 6, 1, '24K', 0.810, 'GoldRate', 550000, NULL, NULL, NULL, 0, 'Active'),
(342, 'MDBZ038', N'Mặt dây Vàng 24K', N'Mặt dây MDBZ038', 'mat-day-mdbz038', 6, 1, '24K', 0.740, 'GoldRate', 370000, NULL, NULL, NULL, 0, 'Active'),
(343, 'MDBZ039', N'Mặt dây Vàng 24K', N'Mặt dây MDBZ039', 'mat-day-mdbz039', 6, 1, '24K', 0.810, 'GoldRate', 450000, NULL, NULL, NULL, 0, 'Active'),
(344, 'MDZ077', N'Mặt dây Vàng 24K', N'Mặt dây MDZ077', 'mat-day-mdz077', 6, 1, '24K', 1.710, 'GoldRate', 700000, NULL, NULL, NULL, 0, 'Active'),
(345, 'MDZ079', N'Mặt dây Vàng 24K', N'Mặt dây MDZ079', 'mat-day-mdz079', 6, 1, '24K', 1.020, 'GoldRate', 550000, NULL, NULL, NULL, 0, 'Active'),
(346, 'MDZ080', N'Mặt dây Vàng 24K', N'Mặt dây MDZ080', 'mat-day-mdz080', 6, 1, '24K', 1.840, 'GoldRate', 560000, NULL, NULL, NULL, 0, 'Active'),
(347, 'MDZ082', N'Mặt dây Vàng 24K', N'Mặt dây MDZ082', 'mat-day-mdz082', 6, 1, '24K', 1.200, 'GoldRate', 470000, NULL, NULL, N'470.000', 0, 'Active'),
(348, 'MDZ083', N'Mặt dây Vàng 24K', N'Mặt dây MDZ083', 'mat-day-mdz083', 6, 1, '24K', 0.930, 'GoldRate', 440000, NULL, NULL, NULL, 0, 'Active'),
(349, 'MDZ084', N'Mặt dây Vàng 24K', N'Mặt dây MDZ084', 'mat-day-mdz084', 6, 1, '24K', 1.270, 'GoldRate', 750000, NULL, NULL, NULL, 0, 'Active'),
(350, 'MDZ085', N'Mặt dây Vàng 24K', N'Mặt dây MDZ085', 'mat-day-mdz085', 6, 1, '24K', 1.010, 'GoldRate', 550000, NULL, NULL, NULL, 0, 'Active'),
(351, 'MDZ086', N'24K đá CZ', N'Mặt dây MDZ086', 'mat-day-mdz086', 6, 1, '24K', 3.260, 'GoldRate', 1240000, NULL, NULL, NULL, 0, 'Active'),
(352, 'MDZ087', N'Mặt dây Vàng 24K', N'Mặt dây MDZ087', 'mat-day-mdz087', 6, 1, '24K', 1.730, 'GoldRate', 680000, NULL, NULL, NULL, 0, 'Active'),
(353, 'MDZ088', N'Mặt dây Vàng 24K', N'Mặt dây MDZ088', 'mat-day-mdz088', 6, 1, '24K', 1.310, 'GoldRate', 520000, NULL, NULL, NULL, 0, 'Active'),
(354, 'MDZ089', N'Mặt dây vàng 24K', N'Mặt dây MDZ089', 'mat-day-mdz089', 6, 1, '24K', 0.640, 'GoldRate', 550000, NULL, NULL, NULL, 0, 'Active'),
(355, 'MDZ090', N'Mặt dây Vàng 24K', N'Mặt dây MDZ090', 'mat-day-mdz090', 6, 1, '24K', 1.500, 'GoldRate', 620000, NULL, NULL, NULL, 0, 'Active'),
(356, 'MDZ093', N'Mặt dây Vàng 24K', N'Mặt dây MDZ093', 'mat-day-mdz093', 6, 1, '24K', 0.990, 'GoldRate', 540000, NULL, NULL, NULL, 0, 'Active'),
(357, 'MDZ094', N'Mặt dây Vàng 24K', N'Mặt dây MDZ094', 'mat-day-mdz094', 6, 1, '24K', 1.090, 'GoldRate', 460000, NULL, NULL, NULL, 0, 'Active'),
(358, 'MDZ097', N'Mặt dây Vàng 24K', N'Mặt dây MDZ097', 'mat-day-mdz097', 6, 1, '24K', 1.310, 'GoldRate', 560000, NULL, NULL, N'560000', 0, 'Active'),
(359, 'MDBKC038', N'Mặt dây chuyền Vàng 10K Đá màu thiên nhiên', N'Mặt dây MDBKC038', 'mat-day-mdbkc038', 6, 1, '10K', 0.450, 'Fixed', 550000, 1807200, 2008000, NULL, 0, 'Active'),
(360, 'MDMAMD810', N'Mặt dây chuyền Vàng 14K đá Xà cừ', N'Mặt dây MDMAMD810', 'mat-day-mdmamd810', 6, 1, '14K', NULL, 'Fixed', NULL, 4115700, 4573000, NULL, 0, 'Active'),
(361, 'MDPTB401', N'Mặt dây chuyền Vàng 10K đá Xà cừ', N'Mặt dây chuyền MDPTB401', 'mat-day-mdptb401', 6, 1, '10K', NULL, 'Fixed', 530000, 2029500, 2255000, NULL, 0, 'Active'),
(362, 'MDZ115', N'Mặt dây chuyền Vàng 10K đá Xà cừ', N'Mặt dây MDZ115', 'mat-day-mdz115', 6, 1, '10K', 0.520, 'Fixed', 570000, 2563000, NULL, NULL, 0, 'Active'),
(363, 'MDMAMD807', N'Mặt dây chuyền Vàng 14K đá Malachite', N'Mặt dây MDMAMD807', 'mat-day-mdmamd807', 6, 1, '14K', 1.310, 'Fixed', 560000, 6875100, 7639000, NULL, 0, 'Active'),
(364, 'MDMAMD808', N'Mặt dây chuyền Vàng 14K đá mã não', N'Mặt dây MDMAMD808', 'mat-day-mdmamd808', 6, 1, '14K', 1.750, 'Fixed', 560000, 9155700, 10173000, NULL, 0, 'Active'),
(365, 'MDZ117', N'Mặt dây chuyền Vàng 10K Đá mã não', N'Mặt dây MDZ117', 'mat-day-mdz117', 6, 1, '10K', 1.110, 'Fixed', 175000, 4503000, NULL, NULL, 0, 'Active'),
(366, 'MDZ120', N'Mặt dây chuyền Vàng 10K đá Mã não', N'Mặt dây MDZ120', 'mat-day-mdz120', 6, 1, '10K', 0.940, 'Fixed', 1750000, 3376800, 3752000, NULL, 0, 'Active'),
(367, 'MDZ121', N'Mặt dây chuyền Vàng 10K đá Chalcedony tự nhiên', N'Mặt dây MDZ121', 'mat-day-mdz121', 6, 1, '10K', 0.970, 'Fixed', 1750000, 3790000, NULL, NULL, 0, 'Active'),
(368, 'MDZ122', N'Mặt dây chuyền Vàng 10K đá Lapis Lazuli', N'Mặt dây MDZ122', 'mat-day-mdz122', 6, 1, '10K', 0.590, 'Fixed', 1750000, 2383000, NULL, NULL, 0, 'Active'),
(369, 'MDZ103LDIA', N'Mặt dây Vàng 14K Kim cương Lab-grown', N'Mặt dây MDZ103LDIA', 'mat-day-mdz103ldia', 6, 1, '14K', NULL, 'Fixed', 750000, 3569000, NULL, NULL, 0, 'Active'),
(370, 'MDZ104LDIA', N'Mặt dây Vàng 14K Kim cương Lab-grown', N'Mặt dây MDZ104LDIA', 'mat-day-mdz104ldia', 6, 1, '14K', 0.690, 'Fixed', 750000, 3775000, NULL, NULL, 0, 'Active'),
(371, 'MDMAMD779', N'Mặt dây chuyền Vàng 14K đá Xà cừ', N'Mặt dây MDMAMD779', 'mat-day-mdmamd779', 6, 1, '14K', 1.010, 'Fixed', NULL, 5175000, 5750000, NULL, 0, 'Active'),
(372, 'MDMAMD780', N'Mặt dây chuyền Vàng 14K đá Xà cừ', N'Mặt dây MDMAMD780', 'mat-day-mdmamd780', 6, 1, '14K', 0.910, 'Fixed', NULL, 5000400, 5556000, NULL, 0, 'Active'),
(373, 'MDMAMD674B', N'Mặt dây chuyền Vàng 14K đá Moissanite', N'Mặt dây MDMAMD674B', 'mat-day-mdmamd-674b', 6, 1, '14K', 0.810, 'Fixed', 530000, 3830400, 4256000, NULL, 0, 'Active'),
(374, 'MDZ081', N'Mặt dây Vàng 22K', N'Mặt dây MDZ081', 'mat-day-mdz081', 6, 1, '22K', 0.630, 'GoldRate', 550000, NULL, NULL, NULL, 0, 'Active'),
(375, 'MDZ091', N'Mặt dây Vàng 22K', N'Mặt dây MDZ091', 'mat-day-mdz091', 6, 1, '22K', 1.560, 'GoldRate', 850000, NULL, NULL, NULL, 0, 'Active'),
(376, 'LLF131', N'Lắc tay Vàng 14K đá CZ', N'Lắc tay LLF131', 'lac-tay-bella-llf131', 7, 1, '14K', 1.350, 'Fixed', NULL, 6510000, NULL, NULL, 0, 'Active'),
(377, 'LLF135', N'Lắc tay Vàng 14K đá CZ', N'Lắc tay LLF135', 'lac-tay-llf135', 7, 1, '14K', 1.460, 'Fixed', 2150000, 6854000, NULL, NULL, 0, 'Active'),
(378, 'LLF162', N'Lắc tay Vàng 14K đá CZ', N'Lắc tay LLF162', 'lac-tay-llf-162', 7, 1, '14K', 1.900, 'Fixed', NULL, 9630000, NULL, NULL, 0, 'Active'),
(379, 'LBZ028', N'Lắc Vàng 14K', N'Lắc LBZ028', 'lac-lbz028', 7, 1, '14K', NULL, 'Fixed', NULL, 5993000, NULL, NULL, 0, 'Active'),
(380, 'LZ029', N'Lắc Vàng 14K', N'Lắc LZ029', 'lac-lz029', 7, 1, '14K', 1.440, 'Fixed', 1450000, 7947000, NULL, NULL, 0, 'Active'),
(381, 'VLF56', N'Lắc tay Vàng 14K', N'Vòng Les Fleurs VLF56', 'vong-les-fleurs-vlf56', 7, 1, '14K', 4.490, 'Fixed', 250000, 23144000, NULL, N'24027000', 0, 'Active'),
(382, 'LLF248', N'Charm Vàng 14K đá CZ', N'CHARM LLF248', 'charm-llf248', 8, 1, '14K', 1.950, 'Fixed', NULL, 8647000, NULL, NULL, 0, 'Active'),
(383, 'LLF248-LLF264', N'Charm Vàng 14K đá CZ', N'LLF248-LLF264', 'phuc-mui-binh-an', 8, 1, '14K', 1.950, 'Fixed', NULL, 19249000, NULL, NULL, 0, 'Active'),
(384, 'LLF216', N'Charm Vàng 14K', N'Charm LLF216', 'charm-kim-tuat-llf-216', 8, 1, '14K', 1.180, 'Fixed', NULL, 5493000, NULL, NULL, 0, 'Active'),
(385, 'LLF217', N'Charm Vàng 14K', N'Charm LLF217', 'charm-kim-ty-llf-217', 8, 1, '14K', 1.140, 'Fixed', NULL, 5422000, NULL, NULL, 0, 'Active'),
(386, 'LLF218', N'Charm Vàng 14K', N'Charm LLF218', 'charm-kim-mui-llf-218', 8, 1, '14K', 1.020, 'Fixed', NULL, 4994000, NULL, NULL, 0, 'Active'),
(387, 'LLF219', N'Charm Vàng 14K', N'Charm LLF219', 'charm-kim-dau-llf-219', 8, 1, '14K', 1.220, 'Fixed', NULL, 5993000, NULL, NULL, 0, 'Active'),
(388, 'LLF220', N'Charm Vàng 14K', N'Charm LLF220', 'charm-kim-dan-llf-220', 8, 1, '14K', 1.100, 'Fixed', NULL, 5422000, NULL, NULL, 0, 'Active'),
(389, 'LLF221', N'Charm Vàng 14K', N'Charm LLF221', 'charm-kim-cat-than-llf-221', 8, 1, '14K', 1.250, 'Fixed', NULL, 5350000, NULL, NULL, 0, 'Active'),
(390, 'LLF222', N'Charm Vàng 14K', N'Charm LLF222', 'charm-kim-loc-hoi-llf-222', 8, 1, '14K', 1.160, 'Fixed', NULL, 5536000, NULL, NULL, 0, 'Active'),
(391, 'LLF223', N'Charm Vàng 14K', N'Charm LLF223', 'charm-kim-loc-mao-llf-223', 8, 1, '14K', 0.820, 'Fixed', NULL, 4280000, NULL, NULL, 0, 'Active'),
(392, 'LLF224', N'Charm Vàng 14K', N'Charm LLF224', 'charm-kim-loc-ngo-llf-224', 8, 1, '14K', 1.290, 'Fixed', NULL, 5208000, NULL, NULL, 0, 'Active'),
(393, 'LLF227', N'Charm Vàng 14K', N'Charm LLF227', 'charm-kim-loc-suu-llf-227', 8, 1, '14K', 1.240, 'Fixed', NULL, 5993000, NULL, NULL, 0, 'Active'),
(394, 'LLF318', N'Charm Vàng 14K đá CZ', N'Charm LLF318', 'charm-kim-loc-tai-llf-318', 8, 1, '14K', 0.820, 'Fixed', NULL, 4138000, NULL, NULL, 0, 'Active'),
(395, 'LLF318-CVZ008-LLF255', N'Charm Vàng 14K đá CZ', N'LLF318-CVZ008-LLF255', 'llf318-cvz008-llf255', 8, 1, '14K', 0.820, 'Fixed', NULL, 13377000, NULL, NULL, 0, 'Active'),
(396, 'LLF319', N'Charm Vàng 14K đá CZ', N'Charm LLF319', 'charm-vinh-loc-llf-319', 8, 1, '14K', 1.360, 'Fixed', 750000, 6297000, NULL, NULL, 0, 'Active'),
(397, 'LLF319-CVZ005-LLF322', N'Charm Vàng 14K đá CZ', N'LLF319-CVZ005-LLF322', 'llf319-cvz005-llf322', 8, 1, '14K', 1.360, 'Fixed', NULL, 16050000, NULL, NULL, 0, 'Active'),
(398, 'LLF319-CVZ011-LLF320', N'Charm Vàng 14K đá CZ', N'LLF319-CVZ011-LLF320', 'llf319-cvz011-llf320', 8, 1, '14K', 1.360, 'Fixed', NULL, 13872000, NULL, NULL, 0, 'Active'),
(399, 'LLF319-LLF260-LLF318', N'Charm Vàng 14K đá CZ', N'LLF319-LLF260-LLF318', 'tai-loc-cat-may', 8, 1, '14K', 1.360, 'Fixed', NULL, 18054000, NULL, NULL, 0, 'Active'),
(400, 'LLF320', N'Charm Vàng 14K đá CZ', N'Charm LLF320', 'charm-cuu-kim-tien-llf-320', 8, 1, '14K', NULL, 'Fixed', NULL, 3976000, NULL, NULL, 0, 'Active');
INSERT INTO dbo.Products (ProductID, SKU, ProductName, ShortName, Slug, CategoryID, WarrantyPolicyID, Material, WeightGram, PricingMethod, LaborPrice, Price, OriginalPrice, Description, IsEngravable, Status) VALUES
(401, 'LLF320-CVZ003-LLF319', N'Charm Vàng 14K đá CZ', N'LLF320-CVZ003-LLF319', 'llf320-cvz003-llf319', 8, 1, '14K', NULL, 'Fixed', NULL, 13872000, NULL, NULL, 0, 'Active'),
(402, 'LLF320-LLF261-LLF321', N'Charm Vàng 14K đá CZ', N'LLF320-LLF261-LLF321', 'phuc-thin-loc-phat', 8, 1, '14K', NULL, 'Fixed', NULL, 19501000, NULL, NULL, 0, 'Active'),
(403, 'LLF320-LLF321', N'Charm Vàng 14K đá CZ', N'LLF320-LLF321', 'truong-tai-phat-loc', 8, 1, '14K', NULL, 'Fixed', NULL, 9841000, NULL, NULL, 0, 'Active'),
(404, 'LLF321', N'Charm Vàng 14K đá CZ', N'Charm LLF321', 'charm-vinh-phat-llf-321', 8, 1, '14K', 1.300, 'Fixed', NULL, 5865000, NULL, NULL, 0, 'Active'),
(405, 'LLF321-CVZ012-LLF255', N'Charm Vàng 14K đá CZ', N'LLF321-CVZ012-LLF255', 'llf321-cvz012-llf255', 8, 1, '14K', 1.300, 'Fixed', NULL, 15104000, NULL, NULL, 0, 'Active'),
(406, 'LLF322', N'Charm Vàng 14K đá CZ', N'Charm LLF322', 'charm-luc-nguyen-bao-llf322', 8, 1, '14K', 1.370, 'Fixed', NULL, 6154000, NULL, NULL, 0, 'Active'),
(407, 'CVZ013', N'Charm Vàng 24K', N'Charm CVZ013', 'charm-cvz013', 8, 1, '24K', NULL, 'Fixed', 5880000, 5880000, NULL, N'588', 0, 'Active'),
(408, 'CVZ014', N'Charm Vàng 24K', N'Charm CVZ014', 'charm-cvz014', 8, 1, '24K', NULL, 'Fixed', NULL, 5880000, NULL, NULL, 0, 'Active'),
(409, 'CVZ015', N'Charm Vàng 24K', N'Charm CVZ015', 'charm-cvz015', 8, 1, '24K', NULL, 'Fixed', 5880000, 5880000, NULL, N'54', 0, 'Active'),
(410, 'CVZ016', N'Charm Vàng 24K', N'Charm CVZ016', 'charm-cvz016', 8, 1, '24K', NULL, 'Fixed', 5880000, 5880000, NULL, N'588', 0, 'Active'),
(411, 'CVZ017', N'Charm Vàng 24K', N'Charm CVZ017', 'charm-cvz017', 8, 1, '24K', NULL, 'Fixed', 5880000, 5880000, NULL, N'4021000', 0, 'Active'),
(412, 'CVZ018', N'Charm Vàng 24K', N'Charm CVZ018', 'charm-cvz018', 8, 1, '24K', NULL, 'Fixed', NULL, 5880000, NULL, NULL, 0, 'Active'),
(413, 'CVZ019', N'Charm Vàng 24K', N'Charm CVZ019', 'charm-cvz019', 8, 1, '24K', NULL, 'Fixed', 5880000, 5880000, NULL, N'588', 0, 'Active'),
(414, 'CVZ020', N'Charm Vàng 24K', N'Charm CVZ020', 'charm-cvz020', 8, 1, '24K', NULL, 'Fixed', NULL, 5880000, NULL, NULL, 0, 'Active'),
(415, 'CVZ021', N'Charm Vàng 24K', N'Charm CVZ021', 'charm-cvz021', 8, 1, '24K', NULL, 'Fixed', 5880000, 5880000, NULL, N'588', 0, 'Active'),
(416, 'CVZ022', N'Charm Vàng 24K', N'Charm CVZ022', 'charm-cvz022', 8, 1, '24K', NULL, 'Fixed', 5880000, 5880000, NULL, N'Charm vàng 24K', 0, 'Active'),
(417, 'CVZ023', N'Charm Vàng 24K', N'Charm CVZ023', 'charm-cvz023', 8, 1, '24K', NULL, 'Fixed', 5880000, 5880000, NULL, NULL, 0, 'Active'),
(418, 'CVZ024', N'Charm Vàng 24K', N'Charm CVZ024', 'charm-cvz024', 8, 1, '24K', NULL, 'Fixed', 5880000, 5880000, NULL, NULL, 0, 'Active'),
(419, 'LLF212', N'Charm Vàng 14K', N'Charm LLF212', 'charm-dinh-loc-llf-212', 8, 1, '14K', 0.750, 'Fixed', NULL, 3995000, NULL, NULL, 0, 'Active'),
(420, 'LLF212B', N'Charm Vàng 14K', N'Charm LLF212B', 'charm-loc-phat-llf-212b', 8, 1, '14K', 0.750, 'Fixed', NULL, 3995000, NULL, NULL, 0, 'Active'),
(421, 'LLF243', N'Charm Vàng 14K', N'Charm LLF243', 'charm-an-lien-llf-243', 8, 1, '14K', 1.060, 'Fixed', NULL, 5921000, NULL, NULL, 0, 'Active'),
(422, 'LLF243-CVZ004-LLF323', N'Charm Vàng 14K đá CZ', N'LLF243-CVZ004-LLF323', 'llf243-cvz004-llf323', 8, 1, '14K', 1.060, 'Fixed', NULL, 15793000, NULL, NULL, 0, 'Active'),
(423, 'LLF243-CVZ006-LLF276', N'Charm Vàng 14K đá CZ', N'LLF243-CVZ006-LLF276', 'llf243-cvz006-llf276', 8, 1, '14K', 1.060, 'Fixed', NULL, 14731000, NULL, NULL, 0, 'Active'),
(424, 'LLF250', N'Charm Vàng 14K', N'Charm LLF250', 'charm-llf-250', 8, 1, '14K', NULL, 'Fixed', NULL, 4087000, NULL, NULL, 0, 'Active'),
(425, 'LLF250-LLF322-LLF272', N'Charm Vàng 14K đá CZ', N'LLF250-LLF322-LLF272', 'duyen-loc-khoi-phat', 8, 1, '14K', NULL, 'Fixed', NULL, 13776000, NULL, NULL, 0, 'Active'),
(426, 'LLF255', N'Charm Vàng 14K', N'Charm LLF255', 'charm-llf-255', 8, 1, '14K', NULL, 'Fixed', 750000, 5640000, NULL, NULL, 0, 'Active'),
(427, 'LLF271', N'Charm Vàng 14K đá CZ', N'Charm LLF271', 'charm-llf-271', 8, 1, '14K', NULL, 'Fixed', NULL, 2306000, NULL, NULL, 0, 'Active'),
(428, 'LLF275', N'Charm Vàng 14K đá CZ', N'Charm LLF275', 'charm-llf-275', 8, 1, '14K', NULL, 'Fixed', NULL, 2786000, NULL, NULL, 0, 'Active'),
(429, 'CB01', N'Combo 2 Lắc tay vàng 10K tặng mẹ và vợ', N'CB01', 'cb01', 9, 1, '10K', NULL, 'Fixed', NULL, 5966000, NULL, NULL, 0, 'Active'),
(430, 'PTB353', N'Bộ trang sức Vàng 14K đá CZ', N'Bộ trang sức PTB353', 'bo-trang-suc-ptb353', 9, 1, '10K', NULL, 'Fixed', NULL, 24497300, 25065000, N'Hoạ tiết thiên nga với sự kết hợp của đá trắng dáng Marquise Cut và đá dáng tròn Round Cut, tạo nên vẻ độc đáo và duyên dáng, nữ tính cho thiết kế. 
Sản phẩm phù hợp với đa dạng phong cách, khi đeo dây chuyền và bông tai theo bộ sẽ tôn lên vẻ đẹp hoàn hảo và cuốn hút nhất. Đặc biệt, sản phẩm phù hợp để cô dâu kết hợp cùng áo dài và váy cưới.', 0, 'Active'),
(431, 'CB02', N'Combo Dây chuyền Vàng 10K đá Xà cừ và Bông tai Vàng 10K', N'CB02', 'cb02', 9, 1, '10K', NULL, 'Fixed', NULL, 5903000, NULL, NULL, 0, 'Active'),
(432, 'BTCC86', N'Bộ trang sức Vàng 14K Ngọc trai', N'Bộ trang sức BTCC86', 'bo-trang-suc-btcc86', 9, 1, '10K', NULL, 'Fixed', NULL, 14693100, 15671000, N'Lấy cảm hứng từ sự cân bằng hài hòa giữa thiên nhiên và biển cả, với hình ảnh mặt trời rực rỡ bên cạnh viên ngọc trai tròn. Viên đá chủ lấp lánh được bao quanh vòng đá tấm, làm điểm nhấn nổi bật cho chất liệu ngọc trai thanh lịch. 
Sản phẩm là lựa chọn hoàn hảo để cô dâu kết hợp cùng váy cưới trong ngày trọng đại.', 0, 'Active'),
(433, 'BTCC88', N'Bộ trang sức Vàng 14K Ngọc trai', N'Bộ trang sức BTCC88', 'bo-trang-suc-btcc88', 9, 1, '14K', NULL, 'Fixed', NULL, 12379700, 13090000, NULL, 0, 'Active'),
(434, 'BTCC90', N'Bộ trang sức Vàng 14K Ngọc trai', N'Bộ trang sức BTCC90', 'bo-trang-suc-btcc-90', 9, 1, '10K', NULL, 'Fixed', NULL, 23283100, 24302000, NULL, 0, 'Active'),
(435, 'BTCC91', N'Bộ trang sức Vàng 14K Ngọc trai', N'Bộ trang sức BTCC91', 'bo-trang-suc-btcc-91', 9, 1, '10K', NULL, 'Fixed', NULL, 28361600, 29429000, NULL, 0, 'Active'),
(436, 'PSMEOTHANTAI', N'Vàng lưu niệm 24K', N'LNPSMEOTHANTAI', 'psmeothantai', 10, 1, '10K', NULL, 'Fixed', NULL, 139000, 539000, NULL, 0, 'Active'),
(437, 'PSNGUA1', N'Vàng lưu niệm 24K', N'LNPSNGUA1', 'psngua1', 10, 1, '24K', NULL, 'Fixed', NULL, 139000, 539000, NULL, 0, 'Active'),
(438, 'PSNGUA2', N'Vàng lưu niệm 24K', N'LNPSNGUA2', 'psngua2', 10, 1, '24K', NULL, 'Fixed', NULL, 139000, 539000, NULL, 0, 'Active'),
(439, 'PSPHAT', N'Vàng lưu niệm 24K', N'LNPSPHAT', 'phuc-an', 10, 1, '24K', NULL, 'Fixed', 1500000, 139000, 539000, NULL, 0, 'Active'),
(440, 'PSTYHUU', N'Vàng lưu niệm 24K', N'LNPSTYHUU', 'pstyhuu', 10, 1, '24K', NULL, 'Fixed', NULL, 139000, 539000, NULL, 0, 'Active'),
(441, 'BINHNGOKIMCHIBAO', N'Vàng lưu niệm 24K', N'BINHNGOKIMCHIBAO', 'binhngokimchibao', 10, 1, '24K', NULL, 'Fixed', 2150000, 1094400, 1368000, NULL, 0, 'Active'),
(442, 'BINHNGOPHAT', N'Vàng lưu niệm 24K', N'BINHNGOPHAT', 'binhngophat', 10, 1, '24K', 0.100, 'Fixed', 2150000, 1094400, 1368000, NULL, 0, 'Active'),
(443, 'PHUCLOCCAT', N'Vàng lưu niệm 24K', N'LNPHUCLOCCAT', 'phucloccat', 10, 1, '24K', NULL, 'Fixed', NULL, 539000, NULL, NULL, 0, 'Active');
SET IDENTITY_INSERT dbo.Products OFF;
GO

-- 5.7. Gán sản phẩm vào bộ sưu tập chính
INSERT INTO dbo.ProductCollections (ProductID, CollectionID, IsPrimary) VALUES
(1, 1, 1),
(2, 1, 1),
(3, 1, 1),
(4, 1, 1),
(5, 1, 1),
(6, 1, 1),
(7, 1, 1),
(8, 1, 1),
(9, 1, 1),
(10, 1, 1),
(11, 1, 1),
(12, 1, 1),
(13, 1, 1),
(14, 1, 1),
(15, 1, 1),
(16, 1, 1),
(17, 1, 1),
(18, 1, 1),
(19, 1, 1),
(20, 1, 1),
(21, 1, 1),
(22, 1, 1),
(23, 1, 1),
(24, 1, 1),
(25, 1, 1),
(26, 1, 1),
(27, 1, 1),
(28, 1, 1),
(29, 1, 1),
(30, 1, 1),
(31, 1, 1),
(32, 1, 1),
(33, 1, 1),
(34, 1, 1),
(35, 1, 1),
(36, 1, 1),
(37, 1, 1),
(38, 1, 1),
(39, 1, 1),
(40, 1, 1),
(41, 1, 1),
(42, 1, 1),
(43, 1, 1),
(44, 1, 1),
(45, 1, 1),
(46, 1, 1),
(47, 1, 1),
(48, 1, 1),
(49, 1, 1),
(50, 1, 1),
(51, 1, 1),
(52, 1, 1),
(53, 1, 1),
(54, 1, 1),
(55, 1, 1),
(56, 1, 1),
(57, 1, 1),
(58, 1, 1),
(59, 1, 1),
(60, 1, 1),
(61, 1, 1),
(62, 1, 1),
(63, 1, 1),
(64, 1, 1),
(65, 1, 1),
(66, 1, 1),
(67, 1, 1),
(68, 1, 1),
(69, 1, 1),
(70, 1, 1),
(71, 1, 1),
(72, 1, 1),
(73, 1, 1),
(74, 1, 1),
(75, 1, 1),
(76, 1, 1),
(77, 3, 1),
(78, 3, 1),
(79, 3, 1),
(80, 3, 1),
(81, 3, 1),
(82, 3, 1),
(83, 3, 1),
(84, 3, 1),
(85, 3, 1),
(86, 3, 1),
(87, 3, 1),
(88, 3, 1),
(89, 3, 1),
(90, 3, 1),
(91, 3, 1),
(92, 3, 1),
(93, 3, 1),
(94, 3, 1),
(95, 3, 1),
(96, 3, 1),
(97, 3, 1),
(98, 3, 1),
(99, 5, 1),
(100, 5, 1),
(101, 5, 1),
(102, 5, 1),
(103, 5, 1),
(104, 5, 1),
(105, 5, 1),
(106, 5, 1),
(107, 5, 1),
(108, 5, 1),
(109, 5, 1),
(110, 5, 1),
(111, 5, 1),
(112, 5, 1),
(113, 5, 1),
(114, 5, 1),
(115, 5, 1),
(116, 5, 1),
(117, 5, 1),
(118, 5, 1),
(119, 5, 1),
(120, 5, 1),
(121, 5, 1),
(122, 5, 1),
(123, 10, 1),
(124, 10, 1),
(125, 10, 1),
(126, 10, 1),
(127, 10, 1),
(128, 10, 1),
(129, 10, 1),
(130, 10, 1),
(131, 10, 1),
(132, 10, 1),
(133, 10, 1),
(134, 10, 1),
(135, 10, 1),
(136, 10, 1),
(137, 10, 1),
(138, 10, 1),
(139, 1, 1),
(140, 1, 1),
(141, 1, 1),
(142, 1, 1),
(143, 1, 1),
(144, 1, 1),
(145, 1, 1),
(146, 1, 1),
(147, 1, 1),
(148, 1, 1),
(149, 1, 1),
(150, 3, 1),
(151, 3, 1),
(152, 3, 1),
(153, 3, 1),
(154, 3, 1),
(155, 3, 1),
(156, 3, 1),
(157, 3, 1),
(158, 3, 1),
(159, 3, 1),
(160, 3, 1),
(161, 3, 1),
(162, 3, 1),
(163, 3, 1),
(164, 3, 1),
(165, 3, 1),
(166, 3, 1),
(167, 3, 1),
(168, 3, 1),
(169, 3, 1),
(170, 3, 1),
(171, 10, 1),
(172, 25, 1),
(173, 2, 1),
(174, 2, 1),
(175, 2, 1),
(176, 2, 1),
(177, 2, 1),
(178, 2, 1),
(179, 2, 1),
(180, 2, 1),
(181, 2, 1),
(182, 2, 1),
(183, 2, 1),
(184, 2, 1),
(185, 2, 1),
(186, 2, 1),
(187, 2, 1),
(188, 2, 1),
(189, 2, 1),
(190, 2, 1),
(191, 2, 1),
(192, 2, 1),
(193, 2, 1),
(194, 2, 1),
(195, 8, 1),
(196, 8, 1),
(197, 8, 1),
(198, 21, 1),
(199, 21, 1),
(200, 22, 1),
(201, 2, 1),
(202, 2, 1),
(203, 2, 1),
(204, 2, 1),
(205, 2, 1),
(206, 2, 1),
(207, 2, 1),
(208, 2, 1),
(209, 2, 1),
(210, 2, 1),
(211, 2, 1),
(212, 2, 1),
(213, 2, 1),
(214, 2, 1),
(215, 2, 1),
(216, 2, 1),
(217, 4, 1),
(218, 4, 1),
(219, 4, 1),
(220, 4, 1),
(221, 4, 1),
(222, 4, 1),
(223, 4, 1),
(224, 4, 1),
(225, 4, 1),
(226, 4, 1),
(227, 7, 1),
(228, 7, 1),
(229, 7, 1),
(230, 7, 1),
(231, 7, 1),
(232, 7, 1),
(233, 7, 1),
(234, 7, 1),
(235, 7, 1),
(236, 7, 1),
(237, 7, 1),
(238, 7, 1),
(239, 7, 1),
(240, 7, 1),
(241, 7, 1),
(242, 8, 1),
(243, 8, 1),
(244, 8, 1),
(245, 8, 1),
(246, 8, 1),
(247, 8, 1),
(248, 9, 1),
(249, 11, 1),
(250, 11, 1),
(251, 11, 1),
(252, 11, 1),
(253, 11, 1),
(254, 11, 1),
(255, 11, 1),
(256, 12, 1),
(257, 12, 1),
(258, 12, 1),
(259, 12, 1),
(260, 12, 1),
(261, 12, 1),
(262, 12, 1),
(263, 12, 1),
(264, 12, 1),
(265, 12, 1),
(266, 12, 1),
(267, 15, 1),
(268, 15, 1),
(269, 15, 1),
(270, 2, 1),
(271, 2, 1),
(272, 2, 1),
(273, 2, 1),
(274, 2, 1),
(275, 2, 1),
(276, 2, 1),
(277, 2, 1),
(278, 4, 1),
(279, 4, 1),
(280, 4, 1),
(281, 4, 1),
(282, 4, 1),
(283, 4, 1),
(284, 4, 1),
(285, 4, 1),
(286, 4, 1),
(287, 7, 1),
(288, 7, 1),
(289, 7, 1),
(290, 7, 1),
(291, 8, 1),
(292, 8, 1),
(293, 8, 1),
(294, 8, 1),
(295, 8, 1),
(296, 8, 1),
(297, 11, 1),
(298, 11, 1),
(299, 11, 1),
(300, 11, 1),
(301, 11, 1),
(302, 11, 1),
(303, 11, 1),
(304, 11, 1),
(305, 11, 1),
(306, 12, 1),
(307, 12, 1),
(308, 12, 1),
(309, 15, 1),
(310, 15, 1),
(311, 15, 1),
(312, 16, 1),
(313, 18, 1),
(314, 24, 1),
(315, 2, 1),
(316, 2, 1),
(317, 2, 1),
(318, 2, 1),
(319, 2, 1),
(320, 2, 1),
(321, 2, 1),
(322, 2, 1),
(323, 2, 1),
(324, 2, 1),
(325, 2, 1),
(326, 2, 1),
(327, 2, 1),
(328, 2, 1),
(329, 2, 1),
(330, 2, 1),
(331, 2, 1),
(332, 2, 1),
(333, 2, 1),
(334, 2, 1),
(335, 2, 1),
(336, 2, 1),
(337, 4, 1),
(338, 4, 1),
(339, 4, 1),
(340, 4, 1),
(341, 9, 1),
(342, 9, 1),
(343, 9, 1),
(344, 9, 1),
(345, 9, 1),
(346, 9, 1),
(347, 9, 1),
(348, 9, 1),
(349, 9, 1),
(350, 9, 1),
(351, 9, 1),
(352, 9, 1),
(353, 9, 1),
(354, 9, 1),
(355, 9, 1),
(356, 9, 1),
(357, 9, 1),
(358, 9, 1),
(359, 12, 1),
(360, 15, 1),
(361, 15, 1),
(362, 15, 1),
(363, 16, 1),
(364, 16, 1),
(365, 16, 1),
(366, 16, 1),
(367, 16, 1),
(368, 16, 1),
(369, 18, 1),
(370, 18, 1),
(371, 20, 1),
(372, 20, 1),
(373, 22, 1),
(374, 23, 1),
(375, 23, 1),
(376, 2, 1),
(377, 2, 1),
(378, 2, 1),
(379, 4, 1),
(380, 4, 1),
(381, 4, 1),
(382, 2, 1),
(383, 2, 1),
(384, 6, 1),
(385, 6, 1),
(386, 6, 1),
(387, 6, 1),
(388, 6, 1),
(389, 6, 1),
(390, 6, 1),
(391, 6, 1),
(392, 6, 1),
(393, 6, 1),
(394, 6, 1),
(395, 6, 1),
(396, 6, 1),
(397, 6, 1),
(398, 6, 1),
(399, 6, 1),
(400, 6, 1),
(401, 6, 1),
(402, 6, 1),
(403, 6, 1),
(404, 6, 1),
(405, 6, 1),
(406, 6, 1),
(407, 13, 1),
(408, 13, 1),
(409, 13, 1),
(410, 13, 1),
(411, 13, 1),
(412, 13, 1),
(413, 13, 1),
(414, 13, 1),
(415, 13, 1),
(416, 13, 1),
(417, 13, 1),
(418, 13, 1),
(419, 14, 1),
(420, 14, 1),
(421, 14, 1),
(422, 14, 1),
(423, 14, 1),
(424, 14, 1),
(425, 14, 1),
(426, 14, 1),
(427, 14, 1),
(428, 14, 1),
(429, 2, 1),
(430, 2, 1),
(431, 4, 1),
(432, 8, 1),
(433, 8, 1),
(434, 8, 1),
(435, 8, 1),
(436, 17, 1),
(437, 17, 1),
(438, 17, 1),
(439, 17, 1),
(440, 17, 1),
(441, 19, 1),
(442, 19, 1),
(443, 19, 1);
GO

-- 5.8. Hình ảnh sản phẩm (2950 ảnh, ảnh đầu tiên là ảnh đại diện)
INSERT INTO dbo.ProductImages (ProductID, ImageUrl, SortOrder, IsThumbnail) VALUES
(1, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754063/ndino131ldia7_1716448926.png', 0, 1),
(1, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754063/ndino131ldia2_1716448926.jpg', 1, 0),
(1, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754063/ndino131ldia1_1716448926.jpg', 2, 0),
(1, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754063/ndino131ldia3_1716448926.jpg', 3, 0),
(1, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754063/ndino131ldia4_1716448926.jpg', 4, 0),
(1, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754063/ndino131ldia6_1716448926.png', 5, 0),
(1, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754063/ndino131ldia9_1716448926.png', 6, 0),
(1, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754063/ndino131ldia8_1716448926.png', 7, 0),
(2, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754061/ndino15ldia7_1716452501.png', 0, 1),
(2, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754061/ndino15ldia1_1716452575.jpg', 1, 0),
(2, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754061/ndino15ldia2_1716452575.jpg', 2, 0),
(2, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754061/ndino15ldia3_1716452575.jpg', 3, 0),
(2, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754061/ndino15ldia4_1716452575.jpg', 4, 0),
(2, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754061/ndino15ldia6_1716452501.png', 5, 0),
(2, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754061/ndino15ldia9_1716452488.png', 6, 0),
(2, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754061/ndino15ldia8_1716452501.png', 7, 0),
(3, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754053/ndino171ldia7-b_1716444514.png', 0, 1),
(3, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754053/ndino171kc2_1716444620.jpg', 1, 0),
(3, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754053/ndino171kc1_1716444620.jpg', 2, 0),
(3, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754053/ndino171kc3_1716444621.jpg', 3, 0),
(3, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754053/ndino171kc4_1716444621.jpg', 4, 0),
(3, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754053/ndino171ldia8-b_1716444497.png', 5, 0),
(3, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754053/ndino171ldia6-b_1716444497.png', 6, 0),
(3, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754053/ndino171ldia9-b_1716444497.png', 7, 0),
(4, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754054/ndino173ldia7-1_1716779713.png', 0, 1),
(4, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754054/ndino173ldia1_1716444873.jpg', 1, 0),
(4, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754054/ndino173ldia3_1716444873.jpg', 2, 0),
(4, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754054/ndino173ldia4_1716444872.jpg', 3, 0),
(4, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754054/ndino173ldia6-1_1716779713.png', 4, 0),
(4, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754054/ndino173ldia9-1_1716779719.png', 5, 0),
(4, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754054/ndino173ldia8-1_1716779713.png', 6, 0),
(5, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754065/ndino175kc7_1716439988.png', 0, 1),
(5, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754065/ndino175kc2_1716439887.jpg', 1, 0),
(5, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754065/ndino175kc3_1716439887.jpg', 2, 0),
(5, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754065/ndino175kc4_1716439888.jpg', 3, 0),
(5, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754065/ndino175kc1_1716439887.jpg', 4, 0),
(5, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754065/ndino175kc6_1716444498.png', 5, 0),
(5, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754065/ndino175kc8_1716439888.png', 6, 0),
(5, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754065/ndino175kc9_1716439888.png', 7, 0),
(6, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754052/ndino180ldia7_1716438950.png', 0, 1),
(6, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754052/ndino180ldia2_1716438950.jpg', 1, 0),
(6, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754052/ndino180ldia3_1716438950.jpg', 2, 0),
(6, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754052/ndino180ldia1_1716438950.jpg', 3, 0),
(6, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754052/ndino180ldia4_1716438949.jpg', 4, 0),
(6, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754052/ndino180ldia6_1716438950.png', 5, 0),
(6, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754052/ndino180ldia8-b_1716438949.png', 6, 0),
(6, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754052/ndino180ldia8_1716438950.png', 7, 0),
(7, 'https://cdn.huythanhjewelry.vn/storage/photos/uploads/ndino19ldia-vt-1_1740370485.png', 0, 1),
(7, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754062/ndino19ldia2_1716450556.jpg', 1, 0),
(7, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754062/ndino19ldia1_1716450555.jpg', 2, 0),
(7, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754062/ndino19ldia3_1716450555.jpg', 3, 0),
(7, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754062/ndino19ldia4_1716450555.jpg', 4, 0),
(7, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754062/ndino19ldia-vt-1_1740370474.png', 5, 0),
(7, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754062/ndino19ldia-vt-3_1740370474.png', 6, 0),
(7, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754062/ndino19ldia-vt-5_1740370474.png', 7, 0),
(7, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754062/ndino19ldia-vt-7_1740370474.png', 8, 0),
(8, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754082/ndino20ldia7_1728532388.png', 0, 1),
(8, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754082/ndino20-vv-2-1_1728532388.jpg', 1, 0),
(8, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754082/ndino20-vv-4-1_1728532388.jpg', 2, 0),
(8, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754082/ndino20ldia9_1728532388.png', 3, 0),
(8, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754082/ndino20ldia6_1728532388.png', 4, 0),
(8, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754082/ndino20ldia8_1728532388.png', 5, 0),
(9, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754083/ndino23ldia7_1716278741.png', 0, 1),
(9, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754083/ndino23ldia2_1716278741.jpg', 1, 0),
(9, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754083/ndino23ldia1_1716278741.jpg', 2, 0),
(9, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754083/ndino23ldia3_1716278741.jpg', 3, 0),
(9, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754083/ndino23ldia4_1716278741.jpg', 4, 0),
(9, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754083/ndino23ldia9_1716278741.png', 5, 0),
(9, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754083/ndino23ldia6_1716278741.png', 6, 0),
(9, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754083/ndino23ldia8_1716278741.png', 7, 0),
(10, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754064/ndino248kc7_1716448379.png', 0, 1),
(10, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754064/ndino248vt2_1786086233.jpg', 1, 0),
(10, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754064/ndino248vt3_1786092923.png', 2, 0),
(10, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754064/ndino248vt4_1786086237.jpg', 3, 0),
(10, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754064/ndino248kc6_1716448379.png', 4, 0),
(10, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754064/ndino248kc8_1716448378.png', 5, 0),
(10, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754064/ndino248kc9_1716448378.png', 6, 0),
(11, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754055/ndino255-1kc7_1716447617.png', 0, 1),
(11, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754055/ndino255-vt-2_1729058885.jpg', 1, 0),
(11, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754055/ndino255-vt-4_1729058885.jpg', 2, 0),
(11, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754055/ndino255-1kc6_1716447617.png', 3, 0),
(11, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754055/ndino255-1kc8_1716445727.png', 4, 0),
(11, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754055/ndino255-1kc9_1716447617.png', 5, 0),
(12, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754058/ndino2677_1716449790.png', 0, 1),
(12, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754058/ndino2672_1716448848.jpg', 1, 0),
(12, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754058/ndino2673_1716448848.jpg', 2, 0),
(12, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754058/ndino2674_1716448848.jpg', 3, 0),
(12, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754058/ndino2671_1716448848.jpg', 4, 0),
(12, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754058/ndino2676_1716449790.png', 5, 0),
(12, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754058/ndino2678_1716448848.png', 6, 0),
(13, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754057/ndino26ldia7_1716448613.png', 0, 1),
(13, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754057/ndino26ldia2_1716448597.jpg', 1, 0),
(13, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754057/ndino26ldia3_1716448598.jpg', 2, 0),
(13, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754057/ndino26ldia4_1716448597.jpg', 3, 0),
(13, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754057/ndino26ldia1_1716448597.jpg', 4, 0),
(13, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754057/ndino26ldia6_1716448613.png', 5, 0),
(13, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754057/ndino26ldia9_1716448598.png', 6, 0),
(13, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754057/ndino26ldia8_1716448614.png', 7, 0),
(14, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754059/ndino271ldiavt1_1737605024.png', 0, 1),
(14, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754059/ndino2712_1716453213.jpg', 1, 0),
(14, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754059/ndino2713_1716453213.jpg', 2, 0),
(14, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754059/ndino2714_1716453213.jpg', 3, 0),
(14, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754059/ndino2711_1716453213.jpg', 4, 0),
(14, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754059/ndino271ldia-vt-5_1737605009.png', 5, 0),
(14, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754059/ndino271ldia-vt-7_1737605009.png', 6, 0),
(14, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754059/ndino271ldia-vt-5_1737605024.png', 7, 0),
(14, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754059/ndino271ldia-vt-3_1737605024.png', 8, 0),
(15, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754085/ndino274ldia7_1716276941.png', 0, 1),
(15, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754085/ndino274ldia2_1716276941.jpg', 1, 0),
(15, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754085/ndino274ldia1_1716276941.jpg', 2, 0),
(15, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754085/ndino274ldia3_1716276949.jpg', 3, 0),
(15, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754085/ndino274ldia4_1716276941.jpg', 4, 0),
(15, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754085/ndino274ldia6_1716276941.png', 5, 0),
(15, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754085/ndino274ldia9_1716276941.png', 6, 0),
(15, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754085/ndino274ldia8_1716276941.png', 7, 0),
(16, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754081/ndino276ldia7-1_1716364230.png', 0, 1),
(16, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754081/ndino276ldia2_1716364230.jpg', 1, 0),
(16, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754081/ndino276ldia1_1716364230.jpg', 2, 0),
(16, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754081/ndino276ldia3_1716364230.jpg', 3, 0),
(16, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754081/ndino276ldia4_1716364230.jpg', 4, 0),
(16, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754081/ndino276ldia9_1716364230.png', 5, 0),
(16, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754081/ndino276ldia6_1716364230.png', 6, 0),
(16, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754081/ndino276ldia8_1716364230.png', 7, 0),
(17, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754051/ndino278ldia7_1716438673.png', 0, 1),
(17, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754051/ndino2782_1716438628.jpg', 1, 0),
(17, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754051/ndino2783_1716438628.jpg', 2, 0),
(17, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754051/ndino2784_1716438628.jpg', 3, 0),
(17, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754051/ndino278ldia3_1716438628.jpg', 4, 0),
(17, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754051/ndino278ldia2_1716438628.jpg', 5, 0),
(17, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754051/ndino278ldia1_1716438628.jpg', 6, 0),
(17, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754051/ndino278ldia6_1716438629.png', 7, 0),
(17, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754051/ndino278ldia9_1716438628.png', 8, 0),
(17, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754051/ndino278ldia8_1716438628.png', 9, 0),
(18, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754060/ndino281ldia7_1716453524.png', 0, 1),
(18, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754060/ndino281ldia1_1716453432.jpg', 1, 0),
(18, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754060/ndino281ldia2_1716453257.jpg', 2, 0),
(18, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754060/ndino281ldia3_1716453304.jpg', 3, 0),
(18, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754060/ndino281ldia4_1716453256.jpg', 4, 0),
(18, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754060/ndino281ldia6_1716453524.png', 5, 0),
(18, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754060/ndino281ldia9_1716453498.png', 6, 0),
(18, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754060/ndino281ldia8_1716453524.png', 7, 0),
(19, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754066/ndino283ldia6_1716439315.png', 0, 1),
(19, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754066/ndino283vt2_1786086098.jpg', 1, 0),
(19, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754066/ndino283vt3_1786092874.png', 2, 0),
(19, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754066/ndino283vt4_1786086104.jpg', 3, 0),
(19, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754066/ndino283ldia1_1716439448.png', 4, 0),
(19, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754066/ndino283ldia5_1716439293.png', 5, 0),
(19, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754066/ndino283ldia7_1716439315.png', 6, 0),
(20, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754067/ndino291ldia6_1716437995.png', 0, 1),
(20, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754067/ndino2912_1716437924.jpg', 1, 0),
(20, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754067/ndino2913_1716437924.jpg', 2, 0),
(20, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754067/ndino2914_1716437924.jpg', 3, 0),
(20, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754067/ndino2911_1716437924.jpg', 4, 0),
(20, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754067/ndino291ldia1_1716438049.png', 5, 0),
(20, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754067/ndino291ldia5_1716437943.png', 6, 0),
(20, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754067/ndino291ldia7_1716437990.png', 7, 0),
(21, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754068/ndino292ldia6_1716435020.png', 0, 1),
(21, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754068/ndino2924_1716435343.jpg', 1, 0),
(21, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754068/ndino2921_1716434870.jpg', 2, 0),
(21, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754068/ndino2922_1716434824.jpg', 3, 0),
(21, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754068/ndino2923_1716434824.jpg', 4, 0),
(21, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754068/ndino292ldia1_1716435332.png', 5, 0),
(21, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754068/ndino292ldia5_1716435331.png', 6, 0),
(21, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754068/ndino292ldia7_1716434886.png', 7, 0),
(22, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754069/ndino295ldia6_1716863322.png', 0, 1),
(22, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754069/ndino2952_1716863295.jpg', 1, 0),
(22, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754069/ndino2953_1716863295.jpg', 2, 0),
(22, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754069/ndino2951_1716863295.jpg', 3, 0),
(22, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754069/ndino2954_1716863295.jpg', 4, 0),
(22, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754069/ndino295ldia1_1716863314.png', 5, 0),
(22, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754069/ndino295ldia5_1716863304.png', 6, 0),
(22, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754069/ndino295ldia7_1716863314.png', 7, 0),
(23, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754070/ndino300ldia6b5fee9141227494fbfae32877da9faca_1716432240.webp', 0, 1),
(23, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754070/ndino3003_1716432338.jpg', 1, 0),
(23, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754070/ndino3002_1716432338.jpg', 2, 0),
(23, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754070/ndino3001_1716432338.jpg', 3, 0),
(23, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754070/ndino3004_1716432338.jpg', 4, 0),
(23, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754070/ndino300ldia1efb5649a5b534949b1930f2849613ab2_1716432240.webp', 5, 0),
(23, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754070/ndino300ldia54e080592333e48539bc7119c8c864448_1716432240.webp', 6, 0),
(23, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754070/ndino300ldia7aa9372ac96154555b6f5859b630a6fc6_1716432240.webp', 7, 0),
(24, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754071/ndino301ldia6_1716431210.png', 0, 1),
(24, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754071/ndino301vt2_1786086017.jpg', 1, 0),
(24, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754071/ndino301vt3_1786092788.png', 2, 0),
(24, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754071/ndino301vt4_1786086022.jpg', 3, 0),
(24, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754071/ndino301ldia1_1716431210.png', 4, 0),
(24, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754071/ndino301ldia5_1716431209.png', 5, 0),
(24, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754071/ndino301ldia7_1716431209.png', 6, 0),
(25, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754072/ndino302ldia6_1716430407.png', 0, 1),
(25, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754072/ndino3023_1786086059.jpg', 1, 0),
(25, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754072/ndino302vt3_1786092823.png', 2, 0),
(25, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754072/ndino302vtvt4_1786086064.jpg', 3, 0),
(25, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754072/ndino302ldia1_1716430450.png', 4, 0),
(25, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754072/ndino302ldia5_1716430406.png', 5, 0),
(25, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754072/ndino302ldia7_1716430446.png', 6, 0),
(26, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754073/ndino3056_1716429910.png', 0, 1),
(26, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754073/ndino305ldia-vt-4_1725869043.jpg', 1, 0),
(26, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754073/ndino305ldia-vt-2_1725869043.jpg', 2, 0),
(26, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754073/ndino3057_1716429910.png', 3, 0),
(26, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754073/ndino3055_1716429866.png', 4, 0),
(26, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754073/ndino3051_1716429897.png', 5, 0),
(27, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717209557/ndino306ldia-vt-4_1717582057.png', 0, 1),
(27, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717209557/ndino306ldia00005-copy_1717582057.jpg', 1, 0),
(27, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717209557/ndino306ldia00002-copy_1717582057.jpg', 2, 0),
(27, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717209557/ndino306ldia-vt-5_1717582057.png', 3, 0),
(27, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717209557/ndino306ldia-vt-6_1717582057.png', 4, 0),
(27, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717209557/ndino306ldia-vt-7_1717582057.png', 5, 0),
(28, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210419/ndino307ldia-vt-4_1717582321.png', 0, 1),
(28, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210419/ndino307ldia00005-copy_1717582321.jpg', 1, 0),
(28, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210419/ndino307ldia00002-copy_1717582321.jpg', 2, 0),
(28, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210419/ndino307ldia-vt-7_1717582321.png', 3, 0),
(28, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210419/ndino307ldia-vt-6_1717582321.png', 4, 0),
(28, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210419/ndino307ldia-vt-5_1717582321.png', 5, 0),
(29, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210452/ndino308ldia-vt-4_1717582360.png', 0, 1),
(29, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210452/ndino308ldia00006-copy_1717582360.jpg', 1, 0),
(29, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210452/ndino308ldia00002-copy_1717582360.jpg', 2, 0),
(29, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210452/ndino308ldia-vt-5_1717582360.png', 3, 0),
(29, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210452/ndino308ldia-vt-6_1717582360.png', 4, 0),
(29, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210452/ndino308ldia-vt-7_1717582360.png', 5, 0),
(30, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210469/ndino309ldia-vt-4_1717582416.png', 0, 1),
(30, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210469/ndino309ldia00004copy_1717582416.jpg', 1, 0),
(30, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210469/ndino309ldia00002copy_1717582416.jpg', 2, 0),
(30, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210469/ndino309ldia-vt-5_1717582416.png', 3, 0),
(30, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210469/ndino309ldia-vt-6_1717582416.png', 4, 0),
(30, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210469/ndino309ldia-vt-7_1717582416.png', 5, 0),
(31, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210482/ndino310ldia-vt-4_1717582461.png', 0, 1),
(31, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210482/ndino310ldia00005copy_1717582461.jpg', 1, 0),
(31, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210482/ndino310ldia00002copy_1717582461.jpg', 2, 0),
(31, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210482/ndino310ldia-vt-5_1717582461.png', 3, 0),
(31, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210482/ndino310ldia-vt-6_1717582461.png', 4, 0),
(31, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210482/ndino310ldia-vt-7_1717582461.png', 5, 0),
(32, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210493/ndino311ldia-vt-4_1717582515.png', 0, 1),
(32, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210493/ndino311ldia00004copy_1717582515.jpg', 1, 0),
(32, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210493/ndino311ldia00002copy_1717582515.jpg', 2, 0),
(32, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210493/ndino311ldia-vt-5_1717582515.png', 3, 0),
(32, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210493/ndino311ldia-vt-6_1717582515.png', 4, 0),
(32, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1717210493/ndino311ldia-vt-7_1717582515.png', 5, 0),
(33, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099740/ndino312ldia-vt-4_1718259215.png', 0, 1),
(33, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099740/ndino312ldia00003-copy_1718254281.jpg', 1, 0),
(33, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099740/ndino312ldia00005-copy_1718254281.jpg', 2, 0),
(33, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099740/ndino312ldia-vt-5_1718259215.png', 3, 0),
(33, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099740/ndino312ldia-vt-6_1718259216.png', 4, 0),
(33, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099740/ndino312ldia-vt-7_1718259216.png', 5, 0),
(34, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099792/ndino313ldia-vt-4_1718259464.png', 0, 1),
(34, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099792/ndino313dia00004-copy_1718259455.jpg', 1, 0),
(34, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099792/ndino313dia00002-copy_1718259455.jpg', 2, 0),
(34, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099792/ndino313ldia-vt-5_1718259464.png', 3, 0),
(34, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099792/ndino313ldia-vt-6_1718259570.png', 4, 0),
(34, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099792/ndino313ldia-vt-7_1718259591.png', 5, 0),
(35, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099860/ndino314ldia-vt-4_1718259777.png', 0, 1),
(35, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099860/ndino314ldia00002-copy_1718259838.jpg', 1, 0),
(35, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099860/ndino314ldia00004-copy_1718259838.jpg', 2, 0),
(35, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099860/ndino314ldia-vt-5_1718259755.png', 3, 0),
(35, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099860/ndino314ldia-vt-7_1718259857.png', 4, 0),
(35, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099860/ndino314ldia-vt-6_1718260366.png', 5, 0),
(36, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099876/ndino315ldia-vt-4_1718260721.png', 0, 1),
(36, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099876/ndino315ldia00002-copy_1718260428.jpg', 1, 0),
(36, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099876/ndino315ldia00005-copy_1718260411.jpg', 2, 0),
(36, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099876/ndino315ldia-vt-5_1718260440.png', 3, 0),
(36, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099876/ndino315ldia-vt-7_1718260721.png', 4, 0),
(36, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099876/ndino315ldia-vt-6_1718260722.png', 5, 0),
(37, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099907/ndino316ldia-vt-4_1718260932.png', 0, 1),
(37, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099907/ndino316dia00006-copy_1718260794.jpg', 1, 0),
(37, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099907/ndino316dia00002-copy_1718260794.jpg', 2, 0),
(37, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099907/ndino316ldia-vt-5_1718260810.png', 3, 0),
(37, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099907/ndino316ldia-vt-7_1718260932.png', 4, 0),
(37, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718099907/ndino316ldia-vt-6_1718260952.png', 5, 0),
(38, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913698/ndino318ldia-vt-1_1725530294.png', 0, 1),
(38, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913698/ndino318ldia-vt-2_1736213751.jpg', 1, 0),
(38, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913698/ndino318ldia-vt-4_1736213751.jpg', 2, 0),
(38, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913698/ndino318ldia-vt-4_1725530294.png', 3, 0),
(38, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913698/ndino318ldia-vt-6_1725530294.png', 4, 0),
(38, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913698/ndino318ldia-vt-5_1725530294.png', 5, 0),
(39, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913856/ndino320ldia-vt-1_1725530612.png', 0, 1),
(39, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913856/ndino320ldia-vt-2_1725530612.jpg', 1, 0),
(39, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913856/ndino320ldia-vt-4_1725530612.jpg', 2, 0),
(39, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913856/ndino320ldia-vt-6_1725530612.png', 3, 0),
(39, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913856/ndino320ldia-vt-4_1725531037.png', 4, 0),
(39, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913856/ndino320ldia-vt-5_1725531061.png', 5, 0),
(40, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913945/ndino321ldia-vt-1_1725530770.png', 0, 1),
(40, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913945/ndino321ldia-vt-2_1725530770.jpg', 1, 0),
(40, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913945/ndino321ldia-vt-4_1725530770.jpg', 2, 0),
(40, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913945/ndino321ldia-vt-4_1725530780.png', 3, 0),
(40, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913945/ndino321ldia-vt-5_1725530780.png', 4, 0),
(40, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724913945/ndino321ldia-vt-6_1725530780.png', 5, 0),
(41, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914028/ndino322ldia-vt-1_1725530838.png', 0, 1),
(41, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914028/ndino322ldia-vt-2_1725530829.jpg', 1, 0),
(41, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914028/ndino322ldia-vt-4_1725530829.jpg', 2, 0),
(41, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914028/ndino322ldia-vt-4_1725530838.png', 3, 0),
(41, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914028/ndino322ldia-vt-5_1725530838.png', 4, 0),
(41, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914028/ndino322ldia-vt-6_1725530838.png', 5, 0),
(42, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914089/ndino323ldia-vt-1_1725530907.png', 0, 1),
(42, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914089/ndino323ldia-vt-2_1725530889.jpg', 1, 0),
(42, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914089/ndino323ldia-vt-4_1725530890.jpg', 2, 0),
(42, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914089/ndino323ldia-vt-6_1725530890.png', 3, 0),
(42, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914089/ndino323ldia-vt-4_1729756245.png', 4, 0),
(42, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724914089/ndino323ldia-vt-5_1725530907.png', 5, 0),
(43, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752852/ndino324ldiavt1_1732004567.png', 0, 1),
(43, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752852/ndino324ldiavt4_1732004566.jpg', 1, 0),
(43, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752852/ndino324ldiavt2_1732004567.jpg', 2, 0),
(43, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752852/ndino324ldiavt2_1732004567.png', 3, 0),
(43, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752852/ndino324ldiavt3_1732004567.png', 4, 0),
(43, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752852/ndino324ldiavt4_1732004580.png', 5, 0),
(44, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752854/ndino325ldiavt1_1732004636.png', 0, 1),
(44, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752854/ndino325ldiavt4_1732004636.jpg', 1, 0),
(44, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752854/ndino325ldiavt2_1732004636.jpg', 2, 0),
(44, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752854/ndino325ldiavt3_1732004636.png', 3, 0),
(44, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752854/ndino325ldiavt2_1732004636.png', 4, 0),
(44, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752854/ndino325ldiavt4_1732004636.png', 5, 0),
(45, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752856/ndino326ldiavt1_1732004909.png', 0, 1),
(45, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752856/ndino326vt2_1786086280.jpg', 1, 0),
(45, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752856/ndino326vt3_1786092960.png', 2, 0),
(45, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752856/ndino326vt4_1786086290.jpg', 3, 0),
(45, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752856/ndino326ldiavt3_1732004909.png', 4, 0),
(45, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752856/ndino326ldiavt2_1732004909.png', 5, 0),
(45, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752856/ndino326ldiavt4_1732004909.png', 6, 0),
(46, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752858/ndino327ldiavt1_1732005011.png', 0, 1),
(46, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752858/ndino327ldiavt4_1732005011.jpg', 1, 0),
(46, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752858/ndino327ldiavt2_1732005011.jpg', 2, 0),
(46, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752858/ndino327ldiavt3_1732005011.png', 3, 0),
(46, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752858/ndino327ldiavt2_1732005011.png', 4, 0),
(46, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752858/ndino327ldiavt4_1732005011.png', 5, 0),
(47, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752860/ndino328ldiavt1_1731922027.png', 0, 1),
(47, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752860/ndino328vt2_1731922040.jpg', 1, 0),
(47, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752860/ndino328vt4_1731922040.jpg', 2, 0),
(47, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752860/ndino328ldiavt7_1731922027.png', 3, 0),
(47, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752860/ndino328ldiavt3_1731922027.png', 4, 0),
(47, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752860/ndino328ldiavt5_1731922027.png', 5, 0),
(48, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752862/ndino329ldia-vt-1_1732009230.png', 0, 1),
(48, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752862/ndino329ldiavt4_1732005426.jpg', 1, 0),
(48, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752862/ndino329ldiavt2_1732005426.jpg', 2, 0),
(48, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752862/ndino329ldia-vt-3_1732009230.png', 3, 0),
(48, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752862/ndino329ldia-vt-5_1732009230.png', 4, 0),
(48, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752862/ndino329ldia-vt-7_1732009230.png', 5, 0),
(49, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752866/ndino331ldia-vt-1_1732009505.png', 0, 1),
(49, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752866/ndino331vt2_1731922397.jpg', 1, 0),
(49, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752866/ndino331vt4_1731922397.jpg', 2, 0),
(49, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752866/ndino331-vt-5_1731922397.png', 3, 0),
(49, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752866/ndino331-vt-7_1731922397.png', 4, 0),
(49, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752866/ndino331-vt-3_1731922397.png', 5, 0),
(50, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752868/ndino333ldia-vt-1_1732009599.png', 0, 1),
(50, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752868/ndino333vt4_1731922492.jpg', 1, 0),
(50, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752868/ndino333vt2_1731922492.jpg', 2, 0),
(50, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752868/ndino333-vt-3_1731922492.png', 3, 0),
(50, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752868/ndino333-vt-5_1731922492.png', 4, 0),
(50, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752868/ndino333-vt-7_1731922492.png', 5, 0),
(51, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743751594/ndino335vt1_1743751807.png', 0, 1),
(51, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743751594/ndino335vt2_1743751807.jpg', 1, 0),
(51, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743751594/ndino335vt4_1743751796.jpg', 2, 0),
(51, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743751594/ndino335vt3_1743751807.png', 3, 0),
(51, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743751594/ndino335vt5_1743751807.png', 4, 0),
(51, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743751594/ndino335vt7_1743751807.png', 5, 0),
(52, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752808201/ndino344ldiavt1_1752830784.png', 0, 1),
(52, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752808201/ndino344ldiavt2_1752830680.jpg', 1, 0),
(52, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752808201/ndino344ldiavt3_1752830784.jpg', 2, 0),
(52, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752808201/ndino344ldiavt4_1752830680.jpg', 3, 0),
(52, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752808201/ndino344ldiavt5_1752830784.jpg', 4, 0),
(52, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752808201/ndino344ldiavt6_1752830784.png', 5, 0),
(52, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752808201/ndino344ldiavt7_1752830713.png', 6, 0),
(52, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752808201/ndino344ldiavt8_1752830713.png', 7, 0),
(53, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752809634/ndino345ldiavt1_1752831296.png', 0, 1),
(53, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752809634/ndino345ldiavt2-1_1752831267.jpg', 1, 0),
(53, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752809634/ndino345ldiavt3_1752831314.jpg', 2, 0),
(53, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752809634/ndino345ldiavt4_1752831233.jpg', 3, 0),
(53, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752809634/ndino345ldiavt5_1752831267.jpg', 4, 0),
(53, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752809634/ndino345ldiavt6_1752831339.png', 5, 0),
(53, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752809634/ndino345ldiavt7_1752831233.png', 6, 0),
(53, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752809634/ndino345ldiavt8_1752831233.png', 7, 0),
(54, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810246/ndino346ldiavt1_1752831734.png', 0, 1),
(54, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810246/ndino346ldiavt2_1752831741.jpg', 1, 0),
(54, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810246/ndino346ldiavt3_1752831749.jpg', 2, 0),
(54, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810246/ndino346ldiavt4_1752831754.jpg', 3, 0),
(54, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810246/ndino346ldiavt5_1752831764.jpg', 4, 0),
(54, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810246/ndino346ldiavt6_1752831771.png', 5, 0),
(54, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810246/ndino346ldiavt7_1752831776.png', 6, 0),
(54, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810246/ndino346ldiavt8_1752831784.png', 7, 0),
(55, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810333/ndino347ldiavt1_1752832046.png', 0, 1),
(55, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810333/ndino347ldiavt2_1752832054.jpg', 1, 0),
(55, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810333/ndino347ldiavt3_1752832060.jpg', 2, 0),
(55, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810333/ndino347ldiavt4_1752832066.jpg', 3, 0),
(55, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810333/ndino347ldiavt5_1752832070.jpg', 4, 0),
(55, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810333/ndino347ldiavt6_1752832077.png', 5, 0),
(55, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810333/ndino347ldiavt7_1752832083.png', 6, 0),
(55, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810333/ndino347ldiavt8_1752832090.png', 7, 0),
(56, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810417/ndino348ldiavt1_1752832382.png', 0, 1),
(56, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810417/ndino348ldiavt2_1752832390.jpg', 1, 0),
(56, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810417/ndino348ldiavt3_1752832396.jpg', 2, 0),
(56, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810417/ndino348ldiavt4_1752832403.jpg', 3, 0),
(56, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810417/ndino348ldiavt5_1752832409.jpg', 4, 0),
(56, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810417/ndino348ldiavt6_1752832414.png', 5, 0),
(56, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810417/ndino348ldiavt7_1752832420.png', 6, 0),
(56, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810417/ndino348ldiavt8_1752832438.png', 7, 0),
(57, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810498/ndino349ldiavt1_1752832738.png', 0, 1),
(57, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810498/ndino349ldiavt2_1752832745.jpg', 1, 0),
(57, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810498/ndino349ldiavt3_1752832751.jpg', 2, 0),
(57, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810498/ndino349ldiavt4_1752832776.jpg', 3, 0),
(57, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810498/ndino349ldiavt5_1752832783.jpg', 4, 0),
(57, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810498/ndino349ldiavt6_1752832794.png', 5, 0),
(57, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810498/ndino349ldiavt7_1752832801.png', 6, 0),
(57, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810498/ndino349ldiavt8_1752832808.png', 7, 0),
(58, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810604/ndino350ldiavt1_1752832948.png', 0, 1),
(58, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810604/ndino350ldiavt2_1752832955.jpg', 1, 0),
(58, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810604/ndino350ldiavt3_1752832963.jpg', 2, 0),
(58, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810604/ndino350ldiavt4_1752832970.jpg', 3, 0),
(58, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810604/ndino350ldiavt5_1752832976.jpg', 4, 0),
(58, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810604/ndino350ldiavt6_1752832982.png', 5, 0),
(58, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810604/ndino350ldiavt7_1752832988.png', 6, 0),
(58, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810604/ndino350ldiavt8_1752832997.png', 7, 0),
(59, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810693/ndino351ldiavt1_1752833121.png', 0, 1),
(59, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810693/ndino351ldiavt2_1752833130.jpg', 1, 0),
(59, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810693/ndino351ldiavt3_1752833138.jpg', 2, 0),
(59, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810693/ndino351ldiavt4_1752833145.jpg', 3, 0),
(59, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810693/ndino351ldiavt5_1752833158.jpg', 4, 0),
(59, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810693/ndino351ldiavt6_1752833165.png', 5, 0),
(59, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810693/ndino351ldiavt7_1752833170.png', 6, 0),
(59, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810693/ndino351ldiavt8_1752833178.png', 7, 0),
(60, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810797/ndino352ldiavt1_1752833586.png', 0, 1),
(60, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810797/ndino352ldiavt2_1752833596.jpg', 1, 0),
(60, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810797/ndino352ldiavt3_1752833602.jpg', 2, 0),
(60, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810797/ndino352ldiavt4_1752833610.jpg', 3, 0),
(60, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810797/ndino352ldiavt5_1752833621.jpg', 4, 0),
(60, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810797/ndino352ldiavt6_1752833627.png', 5, 0),
(60, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810797/ndino352ldiavt7_1752833634.png', 6, 0),
(60, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810797/ndino352ldiavt8_1752833642.png', 7, 0),
(61, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810894/ndino353ldiavt1_1752833846.png', 0, 1),
(61, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810894/ndino353ldiavt2_1752833853.jpg', 1, 0),
(61, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810894/ndino353ldiavt3_1752833859.jpg', 2, 0),
(61, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810894/ndino353ldiavt4_1752833869.jpg', 3, 0),
(61, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810894/ndino353ldiavt5_1752833878.jpg', 4, 0),
(61, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810894/ndino353ldiavt6_1752833884.png', 5, 0),
(61, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810894/ndino353ldiavt7_1752833889.png', 6, 0),
(61, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752810894/ndino353ldiavt8_1752833895.png', 7, 0),
(62, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811031/ndino354ldiavt1_1752834017.png', 0, 1),
(62, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811031/ndino354ldiavt2_1752834023.jpg', 1, 0),
(62, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811031/ndino354ldiavt3_1752834028.jpg', 2, 0),
(62, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811031/ndino354ldiavt4_1752834036.jpg', 3, 0),
(62, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811031/ndino354ldiavt5_1752834041.jpg', 4, 0),
(62, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811031/ndino354ldiavt6_1752834047.png', 5, 0),
(62, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811031/ndino354ldiavt7_1752834053.png', 6, 0),
(62, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811031/ndino354ldiavt8_1752834060.png', 7, 0),
(63, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811124/ndino355ldiavt1_1752834316.png', 0, 1),
(63, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811124/ndino355ldiavt2_1752834327.jpg', 1, 0),
(63, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811124/ndino355ldiavt3_1752834334.jpg', 2, 0),
(63, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811124/ndino355ldiavt4_1752834340.jpg', 3, 0),
(63, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811124/ndino355ldiavt5_1752834346.jpg', 4, 0),
(63, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811124/ndino355ldiavt6_1752834353.png', 5, 0),
(63, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811124/ndino355ldiavt7_1752834360.png', 6, 0),
(63, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1752811124/ndino355ldiavt8_1752834368.png', 7, 0),
(64, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760581/ndino356ldiavt1_1776914472.png', 0, 1),
(64, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760581/ndino356ldiavt2_1776914472.jpg', 1, 0),
(64, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760581/ndino356ldiavt3_1776914472.jpg', 2, 0),
(64, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760581/ndino356ldiavt6_1776914472.png', 3, 0),
(64, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760581/ndino356ldiavt7_1776914477.png', 4, 0),
(64, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760581/ndino356ldiavt8_1776914463.png', 5, 0),
(65, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760758/ndino357ldiavt1_1776914573.png', 0, 1),
(65, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760758/ndino357ldiavt2_1776914585.jpg', 1, 0),
(65, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760758/ndino357ldiavt3_1776914579.jpg', 2, 0),
(65, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760758/ndino357ldiavt6_1776914579.png', 3, 0),
(65, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760758/ndino357ldiavt7_1776914593.png', 4, 0),
(65, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776760758/ndino357ldiavt8_1776914598.png', 5, 0),
(66, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761007/ndino358ldiavt1_1776914713.png', 0, 1),
(66, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761007/ndino358ldiavt2_1776914713.jpg', 1, 0),
(66, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761007/ndino358ldiavt3_1776914713.jpg', 2, 0),
(66, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761007/ndino358ldiavt6_1776914713.png', 3, 0),
(66, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761007/ndino358ldiavt7_1776914712.png', 4, 0),
(66, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761007/ndino358ldiavt8_1776914712.png', 5, 0),
(67, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761092/ndino359ldiavt1_1776915903.png', 0, 1),
(67, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761092/ndino359ldiavt2_1776915913.jpg', 1, 0),
(67, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761092/ndino359ldiavt3_1776915917.jpg', 2, 0),
(67, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761092/ndino359ldiavt6_1776915929.png', 3, 0),
(67, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761092/ndino359ldiavt7_1776915837.png', 4, 0),
(67, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761092/ndino359ldiavt8_1776915837.png', 5, 0),
(68, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761162/ndino360ldiavt1_1776916033.png', 0, 1),
(68, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761162/ndino360ldiavt2_1776916034.jpg', 1, 0),
(68, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761162/ndino360ldiavt3_1776916034.jpg', 2, 0),
(68, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761162/ndino360ldiavt6_1776916033.png', 3, 0),
(68, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761162/ndino360ldiavt7_1776916033.png', 4, 0),
(68, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761162/ndino360ldiavt8_1776916033.png', 5, 0),
(69, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761239/ndino361ldiavt1_1776916200.png', 0, 1),
(69, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761239/ndino361ldiavt2_1776916194.jpg', 1, 0),
(69, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761239/ndino361ldiavt3_1776916194.jpg', 2, 0),
(69, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761239/ndino361ldiavt6_1776916213.png', 3, 0),
(69, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761239/ndino361ldiavt7_1776916187.png', 4, 0),
(69, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761239/ndino361ldiavt8_1776916187.png', 5, 0),
(70, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761319/ndino362ldiavt1_1776916322.png', 0, 1),
(70, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761319/ndino362ldiavt2_1776916322.jpg', 1, 0),
(70, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761319/ndino362ldiavt3_1776916322.jpg', 2, 0),
(70, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761319/ndino362ldiavt6_1776916322.png', 3, 0),
(70, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761319/ndino362ldiavt7_1776916322.png', 4, 0),
(70, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761319/ndino362ldiavt8_1776916322.png', 5, 0),
(71, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761416/ndino363ldiavt1_1776916462.png', 0, 1),
(71, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761416/ndino363ldiavt8_1776916448.png', 1, 0),
(71, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761416/ndino363ldiavt2_1776916454.jpg', 2, 0),
(71, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761416/ndino363ldiavt3_1776916454.jpg', 3, 0),
(71, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761416/ndino363ldiavt7_1776916448.png', 4, 0),
(71, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761416/ndino363ldiavt6_1776916466.png', 5, 0),
(72, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761657/ndino364ldiavt1_1776916558.png', 0, 1),
(72, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761657/ndino364ldiavt2_1776916563.jpg', 1, 0),
(72, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761657/ndino364ldiavt3_1776916568.jpg', 2, 0),
(72, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761657/ndino364ldiavt8_1776916558.png', 3, 0),
(72, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761657/ndino364ldiavt6_1776916558.png', 4, 0);
INSERT INTO dbo.ProductImages (ProductID, ImageUrl, SortOrder, IsThumbnail) VALUES
(72, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761657/ndino364ldiavt7_1776916558.png', 5, 0),
(73, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761782/ndino365ldiavt1_1776916765.png', 0, 1),
(73, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761782/ndino365ldiavt6_1776916758.png', 1, 0),
(73, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761782/ndino365ldiavt3_1776916759.jpg', 2, 0),
(73, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761782/ndino365ldiavt2_1776916759.jpg', 3, 0),
(73, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761782/ndino365ldiavt7_1776916751.png', 4, 0),
(73, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761782/ndino365ldiavt8_1776916751.png', 5, 0),
(74, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761855/ndino366ldiavt1_1776916871.png', 0, 1),
(74, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761855/ndino366ldiavt2_1776916871.jpg', 1, 0),
(74, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761855/ndino366ldiavt3_1776916871.jpg', 2, 0),
(74, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761855/ndino366ldiavt8_1776916863.png', 3, 0),
(74, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761855/ndino366ldiavt7_1776916862.png', 4, 0),
(74, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776761855/ndino366ldiavt6_1776916875.png', 5, 0),
(75, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754056/ndino39ldia7_1716448454.png', 0, 1),
(75, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754056/ndino39ldia2_1716448454.jpg', 1, 0),
(75, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754056/ndino39ldia3_1716448454.jpg', 2, 0),
(75, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754056/ndino39ldia4_1716448454.jpg', 3, 0),
(75, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754056/ndino39ldia1_1716448454.jpg', 4, 0),
(75, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754056/ndino39ldia6_1716448454.png', 5, 0),
(75, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754056/ndino39ldia9_1716448454.png', 6, 0),
(75, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754056/ndino39ldia8_1716448455.png', 7, 0),
(76, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754084/nkc312ldia7_1716278055.png', 0, 1),
(76, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754084/nkc312ldia3_1716278055.jpg', 1, 0),
(76, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754084/nkc312ldia1_1716278055.jpg', 2, 0),
(76, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754084/nkc312ldia2_1716278055.jpg', 3, 0),
(76, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754084/nkc312ldia4_1716278054.jpg', 4, 0),
(76, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754084/nkc312ldia6_1716278055.png', 5, 0),
(76, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754084/nkc312ldia9_1716278055.png', 6, 0),
(76, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754084/nkc312ldia8_1716278055.png', 7, 0),
(77, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754032/ndino163-vv-1_1727492162.png', 0, 1),
(77, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754032/ndino163vv4_1727492169.jpg', 1, 0),
(77, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754032/ndino163vv2_1727492169.jpg', 2, 0),
(77, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754032/ndino163-vt-2_1727492190.jpg', 3, 0),
(77, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754032/ndino163-vt-4_1727492190.jpg', 4, 0),
(77, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754032/ndino163-vv-5_1727492177.png', 5, 0),
(77, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754032/ndino163-vv-3_1727492177.png', 6, 0),
(77, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754032/ndino163-vv-7_1727492177.png', 7, 0),
(78, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754033/ndino198kcvt7_1728533754.png', 0, 1),
(78, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754033/ndino198kcvt3_1728533754.jpg', 1, 0),
(78, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754033/ndino198kcvt1_1728533754.jpg', 2, 0),
(78, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754033/ndino198kcvt2_1728533754.jpg', 3, 0),
(78, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754033/ndino198kcvt4_1728533754.jpg', 4, 0),
(78, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754033/ndino198kcvt8_1728533754.png', 5, 0),
(78, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754033/ndino198kcvt6_1728533754.png', 6, 0),
(78, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754033/ndino198kcvt9_1728533754.png', 7, 0),
(79, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754021/ndino231vv1_1737605190.png', 0, 1),
(79, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754021/ndino231-vv-2_1728532715.jpg', 1, 0),
(79, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754021/ndino231-vv-4_1728532715.jpg', 2, 0),
(79, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754021/ndino231-vv-7_1737604702.png', 3, 0),
(79, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754021/ndino231-vv-5_1737604713.png', 4, 0),
(79, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754021/ndino231-vv-3_1737604702.png', 5, 0),
(80, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102626/ndino259-16_1728293916.png', 0, 1),
(80, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102626/ndino2592_1728293916.jpg', 1, 0),
(80, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102626/ndino2593_1728293916.jpg', 2, 0),
(80, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102626/ndino2591_1728293916.jpg', 3, 0),
(80, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102626/ndino2594_1728293916.jpg', 4, 0),
(80, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102626/ndino259-18_1728293916.png', 5, 0),
(80, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102626/ndino259-19_1728293916.png', 6, 0),
(81, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754022/ndino2607_1716274519.png', 0, 1),
(81, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754022/ndino2603_1716274542.jpg', 1, 0),
(81, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754022/ndino2602_1716274542.jpg', 2, 0),
(81, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754022/ndino2601_1716274542.jpg', 3, 0),
(81, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754022/ndino2604_1716274542.jpg', 4, 0),
(81, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754022/ndino260-16_1716274519.png', 5, 0),
(81, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754022/ndino260-18_1716274519.png', 6, 0),
(81, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754022/ndino260-19_1716274519.png', 7, 0),
(81, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754022/ndino260-26_1716274536.png', 8, 0),
(81, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754022/ndino260-28_1716274536.png', 9, 0),
(82, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754035/ndino2657_1716368586.png', 0, 1),
(82, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754035/ndino2651_1716366837.jpg', 1, 0),
(82, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754035/ndino2653_1716366837.jpg', 2, 0),
(82, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754035/ndino2654_1716366837.jpg', 3, 0),
(82, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754035/ndino2652_1716366837.jpg', 4, 0),
(82, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754035/ndino2656_1716366838.png', 5, 0),
(82, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754035/ndino2658_1716368586.png', 6, 0),
(82, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754035/ndino2659_1716366837.png', 7, 0),
(83, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102757/ndino266-210_1728294456.png', 0, 1),
(83, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102757/ndino2662_1728294468.jpg', 1, 0),
(83, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102757/ndino2661_1728294468.jpg', 2, 0),
(83, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102757/ndino2663_1728294468.jpg', 3, 0),
(83, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102757/ndino2666_1728294468.jpg', 4, 0),
(83, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102757/ndino2667_1728294468.jpg', 5, 0),
(83, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102757/ndino2664_1728294468.jpg', 6, 0),
(83, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102757/ndino2665_1728294468.jpg', 7, 0),
(84, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754077/ndino2687_1716368914.png', 0, 1),
(84, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754077/ndino2682_1716368913.jpg', 1, 0),
(84, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754077/ndino2683_1716368914.jpg', 2, 0),
(84, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754077/ndino2681_1716368913.jpg', 3, 0),
(84, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754077/ndino2684_1716368913.jpg', 4, 0),
(84, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754077/ndino2686_1716368914.png', 5, 0),
(84, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754077/ndino2688_1716368914.png', 6, 0),
(85, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754078/ndino2697_1716368570.png', 0, 1),
(85, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754078/ndino2692_1716368570.jpg', 1, 0),
(85, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754078/ndino2693_1716368570.jpg', 2, 0),
(85, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754078/ndino2691_1716368570.jpg', 3, 0),
(85, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754078/ndino2694_1716368569.jpg', 4, 0),
(85, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754078/ndino2698_1716368570.png', 5, 0),
(85, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754078/ndino2696_1716368570.png', 6, 0),
(86, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754079/ndino2707_1716367215.png', 0, 1),
(86, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754079/ndino2703_1716367215.jpg', 1, 0),
(86, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754079/ndino2702_1716367215.jpg', 2, 0),
(86, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754079/ndino2704_1716367215.jpg', 3, 0),
(86, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754079/ndino2701_1716367215.jpg', 4, 0),
(86, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754079/ndino2708_1716367215.png', 5, 0),
(86, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754079/ndino2706_1716367215.png', 6, 0),
(87, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754034/ndino280-vt-3_1716779943.png', 0, 1),
(87, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754034/ndino280-vt-4_1716779910.jpg', 1, 0),
(87, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754034/ndino280-vt-2_1716779943.jpg', 2, 0),
(87, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754034/ndino280-vt-7_1716779942.jpg', 3, 0),
(87, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754034/ndino280-vt-8_1716779910.jpg', 4, 0),
(87, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754034/ndino280-vt-5_1716779943.png', 5, 0),
(87, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754034/ndino280-vt-1_1716779943.png', 6, 0),
(87, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754034/ndino280-vt-6_1716779943.png', 7, 0),
(88, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754023/ndino281ldia7_1716275267.png', 0, 1),
(88, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754023/ndino281ldia1_1716275267.jpg', 1, 0),
(88, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754023/ndino281ldia3_1716275267.jpg', 2, 0),
(88, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754023/ndino281ldia2_1716275266.jpg', 3, 0),
(88, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754023/ndino281ldia4_1716275266.jpg', 4, 0),
(88, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754023/ndino281ldia9_1716275266.png', 5, 0),
(88, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754023/ndino281ldia6_1716275267.png', 6, 0),
(88, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754023/ndino281ldia8_1716275267.png', 7, 0),
(89, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754024/ndino2826_1716277123.png', 0, 1),
(89, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754024/ndino2822_1716277123.jpg', 1, 0),
(89, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754024/ndino2823_1716277123.jpg', 2, 0),
(89, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754024/ndino2824_1716277123.jpg', 3, 0),
(89, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754024/ndino2821_1716277123.jpg', 4, 0),
(89, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754024/ndino2827_1716277123.png', 5, 0),
(89, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754024/ndino2824_1716277123.png', 6, 0),
(89, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754024/ndino2825_1716277123.png', 7, 0),
(90, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754026/ndino28561_1716780529.png', 0, 1),
(90, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754026/ndino2853-1_1729581644.jpg', 1, 0),
(90, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754026/ndino2854-1_1729581644.jpg', 2, 0),
(90, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754026/ndino2851-1_1729581644.jpg', 3, 0),
(90, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754026/ndino2852-1_1729581644.jpg', 4, 0),
(90, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754026/ndino28511_1716780507.png', 5, 0),
(90, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754026/ndino28551_1716780523.png', 6, 0),
(90, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754026/ndino28571_1716780535.png', 7, 0),
(91, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754027/ndino28662_1716278055.png', 0, 1),
(91, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754027/ndino2864_1716278055.jpg', 1, 0),
(91, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754027/ndino2861_1716278055.jpg', 2, 0),
(91, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754027/ndino2862_1716278055.jpg', 3, 0),
(91, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754027/ndino2863_1716278055.jpg', 4, 0),
(91, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754027/ndino28652_1716278055.png', 5, 0),
(91, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754027/ndino28612_1716278055.png', 6, 0),
(91, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754027/ndino28672_1716278055.png', 7, 0),
(92, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754028/ndino28861_1716278653.png', 0, 1),
(92, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754028/ndino2882_1729654753.jpg', 1, 0),
(92, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754028/ndino2883_1729654753.jpg', 2, 0),
(92, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754028/ndino2884_1729654753.jpg', 3, 0),
(92, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754028/ndino2881_1729654753.jpg', 4, 0),
(92, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754028/ndino28851_1716278653.png', 5, 0),
(92, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754028/ndino28811_1716278653.png', 6, 0),
(92, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754028/ndino28871_1716278653.png', 7, 0),
(93, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754029/ndino28961_1716779262.png', 0, 1),
(93, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754029/ndino2892_1716779209.jpg', 1, 0),
(93, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754029/ndino2893_1716779226.jpg', 2, 0),
(93, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754029/ndino2894_1716779246.jpg', 3, 0),
(93, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754029/ndino2891_1716779194.jpg', 4, 0),
(93, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754029/ndino28951_1716779254.png', 5, 0),
(93, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754029/ndino28911_1716779237.png', 6, 0),
(93, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754029/ndino28971_1716779280.png', 7, 0),
(94, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754030/ndino29361_1716364365.png', 0, 1),
(94, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754030/ndino2933_1716364349.jpg', 1, 0),
(94, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754030/ndino2932_1716364349.jpg', 2, 0),
(94, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754030/ndino2931_1716364349.jpg', 3, 0),
(94, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754030/ndino2934_1716364349.jpg', 4, 0),
(94, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754030/ndino29351_1716364365.png', 5, 0),
(94, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754030/ndino29311_1716364365.png', 6, 0),
(94, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754030/ndino29371_1716364365.png', 7, 0),
(95, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754031/ndino29461_1716365174.png', 0, 1),
(95, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754031/ndino2942_1716364997.jpg', 1, 0),
(95, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754031/ndino2943_1716364997.jpg', 2, 0),
(95, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754031/ndino2944_1716364998.jpg', 3, 0),
(95, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754031/ndino2941_1716364998.jpg', 4, 0),
(95, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754031/ndino29451_1716365032.png', 5, 0),
(95, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754031/ndino29411_1716365118.png', 6, 0),
(95, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754031/ndino29471_1716365174.png', 7, 0),
(96, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477266/ndino338vv1_1733539886.png', 0, 1),
(96, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477266/ndino338vv4_1733539893.jpg', 1, 0),
(96, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477266/ndino338vv2_1733539893.jpg', 2, 0),
(96, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477266/ndino338vv3_1733539893.png', 3, 0),
(96, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477266/ndino338vv5_1733539893.png', 4, 0),
(96, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477266/ndino338vv7_1733539893.png', 5, 0),
(97, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477135/ndino339vv1_1733539342.png', 0, 1),
(97, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477135/ndino3392_1733539333.jpg', 1, 0),
(97, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477135/ndino3393_1733539333.jpg', 2, 0),
(97, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477135/ndino3394_1733539333.jpg', 3, 0),
(97, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477135/ndino3391_1733539333.jpg', 4, 0),
(97, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477135/ndino339vv7_1733539349.png', 5, 0),
(97, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477135/ndino339vv3_1733539355.png', 6, 0),
(97, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733477135/ndino339vv5_1733539342.png', 7, 0),
(98, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754009/ndino39vv1_1735118714.png', 0, 1),
(98, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754009/ndino393_1715650957.jpg', 1, 0),
(98, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754009/ndino391_1715650957.jpg', 2, 0),
(98, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754009/ndino39-vv-7_1735118429.png', 3, 0),
(98, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754009/ndino39-vv-3_1735118429.png', 4, 0),
(98, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754009/ndino39-vv-5_1735118429.png', 5, 0),
(99, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754036/ndino206mo-vh-1_1728008849.png', 0, 1),
(99, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754036/ndino206ldiavh1_1722996922.jpg', 1, 0),
(99, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754036/ndino206ldiavh2_1722996922.jpg', 2, 0),
(99, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754036/ndino206ldiavh3_1722996922.jpg', 3, 0),
(99, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754036/ndino206ldiavh4_1722996922.jpg', 4, 0),
(99, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754036/ndino206mo-vh-3_1728008849.png', 5, 0),
(99, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754036/ndino206mo-vh-4_1728008849.png', 6, 0),
(99, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754036/ndino206mo-vh-5_1728008849.png', 7, 0),
(100, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754037/ndino208movt1_1737605128.png', 0, 1),
(100, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754037/ndino208ldiavh2_1722997357.jpg', 1, 0),
(100, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754037/ndino208ldiavh1_1722997357.jpg', 2, 0),
(100, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754037/ndino208ldiavh4_1722997357.jpg', 3, 0),
(100, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754037/ndino208ldiavh3_1722997357.jpg', 4, 0),
(100, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754037/ndino208mo-vt-5_1737604277.png', 5, 0),
(100, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754037/ndino208mo-vt-3_1737604358.png', 6, 0),
(100, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754037/ndino208mo-vt-7_1737604277.png', 7, 0),
(101, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1725941871/ndino20-vv-1_1735117497.png', 0, 1),
(101, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1725941871/ndino20-vv-2_1735117555.jpg', 1, 0),
(101, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1725941871/ndino20-vv-4_1735117555.jpg', 2, 0),
(101, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1725941871/ndino20-vv-7_1735117497.png', 3, 0),
(101, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1725941871/ndino20-vv-5_1735117497.png', 4, 0),
(101, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1725941871/ndino20-vv-3_1735117497.png', 5, 0),
(102, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754038/ndino214mo-vt-1_1735120430.png', 0, 1),
(102, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754038/ndino214movt4_1729674700.jpg', 1, 0),
(102, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754038/ndino214movt2_1729674700.jpg', 2, 0),
(102, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754038/ndino214mo-vt-3_1735120430.png', 3, 0),
(102, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754038/ndino214mo-vt-5_1735120430.png', 4, 0),
(102, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754038/ndino214mo-vt-7_1735120430.png', 5, 0),
(103, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754080/ndino215mo-1vt1_1730455696.png', 0, 1),
(103, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754080/ndino215movt2_1729664691.jpg', 1, 0),
(103, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754080/ndino215movt4_1729664691.jpg', 2, 0),
(103, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754080/ndino215-vt-1-1_1718246936.png', 3, 0),
(103, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754080/ndino215mo-1-vt-7_1730455696.png', 4, 0),
(103, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754080/ndino215mo-1-vt-5_1730455696.png', 5, 0),
(104, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754041/ndino217movt1_1735202506.png', 0, 1),
(104, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754041/ndino2172_1716431238.jpg', 1, 0),
(104, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754041/ndino2173_1716431238.jpg', 2, 0),
(104, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754041/ndino217mo-vt-3_1735120689.png', 3, 0),
(104, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754041/ndino217mo-vt-5_1735120689.png', 4, 0),
(104, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754041/ndino217mo-vt-7_1735120689.png', 5, 0),
(105, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754046/ndino249mo6_1716432272.png', 0, 1),
(105, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754046/ndino249vt2_1786085842.jpg', 1, 0),
(105, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754046/ndino249vt3_1786092730.png', 2, 0),
(105, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754046/ndino249vt4_1786085847.jpg', 3, 0),
(105, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754046/ndino249mo1_1716432272.png', 4, 0),
(105, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754046/ndino249mo5_1716432272.png', 5, 0),
(105, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754046/ndino249mo7_1716432272.png', 6, 0),
(106, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754047/ndino252mo6_1716436464.png', 0, 1),
(106, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754047/ndino2522_1716436464.jpg', 1, 0),
(106, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754047/ndino2523_1716436463.jpg', 2, 0),
(106, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754047/ndino2524_1716436464.jpg', 3, 0),
(106, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754047/ndino2521_1716436464.jpg', 4, 0),
(106, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754047/ndino252mo1_1716436464.png', 5, 0),
(106, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754047/ndino252mo5_1716436464.png', 6, 0),
(106, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754047/ndino252mo7_1716436464.png', 7, 0),
(107, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754042/ndino253mo-vt-1_1737604792.png', 0, 1),
(107, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754042/ndino253mo4_1716431346.jpg', 1, 0),
(107, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754042/ndino253mo3_1716431345.jpg', 2, 0),
(107, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754042/ndino253mo2_1716431345.jpg', 3, 0),
(107, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754042/ndino253mo5_1716431345.jpg', 4, 0),
(107, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754042/ndino253mo1_1716431346.jpg', 5, 0),
(107, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754042/ndino253mo-vt-3_1737604792.png', 6, 0),
(107, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754042/ndino253mo-vt-5_1737604791.png', 7, 0),
(107, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754042/ndino253mo-vt-7_1737604792.png', 8, 0),
(108, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754043/ndino254mo-vt-1_1735120864.png', 0, 1),
(108, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754043/ndino254mo1_1716431465.jpg', 1, 0),
(108, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754043/ndino254mo5_1716431465.jpg', 2, 0),
(108, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754043/ndino254mo3_1716431465.jpg', 3, 0),
(108, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754043/ndino254mo-vt-7_1735120864.png', 4, 0),
(108, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754043/ndino254mo-vt-3_1735120864.png', 5, 0),
(108, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754043/ndino254mo-vt-5_1735120864.png', 6, 0),
(109, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754044/ndino256mo-vt-1_1737604847.png', 0, 1),
(109, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754044/ndino2563_1786085981.jpg', 1, 0),
(109, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754044/ndino256vt3_1786092757.png', 2, 0),
(109, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754044/ndino256vtvt4_1786085986.jpg', 3, 0),
(109, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754044/ndino256mo-vt-3_1737604847.png', 4, 0),
(109, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754044/ndino256mo-vt-5_1737604846.png', 5, 0),
(109, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754044/ndino256mo-vt-7_1737604847.png', 6, 0),
(110, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754045/ndino257mo-vt-1_1737604906.png', 0, 1),
(110, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754045/ndino257mo3_1716431959.jpg', 1, 0),
(110, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754045/ndino257mo2_1716431959.jpg', 2, 0),
(110, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754045/ndino257mo6_1716431959.jpg', 3, 0),
(110, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754045/ndino257mo1_1716431959.jpg', 4, 0),
(110, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754045/ndino257mo5_1716431959.jpg', 5, 0),
(110, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754045/ndino257mo4_1716431959.jpg', 6, 0),
(110, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754045/ndino257mo-vt-7_1737604906.png', 7, 0),
(110, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754045/ndino257mo-vt-3_1737604906.png', 8, 0),
(110, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754045/ndino257mo-vt-5_1737604906.png', 9, 0),
(111, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754048/ndino290mo6_1716437722.png', 0, 1),
(111, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754048/ndino2903_1716437179.jpg', 1, 0),
(111, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754048/ndino2902_1716437179.jpg', 2, 0),
(111, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754048/ndino2904_1716437179.jpg', 3, 0),
(111, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754048/ndino2901_1716437179.jpg', 4, 0),
(111, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754048/ndino290mo1_1716437722.png', 5, 0),
(111, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754048/ndino290mo5_1716437722.png', 6, 0),
(111, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754048/ndino290mo7_1716437722.png', 7, 0),
(112, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754049/ndino303mo6_1716438126.png', 0, 1),
(112, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754049/ndino3033_1716438081.jpg', 1, 0),
(112, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754049/ndino3034_1716438081.jpg', 2, 0),
(112, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754049/ndino3032_1716438081.jpg', 3, 0),
(112, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754049/ndino303mo1_1716438095.png', 4, 0),
(112, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754049/ndino303mo5_1716438095.png', 5, 0),
(112, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754049/ndino303mo7_1716438126.png', 6, 0),
(113, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754050/ndino304mo6_1716438523.png', 0, 1),
(113, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754050/ndino3042_1716438425.jpg', 1, 0),
(113, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754050/ndino3044_1716438425.jpg', 2, 0),
(113, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754050/ndino3043_1716438425.jpg', 3, 0),
(113, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754050/ndino304mo1_1716438436.png', 4, 0),
(113, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754050/ndino304mo5_1716438436.png', 5, 0),
(113, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754050/ndino304mo7_1716438425.png', 6, 0),
(114, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752851/ndino324movt1_1731894075.png', 0, 1),
(114, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752851/ndino324vt2-2_1786085384.jpg', 1, 0),
(114, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752851/ndino324vt3_1786092511.png', 2, 0),
(114, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752851/ndino324vt4-2_1786085391.jpg', 3, 0),
(114, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752851/ndino324movt2_1731894075.png', 4, 0),
(114, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752851/ndino324movt3_1731894102.png', 5, 0),
(114, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752851/ndino324movt4_1731894102.png', 6, 0),
(115, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752853/ndino325movt1_1731915297.png', 0, 1),
(115, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752853/ndino325vt4_1731915281.jpg', 1, 0),
(115, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752853/ndino325vt2_1731915309.jpg', 2, 0),
(115, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752853/ndino325movt3_1731915297.png', 3, 0),
(115, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752853/ndino325movt4_1731915297.png', 4, 0),
(115, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752853/ndino325movt2_1731915297.png', 5, 0),
(116, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752855/ndino326movt1_1731916461.png', 0, 1),
(116, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752855/ndino326vt4_1731916460.jpg', 1, 0),
(116, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752855/ndino326vt2_1731916460.jpg', 2, 0),
(116, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752855/ndino326movt2_1731916461.png', 3, 0),
(116, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752855/ndino326movt3_1731916461.png', 4, 0),
(116, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752855/ndino326movt4_1731916461.png', 5, 0),
(117, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752857/ndino327movt1_1731916680.png', 0, 1),
(117, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752857/ndino3273_1786085457.jpg', 1, 0),
(117, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752857/ndino327vt3_1786092584.png', 2, 0),
(117, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752857/ndino327vtvt4_1786085477.jpg', 3, 0),
(117, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752857/ndino327movt2_1731916680.png', 4, 0),
(117, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752857/ndino327movt3_1731916680.png', 5, 0),
(117, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752857/ndino327movt4_1731916680.png', 6, 0),
(118, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752861/ndino329mo-vt-1_1732009296.png', 0, 1),
(118, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752861/ndino329vt4_1731917463.jpg', 1, 0),
(118, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752861/ndino329vt2_1731917463.jpg', 2, 0),
(118, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752861/ndino329-vt-7_1731917432.png', 3, 0),
(118, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752861/ndino329-vt-3_1731917432.png', 4, 0),
(118, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752861/ndino329-vt-5_1731917455.png', 5, 0),
(119, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752863/ndino330ldia-vt-1_1732009337.png', 0, 1),
(119, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752863/ndino330vt2_1731918084.jpg', 1, 0),
(119, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752863/ndino330vt4_1731918083.jpg', 2, 0),
(119, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752863/ndino330-vt-7_1731917713.png', 3, 0),
(119, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752863/ndino330-vt-3_1731917713.png', 4, 0),
(119, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752863/ndino330-vt-5_1731918009.png', 5, 0),
(120, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752865/ndino331ldia-vt-1_1732009473.png', 0, 1),
(120, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752865/ndino331vt4_1731918264.jpg', 1, 0),
(120, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752865/ndino331vt2_1731918264.jpg', 2, 0),
(120, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752865/ndino331-vt-3_1731918223.png', 3, 0),
(120, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752865/ndino331-vt-5_1731918281.png', 4, 0),
(120, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752865/ndino331-vt-7_1731918222.png', 5, 0),
(121, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752867/ndino333ldia-vt-1_1733543693.png', 0, 1),
(121, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752867/ndino333vt4_1731919210.jpg', 1, 0),
(121, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752867/ndino333vt2_1731919210.jpg', 2, 0),
(121, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752867/ndino333-vt-3_1731919211.png', 3, 0),
(121, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752867/ndino333-vt-5_1731919211.png', 4, 0),
(121, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752867/ndino333-vt-7_1731919210.png', 5, 0),
(122, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752869/ndino334ldia-vt-1_1732009638.png', 0, 1),
(122, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752869/ndino334vt4_1731919789.jpg', 1, 0),
(122, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752869/ndino334vt2_1731919789.jpg', 2, 0),
(122, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752869/ndino334-vt-3_1731919790.png', 3, 0),
(122, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752869/ndino334-vt-5_1731919790.png', 4, 0),
(122, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1731752869/ndino334-vt-7_1731919789.png', 5, 0),
(123, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852061/ndino172kc7_1723024751.png', 0, 1),
(123, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852061/ndino172kc2_1723024751.jpg', 1, 0),
(123, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852061/ndino172kc3_1723024751.jpg', 2, 0),
(123, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852061/ndino172kc4_1723024751.jpg', 3, 0),
(123, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852061/ndino172kc6_1723024751.png', 4, 0),
(123, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852061/ndino172kc1_1723024751.jpg', 5, 0),
(123, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852061/ndino172kc8_1723024751.png', 6, 0),
(123, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852061/ndino172kc9_1723024751.png', 7, 0),
(124, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852062/ndino173kc7_1723024310.png', 0, 1),
(124, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852062/ndino173kc2_1723024310.jpg', 1, 0),
(124, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852062/ndino173kc3_1723024310.jpg', 2, 0),
(124, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852062/ndino173kc4_1723024310.jpg', 3, 0),
(124, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852062/ndino173kc1_1723024310.jpg', 4, 0),
(124, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852062/ndino173kc6_1723024310.png', 5, 0),
(124, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852062/ndino173kc8_1723024310.png', 6, 0),
(124, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852062/ndino173kc9_1723024310.png', 7, 0),
(125, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852063/ndino174kc7_1729564344.png', 0, 1),
(125, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852063/ndino174kc4_1729564344.jpg', 1, 0),
(125, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852063/ndino174kc2_1729564344.jpg', 2, 0),
(125, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852063/ndino174kc3_1729564344.jpg', 3, 0),
(125, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852063/ndino174kc1_1729564344.jpg', 4, 0),
(125, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852063/ndino174kc8_1729564344.png', 5, 0),
(125, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852063/ndino174kc6_1729564344.png', 6, 0),
(125, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852063/ndino174kc9_1729564344.png', 7, 0),
(126, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852065/ndino175kc7_1723023584.png', 0, 1),
(126, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852065/ndino175kc2_1723023584.jpg', 1, 0),
(126, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852065/ndino175kc3_1723023584.jpg', 2, 0),
(126, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852065/ndino175kc4_1723023584.jpg', 3, 0),
(126, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852065/ndino175kc1_1723023584.jpg', 4, 0),
(126, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852065/ndino175kc6_1723023584.png', 5, 0),
(126, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852065/ndino175kc8_1723023584.png', 6, 0),
(126, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852065/ndino175kc9_1723023584.png', 7, 0),
(127, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852066/ndino176kcvv7_1730102608.png', 0, 1),
(127, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852066/ndino176kcvv2_1730102608.jpg', 1, 0),
(127, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852066/ndino176kcvv3_1730102608.jpg', 2, 0),
(127, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852066/ndino176kcvv1_1730102608.jpg', 3, 0),
(127, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852066/ndino176kcvv4_1730102608.jpg', 4, 0),
(127, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852066/ndino176kcvv8_1730102608.png', 5, 0),
(127, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852066/ndino176kcvv6_1730102618.png', 6, 0),
(127, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852066/ndino176kcvv9_1730102608.png', 7, 0),
(128, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852067/ndino177kc7_1723024679.png', 0, 1),
(128, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852067/ndino177kc2_1723024679.jpg', 1, 0),
(128, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852067/ndino177kc3_1723024679.jpg', 2, 0),
(128, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852067/ndino177kc4_1723024679.jpg', 3, 0),
(128, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852067/ndino177kc1_1723024679.jpg', 4, 0),
(128, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852067/ndino177kc6_1723024679.png', 5, 0),
(128, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852067/ndino177kc8_1723024679.png', 6, 0),
(129, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852068/ndino179kc7_1723023690.png', 0, 1),
(129, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852068/ndino179kc1_1723023690.jpg', 1, 0),
(129, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852068/ndino179kc3_1723023690.jpg', 2, 0),
(129, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852068/ndino179kc4_1723023690.jpg', 3, 0),
(129, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852068/ndino179kc2_1723023690.jpg', 4, 0),
(129, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852068/ndino179kc6_1723023690.png', 5, 0),
(129, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852068/ndino179kc8_1723023690.png', 6, 0),
(129, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852068/ndino179kc9_1723023690.png', 7, 0),
(130, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852070/ndino180kcvt7_1729563098.png', 0, 1),
(130, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852070/ndino180kc2_1729563103.jpg', 1, 0),
(130, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852070/ndino180kc1_1729563103.jpg', 2, 0),
(130, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852070/ndino180kc3_1729563103.jpg', 3, 0),
(130, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852070/ndino180kc4_1729563103.jpg', 4, 0),
(130, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852070/ndino180kcvt6_1729563091.png', 5, 0),
(130, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852070/ndino180kcvt8_1729563091.png', 6, 0),
(130, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852070/ndino180kcvt9_1729563091.png', 7, 0),
(131, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852072/ndino198kcvt7_1730186038.png', 0, 1),
(131, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852072/ndino198kcvt1_1730186045.jpg', 1, 0),
(131, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852072/ndino198kcvt3_1730186045.jpg', 2, 0),
(131, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852072/ndino198kcvt2_1730186045.jpg', 3, 0),
(131, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852072/ndino198kcvt4_1730186045.jpg', 4, 0),
(131, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852072/ndino198kcvt6_1730186038.png', 5, 0),
(131, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852072/ndino198kcvt8_1730186038.png', 6, 0),
(131, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852072/ndino198kcvt9_1730186038.png', 7, 0),
(132, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754074/ndino206ldia7_1717665315.png', 0, 1),
(132, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754074/ndino206ldia3_1717665124.jpg', 1, 0),
(132, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754074/ndino206ldia1_1717665124.jpg', 2, 0),
(132, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754074/ndino206ldia2_1717665124.jpg', 3, 0),
(132, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754074/ndino206ldia4_1717665124.jpg', 4, 0),
(132, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754074/ndino206ldia6_1717665315.png', 5, 0),
(132, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754074/ndino206ldia9_1717665315.png', 6, 0),
(132, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754074/ndino206ldia8_1717665315.png', 7, 0),
(133, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754076/ndino235bldia7_1716369261.png', 0, 1),
(133, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754076/ndino235bldia1_1716369260.jpg', 1, 0),
(133, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754076/ndino235bldia2_1716369261.jpg', 2, 0),
(133, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754076/ndino2351_1716369260.jpg', 3, 0),
(133, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754076/ndino235bldia3_1716369260.jpg', 4, 0),
(133, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754076/ndino235bldia4_1716369260.jpg', 5, 0),
(133, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754076/ndino235bldia6_1716369261.png', 6, 0),
(133, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754076/ndino235bldia9_1716369260.png', 7, 0),
(133, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754076/ndino235bldia8_1716369261.png', 8, 0),
(134, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852076/ndino248kc7_1723022972.png', 0, 1),
(134, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852076/ndino248kc2_1723022972.jpg', 1, 0),
(134, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852076/ndino248kc3_1723022972.jpg', 2, 0),
(134, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852076/ndino248kc4_1723022972.jpg', 3, 0),
(134, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852076/ndino248kc1_1723022972.jpg', 4, 0),
(134, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852076/ndino248kc6_1723022972.png', 5, 0),
(134, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852076/ndino248kc8_1723022972.png', 6, 0),
(134, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852076/ndino248kc9_1723022972.png', 7, 0),
(135, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754075/ndino255-1kc7_1725067062.png', 0, 1),
(135, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754075/ndino255-vt-2_1728898399.jpg', 1, 0),
(135, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754075/ndino255-vt-4_1728898399.jpg', 2, 0),
(135, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754075/ndino255-1kc6_1725067047.png', 3, 0),
(135, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754075/ndino255-1kc8_1725067029.png', 4, 0),
(135, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754075/ndino255-1kc9_1725067309.png', 5, 0),
(136, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102526/ndino255-2kc7_1728293370.png', 0, 1),
(136, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102526/ndino255-2kc3_1728293375.jpg', 1, 0),
(136, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102526/ndino255-2kc2_1728293375.jpg', 2, 0),
(136, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102526/ndino255-2kc4_1728293375.jpg', 3, 0),
(136, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102526/ndino255-2kc1_1728293375.jpg', 4, 0),
(136, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102526/ndino255-2kc6_1728293370.png', 5, 0),
(136, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102526/ndino255-2kc8_1728293370.png', 6, 0),
(136, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1728102526/ndino255-2kc9_1728293370.png', 7, 0),
(137, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852077/ndino258kc7_1723024216.png', 0, 1),
(137, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852077/ndino258kc2_1723024216.jpg', 1, 0),
(137, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852077/ndino258kc3_1723024216.jpg', 2, 0),
(137, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852077/ndino258kc1_1723024216.jpg', 3, 0),
(137, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852077/ndino258kc6_1723024216.png', 4, 0),
(137, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852077/ndino258kc8_1723024216.png', 5, 0),
(137, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852077/ndino258kc9_1723024216.png', 6, 0),
(138, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852078/ndino26kc7_1727496874.png', 0, 1),
(138, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852078/ndino26kc1_1727496842.jpg', 1, 0),
(138, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852078/ndino26kc2_1727496851.jpg', 2, 0),
(138, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852078/ndino26kc3_1727496859.jpg', 3, 0),
(138, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852078/ndino26kc4_1727496863.jpg', 4, 0),
(138, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852078/ndino26kc6_1727496871.png', 5, 0),
(138, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722852078/ndino26kc8_1727496878.png', 6, 0),
(139, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651417/ncz032ldia7_1723020778.png', 0, 1),
(139, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651417/ncz032ldia3_1728030559.jpg', 1, 0),
(139, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651417/ncz032ldia1_1728030550.jpg', 2, 0),
(139, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651417/ncz032ldia4_1728030559.jpg', 3, 0),
(139, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651417/ncz032ldia5_1728030550.jpg', 4, 0),
(139, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651417/ncz032ldia2_1728030550.jpg', 5, 0),
(140, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651438/ncz041ldia7_1723016239.png', 0, 1),
(140, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651438/ncz041ldia3_1728029160.jpg', 1, 0),
(140, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651438/ncz041ldia2_1728029160.jpg', 2, 0),
(140, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651438/ncz041ldia1_1728029160.jpg', 3, 0),
(140, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651438/ncz041ldia4_1728029160.jpg', 4, 0),
(140, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651438/ncz041ldia5_1728029160.jpg', 5, 0),
(141, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651513/ncz077ldiavh1_1725508672.png', 0, 1);
INSERT INTO dbo.ProductImages (ProductID, ImageUrl, SortOrder, IsThumbnail) VALUES
(141, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651513/ncz077ldiavh3_1725960880.jpg', 1, 0),
(141, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651513/ncz077ldiavh5_1725960880.jpg', 2, 0),
(141, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651513/ncz077ldiavh1_1725960880.jpg', 3, 0),
(141, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651513/ncz077ldiamvh3_1725508672.png', 4, 0),
(141, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651513/ncz077ldiamvh7_1725508672.png', 5, 0),
(141, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651513/ncz077ldiawvh9_1725508672.png', 6, 0),
(141, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1722651513/ncz077ldiawvh5_1725508681.png', 7, 0),
(142, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742441133/ncz085ldiavv1_1742885003.png', 0, 1),
(142, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742441133/ncz085ldiavv2_1742885003.jpg', 1, 0),
(142, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441133/ncz085ldiawvv8_1752919120.jpg', 2, 0),
(142, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441133/ncz085ldiawvv10_1752919120.jpg', 3, 0),
(142, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441133/ncz085ldiamvv4_1752919133.jpg', 4, 0),
(142, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441133/ncz085ldiawvv6_1752919134.jpg', 5, 0),
(142, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441133/ncz085ldiawvv7_1752919156.png', 6, 0),
(142, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441133/ncz085ldiawvv9_1752919147.png', 7, 0),
(142, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441133/ncz085ldiamvv3_1752919169.png', 8, 0),
(142, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441133/ncz085ldiamvv5_1752919169.png', 9, 0),
(143, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782098837/ncz099vv1_1786077123.png', 0, 1),
(143, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782098837/ncz099vv2_1786077128.jpg', 1, 0),
(143, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782098837/ncz099vv4_1786077136.jpg', 2, 0),
(143, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782098837/ncz099vv3_1786077132.jpg', 3, 0),
(143, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782098837/ncz099mvv8_1786077148.png', 4, 0),
(143, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782098837/ncz099wvv10_1786077157.png', 5, 0),
(143, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782098837/ncz099mvv7_1786077144.png', 6, 0),
(143, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782098837/ncz099wvv9_1786077153.png', 7, 0),
(144, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786091244/ncz112vv1_1786091553.png', 0, 1),
(144, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786091244/ncz112vv2_1786091553.jpg', 1, 0),
(144, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786091244/ncz112vv4_1786091553.jpg', 2, 0),
(144, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786091244/ncz112vv3_1786091553.jpg', 3, 0),
(144, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786091244/ncz112mvv8_1786091552.png', 4, 0),
(144, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786091244/ncz112mvv7_1786091553.png', 5, 0),
(144, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786091244/ncz112w9_1786091553.png', 6, 0),
(144, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786091244/ncz112w10_1786091552.png', 7, 0),
(145, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099092/ncz113ldiavv1_1782202188.png', 0, 1),
(145, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099092/ncz113ldiavv4_1786089645.jpg', 1, 0),
(145, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099092/ncz113ldiavv3_1786089645.jpg', 2, 0),
(145, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099092/ncz113ldiavv2_1786089645.jpg', 3, 0),
(145, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099092/ncz113ldiawvv10_1782202172.png', 4, 0),
(145, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099092/ncz113ldiawvv9_1782202203.png', 5, 0),
(145, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099092/ncz113ldiamvv8_1782202171.png', 6, 0),
(145, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099092/ncz113ldiamvv7_1782202198.png', 7, 0),
(146, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099904/ncz115ldiavv1_1782204533.png', 0, 1),
(146, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099904/ncz115ldiavv2_1786086510.jpg', 1, 0),
(146, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099904/ncz115ldiavv3_1786086517.jpg', 2, 0),
(146, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099904/ncz115ldiamvv7_1782204533.png', 3, 0),
(146, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099904/ncz115ldiawvv10_1782204526.png', 4, 0),
(146, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099904/ncz115ldiawvv9_1782204539.png', 5, 0),
(146, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782099904/ncz115ldiamvv8_1782204526.png', 6, 0),
(147, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100014/ncz117ldiavv1_1782204791.png', 0, 1),
(147, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100014/ncz117ldiavv2_1786091656.jpg', 1, 0),
(147, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100014/ncz117vv4_1786091656.jpg', 2, 0),
(147, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100014/ncz117ldiavv3_1786091656.jpg', 3, 0),
(147, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100014/ncz117ldiawvv10_1782204796.png', 4, 0),
(147, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100014/ncz117ldiamvv7_1782204797.png', 5, 0),
(147, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100014/ncz117ldiawvv9_1782204797.png', 6, 0),
(147, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100014/ncz117ldiamvv8_1782204796.png', 7, 0),
(148, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100152/ncz118ldiavv1_1782205170.png', 0, 1),
(148, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100152/ncz118ldiavv3_1786091896.jpg', 1, 0),
(148, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100152/ncz118ldiavv2_1786091896.jpg', 2, 0),
(148, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100152/ncz118vv4_1786091896.jpg', 3, 0),
(148, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100152/ncz118ldiamvv8_1782205177.png', 4, 0),
(148, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100152/ncz118ldiawvv9_1782205159.png', 5, 0),
(148, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100152/ncz118ldiamvv8_1782204947.png', 6, 0),
(148, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100152/ncz118ldiamvv7_1782205178.png', 7, 0),
(149, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100438/ncz119ldiavv1_1782205857.png', 0, 1),
(149, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100438/ncz119vv4_1786091929.jpg', 1, 0),
(149, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100438/ncz119ldiavv2_1786091929.jpg', 2, 0),
(149, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100438/ncz119ldiavv3_1786091929.jpg', 3, 0),
(149, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100438/ncz119ldiamvv9_1782205865.png', 4, 0),
(149, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100438/ncz119ldiawvv7_1782205865.png', 5, 0),
(149, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100438/ncz119ldiawvv10_1782205852.png', 6, 0),
(150, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440962/nc129vt_1742891371.png', 0, 1),
(150, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440962/nc129vt2_1744623751.jpg', 1, 0),
(150, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440962/nc129wvt10_1752915628.jpg', 2, 0),
(150, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440962/nc129wvt12_1752915628.jpg', 3, 0),
(150, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440962/nc129wvt6_1752915568.jpg', 4, 0),
(150, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440962/nc129wvt8_1752915592.jpg', 5, 0),
(150, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440962/nc129wvt3_1752917244.png', 6, 0),
(150, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440962/nc129wvt5_1752917248.png', 7, 0),
(150, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440962/nc129mvt7_1752917255.png', 8, 0),
(150, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440962/nc129mvt9_1752917255.png', 9, 0),
(151, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344673/nc130b8_1718011643.png', 0, 1),
(151, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344673/nc1301_1717477202.jpg', 1, 0),
(151, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344673/nc1303_1717477206.jpg', 2, 0),
(151, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344673/nc1302_1717477206.jpg', 3, 0),
(151, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344673/nc130b6_1718011643.png', 4, 0),
(151, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344673/nc130b9_1718011643.png', 5, 0),
(152, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440601/nc131vt_1742887925.png', 0, 1),
(152, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440601/nc131vt2_1752916195.jpg', 1, 0),
(152, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440601/nc131vt10_1752916241.jpg', 2, 0),
(152, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440601/nc131vt12_1752916808.jpg', 3, 0),
(152, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440601/nc131mvt6_1752916816.jpg', 4, 0),
(152, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440601/nc131mvt8_1752916823.jpg', 5, 0),
(152, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440601/nc131mvt7_1752916846.png', 6, 0),
(152, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440601/nc131mvt9_1752916852.png', 7, 0),
(152, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440601/nc131wvt3_1752916875.png', 8, 0),
(152, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440601/nc131wvt5_1752916875.png', 9, 0),
(153, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440909/nc206vt_1742895357.png', 0, 1),
(153, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440909/nc206vt4_1760606209.jpg', 1, 0),
(153, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440909/nc206vt2_1760606180.jpg', 2, 0),
(153, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440909/nc206wvt12_1760606190.jpg', 3, 0),
(153, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440909/nc206wvt10_1760606190.jpg', 4, 0),
(153, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440909/nc206mvt6_1760606190.jpg', 5, 0),
(153, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440909/nc206mvt8_1760606209.jpg', 6, 0),
(153, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440909/nc206mvt7_1760605628.png', 7, 0),
(153, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440909/nc206mvt9_1760605621.png', 8, 0),
(154, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440549/nc215vt_1742887376.png', 0, 1),
(154, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440549/nc215vt2_1744624469.jpg', 1, 0),
(154, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440549/nc215wvt10_1752917814.jpg', 2, 0),
(154, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440549/nc215wvt12_1752917814.jpg', 3, 0),
(154, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440549/nc215mvt6_1752917838.jpg', 4, 0),
(154, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440549/nc215mvt8_1752917846.jpg', 5, 0),
(154, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440549/nc215wvt3_1752917858.png', 6, 0),
(154, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440549/nc215wvt5_1752917858.png', 7, 0),
(154, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440549/nc215mvt7_1752917866.png', 8, 0),
(154, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440549/nc215mvt9_1752917866.png', 9, 0),
(155, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440852/nc225vt_1742887765.png', 0, 1),
(155, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440852/nc225vt2_1744624593.jpg', 1, 0),
(155, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440852/nc225wvt10_1752918025.jpg', 2, 0),
(155, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440852/nc225wvt12_1752918025.jpg', 3, 0),
(155, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440852/nc225mvt8_1752918042.jpg', 4, 0),
(155, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440852/nc225mvt6_1752918042.jpg', 5, 0),
(155, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440852/nc225wvt3_1752918054.png', 6, 0),
(155, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440852/nc225wvt5_1752918054.png', 7, 0),
(155, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440852/nc225mvt7_1752918062.png', 8, 0),
(155, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440852/nc225mvt9_1752918062.png', 9, 0),
(156, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742441076/nc274vt_1742894325.png', 0, 1),
(156, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742441076/nc274vt2_1744624658.jpg', 1, 0),
(156, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441076/nc274wvt10_1752918262.jpg', 2, 0),
(156, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441076/nc274wvt12_1752918262.jpg', 3, 0),
(156, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441076/nc274mvt6_1752918277.jpg', 4, 0),
(156, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441076/nc274mvt8_1752918277.jpg', 5, 0),
(156, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441076/nc274wvt3_1752918287.png', 6, 0),
(156, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441076/nc274wvt5_1752918287.png', 7, 0),
(156, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441076/nc274mvt7_1752918297.png', 8, 0),
(156, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742441076/nc274mvt9_1752918297.png', 9, 0),
(157, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440776/nc411vt1_1745807849.png', 0, 1),
(157, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440776/nc411wvt12_1760606075.jpg', 1, 0),
(157, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440776/nc411wvt10_1760606074.jpg', 2, 0),
(157, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440776/nc411mvt6_1760606075.jpg', 3, 0),
(157, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440776/nc411wvt8_1760606075.jpg', 4, 0),
(157, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440776/nc411mvt7_1752918564.png', 5, 0),
(157, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440776/nc411mvt9_1752918564.png', 6, 0),
(157, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440776/nc411wvt5_1752918556.png', 7, 0),
(157, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440776/nc411wvt3_1752918556.png', 8, 0),
(158, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440425/nc558vt1_1744617227.png', 0, 1),
(158, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742440425/nc558vt2_1744617227.jpg', 1, 0),
(158, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440425/nc558wvt10_1752918632.jpg', 2, 0),
(158, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440425/nc558wvt12_1752918632.jpg', 3, 0),
(158, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440425/nc558mvt6_1752918646.jpg', 4, 0),
(158, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440425/nc558mvt8_1752918646.jpg', 5, 0),
(158, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440425/nc558vt7_1752918784.png', 6, 0),
(158, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440425/nc558vt9_1752918784.png', 7, 0),
(158, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440425/nc558vt3_1752918791.png', 8, 0),
(158, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742440425/nc558vt5_1752918791.png', 9, 0),
(159, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344640/nc7846_1716517461.png', 0, 1),
(159, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344640/nc7845_1716517461.jpg', 1, 0),
(159, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344640/nc7842_1716517461.jpg', 2, 0),
(159, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344640/nc7841_1716517461.jpg', 3, 0),
(159, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344640/nc7844_1716517461.jpg', 4, 0),
(159, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344640/nc7843_1716517461.jpg', 5, 0),
(160, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344643/nc7856_1729742480.png', 0, 1),
(160, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344643/nc7855_1729742485.jpg', 1, 0),
(160, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344643/nc7852_1729742485.jpg', 2, 0),
(160, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344643/nc7851_1729742485.jpg', 3, 0),
(160, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344643/nc7853_1729742485.jpg', 4, 0),
(160, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344643/nc7854_1729742485.jpg', 5, 0),
(161, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344646/nc7876_1716518029.png', 0, 1),
(161, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344646/nc7875_1716518029.jpg', 1, 0),
(161, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344646/nc7874_1716518029.jpg', 2, 0),
(161, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344646/nc7873_1716518029.jpg', 3, 0),
(161, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344646/nc7872_1716518029.jpg', 4, 0),
(161, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344646/nc7871_1716518029.jpg', 5, 0),
(162, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718158125/nc7887-2_1718246443.png', 0, 1),
(162, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718158125/nc7884_1718246455.jpg', 1, 0),
(162, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718158125/nc7881_1718246455.jpg', 2, 0),
(162, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718158125/nc7883_1718246455.jpg', 3, 0),
(162, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718158125/nc7882_1718246455.jpg', 4, 0),
(162, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718158125/nc7886_1718246455.jpg', 5, 0),
(162, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1718158125/nc7885_1718246455.jpg', 6, 0),
(163, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1726114014/nc7997_1726124065.png', 0, 1),
(163, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1726114014/nc7991_1726124049.jpg', 1, 0),
(163, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1726114014/nc7994_1726124049.jpg', 2, 0),
(163, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1726114014/nc7993_1726124049.jpg', 3, 0),
(163, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1726114014/nc7992_1726124049.jpg', 4, 0),
(163, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1726114014/nc799w7_1726124065.png', 5, 0),
(163, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1726114014/nc799m7_1726124065.png', 6, 0),
(164, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733465575/nc8558_1733469662.png', 0, 1),
(164, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733465575/nc8551_1733469662.jpg', 1, 0),
(164, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733465575/nc8552_1733469662.jpg', 2, 0),
(164, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733465575/nc8557_1733469661.png', 3, 0),
(164, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733465575/nc8556_1733469661.png', 4, 0),
(164, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733465575/nc8559_1733469662.png', 5, 0),
(164, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1733465575/nc85510_1733469661.png', 6, 0),
(165, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344556/nc8721_1716436044.png', 0, 1),
(165, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344556/nc872-b_1716436057.jpg', 1, 0),
(165, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344556/nc873-b_1716436058.jpg', 2, 0),
(165, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344556/nc872m-b_1716436058.jpg', 3, 0),
(165, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344556/nc872w-b_1716436058.jpg', 4, 0),
(165, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344556/nc873w-b_1716436058.jpg', 5, 0),
(166, 'https://cdn.huythanhjewelry.vn/storage/photos/uploads/ncz114vv1_1786086607.png', 0, 1),
(166, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100657/ncz114vv2_1786086640.jpg', 1, 0),
(166, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100657/ncz114vv4_1786086640.jpg', 2, 0),
(166, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100657/ncz114vv3_1786086640.jpg', 3, 0),
(166, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100657/ncz114wvv10_1786086626.png', 4, 0),
(166, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100657/ncz114mvv7_1786086640.png', 5, 0),
(166, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100657/ncz114mvv7_1786086627.png', 6, 0),
(166, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100657/ncz114wvv9_1786086627.png', 7, 0),
(166, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100657/ncz114mvv8_1786086626.png', 8, 0),
(167, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100732/ncz116vv1_1786086715.png', 0, 1),
(167, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100732/ncz116vv2_1786086722.jpg', 1, 0),
(167, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100732/ncz116vv3_1786086722.jpg', 2, 0),
(167, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100732/ncz116vv4_1786086722.jpg', 3, 0),
(167, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100732/ncz116mvv7_1786086734.png', 4, 0),
(167, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100732/ncz116mvv8_1786086734.png', 5, 0),
(167, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100732/ncz116wvv9_1786086734.png', 6, 0),
(167, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100732/ncz116wvv10_1786086734.png', 7, 0),
(168, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786090457/ncz120vv1_1786091208.png', 0, 1),
(168, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786090457/ncz120ldiavv2_1786091201.jpg', 1, 0),
(168, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786090457/ncz120ldiavv4_1786091201.jpg', 2, 0),
(168, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786090457/ncz120ldiavv3_1786091201.jpg', 3, 0),
(168, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786090457/ncz120mvv8_1786091201.png', 4, 0),
(168, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786090457/ncz120wvv9_1786091201.png', 5, 0),
(168, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786090457/ncz120wvv10_1786091201.png', 6, 0),
(168, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786090457/ncz120mvv7_1786091201.png', 7, 0),
(169, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100890/ncz121vv1_1786090077.png', 0, 1),
(169, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100890/ncz121vv2_1786090077.jpg', 1, 0),
(169, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100890/ncz121vv3_1786090077.jpg', 2, 0),
(169, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100890/ncz121vv4_1786090078.jpg', 3, 0),
(169, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100890/ncz121mvv7_1786090090.png', 4, 0),
(169, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100890/ncz121mvv8_1786090090.png', 5, 0),
(170, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100957/ncz122vv1_1785466904.png', 0, 1),
(170, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100957/ncz122vv2_1786077780.jpg', 1, 0),
(170, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100957/ncz122vv3_1786077793.jpg', 2, 0),
(170, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100957/ncz122vv4_1786077799.jpg', 3, 0),
(170, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100957/ncz122ldiawvv10_1785466895.png', 4, 0),
(170, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1782100957/ncz122ldiawvv9_1785466904.png', 5, 0),
(171, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344766/nc8608_1717152782.png', 0, 1),
(171, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344766/nc8603_1717152782.jpg', 1, 0),
(171, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344766/nc8604_1717152782.jpg', 2, 0),
(171, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344766/nc8605_1717152782.jpg', 3, 0),
(171, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344766/nc8601_1717152782.jpg', 4, 0),
(171, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1716344766/nc8602_1717152782.jpg', 5, 0),
(172, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1750299516/nc433bac9251_1750418704.jpg', 0, 1),
(172, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1750299516/nc433bac9252_1752293088.jpg', 1, 0),
(172, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1750299516/nc433bac9253_1752293100.jpg', 2, 0),
(172, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1750299516/nc433mbac9254_1752293162.jpg', 3, 0),
(172, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1750299516/nc433mbac9255_1752293162.jpg', 4, 0),
(172, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1750299516/nc433wbac9256_1752293162.jpg', 5, 0),
(172, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1750299516/nc433wbac9257_1752293162.jpg', 6, 0),
(173, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754270/nlf4247_1715827300.png', 0, 1),
(173, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754270/nlf4242_1715827288.jpg', 1, 0),
(173, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754270/nlf4241_1715827287.jpg', 2, 0),
(173, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754270/nlf4243_1715827300.jpg', 3, 0),
(173, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754270/nlf4244_1715827288.jpg', 4, 0),
(173, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754270/nlf4246_1715827300.png', 5, 0),
(174, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754273/nlf4317-1_1728963481.png', 0, 1),
(174, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754273/nlf4312_1728963487.jpg', 1, 0),
(174, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754273/nlf4314_1728963487.jpg', 2, 0),
(174, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754273/nlf4313_1728963487.jpg', 3, 0),
(174, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754273/nlf4311_1728963487.jpg', 4, 0),
(174, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754273/nlf4316-1_1728963481.png', 5, 0),
(175, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754274/nlf4337-1_1728895445.png', 0, 1),
(175, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754274/nlf4333_1728895459.jpg', 1, 0),
(175, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754274/nlf4334_1728895459.jpg', 2, 0),
(175, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754274/nlf4331_1728895459.jpg', 3, 0),
(175, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754274/nlf4335_1728895459.jpg', 4, 0),
(175, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754274/nlf4332_1728895459.jpg', 5, 0),
(175, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754274/nlf4336-1_1728895451.png', 6, 0),
(175, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754274/nlf4338-1_1728895445.png', 7, 0),
(176, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754275/nlf4347_1715830406.png', 0, 1),
(176, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754275/nlf4343_1715830337.jpg', 1, 0),
(176, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754275/nlf4342_1715830385.jpg', 2, 0),
(176, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754275/nlf4344_1715830397.jpg', 3, 0),
(176, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754275/nlf4341_1715830376.jpg', 4, 0),
(176, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754275/nlf4346_1715830406.png', 5, 0),
(177, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754283/nlf449-vvv-1_1728964508.png', 0, 1),
(177, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754283/nlf4491_1728964508.jpg', 1, 0),
(177, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754283/nlf449-vv-2_1728964508.jpg', 2, 0),
(177, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754283/nlf4493_1728964508.jpg', 3, 0),
(177, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754283/nlf4492_1728964508.jpg', 4, 0),
(177, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754283/nlf449-vv-3_1728964525.png', 5, 0),
(177, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754283/nlf449-vv-5_1728964525.png', 6, 0),
(178, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754284/nlf4507_1715834558.png', 0, 1),
(178, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754284/nlf4502_1715834558.jpg', 1, 0),
(178, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754284/nlf4503_1715834558.jpg', 2, 0),
(178, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754284/nlf4504_1715834558.jpg', 3, 0),
(178, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754284/nlf4501_1715834557.jpg', 4, 0),
(178, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754284/nlf4506_1715834558.png', 5, 0),
(178, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754284/nlf4508_1715834558.png', 6, 0),
(179, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754287/nlf45362_1728973786.png', 0, 1),
(179, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754287/nlf4532_1728973795.jpg', 1, 0),
(179, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754287/nlf4533_1728973795.jpg', 2, 0),
(179, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754287/nlf4531_1728973794.jpg', 3, 0),
(179, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754287/nlf45312_1728973781.png', 4, 0),
(179, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754287/nlf45352_1728973781.png', 5, 0),
(180, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754288/nlf45462_1728967814.png', 0, 1),
(180, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754288/nlf4542_1728967822.jpg', 1, 0),
(180, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754288/nlf4543_1728967822.jpg', 2, 0),
(180, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754288/nlf4541_1728967822.jpg', 3, 0),
(180, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754288/nlf45412_1728967814.png', 4, 0),
(180, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754288/nlf45472_1728967814.png', 5, 0),
(180, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754288/nlf45452_1728967814.png', 6, 0),
(181, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754289/nlf45562_1728965135.png', 0, 1),
(181, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754289/nlf4552_1728965135.jpg', 1, 0),
(181, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754289/nlf4553_1728965135.jpg', 2, 0),
(181, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754289/nlf4551_1728965135.jpg', 3, 0),
(181, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754289/nlf45512_1728965135.png', 4, 0),
(181, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754289/nlf45552_1728965135.png', 5, 0),
(182, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754290/nlf45662_1728975421.png', 0, 1),
(182, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754290/nlf4563_1728975427.jpg', 1, 0),
(182, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754290/nlf4564_1728975427.jpg', 2, 0),
(182, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754290/nlf4562_1728975427.jpg', 3, 0),
(182, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754290/nlf45612_1728975421.png', 4, 0),
(182, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754290/nlf45652_1728975414.png', 5, 0),
(183, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754291/nlf45761_1728968242.png', 0, 1),
(183, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754291/nlf4573_1728968191.jpg', 1, 0),
(183, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754291/nlf4572_1728968191.jpg', 2, 0),
(183, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754291/nlf4571_1728968191.jpg', 3, 0),
(183, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754291/nlf45711_1728968242.png', 4, 0),
(183, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754291/nlf45751_1728968242.png', 5, 0),
(183, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754291/nlf45771_1728968242.png', 6, 0),
(184, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754293/nlf46062_1728974887.png', 0, 1),
(184, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754293/nlf4602_1728974899.jpg', 1, 0),
(184, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754293/nlf4603_1728974899.jpg', 2, 0),
(184, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754293/nlf4601_1728974899.jpg', 3, 0),
(184, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754293/nlf46012_1728974894.png', 4, 0),
(184, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754293/nlf46072_1728974885.png', 5, 0),
(184, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754293/nlf46052_1728974880.png', 6, 0),
(185, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754296/nlf46561_1728975138.png', 0, 1),
(185, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754296/nlf4652_1728975135.jpg', 1, 0),
(185, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754296/nlf4653_1728975135.jpg', 2, 0),
(185, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754296/nlf4651_1728975135.jpg', 3, 0),
(185, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754296/nlf46513_1728975135.png', 4, 0),
(185, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754296/nlf46553_1728975135.png', 5, 0),
(186, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754297/nlf4677_1728965465.png', 0, 1),
(186, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754297/nlf4672_1728965465.jpg', 1, 0),
(186, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754297/nlf4673_1728965465.jpg', 2, 0),
(186, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754297/nlf4671_1728965465.jpg', 3, 0),
(186, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754297/nlf4674_1728965465.jpg', 4, 0),
(186, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754297/nlf4676_1728965465.png', 5, 0),
(186, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754297/nlf4678_1728965465.png', 6, 0),
(187, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754298/nlf4687_1728965650.png', 0, 1),
(187, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754298/nlf4681_1728965650.jpg', 1, 0),
(187, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754298/nlf4682_1728965650.jpg', 2, 0),
(187, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754298/nlf4684_1728965650.jpg', 3, 0),
(187, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754298/nlf4683_1728965650.jpg', 4, 0),
(187, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754298/nlf4686_1728965650.png', 5, 0),
(187, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754298/nlf4688_1728965650.png', 6, 0),
(188, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754301/nlf4817_1728966023.png', 0, 1),
(188, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754301/nlf481-b_1728966028.jpg', 1, 0),
(188, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754301/nlf481483-b_1728966028.jpg', 2, 0),
(188, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754301/nlf481492-b_1728966028.jpg', 3, 0),
(188, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754301/nlf4816_1728966023.png', 4, 0),
(188, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754301/nlf4818_1728966023.png', 5, 0),
(189, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754303/nlf4847_1728966350.png', 0, 1),
(189, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754303/nlf484-b_1728966350.jpg', 1, 0),
(189, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754303/nlf478484493503-b_1728966350.jpg', 2, 0),
(189, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754303/nlf477479484-b_1728966350.jpg', 3, 0),
(189, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754303/nlf4846_1728966350.png', 4, 0),
(189, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754303/nlf4848_1728966350.png', 5, 0),
(190, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754306/nlf4887_1715851693.png', 0, 1),
(190, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754306/nlf488-b_1715851705.jpg', 1, 0),
(190, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754306/nlf4984882-b_1715851705.jpg', 2, 0),
(190, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754306/nlf4984881-b_1715851705.jpg', 3, 0),
(190, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754306/nlf4886_1715851665.png', 4, 0),
(190, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754306/nlf4888_1715851687.png', 5, 0),
(191, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754307/nlf4897_1715851951.png', 0, 1),
(191, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754307/nlf489-b_1715851977.jpg', 1, 0),
(191, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754307/nlf486489504-b_1715851977.jpg', 2, 0),
(191, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754307/nlf489497-b_1715851977.jpg', 3, 0),
(191, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754307/nlf4896_1715851938.png', 4, 0),
(191, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754307/nlf4898_1715851965.png', 5, 0),
(192, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754314/nlf4987_1715936374.png', 0, 1),
(192, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754314/nlf498-b_1715936391.jpg', 1, 0),
(192, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754314/nlf4984882-b_1715936391.jpg', 2, 0),
(192, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754314/nlf4984881-b_1715936391.jpg', 3, 0),
(192, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754314/nlf4986_1715936438.png', 4, 0),
(192, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754314/nlf4988_1715936353.png', 5, 0),
(193, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1729496717/nptb35062_1729499215.png', 0, 1),
(193, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1729496717/nptb3501_1729499223.jpg', 1, 0),
(193, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1729496717/nptb3502_1729499223.jpg', 2, 0),
(193, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1729496717/nptb3503_1729499223.jpg', 3, 0),
(193, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1729496717/nptb3504_1729499223.jpg', 4, 0),
(193, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1729496717/nptb35012_1729499215.png', 5, 0),
(193, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1729496717/nptb35052_1729499210.png', 6, 0),
(194, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786413221/nz081vt1_1787539738.png', 0, 1),
(194, 'https://cdn.huythanhjewelry.vn/storage/photos/uploads/nz081vt2_1790235026.jpg', 1, 0),
(194, 'https://cdn.huythanhjewelry.vn/storage/photos/uploads/nz081vt3_1790235028.jpg', 2, 0),
(194, 'https://cdn.huythanhjewelry.vn/storage/photos/uploads/nz081vt4_1790235066.jpg', 3, 0),
(194, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786413221/nz081vt5_1790235070.png', 4, 0),
(194, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1786413221/nz081vt6_1790235072.png', 5, 0),
(195, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754457/nbtcc904_1715653737.png', 0, 1),
(195, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754457/nbtcc902_1715653737.jpg', 1, 0),
(195, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754457/nbtcc901_1715653737.jpg', 2, 0),
(195, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754457/nbtcc906_1715653737.png', 3, 0),
(195, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754457/nbtcc907_1715653737.png', 4, 0),
(195, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754457/nbtcc905_1715653737.png', 5, 0),
(196, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754460/nbtcc914_1715654123.png', 0, 1),
(196, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754460/nbtcc912_1715654122.jpg', 1, 0),
(196, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754460/nbtcc911_1715654123.jpg', 2, 0),
(196, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754460/nbtcc916_1715654123.png', 3, 0),
(196, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754460/nbtcc917_1715654123.png', 4, 0),
(196, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754460/nbtcc915_1715654123.png', 5, 0),
(197, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754465/nbtcc984-1_1715654885.png', 0, 1),
(197, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754465/nbtcc98-vh-2_1728544082.jpg', 1, 0),
(197, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754465/nbtcc98-vh-4_1728544082.jpg', 2, 0),
(197, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754465/nbtcc984-3_1715654885.png', 3, 0),
(197, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754465/nbtcc984-4_1715654885.png', 4, 0),
(197, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754465/nbtcc984-2_1715654885.png', 5, 0),
(198, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201445/nptb423vv1_1768206240.png', 0, 1),
(198, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201445/nptb423vv2_1768206221.jpg', 1, 0),
(198, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201445/nptb423vv3_1768206221.jpg', 2, 0),
(198, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201445/nptb423vv5_1768206169.png', 3, 0),
(198, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201445/nptb423vv7_1768206169.png', 4, 0),
(198, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201445/nptb423vv6_1768206169.png', 5, 0),
(199, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201382/nz042vv1_1768205735.png', 0, 1),
(199, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201382/nz042vv2_1768205735.jpg', 1, 0),
(199, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201382/nz042vv3_1768205756.jpg', 2, 0),
(199, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201382/nz042vv5_1768205747.png', 3, 0),
(199, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201382/nz042vv6_1768205766.png', 4, 0),
(199, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201382/nz042vv5_1768205767.png', 5, 0),
(200, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1734341178/nlf457611728968242_1785639258.webp', 0, 1),
(200, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1734341178/nlf45721728968191_1785639283.jpg', 1, 0),
(200, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1734341178/nlf45711728968191_1785639258.jpg', 2, 0),
(200, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1734341178/nlf457111728968242_1785639289.png', 3, 0),
(200, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1734341178/nlf457511728968242_1785639298.png', 4, 0),
(200, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1734341178/nlf457711728968242_1785639327.png', 5, 0),
(201, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589574/bt161b1_1790652457.png', 0, 1),
(201, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589574/bt161b2_1790652456.jpg', 1, 0),
(201, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589574/bt161b2_1790652457.png', 2, 0),
(201, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589574/bt161b3_1790652457.jpg', 3, 0),
(201, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589574/bt161b3_1790652457.png', 4, 0),
(201, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589574/bt161b4_1790652457.png', 5, 0),
(202, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754142/bt2841_1729912574.png', 0, 1),
(202, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754142/bt2843_1715928570.jpg', 1, 0),
(202, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754142/bt2842_1715928570.jpg', 2, 0),
(202, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754142/bt2844_1715928570.jpg', 3, 0),
(202, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754142/bt2844_1715928570.png', 4, 0),
(202, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754142/bt2843_1715928570.png', 5, 0),
(202, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754142/bt2842_1715928593.png', 6, 0),
(203, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754113/bt3361_1715921531.png', 0, 1),
(203, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754113/bt3362_1715921531.jpg', 1, 0),
(203, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754113/bt3364_1715921531.jpg', 2, 0),
(203, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754113/bt3363_1715921531.jpg', 3, 0),
(203, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754113/bt3363_1715921531.png', 4, 0),
(203, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754113/bt3362_1715921531.png', 5, 0),
(203, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754113/bt3364_1715921531.png', 6, 0),
(204, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754094/bt4086-1_1715918675.png', 0, 1),
(204, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754094/bt4082_1715918675.jpg', 1, 0),
(204, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754094/bt4083_1715918675.jpg', 2, 0),
(204, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754094/bt4084_1715918675.jpg', 3, 0),
(204, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754094/bt4081_1715918675.jpg', 4, 0),
(204, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754094/bt4087-3_1715918675.jpg', 5, 0),
(205, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754153/bt4156_1715929658.png', 0, 1),
(205, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754153/bt4153_1715929657.jpg', 1, 0),
(205, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754153/bt4152_1715929658.jpg', 2, 0),
(205, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754153/bt4151_1715929658.jpg', 3, 0),
(205, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754153/bt4154_1715929657.jpg', 4, 0),
(205, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754153/bt4158_1715929658.jpg', 5, 0),
(206, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754131/bt4236_1715927726.png', 0, 1),
(206, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754131/bt4231_1715927726.jpg', 1, 0),
(206, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754131/bt4232_1715927726.jpg', 2, 0),
(206, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754131/bt4233_1715927726.jpg', 3, 0),
(206, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754131/bt4234_1715927736.jpg', 4, 0),
(206, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754131/bt4238_1715927740.jpg', 5, 0),
(207, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754132/bt4246_1715927814.png', 0, 1),
(207, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754132/bt4241_1715927814.jpg', 1, 0),
(207, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754132/bt4242_1715927814.jpg', 2, 0),
(207, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754132/bt4243_1715927814.jpg', 3, 0),
(207, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754132/bt4244_1715927814.jpg', 4, 0),
(207, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754132/bt4248_1715927814.jpg', 5, 0),
(208, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754133/bt4266_1715927875.png', 0, 1),
(208, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754133/bt4261_1715927875.jpg', 1, 0),
(208, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754133/bt4262_1715927875.jpg', 2, 0),
(208, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754133/bt4263_1715927875.jpg', 3, 0),
(208, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754133/bt4264_1715927875.jpg', 4, 0),
(208, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754133/bt4268_1715927875.jpg', 5, 0),
(209, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754119/bt4326_1715926764.png', 0, 1),
(209, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754119/bt4321_1715926764.jpg', 1, 0),
(209, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754119/bt4323_1715926764.jpg', 2, 0),
(209, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754119/bt4322_1715926764.jpg', 3, 0),
(209, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754119/bt4324_1715926764.jpg', 4, 0),
(209, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754119/bt4327_1715926764.jpg', 5, 0),
(210, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754144/bt4336vt_1729148322.png', 0, 1),
(210, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754144/bt4331vt_1729148335.jpg', 1, 0),
(210, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754144/bt4332vt_1729148335.jpg', 2, 0),
(210, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754144/bt4333vt_1729148335.jpg', 3, 0),
(210, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754144/bt4334vt_1729148335.jpg', 4, 0),
(210, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754144/bt4337vt_1729148341.jpg', 5, 0),
(211, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733493/btam421_1728697021.png', 0, 1),
(211, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733493/btam42-vv-2_1728697026.jpg', 1, 0),
(211, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733493/btam42-vv-4_1728697026.jpg', 2, 0),
(211, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733493/btam423_1728697021.png', 3, 0),
(211, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733493/btam422_1728697021.png', 4, 0),
(211, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733493/btam424_1728697021.png', 5, 0),
(212, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115563/btbz044vt1_1761122500.png', 0, 1),
(212, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115563/btbz044vt2_1761122494.jpg', 1, 0),
(212, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115563/btbz044vt3_1761122494.jpg', 2, 0),
(212, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115563/btbz044vt4_1761122495.jpg', 3, 0);
INSERT INTO dbo.ProductImages (ProductID, ImageUrl, SortOrder, IsThumbnail) VALUES
(212, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115563/btbz044vt5_1761122500.png', 4, 0),
(212, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115563/btbz044vt5_1761122494.jpg', 5, 0),
(213, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754575/btptb2991_1716259249.png', 0, 1),
(213, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754575/btptb2995_1716259249.jpg', 1, 0),
(213, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754575/btptb2996_1716259285.jpg', 2, 0),
(213, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754575/btptb2992_1716259249.png', 3, 0),
(213, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754575/btptb2993_1716259249.png', 4, 0),
(213, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754575/btptb2994_1716259249.png', 5, 0),
(214, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754116/btptb324-vv-1_1717657801.png', 0, 1),
(214, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754116/btptb3242_1715921963.jpg', 1, 0),
(214, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754116/btptb3243_1715921963.jpg', 2, 0),
(214, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754116/btptb3241_1715921963.jpg', 3, 0),
(214, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754116/btptb3245_1715921963.jpg', 4, 0),
(214, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754116/btptb3244_1715921963.jpg', 5, 0),
(215, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754540/btptb3536_1716258589.png', 0, 1),
(215, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754540/btptb3533_1716258565.jpg', 1, 0),
(215, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754540/btptb3532_1716258589.jpg', 2, 0),
(215, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754540/btptb3531_1716258589.jpg', 3, 0),
(215, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754540/btptb3534_1716258565.jpg', 4, 0),
(215, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754540/btptb3538_1716258602.jpg', 5, 0),
(216, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759456/btptb418bac1_1776824584.png', 0, 1),
(216, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759456/btptb418bac6_1776824584.png', 1, 0),
(216, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759456/btptb418vh1_1776824584.png', 2, 0),
(216, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759456/btptb418vh2_1776824583.jpg', 3, 0),
(216, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759456/btptb418vh3_1776824583.jpg', 4, 0),
(216, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759456/btptb418vh4_1776824584.jpg', 5, 0),
(216, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759456/btptb418vh5_1776824583.jpg', 6, 0),
(217, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754099/bt4116-1_1715919377.png', 0, 1),
(217, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754099/bt4112_1715919377.jpg', 1, 0),
(217, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754099/bt4111_1715919377.jpg', 2, 0),
(217, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754099/bt4113_1715919377.jpg', 3, 0),
(217, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754099/bt4114_1715919377.jpg', 4, 0),
(217, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754099/bt4117-1_1715919377.jpg', 5, 0),
(218, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754100/bt4126-1_1715919663.png', 0, 1),
(218, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754100/bt4122_1715919663.jpg', 1, 0),
(218, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754100/bt4123_1715919663.jpg', 2, 0),
(218, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754100/bt4124_1715919663.jpg', 3, 0),
(218, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754100/bt4121_1715919663.jpg', 4, 0),
(218, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754100/bt4127-1_1715919663.jpg', 5, 0),
(219, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754101/bt4136-1_1715919792.png', 0, 1),
(219, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754101/bt4132_1715919792.jpg', 1, 0),
(219, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754101/bt4133_1715919792.jpg', 2, 0),
(219, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754101/bt4131_1715919792.jpg', 3, 0),
(219, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754101/bt4134_1715919792.jpg', 4, 0),
(219, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754101/bt4137-1_1715919805.jpg', 5, 0),
(220, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754102/bt4146-1_1715919945.png', 0, 1),
(220, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754102/bt4142_1715919945.jpg', 1, 0),
(220, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754102/bt4143_1715919945.jpg', 2, 0),
(220, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754102/bt4144_1715919945.jpg', 3, 0),
(220, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754102/bt4141_1715919945.jpg', 4, 0),
(220, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754102/bt4147-1_1715919945.jpg', 5, 0),
(221, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733302/btam441_1728697393.png', 0, 1),
(221, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733302/btam44-vv-4_1728697396.jpg', 1, 0),
(221, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733302/btam44-vv-2_1728697396.jpg', 2, 0),
(221, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733302/btam443_1728697393.png', 3, 0),
(221, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733302/btam442_1728697393.png', 4, 0),
(221, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724733302/btam444_1728697393.png', 5, 0),
(222, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714163/btbz018vv1_1766902895.png', 0, 1),
(222, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714163/btbz018vv2_1766902894.jpg', 1, 0),
(222, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714163/btbz018vv3_1766902894.jpg', 2, 0),
(222, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714163/btbz018vv4_1766902894.jpg', 3, 0),
(222, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714163/btbz018vv5_1766902894.jpg', 4, 0),
(222, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714163/btbz018vv5_1766902894.png', 5, 0),
(223, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663423/btz007vv1_1764755609.png', 0, 1),
(223, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663423/btz007vv6_1764755619.jpg', 1, 0),
(223, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663423/btz007vv4_1764755622.jpg', 2, 0),
(223, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663423/btz007vv2_1764755626.jpg', 3, 0),
(223, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663423/btz007vv8_1764755629.jpg', 4, 0),
(223, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663423/btz007vv3_1764755632.png', 5, 0),
(224, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663437/btz008vv1_1764755722.png', 0, 1),
(224, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663437/btz008vv6_1764755727.jpg', 1, 0),
(224, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663437/btz008vv4_1764755730.jpg', 2, 0),
(224, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663437/btz008vv2_1764755733.jpg', 3, 0),
(224, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663437/btz008vv8_1764755736.jpg', 4, 0),
(224, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663437/btz008vv3_1764755741.png', 5, 0),
(225, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663459/btz009vv1_1764849208.png', 0, 1),
(225, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663459/btz009vv4_1764849224.jpg', 1, 0),
(225, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663459/btz009vv6_1764849229.jpg', 2, 0),
(225, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663459/btz009vv2_1764849224.jpg', 3, 0),
(225, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663459/btz009vv8_1764849241.jpg', 4, 0),
(225, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663459/btz009vv3_1764849241.png', 5, 0),
(226, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663484/btz010vv1_1764849460.png', 0, 1),
(226, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663484/btz010vv6_1764849448.jpg', 1, 0),
(226, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663484/btz010vv4_1764849448.jpg', 2, 0),
(226, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663484/btz010vv2_1764849441.jpg', 3, 0),
(226, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663484/btz010vv8_1764849447.jpg', 4, 0),
(226, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663484/btz010vv3_1764849441.png', 5, 0),
(227, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216604/btbac01vv1_1790235317.png', 0, 1),
(227, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216604/btbac01vv2_1790235323.jpg', 1, 0),
(227, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216604/btbac01vv3_1790235326.jpg', 2, 0),
(227, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216604/btbac01vv4_1790235330.jpg', 3, 0),
(227, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216604/btbac01vv5_1790235334.jpg', 4, 0),
(227, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216604/btbac01vv6_1790235338.png', 5, 0),
(227, 'https://cdn.huythanhjewelry.vn/storage/photos/uploads/btbac01vv8_1790235347.jpg', 6, 0),
(228, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216680/btbac02vv1_1790235568.png', 0, 1),
(228, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216680/btbac02vv2_1790235580.jpg', 1, 0),
(228, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216680/btbac02vv3_1790235584.jpg', 2, 0),
(228, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216680/btbac02vv4_1790235588.jpg', 3, 0),
(228, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216680/btbac02vv5_1790235593.jpg', 4, 0),
(228, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216680/btbac02vv6_1790235596.png', 5, 0),
(228, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790216680/btbac02vv7_1790235601.jpg', 6, 0),
(229, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235236/btbac04vv1_1790235731.png', 0, 1),
(229, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235236/btbac04vv2_1790235739.jpg', 1, 0),
(229, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235236/btbac04vv3_1790235743.jpg', 2, 0),
(229, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235236/btbac04vv4_1790235779.jpg', 3, 0),
(229, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235236/btbac04vv5_1790235783.jpg', 4, 0),
(229, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235236/btbac04vv6_1790235785.png', 5, 0),
(229, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235236/btbac04vv7_1790235790.jpg', 6, 0),
(230, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235268/btbac05vv1_1790236633.jpg', 0, 1),
(230, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235268/btbac05vv5_1790236669.jpg', 1, 0),
(230, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235268/btbac05vv7_1790236669.jpg', 2, 0),
(230, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235268/btbac05vv6_1790236660.jpg', 3, 0),
(230, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235268/btbac05vv4_1790236680.jpg', 4, 0),
(230, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235268/btbac05vv3_1790236649.jpg', 5, 0),
(231, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235800/btbac08vv1_1790655048.png', 0, 1),
(231, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235800/btbac08vv2_1790655048.jpg', 1, 0),
(231, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235800/btbac08vv3_1790655048.jpg', 2, 0),
(231, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235800/btbac08vv4_1790655054.jpg', 3, 0),
(231, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235800/btbac08vv5_1790655054.jpg', 4, 0),
(231, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235800/btbac08vv6_1790655054.png', 5, 0),
(231, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235800/btbac08vv7_1790655059.jpg', 6, 0),
(231, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235800/btbac08vv8_1790655062.jpg', 7, 0),
(232, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235825/btbac09vv1_1790655116.png', 0, 1),
(232, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235825/btbac09vv3_1790655111.jpg', 1, 0),
(232, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235825/btbac09vv2_1790655111.jpg', 2, 0),
(232, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235825/btbac09vv4_1790655124.jpg', 3, 0),
(232, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235825/btbac09vv5_1790655124.jpg', 4, 0),
(232, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235825/btbac09vv6_1790655124.png', 5, 0),
(232, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235825/btbac09vv7_1790655131.jpg', 6, 0),
(232, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235825/btbac09vv8_1790655135.jpg', 7, 0),
(232, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235825/btbac09vv9_1790655135.jpg', 8, 0),
(232, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235825/btbac09vv10_1790655135.jpg', 9, 0),
(233, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235905/btbac11vv1_1790655177.png', 0, 1),
(233, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235905/btbac11vv2_1790655184.jpg', 1, 0),
(233, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235905/btbac11vv3_1790655184.jpg', 2, 0),
(233, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235905/btbac11vv4_1790655184.jpg', 3, 0),
(233, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235905/btbac11vv5_1790655184.jpg', 4, 0),
(233, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235905/btbac11vv6_1790655177.png', 5, 0),
(233, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235905/btbac11vv7_1790655193.jpg', 6, 0),
(234, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235918/btbac12vv1_1790655227.png', 0, 1),
(234, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235918/btbac12vv2_1790655227.jpg', 1, 0),
(234, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235918/btbac12vv3_1790655227.jpg', 2, 0),
(234, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235918/btbac12vv4_1790655233.jpg', 3, 0),
(234, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235918/btbac12vv5_1790655234.jpg', 4, 0),
(234, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235918/btbac12vv6_1790655239.png', 5, 0),
(234, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235918/btbac12vv7_1790655243.jpg', 6, 0),
(235, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235948/btbac13vv1_1790655278.png', 0, 1),
(235, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235948/btbac13vv2_1790655278.jpg', 1, 0),
(235, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235948/btbac13vv3_1790655278.jpg', 2, 0),
(235, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235948/btbac13vv4_1790655278.jpg', 3, 0),
(235, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235948/btbac13vv5_1790655284.jpg', 4, 0),
(235, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235948/btbac13vv6_1790655284.png', 5, 0),
(235, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235948/btbac13vv7_1790655284.jpg', 6, 0),
(236, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235968528/btbac14vv1_1790655429.png', 0, 1),
(236, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235968528/btbac14vv2_1790655429.jpg', 1, 0),
(236, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235968528/btbac14vv3_1790655429.jpg', 2, 0),
(236, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235968528/btbac14vv4_1790655429.jpg', 3, 0),
(236, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235968528/btbac14vv5_1790655434.jpg', 4, 0),
(236, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235968528/btbac14vv6_1790655434.png', 5, 0),
(236, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235968528/btbac14vv7_1790655438.jpg', 6, 0),
(237, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235988/btbbac01vv1_1790654625.png', 0, 1),
(237, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235988/btbbac01vv2_1790654619.jpg', 1, 0),
(237, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235988/btbbac01vv3_1790654639.jpg', 2, 0),
(237, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235988/btbbac01vv4_1790654639.jpg', 3, 0),
(237, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235988/btbbac01vv6_1790654619.png', 4, 0),
(237, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235988/btbbac01vv5_1790654639.jpg', 5, 0),
(237, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235988/btbbac01vv7_1790654656.jpg', 6, 0),
(237, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790235988/btbbac01vv8_1790654659.jpg', 7, 0),
(238, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236009/btbbac02vv1_1790654707.png', 0, 1),
(238, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236009/btbbac02vv2_1790654707.jpg', 1, 0),
(238, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236009/btbbac02vv3_1790654707.jpg', 2, 0),
(238, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236009/btbbac02vv4_1790654718.jpg', 3, 0),
(238, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236009/btbbac02vv5_1790654718.jpg', 4, 0),
(238, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236009/btbbac02vv6_1790654713.png', 5, 0),
(238, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236009/btbbac02vv7_1790654729.jpg', 6, 0),
(238, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236009/btbbac02vv8_1790654733.jpg', 7, 0),
(238, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236009/btbbac02vv9_1790654733.jpg', 8, 0),
(239, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236025/btbbac03vv1_1790654775.png', 0, 1),
(239, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236025/btbbac03vv2_1790654775.jpg', 1, 0),
(239, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236025/btbbac03vv3_1790654775.jpg', 2, 0),
(239, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236025/btbbac03vv4_1790654779.jpg', 3, 0),
(239, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236025/btbbac03vv5_1790654779.jpg', 4, 0),
(239, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236025/btbbac03vv6_1790654779.png', 5, 0),
(239, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236025/btbbac03vv7_1790654783.jpg', 6, 0),
(240, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236042/btbbac04vv1_1790654816.png', 0, 1),
(240, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236042/btbbac04vv2_1790654817.jpg', 1, 0),
(240, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236042/btbbac04vv3_1790654822.jpg', 2, 0),
(240, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236042/btbbac04vv4_1790654822.jpg', 3, 0),
(240, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236042/btbbac04vv5_1790654829.jpg', 4, 0),
(240, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236042/btbbac04vv6_1790654829.png', 5, 0),
(240, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236042/btbbac04vv7_1790654832.jpg', 6, 0),
(240, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236042/btbbac04vv8_1790654835.jpg', 7, 0),
(241, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236071/btbbac05vv1_1790654870.png', 0, 1),
(241, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236071/btbbac05vv2_1790654877.jpg', 1, 0),
(241, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236071/btbbac05vv3_1790654877.jpg', 2, 0),
(241, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236071/btbbac05vv4_1790654877.jpg', 3, 0),
(241, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236071/btbbac05vv5_1790654883.jpg', 4, 0),
(241, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236071/btbbac05vv6_1790654882.png', 5, 0),
(242, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713890/btbtcc109vv1_1766894678.png', 0, 1),
(242, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713890/btbtcc109vv2_1766894703.jpg', 1, 0),
(242, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713890/btbtcc109vv3_1766894703.jpg', 2, 0),
(242, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713890/btbtcc109vv4_1766894703.jpg', 3, 0),
(242, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713890/btbtcc109vv5_1766894703.jpg', 4, 0),
(242, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713890/btbtcc109vv6_1766894703.png', 5, 0),
(243, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714111/btbtcc110vh1_1766895766.png', 0, 1),
(243, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714111/btbtcc110vh2_1766895783.jpg', 1, 0),
(243, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714111/btbtcc110vh3_1766895786.jpg', 2, 0),
(243, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714111/btbtcc110vh4_1766895791.jpg', 3, 0),
(243, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714111/btbtcc110vh5_1766895793.jpg', 4, 0),
(243, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714111/btbtcc110vh6_1766895796.png', 5, 0),
(244, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754490/btbtcc836_1715668975.png', 0, 1),
(244, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754490/btbtcc831_1715668975.jpg', 1, 0),
(244, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754490/btbtcc832_1715668975.jpg', 2, 0),
(244, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754490/btbtcc833_1715668975.jpg', 3, 0),
(244, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754490/btbtcc834_1715668980.jpg', 4, 0),
(244, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754490/btbtcc838_1715668984.jpg', 5, 0),
(245, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754492/btbtcc856_1715669354.png', 0, 1),
(245, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754492/btbtcc851_1715669354.jpg', 1, 0),
(245, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754492/btbtcc852_1715669354.jpg', 2, 0),
(245, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754492/btbtcc853_1715669354.jpg', 3, 0),
(245, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754492/btbtcc854_1715669354.jpg', 4, 0),
(245, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754492/btbtcc858_1715669354.jpg', 5, 0),
(246, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754452/btbtcc866_1715652054.png', 0, 1),
(246, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754452/btbtcc863_1715652054.jpg', 1, 0),
(246, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754452/btbtcc864_1715652054.jpg', 2, 0),
(246, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754452/btbtcc862_1715652054.jpg', 3, 0),
(246, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754452/btbtcc861_1715652054.jpg', 4, 0),
(246, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754452/btbtcc868_1715652054.jpg', 5, 0),
(247, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754454/btbtcc886_1715652836.png', 0, 1),
(247, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754454/btbtcc881_1715652836.jpg', 1, 0),
(247, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754454/btbtcc882_1715652836.jpg', 2, 0),
(247, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754454/btbtcc883_1715652835.jpg', 3, 0),
(247, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754454/btbtcc884_1715652835.jpg', 4, 0),
(247, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754454/btbtcc888_1715652836.jpg', 5, 0),
(248, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714196/btbz03022k1_1766903172.png', 0, 1),
(248, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714196/btbz030vv2_1766903177.jpg', 1, 0),
(248, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714196/btbz030vv3_1766903179.jpg', 2, 0),
(248, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714196/btbz030vv4_1766903182.jpg', 3, 0),
(248, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714196/btbz030vv5_1766903192.jpg', 4, 0),
(248, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714196/btbz03022k5_1766903188.png', 5, 0),
(249, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766169/btbtcc112vh1_1763104601.png', 0, 1),
(249, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766169/btbtcc112vh2_1763104601.jpg', 1, 0),
(249, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766169/btbtcc112vh3_1763104601.jpg', 2, 0),
(249, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766169/btbtcc112vh5_1763104601.jpg', 3, 0),
(249, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766169/btbtcc112vh4_1763104601.jpg', 4, 0),
(249, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766169/btbtcc112vh6_1763104601.png', 5, 0),
(250, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765938/btbz050vt1_1762778112.png', 0, 1),
(250, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765938/btbz050vt2_1762778111.jpg', 1, 0),
(250, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765938/btbz050vt3_1762778111.jpg', 2, 0),
(250, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765938/btbz050vt4_1762778111.jpg', 3, 0),
(250, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765938/btbz050vt5_1762778111.jpg', 4, 0),
(250, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765938/btbz050vt6_1762778111.png', 5, 0),
(251, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766014/btbz051vt1_1762778750.png', 0, 1),
(251, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766014/btbz051vt2_1762778750.jpg', 1, 0),
(251, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766014/btbz051vt3_1762778750.jpg', 2, 0),
(251, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766014/btbz051vt4_1762778750.jpg', 3, 0),
(251, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766014/btbz051vt5_1762778749.jpg', 4, 0),
(251, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766014/btbz051vt6_1762778750.png', 5, 0),
(252, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766046/btbz052vt1_1762779226.png', 0, 1),
(252, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766046/btbz052vt2_1762779226.jpg', 1, 0),
(252, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766046/btbz052vt3_1762779226.jpg', 2, 0),
(252, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766046/btbz052vt4_1762779226.jpg', 3, 0),
(252, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766046/btbz052vt5_1762779226.jpg', 4, 0),
(252, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766046/btbz052vt6_1762779226.png', 5, 0),
(253, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766072/btbz053vt1_1762780009.png', 0, 1),
(253, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766072/btbz053vt2_1762780009.jpg', 1, 0),
(253, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766072/btbz053vt3_1762780009.jpg', 2, 0),
(253, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766072/btbz053vt4_1762780009.jpg', 3, 0),
(253, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766072/btbz053vt5_1762780009.jpg', 4, 0),
(253, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766072/btbz053vt6_1762780009.png', 5, 0),
(254, 'https://cdn.huythanhjewelry.vn/storage/photos/uploads/btbz056vh1_1762780575.png', 0, 1),
(254, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766124/btbz056vt2_1762780597.jpg', 1, 0),
(254, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766124/btbz056vt3_1762780624.jpg', 2, 0),
(254, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766124/btbz056vt4_1762780630.jpg', 3, 0),
(254, 'https://cdn.huythanhjewelry.vn/storage/photos/uploads/btbz056vt5_1762780647.jpg', 4, 0),
(254, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766124/btbz056vh6_1762780651.png', 5, 0),
(255, 'https://cdn.huythanhjewelry.vn/storage/photos/uploads/btptb421vh1_1762781792.png', 0, 1),
(255, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766146/btptb421vh2_1762781795.jpg', 1, 0),
(255, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766146/btptb421vh3_1762781799.jpg', 2, 0),
(255, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766146/btptb421vh4_1762781805.jpg', 3, 0),
(255, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766146/btptb421vh5_1762781809.jpg', 4, 0),
(255, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766146/btptb421vh6_1762781812.jpg', 5, 0),
(255, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762766146/btptb421vh6_1762781815.png', 6, 0),
(256, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713141/btbkc033vh1_1766889559.png', 0, 1),
(256, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713141/btbkc033vh2_1766889566.jpg', 1, 0),
(256, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713141/btbkc033vh3_1766889570.jpg', 2, 0),
(256, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713141/btbkc033vh4_1766889573.jpg', 3, 0),
(256, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713141/btbkc033vh5_1766889576.jpg', 4, 0),
(256, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713141/btbkc033vh5_1766889581.png', 5, 0),
(257, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713232/btbkc034vh1_1766889804.png', 0, 1),
(257, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713232/btbkc034vh2_1766889810.jpg', 1, 0),
(257, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713232/btbkc034vh3_1766889810.jpg', 2, 0),
(257, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713232/btbkc034vh4_1766889817.jpg', 3, 0),
(257, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713232/btbkc034vh5_1766889820.jpg', 4, 0),
(257, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713232/btbkc034vh5_1766889823.png', 5, 0),
(258, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713275/btbkc035vv1_1766889903.png', 0, 1),
(258, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713275/btbkc035vv2_1766889907.jpg', 1, 0),
(258, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713275/btbkc035vv3_1766889910.jpg', 2, 0),
(258, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713275/btbkc035vv4_1766889913.jpg', 3, 0),
(258, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713275/btbkc035vv5_1766889916.jpg', 4, 0),
(258, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713275/btbkc035vv5_1766889920.png', 5, 0),
(259, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713334/btbkc036vh1_1766890056.png', 0, 1),
(259, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713334/btbkc036vh2_1766890062.jpg', 1, 0),
(259, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713334/btbkc036vh3_1766890062.jpg', 2, 0),
(259, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713334/btbkc036vh4_1766890069.jpg', 3, 0),
(259, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713334/btbkc036vh5_1766890072.jpg', 4, 0),
(259, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713334/btbkc036vh5_1766890075.png', 5, 0),
(260, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713435/btbkc037vt1_1766893479.png', 0, 1),
(260, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713435/btbkc037vt2_1766893484.jpg', 1, 0),
(260, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713435/btbkc037vt3_1766893484.jpg', 2, 0),
(260, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713435/btbkc037vt4_1766893484.jpg', 3, 0),
(260, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713435/btbkc037vt5_1766893499.jpg', 4, 0),
(260, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713435/btbkc037vt5_1766893499.png', 5, 0),
(261, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713530/btbkc038vt1_1766893778.png', 0, 1),
(261, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713530/btbkc038vt2_1766893784.jpg', 1, 0),
(261, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713530/btbkc038vt3_1766893784.jpg', 2, 0),
(261, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713530/btbkc038vt4_1766893784.jpg', 3, 0),
(261, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713530/btbkc038vt5_1766893792.jpg', 4, 0),
(261, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713530/btbkc038vt5_1766893792.png', 5, 0),
(261, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713530/btbkc038vt6_1766893798.png', 6, 0),
(262, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713631/btbkc039vh1_1766893895.png', 0, 1),
(262, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713631/btbkc039vh2_1766893911.jpg', 1, 0),
(262, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713631/btbkc039vh3_1766893911.jpg', 2, 0),
(262, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713631/btbkc039vh4_1766893912.jpg', 3, 0),
(262, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713631/btbkc039vh5_1766893911.jpg', 4, 0),
(262, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713631/btbkc039vh6_1766893905.png', 5, 0),
(262, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713631/btbkc039vh5_1766893905.png', 6, 0),
(263, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713680/btbkc040vt1_1766894150.png', 0, 1),
(263, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713680/btbkc040vt2_1766894158.jpg', 1, 0),
(263, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713680/btbkc040vt3_1766894158.jpg', 2, 0),
(263, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713680/btbkc040vt4_1766894158.jpg', 3, 0),
(263, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713680/btbkc040vt5_1766894163.jpg', 4, 0),
(263, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713680/btbkc040vt5_1766894163.png', 5, 0),
(263, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713680/btbkc040vt6_1766894163.png', 6, 0),
(264, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088665/btbz040vv1_1760155820.png', 0, 1),
(264, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088665/btbz040vv2_1760155820.jpg', 1, 0),
(264, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088665/btbz040vv3_1760155820.jpg', 2, 0),
(264, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088665/btbz040vv4_1760155820.jpg', 3, 0),
(264, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088665/btbz040vv5_1760155820.jpg', 4, 0),
(264, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088665/btbz040vv5_1760155838.png', 5, 0),
(265, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088590/btbz041vv1_1760155669.png', 0, 1),
(265, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088590/btbz041vv2_1760155669.jpg', 1, 0),
(265, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088590/btbz041vv3_1760155669.jpg', 2, 0),
(265, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088590/btbz041vv4_1760155669.jpg', 3, 0),
(265, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088590/btbz041vv5_1760155676.jpg', 4, 0),
(265, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088590/btbz041vv5_1760155685.png', 5, 0),
(266, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115517/btbz043vt1_1761298570.png', 0, 1),
(266, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115517/btbz043vt2_1761298569.jpg', 1, 0),
(266, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115517/btbz043vt3_1761298569.jpg', 2, 0),
(266, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115517/btbz043vt4_1761298569.jpg', 3, 0),
(266, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115517/btbz043vt5_1761298569.jpg', 4, 0),
(266, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1761115517/btbz043vt5_1761298569.png', 5, 0),
(267, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713738/btam140vv1_1766894473.png', 0, 1),
(267, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713738/btam140vv2_1766894472.jpg', 1, 0),
(267, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713738/btam140vv3_1766894472.jpg', 2, 0),
(267, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713738/btam140vv4_1766894472.jpg', 3, 0),
(267, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713738/btam140vv5_1766894472.jpg', 4, 0),
(267, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766713738/btam140vv5_1766894472.png', 5, 0),
(268, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1740646727/btptb390vh1_1745477319.png', 0, 1),
(268, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1740646727/btptb390vh2_1745477319.jpg', 1, 0),
(268, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1740646727/btptb390vh6_1745477319.jpg', 2, 0),
(268, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1740646727/btptb390vh2_1743750137.jpg', 3, 0),
(268, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1740646727/btptb390vh4_1745477319.jpg', 4, 0),
(268, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1740646727/btptb390vh3_1745477319.png', 5, 0),
(269, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088365/btptb412vv1_1760153291.png', 0, 1),
(269, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088365/btptb412vv2_1760153290.jpg', 1, 0),
(269, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088365/btptb412vv3_1760153302.jpg', 2, 0),
(269, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088365/btptb412vv4_1760153302.jpg', 3, 0),
(269, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088365/btptb412vv5_1760153301.jpg', 4, 0),
(269, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088365/btptb412vv5_1760153302.png', 5, 0),
(270, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743760286/dcb03vv1_1745478036.png', 0, 1),
(270, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743760286/dcb03vv2-2_1745479358.jpg', 1, 0),
(270, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743760286/dcb03vv2_1745479358.jpg', 2, 0),
(270, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743760286/dcb03vv4-2_1745479358.jpg', 3, 0),
(270, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743760286/dcb03vv4_1745479358.jpg', 4, 0),
(270, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1743760286/dcb03vv6_1745479358.jpg', 5, 0),
(271, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcbz067/vh/dcbz067_vh_1.png', 0, 1),
(271, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcbz067/vh/dcbz067_vh_2.jpg', 1, 0),
(271, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcbz067/vh/dcbz067_vh_3.jpg', 2, 0),
(271, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcbz067/vh/dcbz067_vh_4.jpg', 3, 0),
(271, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcbz067/vh/dcbz067_vh_5.png', 4, 0),
(271, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcbz067/vh/dcbz067_vh_6.png', 5, 0),
(272, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754189/dcmamd6796_1715767946.png', 0, 1),
(272, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754189/dcmamd6791_1715767946.jpg', 1, 0),
(272, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754189/dcmamd6792_1715767946.jpg', 2, 0),
(272, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754189/dcmamd6793_1715767946.jpg', 3, 0),
(272, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754189/dcmamd6797_1715767946.png', 4, 0),
(272, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754189/dcmamd6798_1715767946.jpg', 5, 0),
(273, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754190/dcmamd68161_1715768338.png', 0, 1),
(273, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754190/dcmamd6811_1715768338.jpg', 1, 0),
(273, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754190/dcmamd6812_1715768338.jpg', 2, 0),
(273, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754190/dcmamd6813_1715768338.jpg', 3, 0),
(273, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754190/dcmamd68171_1715768338.png', 4, 0),
(273, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754190/dcmamd681-18_1715768338.jpg', 5, 0),
(274, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754515/dcptb34511_1716186329.png', 0, 1),
(274, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754515/dcptb3451_1716186338.jpg', 1, 0),
(274, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754515/dcptb3453_1716186338.jpg', 2, 0),
(274, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754515/dcptb3452_1716186338.jpg', 3, 0),
(274, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754515/dcptb34561_1716186329.png', 4, 0),
(274, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754515/dcptb34551_1716186318.png', 5, 0),
(275, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662870/dcz050vv11_1764850497.png', 0, 1),
(275, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662870/dcz050vv6_1764850497.jpg', 1, 0),
(275, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662870/dcz050vv4_1764850497.jpg', 2, 0),
(275, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662870/dcz050vv2_1764850497.jpg', 3, 0),
(275, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662870/dcz050vv3_1764850497.png', 4, 0),
(275, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662870/dcz050vv5_1764850497.png', 5, 0),
(276, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087825/dcz085vv1_1760449765.png', 0, 1),
(276, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087825/dcz085vh2_1760154813.jpg', 1, 0),
(276, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087825/dcz085vh6_1760154827.jpg', 2, 0),
(276, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087825/dcz085vh4_1760154827.jpg', 3, 0),
(276, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087825/dcz085vv3_1760449775.png', 4, 0),
(276, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087825/dcz085vv5_1760449778.png', 5, 0),
(277, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz124/vt/dcz124_vt_1.png', 0, 1),
(277, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz124/vt/dcz124_vt_2.jpg', 1, 0),
(277, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz124/vt/dcz124_vt_3.jpg', 2, 0),
(277, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz124/vt/dcz124_vt_4.jpg', 3, 0),
(277, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz124/vt/dcz124_vt_5.png', 4, 0),
(277, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz124/vt/dcz124_vt_6.png', 5, 0),
(278, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662815/dcbz021vv11_1764749572.png', 0, 1),
(278, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662815/dcbz021vv6_1764749591.jpg', 1, 0),
(278, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662815/dcbz021vv4_1764749594.jpg', 2, 0),
(278, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662815/dcbz021vv2_1764749599.jpg', 3, 0),
(278, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662815/dcbz021vv3_1764749605.png', 4, 0),
(278, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662815/dcbz021vv5_1764749609.png', 5, 0),
(279, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759105/dcptb417bac1_1776823729.png', 0, 1),
(279, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759105/dcptb417bac5_1776823729.png', 1, 0),
(279, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759105/dcptb417bac6_1776823729.png', 2, 0),
(279, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759105/dcptb417vh2_1776823729.jpg', 3, 0),
(279, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759105/dcptb417vh3_1776823729.jpg', 4, 0),
(279, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759105/dcptb417vh4_1776823729.jpg', 5, 0),
(280, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759154/dcptb418bac1_1776824481.png', 0, 1),
(280, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759154/dcptb418bac5_1776824490.png', 1, 0),
(280, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759154/dcptb418bac6_1776824490.png', 2, 0),
(280, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759154/dcptb418vh2_1776824490.jpg', 3, 0),
(280, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759154/dcptb418vh3_1776824490.jpg', 4, 0),
(280, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759154/dcptb418vh4_1776824490.jpg', 5, 0),
(281, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601719/dcz043vv3_1738807528.png', 0, 1),
(281, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601719/dcz043vv2_1743760269.jpg', 1, 0),
(281, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601719/dcz043vv6_1743760269.jpg', 2, 0),
(281, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601719/dcz043vv4_1743760269.jpg', 3, 0),
(281, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601719/dcz043vv5_1738807528.png', 4, 0),
(281, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601719/dcz043vv1_1738808811.png', 5, 0),
(282, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601790/dcz058vv1_1743754479.png', 0, 1),
(282, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601790/dcz058vv2_1743754479.jpg', 1, 0),
(282, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601790/dcz058vv6_1743754479.jpg', 2, 0),
(282, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601790/dcz058vv4_1743754479.jpg', 3, 0),
(282, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601790/dcz058vv3_1743754479.png', 4, 0),
(282, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737601790/dcz058vv5_1743754479.png', 5, 0),
(283, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715126/dcz0939251_1766910300.png', 0, 1),
(283, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715126/dcz0939252_1766910328.jpg', 1, 0),
(283, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715126/dcz0939253_1766910313.jpg', 2, 0),
(283, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715126/dcz0939254_1766910313.jpg', 3, 0),
(283, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715126/dcz0939252_1766910371.png', 4, 0),
(283, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715126/dcz093bac6_1766910379.png', 5, 0),
(284, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715234/dcz096bac1_1767062199.png', 0, 1),
(284, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715234/dcz0969252_1767062206.jpg', 1, 0),
(284, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715234/dcz0969253_1767062206.jpg', 2, 0),
(284, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715234/dcz0969254_1767062206.jpg', 3, 0),
(284, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715234/dcz096bac5_1767062211.png', 4, 0),
(284, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715234/dcz096bac6_1767062211.png', 5, 0),
(285, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715254/dcz097bac1_1767063786.png', 0, 1),
(285, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715254/dcz0979252_1767063792.jpg', 1, 0),
(285, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715254/dcz0979253_1767063792.jpg', 2, 0),
(285, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715254/dcz0979254_1767063792.jpg', 3, 0),
(285, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715254/dcz097bac5_1767063797.png', 4, 0),
(285, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715254/dcz097bac6_1767063797.png', 5, 0),
(286, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz122/vh/dcz122_vh_1.png', 0, 1),
(286, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz122/vh/dcz122_vh_2.jpg', 1, 0),
(286, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz122/vh/dcz122_vh_3.jpg', 2, 0),
(286, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz122/vh/dcz122_vh_4.jpg', 3, 0),
(286, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz122/vh/dcz122_vh_5.png', 4, 0),
(286, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcz122/vh/dcz122_vh_6.png', 5, 0),
(287, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236208/dcbac01-vv1_1790241513.jpg', 0, 1),
(287, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236208/dcbac01vv5_1790241525.jpg', 1, 0),
(287, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236208/dcbac01vv6_1790241530.jpg', 2, 0),
(287, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236208/dcbac01vv7_1790241525.jpg', 3, 0),
(287, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236208/dcbac01vv2_1790241537.jpg', 4, 0),
(287, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236208/dcbac01vv3_1790241537.jpg', 5, 0),
(287, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236208/dcbac01vv4_1790241537.jpg', 6, 0),
(288, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236242/dcbac03vv1_1790241328.jpg', 0, 1),
(288, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236242/dcbac03vv5_1790241334.jpg', 1, 0),
(288, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236242/dcbac03vv6_1790241335.jpg', 2, 0),
(288, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236242/dcbac03vv2_1790241344.jpg', 3, 0),
(288, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236242/dcbac03vv3_1790241344.jpg', 4, 0),
(288, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236242/dcbac03vv4_1790241344.jpg', 5, 0),
(289, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236610/dcbbac11vv1_1790238836.jpg', 0, 1),
(289, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236610/dcbbac11vv5_1790238844.jpg', 1, 0),
(289, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236610/dcbbac11vv7_1790238844.jpg', 2, 0),
(289, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236610/dcbbac11vv2_1790238853.jpg', 3, 0),
(289, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236610/dcbbac11vv3_1790238853.jpg', 4, 0),
(289, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236610/dcbbac11vv4_1790238853.jpg', 5, 0),
(290, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236624/dcbbac12-vv1_1790238581.jpg', 0, 1),
(290, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236624/dcbbac12vv8_1790238597.jpg', 1, 0),
(290, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236624/dcbbac12vv5_1790238597.jpg', 2, 0),
(290, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236624/dcbbac12vv3_1790238607.jpg', 3, 0),
(290, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236624/dcbbac12vv2_1790238614.jpg', 4, 0),
(290, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790236624/dcbbac12vv4_1790238607.jpg', 5, 0),
(291, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754489/dcbtcc836_1715668854.png', 0, 1),
(291, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754489/dcbtcc831_1715668854.jpg', 1, 0),
(291, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754489/dcbtcc832_1715668854.jpg', 2, 0);
INSERT INTO dbo.ProductImages (ProductID, ImageUrl, SortOrder, IsThumbnail) VALUES
(291, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754489/dcbtcc833_1715668854.jpg', 3, 0),
(291, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754489/dcbtcc837_1715668854.png', 4, 0),
(291, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754489/dcbtcc838_1715668854.jpg', 5, 0),
(292, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754449/dcbtcc846_1715649830.png', 0, 1),
(292, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754449/dcbtcc841_1715649830.jpg', 1, 0),
(292, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754449/dcbtcc842_1715649830.jpg', 2, 0),
(292, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754449/dcbtcc843_1715649830.jpg', 3, 0),
(292, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754449/dcbtcc847_1715649830.png', 4, 0),
(292, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754449/dcbtcc848_1715649830.jpg', 5, 0),
(293, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754491/dcbtcc856_1715669122.png', 0, 1),
(293, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754491/dcbtcc851_1715669122.jpg', 1, 0),
(293, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754491/dcbtcc852_1715669122.jpg', 2, 0),
(293, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754491/dcbtcc853_1715669122.jpg', 3, 0),
(293, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754491/dcbtcc857_1715669122.png', 4, 0),
(293, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754491/dcbtcc858_1715669141.jpg', 5, 0),
(294, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754451/dcbtcc866_1715651208.png', 0, 1),
(294, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754451/dcbtcc863_1715651208.jpg', 1, 0),
(294, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754451/dcbtcc862_1715651208.jpg', 2, 0),
(294, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754451/dcbtcc861_1715651208.jpg', 3, 0),
(294, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754451/dcbtcc867_1715651208.png', 4, 0),
(294, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754451/dcbtcc868_1715651208.jpg', 5, 0),
(295, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714772/dcbz046vv1_1766908556.png', 0, 1),
(295, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714772/dcbz046vv2_1766908556.jpg', 1, 0),
(295, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714772/dcbz046vv3_1766908556.jpg', 2, 0),
(295, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714772/dcbz046vv4_1766908556.jpg', 3, 0),
(295, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714772/dcbz046vv6_1766908556.png', 4, 0),
(295, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766714772/dcbz046vv5_1766908556.png', 5, 0),
(296, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759350/dcz100vt1_1776911349.png', 0, 1),
(296, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759350/dcz100vt2_1776911348.jpg', 1, 0),
(296, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759350/dcz100vt3_1776911348.jpg', 2, 0),
(296, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759350/dcz100vt4_1776911348.jpg', 3, 0),
(296, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759350/dcz100vt5_1776911349.png', 4, 0),
(296, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776759350/dcz100vt6_1776911348.png', 5, 0),
(297, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765199/dcbz050vt1_1762775961.png', 0, 1),
(297, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765199/dcbz050vt2_1762775961.jpg', 1, 0),
(297, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765199/dcbz050vt3_1762775961.jpg', 2, 0),
(297, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765199/dcbz050vt4_1762775961.jpg', 3, 0),
(297, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765199/dcbz050vt5_1762775961.png', 4, 0),
(297, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765199/dcbz050vt6_1762775961.png', 5, 0),
(298, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765412/dcbz053vt1_1762779899.png', 0, 1),
(298, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765412/dcbz053vt2_1762779899.jpg', 1, 0),
(298, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765412/dcbz053vt3_1762779899.jpg', 2, 0),
(298, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765412/dcbz053vt4_1762779899.jpg', 3, 0),
(298, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765412/dcbz053vt5_1762779899.png', 4, 0),
(298, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765412/dcbz053vt6_1762779899.png', 5, 0),
(299, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765455/dcbz056vt1_1762780191.png', 0, 1),
(299, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765455/dcbz056vt2_1762780190.jpg', 1, 0),
(299, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765455/dcbz056vt3_1762780190.jpg', 2, 0),
(299, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765455/dcbz056vt4_1762780190.jpg', 3, 0),
(299, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765455/dcbz056vt5_1762780191.png', 4, 0),
(299, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765455/dcbz056vt6_1762780191.png', 5, 0),
(300, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765696/dcz099vt1_1762830518.png', 0, 1),
(300, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765696/dcz099vt2_1762830518.jpg', 1, 0),
(300, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765696/dcz099vt3_1762830517.jpg', 2, 0),
(300, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765696/dcz099vt4_1762830518.jpg', 3, 0),
(300, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765696/dcz099vt5_1762830518.png', 4, 0),
(300, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765696/dcz099vt6_1762830518.png', 5, 0),
(301, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765741/dcz101vv1_1762830626.png', 0, 1),
(301, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765741/dcz101vv2_1762830626.jpg', 1, 0),
(301, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765741/dcz101vv3_1762830626.jpg', 2, 0),
(301, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765741/dcz101vv4_1762830626.jpg', 3, 0),
(301, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765741/dcz101vv5_1762830626.png', 4, 0),
(301, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765741/dcz101vv6_1762830626.png', 5, 0),
(302, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765772/dcz102vt1_1762830696.png', 0, 1),
(302, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765772/dcz102vt2_1762830695.jpg', 1, 0),
(302, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765772/dcz102vt3_1762830695.jpg', 2, 0),
(302, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765772/dcz102vt4_1762830696.jpg', 3, 0),
(302, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765772/dcz102vt5_1762830696.png', 4, 0),
(302, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765772/dcz102vt6_1762830696.png', 5, 0),
(303, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765790/dcz103vt1_1762831325.png', 0, 1),
(303, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765790/dcz103vt2_1762831324.jpg', 1, 0),
(303, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765790/dcz103vt3_1762831324.jpg', 2, 0),
(303, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765790/dcz103vt4_1762831325.jpg', 3, 0),
(303, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765790/dcz103vt5_1762831325.png', 4, 0),
(303, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765790/dcz103vt6_1762831324.png', 5, 0),
(304, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765807/dcz104vt1_1762831397.png', 0, 1),
(304, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765807/dcz104vt2_1762831397.jpg', 1, 0),
(304, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765807/dcz104vt3_1762831397.jpg', 2, 0),
(304, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765807/dcz104vt4_1762831397.jpg', 3, 0),
(304, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765807/dcz104vt5_1762831397.png', 4, 0),
(304, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765807/dcz104vt6_1762831397.png', 5, 0),
(305, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765833/dcz105vt1_1763102670.png', 0, 1),
(305, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765833/dcz105vt2_1763102670.jpg', 1, 0),
(305, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765833/dcz105vt3_1763102670.jpg', 2, 0),
(305, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765833/dcz105vt4_1763102670.jpg', 3, 0),
(305, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765833/dcz105vt5_1763102670.png', 4, 0),
(305, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1762765833/dcz105vt6_1763102670.png', 5, 0),
(306, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438648/dcmamd811vh1_1752890296.png', 0, 1),
(306, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438648/dcmamd811vh2_1752890303.jpg', 1, 0),
(306, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438648/dcmamd811vh4_1752890352.jpg', 2, 0),
(306, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438648/dcmamd811vh6_1752890358.jpg', 3, 0),
(306, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438648/dcmamd811vh3_1752890389.png', 4, 0),
(306, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438648/dcmamd811vh5_1752890395.png', 5, 0),
(307, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438733/dcmamd813vv1_1752890997.png', 0, 1),
(307, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438733/dcmamd813vv2_1752891055.jpg', 1, 0),
(307, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438733/dcmamd813vv4_1752891067.jpg', 2, 0),
(307, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438733/dcmamd813vv6_1752891073.jpg', 3, 0),
(307, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438733/dcmamd813vv3_1752891083.png', 4, 0),
(307, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438733/dcmamd813vv5_1752891090.png', 5, 0),
(308, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438767/dcmamd814vv1_1752891264.png', 0, 1),
(308, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438767/dcmamd814vv2_1752891289.jpg', 1, 0),
(308, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438767/dcmamd814vv4_1752891326.jpg', 2, 0),
(308, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438767/dcmamd814vv6_1752891331.jpg', 3, 0),
(308, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438767/dcmamd814vv3_1752891344.png', 4, 0),
(308, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438767/dcmamd814vv5_1752891352.png', 5, 0),
(309, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd829/vh/dcmzmd829_vh_1.png', 0, 1),
(309, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd829/vh/dcmamd829_vh_2.jpg', 1, 0),
(309, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd829/vh/dcmamd829_vh_3.jpg', 2, 0),
(309, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd829/vh/dcmamd829_vh_4.jpg', 3, 0),
(309, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd829/vh/dcmzmd829_vh_5.png', 4, 0),
(309, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd829/vh/dcmzmd829_vh_6.png', 5, 0),
(310, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438583/dcptb405vv1_1749028638.png', 0, 1),
(310, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438583/dcptb405vv2_1749028638.jpg', 1, 0),
(310, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438583/dcptb405vv6_1749028638.jpg', 2, 0),
(310, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438583/dcptb405vv4_1749028638.jpg', 3, 0),
(310, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438583/dcptb405vv5_1749028638.png', 4, 0),
(310, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438583/dcptb405vv3_1749028638.png', 5, 0),
(311, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087691/dcptb413vv1_1760157291.png', 0, 1),
(311, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087691/dcptb413vv4_1760157291.jpg', 1, 0),
(311, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087691/dcptb413vv3_1760157291.jpg', 2, 0),
(311, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087691/dcptb413vv2_1760157291.jpg', 3, 0),
(311, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087691/dcptb413vv5_1760157291.png', 4, 0),
(311, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760087691/dcptb413vv1_1760157320.png', 5, 0),
(312, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd827/vv/dcmamd827_vv_1.png', 0, 1),
(312, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd827/vv/dcmamd827_vv_2.jpg', 1, 0),
(312, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd827/vv/dcmamd827_vv_3.jpg', 2, 0),
(312, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd827/vv/dcmamd827_vv_4.jpg', 3, 0),
(312, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd827/vv/dcmamd827_vv_5.png', 4, 0),
(312, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/product/dcmamd827/vv/dcmamd827_vv_6.png', 5, 0),
(313, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662897/dcz086ldiavv11_1764850641.png', 0, 1),
(313, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662897/dcz086ldiavv6_1764850641.jpg', 1, 0),
(313, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662897/dcz086ldiavv4_1764850641.jpg', 2, 0),
(313, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662897/dcz086ldiavv2_1764850641.jpg', 3, 0),
(313, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662897/dcz086ldiavv5_1764850641.png', 4, 0),
(313, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764662897/dcz086ldiavv3_1764850641.png', 5, 0),
(314, 'https://cloud.huythanhjewelry.vn/storage/photos/uploads/dcbz033vv1_1753419981.png', 0, 1),
(314, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1753091328623/dcbz033vh2_1753102588.jpg', 1, 0),
(314, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1753091328623/dcbz033vh3_1753102588.jpg', 2, 0),
(314, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1753091328623/dcbz033vh4_1753102604.jpg', 3, 0),
(314, 'https://cloud.huythanhjewelry.vn/storage/photos/uploads/dcbz033vv5_1753419995.png', 4, 0),
(314, 'https://cloud.huythanhjewelry.vn/storage/photos/uploads/dcbz033vv6_1753420005.png', 5, 0),
(315, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663027/mdbz022vv1_1764752066.png', 0, 1),
(315, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663027/mdbz022vv6_1764752073.jpg', 1, 0),
(315, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663027/mdbz022vv4_1764752076.jpg', 2, 0),
(315, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663027/mdbz022vv2_1764752079.jpg', 3, 0),
(315, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663027/mdbz022vv5_1764752085.png', 4, 0),
(315, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663027/mdbz022vv3_1764752089.png', 5, 0),
(316, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754216/mdmamd65712_1715830478.png', 0, 1),
(316, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754216/mdmamd6571_1715830478.jpg', 1, 0),
(316, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754216/mdmamd6573_1715830478.jpg', 2, 0),
(316, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754216/mdmamd6572_1715830505.jpg', 3, 0),
(316, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754216/mdmamd65762_1715830478.png', 4, 0),
(316, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754216/mdmamd65752_1715830478.png', 5, 0),
(317, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754217/mdmamd65911_1715830674.png', 0, 1),
(317, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754217/mdmamd6591_1715830641.jpg', 1, 0),
(317, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754217/mdmamd6593_1715830641.jpg', 2, 0),
(317, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754217/mdmamd6592_1715830663.jpg', 3, 0),
(317, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754217/mdmamd65951_1715830664.png', 4, 0),
(317, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754217/mdmamd65961_1715830664.png', 5, 0),
(318, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754218/mdmamd6601_1715831469.png', 0, 1),
(318, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754218/mdmamd6601_1715831469.jpg', 1, 0),
(318, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754218/mdmamd6602_1715831469.jpg', 2, 0),
(318, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754218/mdmamd6603_1715831469.jpg', 3, 0),
(318, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754218/mdmamd6605_1715831469.png', 4, 0),
(318, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754218/mdmamd6606_1715831469.png', 5, 0),
(319, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754219/mdmamd6641_1715831551.png', 0, 1),
(319, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754219/mdmamd6641_1715831551.jpg', 1, 0),
(319, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754219/mdmamd6642_1715831551.jpg', 2, 0),
(319, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754219/mdmamd6643_1715831551.jpg', 3, 0),
(319, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754219/mdmamd6645_1715831551.png', 4, 0),
(319, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754219/mdmamd6646_1715831551.png', 5, 0),
(320, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754254/mdmamd6651_1715841928.png', 0, 1),
(320, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754254/mdmamd6651_1715841928.jpg', 1, 0),
(320, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754254/mdmamd6653_1715841928.jpg', 2, 0),
(320, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754254/mdmamd6652_1715841928.jpg', 3, 0),
(320, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754254/mdmamd6655_1715841928.png', 4, 0),
(320, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754254/mdmamd6656_1715841928.png', 5, 0),
(321, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754220/mdmamd66711_1715831676.png', 0, 1),
(321, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754220/mdmamd6671_1715831676.jpg', 1, 0),
(321, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754220/mdmamd6672_1715831676.jpg', 2, 0),
(321, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754220/mdmamd6673_1715831681.jpg', 3, 0),
(321, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754220/mdmamd66751_1715831676.png', 4, 0),
(321, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754220/mdmamd66762_1715831681.png', 5, 0),
(322, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754244/mdmamd6756_1715840074.png', 0, 1),
(322, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754244/mdmamd675syntheite-ruby1_1715840065.jpg', 1, 0),
(322, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754244/mdmamd675garnet-cz3_1715840065.jpg', 2, 0),
(322, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754244/mdmamd675garnet-cz2_1715840065.jpg', 3, 0),
(322, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754244/mdmamd6758_1715840074.png', 4, 0),
(322, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754244/mdmamd6757_1715840074.png', 5, 0),
(323, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754245/mdmamd6766_1715840403.png', 0, 1),
(323, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754245/mdmamd676glass-sapphair1_1715840402.jpg', 1, 0),
(323, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754245/mdmamd676spinel-topaz2_1715840410.jpg', 2, 0),
(323, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754245/mdmamd676spinel-topaz3_1715840410.jpg', 3, 0),
(323, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754245/mdmamd676spinel-topaz1_1715840410.jpg', 4, 0),
(323, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754245/mdmamd676glass-sapphair3_1715840402.jpg', 5, 0),
(323, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754245/mdmamd676glass-sapphair2_1715840402.jpg', 6, 0),
(323, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754245/mdmamd6768_1715840403.png', 7, 0),
(323, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754245/mdmamd6767_1715840403.png', 8, 0),
(324, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754246/mdmamd6776_1715840625.png', 0, 1),
(324, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754246/mdmamd6771_1715840612.jpg', 1, 0),
(324, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754246/mdmamd6772_1715840612.jpg', 2, 0),
(324, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754246/mdmamd6773_1715840612.jpg', 3, 0),
(324, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754246/mdmamd6778_1715840625.png', 4, 0),
(324, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754246/mdmamd6777_1715840635.png', 5, 0),
(325, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754226/mdmamd6806_1715832449.png', 0, 1),
(325, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754226/mdmamd6801_1715832449.jpg', 1, 0),
(325, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754226/mdmamd6802_1715832449.jpg', 2, 0),
(325, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754226/mdmamd6803_1715832449.jpg', 3, 0),
(325, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754226/mdmamd6807_1715832449.png', 4, 0),
(325, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754226/mdmamd6808_1715832449.jpg', 5, 0),
(326, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754248/mdmamd6886_1715840864.png', 0, 1),
(326, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754248/mdmamd6881_1715840864.jpg', 1, 0),
(326, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754248/mdmamd6882_1715840864.jpg', 2, 0),
(326, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754248/mdmamd6883_1715840864.jpg', 3, 0),
(326, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754248/mdmamd6887_1715840864.png', 4, 0),
(326, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754248/mdmamd6888_1715840864.jpg', 5, 0),
(327, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754249/mdmamd6896_1715840960.png', 0, 1),
(327, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754249/mdmamd6891_1715840960.jpg', 1, 0),
(327, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754249/mdmamd6892_1715840960.jpg', 2, 0),
(327, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754249/mdmamd6893_1715840960.jpg', 3, 0),
(327, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754249/mdmamd6897_1715840960.png', 4, 0),
(327, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754249/mdmamd6898_1715840960.jpg', 5, 0),
(328, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754250/mdmamd6906_1715841052.png', 0, 1),
(328, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754250/mdmamd6901_1715841052.jpg', 1, 0),
(328, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754250/mdmamd6902_1715841052.jpg', 2, 0),
(328, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754250/mdmamd6903_1715841052.jpg', 3, 0),
(328, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754250/mdmamd6907_1715841052.png', 4, 0),
(328, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754250/mdmamd6908_1715841052.jpg', 5, 0),
(329, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754251/mdmamd6916_1715841118.png', 0, 1),
(329, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754251/mdmamd6911_1715841118.jpg', 1, 0),
(329, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754251/mdmamd6912_1715841118.jpg', 2, 0),
(329, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754251/mdmamd6913_1715841118.jpg', 3, 0),
(329, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754251/mdmamd6917_1715841118.png', 4, 0),
(329, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754251/mdmamd6918_1715841118.jpg', 5, 0),
(330, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754252/mdmamd6926_1715841178.png', 0, 1),
(330, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754252/mdmamd6921_1715841178.jpg', 1, 0),
(330, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754252/mdmamd6922_1715841178.jpg', 2, 0),
(330, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754252/mdmamd6923_1715841178.jpg', 3, 0),
(330, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754252/mdmamd6927_1715841178.png', 4, 0),
(330, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754252/mdmamd6928_1715841178.jpg', 5, 0),
(331, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754253/mdmamd6936_1715841280.png', 0, 1),
(331, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754253/mdmamd6931_1715841280.jpg', 1, 0),
(331, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754253/mdmamd6932_1715841280.jpg', 2, 0),
(331, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754253/mdmamd6933_1715841280.jpg', 3, 0),
(331, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754253/mdmamd6937_1715841280.png', 4, 0),
(331, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754253/mdmamd6938_1715841299.jpg', 5, 0),
(332, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754509/mdptb34211_1716177086.png', 0, 1),
(332, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754509/mdptb3421_1716456158.jpg', 1, 0),
(332, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754509/mdptb3423_1716456158.jpg', 2, 0),
(332, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754509/mdptb3422_1716456158.jpg', 3, 0),
(332, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754509/mdptb34251_1716177164.png', 4, 0),
(332, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754509/mdptb34261_1716177185.png', 5, 0),
(333, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754513/mdptb34912_1716180623.png', 0, 1),
(333, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754513/mdptb3491_1716180724.jpg', 1, 0),
(333, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754513/mdptb3493_1716180724.jpg', 2, 0),
(333, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754513/mdptb3492_1716180724.jpg', 3, 0),
(333, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754513/mdptb34952_1716180646.png', 4, 0),
(333, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754513/mdptb34962_1716180653.png', 5, 0),
(334, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754470/mdptb35111_1728871332.png', 0, 1),
(334, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754470/mdptb3511_1728871375.jpg', 1, 0),
(334, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754470/mdptb3512_1728871375.jpg', 2, 0),
(334, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754470/mdptb3513_1728871375.jpg', 3, 0),
(334, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754470/mdptb35151_1728871338.png', 4, 0),
(334, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754470/mdptb35161_1728871338.png', 5, 0),
(335, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754472/mdptb35212_1728870676.png', 0, 1),
(335, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754472/mdptb3521_1728870676.jpg', 1, 0),
(335, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754472/mdptb3522_1728870681.jpg', 2, 0),
(335, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754472/mdptb3523_1728870682.jpg', 3, 0),
(335, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754472/mdptb35252_1728870682.png', 4, 0),
(335, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754472/mdptb35262_1728870686.png', 5, 0),
(336, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663094/mdz059vv1_1764852077.png', 0, 1),
(336, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663094/mdz059vv6_1764852077.jpg', 1, 0),
(336, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663094/mdz059vv4_1764852077.jpg', 2, 0),
(336, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663094/mdz059vv2_1764852077.jpg', 3, 0),
(336, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663094/mdz059vv3_1764852077.png', 4, 0),
(336, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1764663094/mdz059vv5_1764852076.png', 5, 0),
(337, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905677/mdz033-vv-3_1726628175.png', 0, 1),
(337, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905677/mdz033vv2_1728362726.jpg', 1, 0),
(337, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905677/mdz033vv4_1728362726.jpg', 2, 0),
(337, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905677/mdz033-vv-1_1726628152.png', 3, 0),
(337, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905677/mdz033-vv-7_1726628175.png', 4, 0),
(337, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905677/mdz033-vv-5_1726628152.png', 5, 0),
(338, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905678/mdz035-vv-3_1726628220.png', 0, 1),
(338, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905678/mdz035vv2_1727923846.jpg', 1, 0),
(338, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905678/mdz035vv4_1727923846.jpg', 2, 0),
(338, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905678/mdz035-vv-1_1726628208.png', 3, 0),
(338, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905678/mdz035-vv-5_1726628220.png', 4, 0),
(338, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1724905678/mdz035-vv-7_1726628208.png', 5, 0),
(339, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737600881/mdz057vv1_1740993727.png', 0, 1),
(339, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1737600881/mdz057vv2_1752896023.jpg', 1, 0),
(339, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1737600881/mdz057vv6_1752896037.jpg', 2, 0),
(339, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1737600881/mdz057vv4_1752896048.jpg', 3, 0),
(339, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737600881/mdz057vv5_1740993727.png', 4, 0),
(339, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1737600881/mdz057vv3_1740993727.png', 5, 0),
(340, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745898424/mdz07622k1_1749029828.png', 0, 1),
(340, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1745898424/mdz07622k2_1752309789.jpg', 1, 0),
(340, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1745898424/mdz07622k3_1752309789.jpg', 2, 0),
(340, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1745898424/mdz07622k4_1752309789.jpg', 3, 0),
(340, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1745898424/mdz07622k5_1752309789.png', 4, 0),
(340, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1745898424/mdz07622k6_1752309789.png', 5, 0),
(341, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1752807162619/mdbz036bac9251_1769417875.png', 0, 1),
(341, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1752807162619/mdbz036vv2_1769417869.jpg', 1, 0),
(341, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1752807162619/mdbz036vv4_1769417852.jpg', 2, 0),
(341, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1752807162619/mdbz036vv3_1769417852.jpg', 3, 0),
(341, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1752807162619/mdbz036bac9255_1769417875.png', 4, 0),
(341, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1752807162619/mdbz036bac9256_1769417875.png', 5, 0),
(342, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792427/mdbz038bac9251_1769418691.png', 0, 1),
(342, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792427/mdbz038vv2_1769418670.jpg', 1, 0),
(342, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792427/mdbz038vv3_1769418670.jpg', 2, 0),
(342, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792427/mdbz038vv4_1769418670.jpg', 3, 0),
(342, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792427/mdbz038bac9255_1769418691.png', 4, 0),
(342, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792427/mdbz038bac9256_1769418690.png', 5, 0),
(343, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792468790/mdbz039bac9251_1769418757.png', 0, 1),
(343, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792468790/mdbz039vv2_1769418756.jpg', 1, 0),
(343, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792468790/mdbz039vv3_1769418756.jpg', 2, 0),
(343, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792468790/mdbz039vv4_1769418756.jpg', 3, 0),
(343, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792468790/mdbz039bac9256_1769418756.png', 4, 0),
(343, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768792468790/mdbz039bac9255_1769418756.png', 5, 0),
(344, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749025957/mdz07722k1_1749030005.png', 0, 1),
(344, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749025957/mdz07722k2_1752309980.jpg', 1, 0),
(344, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749025957/mdz07722k3_1752309980.jpg', 2, 0),
(344, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749025957/mdz07722k4_1752309981.jpg', 3, 0),
(344, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749025957/mdz07722k5_1752309981.png', 4, 0),
(344, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749025957/mdz07722k6_1752309981.png', 5, 0),
(345, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026027/mdz07922k1_1749030105.png', 0, 1),
(345, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026027/mdz07922k2_1752310181.jpg', 1, 0),
(345, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026027/mdz07922k3_1752310181.jpg', 2, 0),
(345, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026027/mdz07922k4_1752310182.jpg', 3, 0),
(345, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026027/mdz07922k5_1752310182.png', 4, 0),
(345, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026027/mdz07922k6_1752310182.png', 5, 0),
(346, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026050/mdz08022k1_1749030155.png', 0, 1),
(346, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026050/mdz08022k2_1752304422.jpg', 1, 0),
(346, 'https://cloud.huythanhjewelry.vn/storage/photos/uploads/mdz08022k3_1752304446.jpg', 2, 0),
(346, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026050/mdz08022k4_1752304450.jpg', 3, 0),
(346, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026050/mdz08022k3_1749030155.png', 4, 0),
(346, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026050/mdz08022k5_1749030155.png', 5, 0),
(347, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026086/mdz08222k1_1749030255.png', 0, 1),
(347, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026086/mdz08222k2_1752306178.jpg', 1, 0),
(347, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026086/mdz08222k3_1752306189.jpg', 2, 0),
(347, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026086/mdz08222k4_1752306204.jpg', 3, 0),
(347, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026086/mdz08222k3_1749030255.png', 4, 0),
(347, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026086/mdz08222k5_1749030255.png', 5, 0),
(348, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026104/mdz08322k1_1749030298.png', 0, 1),
(348, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026104/mdz08322k2_1752306502.jpg', 1, 0),
(348, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026104/mdz08322k3_1752306480.jpg', 2, 0),
(348, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026104/mdz08322k4_1752306490.jpg', 3, 0),
(348, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026104/mdz08322k3_1749030298.png', 4, 0),
(348, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026104/mdz08322k5_1749030298.png', 5, 0),
(349, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026116/mdz08422k1_1749030450.png', 0, 1),
(349, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026116/mdz08422k2_1752310352.jpg', 1, 0),
(349, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026116/mdz08422k3_1752310352.jpg', 2, 0),
(349, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026116/mdz08422k4_1752310352.jpg', 3, 0),
(349, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026116/mdz08422k5_1752310353.png', 4, 0),
(349, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026116/mdz08422k6_1752310353.png', 5, 0),
(350, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026132/mdz08522k1_1749030498.png', 0, 1),
(350, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026132/mdz08522k2_1769671759.jpg', 1, 0),
(350, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026132/mdz08522k3_1769671759.jpg', 2, 0),
(350, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026132/mdz08522k4_1769671759.jpg', 3, 0),
(350, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026132/mdz08522k6_1769671699.png', 4, 0),
(350, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026132/mdz08422k5_1752310976.png', 5, 0),
(351, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026148/mdz08622k5_1752311240.png', 0, 1),
(351, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026148/mdz08622k2_1752311263.jpg', 1, 0),
(351, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026148/mdz08622k3_1752311263.jpg', 2, 0),
(351, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026148/mdz08622k4_1752311263.jpg', 3, 0),
(351, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026148/mdz08622k5_1752311263.png', 4, 0),
(351, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026148/mdz08622k6_1752311263.png', 5, 0),
(352, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026168/mdz08722k1_1749030583.png', 0, 1),
(352, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026168/mdz08722k2_1752311396.jpg', 1, 0),
(352, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026168/mdz08722k3_1752311396.jpg', 2, 0),
(352, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026168/mdz08722k4_1752311396.jpg', 3, 0),
(352, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026168/mdz08722k5_1752311396.png', 4, 0),
(352, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026168/mdz08722k6_1752311397.png', 5, 0),
(353, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026181/mdz08822k1_1749030633.png', 0, 1),
(353, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026181/mdz08822k2_1752311508.jpg', 1, 0),
(353, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026181/mdz08822k3_1752311508.jpg', 2, 0),
(353, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026181/mdz08822k4_1752311508.jpg', 3, 0),
(353, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026181/mdz08822k5_1752311508.png', 4, 0),
(353, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026181/mdz08822k6_1752311508.png', 5, 0),
(354, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026193/mdz08922k1_1749030689.png', 0, 1),
(354, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026193/mdz08922k2_1752311588.jpg', 1, 0),
(354, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026193/mdz08922k3_1752311588.jpg', 2, 0),
(354, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026193/mdz08922k4_1752311588.jpg', 3, 0),
(354, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026193/mdz08922k5_1752311588.png', 4, 0),
(354, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026193/mdz08922k6_1752311588.png', 5, 0),
(355, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026210/mdz09022k1_1749030743.png', 0, 1),
(355, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026210/mdz09022k2_1752311682.jpg', 1, 0),
(355, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026210/mdz09022k3_1752311682.jpg', 2, 0),
(355, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026210/mdz09022k4_1752311682.jpg', 3, 0),
(355, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026210/mdz09022k5_1752311682.png', 4, 0),
(355, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026210/mdz09022k6_1752311683.png', 5, 0),
(356, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026256/mdz09322k1_1749030863.png', 0, 1),
(356, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026256/mdz09322k2_1752312367.jpg', 1, 0),
(356, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026256/mdz09322k3_1752312367.jpg', 2, 0),
(356, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026256/mdz09322k4_1752312367.jpg', 3, 0),
(356, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026256/mdz09322k5_1752312367.png', 4, 0),
(356, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026256/mdz09322k6_1752312367.png', 5, 0),
(357, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026299/mdz09422k1_1749030906.png', 0, 1),
(357, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026299/mdz09422k2_1752312466.jpg', 1, 0),
(357, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026299/mdz09422k3_1752312466.jpg', 2, 0),
(357, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026299/mdz09422k4_1752312466.jpg', 3, 0),
(357, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026299/mdz09422k5_1752312466.png', 4, 0),
(357, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026299/mdz09422k6_1752312466.png', 5, 0),
(358, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026343/mdz09722k1_1749031039.png', 0, 1),
(358, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026343/mdz09722k2_1752312728.jpg', 1, 0),
(358, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026343/mdz09722k3_1752312728.jpg', 2, 0),
(358, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026343/mdz09722k4_1752312728.jpg', 3, 0),
(358, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026343/mdz09722k5_1752312728.png', 4, 0),
(358, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026343/mdz09722k6_1752312728.png', 5, 0),
(359, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715521/mdbkc038vt1-2_1767064486.png', 0, 1),
(359, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715521/mdbkc038vt1_1767064486.png', 1, 0),
(359, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715521/mdbkc038vt2_1767064486.jpg', 2, 0),
(359, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715521/mdbkc038vt3_1767064485.jpg', 3, 0),
(359, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715521/mdbkc038vt4_1767064486.jpg', 4, 0),
(359, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1766715521/mdbkc038vt6_1767064486.png', 5, 0),
(360, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438877/mdmamd810vt1_1752894621.png', 0, 1),
(360, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438877/mdmamd810vt2_1752894632.jpg', 1, 0),
(360, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438877/mdmamd810vt6_1752894681.jpg', 2, 0),
(360, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438877/mdmamd810vt4_1752894642.jpg', 3, 0),
(360, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438877/mdmamd810vt3_1752894691.png', 4, 0),
(360, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1742438877/mdmamd810vt5_1752894699.png', 5, 0),
(361, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438821/mdptb401vv1_1749028514.png', 0, 1),
(361, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438821/mdptb401vv2_1749028514.jpg', 1, 0),
(361, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438821/mdptb401vv6_1749028514.jpg', 2, 0),
(361, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438821/mdptb401vv4_1749028514.jpg', 3, 0),
(361, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438821/mdptb401vv3_1749028514.png', 4, 0),
(361, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1742438821/mdptb401vv5_1749028514.png', 5, 0),
(362, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776762423/mdz115vh1_1776849700.png', 0, 1),
(362, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776762423/mdz115vh2_1776849700.jpg', 1, 0),
(362, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776762423/mdz115vh3_1776849700.jpg', 2, 0),
(362, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776762423/mdz115vh5_1776849700.png', 3, 0),
(362, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776762423/mdz115vh6_1776849700.png', 4, 0),
(362, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776762423/mdz115vh1_1776849708.png', 5, 0),
(363, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1727686468/mdmamd807-vv-1_1730084868.png', 0, 1),
(363, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1727686468/mdmamd807vv10_1752893886.jpg', 1, 0),
(363, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1727686468/mdmamd807vv6_1752893897.jpg', 2, 0),
(363, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1727686468/mdmamd807vv8_1752893908.jpg', 3, 0),
(363, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1727686468/mdmamd807-vv-3_1730084868.png', 4, 0),
(363, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1727686468/mdmamd807-vv-5_1730084868.png', 5, 0),
(364, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1727686509/mdmamd808-vv-1_1730085222.png', 0, 1),
(364, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1727686509/mdmamd808vv10_1752894096.jpg', 1, 0),
(364, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1727686509/mdmamd808vv6_1752894111.jpg', 2, 0),
(364, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1727686509/mdmamd808vv8_1752894120.jpg', 3, 0),
(364, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1727686509/mdmamd808-vv-3_1730085222.png', 4, 0),
(364, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1727686509/mdmamd808-vv-5_1730085222.png', 5, 0),
(365, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998075/mdz117vv1_1777367109.png', 0, 1),
(365, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998075/mdz117vv2_1777367115.jpg', 1, 0),
(365, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998075/mdz117vv3_1777367123.jpg', 2, 0),
(365, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998075/mdz117vv4_1777367123.jpg', 3, 0),
(365, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998075/mdz117vv5_1777367128.png', 4, 0),
(365, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998075/mdz117vv6_1777367132.png', 5, 0),
(366, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998154/mdz120vv1_1777366979.png', 0, 1),
(366, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998154/mdz120vv3_1777366987.jpg', 1, 0),
(366, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998154/mdz120vv4_1777366987.jpg', 2, 0),
(366, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998154/mdz120vv2_1777366987.jpg', 3, 0),
(366, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998154/mdz120vv6_1777366979.png', 4, 0),
(366, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998154/mdz120vv5_1777366979.png', 5, 0),
(367, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998195/mdz121vv1_1777366901.png', 0, 1),
(367, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998195/mdz121vv4_1777366908.jpg', 1, 0),
(367, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998195/mdz121vv2_1777366908.jpg', 2, 0),
(367, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998195/mdz121vv3_1777366908.jpg', 3, 0),
(367, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998195/mdz121vv6_1777366901.png', 4, 0),
(367, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998195/mdz121vv5_1777366901.png', 5, 0),
(368, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998244/mdz122vt1_1777366826.png', 0, 1),
(368, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998244/mdz122vt2_1777366832.jpg', 1, 0),
(368, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998244/mdz122vt4_1777366838.jpg', 2, 0),
(368, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998244/mdz122vt3_1777366838.jpg', 3, 0),
(368, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998244/mdz122vt5_1777366844.png', 4, 0),
(368, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1776998244/mdz122vt6_1777366844.png', 5, 0),
(369, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760089778/mdz103ldiavv11_1760451055.png', 0, 1),
(369, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760089778/mdz103ldiavh2_1760451059.jpg', 1, 0),
(369, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760089778/mdz103ldiavh4_1760451063.jpg', 2, 0),
(369, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760089778/mdz103ldiavh6_1760451071.jpg', 3, 0),
(369, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760089778/mdz103ldiavv3_1760451078.png', 4, 0),
(369, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760089778/mdz103ldiavv5_1760451081.png', 5, 0),
(370, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088870/mdz104ldiavv11_1760450603.png', 0, 1),
(370, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088870/mdz104ldiavt2_1760155063.jpg', 1, 0),
(370, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088870/mdz104ldiavt6_1760155043.jpg', 2, 0),
(370, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088870/mdz104ldiavt4_1760155043.jpg', 3, 0),
(370, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088870/mdz104ldiavv3_1760450631.png', 4, 0),
(370, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1760088870/mdz104ldiavv5_1760450626.png', 5, 0),
(371, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284906/mdmamd7791-1_1735895536.png', 0, 1),
(371, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284906/mdmamd7793_1735895523.jpg', 1, 0),
(371, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284906/mdmamd7792_1735895523.jpg', 2, 0),
(371, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284906/mdmamd7794_1735895523.jpg', 3, 0),
(371, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284906/mdmamd7791_1735895523.jpg', 4, 0),
(371, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284906/mdmamd7791-2_1735895536.png', 5, 0),
(371, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284906/mdmamd7792_1735895536.png', 6, 0),
(372, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284980/mdmamd7801-1_1735895647.png', 0, 1),
(372, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284980/mdmamd7803_1735895639.jpg', 1, 0),
(372, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284980/mdmamd7802_1735895639.jpg', 2, 0),
(372, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284980/mdmamd7804_1735895639.jpg', 3, 0),
(372, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284980/mdmamd7801_1735895639.jpg', 4, 0),
(372, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284980/mdmamd7801-2_1735895647.png', 5, 0),
(372, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1735284980/mdmamd7802_1735895647.png', 6, 0),
(373, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754243/mdmamd6746_1715839928.png', 0, 1),
(373, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754243/mdmamd6741_1715839928.jpg', 1, 0),
(373, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754243/mdmamd6743_1715839928.jpg', 2, 0),
(373, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754243/mdmamd6742_1715839928.jpg', 3, 0),
(373, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754243/mdmamd6747_1715839928.png', 4, 0),
(373, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754243/mdmamd6748_1715839928.png', 5, 0);
INSERT INTO dbo.ProductImages (ProductID, ImageUrl, SortOrder, IsThumbnail) VALUES
(374, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026072/mdz08122k1_1749030193.png', 0, 1),
(374, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026072/mdz08122k3_1752305790.jpg', 1, 0),
(374, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026072/mdz08122k2_1752305800.jpg', 2, 0),
(374, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026072/mdz08122k4_1752305806.jpg', 3, 0),
(374, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026072/mdz08122k3_1749030193.png', 4, 0),
(374, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026072/mdz08122k5_1749030193.png', 5, 0),
(375, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1749026221/mdz09122k1_1749030784.png', 0, 1),
(375, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026221/mdz09122k2_1752311792.jpg', 1, 0),
(375, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026221/mdz09122k3_1752311792.jpg', 2, 0),
(375, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026221/mdz09122k4_1752311792.jpg', 3, 0),
(375, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026221/mdz09122k5_1752311792.png', 4, 0),
(375, 'https://cloud.huythanhjewelry.vn/storage/photos/shares/01upload/1749026221/mdz09122k6_1752311792.png', 5, 0),
(376, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754345/llf1316_1715936414.png', 0, 1),
(376, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754345/llf1313_1715936414.jpg', 1, 0),
(376, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754345/llf1314_1715936414.jpg', 2, 0),
(376, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754345/llf1311_1715936414.jpg', 3, 0),
(376, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754345/llf1316b_1715936414.png', 4, 0),
(376, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754345/llf1316c_1715936414.png', 5, 0),
(376, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754345/llf1316d_1715936414.png', 6, 0),
(377, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754346/llf135-vv-1_1718251597.png', 0, 1),
(377, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754346/llf135-vv-2_1728542586.jpg', 1, 0),
(377, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754346/llf135-vv-4_1728542586.jpg', 2, 0),
(377, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754346/llf135-vv-3-1_1718251597.png', 3, 0),
(377, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754346/llf135-vv-3-2_1718251597.png', 4, 0),
(377, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754346/llf135-vv-3-3_1718251597.png', 5, 0),
(378, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754342/llf1626_1715936246.png', 0, 1),
(378, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754342/llf1621_1715936246.jpg', 1, 0),
(378, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754342/llf1622_1715936246.jpg', 2, 0),
(378, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754342/llf1626b_1715936246.png', 3, 0),
(378, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754342/llf1626c_1715936246.png', 4, 0),
(378, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754342/llf1626d_1715936246.png', 5, 0),
(379, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1747022731/lbz028vt1_1747032237.png', 0, 1),
(379, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1747022731/lbz028vv2_1747032238.jpg', 1, 0),
(379, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1747022731/lbz028vv4_1747032238.jpg', 2, 0),
(379, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1747022731/lbz028vv6_1747032238.jpg', 3, 0),
(379, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1747022731/lbz028vt5_1747032237.png', 4, 0),
(379, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1747022731/lbz028vt3_1747032237.png', 5, 0),
(380, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745895022/lz029vv1_1749031976.png', 0, 1),
(380, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745895022/lz029vv2_1749031976.jpg', 1, 0),
(380, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745895022/lz029vv4_1749031976.jpg', 2, 0),
(380, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745895022/lz029vv6_1749031976.jpg', 3, 0),
(380, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745895022/lz029vv5_1749031976.png', 4, 0),
(380, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745895022/lz029vv3_1749031976.png', 5, 0),
(381, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745894758/vlf56vhvtvv1_1748499785.png', 0, 1),
(381, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745894758/vlf56vv2_1748499785.jpg', 1, 0),
(381, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745894758/vlf56vv6_1748499785.jpg', 2, 0),
(381, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745894758/vlf56vv4_1748499785.jpg', 3, 0),
(381, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745894758/vlf56vhvtvv3_1748499785.png', 4, 0),
(381, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1745894758/vlf56vhvtvv5_1748499785.png', 5, 0),
(382, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2487_1736323275.png', 0, 1),
(382, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2484_1736323265.jpg', 1, 0),
(382, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2483_1736323265.jpg', 2, 0),
(382, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2482_1736323265.jpg', 3, 0),
(382, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2481_1736323265.jpg', 4, 0),
(382, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2486_1736323275.png', 5, 0),
(382, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2488_1736323275.png', 6, 0),
(383, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2487_1736323275.png', 0, 1),
(383, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2484_1736323265.jpg', 1, 0),
(383, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2483_1736323265.jpg', 2, 0),
(383, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2482_1736323265.jpg', 3, 0),
(383, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2481_1736323265.jpg', 4, 0),
(383, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2486_1736323275.png', 5, 0),
(383, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1736309828/llf2488_1736323275.png', 6, 0),
(384, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754399/llf2167_1715674779.png', 0, 1),
(384, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754399/llf2162_1715674768.jpg', 1, 0),
(384, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754399/llf2161_1715674768.jpg', 2, 0),
(384, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754399/llf2164_1715674768.jpg', 3, 0),
(384, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754399/llf2163_1715674768.jpg', 4, 0),
(384, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754399/llf2166_1715674768.png', 5, 0),
(385, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754400/llf2177_1715674876.png', 0, 1),
(385, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754400/llf2173_1715674875.jpg', 1, 0),
(385, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754400/llf2171_1715674875.jpg', 2, 0),
(385, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754400/llf2172_1715674875.jpg', 3, 0),
(385, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754400/llf2174_1715674876.jpg', 4, 0),
(385, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754400/llf2176_1715674875.png', 5, 0),
(386, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754401/llf2187_1715674937.png', 0, 1),
(386, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754401/llf2182_1715674937.jpg', 1, 0),
(386, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754401/llf2183_1715674937.jpg', 2, 0),
(386, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754401/llf2181_1715674937.jpg', 3, 0),
(386, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754401/llf2184_1715674937.jpg', 4, 0),
(386, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754401/llf2186_1715674937.png', 5, 0),
(387, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754402/llf2197_1715675005.png', 0, 1),
(387, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754402/llf2193_1715674995.jpg', 1, 0),
(387, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754402/llf2192_1715674995.jpg', 2, 0),
(387, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754402/llf2194_1715674995.jpg', 3, 0),
(387, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754402/llf2191_1715674995.jpg', 4, 0),
(387, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754402/llf2196_1715674995.png', 5, 0),
(388, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754403/llf2207_1715675087.png', 0, 1),
(388, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754403/llf2202_1715675069.jpg', 1, 0),
(388, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754403/llf2203_1715675069.jpg', 2, 0),
(388, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754403/llf2204_1715675087.jpg', 3, 0),
(388, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754403/llf2201_1715675091.jpg', 4, 0),
(388, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754403/llf2206_1715675069.png', 5, 0),
(389, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754404/llf2217_1715675179.png', 0, 1),
(389, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754404/llf2214_1715675179.jpg', 1, 0),
(389, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754404/llf2213_1715675179.jpg', 2, 0),
(389, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754404/llf2211_1715675179.jpg', 3, 0),
(389, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754404/llf2212_1715675179.jpg', 4, 0),
(389, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754404/llf2216_1715675179.png', 5, 0),
(390, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754405/llf2227_1715675309.png', 0, 1),
(390, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754405/llf2224_1715675309.jpg', 1, 0),
(390, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754405/llf2223_1715675309.jpg', 2, 0),
(390, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754405/llf2222_1715675309.jpg', 3, 0),
(390, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754405/llf2221_1715675309.jpg', 4, 0),
(390, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754405/llf2226_1715675309.png', 5, 0),
(391, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754406/llf2237_1715675441.png', 0, 1),
(391, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754406/llf2233_1715675441.jpg', 1, 0),
(391, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754406/llf2231_1715675441.jpg', 2, 0),
(391, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754406/llf2234_1715675441.jpg', 3, 0),
(391, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754406/llf2232_1715675441.jpg', 4, 0),
(391, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754406/llf2236_1715675441.png', 5, 0),
(392, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754407/llf2247_1715675514.png', 0, 1),
(392, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754407/llf2243_1715675507.jpg', 1, 0),
(392, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754407/llf2241_1715675507.jpg', 2, 0),
(392, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754407/llf2242_1715675507.jpg', 3, 0),
(392, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754407/llf2244_1715675507.jpg', 4, 0),
(392, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754407/llf2246_1715675507.png', 5, 0),
(393, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754410/llf2277_1715675712.png', 0, 1),
(393, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754410/llf2272_1715675712.jpg', 1, 0),
(393, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754410/llf2271_1715675712.jpg', 2, 0),
(393, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754410/llf2274_1715675712.jpg', 3, 0),
(393, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754410/llf2273_1715675712.jpg', 4, 0),
(393, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754410/llf2276_1715675712.png', 5, 0),
(394, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3181_1715826049.png', 0, 1),
(394, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3181_1715826049.jpg', 1, 0),
(394, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3182_1715826049.jpg', 2, 0),
(394, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3183_1715826049.jpg', 3, 0),
(394, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3184_1715826049.jpg', 4, 0),
(394, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3182_1715826049.png', 5, 0),
(395, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3181_1715826049.png', 0, 1),
(395, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3181_1715826049.jpg', 1, 0),
(395, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3182_1715826049.jpg', 2, 0),
(395, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3183_1715826049.jpg', 3, 0),
(395, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3184_1715826049.jpg', 4, 0),
(395, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754444/llf3182_1715826049.png', 5, 0),
(396, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3191_1715826224.png', 0, 1),
(396, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3191_1715826224.jpg', 1, 0),
(396, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3192_1715826224.jpg', 2, 0),
(396, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3194_1715826224.jpg', 3, 0),
(396, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3193_1715826224.jpg', 4, 0),
(396, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3192_1715826224.png', 5, 0),
(397, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3191_1715826224.png', 0, 1),
(397, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3191_1715826224.jpg', 1, 0),
(397, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3192_1715826224.jpg', 2, 0),
(397, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3194_1715826224.jpg', 3, 0),
(397, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3193_1715826224.jpg', 4, 0),
(397, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3192_1715826224.png', 5, 0),
(398, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3191_1715826224.png', 0, 1),
(398, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3191_1715826224.jpg', 1, 0),
(398, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3192_1715826224.jpg', 2, 0),
(398, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3194_1715826224.jpg', 3, 0),
(398, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3193_1715826224.jpg', 4, 0),
(398, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3192_1715826224.png', 5, 0),
(399, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3191_1715826224.png', 0, 1),
(399, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3191_1715826224.jpg', 1, 0),
(399, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3192_1715826224.jpg', 2, 0),
(399, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3194_1715826224.jpg', 3, 0),
(399, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3193_1715826224.jpg', 4, 0),
(399, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754446/llf3192_1715826224.png', 5, 0),
(400, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3201_1715826301.png', 0, 1),
(400, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3201_1715826301.jpg', 1, 0),
(400, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3202_1715826301.jpg', 2, 0),
(400, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3204_1715826301.jpg', 3, 0),
(400, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3203_1715826301.jpg', 4, 0),
(400, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3202_1715826302.png', 5, 0),
(401, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3201_1715826301.png', 0, 1),
(401, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3201_1715826301.jpg', 1, 0),
(401, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3202_1715826301.jpg', 2, 0),
(401, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3204_1715826301.jpg', 3, 0),
(401, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3203_1715826301.jpg', 4, 0),
(401, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3202_1715826302.png', 5, 0),
(402, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3201_1715826301.png', 0, 1),
(402, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3201_1715826301.jpg', 1, 0),
(402, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3202_1715826301.jpg', 2, 0),
(402, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3204_1715826301.jpg', 3, 0),
(402, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3203_1715826301.jpg', 4, 0),
(402, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3202_1715826302.png', 5, 0),
(403, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3201_1715826301.png', 0, 1),
(403, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3201_1715826301.jpg', 1, 0),
(403, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3202_1715826301.jpg', 2, 0),
(403, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3204_1715826301.jpg', 3, 0),
(403, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3203_1715826301.jpg', 4, 0),
(403, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754447/llf3202_1715826302.png', 5, 0),
(404, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3211_1715826148.png', 0, 1),
(404, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3211_1715826148.jpg', 1, 0),
(404, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3212_1715826148.jpg', 2, 0),
(404, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3213_1715826148.jpg', 3, 0),
(404, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3214_1715826148.jpg', 4, 0),
(404, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3212_1715826148.png', 5, 0),
(405, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3211_1715826148.png', 0, 1),
(405, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3211_1715826148.jpg', 1, 0),
(405, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3212_1715826148.jpg', 2, 0),
(405, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3213_1715826148.jpg', 3, 0),
(405, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3214_1715826148.jpg', 4, 0),
(405, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754445/llf3212_1715826148.png', 5, 0),
(406, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754442/llf3221_1715825853.png', 0, 1),
(406, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754442/llf3221_1715825853.jpg', 1, 0),
(406, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754442/llf3222_1715825853.jpg', 2, 0),
(406, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754442/llf3223_1715825853.jpg', 3, 0),
(406, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754442/llf3224_1715825853.jpg', 4, 0),
(406, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754442/llf3222_1715825853.png', 5, 0),
(407, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804428575/cvz01324k1_1768894311.png', 0, 1),
(407, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804428575/cvz01324k2_1768894311.jpg', 1, 0),
(407, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804428575/cvz01324k3_1768894310.jpg', 2, 0),
(407, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804428575/cvz01324k5_1768894311.png', 3, 0),
(407, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804428575/cvz01324k6_1768894311.jpg', 4, 0),
(407, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804428575/cvz01324k7_1768894311.jpg', 5, 0),
(408, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804880550/cvz01424k1_1768895779.png', 0, 1),
(408, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804880550/cvz01424k2_1768895779.jpg', 1, 0),
(408, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804880550/cvz01424k3_1768895779.jpg', 2, 0),
(408, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804880550/cvz01424k5_1768895779.png', 3, 0),
(408, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804880550/cvz01424k6_1768895779.jpg', 4, 0),
(408, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804880550/cvz01424k7_1768895779.jpg', 5, 0),
(409, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804918723/cvz01524k1_1768895883.png', 0, 1),
(409, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804918723/cvz01524k2_1768895883.jpg', 1, 0),
(409, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804918723/cvz01524k3_1768895883.jpg', 2, 0),
(409, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804918723/cvz01524k5_1768895883.png', 3, 0),
(409, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804918723/cvz01524k6_1768895883.jpg', 4, 0),
(409, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804918723/cvz01524k7_1768895883.jpg', 5, 0),
(410, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804946816/cvz01624k1_1768896015.png', 0, 1),
(410, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804946816/cvz01624k2_1768896015.jpg', 1, 0),
(410, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804946816/cvz01624k3_1768896015.jpg', 2, 0),
(410, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804946816/cvz01624k5_1768896015.png', 3, 0),
(410, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804946816/cvz01624k6_1768896015.jpg', 4, 0),
(410, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804946816/cvz01624k7_1768896015.jpg', 5, 0),
(411, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804978418/cvz01724k1_1768896298.png', 0, 1),
(411, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804978418/cvz01724k2_1768896298.jpg', 1, 0),
(411, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804978418/cvz01724k3_1768896298.jpg', 2, 0),
(411, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804978418/cvz01724k5_1768896298.png', 3, 0),
(411, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804978418/cvz01724k6_1768896298.jpg', 4, 0),
(411, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768804978418/cvz01724k7_1768896298.jpg', 5, 0),
(412, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805004618/cvz01824k1_1768896410.png', 0, 1),
(412, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805004618/cvz01824k2_1768896410.jpg', 1, 0),
(412, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805004618/cvz01824k3_1768896410.jpg', 2, 0),
(412, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805004618/cvz01824k5_1768896410.png', 3, 0),
(412, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805004618/cvz01824k6_1768896410.jpg', 4, 0),
(412, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805004618/cvz01824k7_1768896410.jpg', 5, 0),
(413, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805031387/cvz01924k1_1768898034.png', 0, 1),
(413, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805031387/cvz01924k2_1768898035.jpg', 1, 0),
(413, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805031387/cvz01924k3_1768898035.jpg', 2, 0),
(413, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805031387/cvz01924k5_1768898035.png', 3, 0),
(413, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805031387/cvz01924k6_1768898035.jpg', 4, 0),
(413, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805031387/cvz01924k7_1768898035.jpg', 5, 0),
(414, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805179079/cvz02024k1_1768898998.png', 0, 1),
(414, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805179079/cvz02024k2_1768898999.jpg', 1, 0),
(414, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805179079/cvz02024k3_1768898999.jpg', 2, 0),
(414, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805179079/cvz02024k5_1768898998.png', 3, 0),
(414, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805179079/cvz02024k6_1768898998.jpg', 4, 0),
(414, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805179079/cvz02024k7_1768898998.jpg', 5, 0),
(415, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805159566/cvz02124k1_1768899079.png', 0, 1),
(415, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805159566/cvz02124k2_1768899080.jpg', 1, 0),
(415, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805159566/cvz02124k3_1768899080.jpg', 2, 0),
(415, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805159566/cvz02124k5_1768899080.png', 3, 0),
(415, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805159566/cvz02124k6_1768899080.jpg', 4, 0),
(415, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805159566/cvz02124k7_1768899080.jpg', 5, 0),
(416, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805138442/cvz02224k1_1768899135.png', 0, 1),
(416, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805138442/cvz02224k2_1768899142.jpg', 1, 0),
(416, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805138442/cvz02224k3_1768899142.jpg', 2, 0),
(416, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805138442/cvz02224k5_1768899142.png', 3, 0),
(416, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805138442/cvz02224k6_1768899142.jpg', 4, 0),
(416, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805138442/cvz02224k7_1768899142.jpg', 5, 0),
(417, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805104599/cvz02324k1_1768899707.png', 0, 1),
(417, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805104599/cvz02324k2_1768899707.jpg', 1, 0),
(417, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805104599/cvz02324k3_1768899707.jpg', 2, 0),
(417, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805104599/cvz02324k5_1768899707.png', 3, 0),
(417, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805104599/cvz02324k6_1768899707.jpg', 4, 0),
(417, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805104599/cvz02324k7_1768899706.jpg', 5, 0),
(418, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805082804/cvz02424k1_1768899770.png', 0, 1),
(418, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805082804/cvz02424k2_1768899770.jpg', 1, 0),
(418, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805082804/cvz02424k3_1768899770.jpg', 2, 0),
(418, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805082804/cvz02424k5_1768899770.png', 3, 0),
(418, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805082804/cvz02424k6_1768899770.jpg', 4, 0),
(418, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768805082804/cvz02424k7_1768899770.jpg', 5, 0),
(419, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754397/llf21210_1715674585.png', 0, 1),
(419, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754397/llf2122_1715674585.jpg', 1, 0),
(419, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754397/llf2123_1715674585.jpg', 2, 0),
(419, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754397/llf2121_1715674585.jpg', 3, 0),
(419, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754397/llf2124_1715674585.jpg', 4, 0),
(419, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754397/llf2126_1715674585.png', 5, 0),
(420, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754398/llf212b10_1715674691.png', 0, 1),
(420, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754398/llf212b2_1715674691.jpg', 1, 0),
(420, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754398/llf212b3_1715674691.jpg', 2, 0),
(420, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754398/llf212b1_1715674691.jpg', 3, 0),
(420, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754398/llf212b4_1715674691.jpg', 4, 0),
(420, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754398/llf212b6_1715674691.png', 5, 0),
(421, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2437_1715675780.png', 0, 1),
(421, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2432_1715675780.jpg', 1, 0),
(421, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2433_1715675780.jpg', 2, 0),
(421, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2431_1715675780.jpg', 3, 0),
(421, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2436_1715675780.png', 4, 0),
(421, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2438_1715675780.jpg', 5, 0),
(422, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2437_1715675780.png', 0, 1),
(422, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2432_1715675780.jpg', 1, 0),
(422, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2433_1715675780.jpg', 2, 0),
(422, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2431_1715675780.jpg', 3, 0),
(422, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2436_1715675780.png', 4, 0),
(422, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2438_1715675780.jpg', 5, 0),
(423, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2437_1715675780.png', 0, 1),
(423, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2432_1715675780.jpg', 1, 0),
(423, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2433_1715675780.jpg', 2, 0),
(423, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2431_1715675780.jpg', 3, 0),
(423, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2436_1715675780.png', 4, 0),
(423, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754411/llf2438_1715675780.jpg', 5, 0),
(424, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2506_1715675836.png', 0, 1),
(424, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2502_1715675836.jpg', 1, 0),
(424, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2503_1715675836.jpg', 2, 0),
(424, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2504_1715675836.jpg', 3, 0),
(424, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2501_1715675836.jpg', 4, 0),
(424, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2507_1715675836.png', 5, 0),
(425, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2506_1715675836.png', 0, 1),
(425, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2502_1715675836.jpg', 1, 0),
(425, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2503_1715675836.jpg', 2, 0),
(425, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2504_1715675836.jpg', 3, 0),
(425, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2501_1715675836.jpg', 4, 0),
(425, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754412/llf2507_1715675836.png', 5, 0),
(426, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754413/llf2558_1715675920.png', 0, 1),
(426, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754413/llf2551_1715675920.jpg', 1, 0),
(426, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754413/llf2553_1715675920.jpg', 2, 0),
(426, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754413/llf2552_1715675920.jpg', 3, 0),
(426, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754413/llf2554_1715675920.jpg', 4, 0),
(426, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754413/llf2557_1715675920.png', 5, 0),
(427, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754416/llf2716_1715676297.png', 0, 1),
(427, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754416/llf271-llf276-llf2772_1715676297.jpg', 1, 0),
(427, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754416/llf271-llf276-llf2773_1715676297.jpg', 2, 0),
(427, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754416/llf271-llf278-llf282-llf2731_1715676296.jpg', 3, 0),
(427, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754416/llf271-llf278-llf282-llf2732_1715676297.jpg', 4, 0),
(427, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754416/llf271-llf278-llf282-llf2733_1715676297.jpg', 5, 0),
(427, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754416/llf271-llf276-llf2771_1715676296.jpg', 6, 0),
(428, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754420/llf2756_1715676881.png', 0, 1),
(428, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754420/llf280-llf272-llf2752_1715676881.jpg', 1, 0),
(428, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754420/llf280-llf272-llf2751_1715676881.jpg', 2, 0),
(428, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754420/llf280-llf272-llf2753_1715676881.jpg', 3, 0),
(428, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754420/llf280-llf284-llf2751_1715676881.jpg', 4, 0),
(428, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754420/llf280-llf284-llf2752_1715676881.jpg', 5, 0),
(428, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713754420/llf280-llf284-llf2753_1715676881.jpg', 6, 0),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/1_1790905045.jpg', 0, 1),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/llf333_1790904831.jpg', 1, 0),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/lz051vv2_1790652328.jpg', 2, 0),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/lz051vv3_1790652328.jpg', 3, 0),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/llf333-vv-1_1790652347.png', 4, 0),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/llf333-vv-2_1790652351.jpg', 5, 0),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/llf333-vv-3_1790652355.png', 6, 0),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/llf333-vv-4_1790652355.jpg', 7, 0),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/llf333-vv-5_1790652355.png', 8, 0),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/lz051vv5_1790652322.png', 9, 0),
(429, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589136/lz051vv1_1790652323.png', 10, 0),
(430, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713854115/ptb353-vv-1_1716535438.png', 0, 1),
(430, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713854115/lptb3533_1716535617.jpg', 1, 0),
(430, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713854115/mdptb3531_1716535593.jpg', 2, 0),
(430, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713854115/lptb3531_1716535617.jpg', 3, 0),
(430, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713854115/btptb3531_1716259874.jpg', 4, 0),
(430, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713854115/btptb3538_1716535571.jpg', 5, 0),
(431, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589275/2_1790905087.jpg', 0, 1),
(431, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589275/btz020vv4_1790651949.jpg', 1, 0),
(431, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589275/btz020vv2_1790651956.jpg', 2, 0),
(431, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589275/btz020vv3_1790651956.png', 3, 0),
(431, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589275/btz020vv6_1790651962.jpg', 4, 0),
(431, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589275/dcmamd826vv1_1790651983.png', 5, 0),
(431, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589275/dcmamd826vv2_1790651983.jpg', 6, 0),
(431, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589275/dcmamd826vv5_1790651983.png', 7, 0),
(431, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589275/dcmamd826vv6_1790651983.png', 8, 0),
(431, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1790589275/btz020vv1_1790651956.png', 9, 0),
(432, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853935/btcc86_1716540404.png', 0, 1),
(432, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853935/dcbtcc863_1715912682.jpg', 1, 0),
(432, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853935/btbtcc863_1715912662.jpg', 2, 0),
(432, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853935/dcbtcc862_1715912682.jpg', 3, 0),
(432, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853935/btbtcc862_1715912662.jpg', 4, 0),
(432, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853935/btbtcc864_1715912662.jpg', 5, 0),
(433, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853936/btcc88_1716540667.png', 0, 1),
(433, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853936/dcbtcc881_1715912457.jpg', 1, 0),
(433, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853936/btbtcc882_1715912457.jpg', 2, 0),
(433, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853936/dcbtcc882_1715912457.jpg', 3, 0),
(433, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853936/btbtcc883_1715912457.jpg', 4, 0),
(433, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853936/dcbtcc883_1715912457.jpg', 5, 0),
(434, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853937/btcc90-vv-1_1715908706.png', 0, 1),
(434, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853937/dcbtcc90-vv-2_1715908895.jpg', 1, 0),
(434, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853937/dcbtcc90-vv-4_1715908895.jpg', 2, 0),
(434, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853937/btbtcc90-vv-3_1715912152.jpg', 3, 0),
(434, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853937/btbtcc90-vv-2_1715912152.jpg', 4, 0),
(434, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853937/nbtcc90-vv-2_1715912173.jpg', 5, 0),
(434, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853937/nbtcc90-vv-4_1715912173.jpg', 6, 0),
(435, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853938/btcc91-vv-1_1715910285.png', 0, 1),
(435, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853938/dcbtcc91-vv-2_1715910313.jpg', 1, 0),
(435, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853938/dcbtcc91-vv-4_1715910313.jpg', 2, 0),
(435, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853938/btbtcc91-vv-3_1715910328.jpg', 3, 0),
(435, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853938/btbtcc91-vv-2_1715910328.jpg', 4, 0),
(435, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853938/nbtcc91-vv-2_1715910414.jpg', 5, 0),
(435, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1713853938/nbtcc91-vv-4_1715910414.jpg', 6, 0),
(436, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201138/lnpsmeothantai24k1_1768214778.jpg', 0, 1),
(436, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201138/lnpsmeothantai24k2_1768295408.jpg', 1, 0),
(436, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201138/lnpsmeothantai24k3_1768295411.jpg', 2, 0),
(436, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201138/lnpsmeothantai24k4-2_1768295430.png', 3, 0),
(436, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201138/lnpsmeothantai24k7-1_1768295443.jpg', 4, 0),
(436, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201138/lnpsmeothantai24k8_1768295454.jpg', 5, 0),
(436, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201138/lnpsmeothantai24k9_1768295458.jpg', 6, 0),
(436, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201138/lnpsmeothantai24k10_1768295450.jpg', 7, 0),
(437, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201116/lnpsngua124k1_1768294706.jpg', 0, 1),
(437, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201116/lnpsngua124k2_1768294701.jpg', 1, 0),
(437, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201116/lnpsngua124k3_1768294715.jpg', 2, 0),
(437, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201116/lnpsngua124k4_1768294763.png', 3, 0),
(437, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201116/lnpsngua124k7_1768294747.jpg', 4, 0),
(437, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201116/lnpsngua124k8_1768294736.jpg', 5, 0),
(437, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201116/lnpsngua124k9_1768294736.jpg', 6, 0),
(437, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201116/lnpsngua124k10_1768294736.jpg', 7, 0),
(438, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201221/lnpsngua224k1_1768294925.jpg', 0, 1),
(438, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201221/lnpsngua224k2_1768294925.jpg', 1, 0),
(438, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201221/lnpsngua224k3_1768294933.jpg', 2, 0),
(438, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201221/lnpsngua224k4_1768294944.png', 3, 0),
(438, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201221/lnpsngua224k7_1768294952.jpg', 4, 0),
(438, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201221/lnpsngua224k8_1768294952.jpg', 5, 0),
(438, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201221/lnpsngua224k9_1768294952.jpg', 6, 0),
(438, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201221/lnpsngua224k10_1768294952.jpg', 7, 0),
(439, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201079/lnpsphat24k1_1768295072.jpg', 0, 1),
(439, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201079/lnpsphat24k2_1768295071.jpg', 1, 0),
(439, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201079/lnpsphat24k3_1768295072.jpg', 2, 0),
(439, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201079/lnpsphat24k8_1768295099.jpg', 3, 0),
(439, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201079/lnpsphat24k7_1768295099.jpg', 4, 0),
(439, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201079/lnpsphat24k9_1768295099.jpg', 5, 0),
(439, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201079/lnpsphat24k10_1768295105.jpg', 6, 0),
(440, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201166/lnpstyhuu24k1_1768295225.jpg', 0, 1),
(440, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201166/lnpstyhuu24k2_1768295225.jpg', 1, 0),
(440, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201166/lnpstyhuu24k3_1768295233.jpg', 2, 0),
(440, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201166/lnpstyhuu24k4_1768295238.png', 3, 0),
(440, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201166/lnpstyhuu24k8_1768295248.jpg', 4, 0),
(440, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201166/lnpstyhuu24k7_1768295248.jpg', 5, 0),
(440, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201166/lnpstyhuu24k8_1768295261.jpg', 6, 0),
(440, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201166/lnpstyhuu24k9_1768295261.jpg', 7, 0),
(440, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201166/lnpstyhuu24k10_1768295261.jpg', 8, 0),
(441, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201018/binhngokimchibao24k4_1769058054.png', 0, 1),
(441, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201018/binhngokimchibao24k3_1769058036.png', 1, 0),
(441, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201018/binhngokimchibao24k1_1769058053.png', 2, 0),
(441, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201018/binhngokimchibao24k2_1769058037.png', 3, 0),
(441, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201018/binhngokimchibao24k5_1769058054.png', 4, 0),
(441, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768201018/binhngokimchibao24k6_1769058054.jpg', 5, 0),
(442, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1767164150197/binhngophat24k5_1769162837.png', 0, 1),
(442, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1767164150197/binhngophat24k3_1769162837.jpg', 1, 0),
(442, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1767164150197/binhngophat24k2_1769162837.jpg', 2, 0),
(442, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1767164150197/binhngophat24k4_1769162836.jpg', 3, 0),
(442, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1767164150197/binhngophat24k6_1769162836.png', 4, 0),
(442, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1767164150197/binhngophat24k1_1769162837.png', 5, 0),
(442, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1767164150197/binhngophat24k7_1769162836.jpg', 6, 0),
(443, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768200909/lnphucloccat24k1_1768294223.png', 0, 1),
(443, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768200909/lnphucloccat24k2_1768294230.png', 1, 0),
(443, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768200909/lnphucloccat24k3_1768294230.jpg', 2, 0),
(443, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768200909/lnphucloccat24k4_1768294230.jpg', 3, 0),
(443, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768200909/lnphucloccat24k5_1768294254.png', 4, 0),
(443, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768200909/lnphucloccat24k6_1768294244.jpg', 5, 0),
(443, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768200909/lnphucloccat24k7_1768294244.jpg', 6, 0),
(443, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768200909/lnphucloccat24k12_1768294244.jpg', 7, 0),
(443, 'https://cdn.huythanhjewelry.vn/storage/photos/shares/01upload/1768200909/lnphucloccat24k13_1768294244.jpg', 8, 0);
GO

-- 5.9. Thông tin đá (282 dòng, loại đá suy ra từ tên sản phẩm)
INSERT INTO dbo.ProductStones (ProductID, StoneType, StoneName, SizeMm, Quantity, IsMainStone) VALUES
(1, 'LabDiamond', NULL, '1.25', 14, 0),
(2, 'LabDiamond', NULL, '0.9', 16, 0),
(3, 'LabDiamond', NULL, '1.0', 2, 0),
(4, 'LabDiamond', NULL, '1.1', 20, 0),
(5, 'LabDiamond', NULL, '1.5', 16, 0),
(6, 'LabDiamond', NULL, '3.6', 1, 1),
(7, 'LabDiamond', NULL, '5.0', 1, 1),
(8, 'LabDiamond', NULL, '5.0', 1, 1),
(9, 'LabDiamond', NULL, '0.9', 4, 0),
(10, 'LabDiamond', NULL, '1.0', 12, 0),
(11, 'LabDiamond', NULL, '4.0', 1, 1),
(12, 'LabDiamond', NULL, '0.9', 16, 0),
(13, 'LabDiamond', NULL, '4.0', 1, 1),
(14, 'LabDiamond', NULL, '0.9', 36, 0),
(15, 'LabDiamond', NULL, '5.0', 1, 1),
(16, 'LabDiamond', NULL, '4.5', 1, 1),
(17, 'LabDiamond', NULL, '3.9', 1, 1),
(18, 'LabDiamond', NULL, '0.9', 2, 0),
(19, 'LabDiamond', NULL, '0.9', 22, 0),
(20, 'LabDiamond', NULL, '1.25', 10, 0),
(21, 'LabDiamond', NULL, '0.9', 12, 0),
(22, 'LabDiamond', NULL, '0.9', 16, 0),
(23, 'LabDiamond', NULL, '1.25', 26, 0),
(24, 'LabDiamond', NULL, '1.1', 6, 0),
(25, 'LabDiamond', NULL, '1.5', 16, 0),
(26, 'LabDiamond', NULL, '1.0', 12, 0),
(27, 'LabDiamond', NULL, '1.5', 12, 0),
(28, 'LabDiamond', NULL, '1.0', 8, 0),
(29, 'LabDiamond', NULL, '0.9', 12, 0),
(30, 'LabDiamond', NULL, '0.9', 40, 0),
(31, 'LabDiamond', NULL, '1.25', 23, 0),
(32, 'LabDiamond', NULL, '1.25', 8, 0),
(33, 'LabDiamond', NULL, '0.8', 8, 0),
(34, 'LabDiamond', NULL, '0.9', 2, 0),
(35, 'LabDiamond', NULL, '0.9', 13, 0),
(36, 'LabDiamond', NULL, '1.25', 33, 0),
(37, 'LabDiamond', NULL, '1.25', 15, 0),
(38, 'LabDiamond', NULL, '7x11', 1, 1),
(39, 'LabDiamond', NULL, '7x10', 1, 1),
(40, 'LabDiamond', NULL, '7x7', 1, 1),
(41, 'LabDiamond', NULL, '6.5x8.5', 1, 1),
(42, 'LabDiamond', NULL, '7x11', 1, 1),
(51, 'LabDiamond', NULL, '6.0', 1, 1),
(52, 'LabDiamond', NULL, '1.5', 2, 0),
(53, 'LabDiamond', NULL, '1.5', 10, 0),
(54, 'LabDiamond', NULL, '2.0', 8, 0),
(55, 'LabDiamond', NULL, '1.1', 2, 0),
(56, 'LabDiamond', NULL, '1.5', 2, 0),
(57, 'LabDiamond', NULL, '1.1', 42, 0),
(58, 'LabDiamond', NULL, '1.5', 2, 0),
(59, 'LabDiamond', NULL, '1.5', 6, 0),
(60, 'LabDiamond', NULL, '1.25', 2, 0),
(61, 'LabDiamond', NULL, '1.5', 8, 0),
(62, 'LabDiamond', NULL, '1.1', 16, 0),
(63, 'LabDiamond', NULL, '1.25', 16, 0),
(64, 'LabDiamond', NULL, '6.0', 1, 1),
(65, 'LabDiamond', NULL, '6.0', 1, 1),
(66, 'LabDiamond', NULL, '6.0', 1, 1),
(67, 'LabDiamond', NULL, '6.0', 1, 1),
(68, 'LabDiamond', NULL, '6.0', 1, 1),
(69, 'LabDiamond', NULL, '6.0', 1, 1),
(70, 'LabDiamond', NULL, '1.25', 2, 0),
(71, 'LabDiamond', NULL, '1.25', 2, 0),
(72, 'LabDiamond', NULL, '6.0', 1, 1),
(73, 'LabDiamond', NULL, '1.25', 2, 0),
(74, 'LabDiamond', NULL, '1.25', 2, 0),
(75, 'LabDiamond', NULL, '1.1', 18, 0),
(76, 'LabDiamond', NULL, '1.1', 22, 0),
(77, 'CZ', NULL, '5.0', 1, 1),
(78, 'CZ', NULL, '4.0', 1, 1),
(79, 'CZ', NULL, '5.5', 1, 1),
(80, 'CZ', NULL, '5.0', 1, 1),
(82, 'CZ', NULL, '6.0', 1, 1),
(84, 'CZ', NULL, '5.0', 1, 1),
(85, 'CZ', NULL, '5.0', 1, 1),
(86, 'CZ', NULL, '5.0', 1, 1),
(87, 'CZ', NULL, '5.0', 1, 1),
(88, 'CZ', NULL, '5.0', 1, 1),
(89, 'CZ', NULL, '5.0', 1, 1),
(90, 'CZ', NULL, '5.0', 1, 1),
(91, 'CZ', NULL, '2.25', 1, 1),
(92, 'CZ', NULL, '4.5', 1, 1),
(93, 'CZ', NULL, '4.5', 1, 1),
(94, 'CZ', NULL, '4.5', 1, 1),
(95, 'CZ', NULL, '5.0', 1, 1),
(96, 'CZ', NULL, '4.0', 1, 1),
(97, 'CZ', NULL, '5.0', 1, 1),
(98, 'CZ', NULL, '4.5', 1, 1),
(99, 'Moissanite', NULL, '5.0', 1, 1),
(100, 'Moissanite', NULL, '5.0', 1, 1),
(101, 'Moissanite', NULL, '5.0', 1, 1),
(102, 'Moissanite', NULL, '6.0', 1, 1),
(103, 'Moissanite', NULL, '1.5', 2, 0),
(104, 'Moissanite', NULL, '6.5', 1, 1),
(105, 'Moissanite', NULL, '5.0', 1, 1),
(106, 'Moissanite', NULL, '5.0', 1, 1),
(107, 'Moissanite', NULL, '5.0', 1, 1),
(108, 'Moissanite', NULL, '5.0', 1, 1),
(109, 'Moissanite', NULL, '1.0', 20, 0),
(110, 'Moissanite', NULL, '5.0', 1, 1),
(111, 'Moissanite', NULL, '1.1', 14, 0),
(112, 'Moissanite', NULL, '5.0', 1, 1),
(113, 'Moissanite', NULL, '5.0', 1, 1),
(123, 'NaturalDiamond', NULL, '3.0', 1, 1),
(124, 'NaturalDiamond', NULL, '3.0', 1, 1),
(125, 'NaturalDiamond', NULL, '4.5', 1, 1),
(126, 'NaturalDiamond', NULL, '4.5', 1, 1),
(127, 'NaturalDiamond', NULL, '3.5', 1, 1),
(128, 'NaturalDiamond', NULL, '3.0', 1, 1),
(129, 'NaturalDiamond', NULL, '4.5', 1, 1),
(130, 'NaturalDiamond', NULL, '3.5', 1, 1),
(131, 'NaturalDiamond', NULL, '1.0', 2, 0),
(132, 'NaturalDiamond', NULL, '1.0', 2, 0),
(133, 'NaturalDiamond', NULL, '4.5', 1, 1),
(134, 'NaturalDiamond', NULL, '5.0', 1, 1),
(135, 'NaturalDiamond', NULL, '4.0', 1, 1),
(136, 'NaturalDiamond', NULL, '1.0', 3, 0),
(137, 'NaturalDiamond', NULL, NULL, 1, 1),
(138, 'NaturalDiamond', NULL, '4.0', 1, 1),
(139, 'LabDiamond', NULL, '0.7', 2, 0),
(140, 'LabDiamond', NULL, '0.7', 35, 0),
(150, 'CZ', NULL, '2.5', 1, 1),
(151, 'CZ', NULL, '2.75', 1, 1),
(152, 'CZ', NULL, '2.75', 1, 1),
(155, 'CZ', NULL, '3.5', 1, 1),
(157, 'CZ', NULL, '1.25', 1, 1),
(158, 'CZ', NULL, '2.0', 1, 1),
(159, 'CZ', NULL, '3.5', 1, 1),
(160, 'CZ', NULL, '2.75', 1, 1),
(161, 'CZ', NULL, '1.0', 23, 0),
(164, 'CZ', NULL, '2.25', 1, 1),
(173, 'CZ', NULL, '1.0', 9, 0),
(174, 'CZ', NULL, '1.0', 4, 0),
(175, 'CZ', NULL, '1.2', 4, 0),
(176, 'CZ', NULL, '1.0', 1, 1),
(177, 'CZ', NULL, '1.0', 7, 0),
(178, 'CZ', NULL, '1.5', 17, 0),
(179, 'CZ', NULL, '2.5', 22, 0),
(180, 'CZ', NULL, '2.5', 24, 0),
(181, 'CZ', NULL, '1.5', 6, 0),
(182, 'CZ', NULL, '2.0', 5, 0),
(183, 'CZ', NULL, '1.75', 17, 0),
(184, 'CZ', NULL, '2.5x3.5', 23, 0),
(185, 'CZ', NULL, '3.0', 9, 0),
(186, 'CZ', NULL, '1.0', 6, 0),
(187, 'CZ', NULL, '1.5', 21, 0),
(188, 'CZ', NULL, '1.25', 3, 0),
(189, 'CZ', NULL, '1.25', 7, 0),
(190, 'CZ', NULL, '1.25', 5, 0),
(191, 'CZ', NULL, '0.9', 1, 1),
(192, 'CZ', NULL, '1.1', 18, 0),
(193, 'CZ', NULL, '5.5', 1, 1),
(194, 'CZ', NULL, '2.0', 14, 0),
(195, 'Pearl', N'Ngọc trai', '8.0', 1, 1),
(196, 'Pearl', N'Ngọc trai', '8.0', 1, 1),
(197, 'Pearl', N'Ngọc trai', '1.1', 2, 0),
(198, 'MotherOfPearl', N'Xà cừ', '1.1', 4, 0),
(199, 'CZ', NULL, '0.9', 8, 0),
(201, 'CZ', NULL, '1.25', 24, 0),
(202, 'CZ', NULL, '1.5', 32, 0),
(203, 'CZ', NULL, '1.1', 36, 0),
(204, 'CZ', NULL, '1.25', 26, 0),
(205, 'CZ', NULL, '4.0', 2, 0),
(206, 'CZ', NULL, '1.3', 30, 0),
(207, 'CZ', NULL, '1.5', 18, 0),
(208, 'CZ', NULL, '1.0', 56, 0),
(209, 'CZ', NULL, '1.25', 6, 0),
(210, 'CZ', NULL, '2.0', 16, 0),
(211, 'CZ', NULL, '4.0', 2, 0),
(212, 'CZ', NULL, '2.0', 2, 0),
(213, 'CZ', NULL, '2.25', 8, 0),
(214, 'CZ', NULL, '1.0', 20, 0),
(215, 'CZ', NULL, '2.5x5', 2, 0),
(227, 'Other', NULL, '1.1', 2, 0),
(229, 'Other', NULL, '1.0', 2, 0),
(231, 'Other', NULL, '1.1', 2, 0),
(232, 'Other', NULL, '1.0', 12, 0),
(234, 'Other', NULL, '1.1', 6, 0),
(237, 'Other', NULL, '2.5', 2, 0),
(238, 'Other', NULL, '1.0', 4, 0),
(239, 'Other', NULL, '1.0', 8, 0),
(240, 'Other', NULL, '1.0', 12, 0),
(241, 'Other', NULL, '1.0', 6, 0),
(243, 'Pearl', N'Ngọc trai', '2.0', 2, 0),
(244, 'Pearl', N'Ngọc trai', '6.2', 2, 0),
(245, 'Pearl', N'Ngọc trai', '6.2', 2, 0),
(246, 'Pearl', N'Ngọc trai', '8.2', 2, 0),
(247, 'Pearl', N'Ngọc trai', '2.5', 2, 0),
(249, 'Pearl', N'Ngọc trai', '4.5', 1, 1),
(250, 'Gemstone', N'Đá màu', '2.0', 2, 0),
(251, 'Gemstone', N'Đá màu', '1.5', 2, 0),
(252, 'Gemstone', N'Đá màu', '1.5', 2, 0),
(253, 'Gemstone', N'Đá màu', '1.5', 2, 0),
(255, 'CZ', NULL, '3x4', 1, 1),
(256, 'Gemstone', N'Đá màu', '1.0', 30, 0),
(257, 'Gemstone', N'Đá màu', '0.9', 24, 0),
(258, 'Gemstone', N'Đá màu', '1.5x3', 4, 0),
(259, 'Gemstone', N'Đá màu', '1.5', 8, 0),
(260, 'Gemstone', N'Đá màu', '1.1', 16, 0),
(261, 'Gemstone', N'Đá màu', '1.3', 2, 0),
(262, 'Gemstone', N'Đá màu', '1.1', 8, 0),
(263, 'Gemstone', N'Đá màu', '1.8', 8, 0),
(264, 'Gemstone', N'Đá màu', '10x10', 2, 0),
(265, 'Gemstone', N'Đá màu', '10x10', 2, 0),
(266, 'Gemstone', N'Đá màu', '3.0', 1, 1),
(267, 'MotherOfPearl', N'Xà cừ', '1.25', 2, 0),
(269, 'MotherOfPearl', N'Xà cừ', '10x10', 2, 0),
(271, 'CZ', NULL, '1.5', 1, 1),
(272, 'CZ', NULL, '1.1', 6, 0),
(273, 'CZ', NULL, '3.5', 1, 1),
(274, 'CZ', NULL, '2.25', 6, 0),
(275, 'CZ', NULL, '1.75', 1, 1),
(277, 'CZ', NULL, '1.25', 1, 1),
(288, 'Other', NULL, '1.0', 1, 1),
(290, 'Other', NULL, '1.0', 3, 0),
(291, 'Pearl', N'Ngọc trai', '7.0', 1, 1),
(292, 'Pearl', N'Ngọc trai', '2.5', 1, 1),
(293, 'Pearl', N'Ngọc trai', '7.1', 1, 1),
(294, 'Pearl', N'Ngọc trai', '8.2', 1, 1),
(295, 'Pearl', N'Ngọc trai', '4.5', 1, 1),
(296, 'Pearl', N'Ngọc trai', '3.5', 1, 1),
(297, 'Gemstone', N'Đá màu', '2.25', 1, 1),
(298, 'Gemstone', N'Đá màu', '2.25', 1, 1),
(299, 'CZ', NULL, '1.2', 2, 0),
(300, 'Gemstone', N'Đá màu', '2.5', 1, 1),
(304, 'CZ', NULL, '1.0', 10, 0),
(309, 'MotherOfPearl', N'Xà cừ', '10', 1, 1),
(311, 'MotherOfPearl', N'Xà cừ', '8x8', 1, 1),
(312, 'Gemstone', N'Malachite', '10x10x2.2', 1, 1),
(313, 'LabDiamond', NULL, '1.1', 2, 0),
(314, 'Pearl', N'Ngọc trai', '2.5x5', 1, 1),
(315, 'CZ', NULL, '1.5', 2, 0),
(316, 'CZ', NULL, '1.0', 20, 0),
(317, 'CZ', NULL, '3.0', 1, 1),
(318, 'CZ', NULL, '1.25', 20, 0),
(319, 'CZ', NULL, '2.5', 1, 1),
(320, 'CZ', NULL, '1.0', 18, 0),
(321, 'CZ', NULL, '0.9', 2, 0),
(322, 'Gemstone', N'Ruby', '2.0', 3, 0),
(323, 'Gemstone', N'Sapphire', '2.0', 3, 0),
(324, 'Gemstone', N'Sapphire', '2.0', 3, 0),
(325, 'CZ', NULL, '0.9', 70, 0),
(326, 'Gemstone', N'Sapphire', '2.0', 9, 0),
(327, 'Gemstone', N'Sapphire', '2.0', 9, 0),
(328, 'Gemstone', N'Sapphire', '2.0', 9, 0),
(329, 'Gemstone', N'Sapphire', '2.0', 9, 0),
(330, 'Gemstone', N'Tsavorite', '2.0', 9, 0),
(331, 'Gemstone', N'Ruby', '2.0', 9, 0),
(332, 'CZ', NULL, '1.1', 3, 0),
(333, 'CZ', NULL, '1.5', 8, 0),
(334, 'CZ', NULL, '5.5', 1, 1),
(335, 'CZ', NULL, '3x5', 6, 0),
(336, 'CZ', NULL, '2.5', 1, 1),
(359, 'Gemstone', N'Đá màu', '1.5', 1, 1),
(362, 'MotherOfPearl', N'Xà cừ', '9x15', 1, 1),
(365, 'Gemstone', N'Mã não', '16x16x2.0', 1, 1),
(367, 'Gemstone', N'Chalcedony', '13x13', 1, 1),
(368, 'Gemstone', N'Lapis Lazuli', '10x10', 1, 1),
(369, 'LabDiamond', NULL, '2.0', 1, 1),
(370, 'LabDiamond', NULL, '0.9', 2, 0),
(371, 'MotherOfPearl', N'Xà cừ', NULL, 1, 1),
(372, 'MotherOfPearl', N'Xà cừ', '13x13', 1, 1),
(373, 'Moissanite', NULL, '1.2', 2, 0),
(376, 'CZ', NULL, '1.5', 1, 1),
(377, 'CZ', NULL, '0.9', 13, 0),
(378, 'CZ', NULL, '1.1', 29, 0),
(396, 'CZ', NULL, '1.1', 6, 0),
(397, 'CZ', NULL, '1.1', 6, 0),
(398, 'CZ', NULL, '1.1', 6, 0),
(399, 'CZ', NULL, '1.1', 6, 0),
(400, 'CZ', NULL, '1.25', 18, 0),
(401, 'CZ', NULL, '1.25', 18, 0),
(402, 'CZ', NULL, '1.25', 18, 0),
(403, 'CZ', NULL, '1.25', 18, 0),
(404, 'CZ', NULL, '1.0', 36, 0),
(405, 'CZ', NULL, '1.0', 36, 0),
(406, 'CZ', NULL, '1.0', 30, 0),
(424, 'Other', NULL, '1.25', 4, 0),
(425, 'CZ', NULL, '1.25', 4, 0),
(426, 'Other', NULL, '0.9', 14, 0),
(427, 'CZ', NULL, '1.0', 1, 1),
(428, 'CZ', NULL, '0.9', 3, 0);
GO

-- 5.10. Sinh biến thể bán hàng: màu vàng x size nhẫn (size 6–20) cho nhẫn; theo màu cho sản phẩm khác.
--       Số lượng tồn là số MINH HỌA (dữ liệu crawl chỉ có trạng thái còn hàng).
-- Dùng biến bảng (theo collation của CSDL) thay cho bảng tạm #temp (theo collation của tempdb)
DECLARE @ProductColors TABLE (ProductID INT NOT NULL, GoldColor NVARCHAR(20) NULL, ColorCode VARCHAR(5) NOT NULL);
INSERT INTO @ProductColors (ProductID, GoldColor, ColorCode) VALUES
(1, N'Vàng Trắng', 'VT'),
(2, N'Vàng Trắng', 'VT'),
(3, N'Vàng Trắng', 'VT'),
(4, N'Vàng Trắng', 'VT'),
(4, N'Vàng Vàng', 'VV'),
(5, N'Vàng Trắng', 'VT'),
(6, N'Vàng Trắng', 'VT'),
(7, N'Vàng Trắng', 'VT'),
(8, N'Vàng Trắng', 'VT'),
(9, N'Vàng Trắng', 'VT'),
(10, N'Vàng Trắng', 'VT'),
(11, N'Vàng Trắng', 'VT'),
(12, N'Vàng Trắng', 'VT'),
(13, N'Vàng Trắng', 'VT'),
(14, N'Vàng Trắng', 'VT'),
(15, N'Vàng Trắng', 'VT'),
(16, N'Vàng Trắng', 'VT'),
(17, N'Vàng Trắng', 'VT'),
(18, N'Vàng Trắng', 'VT'),
(19, N'Vàng Trắng', 'VT'),
(20, N'Vàng Trắng', 'VT'),
(21, N'Vàng Trắng', 'VT'),
(22, N'Vàng Trắng', 'VT'),
(23, N'Vàng Trắng', 'VT'),
(24, N'Vàng Trắng', 'VT'),
(25, N'Vàng Trắng', 'VT'),
(26, N'Vàng Trắng', 'VT'),
(27, N'Vàng Trắng', 'VT'),
(28, N'Vàng Trắng', 'VT'),
(29, N'Vàng Trắng', 'VT'),
(30, N'Vàng Trắng', 'VT'),
(31, N'Vàng Trắng', 'VT'),
(32, N'Vàng Trắng', 'VT'),
(33, N'Vàng Trắng', 'VT'),
(34, N'Vàng Trắng', 'VT'),
(35, N'Vàng Trắng', 'VT'),
(36, N'Vàng Trắng', 'VT'),
(37, N'Vàng Trắng', 'VT'),
(38, N'Vàng Trắng', 'VT'),
(39, N'Vàng Trắng', 'VT'),
(40, N'Vàng Trắng', 'VT'),
(41, N'Vàng Trắng', 'VT'),
(42, N'Vàng Trắng', 'VT'),
(43, N'Vàng Trắng', 'VT'),
(44, N'Vàng Trắng', 'VT'),
(45, N'Vàng Trắng', 'VT'),
(46, N'Vàng Trắng', 'VT'),
(47, N'Vàng Trắng', 'VT'),
(48, N'Vàng Trắng', 'VT'),
(49, N'Vàng Trắng', 'VT'),
(50, N'Vàng Trắng', 'VT'),
(51, N'Vàng Trắng', 'VT'),
(52, N'Vàng Trắng', 'VT'),
(53, N'Vàng Trắng', 'VT'),
(54, N'Vàng Trắng', 'VT'),
(55, N'Vàng Trắng', 'VT'),
(56, N'Vàng Trắng', 'VT'),
(57, N'Vàng Trắng', 'VT'),
(58, N'Vàng Trắng', 'VT'),
(59, N'Vàng Trắng', 'VT'),
(60, N'Vàng Trắng', 'VT'),
(61, N'Vàng Trắng', 'VT'),
(62, N'Vàng Trắng', 'VT'),
(63, N'Vàng Trắng', 'VT'),
(64, N'Vàng Trắng', 'VT'),
(65, N'Vàng Trắng', 'VT'),
(66, N'Vàng Trắng', 'VT'),
(67, N'Vàng Trắng', 'VT'),
(68, N'Vàng Trắng', 'VT'),
(69, N'Vàng Trắng', 'VT'),
(70, N'Vàng Trắng', 'VT'),
(71, N'Vàng Trắng', 'VT'),
(72, N'Vàng Trắng', 'VT'),
(73, N'Vàng Trắng', 'VT'),
(74, N'Vàng Trắng', 'VT'),
(75, N'Vàng Trắng', 'VT'),
(76, N'Vàng Trắng', 'VT'),
(77, N'Vàng Vàng', 'VV'),
(78, N'Vàng Trắng', 'VT'),
(78, N'Vàng Vàng', 'VV'),
(79, N'Vàng Vàng', 'VV'),
(80, N'Vàng Vàng', 'VV'),
(81, NULL, 'STD'),
(82, N'Vàng Trắng', 'VT'),
(83, NULL, 'STD'),
(84, N'Vàng Trắng', 'VT'),
(85, N'Vàng Trắng', 'VT'),
(86, N'Vàng Trắng', 'VT'),
(87, N'Vàng Trắng', 'VT'),
(88, N'Vàng Trắng', 'VT'),
(88, N'Vàng Vàng', 'VV'),
(89, N'Vàng Trắng', 'VT'),
(90, N'Vàng Trắng', 'VT'),
(90, N'Vàng Vàng', 'VV'),
(91, N'Vàng Vàng', 'VV'),
(91, N'Vàng Trắng', 'VT'),
(92, N'Vàng Trắng', 'VT'),
(92, N'Vàng Vàng', 'VV'),
(93, N'Vàng Trắng', 'VT'),
(93, N'Vàng Vàng', 'VV'),
(94, N'Vàng Trắng', 'VT'),
(94, N'Vàng Vàng', 'VV'),
(95, N'Vàng Trắng', 'VT'),
(95, N'Vàng Vàng', 'VV'),
(96, N'Vàng Vàng', 'VV'),
(97, N'Vàng Vàng', 'VV'),
(97, N'Vàng Trắng', 'VT'),
(98, N'Vàng Vàng', 'VV'),
(98, N'Vàng Trắng', 'VT'),
(99, N'Vàng Trắng', 'VT'),
(100, N'Vàng Trắng', 'VT'),
(101, N'Vàng Vàng', 'VV'),
(102, N'Vàng Trắng', 'VT'),
(103, N'Vàng Trắng', 'VT'),
(103, N'Vàng Vàng', 'VV'),
(104, N'Vàng Trắng', 'VT'),
(105, N'Vàng Trắng', 'VT'),
(106, N'Vàng Trắng', 'VT'),
(107, N'Vàng Trắng', 'VT'),
(108, N'Vàng Trắng', 'VT'),
(109, N'Vàng Trắng', 'VT'),
(110, N'Vàng Trắng', 'VT'),
(111, N'Vàng Trắng', 'VT'),
(112, N'Vàng Trắng', 'VT'),
(113, N'Vàng Trắng', 'VT'),
(114, N'Vàng Trắng', 'VT'),
(114, N'Vàng Hồng', 'VH'),
(115, N'Vàng Trắng', 'VT'),
(115, N'Vàng Hồng', 'VH'),
(116, N'Vàng Trắng', 'VT'),
(116, N'Vàng Hồng', 'VH'),
(117, N'Vàng Trắng', 'VT'),
(117, N'Vàng Hồng', 'VH'),
(118, N'Vàng Trắng', 'VT'),
(118, N'Vàng Hồng', 'VH'),
(119, N'Vàng Trắng', 'VT'),
(119, N'Vàng Hồng', 'VH'),
(120, N'Vàng Trắng', 'VT'),
(120, N'Vàng Hồng', 'VH'),
(121, N'Vàng Trắng', 'VT'),
(121, N'Vàng Hồng', 'VH'),
(122, N'Vàng Trắng', 'VT'),
(122, N'Vàng Hồng', 'VH'),
(123, N'Vàng Vàng', 'VV'),
(124, N'Vàng Vàng', 'VV'),
(125, N'Vàng Vàng', 'VV'),
(126, N'Vàng Trắng', 'VT'),
(127, N'Vàng Vàng', 'VV'),
(127, N'Vàng Hồng', 'VH'),
(128, N'Vàng Vàng', 'VV'),
(129, N'Vàng Trắng', 'VT'),
(130, N'Vàng Trắng', 'VT'),
(130, N'Vàng Vàng', 'VV'),
(131, N'Vàng Trắng', 'VT'),
(131, N'Vàng Vàng', 'VV'),
(132, N'Vàng Trắng', 'VT'),
(133, N'Vàng Trắng', 'VT'),
(134, N'Vàng Trắng', 'VT'),
(135, N'Vàng Trắng', 'VT'),
(136, N'Vàng Trắng', 'VT'),
(137, N'Vàng Trắng', 'VT'),
(138, N'Vàng Trắng', 'VT'),
(139, N'Vàng Vàng', 'VV'),
(140, N'Vàng Vàng', 'VV'),
(141, N'Vàng Trắng', 'VT'),
(142, N'Vàng Vàng', 'VV'),
(143, N'Vàng Vàng', 'VV'),
(144, N'Vàng Vàng', 'VV'),
(145, N'Vàng Vàng', 'VV'),
(145, N'Vàng Trắng', 'VT'),
(145, N'Vàng Hồng', 'VH'),
(146, N'Vàng Vàng', 'VV'),
(146, N'Vàng Trắng', 'VT'),
(146, N'Vàng Hồng', 'VH'),
(147, N'Vàng Vàng', 'VV'),
(148, N'Vàng Vàng', 'VV'),
(149, N'Vàng Vàng', 'VV'),
(150, N'Vàng Trắng', 'VT'),
(151, N'Vàng Vàng', 'VV'),
(152, N'Vàng Trắng', 'VT'),
(153, N'Vàng Trắng', 'VT'),
(154, N'Vàng Trắng', 'VT'),
(155, N'Vàng Trắng', 'VT'),
(156, N'Vàng Trắng', 'VT'),
(157, N'Vàng Trắng', 'VT'),
(158, N'Vàng Trắng', 'VT'),
(159, N'Vàng Trắng', 'VT'),
(160, N'Vàng Trắng', 'VT'),
(160, N'Vàng Vàng', 'VV'),
(161, N'Vàng Vàng', 'VV'),
(162, N'Vàng Vàng', 'VV'),
(163, N'Vàng Vàng', 'VV'),
(164, N'Vàng Vàng', 'VV'),
(165, N'Vàng Vàng', 'VV'),
(166, N'Vàng Vàng', 'VV'),
(167, N'Vàng Vàng', 'VV'),
(168, N'Vàng Vàng', 'VV'),
(169, N'Vàng Vàng', 'VV'),
(170, N'Vàng Vàng', 'VV'),
(170, N'Vàng Hồng', 'VH'),
(170, N'Vàng Trắng', 'VT'),
(171, N'Vàng Vàng', 'VV'),
(172, N'Bạc Trắng', 'BT'),
(173, N'Vàng Vàng', 'VV'),
(174, N'Vàng Vàng', 'VV'),
(174, N'Vàng Hồng', 'VH'),
(174, N'Vàng Trắng', 'VT'),
(175, N'Vàng Vàng', 'VV'),
(175, N'Vàng Trắng', 'VT'),
(175, N'Vàng Hồng', 'VH'),
(176, N'Vàng Vàng', 'VV'),
(177, N'Vàng Vàng', 'VV'),
(177, N'Vàng Hồng', 'VH'),
(178, N'Vàng Hồng', 'VH'),
(178, N'Vàng Trắng', 'VT'),
(178, N'Vàng Vàng', 'VV'),
(179, N'Vàng Hồng', 'VH'),
(179, N'Vàng Vàng', 'VV'),
(179, N'Vàng Trắng', 'VT'),
(180, N'Vàng Hồng', 'VH'),
(180, N'Vàng Vàng', 'VV'),
(180, N'Vàng Trắng', 'VT'),
(181, N'Vàng Vàng', 'VV'),
(181, N'Vàng Hồng', 'VH'),
(181, N'Vàng Trắng', 'VT'),
(182, N'Vàng Vàng', 'VV'),
(182, N'Vàng Hồng', 'VH'),
(182, N'Vàng Trắng', 'VT'),
(183, N'Vàng Trắng', 'VT'),
(183, N'Vàng Hồng', 'VH'),
(183, N'Vàng Vàng', 'VV'),
(184, N'Vàng Vàng', 'VV'),
(184, N'Vàng Hồng', 'VH'),
(184, N'Vàng Trắng', 'VT'),
(185, N'Vàng Vàng', 'VV'),
(185, N'Vàng Hồng', 'VH'),
(185, N'Vàng Trắng', 'VT'),
(186, N'Vàng Hồng', 'VH'),
(186, N'Vàng Vàng', 'VV'),
(186, N'Vàng Trắng', 'VT'),
(187, N'Vàng Vàng', 'VV'),
(187, N'Vàng Hồng', 'VH'),
(187, N'Vàng Trắng', 'VT'),
(188, N'Vàng Vàng', 'VV'),
(188, N'Vàng Hồng', 'VH'),
(188, N'Vàng Trắng', 'VT'),
(189, N'Vàng Vàng', 'VV'),
(189, N'Vàng Hồng', 'VH'),
(189, N'Vàng Trắng', 'VT'),
(190, N'Vàng Vàng', 'VV'),
(190, N'Vàng Hồng', 'VH'),
(191, N'Vàng Vàng', 'VV'),
(191, N'Vàng Hồng', 'VH'),
(192, N'Vàng Vàng', 'VV'),
(193, N'Vàng Trắng', 'VT'),
(193, N'Vàng Vàng', 'VV'),
(194, N'Vàng Trắng', 'VT'),
(195, N'Vàng Vàng', 'VV'),
(196, N'Vàng Vàng', 'VV'),
(197, N'Vàng Vàng', 'VV'),
(197, N'Vàng Hồng', 'VH'),
(198, N'Vàng Vàng', 'VV'),
(199, N'Vàng Vàng', 'VV'),
(200, N'Vàng Trắng', 'VT'),
(201, N'Vàng Trắng', 'VT'),
(202, N'Vàng Trắng', 'VT'),
(203, N'Vàng Vàng', 'VV'),
(204, N'Vàng Vàng', 'VV'),
(204, N'Vàng Trắng', 'VT'),
(205, N'Vàng Hồng', 'VH'),
(206, N'Vàng Vàng', 'VV'),
(207, N'Vàng Vàng', 'VV'),
(208, N'Vàng Trắng', 'VT'),
(209, N'Vàng Hồng', 'VH'),
(209, N'Vàng Vàng', 'VV'),
(210, N'Vàng Trắng', 'VT'),
(210, N'Vàng Vàng', 'VV'),
(211, N'Vàng Vàng', 'VV'),
(212, N'Vàng Trắng', 'VT'),
(213, N'Vàng Vàng', 'VV'),
(214, N'Vàng Vàng', 'VV'),
(214, N'Vàng Hồng', 'VH'),
(215, N'Vàng Trắng', 'VT'),
(215, N'Vàng Vàng', 'VV'),
(216, NULL, 'STD'),
(217, N'Vàng Vàng', 'VV'),
(217, N'Vàng Trắng', 'VT'),
(217, N'Vàng Hồng', 'VH'),
(218, N'Vàng Vàng', 'VV'),
(218, N'Vàng Trắng', 'VT'),
(218, N'Vàng Hồng', 'VH'),
(219, N'Vàng Vàng', 'VV'),
(219, N'Vàng Trắng', 'VT'),
(219, N'Vàng Hồng', 'VH'),
(220, N'Vàng Vàng', 'VV'),
(220, N'Vàng Trắng', 'VT'),
(220, N'Vàng Hồng', 'VH'),
(221, N'Vàng Vàng', 'VV'),
(222, N'Vàng Vàng', 'VV'),
(223, N'Vàng Vàng', 'VV'),
(224, N'Vàng Vàng', 'VV'),
(225, N'Vàng Vàng', 'VV'),
(226, N'Vàng Vàng', 'VV'),
(227, N'Bạc Vàng', 'BV'),
(228, N'Bạc Vàng', 'BV'),
(229, N'Bạc Vàng', 'BV'),
(230, N'Bạc Vàng', 'BV'),
(231, N'Bạc Vàng', 'BV'),
(232, N'Bạc Vàng', 'BV'),
(233, N'Bạc Vàng', 'BV'),
(234, N'Bạc Vàng', 'BV'),
(235, N'Bạc Vàng', 'BV'),
(236, N'Bạc Vàng', 'BV'),
(237, N'Bạc Vàng', 'BV'),
(238, N'Bạc Vàng', 'BV'),
(239, N'Bạc Vàng', 'BV'),
(240, N'Bạc Vàng', 'BV'),
(241, N'Bạc Vàng', 'BV'),
(242, N'Vàng Vàng', 'VV'),
(243, N'Vàng Hồng', 'VH'),
(244, N'Vàng Hồng', 'VH'),
(245, N'Vàng Hồng', 'VH'),
(246, N'Vàng Vàng', 'VV'),
(247, N'Vàng Vàng', 'VV'),
(248, N'Vàng Vàng', 'VV'),
(249, N'Vàng Hồng', 'VH'),
(250, N'Vàng Trắng', 'VT'),
(251, N'Vàng Trắng', 'VT'),
(252, N'Vàng Trắng', 'VT'),
(253, N'Vàng Trắng', 'VT'),
(254, N'Vàng Hồng', 'VH'),
(255, N'Vàng Hồng', 'VH'),
(256, N'Vàng Hồng', 'VH'),
(257, N'Vàng Hồng', 'VH'),
(258, N'Vàng Vàng', 'VV'),
(259, N'Vàng Hồng', 'VH'),
(260, N'Vàng Trắng', 'VT'),
(261, N'Vàng Trắng', 'VT'),
(262, N'Vàng Hồng', 'VH'),
(263, N'Vàng Trắng', 'VT'),
(264, N'Vàng Vàng', 'VV'),
(265, N'Vàng Vàng', 'VV'),
(266, N'Vàng Trắng', 'VT'),
(267, N'Vàng Vàng', 'VV'),
(268, N'Vàng Hồng', 'VH'),
(269, N'Vàng Vàng', 'VV'),
(269, N'Vàng Hồng', 'VH'),
(270, N'Vàng Vàng', 'VV'),
(271, N'Vàng Hồng', 'VH'),
(272, N'Vàng Vàng', 'VV'),
(273, N'Vàng Vàng', 'VV'),
(273, N'Vàng Trắng', 'VT'),
(274, N'Vàng Trắng', 'VT'),
(274, N'Vàng Vàng', 'VV'),
(275, N'Vàng Vàng', 'VV'),
(276, N'Vàng Vàng', 'VV'),
(276, N'Vàng Hồng', 'VH'),
(277, N'Vàng Trắng', 'VT'),
(277, N'Vàng Vàng', 'VV'),
(278, N'Vàng Vàng', 'VV'),
(279, N'Vàng Hồng', 'VH'),
(280, N'Vàng Hồng', 'VH'),
(281, N'Vàng Vàng', 'VV'),
(282, N'Vàng Vàng', 'VV'),
(283, N'Bạc Trắng', 'BT'),
(284, N'Bạc Trắng', 'BT'),
(285, N'Bạc Trắng', 'BT'),
(286, N'Vàng Hồng', 'VH'),
(287, N'Bạc Vàng', 'BV'),
(288, N'Bạc Vàng', 'BV'),
(289, N'Bạc Vàng', 'BV'),
(290, N'Bạc Vàng', 'BV'),
(291, N'Vàng Hồng', 'VH'),
(292, N'Vàng Vàng', 'VV'),
(293, N'Vàng Hồng', 'VH'),
(293, N'Vàng Trắng', 'VT'),
(294, N'Vàng Vàng', 'VV'),
(295, N'Vàng Vàng', 'VV'),
(296, N'Vàng Trắng', 'VT'),
(297, N'Vàng Trắng', 'VT'),
(298, N'Vàng Trắng', 'VT'),
(299, N'Vàng Trắng', 'VT'),
(300, N'Vàng Trắng', 'VT'),
(301, N'Vàng Vàng', 'VV'),
(302, N'Vàng Trắng', 'VT'),
(303, N'Vàng Trắng', 'VT'),
(304, N'Vàng Trắng', 'VT'),
(305, N'Vàng Trắng', 'VT'),
(306, N'Vàng Hồng', 'VH'),
(307, N'Vàng Vàng', 'VV'),
(308, N'Vàng Vàng', 'VV'),
(309, N'Vàng Hồng', 'VH'),
(310, N'Vàng Vàng', 'VV'),
(311, N'Vàng Vàng', 'VV'),
(312, N'Vàng Vàng', 'VV'),
(313, N'Vàng Vàng', 'VV'),
(314, N'Vàng Vàng', 'VV'),
(314, N'Vàng Hồng', 'VH'),
(314, N'Vàng Trắng', 'VT'),
(315, N'Vàng Vàng', 'VV'),
(316, N'Vàng Vàng', 'VV'),
(316, N'Vàng Trắng', 'VT'),
(317, N'Vàng Trắng', 'VT'),
(317, N'Vàng Vàng', 'VV'),
(318, N'Vàng Vàng', 'VV'),
(319, N'Vàng Vàng', 'VV'),
(320, N'Vàng Vàng', 'VV'),
(321, N'Vàng Vàng', 'VV'),
(321, N'Vàng Hồng', 'VH'),
(322, N'Vàng Vàng', 'VV'),
(322, N'Vàng Hồng', 'VH'),
(323, N'Vàng Trắng', 'VT'),
(324, N'Vàng Vàng', 'VV'),
(325, N'Vàng Trắng', 'VT'),
(326, N'Vàng Trắng', 'VT'),
(327, N'Vàng Vàng', 'VV'),
(328, N'Vàng Hồng', 'VH'),
(329, N'Vàng Hồng', 'VH'),
(330, N'Vàng Vàng', 'VV'),
(330, N'Vàng Trắng', 'VT'),
(331, N'Vàng Vàng', 'VV'),
(331, N'Vàng Trắng', 'VT'),
(332, N'Vàng Trắng', 'VT'),
(332, N'Vàng Vàng', 'VV'),
(333, N'Vàng Vàng', 'VV'),
(333, N'Vàng Hồng', 'VH'),
(334, N'Vàng Trắng', 'VT'),
(334, N'Vàng Vàng', 'VV'),
(335, N'Vàng Vàng', 'VV'),
(335, N'Vàng Trắng', 'VT'),
(336, N'Vàng Vàng', 'VV'),
(337, N'Vàng Vàng', 'VV'),
(338, N'Vàng Vàng', 'VV'),
(339, N'Vàng Vàng', 'VV'),
(340, N'Vàng Vàng', 'VV'),
(341, N'Vàng Vàng', 'VV'),
(342, N'Vàng Vàng', 'VV'),
(343, N'Vàng Vàng', 'VV'),
(344, N'Vàng Vàng', 'VV'),
(345, N'Vàng Vàng', 'VV'),
(346, N'Vàng Vàng', 'VV'),
(347, N'Vàng Vàng', 'VV'),
(348, N'Vàng Vàng', 'VV'),
(349, N'Vàng Vàng', 'VV'),
(350, N'Vàng Vàng', 'VV'),
(351, N'Vàng Vàng', 'VV'),
(352, N'Vàng Vàng', 'VV'),
(353, N'Vàng Vàng', 'VV'),
(354, N'Vàng Vàng', 'VV'),
(355, N'Vàng Vàng', 'VV'),
(356, N'Vàng Vàng', 'VV'),
(357, N'Vàng Vàng', 'VV'),
(358, N'Vàng Vàng', 'VV'),
(359, N'Vàng Trắng', 'VT'),
(360, N'Vàng Trắng', 'VT'),
(361, N'Vàng Vàng', 'VV'),
(362, N'Vàng Hồng', 'VH'),
(363, N'Vàng Vàng', 'VV'),
(364, N'Vàng Vàng', 'VV'),
(365, N'Vàng Vàng', 'VV'),
(366, N'Vàng Vàng', 'VV'),
(367, N'Vàng Trắng', 'VT'),
(368, N'Vàng Trắng', 'VT'),
(369, N'Vàng Vàng', 'VV'),
(369, N'Vàng Hồng', 'VH'),
(370, N'Vàng Vàng', 'VV'),
(370, N'Vàng Hồng', 'VH'),
(371, N'Vàng Vàng', 'VV'),
(372, N'Vàng Vàng', 'VV'),
(373, N'Vàng Vàng', 'VV'),
(374, N'Vàng Vàng', 'VV'),
(375, N'Vàng Vàng', 'VV'),
(376, N'Vàng Hồng', 'VH'),
(376, N'Vàng Vàng', 'VV'),
(377, N'Vàng Vàng', 'VV'),
(377, N'Vàng Hồng', 'VH'),
(378, NULL, 'STD'),
(379, NULL, 'STD'),
(380, NULL, 'STD'),
(381, NULL, 'STD'),
(382, NULL, 'STD'),
(383, NULL, 'STD'),
(384, NULL, 'STD'),
(385, NULL, 'STD'),
(386, NULL, 'STD'),
(387, NULL, 'STD'),
(388, NULL, 'STD'),
(389, NULL, 'STD'),
(390, NULL, 'STD'),
(391, NULL, 'STD'),
(392, NULL, 'STD'),
(393, NULL, 'STD'),
(394, NULL, 'STD'),
(395, NULL, 'STD'),
(396, NULL, 'STD'),
(397, NULL, 'STD'),
(398, NULL, 'STD'),
(399, NULL, 'STD'),
(400, NULL, 'STD'),
(401, NULL, 'STD');
INSERT INTO @ProductColors (ProductID, GoldColor, ColorCode) VALUES
(402, NULL, 'STD'),
(403, NULL, 'STD'),
(404, NULL, 'STD'),
(405, NULL, 'STD'),
(406, NULL, 'STD'),
(407, NULL, 'STD'),
(408, NULL, 'STD'),
(409, NULL, 'STD'),
(410, NULL, 'STD'),
(411, NULL, 'STD'),
(412, NULL, 'STD'),
(413, NULL, 'STD'),
(414, NULL, 'STD'),
(415, NULL, 'STD'),
(416, NULL, 'STD'),
(417, NULL, 'STD'),
(418, NULL, 'STD'),
(419, NULL, 'STD'),
(420, NULL, 'STD'),
(421, NULL, 'STD'),
(422, NULL, 'STD'),
(423, NULL, 'STD'),
(424, NULL, 'STD'),
(425, NULL, 'STD'),
(426, NULL, 'STD'),
(427, NULL, 'STD'),
(428, NULL, 'STD'),
(429, NULL, 'STD'),
(430, NULL, 'STD'),
(431, NULL, 'STD'),
(432, N'Vàng Vàng', 'VV'),
(433, N'Vàng Vàng', 'VV'),
(434, N'Vàng Vàng', 'VV'),
(435, N'Vàng Vàng', 'VV'),
(436, NULL, 'STD'),
(437, NULL, 'STD'),
(438, NULL, 'STD'),
(439, NULL, 'STD'),
(440, NULL, 'STD'),
(441, NULL, 'STD'),
(442, NULL, 'STD'),
(443, NULL, 'STD');

INSERT INTO dbo.ProductVariants (ProductID, VariantSKU, GoldColor, RingSize, StockQuantity)
SELECT pc.ProductID, CONCAT(p.SKU COLLATE DATABASE_DEFAULT, '-', pc.ColorCode COLLATE DATABASE_DEFAULT, '-', CAST(r.SizeVN AS VARCHAR(3)) COLLATE DATABASE_DEFAULT), pc.GoldColor, r.SizeVN, 3
FROM @ProductColors pc
JOIN dbo.Products p   ON p.ProductID = pc.ProductID
JOIN dbo.Categories c ON c.CategoryID = p.CategoryID AND c.RequiresRingSize = 1
JOIN dbo.RingSizeChart r ON r.SizeVN BETWEEN 6 AND 20
UNION ALL
SELECT pc.ProductID, CONCAT(p.SKU COLLATE DATABASE_DEFAULT, '-', pc.ColorCode COLLATE DATABASE_DEFAULT), pc.GoldColor, NULL, 10
FROM @ProductColors pc
JOIN dbo.Products p   ON p.ProductID = pc.ProductID
JOIN dbo.Categories c ON c.CategoryID = p.CategoryID AND c.RequiresRingSize = 0;

GO

-- 5.11. Mã ưu đãi: khuyến mãi khi đặt hàng và ưu đãi giữ chân đơn (BRD5)
INSERT INTO dbo.Vouchers (VoucherCode, VoucherName, VoucherType, DiscountType, DiscountValue, MaxDiscountAmount, MinOrderValue, StartAt, EndAt, UsageLimit) VALUES
('WELCOME5',   N'Giảm 5% cho đơn đầu tiên',                     'Promotion', 'Percent', 5,      1000000, 2000000,  '2026-01-01', '2027-12-31', 1000),
('VINORA500K', N'Giảm 500.000đ cho đơn từ 10 triệu',            'Promotion', 'Amount',  500000, NULL,    10000000, '2026-01-01', '2027-12-31', 500),
('GIUDON30',   N'Ưu đãi giữ lại đơn – giảm thêm 30% (tối đa 3 triệu)', 'Retention', 'Percent', 30, 3000000, 5000000, '2026-01-01', '2027-12-31', NULL);
GO

/* =====================================================================
   PHẦN 6. DỮ LIỆU MẪU MINH HỌA LUỒNG NGHIỆP VỤ
   Toàn bộ dữ liệu được tạo thông qua thủ tục nghiệp vụ để kiểm chứng
   trigger, ràng buộc và quy tắc ở Phần 3:
     - Khách A: đặt hàng VNPay + mã WELCOME5 -> thanh toán sandbox -> giao
       -> xác nhận đã nhận -> tự tạo thẻ bảo hành -> đánh giá -> hậu mãi.
     - Khách B: đặt hàng COD -> yêu cầu hủy -> CHẤP NHẬN ưu đãi giữ đơn
       -> giao thành công.
     - Khách C: đặt hàng COD -> yêu cầu hủy -> TỪ CHỐI ưu đãi -> đơn bị hủy,
       tồn kho được hoàn lại.
   PasswordHash là chuỗi băm minh họa (bcrypt), không phải mật khẩu thật.
   ===================================================================== */
USE VinoraJewelry;
GO
SET NOCOUNT ON;

DECLARE @AdminID INT, @UA INT, @UB INT, @UC INT, @CA INT, @CB INT, @CC INT,
        @AddrA INT, @AddrB INT, @AddrC INT,
        @V1 INT, @V2 INT, @V3 INT, @V4 INT, @V5 INT,
        @OrderA INT, @OrderB INT, @OrderC INT, @PayA INT,
        @ReqB INT, @ReqC INT, @Offer BIT,
        @WCode VARCHAR(20), @S1 INT, @S2 INT, @S3 INT, @FbA INT, @FbB INT,
        @InDays3 DATETIME2(0) = DATEADD(HOUR, 9, DATEADD(DAY, 3, CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME2(0)))),  -- 9h sáng, 3 ngày tới
        @StockC4 INT, @StockC5 INT;

/* ---------- 6.1. Tài khoản ---------- */
INSERT INTO dbo.Users (Username, FullName, Email, PasswordHash, Role)
VALUES ('admin', N'Quản trị viên Vinora', 'admin@vinora.vn', '$2b$12$DemoHashAdmin.OnlyForSampleData.xxxxxxxxxxxxxxxxxxxxxxxx', 'Admin');
SET @AdminID = SCOPE_IDENTITY();

INSERT INTO dbo.Users (FullName, Email, PasswordHash) VALUES
(N'Nguyễn Minh Anh', 'minhanh@example.com', '$2b$12$DemoHashCustomerA.OnlyForSampleData.xxxxxxxxxxxxxxxxxxxx');
SET @UA = SCOPE_IDENTITY();
INSERT INTO dbo.Users (FullName, Email, PasswordHash) VALUES
(N'Trần Gia Huy', 'giahuy@example.com', '$2b$12$DemoHashCustomerB.OnlyForSampleData.xxxxxxxxxxxxxxxxxxxx');
SET @UB = SCOPE_IDENTITY();
INSERT INTO dbo.Users (FullName, Email, PasswordHash) VALUES
(N'Lê Thu Hà', 'thuha@example.com', '$2b$12$DemoHashCustomerC.OnlyForSampleData.xxxxxxxxxxxxxxxxxxxx');
SET @UC = SCOPE_IDENTITY();

INSERT INTO dbo.Customers (UserID, Phone, DateOfBirth, DefaultRingSize) VALUES (@UA, '0901234567', '2003-05-12', 10);
SET @CA = SCOPE_IDENTITY();
INSERT INTO dbo.Customers (UserID, Phone, DateOfBirth, DefaultRingSize) VALUES (@UB, '0912345678', '1998-11-02', 12);
SET @CB = SCOPE_IDENTITY();
INSERT INTO dbo.Customers (UserID, Phone, DateOfBirth, DefaultRingSize) VALUES (@UC, '0987654321', '1975-02-20', NULL);
SET @CC = SCOPE_IDENTITY();

INSERT INTO dbo.CustomerAddresses (CustomerID, RecipientName, Phone, AddressLine, Ward, Province, IsDefault)
VALUES (@CA, N'Nguyễn Minh Anh', '0901234567', N'669 Quốc lộ 1A', N'Phường Linh Xuân', N'Thành phố Hồ Chí Minh', 1);
SET @AddrA = SCOPE_IDENTITY();
INSERT INTO dbo.CustomerAddresses (CustomerID, RecipientName, Phone, AddressLine, Ward, Province, IsDefault)
VALUES (@CB, N'Trần Gia Huy', '0912345678', N'12 Nguyễn Huệ', N'Phường Sài Gòn', N'Thành phố Hồ Chí Minh', 1);
SET @AddrB = SCOPE_IDENTITY();
INSERT INTO dbo.CustomerAddresses (CustomerID, RecipientName, Phone, AddressLine, Ward, Province, IsDefault)
VALUES (@CC, N'Lê Thu Hà', '0987654321', N'45 Trần Phú', N'Phường Hải Châu', N'Thành phố Đà Nẵng', 1);
SET @AddrC = SCOPE_IDENTITY();

/* ---------- 6.2. Chứng nhận minh họa cho sản phẩm khách A mua ---------- */
INSERT INTO dbo.ProductCertificates (ProductID, CertificateType, IssuingOrganization, CertificateNo, IssueDate, Note)
SELECT ProductID, 'GoldPurity', N'Trung tâm kiểm định vàng (minh họa)', 'DEMO-AU14-0001', '2026-09-15', N'Dữ liệu minh họa'
FROM dbo.Products WHERE SKU = 'NDINO131LDIA'
UNION ALL
SELECT ProductID, 'Diamond', N'IGI (minh họa)', 'DEMO-LG-0001', '2026-09-10', N'Dữ liệu minh họa – kim cương lab-grown'
FROM dbo.Products WHERE SKU = 'NDINO131LDIA';

/* ---------- 6.3. Lấy biến thể dùng cho demo ---------- */
SELECT @V1 = VariantID FROM dbo.ProductVariants WHERE VariantSKU = 'NDINO131LDIA-VT-10';   -- Nhẫn cầu hôn 14K lab-grown, size 10
SELECT @V2 = VariantID FROM dbo.ProductVariants WHERE VariantSKU = 'BT161B-VT';            -- Bông tai 10K đá CZ
SELECT @V3 = VariantID FROM dbo.ProductVariants WHERE VariantSKU = 'NDINO172KC-VV-12';     -- Nhẫn cầu hôn 18K kim cương tự nhiên, size 12
SELECT @V4 = VariantID FROM dbo.ProductVariants WHERE VariantSKU = 'MDBZ036-VV';           -- Mặt dây 24K (tính giá theo giá vàng)
SELECT @V5 = VariantID FROM dbo.ProductVariants WHERE VariantSKU = 'DCMAMD679-VV';         -- Dây chuyền 14K đá CZ

/* ---------- 6.4. Khách A: mua hàng trọn vẹn ---------- */
EXEC sp_set_session_context @key = N'UserID', @value = @UA;
EXEC dbo.sp_TrackProductView @CA, 1;
EXEC dbo.sp_TrackProductView @CA, 201;
EXEC dbo.sp_TrackProductView @CA, 1;

INSERT INTO dbo.CartItems (CustomerID, VariantID, Quantity, EngravingText) VALUES (@CA, @V1, 1, N'M & A');
INSERT INTO dbo.CartItems (CustomerID, VariantID, Quantity) VALUES (@CA, @V2, 1);

DECLARE @TokenA UNIQUEIDENTIFIER = NEWID();
EXEC dbo.sp_PlaceOrder @CustomerID = @CA, @AddressID = @AddrA, @PaymentMethod = 'VNPay',
     @CheckoutToken = @TokenA, @ShippingFee = 0, @VoucherCode = 'WELCOME5', @OrderID = @OrderA OUTPUT;
-- Gửi lặp cùng token: không tạo đơn thứ hai (NFR5)
DECLARE @OrderA_Retry INT;
EXEC dbo.sp_PlaceOrder @CustomerID = @CA, @AddressID = @AddrA, @PaymentMethod = 'VNPay',
     @CheckoutToken = @TokenA, @OrderID = @OrderA_Retry OUTPUT;

SELECT @PayA = PaymentID FROM dbo.Payments WHERE OrderID = @OrderA AND Status = 'Pending';
EXEC sp_set_session_context @key = N'Actor', @value = N'System:VNPaySandboxCallback';
EXEC dbo.sp_RecordPaymentResult @PaymentID = @PayA, @IsSuccess = 1, @TransactionID = 'VNP-SANDBOX-0001', @ResponseCode = '00';
EXEC dbo.sp_RecordPaymentResult @PaymentID = @PayA, @IsSuccess = 1, @TransactionID = 'VNP-SANDBOX-0001', @ResponseCode = '00'; -- callback lặp bị bỏ qua
EXEC sp_set_session_context @key = N'Actor', @value = NULL;

EXEC dbo.sp_UpdateOrderStatus @OrderID = @OrderA, @NewStatus = 'Confirmed', @AdminUserID = @AdminID;
EXEC dbo.sp_UpdateOrderStatus @OrderID = @OrderA, @NewStatus = 'Shipping',  @AdminUserID = @AdminID;

EXEC sp_set_session_context @key = N'UserID', @value = @UA;
EXEC dbo.sp_ConfirmOrderReceived @OrderID = @OrderA, @CustomerID = @CA;   -- trigger tạo 2 thẻ bảo hành

INSERT INTO dbo.CustomerFeedbacks (OrderID, CustomerID, RatingStar, ReviewText, SentimentLabel, SentimentScore, IsSentimentSimulated, AnalyzedAt)
VALUES (@OrderA, @CA, 5, N'Nhẫn sáng bóng, đúng size, hộp đóng gói rất sang trọng. Thẻ bảo hành điện tử tiện tra cứu.', 'Positive', 0.940, 1, SYSDATETIME());
SET @FbA = SCOPE_IDENTITY();
INSERT INTO dbo.FeedbackAspects (FeedbackID, AspectName, Polarity) VALUES
(@FbA, N'Độ sáng bóng', 'Positive'), (@FbA, N'Đóng gói', 'Positive'), (@FbA, N'Size nhẫn', 'Positive');

-- Hậu mãi bằng thẻ bảo hành của chiếc nhẫn
SELECT @WCode = w.WarrantyCode
FROM dbo.WarrantyRecords w JOIN dbo.OrderItems oi ON oi.OrderItemID = w.OrderItemID
WHERE w.OrderID = @OrderA AND oi.VariantID = @V1;

EXEC dbo.sp_BookAfterSalesService @WarrantyCode = @WCode, @CustomerID = @CA, @ServiceType = 'Polishing',
     @PreferredDate = @InDays3, @CustomerNote = N'Đánh bóng trước ngày kỷ niệm', @ServiceID = @S1 OUTPUT;
EXEC dbo.sp_ScheduleAfterSalesService @ServiceID = @S1, @AdminUserID = @AdminID, @AppointmentDate = @InDays3;
EXEC dbo.sp_CompleteAfterSalesService @ServiceID = @S1, @AdminUserID = @AdminID, @ResultNote = N'Đã đánh bóng, xi mới';

DECLARE @Resize DATETIME2(0) = DATEADD(HOUR, 5, @InDays3);
EXEC dbo.sp_BookAfterSalesService @WarrantyCode = @WCode, @CustomerID = @CA, @ServiceType = 'Resizing',
     @PreferredDate = @Resize, @NewRingSize = 11, @ServiceID = @S2 OUTPUT;
DECLARE @Proposed DATETIME2(0) = DATEADD(DAY, 1, @Resize);
EXEC dbo.sp_ScheduleAfterSalesService @ServiceID = @S2, @AdminUserID = @AdminID, @AppointmentDate = @Proposed;  -- đề xuất đổi lịch

EXEC dbo.sp_BookAfterSalesService @WarrantyCode = @WCode, @CustomerID = @CA, @ServiceType = 'Cleaning',
     @PreferredDate = @InDays3, @ServiceID = @S3 OUTPUT;
EXEC dbo.sp_CancelAfterSalesService @ServiceID = @S3, @CustomerID = @CA;   -- hủy lịch không mất lượt

/* ---------- 6.5. Khách B: yêu cầu hủy -> chấp nhận ưu đãi giữ đơn ---------- */
EXEC sp_set_session_context @key = N'UserID', @value = @UB;
INSERT INTO dbo.CartItems (CustomerID, VariantID, Quantity, EngravingText) VALUES (@CB, @V3, 1, N'Forever');
DECLARE @TokenB UNIQUEIDENTIFIER = NEWID();
EXEC dbo.sp_PlaceOrder @CustomerID = @CB, @AddressID = @AddrB, @PaymentMethod = 'COD',
     @CheckoutToken = @TokenB, @ShippingFee = 30000, @OrderID = @OrderB OUTPUT;

EXEC dbo.sp_RequestCancelOrder @OrderID = @OrderB, @CustomerID = @CB, @Reason = N'Phân vân về ngân sách',
     @RequestID = @ReqB OUTPUT, @OfferShown = @Offer OUTPUT;           -- @Offer = 1: hiển thị popup giữ đơn
EXEC dbo.sp_RespondRetentionOffer @RequestID = @ReqB, @CustomerID = @CB, @AcceptOffer = 1;

EXEC dbo.sp_UpdateOrderStatus @OrderID = @OrderB, @NewStatus = 'Confirmed', @AdminUserID = @AdminID;
EXEC dbo.sp_UpdateOrderStatus @OrderID = @OrderB, @NewStatus = 'Shipping',  @AdminUserID = @AdminID;
EXEC dbo.sp_UpdateOrderStatus @OrderID = @OrderB, @NewStatus = 'Delivered', @AdminUserID = @AdminID;

INSERT INTO dbo.CustomerFeedbacks (OrderID, CustomerID, RatingStar, ReviewText, SentimentLabel, SentimentScore, IsSentimentSimulated, AnalyzedAt)
VALUES (@OrderB, @CB, 3, N'Nhẫn đẹp, hộp quà chỉn chu nhưng giao trễ so với ngày kỷ niệm.', 'Negative', 0.810, 1, SYSDATETIME());
SET @FbB = SCOPE_IDENTITY();
INSERT INTO dbo.FeedbackAspects (FeedbackID, AspectName, Polarity) VALUES
(@FbB, N'Giao hàng', 'Negative'), (@FbB, N'Đóng gói', 'Positive');

/* ---------- 6.6. Khách C: yêu cầu hủy -> từ chối ưu đãi -> đơn bị hủy ---------- */
EXEC sp_set_session_context @key = N'UserID', @value = @UC;
SELECT @StockC4 = StockQuantity FROM dbo.ProductVariants WHERE VariantID = @V4;
SELECT @StockC5 = StockQuantity FROM dbo.ProductVariants WHERE VariantID = @V5;
INSERT INTO dbo.CartItems (CustomerID, VariantID, Quantity) VALUES (@CC, @V4, 2), (@CC, @V5, 1);
DECLARE @TokenC UNIQUEIDENTIFIER = NEWID();
EXEC dbo.sp_PlaceOrder @CustomerID = @CC, @AddressID = @AddrC, @PaymentMethod = 'COD',
     @CheckoutToken = @TokenC, @ShippingFee = 30000, @OrderID = @OrderC OUTPUT;
EXEC dbo.sp_RequestCancelOrder @OrderID = @OrderC, @CustomerID = @CC, @Reason = N'Muốn chọn mẫu khác',
     @RequestID = @ReqC OUTPUT, @OfferShown = @Offer OUTPUT;
EXEC dbo.sp_RespondRetentionOffer @RequestID = @ReqC, @CustomerID = @CC, @AcceptOffer = 0;

EXEC sp_set_session_context @key = N'UserID', @value = NULL;

/* ---------- 6.7. Kết quả demo ---------- */
SELECT N'Đơn A gửi lặp trả về cùng OrderID' AS KiemTra, CASE WHEN @OrderA = @OrderA_Retry THEN N'ĐẠT' ELSE N'KHÔNG ĐẠT' END AS KetQua
UNION ALL
SELECT N'Tồn kho được hoàn lại sau khi hủy đơn C',
       CASE WHEN (SELECT StockQuantity FROM dbo.ProductVariants WHERE VariantID = @V4) = @StockC4
             AND (SELECT StockQuantity FROM dbo.ProductVariants WHERE VariantID = @V5) = @StockC5 THEN N'ĐẠT' ELSE N'KHÔNG ĐẠT' END
UNION ALL
SELECT N'Đơn A tạo đủ 2 thẻ bảo hành',
       CASE WHEN (SELECT COUNT(*) FROM dbo.WarrantyRecords WHERE OrderID = @OrderA) = 2 THEN N'ĐẠT' ELSE N'KHÔNG ĐẠT' END
UNION ALL
SELECT N'Lượt đánh bóng còn lại của thẻ nhẫn = 4',
       CASE WHEN (SELECT PolishingCountLeft FROM dbo.WarrantyRecords WHERE WarrantyCode = @WCode) = 4 THEN N'ĐẠT' ELSE N'KHÔNG ĐẠT' END;
GO

/* ---------- 6.8. Kiểm thử ràng buộc (các thao tác sai phải bị chặn) ---------- */
SET NOCOUNT ON;
DECLARE @OA INT = (SELECT TOP (1) OrderID FROM dbo.Orders WHERE OrderStatus = 'Delivered' AND IsRetentionApplied = 0 ORDER BY OrderID);
DECLARE @OB INT = (SELECT TOP (1) OrderID FROM dbo.Orders WHERE IsRetentionApplied = 1 ORDER BY OrderID);
DECLARE @OC INT = (SELECT TOP (1) OrderID FROM dbo.Orders WHERE OrderStatus = 'Cancelled' ORDER BY OrderID);
DECLARE @OwnerA INT = (SELECT CustomerID FROM dbo.Orders WHERE OrderID = @OA);
DECLARE @OwnerC INT = (SELECT CustomerID FROM dbo.Orders WHERE OrderID = @OC);
DECLARE @RetentionVoucher INT = (SELECT VoucherID FROM dbo.Vouchers WHERE VoucherCode = 'GIUDON30');
DECLARE @Results TABLE (STT INT IDENTITY(1,1), KiemTra NVARCHAR(200), KetQua NVARCHAR(400));

BEGIN TRY
    UPDATE dbo.Orders SET OrderStatus = 'Shipping' WHERE OrderID = @OA;
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Chuyển đơn Delivered về Shipping', N'KHÔNG ĐẠT: thao tác không bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Chuyển đơn Delivered về Shipping', CONCAT(N'ĐẠT – bị chặn: ', ERROR_MESSAGE()));
END CATCH

BEGIN TRY
    UPDATE dbo.Orders SET ShippingFee = ShippingFee + 1 WHERE OrderID = @OA;
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Sửa số tiền của đơn đã hoàn tất', N'KHÔNG ĐẠT: thao tác không bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Sửa số tiền của đơn đã hoàn tất', CONCAT(N'ĐẠT – bị chặn: ', ERROR_MESSAGE()));
END CATCH

BEGIN TRY
    INSERT INTO dbo.CustomerFeedbacks (OrderID, CustomerID, RatingStar, ReviewText) VALUES (@OC, @OwnerC, 1, N'Thử đánh giá đơn đã hủy');
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Đánh giá đơn chưa nhận thành công', N'KHÔNG ĐẠT: thao tác không bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Đánh giá đơn chưa nhận thành công', CONCAT(N'ĐẠT – bị chặn: ', ERROR_MESSAGE()));
END CATCH

BEGIN TRY
    INSERT INTO dbo.CustomerFeedbacks (OrderID, CustomerID, RatingStar, ReviewText) VALUES (@OC, @OwnerA, 1, N'Thử đánh giá đơn của người khác');
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Đánh giá đơn của khách hàng khác', N'KHÔNG ĐẠT: thao tác không bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Đánh giá đơn của khách hàng khác', CONCAT(N'ĐẠT – bị chặn: ', ERROR_MESSAGE()));
END CATCH

BEGIN TRY
    UPDATE dbo.ProductVariants SET StockQuantity = -1 WHERE VariantID = (SELECT MIN(VariantID) FROM dbo.ProductVariants);
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Cập nhật tồn kho âm', N'KHÔNG ĐẠT: thao tác không bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Cập nhật tồn kho âm', CONCAT(N'ĐẠT – bị chặn: ', ERROR_MESSAGE()));
END CATCH

BEGIN TRY
    INSERT INTO dbo.OrderCancellationRequests (OrderID, OfferShown, OfferVoucherID, OfferDiscountAmount, Decision, DecidedAt)
    VALUES (@OB, 1, @RetentionVoucher, 0, 'ConfirmedCancel', SYSDATETIME());
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Đề nghị giữ chân lần thứ hai cho cùng đơn', N'KHÔNG ĐẠT: thao tác không bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Đề nghị giữ chân lần thứ hai cho cùng đơn', CONCAT(N'ĐẠT – bị chặn: ', ERROR_MESSAGE()));
END CATCH

BEGIN TRY
    INSERT INTO dbo.ProductVariants (ProductID, VariantSKU, GoldColor, RingSize, StockQuantity)
    SELECT TOP (1) p.ProductID, CONCAT(p.SKU, '-TEST-NOSIZE'), NULL, NULL, 1
    FROM dbo.Products p JOIN dbo.Categories c ON c.CategoryID = p.CategoryID
    WHERE c.RequiresRingSize = 1 ORDER BY p.ProductID;
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Tạo biến thể nhẫn không có size', N'KHÔNG ĐẠT: thao tác không bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    INSERT INTO @Results (KiemTra, KetQua) VALUES (N'Tạo biến thể nhẫn không có size', CONCAT(N'ĐẠT – bị chặn: ', ERROR_MESSAGE()));
END CATCH

SELECT * FROM @Results ORDER BY STT;
GO

/* =====================================================================
   PHẦN 7. TRUY VẤN KIỂM TRA NHANH
   ===================================================================== */
SELECT 'Users' AS TableName, COUNT(*) AS RowCnt FROM dbo.Users UNION ALL
SELECT 'Customers', COUNT(*) FROM dbo.Customers UNION ALL
SELECT 'CustomerAddresses', COUNT(*) FROM dbo.CustomerAddresses UNION ALL
SELECT 'RingSizeChart', COUNT(*) FROM dbo.RingSizeChart UNION ALL
SELECT 'Categories', COUNT(*) FROM dbo.Categories UNION ALL
SELECT 'Collections', COUNT(*) FROM dbo.Collections UNION ALL
SELECT 'WarrantyPolicies', COUNT(*) FROM dbo.WarrantyPolicies UNION ALL
SELECT 'Products', COUNT(*) FROM dbo.Products UNION ALL
SELECT 'ProductCollections', COUNT(*) FROM dbo.ProductCollections UNION ALL
SELECT 'ProductVariants', COUNT(*) FROM dbo.ProductVariants UNION ALL
SELECT 'ProductImages', COUNT(*) FROM dbo.ProductImages UNION ALL
SELECT 'ProductStones', COUNT(*) FROM dbo.ProductStones UNION ALL
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

SELECT * FROM dbo.vw_CustomerOrderHistory ORDER BY OrderID;
SELECT * FROM dbo.vw_RevenueByMonth;
SELECT * FROM dbo.vw_RevenueByMaterial;
SELECT * FROM dbo.vw_RetentionStats;
SELECT * FROM dbo.vw_SentimentSummary;
SELECT * FROM dbo.vw_FeedbackAspectSummary;
SELECT * FROM dbo.vw_CustomerWarranties;
SELECT TOP (10) * FROM dbo.vw_ProductCatalog WHERE CategoryGroup = N'Nhẫn' AND CurrentPrice BETWEEN 10000000 AND 30000000 ORDER BY CurrentPrice;
SELECT TOP (20) * FROM dbo.AuditLogs ORDER BY LogID;
GO

