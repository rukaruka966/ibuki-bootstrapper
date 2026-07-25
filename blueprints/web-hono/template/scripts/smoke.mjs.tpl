import { spawn } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";

const port = 3000;
const baseUrl = `http://127.0.0.1:${port}`;
const child = spawn(
  process.execPath,
  ["systems/api-bff/dist/index.js"],
  {
    env: {
      ...process.env,
      API_PORT: String(port),
    },
    stdio: "inherit",
  },
);

let ready = false;

try {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error(`API process exited with code ${child.exitCode}.`);
    }

    try {
      const response = await fetch(`${baseUrl}/internal/health`);
      const body = await response.json();

      if (response.ok && body.status === "ok" && body.service === "api-bff") {
        ready = true;
        break;
      }
    } catch {
      // The server can refuse connections while it is starting.
    }

    await delay(200);
  }

  if (!ready) {
    throw new Error("API health endpoint did not become ready.");
  }

  console.log(`${__PROJECT_DISPLAY_NAME_JSON__} smoke test passed.`);
} finally {
  child.kill();
}
