{
  "name": "@__PROJECT_ID__/api-bff",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "test": "vitest run",
    "typecheck": "tsc --noEmit",
    "build": "tsc"
  },
  "dependencies": {
    "@hono/node-server": "2.0.11",
    "hono": "4.12.32"
  },
  "devDependencies": {
    "@types/node": "26.1.1",
    "tsx": "4.23.1",
    "typescript": "7.0.2",
    "vitest": "4.1.10"
  }
}
