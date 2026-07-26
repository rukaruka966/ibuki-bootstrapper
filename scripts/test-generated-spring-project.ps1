[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$temporaryBase = if ($env:RUNNER_TEMP) {
    [System.IO.Path]::GetFullPath($env:RUNNER_TEMP)
} else {
    [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
}
$testRoot = Join-Path $temporaryBase "ibuki spring $([guid]::NewGuid())"

try {
    & (Join-Path $repositoryRoot "bootstrap.ps1") `
        -Blueprint "api-spring" `
        -ProjectId "ibuki-spring-test" `
        -DisplayName 'Ibuki Spring "Test"' `
        -Destination $testRoot `
        -SkipGitHub `
        -NonInteractive `
        -Yes

    if ($LASTEXITCODE -ne 0) {
        throw "Spring generated project verification failed with exit code $LASTEXITCODE."
    }

    $requiredPaths = @(
        "project.config.yaml",
        ".github/workflows/ci.yml",
        "docs/ja-JP/AGENTS-ja.md",
        "docs/ja-JP/DESIGN-ja.md",
        "systems/api-server/gradlew",
        "systems/api-server/gradlew.bat",
        "systems/api-server/gradle/wrapper/gradle-wrapper.jar",
        "systems/api-server/build/libs/ibuki-spring-test-0.0.1-SNAPSHOT.jar"
    )

    foreach ($relativePath in $requiredPaths) {
        $path = Join-Path $testRoot $relativePath

        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Generated Spring verification artifact is missing: $path"
        }
    }

    $projectConfig = Get-Content `
        -LiteralPath (Join-Path $testRoot "project.config.yaml") `
        -Raw

    if (
        $projectConfig -notmatch 'type: spring-boot' -or
        $projectConfig -notmatch 'port: 8080' -or
        $projectConfig -match '__[A-Z0-9_]+__'
    ) {
        throw "Generated Spring project.config.yaml is incomplete."
    }

    $workflow = Get-Content `
        -LiteralPath (Join-Path $testRoot ".github/workflows/ci.yml") `
        -Raw

    if (
        $workflow -notmatch 'name: Quality' -or
        $workflow -notmatch 'java-version: "17"' -or
        $workflow -match 'setup-node|pnpm'
    ) {
        throw "Generated Spring Quality workflow has incorrect Toolchain requirements."
    }

    & git -C $testRoot init -b main --quiet

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to initialize the generated Spring project."
    }

    & git -C $testRoot add --all

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to stage the generated Spring project."
    }

    $trackedBuildOutputs = @(
        & git -C $testRoot ls-files |
            Where-Object {
                $_ -match '(^|/)(build|\.gradle)/'
            }
    )

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect generated Spring build outputs."
    }

    if ($trackedBuildOutputs.Count -gt 0) {
        throw "Generated Spring build outputs would be included in the initial commit."
    }

    $unresolvedTokens = Get-ChildItem -LiteralPath $testRoot -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '[\\/](build|\.gradle|\.git)[\\/]'
        } |
        Select-String -Pattern '__[A-Z0-9_]+__'

    if ($unresolvedTokens) {
        throw "Generated Spring project contains unresolved template tokens."
    }

    Write-Host "Generated Spring project integration test passed." -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        $temporaryPrefix = $temporaryBase.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ) + [System.IO.Path]::DirectorySeparatorChar

        if (-not $resolvedTestRoot.StartsWith(
            $temporaryPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Refusing to remove a Spring test directory outside the temporary root."
        }

        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
