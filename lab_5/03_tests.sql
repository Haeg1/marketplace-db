-- ============================================================
--  ЛАБОРАТОРНАЯ РАБОТА №5
--  Проверка функций и триггеров
--
--  Выполнять после 01_schema_functions_triggers.sql.
--  Скрипт не оставляет изменений в основных данных:
--  успешный заказ и тестовый отзыв откатываются,
--  цена товара после проверки аудита восстанавливается.
-- ============================================================

SET client_min_messages TO notice;


-- ------------------------------------------------------------
-- 1. Функция seller_revenue: выручка продавца за период.
-- ------------------------------------------------------------
SELECT s.id,
       s.store_name,
       seller_revenue(s.id, DATE '2026-04-25', DATE '2026-10-22') AS revenue
FROM sellers AS s
WHERE s.id IN (1, 2, 3)
ORDER BY s.id;


-- ------------------------------------------------------------
-- 2. Функция place_order: успешное оформление заказа.
--
--    Заказ создаётся, позиция добавляется, остаток уменьшается.
--    В конце транзакция откатывается, чтобы не менять данные
--    основного набора.
-- ------------------------------------------------------------
BEGIN;

SELECT quantity AS stock_before
FROM stock
WHERE product_id = 1;

SELECT place_order(1, 1, 2) AS new_order_id;

SELECT o.id AS order_id,
       o.user_id,
       o.status,
       o.total_amount,
       oi.product_id,
       oi.quantity,
       oi.unit_price
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.id
WHERE o.id = currval(pg_get_serial_sequence('orders', 'id'));

SELECT quantity AS stock_after_order
FROM stock
WHERE product_id = 1;

ROLLBACK;

SELECT quantity AS stock_after_rollback
FROM stock
WHERE product_id = 1;


-- ------------------------------------------------------------
-- 3. Функция place_order: недостаточное количество товара.
--
--    Исключение перехватывается внутри DO-блока, чтобы скрипт
--    продолжил работу. Проверяем, что количество заказов и
--    остаток не изменились: частичных изменений нет.
-- ------------------------------------------------------------
DO $$
DECLARE
    v_orders_before BIGINT;
    v_stock_before  INT;
    v_orders_after  BIGINT;
    v_stock_after   INT;
BEGIN
    SELECT count(*) INTO v_orders_before FROM orders;
    SELECT quantity INTO v_stock_before FROM stock WHERE product_id = 1;

    BEGIN
        PERFORM place_order(1, 1, 1000000);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Ожидаемая ошибка: %', SQLERRM;
    END;

    SELECT count(*) INTO v_orders_after FROM orders;
    SELECT quantity INTO v_stock_after FROM stock WHERE product_id = 1;

    RAISE NOTICE 'Заказы: % -> %, остаток товара 1: % -> %',
        v_orders_before, v_orders_after, v_stock_before, v_stock_after;
END;
$$;


-- ------------------------------------------------------------
-- 4. Триггер аудита цены.
--
--    Меняем цену товара 1 на +100, фиксируем изменение,
--    затем возвращаем цену обратно. В журнале остаются две
--    записи: повышение и понижение цены.
-- ------------------------------------------------------------
BEGIN;

UPDATE products
SET price = price + 100
WHERE id = 1;

COMMIT;

SELECT price AS price_after_increase
FROM products
WHERE id = 1;

SELECT id,
       product_id,
       old_price,
       new_price,
       changed_at,
       changed_by
FROM product_price_audit
WHERE product_id = 1
ORDER BY id DESC
LIMIT 1;

BEGIN;

UPDATE products
SET price = price - 100
WHERE id = 1;

COMMIT;

SELECT price AS price_after_restore
FROM products
WHERE id = 1;

SELECT id,
       product_id,
       old_price,
       new_price,
       changed_at,
       changed_by
FROM product_price_audit
WHERE product_id = 1
ORDER BY id DESC
LIMIT 2;


-- ------------------------------------------------------------
-- 5. Триггер пересчёта среднего рейтинга.
--
--    У товара 2 уже есть отзыв с оценкой 1, поэтому rating = 1.00.
--    Добавляем второй отзыв с оценкой 5: среднее должно стать 3.00.
--    После ROLLBACK отзыв и изменение рейтинга отменяются.
-- ------------------------------------------------------------
BEGIN;

SELECT rating AS rating_before
FROM products
WHERE id = 2;

INSERT INTO reviews (user_id, product_id, score, comment, created_at)
VALUES (1, 2, 5, 'Тестовый отзыв для проверки триггера', now());

SELECT rating AS rating_after_insert
FROM products
WHERE id = 2;

ROLLBACK;

SELECT rating AS rating_after_rollback
FROM products
WHERE id = 2;


-- ------------------------------------------------------------
-- 6. Итоговая проверка: в основных таблицах не осталось
--    тестовых заказов и отзывов, цена восстановлена,
--    рейтинг товара 2 вернулся к исходному значению.
-- ------------------------------------------------------------
SELECT count(*) AS orders_total
FROM orders;

SELECT count(*) AS reviews_total
FROM reviews;

SELECT price AS product_1_price
FROM products
WHERE id = 1;

SELECT rating AS product_2_rating
FROM products
WHERE id = 2;
