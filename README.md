# Ibuki Bootstrapper

Ibuki creates a minimal React and Hono project, verifies it locally, and can
provision a private GitHub repository with protected `main` and `develop`
branches.

## Requirements

- Windows 11
- PowerShell 7.6 or later
- Node.js 24 or later
- pnpm 11 or later
- Git for Windows
- GitHub CLI authenticated with `gh auth login`

## Run from `main`

```powershell
irm https://raw.githubusercontent.com/rukaruka966/ibuki-bootstrapper/main/bootstrap.ps1 | iex
```

The public script contains no credentials. GitHub credentials are read by
GitHub CLI only when a private target repository is provisioned.

## Local development

```powershell
pnpm install
pnpm run verify
```

Generate a local project without GitHub changes:

```powershell
pwsh ./bootstrap.ps1 `
  -ProjectId sample-project `
  -DisplayName "Sample Project" `
  -Destination ./sample-project `
  -SkipGitHub `
  -NonInteractive `
  -Yes
```

## v0.1 scope

- React, TypeScript, and Vite frontend
- Hono and TypeScript backend-for-frontend
- Neutral UI shell
- `/internal/health`
- RFC 7807 not-found responses
- Unit tests and a runtime smoke test
- Private GitHub repository provisioning
- Protected `main` and `develop` branches

PostgreSQL, Redis, Docker, Spring Boot, Android, Desktop, authentication, and
semantic-release are intentionally deferred.
