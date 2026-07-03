-- ============================================================
-- E-Commerce Sales Analysis - SQL Queries
-- Database: PostgreSQL
-- Dataset: Olist Brazilian E-Commerce (Kaggle)
-- Tables: orders, customers, order_items, payments, 
--         reviews, products, sellers
-- ============================================================


-- 1. Total Revenue and Orders (Overall KPIs)
-- Business question: What is the overall business performance?
SELECT
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value)::NUMERIC, 2) AS total_revenue,
    ROUND(AVG(oi.price + oi.freight_value)::NUMERIC, 2) AS avg_order_value
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id;
-- Result: ~96,478 orders | Total revenue ~$16M | Avg order value ~$165


-- 2. Monthly Revenue Trend
-- Business question: How has revenue grown month over month?
SELECT
    EXTRACT(YEAR FROM o.order_purchase_timestamp) AS year,
    EXTRACT(MONTH FROM o.order_purchase_timestamp) AS month,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value)::NUMERIC, 2) AS monthly_revenue
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY
    EXTRACT(YEAR FROM o.order_purchase_timestamp),
    EXTRACT(MONTH FROM o.order_purchase_timestamp)
ORDER BY year ASC, month ASC;
-- Result: 33 months of data (2016-2018)
-- Peak: November 2017 with $1,082,628 (Black Friday effect)
-- 2018 shows ~3x revenue vs same months in 2017


-- 3. Top 10 Product Categories by Revenue
-- Business question: Which product categories drive the most revenue?
SELECT
    p.product_category_name_english AS category,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value)::NUMERIC, 2) AS total_revenue,
    ROUND(AVG(oi.price)::NUMERIC, 2) AS avg_product_price
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
INNER JOIN products p ON oi.product_id = p.product_id
GROUP BY p.product_category_name_english
ORDER BY total_revenue DESC
LIMIT 10;
-- Result: health_beauty #1 ($1.4M), watches_gifts #2 ($1.26M)
-- watches_gifts has fewer orders but higher avg price ($199) than bed_bath_table ($93)
-- showing revenue is driven by both volume AND price point


-- 4. Top 10 States by Number of Orders
-- Business question: Which Brazilian states generate the most orders and revenue?
SELECT
    c.customer_state AS state,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value)::NUMERIC, 2) AS total_revenue
FROM orders o
INNER JOIN customers c ON o.customer_id = c.customer_id
INNER JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_state
ORDER BY total_orders DESC
LIMIT 10;
-- Result: SP dominates with 40,501 orders and $5.7M revenue
-- SP + RJ + MG account for majority of all Brazilian e-commerce


-- 5. Average Order Value by Payment Type
-- Business question: How does payment method affect order value?
SELECT
    p.payment_type,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(AVG(p.payment_value)::NUMERIC, 2) AS avg_payment_value,
    ROUND(SUM(p.payment_value)::NUMERIC, 2) AS total_revenue
FROM orders o
INNER JOIN payments p ON o.order_id = p.order_id
GROUP BY p.payment_type
ORDER BY avg_payment_value DESC;
-- Result: credit_card avg $162 | boleto avg $144 | voucher avg $62
-- Voucher avg is less than half of credit card avg
-- confirming vouchers are supplementary payment tools not primary ones


-- 6. Top 10 Product Categories by Average Review Score
-- Business question: Which categories have the most satisfied customers?
-- Note: HAVING >= 100 filters out categories with too few orders
-- to avoid small sample size bias
SELECT
    p.product_category_name_english AS category,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(AVG(r.review_score)::NUMERIC, 2) AS avg_review_score
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
INNER JOIN products p ON oi.product_id = p.product_id
INNER JOIN reviews r ON o.order_id = r.order_id
GROUP BY p.product_category_name_english
HAVING COUNT(DISTINCT o.order_id) >= 100
ORDER BY avg_review_score DESC
LIMIT 10;
-- Result: books_general_interest #1 (4.51), books_technical #2 (4.39)
-- Books consistently get highest satisfaction scores
-- predictable product quality = met expectations = happy customers


-- 7. Top 10 Sellers by Revenue
-- Business question: Which sellers generate the most revenue?
SELECT
    oi.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value)::NUMERIC, 2) AS total_revenue
FROM order_items oi
INNER JOIN orders o ON oi.order_id = o.order_id
INNER JOIN sellers s ON oi.seller_id = s.seller_id
GROUP BY oi.seller_id, s.seller_city, s.seller_state
ORDER BY total_revenue DESC
LIMIT 10;
-- Result: 9 out of 10 top sellers are from SP (Sao Paulo)
-- BA seller ranks #4 with only 348 orders but $230K revenue
-- showing very high avg order value (~$664) vs SP sellers (~$220)


-- 8. Repeat Customers vs One-Time Customers
-- Business question: What percentage of customers return to buy again?
-- Note: Using customer_unique_id (not customer_id) to correctly
-- identify unique individuals across multiple orders
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM orders o
    INNER JOIN customers c ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    CASE
        WHEN total_orders = 1 THEN 'One-time customer'
        ELSE 'Repeat customer'
    END AS customer_type,
    COUNT(*) AS total_customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS percentage
FROM customer_orders
GROUP BY
    CASE
        WHEN total_orders = 1 THEN 'One-time customer'
        ELSE 'Repeat customer'
    END
ORDER BY total_customers DESC;
-- Result: 97% one-time customers | Only 3% (2,801) ever return
-- CRITICAL BUSINESS INSIGHT: Severe retention problem
-- loyalty programs and re-engagement campaigns urgently needed


-- 9. Average Delivery Time in Days
-- Business question: How long does delivery take on average?
-- Note: BETWEEN 0 AND 60 excludes data errors (negative delivery times
-- and extreme outliers of 688 days found in raw data)
SELECT
    ROUND(AVG(
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))
        / 86400
    )::NUMERIC, 1) AS avg_delivery_days,
    ROUND(MIN(
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))
        / 86400
    )::NUMERIC, 1) AS min_delivery_days,
    ROUND(MAX(
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))
        / 86400
    )::NUMERIC, 1) AS max_delivery_days,
    COUNT(*) AS total_orders_measured
FROM orders o
WHERE order_delivered_customer_date IS NOT NULL
AND order_purchase_timestamp IS NOT NULL
AND EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))
    / 86400 BETWEEN 0 AND 60;
-- Result: avg 14.3 days | min 0.0 days | max 60.0 days
-- Longer delivery times reflect Brazil's geographic challenges
-- Raw data had negative delivery times and 688-day outliers (data errors)
-- filtered out using BETWEEN 0 AND 60


-- 10. Monthly Revenue Growth Rate (Window Function - LAG)
-- Business question: What is the month-over-month revenue growth rate?
WITH monthly_revenue AS (
    SELECT
        EXTRACT(YEAR FROM o.order_purchase_timestamp) AS year,
        EXTRACT(MONTH FROM o.order_purchase_timestamp) AS month,
        ROUND(SUM(oi.price + oi.freight_value)::NUMERIC, 2) AS revenue
    FROM orders o
    INNER JOIN order_items oi ON o.order_id = oi.order_id
    WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) IN (2017, 2018)
    GROUP BY
        EXTRACT(YEAR FROM o.order_purchase_timestamp),
        EXTRACT(MONTH FROM o.order_purchase_timestamp)
)
SELECT
    year,
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY year, month) AS prev_month_revenue,
    ROUND(
        100.0 * (revenue - LAG(revenue) OVER (ORDER BY year, month))
        / LAG(revenue) OVER (ORDER BY year, month)
    , 2) AS mom_growth_pct
FROM monthly_revenue
ORDER BY year, month;
-- Result: 24 months (Jan 2017 - Dec 2018)
-- Highest growth: Nov 2017 (+59.77%) - Black Friday effect
-- January 2017 shows NULL for prev_month and growth (no previous month - expected)
-- Post Aug 2018 shows sharp decline due to incomplete dataset
-- (orders placed late 2018 not yet marked delivered when data was captured)