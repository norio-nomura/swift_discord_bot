import { startCLIBot } from "./deps.ts";
import { serve } from "https://deno.land/std@0.159.0/http/server.ts";

const port = Number(Deno.env.get("PORT") ?? "8080");
const handler = (): Response => new Response("OK", { status: 200 });
serve(handler, { port });

startCLIBot({
  // Set options here
});
