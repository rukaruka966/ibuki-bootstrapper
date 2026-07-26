# DESIGN.md

Ibuki itself is a terminal-first tool. Its output should be concise, readable,
and accessible in both light and dark terminal themes.

## Terminal output

- Use plain text as the primary signal; color is supplementary.
- Prefix phases with stable names such as `[Preflight]` and `[Generate]`.
- Show the active GitHub account before external changes.
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
