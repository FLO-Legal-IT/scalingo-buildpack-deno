Deno.serve(
  {
    port: Number(Deno.env.get("PORT") ?? 8000),
    hostname: "0.0.0.0",
  },
  () => new Response("ok\n"),
);
