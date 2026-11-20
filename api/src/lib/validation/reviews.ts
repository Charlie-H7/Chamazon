import { z } from "zod";
import { paginationSchema } from "./paginationHelper.ts";
import { product_schema } from "./products.ts";

const pagination_review_list = paginationSchema(10, 0);

// Composite schema
const get_product_reviews_query = z.object({
  limit: pagination_review_list.shape.limit,
  offset: pagination_review_list.shape.offset,
  sort: z.enum(["rating_desc", "newest"]).default("rating_desc")
  // sort: z.string().max(20).default("rating_desc") // Line above does filtering on server as opposed to forwarding invalid sorting query to supabase (no hops required)
})

// SCHEMAS BELOW
// This is used for uploading reviews for a product
export const post_product_reviews_schema = z.object({
  params: product_schema,
  rating: z.coerce.number().int().positive().max(5).min(0),
  review: z.string().max(2000, "Reviews must be less than 2000 characters.").min(1, "Reviews must contain at least one character.")
});

// Fetching product reviews
  // -- requires:
  // -- params: product_id (param)
  // query: limit, offset, sort() filter
export const get_product_reviews_schema = z.object({
  params: product_schema,
  query: get_product_reviews_query
});
