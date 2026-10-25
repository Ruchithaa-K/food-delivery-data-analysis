# Food Delivery Business Analysis using SQL


> Analyzed a food delivery database in MySQL to uncover revenue trends, customer ordering patterns and top-performing restaurants, using JOINs, aggregate functions, GROUP BY, subqueries, CTEs and window functions.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Tools and SQL Skills](#2-tools-and-sql-skills)
3. [Key Findings](#3-key-findings)
4. [Database Schema](#4-database-schema)
5. [Data Validation](#5-data-validation)
6. [Business Questions, Queries and Insights](#6-business-questions-queries-and-insights)
   - [A. Core business metrics](#a-core-business-metrics)
   - [B. Restaurant and customer performance ](#b-restaurant-and-customer-performance-joins)
   - [C. Above-Average Performers and Customer Loyalty](#c-Above-Average-Performers-and-Customer-Loyalty)
   - [D. Customer segmentation](#d-customer-segmentation)
   - [E. Rankings and Trends Over Time](#e-rankings-and-trends-over-time)
7. [Assumptions and Known Limitations](#7-assumptions-and-known-limitations)
8. [Project Structure and How to Run](#8-project-structure-and-how-to-run)
9. [Next Steps](#9-next-steps)

---

## 1. Project Overview

**Business problem:** A food delivery company wants to know where its revenue comes from, how customers behave, and which restaurants drive growth or cause problems.

**Goals**
- Measure core KPIs: revenue, orders, average order value, cancellation rate.
- Find the best and worst performing restaurants and cuisines.
- Understand customer spending, loyalty and repeat behavior.
- Track revenue trends month over month.

**Dataset (sample data built for this project)**

| Item | Size |
|---|---|
| Customers | 15 |
| Restaurants | 8 |
| Orders | 30 (27 delivered, 3 cancelled) |
| Order items | 37 |
| Payments | 27 (one per delivered order) |
| Period | 5 January 2026 to 10 June 2026 |
| Total revenue | 12,420 |

Patterns were built into the data on purpose: one restaurant with no orders, one customer who never ordered, one customer with only a cancelled order, and one restaurant with an unusually high cancellation rate.

---

## 2. Tools and SQL Skills

**Tools:** MySQL 8, MySQL Workbench (queries and ER diagram), Git and GitHub.

Skills

Aggregate functions (`SUM`, `AVG`, `COUNT`) 
`GROUP BY` and `HAVING` 
Multi-table `JOIN`s (inner and left) 
`GROUP_CONCAT` 
Subqueries (scalar, nested, derived tables) 
CTEs (including chained CTEs) 
`CASE` expressions and conditional aggregation 
Window functions (`RANK`, `LAG`, `SUM() OVER`) 
Window function over an aggregate functions

---

## 3. Key Findings

1. **Revenue is 12,420 from 27 delivered orders**, an average order value of 460.
2. **UPI is the leading payment method**, with 48.9% of revenue and 16 of 27 transactions.
3. **Indian cuisine earns 56% of revenue** (6,980 of 12,420). Biryani House alone brings in 34.5%.
4. **Burger Barn cancels 50% of its orders**, five times the 10% company average, and accounts for 2 of the 3 cancellations.
5. **Revenue is concentrated in a few customers.** Four "High" customers (31% of paying customers) generate 57.8% of revenue.
6. **About 62% of paying customers ordered again** (8 of 13), so retention is decent, but 5 customers ordered only once.
7. **Revenue peaked in February** (2,700) and slowed from March to May. June is incomplete (data ends on 10 June).

---

## 4. Database Schema

```
customers (1) ───< orders >─── (1) restaurants
                     │
         ┌───────────┴───────────┐
     order_items (many)      payments (1 per delivered order)
```

| Table | Description | Key columns |
|---|---|---|
| `customers` | Customer details | `customer_id` (PK), `customer_name`, `city`, `signup_date` |
| `restaurants` | Restaurant details | `restaurant_id` (PK), `restaurant_name` (unique), `cusine_type`, `city`, `rating` |
| `orders` | One row per order | `order_id` (PK), `customer_id` (FK, not null), `restaurant_id` (FK, not null), `order_date`, `order_status`, `delivery_time` (minutes) |
| `order_items` | One row per dish in an order | `item_id` (PK), `order_id` (FK), `item_name`, `quantity`, `price` |
| `payments` | One row per delivered order | `payment_id` (PK), `order_id` (FK), `payment_method` (upi, cash, card), `amount`, `discount` |

**Relationships**
- One customer places many orders. One restaurant receives many orders.
- One order has many items and one payment (cancelled orders have no payment).
- `orders` is the central table. Items reach their restaurant through `orders`, so the restaurant is stored once per order and not repeated on every dish (normalization).

> **Note:** the column is spelled `cusine_type` in the table, and every query uses that spelling.

---

## 5. Data Validation

Before analysis, I checked that the stored payment amount equals the items total minus the discount for every order.

```sql
-- Does the sum of quantity * price minus discount equal the stored amount for every order?
select count(*) as mismatch_count
from (
    select o.order_id
    from orders o
    inner join order_items oi on o.order_id = oi.order_id
    inner join payments p on o.order_id = p.order_id
    group by o.order_id, p.amount, p.discount
    having sum(oi.quantity * oi.price) - p.discount <> p.amount
) as mismatched;
```

**Result:** `mismatch_count = 0` (PASS).

**How it works**
- `order_items` has many rows per order, so the items are summed per order (`group by o.order_id`) before comparing with the single payment row.
- `p.amount` and `p.discount` are in the `GROUP BY` because `payments.order_id` is not declared unique, so MySQL cannot prove one value per order. This is the functional dependency rule.
- The outer `count(*)` turns "no rows" into an explicit `0`.
- The check was tested by changing one payment by 10, confirming the order appeared, and reverting it.

**Insight:** all 27 payments reconcile with their items, so revenue figures can be trusted. Cancelled orders have items but no payment, as designed.

---

## 6. Business Questions, Queries and Insights

Rule used throughout: **revenue counts delivered orders only.** Cancelled orders have no payment row, so joining to `payments` excludes them automatically.

### A. Core business metrics

#### Q1. What are the total revenue, delivered orders, average order value and cancellation rate?

```sql
-- Total revenue
select sum(amount) as total_revenue from payments;

-- Delivered orders
select sum(order_status = 'Delivered') as delivered_orders from orders;

-- Overall cancellation rate
select round((sum(order_status <> 'Delivered') / count(*)) * 100, 2) as cancellation_rate
from orders;

-- Average order value
select sum(if(o.order_status = 'Delivered', p.amount, 0)) / count(o.order_id) as average_order_value
from orders o
inner join payments p on o.order_id = p.order_id;
```

| total_revenue | delivered_orders | cancellation_rate | average_order_value |
|---|---|---|---|
| 12,420 | 27 | 10.00 | 460.00 |

**How it works**
- A comparison such as `order_status = 'Delivered'` returns 1 or 0, so `sum()` counts matching rows and `avg()` gives a rate.
- The cancellation rate is calculated from `orders` (all 30 orders), because it needs cancelled orders in the denominator. Revenue and average order value come from `payments`, which only has delivered orders.

**Insight:** the business earned 12,420 from 27 delivered orders (460 per order), and loses 1 in 10 orders to cancellation. Each cancelled order is lost revenue, so cutting cancellations is a direct revenue lever.

#### Q2. What is the monthly revenue and order count?

```sql
select date_format(o.order_date, '%Y-%m') as month,
       sum(p.amount) as monthly_revenue,
       count(o.order_id) as monthly_order_count
from payments p
inner join orders o on p.order_id = o.order_id
group by date_format(o.order_date, '%Y-%m')
order by date_format(o.order_date, '%Y-%m');
```

| month | monthly_revenue | monthly_order_count |
|---|---|---|
| 2026-01 | 1,750 | 4 |
| 2026-02 | 2,700 | 5 |
| 2026-03 | 2,460 | 6 |
| 2026-04 | 2,550 | 5 |
| 2026-05 | 2,080 | 5 |
| 2026-06 | 880 | 2 |

**How it works:** `date_format(..., '%Y-%m')` converts each order date to a year-month label, so January 2026 and January 2027 never merge. The monthly rows add up to 12,420 and 27 orders, matching Q1.

**Insight:** February is the strongest month. March has the most orders (6) but lower revenue than February, so average order value dropped. June covers only 10 days, so its low figure reflects incomplete data.

#### Q3. Which payment method brings in the most revenue?

```sql
select payment_method, sum(amount) as revenue, count(order_id) as transaction_count
from payments
group by payment_method
order by revenue desc;
```

| payment_method | revenue | transaction_count |
|---|---|---|
| upi | 6,070 | 16 |
| card | 4,640 | 7 |
| cash | 1,710 | 4 |

**Insight:** UPI brings 48.9% of revenue and 59% of transactions. UPI cashback or offers would reach the largest share of customers. Cash is only 4 of 27 orders (about 15%), which means little cash-handling risk for delivery partners.

### B. Restaurant and customer performance

#### Q4. For each restaurant, what are the total orders, revenue and average delivery time?

```sql
select 
	r.restaurant_name,r.restaurant_id, -- this works because of functional dependency exists btw id and name!!
	count(o.order_id) as total_orders ,sum(p.amount) as total_revenue ,avg(o.delivery_time) as average_delivery_time
from orders o
inner join restaurants r on r.restaurant_id=o.restaurant_id
inner join payments p on p.order_id=o.order_id
group by r.restaurant_id
order by r.restaurant_id;
```


**How it works:** three tables are joined, and each `on` condition links a parent to its child (`orders.restaurant_id` to `restaurants`, `payments.order_id` to `orders`). Selecting `restaurant_name` while grouping only by `restaurant_id` is valid in MySQL 8 because of functional dependency: the primary key fixes one name per group.

**Insight:** Biryani House leads with 4,290 (34.5% of revenue). Pizza Hub has the slowest deliveries (about 42 minutes) and Dosa Corner the fastest (about 25 minutes). Dosa Corner has as many orders as Pizza Hub but less than half its revenue, because its dishes are cheaper. Tandoori Tales is absent because it has no orders

#### Q5. Which cuisine type generates the most revenue?

```sql
select r.cusine_type,sum(p.amount) as cuisine_revenue
from restaurants r
inner join orders o on r.restaurant_id=o.restaurant_id
inner join payments p on o.order_id=p.order_id
group by r.cusine_type
order by cuisine_revenue desc;
```

| cusine_type | cuisine_revenue |
|---|---|
| Indian | 6,980 |
| Italian | 2,260 |
| Chinese | 1,600 |
| South Indian | 830 |
| Fast Food | 750 |

**Insight:** Indian cuisine produces 56.2% of revenue, driven by Biryani House and Spice Garden. Here `cusine_type` is not unique to a restaurant, so it must appear in the `GROUP BY`. Fast Food is the smallest category, and its only active restaurant (Burger Barn) also has the worst cancellation rate (Q8).

#### Q6. Which restaurants have received no orders, and which customers have never ordered?

```sql
-- Restaurants with no orders
select r.restaurant_name
from restaurants r
left join orders o on r.restaurant_id=o.restaurant_id
where o.order_id is null
order by r.restaurant_name;

-- Customers who never placed an order
select c.customer_name
from customers c
left join orders o on c.customer_id = o.customer_id
where o.order_id is null;
```


**How it works:** a `LEFT JOIN` keeps every row from the left table. Where there is no match, the right-side columns are NULL, so `where o.order_id is null` keeps only the unmatched rows. An inner join would hide these rows.

**Insight:** Tandoori Tales (Guntur, rating 4.1) is listed but has not received a single order, so it needs visibility or promotion, or a check that it is active. Naveen Raju signed up on 30 December 2025 and never ordered, which suggests an onboarding nudge such as a first-order coupon.


#### Q7. Show each order with customer, restaurant, items and amount paid

```sql
select c.customer_name,
       r.restaurant_name,
       p.amount,
       group_concat(oi.item_name order by oi.item_name separator ', ') as order_items,
       o.order_date
from orders o
join customers c    on o.customer_id = c.customer_id
join restaurants r  on o.restaurant_id = r.restaurant_id
join payments p     on o.order_id = p.order_id
join order_items oi on oi.order_id = o.order_id
group by o.order_id, c.customer_name, r.restaurant_name, p.amount, o.order_date
order by c.customer_name, o.order_id;
```


**Result:** 27 rows, one per delivered order. For example, order 1009 shows Arjun Rao at Spice Garden with `Butter Naan, Dal Tadka` and an amount of 380.

**How it works:** joining to `order_items` produces one row per dish (34 rows for delivered orders), which is the wrong level of detail for "each order". Grouping by `o.order_id` collapses the dishes back to one row, and `group_concat` joins the dish names into a single text cell. The grain of the result (one row per order) was verified by checking the row count (27).

**Insight:** only 7 of the 27 delivered orders (26%) contain more than one dish, and their average value (about 431) is below the overall average of 460. Most customers order a single dish, so suggesting sides and drinks at checkout is an easy way to increase order value.

#### Q8. Which restaurants have a cancellation rate above the overall rate?

```sql
select r.restaurant_id, r.restaurant_name,
       round(avg(o.order_status = 'Cancelled') * 100, 2) as restaurant_cancellation_rate
from orders o
inner join restaurants r on o.restaurant_id = r.restaurant_id
group by r.restaurant_id
having avg(o.order_status = 'Cancelled') * 100 > (
    select avg(order_status = 'Cancelled') * 100 from orders
)
order by restaurant_cancellation_rate desc;
```

**How it works:** `avg(condition)` gives the share of rows where the condition is true. The subquery returns the overall 10%, calculated once. `HAVING` is used because the rate only exists after grouping.

**Insight:** Burger Barn cancelled 2 of its 4 orders (50%), five times the company average, which points to an operational issue such as stock-outs or slow order acceptance. Dragon Wok (1 of 3 orders) is also above average, but the sample is too small for a firm conclusion, so it should be monitored.

### C. Above-Average Performers and Customer Loyalty

#### Q9. Which customers spent more than the average customer spend?

```sql
with avg_customer as (
    select o.customer_id, sum(p.amount) as amount_spent
    from payments p
    inner join orders o on o.order_id = p.order_id
    group by o.customer_id
)
select c.customer_name, a.amount_spent
from customers c
inner join avg_customer a on a.customer_id = c.customer_id
group by c.customer_id
having a.amount_spent > (select round(avg(amount_spent), 2) from avg_customer)
order by a.amount_spent desc, c.customer_id;
```

**How it works:** the CTE first builds one total per customer. The benchmark is the **average of those totals** (955.38), not the average order value (460). Comparing a customer's total with the per-order average was a mistake caught during development, because it returned 9 customers instead of 5.

**Insight:** five of the 13 paying customers account for 8,330 of the 12,420 revenue (67%). Ravi Kumar alone contributes about 18%.

*Assumption:* the average covers the 13 customers who paid at least once. This is the ARPPU (average revenue per paying user) definition. Using all 15 registered customers would give 828, and the same five customers would qualify.

#### Q10. Which customers ordered from more than one restaurant?

```sql
select c.customer_name, c.customer_id,
       count(distinct o.restaurant_id) as different_restaurants_count
from orders o
inner join customers c on o.customer_id = c.customer_id
group by c.customer_id
having count(distinct o.restaurant_id) > 1
order by c.customer_id;
```



**How it works:** `count(distinct restaurant_id)` counts each restaurant once per customer. Without `distinct`, Divya Teja (2 orders, both at Biryani House) would wrongly appear.

**Insight:** 6 of the 14 customers who placed an order tried two or more restaurants, so many customers are not loyal to a single restaurant. Platform-wide offers such as free delivery encourage them to keep ordering, while restaurant-specific loyalty deals suit the single-restaurant customers.

*Assumption:* cancelled orders count as "ordered from". Excluding them keeps the same six customers.

#### Q11. Which restaurants earn more than the average restaurant revenue?

```sql
with avg_restaurant as (
    select o.restaurant_id, sum(p.amount) as revenue
    from orders o
    inner join payments p on o.order_id = p.order_id
    group by o.restaurant_id
)
select r.restaurant_name, a.revenue
from restaurants r
inner join avg_restaurant a on r.restaurant_id = a.restaurant_id
where a.revenue > (select avg(revenue) from avg_restaurant)
order by a.revenue desc;
```


**How it works:** the CTE gives one revenue row per restaurant, so the plain `where` filter is enough, and no `GROUP BY` is needed. The average (1,774.29) is the average of restaurant totals across the 7 restaurants with revenue.

**Insight:** three of the seven active restaurants bring in 9,240 of the 12,420 revenue (about 74%). Revenue is concentrated in a few restaurants, which deserve priority for promotions and retention, while the other four could be reviewed for growth opportunities.

#### Q12. What percentage of customers ordered more than once (repeat rate)?

```sql
-- Repeat rate = customers with 2+ delivered orders / customers with at least 1 delivered order
with repeat_customers as (
    select customer_id, count(*) as repeat_count
    from orders
    where order_status = 'Delivered'
    group by customer_id
)
select (sum(if(repeat_count > 1, 1, 0)) / count(*)) * 100 as repeat_rate
from repeat_customers;
```

**Result:** 8 repeat customers out of 13, a repeat rate of **61.54%**.

**How it works:** the `WHERE` filter sits inside the CTE, so customers whose only order was cancelled (Suresh Yadav) never get a row and are not in the denominator. Moving the delivered rule into an `IF` in the outer query would have kept him in the denominator and given a different answer (14 customers, 64.29%). `WHERE` decides which rows exist, while `IF` only changes what a row contributes.

**Insight:** about 62% of paying customers come back. The five customers who ordered only once (Priya Sharma, Mahesh Varma, Rahul Chowdary, Vamsi Krishna and Pooja Singh) are the target for a second-order coupon. Combined with the activation rate (13 of 15 registered customers placed a delivered order, 86.67%), the funnel is 15 registered, 13 paying, 8 repeat.

### D. Customer segmentation

#### Q13. Segment customers into High, Medium and Low value and show each segment's share of revenue

**Thresholds (data-driven, so they scale as the data grows):**
- **High:** total spend at least 1.5 times the average customer spend
- **Medium:** total spend at least the average, but below High
- **Low:** below the average

*Why not fixed numbers or "% of total revenue"?* Fixed amounts stop making sense as the data grows, and a customer's share of total revenue shrinks as the customer base grows, so everyone would end up in "Low". Multiples of the average adapt automatically.

```sql
with customer_spend as (
    select o.customer_id,
           sum(p.amount) as total_spend,
           avg(sum(p.amount)) over () as avg_spend
    from orders o
    join payments p on o.order_id = p.order_id
    group by o.customer_id
),
segmented as (
    select customer_id, total_spend,
           case
               when total_spend >= 1.5 * avg_spend then 'High'
               when total_spend >= avg_spend then 'Medium'
               else 'Low'
           end as customer_category
    from customer_spend
)
-- (a) Customer-level detail
select c.customer_id, c.customer_name,
       s.total_spend as revenue,
       s.customer_category,
       round(s.total_spend / sum(s.total_spend) over () * 100, 2) as pct_of_revenue
from segmented s
inner join customers c on s.customer_id = c.customer_id
order by field(s.customer_category, 'High', 'Medium', 'Low'), s.total_spend desc;
```

```sql
-- (b) Segment-level summary (same two CTEs as above)
select customer_category,
       count(*) as customers,
       sum(total_spend) as revenue,
       round(sum(total_spend) / sum(sum(total_spend)) over () * 100, 2) as pct_of_revenue
from segmented
group by customer_category
order by field(customer_category, 'High', 'Medium', 'Low');
```


**How it works**
- `avg(sum(p.amount)) over ()`: `GROUP BY` first creates one total per customer, then the window function averages those totals (955.38) without a separate query. The empty `over ()` means the whole result is one window.
- `CASE` checks branches top to bottom and stops at the first match, so the strictest condition (High) comes first.
- `sum(...) over ()` keeps every row and repeats the grand total (12,420) on each, so each row can divide its own value by it. At segment level, the nested `sum(sum(...)) over ()` is needed because a `GROUP BY` is present.
- Two CTEs are used because the segment label only exists after customer totals do, and the segment summary groups on that label.

**Insight:** four of the 13 paying customers (31%) bring in nearly 58% of revenue, while the eight Low customers contribute 33%. The middle group is thin, so the business depends on a few high spenders. A loyalty offer for the High group protects most of the income, and a second-order coupon could move Low customers upward.

### E. Rankings and Trends Over Time

#### Q14. Rank restaurants by revenue within each city

```sql
with restaurant_revenues as (
    select o.restaurant_id, sum(p.amount) as revenue
    from orders o
    inner join payments p on o.order_id = p.order_id
    group by o.restaurant_id
)
select r.city,
       r.restaurant_name,
       rr.revenue,
       rank() over (partition by r.city order by rr.revenue desc) as city_rank
from restaurant_revenues rr
join restaurants r on r.restaurant_id = rr.restaurant_id
order by r.city, city_rank;
```



**How it works:** `partition by r.city` restarts the ranking inside each city, and `order by ... desc` puts the highest revenue first. Without `partition by`, the query would produce one ranking across all cities. `rank()` leaves gaps after ties, while `dense_rank()` does not. There are no ties in this data, so both give the same result.

> **Note:** the earlier version of this query used `dense_rank() over (order by ...)` without `partition by`, which ranks across all restaurants and not within each city. The version above fixes that.

**Insight:** Biryani House (Hyderabad) and Spice Garden (Vijayawada) are the clear leaders in their cities. Burger Barn is Guntur's only active restaurant, and its top rank there reflects no competition, not strong performance (it has the worst cancellation rate). Guntur needs more active restaurants, since Tandoori Tales has no orders.

#### Q15. What is the month-over-month revenue growth percentage?

```sql
select *,
       round((current_month_revenue - previous_month_revenue)
             / nullif(previous_month_revenue, 0) * 100, 2) as growth_percentage
from (
    select date_format(o.order_date, '%Y-%m') as month_of_the_year,
           sum(p.amount) as current_month_revenue,
           lag(sum(p.amount)) over (order by date_format(o.order_date, '%Y-%m')) as previous_month_revenue
    from orders o
    inner join payments p on o.order_id = p.order_id
    group by date_format(o.order_date, '%Y-%m')
) as revenue_table;
```


**How it works**
- Formula: `(this month - last month) / last month x 100`. The divisor is the previous month, not the grand total.
- `lag(...)` brings the previous row's value onto the current row, and `order by` inside `over()` defines what "previous" means.
- `lag(sum(...))` works because window functions run after `GROUP BY`, so they can wrap an aggregate.
- `nullif(previous, 0)` returns NULL instead of a division error if a month had zero revenue.
- January has no previous month, so its growth is NULL.

**Insight:** revenue grew 54.29% from January to February, then fell in March (-8.89%), stayed roughly flat in April (+3.66%), and declined again in May (-18.43%). June's -57.69% is not a real decline, because the data ends on 10 June and the month is incomplete. The March to May slowdown is worth investigating for seasonality or reduced promotions.

---

## 8. Assumptions and Known Limitations

**Assumptions**
- Revenue and averages use **delivered orders only**.
- "Average customer spend" uses customers with at least one paid order (13), the ARPPU definition.
- Repeat rate uses delivered orders only, among customers with at least one delivered order (13).
- Cancelled orders are counted in the "ordered from more than one restaurant" question (Q10).

**Limitations**
- Small sample dataset (30 orders over 5 months), so patterns are illustrative and not statistically strong.
- June 2026 is incomplete (data ends on 10 June).
- `order_status` is not restricted by a constraint, so values must be typed consistently (`Delivered` or `Cancelled`).
- `payments.order_id` is not declared unique, so one payment per order is a data rule, not enforced by the schema.
- The column `cusine_type` is misspelled in the schema and kept as is for consistency across all queries.

---

## 9. Project Structure and How to Run

```
Project-1/
├── README.md                  # project documentation
├── er_diagram.png             # database ER diagram
├── Schema.sql                 # creates the database and tables
├── Data.sql                   # inserts the sample data
├── analysis_queries.sql       # all analysis queries 
└── screenshots/               # screenshots of query results
```

| File | Purpose |
|---|---|
| `schema.sql` | Creates the `analysis` database and the five tables in dependency order (customers, restaurants, orders, order_items, payments) |
| `data.sql` | Loads the sample data: 15 customers, 8 restaurants, 30 orders, 37 order items, 27 payments |
| `analysis_queries.sql` | Validation check and all business queries, grouped by topic |
| `er_diagram.png` | ER diagram exported from MySQL Workbench |
| `screenshots/` | Result screenshots for the key queries |

**To run**
1. Open MySQL Workbench (MySQL 8.0 or later is required for CTEs and window functions).
2. Run `schema.sql`.
3. Run `data.sql`. Expected row counts: 15, 8, 30, 37 and 27.
4. Run the validation query from section 5 and confirm it returns `0`.
5. Run the queries in `analysis_queries.sql` one at a time and compare the output with the results in this README.

---
## 10. Next Steps

**Still to add**
- Cumulative (running) revenue by date
- Order sequence per customer and days between consecutive orders
- Each order's amount against its restaurant's average, with a flag

**Stretch analyses**
- Month-to-month customer retention rate
- Churn risk (no order in the last 30 days of the dataset)
- Top 2 revenue-generating items per restaurant
- Share of revenue from the top 20% of customers
- 3-month moving average of revenue

**Improvements**
- Load a larger dataset (500+ orders) to make rankings and trends more meaningful
- Add a `menu_items` table linked to restaurants
- Add constraints for `order_status` and a unique `payments.order_id`
- Build a dashboard in Power BI or Tableau on top of these queries

---

## Author

**Your Name** · [LinkedIn](https://www.linkedin.com/in/ruchitha-kannegolla-8096872ba/) · [GitHub](https://github.com/Ruchithaa-K)
