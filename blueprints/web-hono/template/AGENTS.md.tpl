# AGENTS.md

Japanese reference: [`docs/ja-JP/AGENTS-ja.md`](docs/ja-JP/AGENTS-ja.md)

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
pnpm run doctor
```

## API conventions

- Browser-to-BFF endpoints use `/internal/**`.
- Future externally consumed APIs use `/api/v1/**`.
- API errors use RFC 7807 Problem Details.

## Git workflow

- The default branch is `main`.
- Feature work branches from and merges into `develop`.
- Feature Pull Requests use squash merge into `develop`.
- Only `develop` may open a Pull Request targeting `main`.
- Release Pull Requests use a merge commit from `develop` into `main`.
- There is no direct-to-`main` emergency workflow.
- Direct pushes to `main` and `develop` are prohibited after bootstrap.
- Pull requests require successful CI and resolved review conversations.
- Both protected branches require `Quality`. Its release source gate prevents
  accidental misuse, but is not a security boundary because a Pull Request can
  modify its Workflow.
- Required checks are non-strict on `main`, avoiding reverse synchronization
  after a release merge commit, and strict on `develop`, keeping feature Pull
  Requests based on its latest state.

Use Conventional Commit messages without scopes:

```text
feat: add user search

Explain why and what changed.
```

## Safety

Stop for explicit confirmation before destructive file operations, data
migrations, compatibility changes, secret exposure, or weaker repository
protection.

## Definition of Done

A change is complete when all applicable items below are satisfied:

- The requested behavior is implemented without unrelated scope changes.
- Tests cover changed behavior and important failure paths.
- `pnpm run lint`, `pnpm run test`, `pnpm run typecheck`, and
  `pnpm run build` pass from the repository root.
- `pnpm run doctor` passes when dependencies, commands, or environment
  requirements change.
- Documentation and examples match changed commands, contracts, or workflows.
- No secrets, local credentials, build output, or temporary files are tracked.
- Destructive operations, persisted-data changes, compatibility breaks, and
  weaker repository protection have explicit human approval.
- Pull Request CI passes and all review conversations are resolved before merge.
