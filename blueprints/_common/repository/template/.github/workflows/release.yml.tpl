name: Release

on:
  workflow_call:

jobs:
  release:
    name: Release
    runs-on: ubuntu-latest
    permissions:
      contents: write
    concurrency:
      group: release-${{ github.ref }}
      cancel-in-progress: false

    steps:
      - name: Checkout
        uses: actions/checkout@v6
        with:
          fetch-depth: 0

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

      - name: Create GitHub Release
        run: pnpm release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
