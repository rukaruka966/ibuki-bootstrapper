name: CI

on:
  push:
    branches:
      - main
      - develop
  pull_request:
    branches:
      - main
      - develop

permissions:
  contents: read

jobs:
  quality:
    name: Quality
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Setup pnpm
        uses: pnpm/action-setup@v4.4.0
        with:
          version: 11.12.0

      - name: Setup Node.js
        uses: actions/setup-node@v6
        with:
          node-version: 24
          cache: pnpm

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Lint
        run: pnpm run lint

      - name: Test
        run: pnpm run test

      - name: Typecheck
        run: pnpm run typecheck

      - name: Build
        run: pnpm run build

      - name: Smoke test
        run: pnpm run smoke

      - name: Doctor
        shell: pwsh
        run: pnpm run doctor
