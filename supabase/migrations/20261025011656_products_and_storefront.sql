-- Proposed follow-up to 20261019031428_anonymous_user_policies_update.sql.
-- Apply ONCE, after both existing migrations; temp.sql must NOT be applied first.
-- Prepared offline. No live database changes are made by creating this file.
BEGIN;

CREATE TABLE public.categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL CHECK (length(btrim(name)) > 0),
    parent_id uuid REFERENCES public.categories(id) ON DELETE RESTRICT,
    CONSTRAINT categories_not_own_parent CHECK (parent_id <> id)
);
CREATE INDEX categories_parent_idx ON public.categories(parent_id);
-- Multi-level cycles must be prevented by trusted catalog administration.

-- A product can belong to multiple categories; each assignment is unique.
CREATE TABLE public.product_categories (
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    category_id uuid NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
    PRIMARY KEY (product_id, category_id)
);
CREATE INDEX product_categories_category_idx
    ON public.product_categories(category_id, product_id);

-- Zero or one discount per product, not a mandatory discount for every product.
-- The primary key already indexes product_id. Match products.price precision.
CREATE TABLE public.product_discounts (
    product_id uuid PRIMARY KEY REFERENCES public.products(id) ON DELETE CASCADE,
    sale_price numeric(12,2) NOT NULL
        CHECK (sale_price >= 0 AND sale_price <> 'NaN'::numeric),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    CHECK (ends_at > starts_at)
);

CREATE TABLE public.storefront_banners (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL CHECK (length(btrim(title)) > 0),
    image_path text NOT NULL CHECK (length(btrim(image_path)) > 0),
    href text NOT NULL CHECK (length(btrim(href)) > 0),
    sort_order integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    starts_at timestamptz,
    ends_at timestamptz,
    CHECK (starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at)
);

-- Existing products have no known image paths. Preserve them without invented
-- defaults. Backfill real paths before a later migration adds NOT NULL.
ALTER TABLE public.products ADD COLUMN image_path text
    CHECK (image_path IS NULL OR length(btrim(image_path)) > 0);

REVOKE ALL ON public.categories, public.product_categories,
    public.product_discounts, public.storefront_banners
    FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.categories, public.product_categories,
    public.product_discounts, public.storefront_banners TO anon, authenticated;
GRANT ALL ON public.categories, public.product_categories,
    public.product_discounts, public.storefront_banners TO service_role;

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.storefront_banners ENABLE ROW LEVEL SECURITY;

CREATE POLICY categories_read ON public.categories
    FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY product_categories_read ON public.product_categories
    FOR SELECT TO anon, authenticated
    USING (EXISTS (SELECT 1 FROM public.products p
                  WHERE p.id = product_categories.product_id AND p.is_active));
CREATE POLICY product_discounts_read ON public.product_discounts
    FOR SELECT TO anon, authenticated
    USING (now() >= starts_at AND now() < ends_at
           AND EXISTS (SELECT 1 FROM public.products p
                       WHERE p.id = product_discounts.product_id AND p.is_active));
CREATE POLICY storefront_banners_read ON public.storefront_banners
    FOR SELECT TO anon, authenticated
    USING (is_active AND (starts_at IS NULL OR now() >= starts_at)
                     AND (ends_at IS NULL OR now() < ends_at));

-- Invoker rights intentionally respect table grants and row-level policies.
-- Category matching is exact (does not automatically include descendants).
-- Supported sorts: newest and rating_desc; other values fall back to newest.
CREATE OR REPLACE FUNCTION public.search_products(
    p_query text DEFAULT NULL,
    p_category_id uuid DEFAULT NULL,
    p_sort text DEFAULT 'newest',
    p_limit integer DEFAULT 24,
    p_offset integer DEFAULT 0
)
RETURNS TABLE (
    product_id uuid,
    name text,
    description text,
    image_path text,
    regular_price numeric,
    current_price numeric,
    average_rating numeric,
    review_count bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    SELECT
        p.id,
        p.name,
        p.description,
        p.image_path,
        p.price AS regular_price,
        LEAST(p.price, COALESCE(d.sale_price, p.price)) AS current_price,
        ROUND(r.avg_rating, 2) AS average_rating,
        COALESCE(r.review_count, 0::bigint) AS review_count

    FROM public.products p

    -- Active discounts
    LEFT JOIN public.product_discounts d
        ON d.product_id = p.id
        AND now() >= d.starts_at
        AND now() < d.ends_at

    -- Aggregate ratings for each product
    LEFT JOIN (
        SELECT
            product_id,
            AVG(rating)::numeric AS avg_rating,
            COUNT(*) AS review_count
        FROM public.reviews
        GROUP BY product_id
    ) r ON r.product_id = p.id

    WHERE p.is_active = true

    -- Optional text search
    AND (
        p_query IS NULL
        OR p.name ILIKE '%' || p_query || '%'
    )

    -- Optional category filter
    AND (
        p_category_id IS NULL
        OR EXISTS (
            SELECT 1
            FROM public.product_categories pc
            WHERE pc.product_id = p.id
            AND pc.category_id = p_category_id
        )
    )

    ORDER BY
        CASE WHEN p_sort = 'rating_desc'
            THEN r.avg_rating
        END DESC NULLS LAST,

        CASE WHEN p_sort = 'rating_desc'
            THEN r.review_count
        END DESC NULLS LAST,

        p.created_at DESC,
        p.id ASC

    LIMIT LEAST(GREATEST(COALESCE(p_limit, 24), 1), 100)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

REVOKE EXECUTE ON FUNCTION
    public.search_products(text, uuid, text, integer, integer)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.search_products(text, uuid, text, integer, integer)
TO anon, authenticated, service_role;


-- Keep checkout's cart lock, product locks, guest access and idempotency.
-- Snapshot the effective sale price in the existing immutable order items.
-- Discount selection uses the INSERT statement's database snapshot; concurrent
-- discount edits apply to subsequent snapshots. Time windows use transaction now().
-- A catalog price drop below sale_price must never make a "discount" cost more.
CREATE OR REPLACE FUNCTION public.checkout(p_checkout_key uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_user uuid := auth.uid();
    v_order uuid;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
    IF p_checkout_key IS NULL THEN RAISE EXCEPTION 'Checkout key required'; END IF;
    PERFORM 1 FROM public.carts WHERE user_id = v_user FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cart not found'; END IF;
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
    INSERT INTO public.orders(user_id, checkout_key)
    VALUES (v_user, p_checkout_key) RETURNING id INTO v_order;
    INSERT INTO public.order_items(order_id, product_id, product_name_at_purchase,
                                  unit_price_at_purchase, quantity)
    SELECT v_order, p.id, p.name,
           LEAST(p.price, COALESCE(d.sale_price, p.price)), c.quantity
    FROM public.cart_items c JOIN public.products p ON p.id = c.product_id
    LEFT JOIN public.product_discounts d ON d.product_id = p.id
        AND now() >= d.starts_at AND now() < d.ends_at
    WHERE c.user_id = v_user;
    DELETE FROM public.cart_items WHERE user_id = v_user;
    RETURN v_order;
END;
$$;
REVOKE ALL ON FUNCTION public.checkout(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.checkout(uuid) TO authenticated;

-- Ratings are already smallint constrained to 1..5; no type change is needed.
-- A pending checkout is not proof of payment. Only paid/fulfilled orders count.
-- These expressions use the existing owner-only orders/order_items read policies.
DROP POLICY reviews_insert ON public.reviews;
DROP POLICY reviews_update ON public.reviews;

CREATE POLICY reviews_insert ON public.reviews FOR INSERT TO authenticated
    WITH CHECK (
        user_id = (SELECT auth.uid())
        AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false
        AND EXISTS (
            SELECT 1 FROM public.orders o
            JOIN public.order_items oi ON oi.order_id = o.id
            WHERE o.user_id = (SELECT auth.uid())
              AND o.status IN ('paid', 'fulfilled')
              AND oi.product_id = reviews.product_id
        )
    );
CREATE POLICY reviews_update ON public.reviews FOR UPDATE TO authenticated
    USING (user_id = (SELECT auth.uid())
           AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false)
    WITH CHECK (
        user_id = (SELECT auth.uid())
        AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false
        AND EXISTS (
            SELECT 1 FROM public.orders o
            JOIN public.order_items oi ON oi.order_id = o.id
            WHERE o.user_id = (SELECT auth.uid())
              AND o.status IN ('paid', 'fulfilled')
              AND oi.product_id = reviews.product_id
        )
    );
-- Keep reviews_read and reviews_delete: reviews remain public, and permanent
-- owners may remove their reviews even if the qualifying order was canceled.
-- Existing reviews are preserved, not retroactively verified or removed.

COMMIT;
