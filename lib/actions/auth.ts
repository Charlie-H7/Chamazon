"use server"
import { RegisterSchema, LoginSchema } from "../validation/authForm";
import { createClient } from "../supabase/server"
import { redirect } from "next/navigation";
// import z from "zod";

// (property) options?: {
//     emailRedirectTo?: string;
//     data?: object;
//     captchaToken?: string;
//     channel?: "sms" | "whatsapp";
// } | undefined
export async function registerAction(form: FormData){
  const supabase = await createClient();
  
  //Verify form data
  // const {error} = RegisterSchema.apply(form.)
  const parsedData = RegisterSchema.safeParse(form);
  if(!parsedData.success){
    return ({error: parsedData.error.issues[0]?.message ?? "An error has occured verifying your information. Make sure the submitted information was correct."})
  } else {
    const {email, password} = parsedData.data;
    const { error } = await supabase.auth.signUp({email: email, password, options:{emailRedirectTo: `${process.env.NEXT_PROJECT_URL ?? "http://localhost:3000"}/auth/callback`}})
    if(error){
      return ({ error: error.message });
    }
  }
  redirect("/email-verification");
}

export async function loginAction(form: FormData){
  const supabase = await createClient();

  const parsedData = LoginSchema.safeParse(form);
  if(!parsedData.success){
    return ({error: parsedData.error.issues[0]?.message ?? "An error has occured verifying your information. Make sure the submitted information was correct."})
  } else {
    const {email, password} = parsedData.data;
    const { error } = await supabase.auth.signInWithPassword({email: email, password: password});
    if(error){
      return ({ error });
    }
    redirect("/");
  }
}

export async function LogoutAction(){
  const supabase = await createClient();
  const { error } = await supabase.auth.signOut();
  if(error) {
    return {error: error.message};
  }
  redirect("/");
}