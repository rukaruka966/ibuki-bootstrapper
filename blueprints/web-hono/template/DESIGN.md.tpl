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
