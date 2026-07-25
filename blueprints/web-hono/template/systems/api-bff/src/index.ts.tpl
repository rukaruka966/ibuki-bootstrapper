import { serve } from "@hono/node-server";

import { app } from "./app.js";

const portValue = process.env.API_PORT ?? "3000";
const port = Number.parseInt(portValue, 10);

if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error(`API_PORT must be a valid TCP port. Received: ${portValue}`);
}

serve(
  {
    fetch: app.fetch,
    hostname: "127.0.0.1",
    port,
  },
  (info) => {
    console.log(`API BFF listening on http://127.0.0.1:${info.port}`);
  },
);
