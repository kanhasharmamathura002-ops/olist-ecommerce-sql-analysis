-- =====================================================================
-- Project: Brazilian E-Commerce (Olist) SQL Data Analysis
-- Database: PostgreSQL
-- Author: Data Analytics Portfolio Project
-- Description: End-to-end SQL analysis covering exploratory analysis, 
--              revenue metrics, customer RFM segmentation, moving averages,
--              cohort retention, and seller logistics performance.
-- =====================================================================

-- =====================================================================
-- SECTION 1: DATABASE & EXPLORATORY DATA ANALYSIS (EDA)
-- =====================================================================

-- 1.1 List all base tables in the public schema
SELECT 
    table_name 
FROM information_schema.tables
WHERE table_schema = 'public' 
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- 1.2 Inspect orders dataset structure
SELECT * 
FROM orders 
LIMIT 10;

-- 1.3 Count problematic orders (canceled or unavailable)
SELECT 
    order_status,
    COUNT(*) AS total_orders
FROM orders
WHERE order_status IN ('canceled', 'unavailable')
GROUP BY order_status;

-- 1.4 Credit card payment volume and total transaction value
SELECT 
    COUNT(*) AS total_credit_card_transactions, 
    ROUND(SUM(payment_value)::numeric, 2) AS total_payment_value 
FROM order_payments 
WHERE payment_type = 'credit_card';

-- 1.5 Top 10 customer cities and states by customer concentration
SELECT 
    customer_city,
    customer_state,
    COUNT(customer_id) AS total_customers 
FROM customers
GROUP BY customer_city, customer_state
ORDER BY total_customers DESC
LIMIT 10;


-- =====================================================================
-- SECTION 2: INTERMEDIATE BUSINESS PERFORMANCE & SALES METRICS
-- =====================================================================

-- 2.1 Highest revenue generating product category
SELECT 
    p.product_category_name,
    ROUND(SUM(oi.price)::numeric, 2) AS total_revenue 
FROM products p
JOIN order_items oi ON p.product_id = oi.product_id
GROUP BY p.product_category_name
ORDER BY total_revenue DESC
LIMIT 1;

-- 2.2 Average delivery duration for fulfilled orders
SELECT 
    AVG(AGE(order_delivered_customer_date::timestamp, order_purchase_timestamp::timestamp)) AS avg_delivery_time
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_status = 'delivered';

-- 2.3 Paradox Analysis: Orders delivered on or before estimated date with poor reviews (1 or 2 stars)
-- Insight: Identifies product quality or packaging defects rather than shipping delay issues.
SELECT 
    o.order_id,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    r.review_score
FROM orders o 
JOIN order_reviews r ON o.order_id = r.order_id 
WHERE o.order_delivered_customer_date IS NOT NULL 
  AND o.order_delivered_customer_date::timestamp <= o.order_estimated_delivery_date::timestamp 
  AND r.review_score::int IN (1, 2);

-- 2.4 Top 3 highest spending customers per state using Window Functions (DENSE_RANK)
WITH customer_spending AS (
    SELECT 
        c.customer_id,
        c.customer_state,
        SUM(op.payment_value::numeric) AS total_spend 
    FROM customers c 
    JOIN orders o ON o.customer_id = c.customer_id 
    JOIN order_payments op ON o.order_id = op.order_id
    GROUP BY c.customer_id, c.customer_state
), 
ranked_customers AS (
    SELECT 
        customer_id,
        customer_state,
        total_spend,
        DENSE_RANK() OVER (
            PARTITION BY customer_state 
            ORDER BY total_spend DESC
        ) AS rank_num
    FROM customer_spending
)
SELECT 
    customer_id,
    customer_state,
    ROUND(total_spend, 2) AS total_spend,
    rank_num  
FROM ranked_customers
WHERE rank_num <= 3 
ORDER BY customer_state, rank_num;

-- 2.5 Outperforming Sellers: Sellers generating revenue above the market average
WITH seller_revenue AS ( 
    SELECT 
        seller_id,
        SUM(price::numeric) AS total_revenue
    FROM order_items
    GROUP BY seller_id
)
SELECT 
    seller_id,
    ROUND(total_revenue, 2) AS total_revenue 
FROM seller_revenue
WHERE total_revenue > (
    SELECT AVG(total_revenue::numeric) 
    FROM seller_revenue
) 
ORDER BY total_revenue DESC;

-- 2.6 High-Volume, High-Rating Products (>= 50 sales with average rating > 4.0)
SELECT 
    oi.product_id,
    p.product_category_name,
    ROUND(AVG(r.review_score::numeric), 2) AS avg_score,
    COUNT(oi.order_item_id) AS total_sold 
FROM order_items oi
JOIN order_reviews r ON oi.order_id = r.order_id 
JOIN products p ON oi.product_id = p.product_id
GROUP BY oi.product_id, p.product_category_name 
HAVING COUNT(oi.order_item_id) >= 50 
   AND AVG(r.review_score::numeric) > 4.0 
ORDER BY avg_score DESC, total_sold DESC;

-- 2.7 Multi-Payment Method Transactions
-- Count of orders where the customer used more than one distinct payment method
SELECT 
    COUNT(*) AS total_multi_payment_orders  
FROM (
    SELECT order_id 
    FROM order_payments 
    GROUP BY order_id 
    HAVING COUNT(DISTINCT payment_type) > 1
) sub;


-- =====================================================================
-- SECTION 3: ADVANCED ANALYTICS & BUSINESS INTELLIGENCE
-- =====================================================================

-- 3.1 Customer RFM (Recency, Frequency, Monetary) Segmentation
-- Uses NTILE(5) quintiles to rank customers across RFM dimensions.
WITH max_date_cte AS (
    SELECT MAX(order_purchase_timestamp::timestamp) AS max_date 
    FROM orders
),
customer_rfm_raw AS (
    SELECT 
        c.customer_unique_id,
        DATE_PART('day', (SELECT max_date FROM max_date_cte) - MAX(o.order_purchase_timestamp::timestamp)) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(p.payment_value::numeric) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_payments p ON o.order_id = p.order_id
    GROUP BY c.customer_unique_id
),
rfm_scores AS (
    SELECT 
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM customer_rfm_raw
)
SELECT 
    customer_unique_id,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS monetary,
    r_score,
    f_score,
    m_score,
    CONCAT(r_score, f_score, m_score) AS rfm_cell
FROM rfm_scores
ORDER BY monetary DESC;

-- 3.2 Trend & Seasonality Analysis: 7-Day & 30-Day Moving Averages for Daily Sales
-- Smooths out weekend spikes and short-term volatility to identify underlying growth trajectories.
WITH daily_revenue AS (
    SELECT 
        o.order_purchase_timestamp::date AS order_date,
        SUM(p.payment_value::numeric) AS daily_sales
    FROM orders o
    JOIN order_payments p ON o.order_id = p.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY o.order_purchase_timestamp::date
)
SELECT 
    order_date,
    ROUND(daily_sales, 2) AS daily_sales,
    
    -- 7-Day Moving Average
    ROUND(
        AVG(daily_sales) OVER (
            ORDER BY order_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 
        2
    ) AS moving_avg_7_days,
    
    -- 30-Day Moving Average
    ROUND(
        AVG(daily_sales) OVER (
            ORDER BY order_date
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ), 
        2
    ) AS moving_avg_30_days
FROM daily_revenue
ORDER BY order_date;

-- 3.3 Customer Cohort Retention Analysis (January 2017 Cohort)
-- Tracks repeat purchase behavior of the Jan 2017 acquisition cohort across subsequent months.
WITH jan_cohort AS (
    SELECT 
        c.customer_unique_id,
        MIN(TO_CHAR(o.order_purchase_timestamp::timestamp, 'YYYY-MM')) AS first_order_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
    HAVING MIN(TO_CHAR(o.order_purchase_timestamp::timestamp, 'YYYY-MM')) = '2017-01'
)
SELECT 
    TO_CHAR(o.order_purchase_timestamp::timestamp, 'YYYY-MM') AS purchase_month,
    COUNT(DISTINCT c.customer_unique_id) AS active_customers
FROM jan_cohort jc
JOIN customers c ON jc.customer_unique_id = c.customer_unique_id
JOIN orders o ON c.customer_id = o.customer_id
WHERE TO_CHAR(o.order_purchase_timestamp::timestamp, 'YYYY-MM') IN ('2017-01', '2017-02', '2017-03', '2017-04')
GROUP BY TO_CHAR(o.order_purchase_timestamp::timestamp, 'YYYY-MM')
ORDER BY purchase_month;

-- 3.4 Seller Logistics & SLA Bottleneck Analysis
-- Identifies the top 10 sellers with severe late delivery rates (> 20% of orders delayed)
WITH seller_delivery_metrics AS (
    SELECT 
        oi.seller_id,
        COUNT(DISTINCT o.order_id) AS total_orders,
        
        -- Late orders count
        COUNT(DISTINCT CASE 
            WHEN o.order_delivered_customer_date::timestamp > o.order_estimated_delivery_date::timestamp 
            THEN o.order_id 
        END) AS late_orders,
        
        -- Average delay in days for late deliveries
        AVG(CASE 
            WHEN o.order_delivered_customer_date::timestamp > o.order_estimated_delivery_date::timestamp 
            THEN DATE_PART('day', o.order_delivered_customer_date::timestamp - o.order_estimated_delivery_date::timestamp)
        END) AS avg_days_late
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    GROUP BY oi.seller_id
)
SELECT 
    seller_id,
    total_orders,
    late_orders,
    ROUND((late_orders * 100.0 / total_orders), 2) AS late_delivery_rate_pct,
    ROUND(avg_days_late::numeric, 1) AS avg_delay_days
FROM seller_delivery_metrics
WHERE (late_orders * 100.0 / total_orders) > 20
ORDER BY late_delivery_rate_pct DESC, avg_delay_days DESC
LIMIT 10;
