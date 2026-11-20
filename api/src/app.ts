// import { Router } from "express";
// import { createSupabaseClient } from "./lib/supabase.js";
// import { product_list_schema, product_schema } from "./lib/validation/products.js";
import express from "express"
import productRouter from "./routes/products.ts"
import cartRouter from "./routes/cart.ts";

const app = express();
app.use(express.json());
// Matches routes with their corresponding route groups router
app.use("/products", productRouter);
app.use("/cart", cartRouter);
// const router = Router();

// //Honestly it doesnt make sense to just have index be a route by itself. cmon standards charlie ;'v
// // router.get("/", async (req, res) => {
// //   const { supabase, error } = await createSupabaseClient(req);

// //   if (error) {
// //     res.status(error.status).json({ error: error.message });
// //     return;
// //   }

// //   const { data: promotionTable, error: dbError } = await supabase
// //     .from("storefront_banner")
// //     .select("*");
  

  
//   // const { data, error: dbError } = await supabase
//   //   .from("cart_items")
//   //   .select("*");

//   // if (dbError) {
//   //   res.status(500).json({ error: dbError.message });
//   //   return;
//   // }

//   // res.json(data);
// // });


// // Search params vs query params -> tldr (what I aim for is techncially query parameters)
// // This is endpoint to return data for store front or other carousel data
// router.get("/product-search", async (req, res) => {

//   // Validate the query params
//   // const { category, p_query, p_limit } = req.query;
//   const parsed_data = product_list_schema.safeParse(req.query);
//   if(!parsed_data.success){
//     // return ({error: parsed_data.error.issues[0]?.message ?? "An error has occured fetching store data!"})
//     res.status(400).json({error: parsed_data.error.issues[0]?.message ?? "Invalid query parameters"});
//     return;
//   }
//   const { supabase, error } = await createSupabaseClient(req);
//   if(error){
//     res.status(error.status).json({error: error.message ?? "There was an error with authenticating your session"});
//     return;
//   }
//   // After validating the input and assuring there was no error within the validation or the supabase context
//     // Make a request to the rpc based on the requested query data
//     const { data, error: dbError } = await supabase.rpc("search_products", parsed_data.data);
//     if(dbError) {
//       // res.status(500).json({ error: dbError.message ?? "Failed to retrieve Products"})
//       res.status(500).json({ error: "Failed to retrieve Products"}); // dbError could have sens info
//       return; // Hmmmm I'm liking what ive got here so far tbh
//     }
// });


// // This one is specifically to be used when entering to search somthing. (but im not too sure there is something special I have to do when like using the query/ That part is a bit confusing when defining the route)
// router.get("/product", async (req, res) => {
//   // grab the query from req validate its a uuid (lol dont really know its )
//   const parsed_data = product_schema.safeParse(req.query);
//   if(!parsed_data.success) {
//     res.status(400).json({ error: parsed_data.error.issues[0]?.message ?? "Invalid query parameters"});
//     return;
//   }

//   // Upon validating query, check supabase context
//   const {supabase, error} = await createSupabaseClient(req);
//   if(error){
//     res.status(error.status).json({error: error.message ?? "There was an error with authenticating your session"});
//     return;
//   }
//   const data = await supaase
// })


// router.get("/promotions", async (req, res) =>{
//   // 1. try to create a context client via the helper we imported (returns {supab, err})
//   const {supabase, error} = await createSupabaseClient(req);

//   if(error){
//     res.status(error.status).json({error: error.message});
//     return;
//   }

//   // 2. Iff there is no error verifying the claims in the jwt bearer -> we can then interact with the db
//   const { data, error: dbError} = supabase.from("promotions") -> oh right i have to make this shit before hand bc the sdk is like really ugly booger

// });

// export default router;

// // import express, { type Express, type Request, type Response } from "express";
// // import { createClient } from "@supabase/supabase-js";

// // const app: Express = express();
// // const port = 3000;

// // app.get('/homepage', (req: Request, res: Response) => {
// //   // Need to do the following
// //   // Fetch the data need for the home page
// //   // Data needed:
// //     // Promo card data -> lead to search results
// //     // Department
// //   res.send('Hello World!');

// // });

// // app.listen(port, () => {
// //   console.log(`Example app listening on port ${port}`);
// // });