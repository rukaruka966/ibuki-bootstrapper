# AGENTS.md

## Purpose

This repository contains Ibuki Bootstrapper. It safely generates React and Hono
or Kotlin and Spring Boot project files and can provision a private GitHub
repository. Generated-project commands belong to that project and are not part
of Bootstrapper success.

## Environment

- Windows 11
- PowerShell 7.6 or later
- Node.js 24.10.0 or later
- pnpm 11 or later
- Eclipse Temurin JDK 17 (including `javac`)
- Git for Windows
- GitHub CLI

## Commands

Run all repository quality tasks through pnpm:

```powershell
pnpm install
pnpm run lint
pnpm run test
pnpm run test:generated
pnpm run verify
```

`pnpm run test:generated` and `pnpm run verify` generate all available
Blueprints and verify their file contract. They do not install generated
dependencies or require Node.js, pnpm, or a JDK on behalf of generated projects.

## Development rules

- Keep `bootstrap.ps1` compatible with PowerShell 7.
- Save text as UTF-8 without BOM and use LF line endings.
- Never write secrets, GitHub tokens, or user-specific absolute paths.
- Never overwrite or delete files in a generation destination.
- Keep interactive prompts and non-interactive CI execution behavior aligned.
- Validate local generation before making GitHub changes.
- Do not execute generated-project install, lint, test, build, or startup
  commands as part of Bootstrapper success.
- Keep the public entry point self-contained.
- Use the Blueprint manifest as the source of truth for generated files.

## Git workflow

- Register implementation work in a GitHub Issue when a remote exists.
- Branch from `develop` for normal feature work.
- Use three-line Conventional Commit messages without scopes:

  ```text
  feat: add project generation

  Explain why and what changed.
  ```

- Do not use `feat(scope): ...` style messages.

## Safety gates

Stop for explicit confirmation before:

- overwriting or deleting existing user files;
- deleting a GitHub repository;
- changing persisted-data semantics;
- weakening an existing repository ruleset;
- exposing a private repository or secret.
