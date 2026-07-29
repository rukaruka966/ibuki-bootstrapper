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

## Issue intake

Humans provide observed and desired outcomes. When the repository uses GitHub
Issues, AI agents update the Issue before implementation with scope, non-goals,
observable acceptance targets, request-specific constraints and stop conditions,
and a verification plan.

## Pull Request handoff

Use the Pull Request template as a handoff contract between AI delivery and
human acceptance. A Pull Request to `develop` may keep human acceptance
`Pending` after AI implementation, verification, and review are complete, but
it must state the observable acceptance target. A Pull Request from `develop`
to `main` requires acceptance to be `Accepted` with its result or evidence.

Record decisions, differences from the request, verification evidence, review
findings, and triggered stop conditions. Avoid ceremonial checklists that do
not provide evidence or affect the next decision.

The `main` branch is released through semantic-release after Quality succeeds.
Release Notes are generated from Conventional Commits. Releases create a Git
tag and GitHub Release without committing a changelog file.
