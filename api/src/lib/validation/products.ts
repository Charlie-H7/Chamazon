// import type { ZodAny } from "zod";
import { z } from "zod";
import { paginationSchema } from "./paginationHelper.ts";

// export const product_list_schema = z.object({
//   p_query: z.string().optional(),
//   p_category_id: z.string().optional(),
//   p_limit: z.coerce.number().int().positive().max(100).default(24),
//   p_offset: z.coerce.number().int().positive().default(0)
// });

// Composite and generic schemas
const pagination_product_list = paginationSchema(24,0);

const product_list_query_schema = z.object({
  p_query: z.string().optional(),
  p_category_id: z.string().optional(),
  p_limit: pagination_product_list.shape.limit,
  p_offset: pagination_product_list.shape.offset
});


export const product_schema = z.object({
  product_id: z.uuid()
});

// Fetching schema

export const get_product_list_schema = z.object({
  query: product_list_query_schema
});




// Cart Validation
export const cart_schema = z.object({
  product_id: z.uuid(),
  quantity: z.number().int().min(0).default(0)
})