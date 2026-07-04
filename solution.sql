-- Этап 1. Создание и заполнение БД
INSERT INTO car_shop.client (first_name, last_name, phone)
SELECT DISTINCT
    SPLIT_PART(s.person, ' ', 1),
    SUBSTRING(s.person FROM POSITION(' ' IN s.person) + 1),
    s.phone
FROM raw_date.sales as s
ON CONFLICT (phone) DO NOTHING;

INSERT INTO car_shop.brand_origins  (brand_origin_name)
SELECT DISTINCT brant_origin FROM raw_date.sales
ON CONFLICT (brand_origin_name) DO NOTHING;

INSERT INTO car_shop.brand (brand_name)
SELECT DISTINCT SPLIT_PART(s.auto, ' ', 1) AS brand_name
FROM raw_date.sales s
ON CONFLICT (brand_name) DO NOTHING;

-- 1. Справочник моделей (всё после первого слова до запятой)
INSERT INTO car_shop.car_model (car_model_name)
SELECT DISTINCT
    TRIM(SUBSTRING(SPLIT_PART(s.auto, ',', 1) FROM POSITION(' ' IN SPLIT_PART(s.auto, ',', 1)) + 1))
FROM raw_date.sales s
WHERE POSITION(' ' IN SPLIT_PART(s.auto, ',', 1)) > 0
ON CONFLICT (car_model_name) DO NOTHING;

-- 2. Справочник цветов (после запятой)
INSERT INTO car_shop.color (color_name)
SELECT DISTINCT TRIM(SPLIT_PART(s.auto, ',', 2))
FROM raw_date.sales s
WHERE SPLIT_PART(s.auto, ',', 2) <> ''
ON CONFLICT (color_name) DO NOTHING;

-- 3. Справочник расхода топлива (если есть)
INSERT INTO car_shop.gasoline_consumption (total)
SELECT DISTINCT s.gasoline_consumption
FROM raw_date.sales s;

-- 4. Автомобили (каждая запись источника – один автомобиль)
INSERT INTO car_shop.cars (car_model_id, color_id, brand_id, gasoline_id, brand_origin_id)
SELECT
    cm.car_model_id,
    c.color_id,
    b.brand_id,
    COALESCE(g.gasoline_id, (SELECT gasoline_id FROM car_shop.gasoline_consumption WHERE total IS NULL)) AS gasoline_id,
    COALESCE(bo.brand_origin_id, (SELECT brand_origin_id FROM car_shop.brand_origins WHERE brand_origin_name IS NULL)) AS brand_origin_id
FROM raw_date.sales s
JOIN car_shop.car_model cm 
    ON cm.car_model_name = TRIM(SUBSTRING(SPLIT_PART(s.auto, ',', 1) FROM POSITION(' ' IN SPLIT_PART(s.auto, ',', 1)) + 1))
JOIN car_shop.color c 
    ON c.color_name = TRIM(SPLIT_PART(s.auto, ',', 2))
JOIN car_shop.brand b 
    ON b.brand_name = SPLIT_PART(s.auto, ' ', 1)
LEFT JOIN car_shop.gasoline_consumption g 
    ON g.total = s.gasoline_consumption
LEFT JOIN car_shop.brand_origins bo 
    ON bo.brand_origin_name = s.brant_origin;
    
    
    -- 5. Продажи
INSERT INTO car_shop.sales (auto_id, client_id, price, discount, sale_date)
SELECT
    c.auto_id,
    cl.client_id,
    s.price,
    s.discount,
    s.date
FROM raw_date.sales s
JOIN car_shop.cars c ON (
    c.car_model_id = (SELECT car_model_id FROM car_shop.car_model WHERE car_model_name = TRIM(SUBSTRING(SPLIT_PART(s.auto, ',', 1) FROM POSITION(' ' IN SPLIT_PART(s.auto, ',', 1)) + 1)))
    AND c.color_id = (SELECT color_id FROM car_shop.color WHERE color_name = TRIM(SPLIT_PART(s.auto, ',', 2)))
    AND c.brand_id = (SELECT brand_id FROM car_shop.brand WHERE brand_name = SPLIT_PART(s.auto, ' ', 1))
    AND c.gasoline_id IS NOT DISTINCT FROM (SELECT gasoline_id FROM car_shop.gasoline_consumption WHERE total IS NOT DISTINCT FROM s.gasoline_consumption)
    AND c.brand_origin_id IS NOT DISTINCT FROM (SELECT brand_origin_id FROM car_shop.brand_origins WHERE brand_origin_name IS NOT DISTINCT FROM s.brant_origin)   -- исправлено
)
JOIN car_shop.client cl ON cl.phone = s.phone
ON CONFLICT (auto_id) DO NOTHING;


-- Этап 2. Создание выборок
---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.
SELECT 
    ROUND(
        100.0 * (
            SELECT COUNT(*) 
            FROM car_shop.cars c
            JOIN car_shop.gasoline_consumption gc ON c.gasoline_id = gc.gasoline_id
            WHERE gc.total IS NULL
        ) / (SELECT COUNT(*) FROM car_shop.cars),
        2
    ) AS nulls_percentage_gasoline_consumption;


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
JOIN car_shop.brand_origins bo ON c.brand_origin_id = bo.brand_origin_id
GROUP BY bo.brand_origin_name
ORDER BY bo.brand_origin_name;
---- Задание 6. Напишите запрос, который покажет количество всех пользователей из США.
SELECT COUNT(client.client_id) as persons_from_usa_count
FROM car_shop.client
WHERE client.phone LIKE '+1%';