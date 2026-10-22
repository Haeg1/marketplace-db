-- ============================================================
--  Лабораторные работы №2-3. База данных marketplace
--  Наполнение всех таблиц согласованными тестовыми данными.
--
--  Запуск в pgAdmin: Query Tool -> открыть файл -> Execute (F5).
--  Скрипт полностью пересоздаёт данные (TRUNCATE ... RESTART IDENTITY).
--  В products и orders более 1000 строк.
-- ============================================================

BEGIN;

TRUNCATE TABLE deliveries, addresses, reviews, payments, order_items,
               orders, cart_items, carts, stock, products,
               categories, sellers, users
    RESTART IDENTITY CASCADE;

-- ------------------------------------------------------------
-- 1. Пользователи: 1..1000 - покупатели, 1001..1150 - продавцы,
--    1151..1200 - дополнительные покупатели.
-- ------------------------------------------------------------
INSERT INTO users (id, full_name, email, phone, role, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       (ARRAY['Иванов', 'Петров', 'Смирнов', 'Кузнецов', 'Соколов',
              'Попов', 'Лебедев', 'Козлов', 'Новиков', 'Морозов',
              'Иванова', 'Петрова', 'Смирнова', 'Кузнецова', 'Соколова',
              'Попова', 'Лебедева', 'Козлова', 'Новикова', 'Морозова'])[1 + ((g - 1) % 20)]
       || ' ' ||
       (ARRAY['Иван', 'Пётр', 'Алексей', 'Сергей', 'Дмитрий',
              'Андрей', 'Михаил', 'Николай', 'Владимир', 'Артём',
              'Елена', 'Ольга', 'Анна', 'Мария', 'Татьяна',
              'Наталья', 'Ирина', 'Светлана', 'Юлия', 'Екатерина'])[1 + ((g - 1) % 20)],
       'user' || g || '@example.com',
       CASE WHEN g % 9 = 0 THEN NULL
            ELSE '+7-900-' || lpad(((g * 7) % 1000)::text, 3, '0')
                 || '-' || lpad(((g * 13) % 10000)::text, 4, '0')
       END,
       CASE WHEN g BETWEEN 1001 AND 1150 THEN 'seller' ELSE 'customer' END,
       now() - ((g % 400) || ' days')::interval
FROM generate_series(1, 1200) AS g;

-- ------------------------------------------------------------
-- 2. Продавцы: 150 магазинов (пользователи 1001..1150).
--    Товары получат только продавцы 1..140, поэтому 10 магазинов
--    останутся без товаров (пригодятся для NOT EXISTS).
-- ------------------------------------------------------------
INSERT INTO sellers (id, user_id, store_name, description, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       1000 + g,
       (ARRAY['ТехноМир', 'Цифровой мир', 'Книжный дом', 'Читай-город',
              'Модный стиль', 'Одежда Plus', 'Уютный дом', 'Дом и сад',
              'СпортЛайф', 'Активный отдых', 'МегаМаркет', 'Товары 24',
              'ГаджетПлюс', 'СмартШоп', 'Всё для дома'])[1 + ((g - 1) % 15)]
       || ' №' || g,
       CASE WHEN g % 6 = 0 THEN NULL
            ELSE 'Официальный магазин на маркетплейсе. Рейтинг продавца '
                 || (3 + (g % 3)) || '/5.'
       END,
       now() - ((g % 300) || ' days')::interval
FROM generate_series(1, 150) AS g;

-- ------------------------------------------------------------
-- 3. Категории: 5 корневых + 20 подкатегорий (иерархия).
-- ------------------------------------------------------------
INSERT INTO categories (id, parent_id, name)
OVERRIDING SYSTEM VALUE
VALUES
    (1,  NULL, 'Электроника'),
    (2,  NULL, 'Книги'),
    (3,  NULL, 'Одежда'),
    (4,  NULL, 'Дом и сад'),
    (5,  NULL, 'Спорт'),
    (6,  1, 'Смартфоны'),
    (7,  1, 'Ноутбуки'),
    (8,  1, 'Наушники'),
    (9,  1, 'Телевизоры'),
    (10, 1, 'Планшеты'),
    (11, 2, 'Художественная литература'),
    (12, 2, 'Учебники'),
    (13, 2, 'Детские книги'),
    (14, 2, 'Фантастика'),
    (15, 3, 'Мужская одежда'),
    (16, 3, 'Женская одежда'),
    (17, 3, 'Обувь'),
    (18, 3, 'Аксессуары'),
    (19, 4, 'Мебель'),
    (20, 4, 'Посуда'),
    (21, 4, 'Освещение'),
    (22, 4, 'Текстиль'),
    (23, 5, 'Тренажёры'),
    (24, 5, 'Велосипеды'),
    (25, 5, 'Туризм');

-- ------------------------------------------------------------
-- 4. Товары: 1200 строк. Цена, остаток и активность задаются
--    детерминированно, чтобы результаты запросов были стабильны.
-- ------------------------------------------------------------
INSERT INTO products (id, seller_id, category_id, title,
                      description, price, is_active, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       1 + ((g - 1) % 140),
       6 + ((g - 1) % 20),
       CASE 6 + ((g - 1) % 20)
           WHEN 6  THEN 'Телефон '
           WHEN 7  THEN 'Ноутбук '
           WHEN 8  THEN 'Наушники '
           WHEN 9  THEN 'Телевизор '
           WHEN 10 THEN 'Планшет '
           WHEN 11 THEN 'Книга '
           WHEN 12 THEN 'Учебник '
           WHEN 13 THEN 'Детская книга '
           WHEN 14 THEN 'Фантастика '
           WHEN 15 THEN 'Куртка '
           WHEN 16 THEN 'Платье '
           WHEN 17 THEN 'Кроссовки '
           WHEN 18 THEN 'Сумка '
           WHEN 19 THEN 'Стол '
           WHEN 20 THEN 'Набор посуды '
           WHEN 21 THEN 'Лампа '
           WHEN 22 THEN 'Плед '
           WHEN 23 THEN 'Тренажёр '
           WHEN 24 THEN 'Велосипед '
           ELSE 'Палатка '
       END
       || (ARRAY['Galaxy', 'Pulse', 'Aero', 'Nova', 'Prime'])[1 + ((g - 1) % 5)]
       || ' ' || (ARRAY['S', 'M', 'L', 'X', 'Pro'])[1 + ((g - 1) % 5)]
       || ' №' || g,
       CASE WHEN g % 7 = 0 THEN NULL
            ELSE 'Описание товара №' || g || '. Гарантия 12 месяцев.'
       END,
       (1000 + (g * 83) % 99000)::numeric(12, 2),
       g % 13 <> 0,
       now() - ((g % 365) || ' days')::interval
FROM generate_series(1, 1200) AS g;

-- ------------------------------------------------------------
-- 5. Остатки на складе: по одной строке на товар.
-- ------------------------------------------------------------
INSERT INTO stock (product_id, quantity, updated_at)
SELECT g,
       (g * 13) % 501,
       now() - ((g % 30) || ' days')::interval
FROM generate_series(1, 1200) AS g;

-- ------------------------------------------------------------
-- 6. Адреса покупателей (1..1000).
-- ------------------------------------------------------------
INSERT INTO addresses (id, user_id, city, street, house, apartment)
OVERRIDING SYSTEM VALUE
SELECT g,
       g,
       (ARRAY['Москва', 'Санкт-Петербург', 'Казань', 'Екатеринбург',
              'Новосибирск', 'Нижний Новгород', 'Самара', 'Омск',
              'Ростов-на-Дону', 'Краснодар'])[1 + ((g - 1) % 10)],
       (ARRAY['ул. Ленина', 'ул. Мира', 'ул. Гагарина', 'ул. Советская',
              'ул. Пушкина', 'ул. Чехова', 'ул. Горького', 'ул. Садовая'])[1 + ((g - 1) % 8)],
       (1 + (g % 120))::text,
       CASE WHEN g % 8 = 0 THEN NULL ELSE (1 + (g % 200))::text END
FROM generate_series(1, 1000) AS g;

-- ------------------------------------------------------------
-- 7. Корзины и позиции корзин.
-- ------------------------------------------------------------
INSERT INTO carts (id, user_id, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       1 + ((g * 17) % 1000),
       now() - ((g % 90) || ' days')::interval
FROM generate_series(1, 800) AS g;

INSERT INTO cart_items (cart_id, product_id, quantity)
SELECT c.id,
       x.product_id,
       1 + ((c.id + x.product_id) % 3)
FROM carts AS c
CROSS JOIN LATERAL (
    SELECT 1 + ((c.id * 13 + s.k * 7) % 1200) AS product_id
    FROM generate_series(1, 2) AS s(k)
) AS x
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------
-- 8. Заказы: 1500 строк, по 300 на каждый статус.
-- ------------------------------------------------------------
INSERT INTO orders (id, user_id, status, total_amount, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       1 + ((g * 19) % 1000),
       (ARRAY['created', 'paid', 'delivered', 'shipped', 'cancelled'])[1 + ((g - 1) % 5)],
       0,
       now() - ((g % 180) || ' days')::interval
            - ((g % 24) || ' hours')::interval
FROM generate_series(1, 1500) AS g;

-- ------------------------------------------------------------
-- 9. Позиции заказов: от 2 до 4 товаров в каждом заказе.
-- ------------------------------------------------------------
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT o.id,
       p.id,
       1 + ((o.id + s.k) % 3),
       round(p.price * (1 - ((o.id + s.k) % 3) * 0.05), 2)
FROM orders AS o
CROSS JOIN LATERAL generate_series(1, 2 + (o.id % 3)) AS s(k)
JOIN products AS p ON p.id = 1 + ((o.id * 11 + s.k * 17) % 1200)
ON CONFLICT DO NOTHING;

-- Сумма заказа = сумме его позиций.
UPDATE orders AS o
SET total_amount = t.total
FROM (
    SELECT order_id, SUM(quantity * unit_price) AS total
    FROM order_items
    GROUP BY order_id
) AS t
WHERE t.order_id = o.id;

-- ------------------------------------------------------------
-- 10. Платежи: по всем неотменённым заказам.
-- ------------------------------------------------------------
INSERT INTO payments (id, order_id, amount, status, paid_at)
OVERRIDING SYSTEM VALUE
SELECT row_number() OVER (ORDER BY o.id)::bigint,
       o.id,
       o.total_amount,
       CASE WHEN o.status IN ('paid', 'delivered', 'shipped') THEN 'paid'
            WHEN o.id % 7 = 0 THEN 'failed'
            ELSE 'pending'
       END,
       CASE WHEN o.status IN ('paid', 'delivered', 'shipped')
            THEN o.created_at + interval '1 hour'
            ELSE NULL
       END
FROM orders AS o
WHERE o.status <> 'cancelled';

-- ------------------------------------------------------------
-- 11. Отзывы: 900 строк, часть без комментария.
-- ------------------------------------------------------------
INSERT INTO reviews (id, user_id, product_id, score, comment, created_at)
OVERRIDING SYSTEM VALUE
SELECT g,
       1 + ((g * 23) % 1000),
       1 + ((g * 29) % 1200),
       1 + (abs(hashtext('review-' || g)) % 5),
       CASE WHEN g % 4 = 0 THEN NULL
            ELSE (ARRAY['Отлично', 'Хорошо', 'Нормально', 'Не рекомендую'])[1 + (g % 4)]
                 || ', заказ №' || g
       END,
       now() - ((g % 200) || ' days')::interval
FROM generate_series(1, 900) AS g;

-- ------------------------------------------------------------
-- 12. Доставки: по оплаченным, доставленным и отправленным заказам.
-- ------------------------------------------------------------
INSERT INTO deliveries (id, order_id, address_id, delivery_status, delivery_date)
OVERRIDING SYSTEM VALUE
SELECT row_number() OVER (ORDER BY o.id)::bigint,
       o.id,
       a.id,
       CASE WHEN o.status = 'delivered' THEN 'delivered'
            WHEN o.status = 'shipped'   THEN 'in_transit'
            ELSE 'pending'
       END,
       CASE WHEN o.status = 'delivered'
            THEN o.created_at + interval '3 days'
            ELSE NULL
       END
FROM orders AS o
JOIN addresses AS a ON a.user_id = o.user_id
WHERE o.status IN ('paid', 'delivered', 'shipped');

-- ------------------------------------------------------------
-- 13. Синхронизация последовательностей IDENTITY с данными.
-- ------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('users', 'id'),      (SELECT max(id) FROM users));
SELECT setval(pg_get_serial_sequence('sellers', 'id'),    (SELECT max(id) FROM sellers));
SELECT setval(pg_get_serial_sequence('categories', 'id'), (SELECT max(id) FROM categories));
SELECT setval(pg_get_serial_sequence('products', 'id'),   (SELECT max(id) FROM products));
SELECT setval(pg_get_serial_sequence('carts', 'id'),      (SELECT max(id) FROM carts));
SELECT setval(pg_get_serial_sequence('orders', 'id'),     (SELECT max(id) FROM orders));
SELECT setval(pg_get_serial_sequence('payments', 'id'),   (SELECT max(id) FROM payments));
SELECT setval(pg_get_serial_sequence('reviews', 'id'),    (SELECT max(id) FROM reviews));
SELECT setval(pg_get_serial_sequence('addresses', 'id'),  (SELECT max(id) FROM addresses));
SELECT setval(pg_get_serial_sequence('deliveries', 'id'), (SELECT max(id) FROM deliveries));

COMMIT;

ANALYZE;
