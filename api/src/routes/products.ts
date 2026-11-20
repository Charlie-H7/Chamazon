import { Router } from "express";
import { requireAuth } from "../middleware/requireAuth.js";
import { createAuthenticatedSupabaseClient } from "../lib/supabase.js";
import { 
  get_product_list_schema,
  product_schema,
} from "../lib/validation/products.js";
import {
  post_product_reviews_schema,
  get_product_reviews_schema
} from "../lib/validation/reviews.js"

import type { 
  authenticatedResLocal
} from "../lib/types/resLocals.ts";
import { success } from "zod";


const productRouter = Router();

// Search params vs query params -> tldr (what I aim for is techncially query parameters)
// This is endpoint to return data for store front or other carousel data
productRouter.get("/product-search", requireAuth, async (req, res) => {

  // Validate the query params
  // const { category, p_query, p_limit } = req.query;
  const parsed_data = get_product_list_schema.safeParse(req.query);
  const [ supabase, user_id ] = [ res.locals.supabase, res.locals.user_id ];
  if(!parsed_data.success){
    res.status(400).json({error: parsed_data.error.issues[0]?.message ?? "Invalid query parameters"});
    return;
  }
    // Make a request to the rpc based on the requested query data
    const { data, error: dbError } = await supabase.rpc("search_products", parsed_data.data);
    if(dbError) {
      res.status(500).json({ error: "Failed to retrieve Products"}); // dbError could have sens info, dont display
      return;
    }
    // Otherwise just send the data
    res.status(200).json({data: data});
    return
});


// This one is specifically to be used when entering to search somthing. (but im not too sure there is something special I have to do when like using the query/ That part is a bit confusing when defining the route)
productRouter.get("/:product_id", requireAuth, async (req, res) => {
  // grab the query from req validate its a uuid (lol dont really know its )
  const parsed_data = product_schema.safeParse(req.params);
  const [ supabase, user_id ] = [ res.locals.supabase, res.locals.user_id ];
  if(!parsed_data.success) {
    res.status(400).json({ error: parsed_data.error.issues[0]?.message ?? "Invalid query parameters"});
    return;
  }
  const { data, error: dbError } = await supabase.from("product_data").select("*").eq("id", parsed_data.data["product_id"]);
  if(dbError){
    res.status(500).json({error: "Failed to retrieve product"});
    return;
  }
  // Otherwise just send the data
  res.status(200).json({data: data});
  return;
})

// Endpoint to fetch the resources used for json. (shouldn't require auth)
productRouter.get("/promotions", requireAuth, async (req, res) =>{
  // 1. try to create a context client via the helper we imported (returns {supab, err})
  const { supabase, user_id } = res.locals;
  
  // 2. Iff there is no error verifying the claims in the jwt bearer -> we can then interact with the db
  // const { data, error: dbError} = supabase.from("promotions") -> oh right i have to make this shit before hand bc the sdk is like really ugly booger
  const { data, error: dbError } = await supabase.from("promotions").select("*");
  if(dbError){
    res.status(500).json({ error: "There was a problem with fetching promotions"})
    return;
  }
  
  res.status(200).json({data: data});
  return;
  
});

// ----- Reviews ----- //
// POST METHODS
productRouter.post("/:product_id/review", requireAuth, async(req, res) => {
  // const data = req.body
  // Validate the input
  // const parsed_data = product_review_schema(req.body).safeParse()
  // const parsed_data = post_product_reviews_schema() ummm
  const parsed_data = post_product_reviews_schema.safeParse({ post_req: req.params, ...req.body }); // I'm unsure as to how this part works, like looks like a sep func param and not more arg
  // If the post req does not contain valid review and body
  if(!parsed_data.success){
    res.status(400).json({error: parsed_data.error.issues[0]?.message ?? "A problem has occured with your review submission, please try again!"});
    return;
  }

  // If no error has occured with the validation of the input
  const { supabase, user_id } = res.locals;
  const { product_id } = parsed_data.data.params;
  const { rating, review } = parsed_data.data;
  const review_record = { user_id: user_id, rating: rating, review: review, product_id: product_id}

  const { data, error: dbError } = await supabase.from("reviews").insert(review_record);
  if(dbError){
    res.status(500).json({error: "An error has occured while submiting your review."});
    return;
  }
  res.status(201);

});

productRouter.get("/:product_id/review", requireAuth, async(req, res) => {
  const parsed_data = get_product_reviews_schema.safeParse(req)
  // EXAMPLE: if i did pagination I would need a separate schema bc i cant add onto product_schema as i use that somewhere else. Unless theres like some method/ things i dont know about like optional query parameters and enforcing them or something?
  if(!parsed_data.success){
    res.status(400).json({ error: "Please use a valid product id." })
    return
  }
  const data = { 
    product_id: parsed_data.data.params.product_id,
    ...parsed_data.data.query
  };
  // Retrieve supabase instances
  const { supabase } = res.locals as authenticatedResLocal;
  // Retrieve the reviews for the given product
  // const { error } = await supabase.from("reviews").select("*").eq("product_id", product_id);
  const { error } = await supabase.rpc("fetch_product_reviews", data);
});



// make a page to list out like the reviews on a product page? make separate link tbh not really sure until I see how it looks and then decide

// // This one is specifically to be used when entering to search somthing. (but im not too sure there is something special I have to do when like using the query/ That part is a bit confusing when defining the route)
// productRouter.get("/product", async (req, res) => {
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
//   // const data = await supabase.rpc()

//   // const { data, error: dbError } = await supabase.from("products").select(
//   //   "name",
//   //   "description",
//   //   "description"
//   // ).
//   const { data, error: dbError } = await supabase.from("product_data").select("*").eq("id", parsed_data.data["product_id"]);
//   if(dbError){
//     res.status(500).json({error: "Failed to retrieve product"});
//     return;
//   }

//   // Otherwise just send the data
//   res.status(200).json({data: data});
//   return;
// })
export default productRouter;

// import express, { type Express, type Request, type Response } from "express";
// import { createClient } from "@supabase/supabase-js";

// const app: Express = express();
// const port = 3000;

// app.get('/homepage', (req: Request, res: Response) => {
//   // Need to do the following
//   // Fetch the data need for the home page
//   // Data needed:
//     // Promo card data -> lead to search results
//     // Department
//   res.send('Hello World!');

// });

// app.listen(port, () => {
//   console.log(`Example app listening on port ${port}`);
// });




// ------

/*
import { Router } from "express";
import { requireAuth } from "../migrations/requireAuth.ts";
import { createAuthenticatedSupabaseClient } from "../lib/supabase.js";
import { 
  get_product_list_schema,
  product_schema,
} from "../lib/validation/products.js";
import {
  post_product_reviews_schema,
  get_product_reviews_schema
} from "../lib/validation/reviews.js"

import type { 
  authenticatedResLocal
} from "../lib/types/resLocals.ts";
import { success } from "zod";


const productRouter = Router();

//Honestly it doesnt make sense to just have index be a route by itself. cmon standards charlie ;'v
// router.get("/", async (req, res) => {
//   const { supabase, error } = await createSupabaseClient(req);

//   if (error) {
//     res.status(error.status).json({ error: error.message });
//     return;
//   }

//   const { data: promotionTable, error: dbError } = await supabase
//     .from("storefront_banner")
//     .select("*");
  

  
  // const { data, error: dbError } = await supabase
  //   .from("cart_items")
  //   .select("*");

  // if (dbError) {
  //   res.status(500).json({ error: dbError.message });
  //   return;
  // }

  // res.json(data);
// });


// Search params vs query params -> tldr (what I aim for is techncially query parameters)
// This is endpoint to return data for store front or other carousel data
productRouter.get("/product-search", requireAuth, async (req, res) => {

  // Validate the query params
  // const { category, p_query, p_limit } = req.query;
  const parsed_data = product_list_schema.safeParse(req.query);
  const [ supabase, user_id ] = [ res.locals.supabase, res.locals.user_id ];
  if(!parsed_data.success){
    res.status(400).json({error: parsed_data.error.issues[0]?.message ?? "Invalid query parameters"});
    return;
  }
    // Make a request to the rpc based on the requested query data
    const { data, error: dbError } = await supabase.rpc("search_products", parsed_data.data);
    if(dbError) {
      res.status(500).json({ error: "Failed to retrieve Products"}); // dbError could have sens info, dont display
      return;
    }
    // Otherwise just send the data
    res.status(200).json({data: data});
    return
});


// This one is specifically to be used when entering to search somthing. (but im not too sure there is something special I have to do when like using the query/ That part is a bit confusing when defining the route)
productRouter.get("/:product_id", requireAuth, async (req, res) => {
  // grab the query from req validate its a uuid (lol dont really know its )
  const parsed_data = product_schema.safeParse(req.params);
  const [ supabase, user_id ] = [ res.locals.supabase, res.locals.user_id ];
  if(!parsed_data.success) {
    res.status(400).json({ error: parsed_data.error.issues[0]?.message ?? "Invalid query parameters"});
    return;
  }
  const { data, error: dbError } = await supabase.from("product_data").select("*").eq("id", parsed_data.data["product_id"]);
  if(dbError){
    res.status(500).json({error: "Failed to retrieve product"});
    return;
  }
  // Otherwise just send the data
  res.status(200).json({data: data});
  return;
})

// Endpoint to fetch the resources used for json. (shouldn't require auth)
productRouter.get("/promotions", requireAuth, async (req, res) =>{
  // 1. try to create a context client via the helper we imported (returns {supab, err})
  const { supabase, user_id } = res.locals;
  
  // 2. Iff there is no error verifying the claims in the jwt bearer -> we can then interact with the db
  // const { data, error: dbError} = supabase.from("promotions") -> oh right i have to make this shit before hand bc the sdk is like really ugly booger
  const { data, error: dbError } = await supabase.from("promotions").select("*");
  if(dbError){
    res.status(500).json({ error: "There was a problem with fetching promotions"})
    return;
  }
  
  res.status(200).json({data: data});
  return;
  
});

// POST METHODS
productRouter.post("/:product_id/review", requireAuth, async(req, res) => {
  // const data = req.body
  // Validate the input
  // const parsed_data = product_review_schema(req.body).safeParse()
  const parsed_data = product_review_schema.safeParse(req.body);
  const parsed_product_id = product_schema.safeParse(req.params);
  // If the post req does not contain valid review and body
  if(!parsed_data.success){
    res.status(400).json({error: parsed_data.error.issues[0]?.message ?? "A problem has occured with your review submission, please try again!"});
    return;
  } 
  if(!parsed_product_id.success){
    res.status(400).json({ error: parsed_product_id.error.issues[0]?.message ?? "Invalid product id parameter"});
    return;
  }

  // If no error has occured with the validation of the input
  const { supabase, user_id } = res.locals;
  const { product_id } = req.params;
  const { rating, review } = parsed_data.data;
  const review_record = { user_id: user_id, rating: rating, review: review, product_id: product_id}

  const { data, error: dbError } = await supabase.from("reviews").insert(review_record);
  if(dbError){
    res.status(500).json({error: "An error has occured while submiting your review."});
    return;
  }
  res.status(201);

});

productRouter.get("/:product_id/review", requireAuth, async(req, res) => {
  const parsed_data = product_schema.safeParse(req.params);
  // EXAMPLE: if i did pagination I would need a separate schema bc i cant add onto product_schema as i use that somewhere else. Unless theres like some method/ things i dont know about like optional query parameters and enforcing them or something?
  if(!parsed_data.success){
    res.status(400).json({ error: "Please use a valid product id." })
    return
  }
  const { product_id } = parsed_data.data;
  // Retrieve supabase instances
  const { supabase } = res.locals as authenticatedResLocal;
  // Retrieve the reviews for the given product
  // const { error } = await supabase.from("reviews").select("*").eq("product_id", product_id);
  const { error } = await supabase.rpc("product_reviews", {})
});



// make a page to list out like the reviews on a product page? make separate link tbh not really sure until I see how it looks and then decide

// // This one is specifically to be used when entering to search somthing. (but im not too sure there is something special I have to do when like using the query/ That part is a bit confusing when defining the route)
// productRouter.get("/product", async (req, res) => {
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
//   // const data = await supabase.rpc()

//   // const { data, error: dbError } = await supabase.from("products").select(
//   //   "name",
//   //   "description",
//   //   "description"
//   // ).
//   const { data, error: dbError } = await supabase.from("product_data").select("*").eq("id", parsed_data.data["product_id"]);
//   if(dbError){
//     res.status(500).json({error: "Failed to retrieve product"});
//     return;
//   }

//   // Otherwise just send the data
//   res.status(200).json({data: data});
//   return;
// })
export default productRouter;

// import express, { type Express, type Request, type Response } from "express";
// import { createClient } from "@supabase/supabase-js";

// const app: Express = express();
// const port = 3000;

// app.get('/homepage', (req: Request, res: Response) => {
//   // Need to do the following
//   // Fetch the data need for the home page
//   // Data needed:
//     // Promo card data -> lead to search results
//     // Department
//   res.send('Hello World!');

// });

// app.listen(port, () => {
//   console.log(`Example app listening on port ${port}`);
// });



*/