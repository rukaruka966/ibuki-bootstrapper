# AGENTS.md

## Project

- ID: `__PROJECT_ID__`
- Display name: `__PROJECT_DISPLAY_NAME__`
- Host environment: Windows 11 and PowerShell 7
- Package manager: pnpm

## Systems

- `systems/web-frontend`: React, TypeScript, and Vite
- `systems/api-bff`: Hono and TypeScript

Runnable and deployable units belong directly under `systems/`.

## Commands

Run quality and development tasks through pnpm from the repository root:

```powershell
pnpm run dev
pnpm run lint
pnpm run test
pnpm run typecheck
pnpm run build
pnpm run smoke
pnpm run doctor
```

## API conventions

- Browser-to-BFF endpoints use `/internal/**`.
- Future externally consumed APIs use `/api/v1/**`.
- API errors use RFC 7807 Problem Details.

## Git workflow

- The default branch is `main`.
- Feature work branches from and merges into `develop`.
- Releases merge from `develop` into `main`.
- Direct pushes to `main` and `develop` are prohibited after bootstrap.
- Pull requests require successful CI and resolved review conversations.

Use Conventional Commit messages without scopes:

```text
feat: add user search

Explain why and what changed.
```

## Safety

Stop for explicit confirmation before destructive file operations, data
migrations, compatibility changes, secret exposure, or weaker repository
protection.
