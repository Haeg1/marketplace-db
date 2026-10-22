-- ============================================================
--  ЛАБОРАТОРНАЯ РАБОТА №3
--  Многотабличные запросы и аналитические представления
--  База данных: marketplace (PostgreSQL 18)
--
--  Перед выполнением запросов запустите 01_lab2_seed.sql.
--  В pgAdmin: Query Tool -> открыть файл -> Execute (F5).
-- ============================================================

SET client_min_messages TO warning;


-- ------------------------------------------------------------
-- Запрос 1 (задание 1). INNER JOIN трёх таблиц:
-- товар -> категория -> продавец.
-- ------------------------------------------------------------
SELECT p.id,
       p.title AS product_name,
       c.name AS category,
       s.store_name AS seller,
       p.price AS price_rub
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers AS s ON s.id = p.seller_id
WHERE p.is_active = TRUE
ORDER BY p.price DESC, p.id
LIMIT 15;


-- ------------------------------------------------------------
-- Запрос 2 (задание 2). LEFT JOIN: товары без отзывов.
-- LEFT JOIN сохраняет все товары, а условие r.id IS NULL
-- оставляет только те, для которых совпадений в reviews нет.
-- ------------------------------------------------------------
SELECT p.id,
       p.title AS product_name,
       p.category_id,
       p.price AS price_rub
FROM products AS p
LEFT JOIN reviews AS r ON r.product_id = p.id
WHERE r.id IS NULL
ORDER BY p.id
LIMIT 15;


-- Количество товаров без отзывов (проверка результата LEFT JOIN).
SELECT COUNT(*) AS products_without_reviews
FROM products AS p
LEFT JOIN reviews AS r ON r.product_id = p.id
WHERE r.id IS NULL;


-- ------------------------------------------------------------
-- Запрос 3 (задание 3). GROUP BY + агрегатные функции:
-- по каждой подкатегории — количество товаров и средняя цена.
-- ------------------------------------------------------------
SELECT c.name AS category,
       COUNT(p.id) AS products_count,
       ROUND(AVG(p.price), 2) AS avg_price,
       MIN(p.price) AS min_price,
       MAX(p.price) AS max_price
FROM categories AS c
JOIN products AS p ON p.category_id = c.id
WHERE c.parent_id IS NOT NULL
GROUP BY c.id, c.name
ORDER BY products_count DESC, c.name;


-- ------------------------------------------------------------
-- Запрос 4 (задание 4). HAVING: продавцы с выручкой выше
-- заданной (3 500 000 руб.). WHERE здесь не подходит, так как
-- фильтруется уже вычисленная агрегатная функция SUM.
-- ------------------------------------------------------------
SELECT s.id,
       s.store_name AS seller,
       COUNT(DISTINCT oi.order_id) AS orders_count,
       SUM(oi.quantity * oi.unit_price) AS revenue
FROM sellers AS s
JOIN products AS p ON p.seller_id = s.id
JOIN order_items AS oi ON oi.product_id = p.id
GROUP BY s.id, s.store_name
HAVING SUM(oi.quantity * oi.unit_price) > 3500000
ORDER BY revenue DESC;


-- ------------------------------------------------------------
-- Запрос 5 (задание 5). Скалярный подзапрос: товары дороже
-- средней цены по всей базе. Подзапрос возвращает одно значение.
-- ------------------------------------------------------------
SELECT p.title AS product_name,
       p.price AS price_rub,
       (SELECT ROUND(AVG(price), 2) FROM products) AS avg_price_all
FROM products AS p
WHERE p.price > (SELECT AVG(price) FROM products)
ORDER BY p.price DESC, p.id
LIMIT 10;


-- ------------------------------------------------------------
-- Запрос 6 (задание 5). Подзапрос с IN: покупатели, у которых
-- есть хотя бы один заказ в статусе paid.
-- ------------------------------------------------------------
SELECT u.id,
       u.full_name,
       u.email
FROM users AS u
WHERE u.id IN (
    SELECT o.user_id
    FROM orders AS o
    WHERE o.status = 'paid'
)
ORDER BY u.id
LIMIT 10;


-- ------------------------------------------------------------
-- Запрос 7 (задание 5). Коррелированный подзапрос с EXISTS:
-- продавцы, у которых есть хотя бы один товар.
-- ------------------------------------------------------------
SELECT s.id,
       s.store_name AS seller
FROM sellers AS s
WHERE EXISTS (
    SELECT 1
    FROM products AS p
    WHERE p.seller_id = s.id
)
ORDER BY s.id
LIMIT 10;


-- ------------------------------------------------------------
-- Запрос 8 (задание 5). NOT EXISTS: продавцы без товаров.
-- ------------------------------------------------------------
SELECT s.id,
       s.store_name AS seller
FROM sellers AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM products AS p
    WHERE p.seller_id = s.id
)
ORDER BY s.id;


-- ------------------------------------------------------------
-- Запрос 9 (задание 6). CTE: выручка продавцов и её доля
-- в общей выручке (оконная функция SUM() OVER ()).
-- ------------------------------------------------------------
WITH seller_revenue AS (
    SELECT p.seller_id,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM products AS p
    JOIN order_items AS oi ON oi.product_id = p.id
    GROUP BY p.seller_id
)
SELECT s.store_name AS seller,
       ROUND(r.revenue, 2) AS revenue,
       ROUND(100 * r.revenue / SUM(r.revenue) OVER (), 2) AS share_percent
FROM seller_revenue AS r
JOIN sellers AS s ON s.id = r.seller_id
ORDER BY revenue DESC
LIMIT 10;


-- ------------------------------------------------------------
-- Запрос 10 (задание 6). Рекурсивный CTE: обход дерева
-- категорий от корневых узлов ко всем подкатегориям.
-- ------------------------------------------------------------
WITH RECURSIVE category_tree AS (
    SELECT c.id,
           c.parent_id,
           c.name,
           1 AS level,
           c.name::text AS path
    FROM categories AS c
    WHERE c.parent_id IS NULL

    UNION ALL

    SELECT c.id,
           c.parent_id,
           c.name,
           t.level + 1,
           t.path || ' -> ' || c.name
    FROM categories AS c
    JOIN category_tree AS t ON c.parent_id = t.id
)
SELECT id,
       level,
       path
FROM category_tree
ORDER BY path;


-- ============================================================
--  Задание 7. Представления для типовых отчётов.
-- ============================================================

-- Витрина товаров: товар, категория, продавец, остаток.
CREATE OR REPLACE VIEW v_product_catalog AS
SELECT p.id AS product_id,
       p.title AS product_name,
       c.name AS category,
       s.store_name AS seller,
       p.price AS price_rub,
       p.is_active,
       COALESCE(st.quantity, 0) AS stock_quantity
FROM products AS p
JOIN categories AS c ON c.id = p.category_id
JOIN sellers AS s ON s.id = p.seller_id
LEFT JOIN stock AS st ON st.product_id = p.id;

-- Выручка и рейтинг продавцов. Агрегаты по заказам и отзывам
-- считаются отдельно, чтобы соединение не размножало строки.
CREATE OR REPLACE VIEW v_seller_revenue AS
SELECT s.id AS seller_id,
       s.store_name AS seller,
       COALESCE(rev.orders_count, 0) AS orders_count,
       COALESCE(rev.items_sold, 0) AS items_sold,
       COALESCE(rev.revenue, 0) AS revenue,
       rr.avg_review_score
FROM sellers AS s
LEFT JOIN (
    SELECT p.seller_id,
           COUNT(DISTINCT oi.order_id) AS orders_count,
           SUM(oi.quantity) AS items_sold,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM products AS p
    JOIN order_items AS oi ON oi.product_id = p.id
    GROUP BY p.seller_id
) AS rev ON rev.seller_id = s.id
LEFT JOIN (
    SELECT p.seller_id,
           ROUND(AVG(r.score), 2) AS avg_review_score
    FROM products AS p
    JOIN reviews AS r ON r.product_id = p.id
    GROUP BY p.seller_id
) AS rr ON rr.seller_id = s.id;

-- Сводка по категориям: количество товаров и средняя цена.
CREATE OR REPLACE VIEW v_category_stats AS
SELECT c.id AS category_id,
       c.name AS category,
       COUNT(p.id) AS products_count,
       ROUND(AVG(p.price), 2) AS avg_price,
       COUNT(p.id) FILTER (WHERE p.is_active) AS active_products
FROM categories AS c
LEFT JOIN products AS p ON p.category_id = c.id
GROUP BY c.id, c.name;

-- Демонстрация обращения к представлениям.
SELECT *
FROM v_product_catalog
ORDER BY price_rub DESC
LIMIT 10;

SELECT *
FROM v_seller_revenue
ORDER BY revenue DESC
LIMIT 10;

SELECT *
FROM v_category_stats
ORDER BY products_count DESC, category;


-- ============================================================
--  Дополнительно: материализованное представление.
--  В отличие от обычного VIEW, результат хранится физически
--  и обновляется командой REFRESH MATERIALIZED VIEW.
-- ============================================================
DROP MATERIALIZED VIEW IF EXISTS mv_category_sales;

CREATE MATERIALIZED VIEW mv_category_sales AS
SELECT c.id AS category_id,
       c.name AS category,
       COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS revenue
FROM categories AS c
LEFT JOIN products AS p ON p.category_id = c.id
LEFT JOIN order_items AS oi ON oi.product_id = p.id
WHERE c.parent_id IS NOT NULL
GROUP BY c.id, c.name
WITH DATA;

SELECT *
FROM mv_category_sales
ORDER BY revenue DESC
LIMIT 10;

REFRESH MATERIALIZED VIEW mv_category_sales;

SELECT COUNT(*) AS categories_in_matview
FROM mv_category_sales;
