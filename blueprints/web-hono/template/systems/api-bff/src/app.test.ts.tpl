import { describe, expect, it } from "vitest";

import { app } from "./app";

describe("API BFF", () => {
  it("reports health", async () => {
    const response = await app.request("/internal/health");

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      status: "ok",
      service: "api-bff",
    });
  });

  it("returns RFC 7807 problem details for unknown routes", async () => {
    const response = await app.request("/missing");

    expect(response.status).toBe(404);
    expect(response.headers.get("content-type")).toContain(
      "application/problem+json",
    );
    await expect(response.json()).resolves.toMatchObject({
      title: "Not Found",
      status: 404,
      instance: "/missing",
    });
  });
});
