-- ============================================================
--  ЛАБОРАТОРНАЯ РАБОТА №2
--  Базовые SQL-запросы и фильтрация данных
--  База данных: marketplace (PostgreSQL 18)
--
--  Перед выполнением запросов запустите 01_lab2_seed.sql.
--  В pgAdmin: Query Tool -> открыть файл -> Execute (F5).
-- ============================================================


-- ------------------------------------------------------------
-- Запрос 1 (задание 2). DISTINCT + псевдонимы столбцов.
-- Назначение: показать все различные сочетания категории и
-- признака активности товара, убрав полностью совпадающие строки.
-- ------------------------------------------------------------
SELECT DISTINCT
       p.category_id AS category_id,
       p.is_active   AS active
FROM products AS p
ORDER BY category_id, active DESC;


-- ------------------------------------------------------------
-- Запрос 2 (задание 3). Несколько условий AND / OR со скобками.
-- Назначение: активные товары продавцов 1..50, которые относятся
-- к смартфонам/ноутбукам/наушникам ИЛИ стоят от 80 000 руб.
-- Скобки задают приоритет: сначала OR, затем AND.
-- ------------------------------------------------------------
SELECT p.id,
       p.title AS product_name,
       p.price AS price_rub,
       p.category_id
FROM products AS p
WHERE (p.category_id IN (6, 7, 8) OR p.price >= 80000)
  AND p.is_active = TRUE
  AND p.seller_id <= 50
ORDER BY p.price DESC, p.id
LIMIT 15;


-- ------------------------------------------------------------
-- Запрос 3 (задание 4). Предикат BETWEEN.
-- Назначение: активные товары с ценой в замкнутом диапазоне
-- от 5 000 до 15 000 руб. включительно.
-- ------------------------------------------------------------
SELECT p.title AS product_name,
       p.price AS price_rub
FROM products AS p
WHERE p.price BETWEEN 5000 AND 15000
  AND p.is_active = TRUE
ORDER BY p.price, p.id
LIMIT 10;


-- ------------------------------------------------------------
-- Запрос 4 (задание 4). Предикат IN.
-- Назначение: товары только из категорий 6, 7 и 10
-- (смартфоны, ноутбуки, планшеты).
-- ------------------------------------------------------------
SELECT p.title AS product_name,
       p.category_id
FROM products AS p
WHERE p.category_id IN (6, 7, 10)
ORDER BY p.category_id, p.id
LIMIT 10;


-- ------------------------------------------------------------
-- Запрос 5 (задание 4). Предикат ILIKE.
-- Назначение: поиск товаров, в названии которых встречается
-- слово «телефон» в любом регистре (% — любая последовательность).
-- ------------------------------------------------------------
SELECT p.title AS product_name,
       p.price AS price_rub
FROM products AS p
WHERE p.title ILIKE '%телефон%'
ORDER BY p.price DESC, p.id
LIMIT 10;


-- ------------------------------------------------------------
-- Запрос 6 (задание 4). IS NULL + COALESCE.
-- Назначение: товары без описания; вместо NULL выводится
-- текст «нет описания».
-- ------------------------------------------------------------
SELECT p.title AS product_name,
       COALESCE(p.description, 'нет описания') AS description
FROM products AS p
WHERE p.description IS NULL
ORDER BY p.id
LIMIT 10;


-- ------------------------------------------------------------
-- Запрос 7 (задание 4). Совместное применение IN, BETWEEN,
-- ILIKE и проверки активности в одном условии WHERE.
-- ------------------------------------------------------------
SELECT p.title AS product_name,
       p.price AS price_rub,
       p.is_active
FROM products AS p
WHERE p.category_id IN (6, 7)
  AND p.is_active = TRUE
  AND p.price BETWEEN 1000 AND 20000
  AND p.title ILIKE '%телефон%'
ORDER BY p.price DESC;


-- ------------------------------------------------------------
-- Запрос 8 (задание 5). Сортировка по двум столбцам в разных
-- направлениях: цена — по убыванию, название — по возрастанию.
-- ------------------------------------------------------------
SELECT p.title AS product_name,
       p.price AS price_rub,
       p.category_id
FROM products AS p
WHERE p.is_active = TRUE
ORDER BY p.price DESC, p.title ASC
LIMIT 15;


-- ------------------------------------------------------------
-- Запрос 9 (задание 6). Постраничный вывод: страница 1
-- (первые 10 активных товаров по убыванию цены).
-- ------------------------------------------------------------
SELECT p.id,
       p.title AS product_name,
       p.price AS price_rub
FROM products AS p
WHERE p.is_active = TRUE
ORDER BY p.price DESC, p.id
LIMIT 10 OFFSET 0;


-- ------------------------------------------------------------
-- Запрос 10 (задание 6). Постраничный вывод: страница 3
-- (LIMIT 10 OFFSET 20 пропускает первые 20 строк).
-- ------------------------------------------------------------
SELECT p.id,
       p.title AS product_name,
       p.price AS price_rub
FROM products AS p
WHERE p.is_active = TRUE
ORDER BY p.price DESC, p.id
LIMIT 10 OFFSET 20;
