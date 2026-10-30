-- ============================================================
--  ЛАБОРАТОРНАЯ РАБОТА №4
--  Оконные функции и аналитика данных
--  База данных: marketplace (PostgreSQL 18)
--
--  Перед выполнением запросов база должна быть заполнена
--  скриптом lab_2/01_seed.sql.
--  В pgAdmin: Query Tool -> открыть файл -> Execute (F5).
-- ============================================================

SET client_min_messages TO warning;


-- ------------------------------------------------------------
-- Запрос 1 (задание 1). Рейтинг товаров по цене внутри
-- каждой категории.
--
-- ROW_NUMBER() даёт уникальный номер каждой строке, поэтому
-- для воспроизводимости добавлен второй ключ сортировки p.id.
-- RANK() и DENSE_RANK() упорядочены только по цене: товары
-- с одинаковой ценой получат одинаковый ранг. Разница между
-- ними проявляется именно на таких строках.
-- ------------------------------------------------------------
SELECT c.name AS category,
       p.title AS product_name,
       p.price AS price_rub,
       ROW_NUMBER() OVER (
           PARTITION BY p.category_id
           ORDER BY p.price DESC, p.id
       ) AS row_number,
       RANK() OVER w AS rank,
       DENSE_RANK() OVER w AS dense_rank
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
WINDOW w AS (
    PARTITION BY p.category_id
    ORDER BY p.price DESC
)
ORDER BY p.category_id, p.price DESC, p.id;


-- ------------------------------------------------------------
-- Запрос 1a (пояснение к заданию 1). Небольшой учебный набор,
-- в котором есть одинаковые цены. На нём хорошо видно:
--   ROW_NUMBER: 1, 2, 3, 4, 5 — номера всегда уникальны;
--   RANK:       1, 1, 3, 3, 5 — равные цены делят ранг,
--               после чего номера пропускаются;
--   DENSE_RANK: 1, 1, 2, 2, 3 — равные цены делят ранг,
--               но пропусков нет.
-- ------------------------------------------------------------
WITH demo(category, product_name, price) AS (
    VALUES
        ('Смартфоны', 'Товар A', 50000),
        ('Смартфоны', 'Товар B', 50000),
        ('Смартфоны', 'Товар C', 40000),
        ('Смартфоны', 'Товар D', 40000),
        ('Смартфоны', 'Товар E', 30000)
)
SELECT category,
       product_name,
       price,
       ROW_NUMBER() OVER (
           PARTITION BY category
           ORDER BY price DESC, product_name
       ) AS row_number,
       RANK() OVER (
           PARTITION BY category
           ORDER BY price DESC
       ) AS rank,
       DENSE_RANK() OVER (
           PARTITION BY category
           ORDER BY price DESC
       ) AS dense_rank
FROM demo
ORDER BY category, price DESC, product_name;


-- ------------------------------------------------------------
-- Запрос 2 (задание 2). Три самых дорогих товара в каждой
-- категории. Сначала CTE ranked нумерует товары внутри
-- категории, затем внешний запрос оставляет только rn <= 3.
-- ------------------------------------------------------------
WITH ranked AS (
    SELECT c.name AS category,
           p.title AS product_name,
           p.price AS price_rub,
           ROW_NUMBER() OVER (
               PARTITION BY p.category_id
               ORDER BY p.price DESC, p.id
           ) AS rn
    FROM products AS p
    JOIN categories AS c ON c.id = p.category_id
)
SELECT category,
       rn,
       product_name,
       price_rub
FROM ranked
WHERE rn <= 3
ORDER BY category, rn;


-- ------------------------------------------------------------
-- Запрос 3 (задание 3). Нарастающий итог выручки по дням.
--
-- Сначала daily считает выручку каждого дня, затем оконная
-- SUM(...) OVER (ORDER BY day ROWS BETWEEN UNBOUNDED PRECEDING
-- AND CURRENT ROW) накапливает её от первого дня до текущего.
-- ------------------------------------------------------------
WITH daily AS (
    SELECT o.created_at::date AS day,
           SUM(oi.quantity * oi.unit_price) AS day_revenue
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.id
    GROUP BY o.created_at::date
)
SELECT day,
       ROUND(day_revenue, 2) AS day_revenue,
       ROUND(
           SUM(day_revenue) OVER (
               ORDER BY day
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ),
           2
       ) AS running_total
FROM daily
ORDER BY day;


-- ------------------------------------------------------------
-- Запрос 4 (задание 4). Доля выручки каждого продавца
-- в выручке его категории.
--
-- seller_category_revenue агрегирует выручку до уровня
-- «категория + продавец». Оконная SUM(...) OVER
-- (PARTITION BY category_id) добавляет к каждой строке общую
-- выручку категории, не сворачивая строки продавцов.
-- ------------------------------------------------------------
WITH seller_category_revenue AS (
    SELECT p.category_id,
           p.seller_id,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM products AS p
    JOIN order_items AS oi ON oi.product_id = p.id
    GROUP BY p.category_id, p.seller_id
)
SELECT c.name AS category,
       s.store_name AS seller,
       ROUND(scr.revenue, 2) AS revenue,
       ROUND(
           SUM(scr.revenue) OVER (PARTITION BY scr.category_id),
           2
       ) AS category_revenue,
       ROUND(
           100 * scr.revenue
           / SUM(scr.revenue) OVER (PARTITION BY scr.category_id),
           2
       ) AS share_percent
FROM seller_category_revenue AS scr
JOIN categories AS c ON c.id = scr.category_id
JOIN sellers AS s ON s.id = scr.seller_id
ORDER BY scr.category_id, revenue DESC, s.store_name;


-- ------------------------------------------------------------
-- Запрос 5 (задание 5). Сравнение выручки текущего дня с
-- предыдущим и следующим с помощью LAG и LEAD.
--
-- LAG возвращает выручку предыдущего дня, LEAD — следующего.
-- Прирост считается как разность с предыдущим днём, процент —
-- как отношение прироста к предыдущему значению. NULLIF
-- защищает от деления на ноль.
-- ------------------------------------------------------------
WITH daily AS (
    SELECT o.created_at::date AS day,
           SUM(oi.quantity * oi.unit_price) AS day_revenue
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.id
    GROUP BY o.created_at::date
)
SELECT day,
       ROUND(day_revenue, 2) AS day_revenue,
       ROUND(
           LAG(day_revenue) OVER (ORDER BY day),
           2
       ) AS prev_day_revenue,
       ROUND(
           day_revenue - LAG(day_revenue) OVER (ORDER BY day),
           2
       ) AS day_over_day_change,
       ROUND(
           100 * (
               day_revenue - LAG(day_revenue) OVER (ORDER BY day)
           ) / NULLIF(LAG(day_revenue) OVER (ORDER BY day), 0),
           2
       ) AS growth_percent,
       ROUND(
           LEAD(day_revenue) OVER (ORDER BY day),
           2
       ) AS next_day_revenue
FROM daily
ORDER BY day;


-- ------------------------------------------------------------
-- Запрос 6 (задание 6). Та же задача, что и в запросе 4,
-- но без оконной функции: через обычную группировку.
--
-- Сначала считаем выручку по парам «категория + продавец»,
-- затем отдельно считаем общую выручку категории и соединяем
-- два агрегата. Получается больше кода и дополнительный JOIN,
-- зато видно, как GROUP BY сворачивает строки и требует
-- отдельного агрегата для итога категории.
-- ------------------------------------------------------------
WITH seller_category_revenue AS (
    SELECT p.category_id,
           p.seller_id,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM products AS p
    JOIN order_items AS oi ON oi.product_id = p.id
    GROUP BY p.category_id, p.seller_id
),
category_revenue AS (
    SELECT category_id,
           SUM(revenue) AS category_revenue
    FROM seller_category_revenue
    GROUP BY category_id
)
SELECT c.name AS category,
       s.store_name AS seller,
       ROUND(scr.revenue, 2) AS revenue,
       ROUND(cr.category_revenue, 2) AS category_revenue,
       ROUND(
           100 * scr.revenue / cr.category_revenue,
           2
       ) AS share_percent
FROM seller_category_revenue AS scr
JOIN category_revenue AS cr ON cr.category_id = scr.category_id
JOIN categories AS c ON c.id = scr.category_id
JOIN sellers AS s ON s.id = scr.seller_id
ORDER BY scr.category_id, revenue DESC, s.store_name;
