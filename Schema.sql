create table customers
(
	customer_id int primary key,
    customer_name varchar(30) not null,
    city varchar(20) not null,
    signup_date datetime
);


create table restaurants
(
	restaurant_id int primary key,
    restaurant_name varchar(20) unique,
    cusine_type varchar(20),
    city varchar(20) not null,
    rating decimal(2,1) check (rating>=0.0 and rating<=10.0)
    
);

create table orders
(
	order_id int primary key,
    customer_id int,
    restaurant_id int,
    order_date datetime,
    order_status varchar(15),
    delivery_time int
    
);
alter table orders
add constraint orders_customer_fk foreign key (customer_id) references customer(customer_id);  

alter table orders
add constraint orders_restaurant_fk foreign key (restaurant_id) references restaurant(restaurant_id);

create table order_items
(
	item_id int primary key,
    order_id int,
    item_name varchar(30),
    quantity int check (quantity>0),
    price decimal(5,2),
    foreign key (order_id) references orders(order_id) 
);
alter table order_items
modify item_name varchar(30) not null;

create table payments
(
	payment_id int primary key,
    order_id int,
    payment_method enum("upi","cash","card"),
    amount decimal(10,2),
    discount int default 0,
    foreign key (order_id) references orders(order_id)
    
);
alter table order_items
modify price decimal(8,2);

alter table orders
modify customer_id int not null;

alter table orders
modify restaurant_id int not null;
