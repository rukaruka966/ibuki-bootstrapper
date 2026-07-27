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

The `main` branch is released through semantic-release after Quality succeeds.
Release Notes are generated from Conventional Commits. Releases create a Git
tag and GitHub Release without committing a changelog file.
