# 🛒 E-Commerce Business Intelligence & Customer Analytics (Olist Dataset)

[![Database: PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL-336791?style=for-the-badge&logo=postgresql&logoColor=white)](#)
[![Language: SQL](https://img.shields.io/badge/Language-SQL-CC292B?style=for-the-badge&logo=sqlite&logoColor=white)](#)
[![Tool: pgAdmin 4](https://img.shields.io/badge/Tool-pgAdmin_4-326690?style=for-the-badge&logo=postgresql&logoColor=white)](#)
[![Analytics: RFM & Cohorts](https://img.shields.io/badge/Analytics-RFM_%26_Cohort-2ea44f?style=for-the-badge)](#)

---

## 📌 Project Overview
This repository contains an advanced **PostgreSQL-based Data Analytics Portfolio Project** built on the Brazilian E-Commerce public dataset by **Olist** (100k+ orders from 2016 to 2018).

The project moves beyond basic querying to deliver actionable business intelligence for executive decision-makers, addressing:
- **Revenue & Growth Dynamics** (7-day and 30-day moving sales averages)
- **Customer Value & Segmentation** (RFM scoring using statistical quintiles)
- **Retention & Churn Dynamics** (Month-over-month cohort retention analysis)
- **Supply Chain & Logistics SLAs** (Vendor-level delivery delay and bottleneck detection)
- **Product Quality Paradoxes** (Analyzing low reviews on early/on-time deliveries)

---

## 📁 Repository Structure

```text
olist-ecommerce-sql-analysis/
│
├── sql/
│   └── olist_ecommerce_analysis.sql   # Complete, production-grade SQL script
│
├── docs/
│   └── business_insights.md           # In-depth executive summary & recommendations
│
└── README.md                          # Project documentation & analysis walkthrough
```

---

## 📊 Dataset Schema & Entity Relationships
The Olist dataset models real-world marketplace operations with 8 relational tables:
- **`orders`**: Order lifecycle tracking, status (`delivered`, `canceled`, etc.), timestamps.
- **`customers`**: Unique customer identifiers and demographic location (state/city).
- **`order_payments`**: Transaction breakdown by type (`credit_card`, `boleto`, `voucher`, etc.) and installment details.
- **`order_items`**: Line-item details connecting orders, products, and sellers with pricing/freight.
- **`products`**: Product dimensions and category taxonomies.
- **`order_reviews`**: Customer satisfaction review scores (1 to 5) and feedback timestamps.
- **`sellers`**: Merchant details and geographic location.
- **`geolocation`**: Zip code prefixes mapped to latitude and longitude coordinates.

---

## 🔍 Key Business Analysis & SQL Techniques

### 1. RFM Customer Segmentation (Recency, Frequency, Monetary)
Identifies high-value enterprise accounts and dormant segments for targeted marketing.
* **Technique:** Common Table Expressions (CTEs), `DATE_PART()`, and `NTILE(5)` window ranking.
* **Output:** RFM quintile scores (e.g., `555` champions down to `111` at-risk customers).

```sql
WITH customer_rfm_raw AS (
    SELECT 
        c.customer_unique_id,
        DATE_PART('day', (SELECT MAX(order_purchase_timestamp::timestamp) FROM orders) - MAX(o.order_purchase_timestamp::timestamp)) AS recency_days,
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
        recency_days, frequency, monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM customer_rfm_raw
)
SELECT customer_unique_id, recency_days, frequency, ROUND(monetary, 2) AS monetary,
       CONCAT(r_score, f_score, m_score) AS rfm_cell
FROM rfm_scores
ORDER BY monetary DESC;
```

---

### 2. Trend & Seasonality Analysis (7-Day & 30-Day Moving Averages)
Smooths short-term day-of-week demand variance to track real quarterly growth.
* **Technique:** `AVG(...) OVER (ORDER BY order_date ROWS BETWEEN X PRECEDING AND CURRENT ROW)`.

```sql
SELECT 
    order_date,
    ROUND(daily_sales, 2) AS daily_sales,
    ROUND(AVG(daily_sales) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS moving_avg_7_days,
    ROUND(AVG(daily_sales) OVER (ORDER BY order_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW), 2) AS moving_avg_30_days
FROM daily_revenue
ORDER BY order_date;
```

---

### 3. Customer Cohort Retention Analysis
Tracks repeat purchase retention rates across the January 2017 acquisition cohort across months M0, M1, M2, and M3.
* **Technique:** Multi-table self-joins, timestamp formatting (`TO_CHAR`), and aggregation.

---

### 4. Supply Chain & Seller SLA Bottleneck Detection
Flags high-risk merchants with late delivery rates exceeding 20% of their total order volume.
* **Technique:** Conditional aggregation (`COUNT(CASE WHEN ...)`), interval arithmetic, and ratio calculations.

```sql
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
```

---

### 5. On-Time Delivery Paradox Analysis
Identifies orders delivered on or before the promised delivery date that still received negative customer ratings (1 or 2 stars).
* **Insight:** Proves that customer dissatisfaction is caused by product quality, defective items, or misleading catalog images rather than courier/logistics delays.

---

## 📈 Executive Insights & Recommendations

| Business Domain | Core Finding | Strategic Action |
|---|---|---|
| **Logistics / SLAs** | Top 10 delayed sellers account for delay rates > 20% (average 10-15+ days late). | Implement seller performance penalties or automated delisting for chronic SLA breaches. |
| **Product Experience** | High volume of negative reviews occurred on early/on-time deliveries. | Audit vendor packaging and description accuracy for categories with high return/dissatisfaction rates. |
| **Payment Preferences** | Credit card payments generate the largest share of high-ticket transactions. | Introduce promotional cashback / zero-interest installment options for credit card users. |
| **Retention** | High initial drop-off observed in Month 1 post-acquisition. | Launch personalized post-purchase email onboarding workflows and win-back offers within 30 days. |

---

## 🚀 How to Run the Project
1. **Clone or Download** this repository.
2. Open **pgAdmin 4** (or connect via `psql`).
3. Ensure the **Olist Brazilian E-Commerce dataset** tables are imported into your `public` schema.
4. Open [`sql/olist_ecommerce_analysis.sql`](./sql/olist_ecommerce_analysis.sql) in the Query Tool.
5. Execute the queries sequentially to review business metrics and insights.

---

## 📬 Contact & Connect
- **Author:** Kanha Sharma
- **GitHub:** [@kanhasharmamathura002-ops](https://github.com/kanhasharmamathura002-ops)
- **LinkedIn:** [LinkedIn Profile](https://linkedin.com)

*If you found this analysis helpful or insightful, please consider starring ⭐ this repository!*
