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
    runs-on: windows-latest

    steps:
      - name: Enforce main pull request source
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

      - name: Setup Java
        uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: "17"
          cache: gradle

      - name: Check
        run: .\gradlew.bat check
        working-directory: systems/api-server

      - name: Build executable JAR
        run: .\gradlew.bat bootJar
        working-directory: systems/api-server
