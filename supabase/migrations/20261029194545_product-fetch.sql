BEGIN;

CREATE OR REPLACE VIEW public.product_data
WITH (security_invoker = true)
AS
SELECT
    p.id,
    p.name,
    p.description,
    p.price,
    p.is_active,
    p.image_path,

    COALESCE(cat.categories, '[]'::jsonb) AS categories,

    rev.average_rating,
    COALESCE(rev.review_count, 0) AS review_count,

    -- Discount information
    d.sale_price,
    COALESCE(d.sale_price, p.price) AS effective_price,
    (d.product_id IS NOT NULL) AS on_sale

FROM public.products AS p

-- Aggregate product categories
LEFT JOIN (
    SELECT
        pc.product_id,
        jsonb_agg(
            jsonb_build_object(
                'id', c.id,
                'name', c.name
            )
            ORDER BY c.name
        ) AS categories
    FROM public.product_categories AS pc
    JOIN public.categories AS c
        ON pc.category_id = c.id
    GROUP BY pc.product_id
) AS cat
    ON cat.product_id = p.id

-- Aggregate review ratings
LEFT JOIN (
    SELECT
        product_id,
        ROUND(AVG(rating), 2) AS average_rating,
        COUNT(*) AS review_count
    FROM public.reviews
    GROUP BY product_id
) AS rev
    ON rev.product_id = p.id

-- Join only currently active discounts
LEFT JOIN public.product_discounts AS d
    ON d.product_id = p.id
    AND (d.starts_at IS NULL OR d.starts_at <= NOW())
    AND (d.ends_at IS NULL OR d.ends_at > NOW())

WHERE p.is_active = true;



-- Function for retrieving more reviews from an onset
    -- will plan to work off of pagination and not infinite scroll, doesnt make much sense
    -- Security invoker uses client authorization
CREATE OR REPLACE FUNCTION public.fetch_product_reviews(
    product_id uuid,
    review_sort text DEFAULT 'rating_desc',
    review_limit integer DEFAULT 10,
    review_offset integer DEFAULT 0
)
RETURNS TABLE (
    name text,
    review text,
    rating integer,
    created timestamptz
)
LANGUAGE sql
STABLE 
SECURITY INVOKER
SET search_path = '' 
AS $$
    SELECT
        u.name,
        r.review, 
        r.rating,
        r.created_at
    FROM public.reviews r
    JOIN public.users u ON r.user_id = u.user_id 
    WHERE r.product_id = fetch_product_reviews.product_id
    ORDER BY
    -- If review_sort = 'rating_desc': highest-rated reviews first, with newer reviews winning ties.
    -- If review_sort is anything else: newest reviews first, regardless of rating.
        CASE WHEN review_sort = 'rating_desc'
            THEN r.rating 
            END DESC NULLS LAST,
        r.created_at DESC,
        r.user_id DESC -- Used for tiebreakers (since user and product is composite key)
    LIMIT LEAST(GREATEST(COALESCE(review_limit, 10), 1), 100)
    OFFSET GREATEST(COALESCE(review_offset, 0), 0);
$$

COMMIT;

--     LIMIT LEAST(GREATEST(COALESCE(p_limit, 10), 1), 100)
    -- OFFSET GREATEST(COALESCE(p_offset, 0), 0);


-- BEGIN;

-- CREATE VIEW public.product_data
-- WITH (security_invoker = true)
-- AS
-- SELECT
--     p.id,
--     p.name,
--     p.description,
--     p.price,
--     p.is_active,
--     p.image_path,

--     COALESCE(cat.categories, '[]'::jsonb) AS categories,

--     rev.average_rating,
--     COALESCE(rev.review_count, 0) AS review_count

-- FROM public.products AS p

-- -- Get categories for each product
-- LEFT JOIN (
--     SELECT
--         pc.product_id,
--         jsonb_agg(
--             jsonb_build_object(
--                 'id', c.id,
--                 'name', c.name
--             )
--             ORDER BY c.name
--         ) AS categories

--     FROM public.product_categories AS pc

--     JOIN public.categories AS c
--         ON pc.category_id = c.id

--     GROUP BY pc.product_id
-- ) AS cat
--     ON cat.product_id = p.id

-- -- Calculate average rating and review count
-- LEFT JOIN (
--     SELECT
--         product_id,
--         ROUND(AVG(rating), 2) AS average_rating,
--         COUNT(*) AS review_count

--     FROM public.reviews

--     GROUP BY product_id
-- ) AS rev
--     ON rev.product_id = p.id

-- WHERE p.is_active = true;

-- COMMIT;

-- -- BEGIN;

-- -- CREATE VIEW public.product_data AS
-- --     SELECT
-- --         products.id,
-- --         products.name,
-- --         products.description,
-- --         products.is_active,
-- --         products.image_path,
-- --         product_categories.category,
-- --         (GROUP BY products.id)
-- --     FROM public.products
-- --     JOIN public.product_categories on products.id = product_categories.product_id = products.id
-- --     JOIN public.reviews on products.id = reviews.id -- actually I dont think this makes sense I should probably put this into like the select/groupby


-- -- COMMIT;