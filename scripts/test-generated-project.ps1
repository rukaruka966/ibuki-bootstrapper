[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$temporaryBase = if ($env:RUNNER_TEMP) {
    [System.IO.Path]::GetFullPath($env:RUNNER_TEMP)
} else {
    [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
}
$temporaryBase = $temporaryBase.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$maximumDestinationLength = 96
$testRootName = "ibuki-$([guid]::NewGuid())"
$paddingLength = $maximumDestinationLength - $temporaryBase.Length - 1 - $testRootName.Length

if ($paddingLength -lt 0) {
    throw (
        "The temporary base path is too long to test the supported destination boundary: " +
        "$temporaryBase"
    )
}

$testRootName += "x" * $paddingLength
$testRoot = Join-Path $temporaryBase $testRootName

if ($testRoot.Length -ne $maximumDestinationLength) {
    throw "Unable to create a $maximumDestinationLength-character generated test path: $testRoot"
}

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
        ".github/workflows/ci.yml",
        "scripts/check-pr-branch-policy.mjs",
        "docs/ja-JP/AGENTS-ja.md",
        "docs/ja-JP/DESIGN-ja.md",
        "systems/web-frontend/dist/index.html",
        "systems/api-bff/dist/index.js"
    )

    foreach ($relativePath in $requiredPaths) {
        $path = Join-Path $testRoot $relativePath

        if (-not (Test-Path -LiteralPath $path)) {
            throw "Generated verification artifact is missing: $path"
        }
    }

    $generatedAgents = Get-Content -LiteralPath (Join-Path $testRoot "AGENTS.md") -Raw

    if (
        $generatedAgents -notmatch '(?m)^## Definition of Done$' -or
        $generatedAgents -notmatch 'pnpm run typecheck' -or
        $generatedAgents -notmatch 'explicit human approval'
    ) {
        throw "Generated AGENTS.md does not contain the required Definition of Done."
    }

    $generatedJapaneseAgents = Get-Content `
        -LiteralPath (Join-Path $testRoot "docs/ja-JP/AGENTS-ja.md") `
        -Raw

    if (
        $generatedJapaneseAgents -notmatch [regex]::Escape("Ibuki `"Test`" <Project>") -or
        $generatedJapaneseAgents -match '__PROJECT_' -or
        $generatedJapaneseAgents -notmatch 'squash merge' -or
        $generatedJapaneseAgents -notmatch 'merge commit' -or
        $generatedJapaneseAgents -notmatch 'main.*develop' -or
        $generatedJapaneseAgents -notmatch 'strictを無効' -or
        $generatedJapaneseAgents -notmatch 'strictを有効'
    ) {
        throw "Generated Japanese AGENTS reference was not rendered correctly."
    }

    if (
        $generatedAgents -notmatch 'squash merge' -or
        $generatedAgents -notmatch 'merge commit' -or
        $generatedAgents -notmatch 'Only `develop` may open' -or
        $generatedAgents -notmatch 'non-strict on `main`' -or
        $generatedAgents -notmatch 'strict on `develop`'
    ) {
        throw "Generated AGENTS.md does not contain the required merge policy."
    }

    $generatedWorkflow = Get-Content `
        -LiteralPath (Join-Path $testRoot ".github/workflows/ci.yml") `
        -Raw

    if (
        $generatedWorkflow -notmatch 'node scripts/check-pr-branch-policy\.mjs' -or
        $generatedWorkflow -notmatch 'GITHUB_BASE_REPOSITORY' -or
        $generatedWorkflow -notmatch 'GITHUB_HEAD_REPOSITORY' -or
        $generatedWorkflow -notmatch 'head\.repo\.full_name'
    ) {
        throw "Generated CI does not enforce the Pull Request branch policy."
    }

    $policyScript = Join-Path $testRoot "scripts/check-pr-branch-policy.mjs"
    $env:GITHUB_EVENT_NAME = "pull_request"
    $env:GITHUB_BASE_REF = "main"
    $env:GITHUB_HEAD_REF = "develop"
    $env:GITHUB_BASE_REPOSITORY = "owner/project"
    $env:GITHUB_HEAD_REPOSITORY = "owner/project"
    & node $policyScript

    if ($LASTEXITCODE -ne 0) {
        throw "Generated policy rejected the trusted develop branch."
    }

    $env:GITHUB_HEAD_REPOSITORY = "fork-owner/project"
    $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false

    try {
        & node $policyScript 2>$null
        $forkPolicyExitCode = $LASTEXITCODE
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
    }

    if ($forkPolicyExitCode -eq 0) {
        throw "Generated policy accepted a fork develop branch."
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
