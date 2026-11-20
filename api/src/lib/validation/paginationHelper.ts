import { z } from "zod";

export const paginationSchema = (
  limit: number,
  offset: number = 0
) => {
  return z.object({
    limit: z.coerce.number().int().min(1).max(100).default(limit),
    offset: z.coerce.number().int().min(0).default(offset)
  });
};