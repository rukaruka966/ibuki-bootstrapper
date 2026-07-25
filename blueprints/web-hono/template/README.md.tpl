# __PROJECT_DISPLAY_NAME__

`__PROJECT_ID__` is a pnpm workspace containing a React frontend and a Hono
backend-for-frontend.

## Requirements

- Node.js 24 or later
- pnpm 11 or later
- PowerShell 7

## Start

```powershell
pnpm install
pnpm run dev
```

The frontend runs on `http://127.0.0.1:5173` and the BFF runs on
`http://127.0.0.1:3000`.

## Verify

```powershell
pnpm run lint
pnpm run test
pnpm run typecheck
pnpm run build
pnpm run smoke
pnpm run doctor
```

## Repository workflow

Feature pull requests target `develop`. Release pull requests merge `develop`
into `main`.
