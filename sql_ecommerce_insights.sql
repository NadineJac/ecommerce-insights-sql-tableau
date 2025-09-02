/*
*******************************************************************************
E-commerce Case Study:
Exploring a potential collaboration between ENIAC and Magist
*******************************************************************************

Schema:
- products
- product_category_name_translation
- sellers
- customers
- geo
- orders
- order_items
- order_payments
- order_reviews

Note: All prices are in Euros.
*/

USE magist123;

-------------------------------------------------------------------------------
-- 1. Orders Overview
-------------------------------------------------------------------------------

-- Orders by status (summary table)
SELECT 
    order_status,
    COUNT(order_id) AS num_orders,
    ROUND(COUNT(order_id) * 100.0 / (SELECT COUNT(*) FROM orders), 2) AS pct_orders
FROM orders
GROUP BY order_status
ORDER BY num_orders DESC;

-- Orders over time (user growth)
SELECT 
    YEAR(order_purchase_timestamp) AS order_year,
    MONTH(order_purchase_timestamp) AS order_month,
    COUNT(DISTINCT order_id) AS num_orders,
    COUNT(DISTINCT customer_id) AS num_customers
FROM orders
GROUP BY order_year, order_month
ORDER BY order_year, order_month;

-- Order date range (summary)
SELECT 
    MIN(DATE(order_purchase_timestamp)) AS first_order,
    MAX(DATE(order_purchase_timestamp)) AS last_order,
    TIMESTAMPDIFF(MONTH,
        MIN(order_purchase_timestamp),
        MAX(order_purchase_timestamp)) AS duration_months,
    COUNT(DISTINCT order_id) AS total_orders
FROM orders;

-------------------------------------------------------------------------------
-- 2. Products Overview
-------------------------------------------------------------------------------

-- Total products vs products in transactions
SELECT 
    (SELECT COUNT(DISTINCT product_id) FROM products) AS total_products,
    (SELECT COUNT(DISTINCT product_id) FROM order_items) AS products_in_orders;

-- Product categories with most products
SELECT 
    t.product_category_name_english AS category,
    COUNT(DISTINCT p.product_id) AS num_products
FROM products p
LEFT JOIN product_category_name_translation t USING (product_category_name)
GROUP BY t.product_category_name_english
ORDER BY num_products DESC
LIMIT 10;

-- Product price range (overall)
SELECT 
    MIN(price) AS min_price,
    MAX(price) AS max_price,
    ROUND(AVG(price), 2) AS avg_price
FROM order_items;

-------------------------------------------------------------------------------
-- 3. Payments Overview
-------------------------------------------------------------------------------

-- Payment values
SELECT 
    MIN(payment_value) AS min_payment_value,
    MAX(payment_value) AS max_payment_value,
    ROUND(AVG(payment_value), 2) AS avg_payment_value
FROM order_payments;

-------------------------------------------------------------------------------
-- 4. Define Technology Categories
-------------------------------------------------------------------------------
CREATE TEMPORARY TABLE tech_products AS
SELECT 
    p.product_id,
    p.product_category_name,
    t.product_category_name_english
FROM products p
LEFT JOIN product_category_name_translation t USING (product_category_name)
WHERE t.product_category_name_english IN (
    'computers_accessories',
    'telephony',
    'electronics',
    'audio',
    'tablets_printing_image',
    'pc_gamer',
    'computers'
);

-------------------------------------------------------------------------------
-- 5. Tech vs Overall Share
-------------------------------------------------------------------------------

-- Products: overall vs tech
SELECT 
    COUNT(DISTINCT oi.product_id) AS total_products_sold,
    COUNT(DISTINCT tp.product_id) AS tech_products_sold,
    ROUND(COUNT(DISTINCT tp.product_id) * 100.0 / COUNT(DISTINCT oi.product_id), 2) AS pct_tech_products
FROM order_items oi
LEFT JOIN tech_products tp USING (product_id);

-- Sellers: overall vs tech
SELECT 
    COUNT(DISTINCT s.seller_id) AS total_sellers,
    COUNT(DISTINCT CASE WHEN tp.product_id IS NOT NULL THEN s.seller_id END) AS tech_sellers,
    ROUND(COUNT(DISTINCT CASE WHEN tp.product_id IS NOT NULL THEN s.seller_id END) * 100.0 / COUNT(DISTINCT s.seller_id), 2) AS pct_tech_sellers
FROM sellers s
LEFT JOIN order_items oi USING (seller_id)
LEFT JOIN tech_products tp USING (product_id);

-- Revenue: overall vs tech
SELECT 
    SUM(CASE WHEN o.order_status NOT IN ('unavailable','canceled') THEN oi.price END) AS total_revenue,
    SUM(CASE WHEN tp.product_id IS NOT NULL AND o.order_status NOT IN ('unavailable','canceled') THEN oi.price END) AS tech_revenue,
    ROUND(SUM(CASE WHEN tp.product_id IS NOT NULL AND o.order_status NOT IN ('unavailable','canceled') THEN oi.price END) 
          * 100.0 / SUM(CASE WHEN o.order_status NOT IN ('unavailable','canceled') THEN oi.price END), 2) AS pct_tech_revenue
FROM order_items oi
JOIN orders o USING (order_id)
LEFT JOIN tech_products tp USING (product_id);

-------------------------------------------------------------------------------
-- 6. Product Prices (with categories)
-------------------------------------------------------------------------------

-- Overall vs tech product prices
SELECT 
    'All Products' AS category,
    MIN(oi.price) AS min_price,
    MAX(oi.price) AS max_price,
    ROUND(AVG(oi.price), 2) AS avg_price
FROM order_items oi
UNION ALL
SELECT 
    'Tech Products',
    MIN(oi.price),
    MAX(oi.price),
    ROUND(AVG(oi.price), 2)
FROM order_items oi
JOIN tech_products tp USING (product_id);

-- Tech product popularity by price segment
SELECT 
    CASE
        WHEN oi.price > 500 THEN 'Expensive'
        WHEN oi.price > 100 THEN 'Mid-range'
        ELSE 'Cheap'
    END AS price_segment,
    COUNT(*) AS num_items,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_items,
    ROUND(AVG(oi.price), 2) AS avg_price
FROM order_items oi
JOIN tech_products tp USING (product_id)
GROUP BY price_segment
ORDER BY MIN(oi.price);

-------------------------------------------------------------------------------
-- 7. Delivery Performance
-------------------------------------------------------------------------------

-- Average delivery times
SELECT 
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_approved_at))) AS avg_days,
    ROUND(MIN(DATEDIFF(order_delivered_customer_date, order_approved_at))) AS min_days,
    ROUND(MAX(DATEDIFF(order_delivered_customer_date, order_approved_at))) AS max_days
FROM orders
WHERE order_delivered_customer_date IS NOT NULL;

-- On-time vs delayed deliveries (summary table)
SELECT 
    CASE
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) <= 0 THEN 'On Time'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) > 3 THEN 'Too Delayed (>3d)'
        ELSE 'Delayed (1-3d)'
    END AS delivery_category,
    COUNT(order_id) AS num_orders,
    ROUND(COUNT(order_id) * 100.0 / (SELECT COUNT(*) FROM orders WHERE order_status='delivered'), 2) AS pct_orders
FROM orders
WHERE order_status = 'delivered'
GROUP BY delivery_category
ORDER BY num_orders DESC;

-- Delivery delays by product size
SELECT 
    CASE
        WHEN product_weight_g >= 10000
             AND product_length_cm * product_height_cm * product_width_cm >= 50000
        THEN 'Big'
        WHEN product_weight_g <= 1000
             AND product_length_cm * product_height_cm * product_width_cm <= 10000
        THEN 'Small'
        ELSE 'Medium'
    END AS size_category,
    CASE
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) <= 0 THEN 'On Time'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) > 3 THEN 'Too Delayed (>3d)'
        ELSE 'Delayed (1-3d)'
    END AS delivery_category,
    COUNT(order_id) AS num_orders
FROM orders
JOIN order_items USING (order_id)
JOIN products USING (product_id)
WHERE order_status = 'delivered'
GROUP BY size_category, delivery_category
ORDER BY size_category, delivery_category;