"use server"
import { createClient } from "@/lib/supabase/server"
import { NextResponse } from "next/server";

export async function GET(req: Request){
  const supabase = await createClient();
  // Need to get the code that was given after clicking the email link. 
  const url = new URL(req.url);
  // const url = req.url;
  const code = url.searchParams.get("code");
  // const code = url.
  if(code) {
    await supabase.auth.exchangeCodeForSession(code);
  }
  return (NextResponse.redirect(new URL("/", req.url)))
}