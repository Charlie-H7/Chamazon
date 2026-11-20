import { SupabaseClient } from "@supabase/supabase-js";

export type authenticatedResLocal = {
  supabase: SupabaseClient,
  user_id: string
}