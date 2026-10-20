import z from "zod";

export const RegisterSchema = z.object({
  email: z.email(),
  password: z.string().min(8, "Passwords must be at least 8 characters long"),
  confirmPassword: z.string().min(8, "")
}).refine((data) => 
  data.password === data.confirmPassword,
  {
    path: ["confirmPasswords"],
    error: "Passwords must match"
  }
);

export const LoginSchema = z.object({
  email: z.email(),
  password: z.string().min(8, "Passwords must be at least 8 characters long")
});