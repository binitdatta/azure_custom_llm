-- =============================================================
-- ShopIQ Seed Data
-- Run AFTER 01_schema.sql
-- =============================================================

USE shopiq_db;

-- -------------------------------------------------------------
-- CATEGORIES
-- -------------------------------------------------------------
INSERT INTO categories (category_id, name, parent_id) VALUES
(1,  'Electronics',           NULL),
(2,  'Laptops & Computers',   1),
(3,  'Smartphones',           1),
(4,  'Audio',                 1),
(5,  'Clothing',              NULL),
(6,  'Men''s Clothing',       5),
(7,  'Women''s Clothing',     5),
(8,  'Home & Kitchen',        NULL),
(9,  'Kitchen Appliances',    8),
(10, 'Furniture',             8);

-- -------------------------------------------------------------
-- PRODUCTS
-- -------------------------------------------------------------
INSERT INTO products (product_id, sku, name, description, category_id, unit_price, stock_qty) VALUES
(1,  'LAP-001', 'ProBook 15 Laptop',
     '15.6" FHD, Intel i7, 16GB RAM, 512GB SSD. Slim professional laptop.',
     2, 1299.99, 45),
(2,  'LAP-002', 'UltraSlim X1 Laptop',
     '13.3" 4K OLED, AMD Ryzen 9, 32GB RAM, 1TB NVMe. Ultra-portable powerhouse.',
     2, 1899.99, 20),
(3,  'PHN-001', 'Galaxy S25 Smartphone',
     '6.7" Dynamic AMOLED, 200MP camera, 5000mAh battery.',
     3, 999.99, 120),
(4,  'PHN-002', 'Pixel 9 Pro',
     '6.3" LTPO OLED, Google Tensor G4, 7 years of OS updates.',
     3, 1099.99, 85),
(5,  'AUD-001', 'SoundMax Pro Headphones',
     'Active Noise Cancelling, 30hr battery, Hi-Res Audio certified.',
     4, 349.99, 200),
(6,  'AUD-002', 'BassCore Earbuds',
     'True wireless, IPX5 water resistant, 8hr + 24hr case battery.',
     4, 129.99, 350),
(7,  'CLM-001', 'Classic Oxford Shirt - Navy',
     '100% premium cotton. Available sizes S, M, L, XL, XXL.',
     6, 59.99, 180),
(8,  'CLW-001', 'Cashmere Blend Sweater - Cream',
     'Luxurious cashmere-merino blend. Relaxed fit. Hand wash only.',
     7, 149.99, 90),
(9,  'KIT-001', 'AeroChef Air Fryer 5.5L',
     '1800W digital air fryer. 12 presets. Dishwasher-safe basket.',
     9, 89.99, 300),
(10, 'FRN-001', 'ErgoDesk Standing Desk',
     'Electric height-adjustable desk. 120x60cm. Memory presets.',
     10, 699.99, 30);

-- -------------------------------------------------------------
-- CUSTOMERS
-- -------------------------------------------------------------
INSERT INTO customers (customer_id, first_name, last_name, email, phone, loyalty_tier) VALUES
(1, 'Alice',   'Walker',   'alice.walker@example.com',   '555-101-2020', 'GOLD'),
(2, 'Bob',     'Martinez', 'bob.martinez@example.com',   '555-202-3131', 'SILVER'),
(3, 'Carol',   'Johnson',  'carol.johnson@example.com',  '555-303-4242', 'PLATINUM'),
(4, 'David',   'Lee',      'david.lee@example.com',      '555-404-5353', 'BRONZE'),
(5, 'Eve',     'Chen',     'eve.chen@example.com',        NULL,           'SILVER');

-- -------------------------------------------------------------
-- ORDERS
-- -------------------------------------------------------------
INSERT INTO orders (order_id, customer_id, status, subtotal, shipping_cost, tax_amount,
                    total_amount, shipping_address, tracking_number, carrier,
                    ordered_at, shipped_at, delivered_at) VALUES
(1, 1, 'DELIVERED', 1299.99, 0.00, 117.00, 1416.99,
   '100 Maple Ave, Seattle WA 98101',
   'UPS-9374651234', 'UPS',
   '2025-04-01 10:00:00', '2025-04-02 14:00:00', '2025-04-04 11:00:00'),

(2, 1, 'SHIPPED', 349.99, 9.99, 32.40, 392.38,
   '100 Maple Ave, Seattle WA 98101',
   'FEDEX-7749382910', 'FedEx',
   '2025-04-28 09:00:00', '2025-04-29 15:30:00', NULL),

(3, 2, 'PROCESSING', 999.99, 0.00, 90.00, 1089.99,
   '45 Oak St, Austin TX 78701',
   NULL, NULL,
   '2025-05-01 11:30:00', NULL, NULL),

(4, 3, 'DELIVERED', 89.99, 5.99, 8.64, 104.62,
   '200 Pine Rd, Chicago IL 60601',
   'UPS-1122334455', 'UPS',
   '2025-03-20 08:00:00', '2025-03-21 12:00:00', '2025-03-23 09:30:00'),

(5, 3, 'CANCELLED', 1899.99, 0.00, 0.00, 1899.99,
   '200 Pine Rd, Chicago IL 60601',
   NULL, NULL,
   '2025-04-15 16:00:00', NULL, NULL),

(6, 4, 'PENDING', 699.99, 49.99, 67.50, 817.48,
   '9 Birch Blvd, Miami FL 33101',
   NULL, NULL,
   '2025-05-08 14:00:00', NULL, NULL),

(7, 5, 'DELIVERED', 279.98, 0.00, 25.20, 305.18,
   '77 Elm Dr, Denver CO 80201',
   'USPS-9400111899223344556677', 'USPS',
   '2025-04-10 07:00:00', '2025-04-11 10:00:00', '2025-04-14 13:00:00');

-- -------------------------------------------------------------
-- ORDER ITEMS
-- -------------------------------------------------------------
INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
-- Order 1: ProBook Laptop
(1, 1, 1, 1299.99, 1299.99),
-- Order 2: SoundMax Headphones
(2, 5, 1, 349.99, 349.99),
-- Order 3: Galaxy S25
(3, 3, 1, 999.99, 999.99),
-- Order 4: AeroChef Air Fryer
(4, 9, 1, 89.99, 89.99),
-- Order 5: UltraSlim X1 (cancelled)
(5, 2, 1, 1899.99, 1899.99),
-- Order 6: ErgoDesk
(6, 10, 1, 699.99, 699.99),
-- Order 7: Oxford Shirt + BassCore Earbuds
(7, 7,  1, 59.99, 59.99),
(7, 6,  1, 129.99, 129.99),
(7, 8,  1, 149.99, 149.99);

-- -------------------------------------------------------------
-- RETURNS
-- -------------------------------------------------------------
INSERT INTO returns (order_id, item_id, reason, status, refund_amount, requested_at, resolved_at) VALUES
(5, 5, 'Changed mind after reading reviews', 'REFUNDED', 1899.99,
 '2025-04-15 18:00:00', '2025-04-16 09:00:00');
