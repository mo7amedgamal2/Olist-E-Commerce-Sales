-- ==================================================================================
-- PROJECT: Brazilian E-Commerce Analysis (Olist Dataset)
-- DESCRIPTION: SQL queries for database cleanup, analytics, views, and procedures
-- DIALECT: Microsoft SQL Server (T-SQL)
-- ==================================================================================

USE olist;
GO

-- ==================================================================================
-- 0. DATABASE PREPARATION & CLEANUP
-- ==================================================================================

-- View translation table and product category schema
SELECT * FROM product_category_name_translation;
SELECT * FROM olist_products_dataset;

-- Check for product categories that do not have English translations
SELECT DISTINCT p.product_category_name
FROM olist_products_dataset p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
WHERE t.product_category_name IS NULL;

-- Handle missing translations and NULLs
INSERT INTO product_category_name_translation (product_category_name, product_category_name_english)
VALUES ('unknown', 'Unknown');

UPDATE olist_products_dataset
SET product_category_name = 'unknown'
WHERE product_category_name IS NULL;
GO


-- ==================================================================================
-- 1. BUSINESS QUESTIONS (SQL QUERIES)
-- ==================================================================================

-- a) How many unique customers placed orders?
SELECT COUNT(DISTINCT customer_id) AS unique_customers
FROM olist_customers_dataset;

-- b) Which are the top 10 most sold product categories?
SELECT TOP 10 
    COUNT(DISTINCT o.order_item_id) AS total_orders,
    p.product_category_name
FROM olist_order_items_dataset o 
JOIN olist_products_dataset p ON o.product_id = p.product_id
GROUP BY p.product_category_name
ORDER BY total_orders DESC;

-- c) Which sellers generated the highest revenue?
SELECT 
    s.seller_id,
    s.seller_city,
    s.seller_state,
    (oi.price + oi.freight_value) AS revenue
FROM olist_sellers_dataset s 
JOIN olist_order_items_dataset oi ON s.seller_id = oi.seller_id
ORDER BY revenue DESC;

-- d) What is the average delivery delay (actual vs estimated)?
SELECT AVG(DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date)) AS avg_delivery_delay_days
FROM olist_orders_dataset
WHERE order_delivered_customer_date IS NOT NULL;

-- d.2) Total orders by delivery status (Delayed, On Time, Early)
SELECT 
    CASE 
        WHEN DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) > 0 THEN 'Delayed'
        WHEN DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) = 0 THEN 'On Time'
        ELSE 'Early'
    END AS delivery_status,
    COUNT(*) AS total_orders
FROM olist_orders_dataset
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY 
    CASE 
        WHEN DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) > 0 THEN 'Delayed'
        WHEN DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) = 0 THEN 'On Time'
        ELSE 'Early'
    END;

-- e) Which payment methods are most common?
SELECT 
    payment_type,
    COUNT(payment_type) AS total_used
FROM olist_order_payments_dataset
GROUP BY payment_type 
ORDER BY total_used DESC;

-- f) What is the monthly trend of orders and revenue?
SELECT 
    COUNT(DISTINCT o.order_id) AS total_orders,
    FORMAT(o.order_purchase_timestamp, 'yyyy-MM') AS order_month,
    SUM(oi.price + oi.freight_value) AS total_revenue
FROM olist_orders_dataset o 
JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
GROUP BY FORMAT(o.order_purchase_timestamp, 'yyyy-MM')
ORDER BY total_revenue DESC;

-- g) What is the average review score by product category?
SELECT 
    p.product_category_name,
    AVG(r.review_score) AS avg_review_score
FROM olist_order_reviews_dataset r 
JOIN olist_order_items_dataset oi ON r.order_id = oi.order_id
JOIN olist_products_dataset p ON oi.product_id = p.product_id
GROUP BY p.product_category_name
ORDER BY avg_review_score DESC;

-- h) Who are the top customers by spending?
SELECT TOP 5 
    o.customer_id,
    SUM(oi.price + oi.freight_value) AS total_spending
FROM olist_orders_dataset o 
JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
GROUP BY o.customer_id
ORDER BY total_spending DESC;

-- i) Which states have the highest number of orders?
SELECT TOP 10 
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM olist_orders_dataset o 
JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY total_orders DESC;

-- j) Use window functions to rank sellers by revenue within each state.
SELECT 
    oi.seller_id,
    s.seller_state,
    SUM(oi.price + oi.freight_value) AS total_revenue,
    RANK() OVER (PARTITION BY s.seller_state ORDER BY SUM(oi.price + oi.freight_value) DESC) AS revenue_rank
FROM olist_order_items_dataset oi 
JOIN olist_sellers_dataset s ON oi.seller_id = s.seller_id
GROUP BY s.seller_state, oi.seller_id;

-- k) In year 2018, flag each seller as (Below Target, Within Target, Above Target) based on number of sold items and revenue.
SELECT 
    s.seller_id,
    s.total_items_sold,
    s.total_revenue,
    CASE 
        WHEN s.total_items_sold < 50 OR s.total_revenue < 5000 THEN 'Below Target'
        WHEN s.total_items_sold BETWEEN 50 AND 100 OR s.total_revenue BETWEEN 5000 AND 10000 THEN 'Within Target'
        ELSE 'Above Target'
    END AS target_flag
FROM (
    SELECT 
        oi.seller_id,
        COUNT(oi.product_id) AS total_items_sold,
        SUM(oi.price + oi.freight_value) AS total_revenue
    FROM olist_order_items_dataset oi 
    JOIN olist_orders_dataset o ON oi.order_id = o.order_id
    WHERE YEAR(o.order_purchase_timestamp) = 2018
    GROUP BY oi.seller_id
) s;
GO


-- ==================================================================================
-- 2. VIEWS
-- ==================================================================================

-- 1- Customer Order Summary View
CREATE OR ALTER VIEW customer_order_summary AS
SELECT 
    c.customer_id,
    c.customer_city,
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(oi.price + oi.freight_value) AS total_spent
FROM olist_customers_dataset c 
JOIN olist_orders_dataset o ON c.customer_id = o.customer_id
JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.customer_city, c.customer_state;
GO

SELECT * FROM customer_order_summary;
GO

-- 2- Seller Performance View
CREATE OR ALTER VIEW seller_performance AS
SELECT 
    s.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(oi.product_id) AS total_items_sold,
    SUM(oi.price + oi.freight_value) AS total_revenue,
    AVG(CAST(r.review_score AS FLOAT)) AS avg_review_score
FROM olist_sellers_dataset s 
JOIN olist_order_items_dataset oi ON s.seller_id = oi.seller_id
JOIN olist_orders_dataset o ON oi.order_id = o.order_id
LEFT JOIN olist_order_reviews_dataset r ON o.order_id = r.order_id
GROUP BY s.seller_id, s.seller_city, s.seller_state;
GO

SELECT * FROM seller_performance;
GO

-- 3- Product Category Sales View
CREATE OR ALTER VIEW product_category_sales AS
SELECT 
    p.product_category_name,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    SUM(oi.price) AS total_sales,
    AVG(CAST(r.review_score AS FLOAT)) AS avg_review_score
FROM olist_products_dataset p 
JOIN olist_order_items_dataset oi ON p.product_id = oi.product_id
JOIN olist_orders_dataset o ON oi.order_id = o.order_id
LEFT JOIN olist_order_reviews_dataset r ON o.order_id = r.order_id
GROUP BY p.product_category_name;
GO

SELECT * FROM product_category_sales;
GO


-- ==================================================================================
-- 3. STORED PROCEDURES
-- ==================================================================================

-- 1- Get top 10 customers by total spend
CREATE OR ALTER PROCEDURE get_top_10_customers_by_spend
AS
BEGIN
    SELECT TOP 10 
        c.customer_id,
        SUM(oi.price + oi.freight_value) AS total_spent
    FROM olist_customers_dataset c 
    JOIN olist_orders_dataset o ON c.customer_id = o.customer_id
    JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
    GROUP BY c.customer_id
    ORDER BY total_spent DESC;
END;
GO

EXEC get_top_10_customers_by_spend;
GO

-- 2- Get top 5 sellers by revenue in a given time period
CREATE OR ALTER PROCEDURE get_top_5_sellers_by_revenue
    @start_date DATETIME,
    @end_date DATETIME
AS
BEGIN
    SELECT TOP 5 
        s.seller_id,
        s.seller_city,
        s.seller_state,
        FORMAT(o.order_purchase_timestamp, 'yyyy-MM-dd') AS order_date,
        SUM(oi.price + oi.freight_value) AS total_revenue
    FROM olist_sellers_dataset s 
    JOIN olist_order_items_dataset oi ON s.seller_id = oi.seller_id
    JOIN olist_orders_dataset o ON oi.order_id = o.order_id
    WHERE o.order_purchase_timestamp BETWEEN @start_date AND @end_date
    GROUP BY s.seller_id, s.seller_city, s.seller_state, FORMAT(o.order_purchase_timestamp, 'yyyy-MM-dd')
    ORDER BY total_revenue DESC;
END;
GO

EXEC get_top_5_sellers_by_revenue '2018-01-01', '2018-12-31';
GO
