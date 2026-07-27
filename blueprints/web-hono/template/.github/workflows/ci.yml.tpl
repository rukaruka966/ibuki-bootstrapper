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

      - name: Check
        run: pnpm check

      - name: Doctor
        shell: pwsh
        run: pnpm doctor

  release:
    name: Release
    needs:
      - quality
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    permissions:
      contents: write
    uses: ./.github/workflows/release.yml
