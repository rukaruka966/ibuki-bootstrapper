# DESIGN.md

Ibuki itself is a terminal-first tool. Its output should be concise, readable,
and accessible in both light and dark terminal themes.

## Terminal output

- Use plain text as the primary signal; color is supplementary.
- Prefix phases with stable names such as `[Preflight]` and `[Generate]`.
- Show the active GitHub account before external changes.
- Show the source commit and its matching GitHub Release when available.
- Treat release metadata lookup failures as non-blocking.
- Show a complete summary before confirmation.
- On failure, show the failed phase and the files already created.
- Never print authentication tokens or secret values.
- Reject destination paths longer than 96 characters before confirmation or
  file creation to avoid unreliable dependency resolution on Windows.

## Generated web application

The v0.1 Blueprint generates a neutral application shell rather than a demo
dashboard.

- Use semantic HTML.
- Preserve visible keyboard focus.
- Meet WCAG AA contrast.
- Honor `prefers-reduced-motion`.
- Include explicit loading, empty, error, and success states when features add
  asynchronous behavior.
- Keep the starter screen intentionally minimal so product work can replace it
  without removing decorative sample code.

## Git history

- Squash feature pull requests into `develop`.
- Merge `develop` pull requests into `main` with a merge commit.
- Permit only `develop` to target `main`; do not provide a direct-main
  emergency path.
- Keep feature commits visible to semantic-release through the release merge
  topology.
- Use the source gate in `Quality` to prevent accidental release Pull Requests.
  It is not a security boundary because a Pull Request can modify its Workflow.
- Keep required checks non-strict on `main` so release merge commits need no
  reverse synchronization into `develop`.
- Keep required checks strict on `develop` so feature Pull Requests are tested
  against its latest state.
