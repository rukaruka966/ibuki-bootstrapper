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
      - name: Enforce trusted main pull request source
        if: github.event_name == 'pull_request' && github.base_ref == 'main'
        shell: pwsh
        env:
          HEAD_REF: ${{ github.head_ref }}
          BASE_REPOSITORY: ${{ github.repository }}
          HEAD_REPOSITORY: ${{ github.event.pull_request.head.repo.full_name }}
        run: |
          if (
            $env:HEAD_REF -ne "develop" -or
            $env:HEAD_REPOSITORY -ne $env:BASE_REPOSITORY
          ) {
            throw "Pull requests targeting main must come from develop in the same repository."
          }

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

      - name: Validate pull request branch policy
        run: node scripts/check-pr-branch-policy.mjs
        env:
          GITHUB_EVENT_NAME: ${{ github.event_name }}
          GITHUB_BASE_REF: ${{ github.base_ref }}
          GITHUB_HEAD_REF: ${{ github.head_ref }}
          GITHUB_BASE_REPOSITORY: ${{ github.repository }}
          GITHUB_HEAD_REPOSITORY: ${{ github.event.pull_request.head.repo.full_name }}

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

      - name: Doctor
        shell: pwsh
        run: pnpm run doctor
