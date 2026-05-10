-- =============================================================
-- ShopIQ E-Commerce Database Schema
-- DBA-owned DDL: no app-level DDL privileges
-- Database: shopiq_db
-- =============================================================

CREATE DATABASE IF NOT EXISTS shopiq_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE shopiq_db;

-- -------------------------------------------------------------
-- CUSTOMERS
-- -------------------------------------------------------------
CREATE TABLE customers (
    customer_id     INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    first_name      VARCHAR(60)     NOT NULL,
    last_name       VARCHAR(60)     NOT NULL,
    email           VARCHAR(120)    NOT NULL,
    phone           VARCHAR(20)         NULL,
    loyalty_tier    ENUM('BRONZE','SILVER','GOLD','PLATINUM') NOT NULL DEFAULT 'BRONZE',
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_customers         PRIMARY KEY (customer_id),
    CONSTRAINT uq_customers_email   UNIQUE      (email)
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- CATEGORIES
-- -------------------------------------------------------------
CREATE TABLE categories (
    category_id     INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    name            VARCHAR(80)     NOT NULL,
    parent_id       INT UNSIGNED        NULL,
    CONSTRAINT pk_categories        PRIMARY KEY (category_id),
    CONSTRAINT fk_cat_parent        FOREIGN KEY (parent_id)
        REFERENCES categories (category_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- PRODUCTS
-- -------------------------------------------------------------
CREATE TABLE products (
    product_id      INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    sku             VARCHAR(40)     NOT NULL,
    name            VARCHAR(200)    NOT NULL,
    description     TEXT                NULL,
    category_id     INT UNSIGNED        NULL,
    unit_price      DECIMAL(10,2)   NOT NULL,
    stock_qty       INT             NOT NULL DEFAULT 0,
    is_active       TINYINT(1)      NOT NULL DEFAULT 1,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_products          PRIMARY KEY (product_id),
    CONSTRAINT uq_products_sku      UNIQUE      (sku),
    CONSTRAINT fk_prod_category     FOREIGN KEY (category_id)
        REFERENCES categories (category_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- ORDERS
-- -------------------------------------------------------------
CREATE TABLE orders (
    order_id        INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    customer_id     INT UNSIGNED    NOT NULL,
    status          ENUM('PENDING','CONFIRMED','PROCESSING','SHIPPED',
                         'DELIVERED','CANCELLED','REFUNDED') NOT NULL DEFAULT 'PENDING',
    subtotal        DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    shipping_cost   DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    tax_amount      DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    total_amount    DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    shipping_address TEXT               NULL,
    tracking_number VARCHAR(80)         NULL,
    carrier         VARCHAR(40)         NULL,
    ordered_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    shipped_at      DATETIME            NULL,
    delivered_at    DATETIME            NULL,
    CONSTRAINT pk_orders            PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_customer   FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- ORDER ITEMS
-- -------------------------------------------------------------
CREATE TABLE order_items (
    item_id         INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    order_id        INT UNSIGNED    NOT NULL,
    product_id      INT UNSIGNED    NOT NULL,
    quantity        INT             NOT NULL DEFAULT 1,
    unit_price      DECIMAL(10,2)   NOT NULL,
    line_total      DECIMAL(10,2)   NOT NULL,
    CONSTRAINT pk_order_items       PRIMARY KEY (item_id),
    CONSTRAINT fk_oi_order          FOREIGN KEY (order_id)
        REFERENCES orders (order_id) ON DELETE CASCADE,
    CONSTRAINT fk_oi_product        FOREIGN KEY (product_id)
        REFERENCES products (product_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- RETURNS
-- -------------------------------------------------------------
CREATE TABLE returns (
    return_id       INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    order_id        INT UNSIGNED    NOT NULL,
    item_id         INT UNSIGNED        NULL,
    reason          VARCHAR(200)    NOT NULL,
    status          ENUM('REQUESTED','APPROVED','REJECTED','RECEIVED','REFUNDED')
                                    NOT NULL DEFAULT 'REQUESTED',
    refund_amount   DECIMAL(10,2)       NULL,
    requested_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at     DATETIME            NULL,
    CONSTRAINT pk_returns           PRIMARY KEY (return_id),
    CONSTRAINT fk_ret_order         FOREIGN KEY (order_id)
        REFERENCES orders (order_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ret_item          FOREIGN KEY (item_id)
        REFERENCES order_items (item_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- CHAT SESSIONS
-- -------------------------------------------------------------
CREATE TABLE chat_sessions (
    session_id      VARCHAR(64)     NOT NULL,
    customer_id     INT UNSIGNED        NULL,
    started_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at        DATETIME            NULL,
    CONSTRAINT pk_chat_sessions     PRIMARY KEY (session_id),
    CONSTRAINT fk_cs_customer       FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- CHAT MESSAGES (audit log)
-- -------------------------------------------------------------
CREATE TABLE chat_messages (
    message_id      INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    session_id      VARCHAR(64)     NOT NULL,
    role            ENUM('user','assistant') NOT NULL,
    content         TEXT            NOT NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_chat_messages     PRIMARY KEY (message_id),
    CONSTRAINT fk_cm_session        FOREIGN KEY (session_id)
        REFERENCES chat_sessions (session_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- INDEXES
-- -------------------------------------------------------------
CREATE INDEX idx_orders_customer    ON orders (customer_id);
CREATE INDEX idx_orders_status      ON orders (status);
CREATE INDEX idx_oi_order           ON order_items (order_id);
CREATE INDEX idx_chat_msg_session   ON chat_messages (session_id);
CREATE INDEX idx_products_sku       ON products (sku);
