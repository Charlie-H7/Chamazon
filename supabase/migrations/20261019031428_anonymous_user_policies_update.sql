BEGIN; -- assures atomicity (all commited or nothing is)

DROP POLICY IF EXISTS reviews_insert ON public.reviews;
DROP POLICY IF EXISTS reviews_delete ON public.reviews;
DROP POLICY IF EXISTS reviews_update ON public.reviews;
DROP POLICY IF EXISTS wishlist_own ON public.wishlist_items;

DROP TABLE public.wishlist_items;

CREATE TABLE public.wishlist(
    wishlist_id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    is_public boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.wishlist_items(
    wishlist_id uuid NOT NULL REFERENCES public.wishlist(wishlist_id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE, -- this part doesnt matter to much since I restrict on order items although technically shouldn't delete products but mark inactive
    PRIMARY KEY (wishlist_id, product_id)
);

CREATE INDEX wishlists_user_idx ON public.wishlist(user_id);
CREATE INDEX wishlist_product_idx ON public.wishlist_items(product_id);

-- Explicitly state which priveleges users have
REVOKE ALL ON public.wishlist, public.wishlist_items FROM PUBLIC, anon, authenticated;
GRANT INSERT ON public.wishlist, public.wishlist_items TO authenticated;
GRANT SELECT ON public.wishlist, public.wishlist_items TO anon, authenticated;
GRANT DELETE ON public.wishlist, public.wishlist_items TO authenticated;
GRANT UPDATE (is_public) ON public.wishlist TO authenticated;
-- DONT worry about granting update to wishlist_items, This operation is not applicable
GRANT ALL on public.wishlist, public.wishlist_items TO service_role;

ALTER TABLE public.wishlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wishlist_items ENABLE ROW LEVEL SECURITY;
-- anonymousUser shouldn't be able to 
-- 1. write reviews
-- 2. update reviews
-- 3. delete reviews
-- 4. For all wishlist -> just assume that the user needs to be auth to interact with wishlist. Make migration to let them read but not create/update/del



CREATE POLICY reviews_insert ON public.reviews FOR INSERT to authenticated
    WITH CHECk (user_id = (SELECT auth.uid()) AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false);
CREATE POLICY reviews_update ON public.reviews FOR UPDATE to authenticated
    USING(user_id = (SELECT auth.uid()) AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false)
    WITH CHECK(user_id = (SELECT auth.uid()));
CREATE POLICY reviews_delete ON public.reviews FOR DELETE to authenticated
    USING (user_id = (SELECT auth.uid()) AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false);


-- Wishlist policies
CREATE POLICY wishlist_create ON public.wishlist FOR INSERT TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()) AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false);
CREATE POLICY wishlist_read ON public.wishlist FOR SELECT TO anon, authenticated
    USING(
        user_id = (SELECT auth.uid()) AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false
        OR 
        is_public = true
        -- (SELECT (is_public) FROM public.wishlist WHERE (is_public = true))
    );
CREATE POLICY wishlist_delete ON public.wishlist FOR DELETE TO authenticated
    USING(user_id = (SELECT auth.uid()) AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false);
CREATE POLICY wishlist_update ON public.wishlist FOR UPDATE TO authenticated 
    USING(user_id = (SELECT auth.uid()) AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false)
    WITH CHECK(user_id = (SELECT auth.uid()));

CREATE POLICY wishlist_items_insert ON public.wishlist_items FOR INSERT TO authenticated
    WITH CHECK(
        (EXISTS(SELECT 1 FROM public.wishlist AS w 
        WHERE(wishlist_items.wishlist_id = w.wishlist_id) 
            AND w.user_id = (SELECT auth.uid()))) 
        AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false)
    ;

CREATE POLICY wishlist_items_delete ON public.wishlist_items FOR DELETE TO authenticated
    USING(
        (EXISTS(SELECT 1 FROM public.wishlist AS w 
        WHERE wishlist_items.wishlist_id = w.wishlist_id
            AND w.user_id = (SELECT auth.uid())))
        AND (SELECT auth.jwt() ->> 'is_anonymous')::boolean = false
    );

-- Parent table already checks whether the wishlist is already public
-- DONT need to check if it is public here
CREATE POLICY wishlist_items_read ON public.wishlist_items FOR SELECT to anon, authenticated
    USING(
        EXISTS(SELECT 1 FROM public.wishlist AS w
        WHERE(wishlist_items.wishlist_id = w.wishlist_id))
    );

-- Dont need RLS Policy for UPDATE as we revoke UPDATE for public.wishlist_items


COMMIT;