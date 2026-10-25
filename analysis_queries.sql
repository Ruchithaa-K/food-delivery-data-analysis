use analysis;

-- Does the sum of quantity * price minus discount equal the stored amount for every order? List any mismatches. 
select count(*) from 
(
select o.order_id
from orders o
inner join order_items oi on o.order_id=oi.order_id
inner join payments p on o.order_id=p.order_id
group by o.order_id,p.amount,p.discount
having sum(oi.quantity*oi.price) -p.discount<> p.amount
) as mismatched;

-- What is the total revenue? 
	select sum(amount) as total_revenue
    from payments;
    
-- What is the total number of delivered orders?
    select sum(order_status = "delivered") as delivered_orders
    from orders;
-- what is the overall cancellation rate?
	select round((sum(order_status <> "delivered")/count(*))*100,2) as cancellation_rate
    from orders;
-- what is the average order value?
	select sum(if(o.order_status = "delivered",p.amount,0))/count(o.order_id) as average_order_value
    from orders o
    inner join payments p on o.order_id=p.order_id;
-- What is the monthly revenue and order count? 
select date_format(o.order_date, '%Y-%m') as month,
       sum(p.amount) as monthly_revenue,
       count(o.order_id) as monthly_order_count
from payments p
inner join orders o on p.order_id = o.order_id
group by date_format(o.order_date, '%Y-%m')
order by date_format(o.order_date, '%Y-%m');

-- Which payment method brings in the most revenue, and how many transactions does each have? 

select payment_method,sum(amount) as revenue, count(order_id) as transaction_count
from payments
group by payment_method
order by revenue desc;
-- For each restaurant, show total orders, revenue, and average delivery time (delivered orders only).
select 
	r.restaurant_name,r.restaurant_id, -- this works because of functional dependency exists btw id and name!!
	count(o.order_id) as total_orders ,sum(p.amount) as total_revenue ,avg(o.delivery_time) as average_delivery_time
from orders o
inner join restaurants r on r.restaurant_id=o.restaurant_id
inner join payments p on p.order_id=o.order_id
group by r.restaurant_id
order by r.restaurant_id;

-- Which cuisine type generates the most revenue? 
select r.cusine_type,sum(p.amount) as cuisine_revenue
from restaurants r
inner join orders o on r.restaurant_id=o.restaurant_id
inner join payments p on o.order_id=p.order_id
group by r.cusine_type
order by cuisine_revenue desc;

-- Which restaurants have received no orders 
select r.restaurant_name
from restaurants r
left join orders o on r.restaurant_id=o.restaurant_id
where o.order_id is null
order by r.restaurant_name;
-- which customers have never placed an order? 
select c.customer_name
from customers c
left join orders o on c.customer_id = o.customer_id
where o.order_id is null;

-- Show each order with the customer name, restaurant name, items ordered, and amount paid. 
select 
	c.customer_name,
    r.restaurant_name,
    p.amount,
    group_concat(oi.item_name order by oi.item_name separator ',') as order_items,
    o.order_date
from orders o
join customers c on o.customer_id=c.customer_id
join restaurants r on o.restaurant_id=r.restaurant_id
join payments p on o.order_id=p.order_id
join order_items oi on oi.order_id=o.order_id
group by o.order_id,c.customer_name,r.restaurant_name,p.amount,o.order_date
order by c.customer_name,o.order_id;

-- Which restaurants have a cancellation rate above the overall cancellation rate? 

select r.restaurant_id,r.restaurant_name,round(avg(o.order_status = "cancelled")*100,2) as restaurant_cancellation_rate
from orders o 
inner join restaurants r on o.restaurant_id=r.restaurant_id
group by r.restaurant_id
having avg(o.order_status = "cancelled")*100 >(select avg(order_status = "cancelled")*100 asoverall_cancellation_rate from orders)
order by restaurant_cancellation_rate desc;

-- Which customers spent more than the average customer spend? 
with avg_customer as
(
select o.customer_id,sum(p.amount) as amount_spent
from payments p
inner join orders o on o.order_id=p.order_id
group by o.customer_id 
)
select c.customer_name,a.amount_spent
from customers c
inner join avg_customer a on a.customer_id=c.customer_id
group by c.customer_id
having a.amount_spent > (select round(avg(amount_spent),2) from avg_customer)
order by a.amount_spent desc,c.customer_id;







-- Which customers ordered from more than one restaurant? 
select c.customer_name,c.customer_id,count(distinct o.restaurant_id) as different_restaurants_count
from orders o
inner join customers c on o.customer_id=c.customer_id
group by c.customer_id
having count(distinct o.restaurant_id)>1
order by c.customer_id;

-- Which restaurants earn more than the average restaurant revenue? 
with avg_restaurant as
(
	select o.restaurant_id,sum(p.amount) as revenue
    from orders o
    inner join payments p on o.order_id=p.order_id
    group by restaurant_id
)
select r.restaurant_name,a.revenue
from restaurants r
inner join avg_restaurant a  on r.restaurant_id=a.restaurant_id
where revenue> (select avg(revenue) from avg_restaurant)
order by revenue;
-- Segment customers into High, Medium, and Low value by total spend, and show what percentage of total revenue each segment contributes.
-- Choose your own thresholds and justify them. 

with customer_spend as (
    select o.customer_id,
           sum(p.amount) as total_spend, -- total spend of a customer
           avg(sum(p.amount)) over () as avg_spend
    from orders o
    join payments p on o.order_id = p.order_id
    group by o.customer_id
),
segmented as (
    select customer_id,
           total_spend,
           case
               when total_spend >= 1.5 * avg_spend then 'High'
               when total_spend >= avg_spend then 'Medium'
               else 'Low'
           end as customer_category
    from customer_spend
)
select 
	c.customer_id,
    c.customer_name,
	s.total_spend as revenue,
    s.customer_category,
	round(s.total_spend / sum(s.total_spend) over () * 100, 2) as pct_of_revenue
from segmented s
inner join customers c on s.customer_id=c.customer_id
order by field(customer_category, 'High', 'Medium', 'Low');   

-- What percentage of customers ordered more than once (repeat rate)?  
with repeat_customers as
(
select customer_id,count(*) as repeat_count
from orders
where order_status="Delivered"
group by customer_id
)
select (sum(if(repeat_count>1,1,0))/count(*))*100 as repeat_rate
from repeat_customers;

-- Rank restaurants by revenue within each city. Show the city, restaurant name, revenue and rank.
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
-- What is the month-over-month revenue growth percentage? Show each month, its revenue, the previous month’s revenue and the growth %.
select * ,
   round(
           (current_month_revenue - previous_month_revenue)/ 
           nullif(previous_month_revenue, 0) * 100, 2) as growth_percentage
    from
(
select 
	date_format(o.order_date,'%Y-%m') as month_of_the_year,
    sum(p.amount) as current_month_revenue,
    lag(sum(p.amount)) over(order by date_format(o.order_date,'%Y-%m')) as previous_month_revenue
from orders o
inner join payments p on o.order_id=p.order_id
group by date_format(o.order_date,'%Y-%m')
) as revenue_table;




