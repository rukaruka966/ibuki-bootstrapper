{
  "name": "__PROJECT_ID__",
  "version": "0.1.0",
  "private": true,
  "packageManager": "pnpm@11.12.0",
  "engines": {
    "node": ">=24.0.0",
    "pnpm": ">=11.0.0"
  },
  "scripts": {
    "dev": "pnpm --parallel --filter \"./systems/*\" dev",
    "lint": "oxlint systems scripts && markdownlint \"**/*.md\" --ignore \"**/node_modules/**\"",
    "test": "pnpm --recursive --filter \"./systems/*\" test",
    "typecheck": "pnpm --recursive --filter \"./systems/*\" typecheck",
    "build": "pnpm --recursive --filter \"./systems/*\" build",
    "smoke": "node scripts/smoke.mjs",
    "doctor": "pwsh -NoProfile -File ./scripts/doctor.ps1"
  },
  "devDependencies": {
    "markdownlint-cli": "0.49.1",
    "oxlint": "1.75.0"
  }
}
