-- Fresh Supabase schema. Run as postgres in the SQL editor.
-- Intentionally NOT IF NOT EXISTS: existing tables need a migration,
-- not a script that silently leaves their old definitions in place.
-- Assumptions: store-managed catalog, USD, no stock/variants/shipping yet.
BEGIN;

CREATE TABLE public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL CHECK (length(btrim(name)) > 0),
    description text NOT NULL DEFAULT '',
    price numeric(12,2) NOT NULL CHECK (price >= 0 AND price <> 'NaN'::numeric),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- One cart per user: no separate cart UUID is needed.
CREATE TABLE public.carts (
    user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.cart_items (
    user_id uuid NOT NULL REFERENCES public.carts(user_id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    quantity integer NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (user_id, product_id)
);
CREATE INDEX cart_items_product_idx ON public.cart_items(product_id);

CREATE TABLE public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    -- Reuse the same key when retrying a checkout request.
    checkout_key uuid NOT NULL,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'fulfilled', 'canceled')),
    currency text NOT NULL DEFAULT 'USD' CHECK (currency = 'USD'),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, checkout_key)
);

CREATE TABLE public.order_items (
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    product_name_at_purchase text NOT NULL,
    unit_price_at_purchase numeric(12,2) NOT NULL
        CHECK (unit_price_at_purchase >= 0 AND unit_price_at_purchase <> 'NaN'::numeric),
    quantity integer NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (order_id, product_id)
);
CREATE INDEX order_items_product_idx ON public.order_items(product_id);

CREATE TABLE public.reviews (
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review text NOT NULL CHECK (length(btrim(review)) > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, product_id)
);
CREATE INDEX reviews_product_idx ON public.reviews(product_id);

CREATE TABLE public.wishlist_items (
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, product_id)
);
CREATE INDEX wishlist_items_product_idx ON public.wishlist_items(product_id);

-- Create a profile and cart for every new auth user, including anonymous users.
CREATE FUNCTION public.initialize_store_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    INSERT INTO public.users(id) VALUES (NEW.id);
    INSERT INTO public.carts(user_id) VALUES (NEW.id);
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.initialize_store_user() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER initialize_store_user AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.initialize_store_user();

-- Cover accounts that existed before this schema was installed.
INSERT INTO public.users(id) SELECT id FROM auth.users;
INSERT INTO public.carts(user_id) SELECT id FROM public.users;

-- Cart writes and checkout share a lock, preventing overlapping checkouts
-- or cart edits from losing items. Use this RPC instead of direct item writes.
CREATE FUNCTION public.set_cart_item(p_product_id uuid, p_quantity integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_user uuid := auth.uid();
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
    IF p_quantity IS NULL OR p_quantity < 0 THEN
        RAISE EXCEPTION 'Quantity must be zero or positive';
    END IF;
    PERFORM 1 FROM public.carts WHERE user_id = v_user FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cart not found'; END IF;
    IF p_quantity = 0 THEN
        DELETE FROM public.cart_items WHERE user_id = v_user AND product_id = p_product_id;
        RETURN;
    END IF;
    PERFORM 1 FROM public.products WHERE id = p_product_id AND is_active FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Product unavailable'; END IF;
    INSERT INTO public.cart_items(user_id, product_id, quantity)
    VALUES (v_user, p_product_id, p_quantity)
    ON CONFLICT (user_id, product_id) DO UPDATE SET quantity = EXCLUDED.quantity;
END;
$$;
REVOKE ALL ON FUNCTION public.set_cart_item(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_cart_item(uuid, integer) TO authenticated;

-- Places the whole cart as a PENDING order. Does not charge a payment method.
-- A function call is atomic: an exception rolls back all its changes.
CREATE FUNCTION public.checkout(p_checkout_key uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_user uuid := auth.uid();
    v_order uuid;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
    IF p_checkout_key IS NULL THEN RAISE EXCEPTION 'Checkout key required'; END IF;
    PERFORM 1 FROM public.carts WHERE user_id = v_user FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cart not found'; END IF;
-- SELECT ... INTO v_order saves the matching order ID into a variable.
    SELECT id INTO v_order FROM public.orders
    WHERE user_id = v_user AND checkout_key = p_checkout_key;
    IF FOUND THEN RETURN v_order; END IF;

    IF NOT EXISTS (SELECT 1 FROM public.cart_items WHERE user_id = v_user) THEN
        RAISE EXCEPTION 'Cart is empty';
    END IF;
    -- Hold catalog rows stable until the transaction ends. Updates to price
    -- or availability cannot race between validation and snapshot creation.
    PERFORM p.id FROM public.products p
    JOIN public.cart_items c ON c.product_id = p.id
    WHERE c.user_id = v_user ORDER BY p.id FOR SHARE OF p;

    IF EXISTS (
        SELECT 1 FROM public.cart_items c JOIN public.products p ON p.id = c.product_id
        WHERE c.user_id = v_user AND NOT p.is_active
    ) THEN RAISE EXCEPTION 'Remove unavailable products before checkout'; END IF;
-- This is where your permanent purchase record gets created:
    INSERT INTO public.orders(user_id, checkout_key)
    VALUES (v_user, p_checkout_key) RETURNING id INTO v_order;
    INSERT INTO public.order_items(order_id, product_id, product_name_at_purchase,
                                  unit_price_at_purchase, quantity)
    SELECT v_order, p.id, p.name, p.price, c.quantity
    FROM public.cart_items c JOIN public.products p ON p.id = c.product_id
    WHERE c.user_id = v_user;
    DELETE FROM public.cart_items WHERE user_id = v_user;
    RETURN v_order;
END;
$$;
REVOKE ALL ON FUNCTION public.checkout(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.checkout(uuid) TO authenticated;

-- Explicit privileges: clients cannot manufacture orders, set prices, or
-- bypass the cart RPC. Catalog/status administration is trusted backend work.
REVOKE ALL ON public.users, public.products, public.carts, public.cart_items,
    public.orders, public.order_items, public.reviews, public.wishlist_items
    FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.products, public.reviews TO anon, authenticated;
GRANT SELECT ON public.users, public.carts, public.cart_items, public.orders,
    public.order_items, public.wishlist_items TO authenticated;
GRANT UPDATE (name) ON public.users TO authenticated;
GRANT INSERT (user_id, product_id, rating, review), UPDATE (rating, review), DELETE
    ON public.reviews TO authenticated;
GRANT INSERT (user_id, product_id), DELETE ON public.wishlist_items TO authenticated;
GRANT ALL ON public.users, public.products, public.carts, public.cart_items,
    public.orders, public.order_items, public.reviews, public.wishlist_items TO service_role;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wishlist_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY users_read ON public.users FOR SELECT TO authenticated
    USING (id = (SELECT auth.uid()));
CREATE POLICY users_edit ON public.users FOR UPDATE TO authenticated
    USING (id = (SELECT auth.uid())) WITH CHECK (id = (SELECT auth.uid()));
-- Inactive catalog entries remain readable for old carts and receipts.
-- Storefront queries should filter is_active = true.
CREATE POLICY products_read ON public.products FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY carts_read ON public.carts FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));
CREATE POLICY cart_items_read ON public.cart_items FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));
CREATE POLICY orders_read ON public.orders FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));
CREATE POLICY order_items_read ON public.order_items FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.orders o
                  WHERE o.id = order_id AND o.user_id = (SELECT auth.uid())));
CREATE POLICY reviews_read ON public.reviews FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY reviews_insert ON public.reviews FOR INSERT TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY reviews_update ON public.reviews FOR UPDATE TO authenticated
    USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY reviews_delete ON public.reviews FOR DELETE TO authenticated
    USING (user_id = (SELECT auth.uid()));
CREATE POLICY wishlist_own ON public.wishlist_items FOR ALL TO authenticated
    USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

COMMIT;


-- -- Fresh Supabase schema. Run as postgres in the SQL editor.
-- -- Intentionally NOT IF NOT EXISTS: existing tables need a migration,
-- -- not a script that silently leaves their old definitions in place.
-- -- Assumptions: store-managed catalog, USD, no stock/variants/shipping yet.
-- BEGIN;

-- CREATE TABLE public.users (
--     id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
--     name text,
--     created_at timestamptz NOT NULL DEFAULT now()
-- );

-- CREATE TABLE public.products (
--     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
--     name text NOT NULL CHECK (length(btrim(name)) > 0),
--     description text NOT NULL DEFAULT '',
--     price numeric(12,2) NOT NULL CHECK (price >= 0 AND price <> 'NaN'::numeric),
--     is_active boolean NOT NULL DEFAULT true,
--     created_at timestamptz NOT NULL DEFAULT now()
-- );

-- -- One cart per user: no separate cart UUID is needed.
-- CREATE TABLE public.carts (
--     user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
--     created_at timestamptz NOT NULL DEFAULT now()
-- );

-- CREATE TABLE public.cart_items (
--     user_id uuid NOT NULL REFERENCES public.carts(user_id) ON DELETE CASCADE,
--     product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
--     quantity integer NOT NULL CHECK (quantity > 0),
--     PRIMARY KEY (user_id, product_id)
-- );
-- CREATE INDEX cart_items_product_idx ON public.cart_items(product_id);

-- -- Wouldn't there just always be one order per user, since user_id is a primary key
-- CREATE TABLE public.orders (
--     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
--     user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
--     -- Reuse the same key when retrying a checkout request.
--     checkout_key uuid NOT NULL,
--     status text NOT NULL DEFAULT 'pending'
--         CHECK (status IN ('pending', 'paid', 'fulfilled', 'canceled')),
--     currency text NOT NULL DEFAULT 'USD' CHECK (currency = 'USD'),
--     created_at timestamptz NOT NULL DEFAULT now(),
--     UNIQUE (user_id, checkout_key)
-- );

-- -- explain the restrict shit? like whats the idea behind it
-- CREATE TABLE public.order_items (
--     order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE RESTRICT,
--     product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
--     product_name_at_purchase text NOT NULL,
--     unit_price_at_purchase numeric(12,2) NOT NULL
--         CHECK (unit_price_at_purchase >= 0 AND unit_price_at_purchase <> 'NaN'::numeric),
--     quantity integer NOT NULL CHECK (quantity > 0),
--     PRIMARY KEY (order_id, product_id)
-- );
-- CREATE INDEX order_items_product_idx ON public.order_items(product_id);

-- CREATE TABLE public.reviews (
--     user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
--     product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
--     rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
--     review text NOT NULL CHECK (length(btrim(review)) > 0),
--     created_at timestamptz NOT NULL DEFAULT now(),
--     PRIMARY KEY (user_id, product_id)
-- );
-- CREATE INDEX reviews_product_idx ON public.reviews(product_id);

-- CREATE TABLE public.wishlist_items (
--     user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
--     product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
--     created_at timestamptz NOT NULL DEFAULT now(),
--     PRIMARY KEY (user_id, product_id)
-- );
-- CREATE INDEX wishlist_items_product_idx ON public.wishlist_items(product_id);

-- -- Create a profile and cart for every new auth user, including anonymous users.
-- CREATE FUNCTION public.initialize_store_user() RETURNS trigger
-- LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
-- BEGIN
--     INSERT INTO public.users(id) VALUES (NEW.id);
--     INSERT INTO public.carts(user_id) VALUES (NEW.id);
--     RETURN NEW;
-- END;
-- $$;
-- REVOKE ALL ON FUNCTION public.initialize_store_user() FROM PUBLIC, anon, authenticated;
-- CREATE TRIGGER initialize_store_user AFTER INSERT ON auth.users
-- FOR EACH ROW EXECUTE FUNCTION public.initialize_store_user();

-- -- Cover accounts that existed before this schema was installed.
-- INSERT INTO public.users(id) SELECT id FROM auth.users;
-- INSERT INTO public.carts(user_id) SELECT id FROM public.users;

-- -- Cart writes and checkout share a lock, preventing overlapping checkouts
-- -- or cart edits from losing items. Use this RPC instead of direct item writes.
-- CREATE FUNCTION public.set_cart_item(p_product_id uuid, p_quantity integer)
-- RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
-- DECLARE
--     v_user uuid := auth.uid();
-- BEGIN
--     IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
--     IF p_quantity IS NULL OR p_quantity < 0 THEN
--         RAISE EXCEPTION 'Quantity must be zero or positive';
--     END IF;
--     PERFORM 1 FROM public.carts WHERE user_id = v_user FOR UPDATE;
--     IF NOT FOUND THEN RAISE EXCEPTION 'Cart not found'; END IF;
--     IF p_quantity = 0 THEN
--         DELETE FROM public.cart_items WHERE user_id = v_user AND product_id = p_product_id;
--         RETURN;
--     END IF;
--     PERFORM 1 FROM public.products WHERE id = p_product_id AND is_active FOR SHARE;
--     IF NOT FOUND THEN RAISE EXCEPTION 'Product unavailable'; END IF;
--     INSERT INTO public.cart_items(user_id, product_id, quantity)
--     VALUES (v_user, p_product_id, p_quantity)
--     ON CONFLICT (user_id, product_id) DO UPDATE SET quantity = EXCLUDED.quantity;
-- END;
-- $$;
-- REVOKE ALL ON FUNCTION public.set_cart_item(uuid, integer) FROM PUBLIC, anon, authenticated;
-- GRANT EXECUTE ON FUNCTION public.set_cart_item(uuid, integer) TO authenticated;

-- -- Places the whole cart as a PENDING order. Does not charge a payment method.
-- -- A function call is atomic: an exception rolls back all its changes.
-- CREATE FUNCTION public.checkout(p_checkout_key uuid)
-- RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
-- DECLARE
--     v_user uuid := auth.uid();
--     v_order uuid;
-- BEGIN
--     IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
--     IF p_checkout_key IS NULL THEN RAISE EXCEPTION 'Checkout key required'; END IF;
--     PERFORM 1 FROM public.carts WHERE user_id = v_user FOR UPDATE;
--     IF NOT FOUND THEN RAISE EXCEPTION 'Cart not found'; END IF;

--     SELECT id INTO v_order FROM public.orders
--     WHERE user_id = v_user AND checkout_key = p_checkout_key;
--     IF FOUND THEN RETURN v_order; END IF;

--     IF NOT EXISTS (SELECT 1 FROM public.cart_items WHERE user_id = v_user) THEN
--         RAISE EXCEPTION 'Cart is empty';
--     END IF;
--     -- Hold catalog rows stable until the transaction ends. Updates to price
--     -- or availability cannot race between validation and snapshot creation.
--     PERFORM p.id FROM public.products p
--     JOIN public.cart_items c ON c.product_id = p.id
--     WHERE c.user_id = v_user ORDER BY p.id FOR SHARE OF p;

--     IF EXISTS (
--         SELECT 1 FROM public.cart_items c JOIN public.products p ON p.id = c.product_id
--         WHERE c.user_id = v_user AND NOT p.is_active
--     ) THEN RAISE EXCEPTION 'Remove unavailable products before checkout'; END IF;

--     INSERT INTO public.orders(user_id, checkout_key)
--     VALUES (v_user, p_checkout_key) RETURNING id INTO v_order;
--     INSERT INTO public.order_items(order_id, product_id, product_name_at_purchase,
--                                   unit_price_at_purchase, quantity)
--     SELECT v_order, p.id, p.name, p.price, c.quantity
--     FROM public.cart_items c JOIN public.products p ON p.id = c.product_id
--     WHERE c.user_id = v_user;
--     DELETE FROM public.cart_items WHERE user_id = v_user;
--     RETURN v_order;
-- END;
-- $$;
-- REVOKE ALL ON FUNCTION public.checkout(uuid) FROM PUBLIC, anon, authenticated;
-- GRANT EXECUTE ON FUNCTION public.checkout(uuid) TO authenticated;

-- -- Explicit privileges: clients cannot manufacture orders, set prices, or
-- -- bypass the cart RPC. Catalog/status administration is trusted backend work.
-- REVOKE ALL ON public.users, public.products, public.carts, public.cart_items,
--     public.orders, public.order_items, public.reviews, public.wishlist_items
--     FROM PUBLIC, anon, authenticated;
-- GRANT SELECT ON public.products, public.reviews TO anon, authenticated;
-- GRANT SELECT ON public.users, public.carts, public.cart_items, public.orders,
--     public.order_items, public.wishlist_items TO authenticated;
-- GRANT UPDATE (name) ON public.users TO authenticated;
-- GRANT INSERT (user_id, product_id, rating, review), UPDATE (rating, review), DELETE
--     ON public.reviews TO authenticated;
-- GRANT INSERT (user_id, product_id), DELETE ON public.wishlist_items TO authenticated;
-- GRANT ALL ON public.users, public.products, public.carts, public.cart_items,
--     public.orders, public.order_items, public.reviews, public.wishlist_items TO service_role;

-- ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.carts ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.wishlist_items ENABLE ROW LEVEL SECURITY;

-- CREATE POLICY users_read ON public.users FOR SELECT TO authenticated
--     USING (id = (SELECT auth.uid()));
-- CREATE POLICY users_edit ON public.users FOR UPDATE TO authenticated
--     USING (id = (SELECT auth.uid())) WITH CHECK (id = (SELECT auth.uid()));
-- -- Inactive catalog entries remain readable for old carts and receipts.
-- -- Storefront queries should filter is_active = true.
-- CREATE POLICY products_read ON public.products FOR SELECT TO anon, authenticated USING (true);
-- CREATE POLICY carts_read ON public.carts FOR SELECT TO authenticated
--     USING (user_id = (SELECT auth.uid()));
-- CREATE POLICY cart_items_read ON public.cart_items FOR SELECT TO authenticated
--     USING (user_id = (SELECT auth.uid()));
-- CREATE POLICY orders_read ON public.orders FOR SELECT TO authenticated
--     USING (user_id = (SELECT auth.uid()));
-- CREATE POLICY order_items_read ON public.order_items FOR SELECT TO authenticated
--     USING (EXISTS (SELECT 1 FROM public.orders o
--                   WHERE o.id = order_id AND o.user_id = (SELECT auth.uid())));
-- CREATE POLICY reviews_read ON public.reviews FOR SELECT TO anon, authenticated USING (true);
-- CREATE POLICY reviews_insert ON public.reviews FOR INSERT TO authenticated
--     WITH CHECK (user_id = (SELECT auth.uid()));
-- CREATE POLICY reviews_update ON public.reviews FOR UPDATE TO authenticated
--     USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
-- CREATE POLICY reviews_delete ON public.reviews FOR DELETE TO authenticated
--     USING (user_id = (SELECT auth.uid()));
-- CREATE POLICY wishlist_own ON public.wishlist_items FOR ALL TO authenticated
--     USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

-- COMMIT;


-- ---------
-- -- -- drop policy if exists

-- -- create table if not exists public.users(
-- --     id uuid primary key references auth.users(id) on delete cascade,
-- --     name text, -- can be null due to anon users
-- --     created timestamptz not null default now()
-- -- );

-- -- create table if not exists public.products(
-- --     id uuid primary key,
-- --     name text not null,
-- --     created timestamptz not null default now()
-- --     -- POSTER USER ID oaahdasohfosuahOIHSFOIHOAH
-- --     -- For right now assume products are static (makes more interesting building off this later anyways :) )
-- -- );

-- -- -- create table if not exists public.cart(
-- -- --     user_id uuid references public.users(id),
-- -- --     pid uuid references public.products(id),
-- -- --     quantity int4 not null,
-- -- --     primary key (user_id, pid)
-- -- --     cart_id uuid -> composite OF THREE AHFDNJFNJDS
-- -- -- );

-- -- create table if not exists public.cart(
-- --     id uuid primary key,
-- --     user_id uuid references public.users(id) on delete cascade unique not null
-- -- );

-- -- create table if not exists public.cartItems(
-- --     cid uuid references public.cart(id) on delete cascade,
-- --     pid uuid references public.products(id) on delete cascade, -- If a product is no longer offered/sold. Want to get rid of them from the current carts
-- --     quantity int4 not null check (quantity > 0),
-- --     primary key (cid, pid)
-- -- );

-- -- -- M2M
-- -- create table if not exists public.userOrders(
-- --     -- pid uuid primary key references public.products(id)
-- --     id uuid primary key,
-- --     user_id uuid references public.users(id) on delete set null, -- If user deleted make orders still accessible. (still good for server side inventory or statistics tracking)
-- --     created timestamptz not null default now()
-- -- );

-- -- -- Don't want cascade delete as it should preserve order history
-- -- create table if not exists public.orderProducts(
-- --     oid uuid references public.userOrders(id) on delete cascade,
-- --     pid uuid references public.products(id) on delete restrict,
-- --     quantity int4 not null check (quantity > 0),
-- --     price numeric(7, 2) not null check (price > 0),
-- --     primary key (oid, pid)
-- -- );

-- -- -- Remove reviews of non-existant users
-- -- create table if not exists public.reviews(
-- --     user_id uuid references public.users(id) on delete cascade,
-- --     pid uuid references public.products(id),
-- --     review text not null,
-- --     created timestamptz not null default now(),
-- --     primary key (user_id, pid)
-- -- );

-- -- --Why the FOREIGN KEY keyword is requiredIf you only write REFERENCES, some databases (like MySQL/MariaDB) will comple
-- -- -- while others (like PostgreSQL) allow a shorthand but still internally create a full Foreign Key constraint.