import { Hono } from "hono";

export const app = new Hono();

app.get("/internal/health", (context) =>
  context.json({
    status: "ok",
    service: "api-bff",
  }),
);

app.notFound((context) =>
  context.json(
    {
      type: "about:blank",
      title: "Not Found",
      status: 404,
      detail: `No route matches ${context.req.method} ${context.req.path}.`,
      instance: context.req.path,
    },
    404,
    {
      "Content-Type": "application/problem+json",
    },
  ),
);
