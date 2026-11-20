// export function requireAuth(req, res, next())
import type { RequestHandler } from "express"
import type { Response, Request } from "express"
import { createAuthenticatedSupabaseClient } from "../lib/supabase.js"

// The point of this Middleware is to send the client and abstract error handling from routes that the client is recieved to
export const requireAuth: RequestHandler = async (
  req: Request,
  res: Response,
  next,
) => {
  // Ensure that the function `createSupabaseClient` is successful. If yes move it along to the actual endpoint
  try {
    const { supabase, user_id, error } = await createAuthenticatedSupabaseClient(req);
    if(error || !supabase || !user_id){
      res.status(401).json({ error: error?.message ?? "Authentication failed" })
      return;
    }
    // Save supabase instance and data to pass downstream
    res.locals.supabase = supabase;
    res.locals.user_id = user_id;
    next();
  } catch(error) {
    next(error);
  }
}