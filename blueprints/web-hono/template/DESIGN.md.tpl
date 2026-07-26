# DESIGN.md

Japanese reference: [`docs/ja-JP/DESIGN-ja.md`](docs/ja-JP/DESIGN-ja.md)

## Principles

- Prefer a neutral, product-specific design over decorative starter UI.
- Use semantic HTML and visible keyboard focus.
- Meet WCAG AA color contrast.
- Honor `prefers-reduced-motion`.
- Design responsive layouts from 320 px upward.
- Do not encode meaning with color alone.

## Application states

Features that perform asynchronous work must define:

- loading;
- empty;
- success;
- recoverable error;
- unrecoverable error.

Success feedback should be concise and self-closing. Error feedback should
remain available when the user needs details for recovery.

## Destructive actions

- State the target and impact before confirmation.
- Do not preselect destructive actions.
- Preserve recovery information after failures.

## Git history

- Squash feature Pull Requests into `develop`.
- Merge only `develop` into `main`, using a merge commit.
- Do not create a direct-main emergency path.
- Use the release source gate to prevent accidental misuse. It is not a security
  boundary because a Pull Request can modify its Workflow.
- Keep required checks non-strict on `main` to avoid reverse synchronization
  after release merge commits, and strict on `develop` to keep feature Pull
  Requests based on its latest state.
