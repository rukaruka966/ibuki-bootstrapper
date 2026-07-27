{
  "name": "__PROJECT_ID__",
  "version": "0.1.0",
  "private": true,
  "packageManager": "pnpm@11.12.0",
  "engines": {
    "node": ">=24.10.0",
    "pnpm": ">=11.0.0"
  },
  "scripts": {
    "dev": "node scripts/run-gradle.mjs bootRun",
    "test": "node scripts/run-gradle.mjs test",
    "test:release": "node --test tests/release-notes.test.mjs",
    "check": "node scripts/run-gradle.mjs check && pnpm test:release",
    "build": "node scripts/run-gradle.mjs bootJar",
    "e2e": "node scripts/run-gradle.mjs e2eTest",
    "release": "semantic-release"
  },
  "devDependencies": {
    "@semantic-release/commit-analyzer": "13.0.1",
    "@semantic-release/github": "12.0.9",
    "@semantic-release/release-notes-generator": "14.1.1",
    "conventional-changelog-conventionalcommits": "9.3.1",
    "semantic-release": "25.0.8"
  }
}
