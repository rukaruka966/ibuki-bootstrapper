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
    "test": "pnpm --recursive --filter \"./systems/*\" test && pnpm test:release",
    "test:release": "node --test tests/release-notes.test.mjs",
    "typecheck": "pnpm --recursive --filter \"./systems/*\" typecheck",
    "build": "pnpm --recursive --filter \"./systems/*\" build",
    "check": "pnpm lint && pnpm test && pnpm typecheck && pnpm build",
    "doctor": "pwsh -NoProfile -File ./scripts/doctor.ps1",
    "release": "semantic-release"
  },
  "devDependencies": {
    "@semantic-release/commit-analyzer": "13.0.1",
    "@semantic-release/github": "12.0.9",
    "@semantic-release/release-notes-generator": "14.1.1",
    "conventional-changelog-conventionalcommits": "9.3.1",
    "markdownlint-cli": "0.49.1",
    "oxlint": "1.75.0",
    "semantic-release": "25.0.8"
  }
}
