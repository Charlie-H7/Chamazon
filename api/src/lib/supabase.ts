// api/src/lib/supabase.ts

import {
  verifyCredentials,
  createContextClient,
} from "@supabase/server/core";

import type { Request } from "express";

export async function createAuthenticatedSupabaseClient(req: Request) {
  const authorization = req.headers.authorization;

  const token = authorization?.startsWith("Bearer ")
    ? authorization.slice(7)
    : null;

  // https://supabase.com/docs/reference/server/primitives-verifycredentials -> verify that the thing that is here is like the way it should be.
  // 1. Why slice at 7 for the authorization heady 
  // 2. where the fuck does `apikey` come from
  // Also between `withSupabase` and `createContextClient` it said something about handling cors or something like that. Is this something I should be worried about??
  const { data: auth, error } = await verifyCredentials(
    { token, apikey: null },
    { auth: "user" }
  );

  if (error) {
    return { supabase: null, user_id: null, error };
  }

  const supabase = createContextClient({
    auth: {
      token: auth.token,
      keyName: auth.keyName,
    },
  });

  return { supabase, user_id: auth.userClaims!.id , error: null };
}


// -----

// import { verifyCredentials, createContextClient } from "@supabase/server/core";
// import type { Request } from "express";

// export async function createSupabaseClient(req: Request) {
//   const authorization = req.headers.authorization;

//   const token = authorization?.startsWith("Bearer ")
//     ? authorization.slice(7)
//     : null;

//   // Verify the user's JWT
//   const { data: auth, error } = await verifyCredentials(
//     { token, apikey: null },
//     { auth: "user" }
//   );

//   if (error) {
//     return { supabase: null, error };
//   }

//   // Create a Supabase client authenticated as that user
//   const supabase = createContextClient(auth.token);

//   return { supabase, error: null };
// }

//=====

// // import { createClient } from "@/lib/supabase/server";
// // import { createClient } from "@/lib/supabase/server";
// import { createServerClient } from "@supabase/ssr";


// export function createSupabaseClient(accessToken: string) {
//   return createClient(
//     process.env.SUPABASE_URL!,
//     process.env.SUPABASE_PUBLISHABLE_KEY!,
//     {
//       accessToken: async () => accessToken,
//     }
//   );
// }