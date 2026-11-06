-- ============================================================
--  ЛАБОРАТОРНАЯ РАБОТА №5
--  Демонстрация транзакций: COMMIT, ошибка и ROLLBACK
--
--  Скрипт использует отдельный тестовый товар id = 999001
--  и тестовые заказы id = 999001, 999002, чтобы не менять
--  основные данные маркетплейса. В конце выполняется очистка.
--
--  Выполнять после 01_schema_functions_triggers.sql.
--  В pgAdmin скрипт лучше выполнять по шагам: после
--  намеренной ошибки SELECT 1/0; транзакция переходит в
--  состояние aborted, затем выполняется ROLLBACK.
-- ============================================================

SET client_min_messages TO warning;


-- ------------------------------------------------------------
-- 0. Подготовка: удалить следы предыдущего запуска и создать
--    тестовый товар с остатком 100 шт.
-- ------------------------------------------------------------
BEGIN;

DELETE FROM orders WHERE id IN (999001, 999002);
DELETE FROM products WHERE id = 999001;

INSERT INTO products (id, seller_id, category_id, title,
                      description, price, is_active)
OVERRIDING SYSTEM VALUE
VALUES (999001, 1, 6,
        'Товар для демонстрации транзакции',
        'Тестовая запись лабораторной работы №5',
        1000.00, TRUE);

INSERT INTO stock (product_id, quantity)
VALUES (999001, 100);

COMMIT;

SELECT count(*) AS orders_before
FROM orders;

SELECT product_id, quantity AS stock_before
FROM stock
WHERE product_id = 999001;


-- ------------------------------------------------------------
-- 1. Успешная транзакция: заказ + позиция + уменьшение остатка.
--    Все три изменения фиксируются одной командой COMMIT.
-- ------------------------------------------------------------
BEGIN;

INSERT INTO orders (id, user_id, status, total_amount, created_at)
OVERRIDING SYSTEM VALUE
VALUES (999001, 1, 'created', 2000.00, now());

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (999001, 999001, 2, 1000.00);

UPDATE stock
SET quantity = quantity - 2,
    updated_at = now()
WHERE product_id = 999001;

COMMIT;

SELECT o.id AS order_id,
       o.total_amount,
       oi.product_id,
       oi.quantity,
       oi.unit_price
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.id
WHERE o.id = 999001;

SELECT product_id, quantity AS stock_after_commit
FROM stock
WHERE product_id = 999001;


-- ------------------------------------------------------------
-- 2. Транзакция с намеренной ошибкой.
--    Заказ и позиция уже вставлены, остаток уже уменьшен,
--    но затем происходит деление на ноль. Транзакция
--    становится aborted, и ROLLBACK отменяет все её изменения.
-- ------------------------------------------------------------
BEGIN;

INSERT INTO orders (id, user_id, status, total_amount, created_at)
OVERRIDING SYSTEM VALUE
VALUES (999002, 1, 'created', 1000.00, now());

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (999002, 999001, 1, 1000.00);

UPDATE stock
SET quantity = quantity - 1,
    updated_at = now()
WHERE product_id = 999001;

-- Намеренная ошибка: имитируем сбой на последнем шаге.
SELECT 1 / 0;

-- После ошибки транзакция aborted. Откатываем все изменения.
ROLLBACK;

SELECT count(*) AS test_orders_after_rollback
FROM orders
WHERE id IN (999001, 999002);

SELECT product_id, quantity AS stock_after_rollback
FROM stock
WHERE product_id = 999001;


-- ------------------------------------------------------------
-- 3. Очистка тестовых данных: удаляем заказы и тестовый товар.
--    Основные данные маркетплейса остаются без изменений.
-- ------------------------------------------------------------
BEGIN;

DELETE FROM orders WHERE id IN (999001, 999002);
DELETE FROM products WHERE id = 999001;

COMMIT;

SELECT count(*) AS total_orders_after_cleanup
FROM orders;

SELECT count(*) AS test_product_rows
FROM products
WHERE id = 999001;
