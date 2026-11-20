// fetch things from the cart
import { Router } from "express"
import { createAuthenticatedSupabaseClient } from "../lib/supabase.js";
import { requireAuth } from "../middleware/requireAuth.js";
// Validation
import {
  product_schema,
  cart_schema
} from "../lib/validation/products.ts"

// Types
import type { 
  authenticatedResLocal
} from "../lib/types/resLocals.ts";

import type {
  RequestHandler
} from "express"

// helper functions (cart handler)
const handleCartUpdate: RequestHandler = async (req, res) => {
    // const { supabase, user_id }: authenticatedResLocal = res.locals;
  const { supabase, user_id } = res.locals as authenticatedResLocal; // Type declaration doesnt work as this is passed via middleware and not technically guarunteed to exist outside of middleware
  const parsed_data = cart_schema.safeParse({ 
    product_id: req.params,
    quantity: req.method === "DELETE" ? 0: req.body?.quantity
  });
  if(!parsed_data.success){
    res.status(400).json({ error: parsed_data.error ?? "Ensure you are using a valid product id number" });
    return;
  }
  const { error } = await supabase.rpc("set_cart_item", {
    p_product_id: parsed_data.data.product_id,
    p_quantity: parsed_data.data.quantity
  }); // I wonder if the parameter names have to match the paramater names of the rpc, probably. And I'm gonna have to go for a rename :'v

  // Dont want to return db error (sensitive data) -> double check
  error ? res.status(500).json({ error: "An error has occured while updating your cart item try again (cart post)" }) : 
    res.status(200);
  return;
}

const cartRouter = Router();

// Fetches all of the items for the user and returns all items given by that
cartRouter.get("/cart", requireAuth, async (req, res) => {

  const [ supabase, user_id ] = [ res.locals.supabase, res.locals.user_id ] ;
  // Fetch all of the products currently in the cart for the current user
  // From cart id fetch all associated products for use
  // Fetch products for each of the products tied to them
  // Returns as a list of records 
    // [{product_id: x, quantity: y}, ...]
  const { data, error: dbError } = await supabase.from("cart_items").select("product_id, quantity").eq("user_id", user_id);
  if(dbError){
    res.status(500).json({ error: "An error has occured fetching your cart."});
    return;
  }
  // Then using the list of results I got back from the poducts I've gotten in my carts fetch the product carts im interested in for displaying
  // const cartProductList = data?.map(async (productRecord) => await supabase.from("product_data").select("*").eq("id", user_id)) ?? null; // makes an array of promises
    const productIds = (data ?? []).map(
      (productRecord) => productRecord.product_id
  );

  // If the cart contains no products
  if (productIds.length === 0) {
    res.status(200).json({ data: [] });
    return;
  }

  const { data: products, error: productsError } = await supabase
      .from("product_data")
      .select("id, name, image_path, effective_price")
      .in("id", productIds);
    // const { data: cartData, error: cartDbError } = await supabase.from("product_data").select("*").eq()

  if (productsError) {
    res.status(500).json({ error: "Failed to fetch product information" });
    return;
  }

  res.status(200).json({ data: products });
  return;
});

// // Update cart by adding a product to cart to a cart
// cartRouter.post("/cart/:product_id", requireAuth, (req, res) => {
//   // const { supabase, user_id }: authenticatedResLocal = res.locals;
//   const { supabase, user_id } = res.locals as authenticatedResLocal; // Type declaration doesnt work as this is passed via middleware and not technically guarunteed to exist outside of middleware
//   const parsed_data = cart_schema.safeParse(req.params);
//   if(!parsed_data.success){
//     res.status(400).json({ error: parsed_data.error ?? "Ensure you are using a valid product id number" });
//     return;
//   }
//   const { error } = await supabase.rpc("set_cart_item", {
//     p_product_id: parsed_data.data.product_id,
//     p_quantity: parsed_data.data.quantity
//   }); // I wonder if the parameter names have to match the paramater names of the rpc, probably. And I'm gonna have to go for a rename :'v

//   // Dont want to return db error (sensitive data) -> double check
//   error ? res.status(500).json({ error: "An error has occured while updating your cart item try again (cart post)" }) : 
//     res.status(200);
//   return;
// });

// Update cart by adding a product to cart to a cart
cartRouter.post("/cart/:product_id", requireAuth, handleCartUpdate);
cartRouter.put("/cart/:product_id", requireAuth, handleCartUpdate);
cartRouter.delete("/cart/:product_id", requireAuth, handleCartUpdate);


// // Update cart by deleting items from cart
// cartRouter.delete("cart/:product_id", requireAuth, (req, res) => {
//   const { supabase, user_id } = res.locals as authenticatedResLocal;
//   const 
// });

// cartRouter.put(){

// }





export default cartRouter;