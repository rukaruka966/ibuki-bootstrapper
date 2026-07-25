[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$temporaryBase = if ($env:RUNNER_TEMP) {
    [System.IO.Path]::GetFullPath($env:RUNNER_TEMP)
} else {
    [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
}
$testRoot = Join-Path $temporaryBase "ibuki-$([guid]::NewGuid())"

try {
    & (Join-Path $repositoryRoot "bootstrap.ps1") `
        -ProjectId "ibuki-test-project" `
        -DisplayName 'Ibuki "Test" <Project>' `
        -Destination $testRoot `
        -SkipGitHub `
        -NonInteractive `
        -Yes

    if ($LASTEXITCODE -ne 0) {
        throw "Generated project verification failed with exit code $LASTEXITCODE."
    }

    $requiredPaths = @(
        "pnpm-lock.yaml",
        "project.config.yaml",
        "systems/web-frontend/dist/index.html",
        "systems/api-bff/dist/index.js"
    )

    foreach ($relativePath in $requiredPaths) {
        $path = Join-Path $testRoot $relativePath

        if (-not (Test-Path -LiteralPath $path)) {
            throw "Generated verification artifact is missing: $path"
        }
    }

    & git -C $testRoot init -b main --quiet

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to initialize the generated project for ignore verification."
    }

    & git -C $testRoot add --all

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to stage the generated project for ignore verification."
    }

    $trackedBuildMetadata = & git -C $testRoot ls-files "*.tsbuildinfo"

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect tracked TypeScript build metadata."
    }

    if (-not [string]::IsNullOrWhiteSpace(($trackedBuildMetadata -join "`n"))) {
        throw "Generated TypeScript build metadata would be included in the initial commit."
    }

    $unresolvedTokens = Get-ChildItem -LiteralPath $testRoot -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '[\\/](node_modules|\.git)[\\/]'
        } |
        Select-String -Pattern '__PROJECT_(ID|DISPLAY_NAME|DISPLAY_NAME_(HTML|JSON|YAML))__'

    if ($unresolvedTokens) {
        throw "Generated project contains unresolved template tokens."
    }

    Write-Host "Generated project integration test passed." -ForegroundColor Green
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
            throw "Refusing to remove a test directory outside the temporary root: $resolvedTestRoot"
        }

        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
