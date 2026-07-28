# Repository operations

pnpm is the repository-wide task runner for every generated Blueprint.
Application build systems remain authoritative: Node.js workspaces run their
native scripts, while Spring projects delegate to the checked-in Gradle Wrapper.

## Common commands

- `pnpm dev`
- `pnpm test`
- `pnpm check`
- `pnpm build`
- `pnpm release`

PostgreSQL Spring projects also provide `pnpm e2e`.

Node.js and pnpm are repository-operation requirements. JDK 17 remains an
additional application requirement for Spring projects. Direct Gradle Wrapper
commands remain available for diagnosis, but automation and AI agents should
use the root pnpm commands.

## Ignore-file ownership

The root `.gitignore` contains only repository-wide rules for pnpm dependencies,
local environment variables, logs, IDE state, and operating-system metadata.
Each independently buildable system owns its build-output rules in a nested
`.gitignore`. For example, `systems/api-server/.gitignore` owns Gradle, Kotlin,
and JVM output, while Node.js systems own `dist`, coverage, and TypeScript build
metadata.

Do not add broad root rules for names such as `build`, `bin`, or `dist`.
They can hide legitimate assets belonging to another system. A `.gitignore`
reduces accidental commits; it is not a security boundary. Keep secrets outside
the repository and review staged changes before committing.

The `main` branch is released through semantic-release after Quality succeeds.
Release Notes are generated from Conventional Commits. Releases create a Git
tag and GitHub Release without committing a changelog file.
