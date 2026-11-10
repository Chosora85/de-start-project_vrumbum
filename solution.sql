-- Этап 1. Создание и заполнение БД


create schema raw_date;

create table raw_date.sales(
	id integer,
	auto varchar,
	gasoline_consumption Numeric(4,2) check (gasoline_consumption is null or (gasoline_consumption < 100 and gasoline_consumption >= 0)),
	price decimal (7,2),
	date date,
	person varchar,
	phone varchar,
	discount smallint,
	brand_origin varchar
);
create schema car_shop;

create table car_shop.client (
	client_id serial primary key,
	first_name varchar not null,
	last_name varchar not null,
	phone varchar NOT null unique
	);
	
create table car_shop.car_model (
	car_model_id serial primary key,
	car_model_name varchar not null unique
	gasoline_consumption numeric(4,2)
        CHECK (gasoline_consumption IS NULL
               OR (gasoline_consumption < 100 AND gasoline_consumption >= 0))
    UNIQUE (brand_id, car_model_name)
);

create table car_shop.color (
	color_id serial primary key,
	color_name varchar not null unique
	);

create table car_shop.brand_origins (
	brand_origin_id serial primary key,
	brand_origin_name varchar unique
	);

create table car_shop.brand (
	brand_id serial primary key,
	brand_name varchar not null unique,
    brand_origin_id integer references car_shop.brand_origins (brand_origin_id)
	);

create table car_shop.cars (
	auto_id SERIAL primary key,
	car_model_id integer not null references car_shop.car_model (car_model_id),
	color_id integer not null references car_shop.color (color_id),
	    UNIQUE (car_model_id, color_id)
	);

create table car_shop.sales (
	sales_id SERIAL primary key,
	auto_id INTEGER NOT NULL UNIQUE REFERENCES car_shop.cars (auto_id),
	client_id integer NOT NULL references car_shop.client (client_id),
	price decimal (7,2) NOT NULL,
	discount SMALLINT DEFAULT 0 CHECK (discount BETWEEN 0 AND 100),
	sale_date date
	);

INSERT INTO car_shop.client (first_name, last_name, phone)
SELECT DISTINCT
    SPLIT_PART(s.person, ' ', 1),
    SUBSTRING(s.person FROM POSITION(' ' IN s.person) + 1),
    s.phone
FROM raw_date.sales as s
ON CONFLICT (phone) DO NOTHING;

INSERT INTO car_shop.brand_origins (brand_origin_name)
SELECT DISTINCT brand_origin FROM raw_date.sales s
WHERE NOT EXISTS 
    (SELECT 1 FROM car_shop.brand_origins bo
    WHERE bo.brand_origin_name IS NOT DISTINCT FROM s.brand_origin) 
ON CONFLICT (brand_origin_name) DO NOTHING;

INSERT INTO car_shop.brand (brand_name, brand_origin_id)
SELECT DISTINCT 
        SPLIT_PART(s.auto, ' ', 1) AS brand_name,
        MAX(bo.brand_origin_id) AS brand_origin_id
FROM raw_date.sales s
LEFT JOIN car_shop.brand_origins bo
    ON bo.brand_origin_name IS NOT DISTINCT FROM s.brand_origin
GROUP BY SPLIT_PART(s.auto, ' ', 1)
ON CONFLICT (brand_name) DO NOTHING;

-- 1. Справочник моделей (всё после первого слова до запятой)
INSERT INTO car_shop.car_model (car_model_name, gasoline_consumption)
SELECT DISTINCT
    TRIM(SUBSTRING(SPLIT_PART(s.auto, ',', 1) 
        FROM POSITION(' ' IN SPLIT_PART(s.auto, ',', 1)) + 1)) AS car_model_name,
    MAX(s.gasoline_consumption) AS gasoline_consumption
FROM raw_date.sales s
WHERE POSITION(' ' IN SPLIT_PART(s.auto, ',', 1)) > 0
GROUP BY TRIM(SUBSTRING(SPLIT_PART(s.auto, ',', 1)
              FROM POSITION(' ' IN SPLIT_PART(s.auto, ',', 1)) + 1))
ON CONFLICT (car_model_name) DO NOTHING;

-- 2. Справочник цветов (после запятой)
INSERT INTO car_shop.color (color_name)
SELECT DISTINCT TRIM(SPLIT_PART(s.auto, ',', 2))
FROM raw_date.sales s
WHERE SPLIT_PART(s.auto, ',', 2) <> ''
ON CONFLICT (color_name) DO NOTHING;

-- 3. Автомобили (каждая запись источника – один автомобиль)
INSERT INTO car_shop.cars (car_model_id, color_id)
SELECT
    cm.car_model_id,
    c.color_id,
    b.brand_id
FROM raw_date.sales s
JOIN car_shop.car_model cm 
    ON cm.car_model_name = TRIM(SUBSTRING(SPLIT_PART(s.auto, ',', 1) 
    FROM POSITION(' ' IN SPLIT_PART(s.auto, ',', 1)) + 1))
JOIN car_shop.color c 
    ON c.color_name = TRIM(SPLIT_PART(s.auto, ',', 2))
JOIN car_shop.brand b 
    ON b.brand_name = SPLIT_PART(s.auto, ' ', 1)
ORDER BY cm.car_model_id, col.color_id, s.id
ON CONFLICT (car_model_id, color_id) DO NOTHING;
        
    -- 4. Продажи
INSERT INTO car_shop.sales (auto_id, client_id, price, discount, sale_date)
SELECT
    c.auto_id,
    cl.client_id,
    s.price,
    s.discount,
    s.date
FROM raw_date.sales s
JOIN car_shop.car_model cm
    ON cm.car_model_name = TRIM(SUBSTRING(SPLIT_PART(s.auto, ',', 1)
         FROM POSITION(' ' IN SPLIT_PART(s.auto, ',', 1)) + 1))
JOIN car_shop.color col
    ON col.color_name = TRIM(SPLIT_PART(s.auto, ',', 2))
JOIN car_shop.cars c
    ON c.car_model_id = cm.car_model_id
   AND c.color_id     = col.color_id
JOIN car_shop.client cl 
ON cl.phone = s.phone;

-- Этап 2. Создание выборок
---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.
SELECT 
    ROUND(
        100.0 * COUNT (*) FILTER (WHERE cm.gasoline_consumption IS NULL)
        / NULLIF(COUNT(*), 0),
        2
    ) AS nulls_percentage_gasoline_consumption
FROM car_shop.car_model cm;


---- Задание 2. Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам с учётом скидки.
select b.brand_name as brand_name, EXTRACT (year from s.sale_date) as year, ROUND(AVG(s.price), 2) as price_avg
from car_shop.sales as s
join car_shop.cars as c on s.auto_id = c.auto_id 
join car_shop.brand as b on c.brand_id = b.brand_id
GROUP BY b.brand_name, EXTRACT (year from s.sale_date)
ORDER BY b.brand_name, year;


---- Задание 3. Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки.
SELECT 
    EXTRACT(MONTH FROM sale_date) as month,
    EXTRACT(YEAR FROM sale_date) AS YEAR,
    ROUND(AVG(price), 2) AS avg_price_with_discount
FROM car_shop.sales
WHERE EXTRACT(YEAR FROM sale_date) = 2022
GROUP BY month, year
ORDER BY month ASC;


---- Задание 4. Напишите запрос, который выведет список купленных машин у каждого пользователя.
SELECT 
    CONCAT(cl.first_name, ' ', cl.last_name) AS person,
    STRING_AGG(CONCAT(b.brand_name, ' ', cm.car_model_name), ', ') AS cars
FROM car_shop.sales s
JOIN car_shop.cars c ON s.auto_id = c.auto_id
JOIN car_shop.brand b ON c.brand_id = b.brand_id
JOIN car_shop.car_model cm ON c.car_model_id = cm.car_model_id
JOIN car_shop.client cl ON s.client_id = cl.client_id
GROUP BY cl.client_id, cl.first_name, cl.last_name
ORDER BY cl.first_name, cl.last_name;


---- Задание 5. Напишите запрос, который вернёт самую большую и самую маленькую цену продажи автомобиля с разбивкой по стране без учёта скидки. 
----Цена в колонке price дана с учётом скидки.
SELECT 
    bo.brand_origin_name AS country,
    ROUND(MAX(s.price / (1 - s.discount / 100.0)),2) AS max_price,
    ROUND(MIN(s.price / (1 - s.discount / 100.0)),2) AS min_price
FROM car_shop.sales s
JOIN car_shop.cars c ON s.auto_id = c.auto_id
JOIN car_shop.brand b  ON c.brand_id   = b.brand_id
JOIN car_shop.brand_origins bo ON c.brand_origin_id = bo.brand_origin_id
GROUP BY bo.brand_origin_name
ORDER BY bo.brand_origin_name;

---- Задание 6. Напишите запрос, который покажет количество всех пользователей из США.
SELECT COUNT(client.client_id) as persons_from_usa_count
FROM car_shop.client
WHERE client.phone LIKE '+1%';