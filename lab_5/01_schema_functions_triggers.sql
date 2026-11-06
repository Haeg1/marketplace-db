-- ============================================================
--  ЛАБОРАТОРНАЯ РАБОТА №5
--  Транзакции, целостность данных и серверная логика
--  База данных: marketplace (PostgreSQL 18)
--
--  Скрипт создаёт объекты серверной логики:
--    * таблицу аудита изменения цен;
--    * денормализованное поле products.rating;
--    * функцию атомарного оформления заказа;
--    * функцию расчёта выручки продавца за период;
--    * триггер аудита цен;
--    * триггер пересчёта рейтинга товара.
--
--  Выполнять первым: 01_schema_functions_triggers.sql
-- ============================================================

SET client_min_messages TO warning;


-- ------------------------------------------------------------
-- 1. Журнал аудита изменения цен товаров.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product_price_audit (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id  BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    old_price   NUMERIC(12, 2) NOT NULL,
    new_price   NUMERIC(12, 2) NOT NULL,
    changed_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    changed_by  TEXT NOT NULL DEFAULT current_user
);

COMMENT ON TABLE product_price_audit IS
    'Журнал изменений цен товаров: старое и новое значение, время и пользователь';


-- ------------------------------------------------------------
-- 2. Денормализованное поле среднего рейтинга товара.
-- ------------------------------------------------------------
ALTER TABLE products
    ADD COLUMN IF NOT EXISTS rating NUMERIC(3, 2) NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'products_rating_check'
          AND conrelid = 'products'::regclass
    ) THEN
        ALTER TABLE products
            ADD CONSTRAINT products_rating_check
            CHECK (rating BETWEEN 0 AND 5);
    END IF;
END;
$$;

-- Первичный расчёт рейтинга по уже существующим отзывам.
UPDATE products AS p
SET rating = COALESCE(
    (
        SELECT ROUND(AVG(r.score)::numeric, 2)
        FROM reviews AS r
        WHERE r.product_id = p.id
    ),
    0
);


-- ------------------------------------------------------------
-- 3. Функция атомарного оформления заказа.
--
-- Функция:
--   * проверяет положительное количество;
--   * проверяет существование и активность товара;
--   * блокирует строку остатка (FOR UPDATE), чтобы параллельные
--     заказы не продали один и тот же товар дважды;
--   * проверяет остаток;
--   * создаёт заказ и позицию заказа;
--   * уменьшает остаток.
--
-- При любом RAISE EXCEPTION изменения функции откатываются.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION place_order(
    p_user_id   BIGINT,
    p_product_id BIGINT,
    p_qty       INT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id BIGINT;
    v_price    NUMERIC(12, 2);
    v_title    VARCHAR(255);
    v_stock    INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Количество должно быть положительным: %', p_qty;
    END IF;

    SELECT p.price, p.title
    INTO v_price, v_title
    FROM products AS p
    WHERE p.id = p_product_id
      AND p.is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Товар % не найден или неактивен', p_product_id;
    END IF;

    SELECT s.quantity
    INTO v_stock
    FROM stock AS s
    WHERE s.product_id = p_product_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Для товара % нет записи об остатке', p_product_id;
    END IF;

    IF v_stock < p_qty THEN
        RAISE EXCEPTION
            'Недостаточно товара «%» на складе: запрошено %, доступно %',
            v_title, p_qty, v_stock;
    END IF;

    INSERT INTO orders (user_id, status, total_amount)
    VALUES (p_user_id, 'created', v_price * p_qty)
    RETURNING id INTO v_order_id;

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product_id, p_qty, v_price);

    UPDATE stock
    SET quantity = quantity - p_qty,
        updated_at = now()
    WHERE product_id = p_product_id;

    RETURN v_order_id;
END;
$$;

COMMENT ON FUNCTION place_order(BIGINT, BIGINT, INT) IS
    'Атомарно оформляет заказ: создаёт заказ и позицию, уменьшает остаток';


-- ------------------------------------------------------------
-- 4. Функция расчёта выручки продавца за период.
--
-- Использует локальную переменную и SELECT ... INTO.
-- Отменённые заказы в выручку не включаются.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION seller_revenue(
    p_seller_id BIGINT,
    p_from      DATE,
    p_to        DATE
)
RETURNS NUMERIC(14, 2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_revenue NUMERIC(14, 2);
BEGIN
    SELECT COALESCE(SUM(oi.quantity * oi.unit_price), 0)::numeric(14, 2)
    INTO v_revenue
    FROM products AS p
    JOIN order_items AS oi ON oi.product_id = p.id
    JOIN orders AS o ON o.id = oi.order_id
    WHERE p.seller_id = p_seller_id
      AND o.status <> 'cancelled'
      AND o.created_at::date BETWEEN p_from AND p_to;

    RETURN v_revenue;
END;
$$;

COMMENT ON FUNCTION seller_revenue(BIGINT, DATE, DATE) IS
    'Возвращает выручку продавца за период без отменённых заказов';


-- ------------------------------------------------------------
-- 5. Триггер аудита изменения цены.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION log_product_price_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.price IS DISTINCT FROM OLD.price THEN
        INSERT INTO product_price_audit (product_id, old_price, new_price)
        VALUES (OLD.id, OLD.price, NEW.price);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_product_price_audit ON products;

CREATE TRIGGER trg_product_price_audit
AFTER UPDATE OF price ON products
FOR EACH ROW
WHEN (OLD.price IS DISTINCT FROM NEW.price)
EXECUTE FUNCTION log_product_price_change();


-- ------------------------------------------------------------
-- 6. Триггер поддержки денормализованного рейтинга.
--
-- Срабатывает после INSERT, UPDATE и DELETE отзыва.
-- При изменении product_id пересчитывает рейтинг и старого,
-- и нового товара.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_product_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_product_id BIGINT;
    v_new_product_id BIGINT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_old_product_id := OLD.product_id;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_product_id := OLD.product_id;
        v_new_product_id := NEW.product_id;
    ELSE
        v_new_product_id := NEW.product_id;
    END IF;

    IF v_old_product_id IS NOT NULL THEN
        UPDATE products AS p
        SET rating = COALESCE(
            (
                SELECT ROUND(AVG(r.score)::numeric, 2)
                FROM reviews AS r
                WHERE r.product_id = v_old_product_id
            ),
            0
        )
        WHERE p.id = v_old_product_id;
    END IF;

    IF v_new_product_id IS NOT NULL
       AND v_new_product_id IS DISTINCT FROM v_old_product_id THEN
        UPDATE products AS p
        SET rating = COALESCE(
            (
                SELECT ROUND(AVG(r.score)::numeric, 2)
                FROM reviews AS r
                WHERE r.product_id = v_new_product_id
            ),
            0
        )
        WHERE p.id = v_new_product_id;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_product_rating ON reviews;

CREATE TRIGGER trg_refresh_product_rating
AFTER INSERT OR UPDATE OR DELETE ON reviews
FOR EACH ROW
EXECUTE FUNCTION refresh_product_rating();


-- ------------------------------------------------------------
-- 7. Проверка созданных объектов.
-- ------------------------------------------------------------
SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments
FROM pg_proc AS p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
      'place_order',
      'seller_revenue',
      'log_product_price_change',
      'refresh_product_rating'
  )
ORDER BY p.proname;

SELECT t.tgname AS trigger_name,
       c.relname AS table_name,
       pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger AS t
JOIN pg_class AS c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal
ORDER BY t.tgname;
