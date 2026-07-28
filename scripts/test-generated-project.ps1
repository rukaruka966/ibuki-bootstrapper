[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$temporaryBase = if ($env:RUNNER_TEMP) {
    [System.IO.Path]::GetFullPath($env:RUNNER_TEMP)
} else {
    [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
}
$testRoot = Join-Path $temporaryBase "ibuki-contract-$([guid]::NewGuid())"
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Assert-GitIgnoreState {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string]$GlobalIgnorePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [bool]$ExpectedIgnored
    )

    & git `
        -c "core.excludesFile=$GlobalIgnorePath" `
        -C $RepositoryRoot `
        check-ignore `
        --no-index `
        --quiet `
        -- `
        $RelativePath
    $status = $LASTEXITCODE

    if ($status -notin @(0, 1)) {
        $diagnostic = (
            & git `
                -c "core.excludesFile=$GlobalIgnorePath" `
                -C $RepositoryRoot `
                check-ignore `
                --no-index `
                -v `
                -- `
                $RelativePath 2>&1
        ) -join "`n"
        throw (
            "git check-ignore failed for '$RelativePath' with exit code " +
            "$status`: $diagnostic"
        )
    }

    if ($ExpectedIgnored -and $status -ne 0) {
        throw "Expected generated .gitignore to ignore '$RelativePath'."
    }

    if (-not $ExpectedIgnored -and $status -eq 0) {
        $diagnostic = (
            & git `
                -c "core.excludesFile=$GlobalIgnorePath" `
                -C $RepositoryRoot `
                check-ignore `
                --no-index `
                -v `
                -- `
                $RelativePath 2>&1
        ) -join "`n"
        throw (
            "Generated .gitignore unexpectedly ignores '$RelativePath': " +
            $diagnostic
        )
    }
}

function Assert-GitIgnoreProbeParentsSafe {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string]$Target
    )

    $canonicalRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $canonicalTarget = [System.IO.Path]::GetFullPath($Target)
    $requiredPrefix = "$canonicalRoot$([System.IO.Path]::DirectorySeparatorChar)"

    if (-not $canonicalTarget.StartsWith(
        $requiredPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Git ignore contract probe escapes its repository root: $Target"
    }

    $current = [System.IO.Path]::GetDirectoryName($canonicalTarget)

    while ($true) {
        if ([string]::IsNullOrWhiteSpace($current)) {
            throw "Git ignore contract probe has no safe parent: $Target"
        }

        if (
            -not $current.Equals(
                $canonicalRoot,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -and
            -not $current.StartsWith(
                $requiredPrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            throw "Git ignore contract probe parent escapes its repository root: $current"
        }

        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force

            if (-not $item.PSIsContainer) {
                throw "Git ignore contract probe parent is not a directory: $current"
            }

            if (
                ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne
                0
            ) {
                throw "Git ignore contract probe parent is a reparse point: $current"
            }
        }

        if ($current.Equals(
            $canonicalRoot,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            break
        }

        $current = [System.IO.Path]::GetDirectoryName($current)
    }
}

function New-GitIgnoreTrackedProbe {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Git ignore contract probe path must be relative: $RelativePath"
    }

    $segments = @($RelativePath -split '[\\/]')

    if (
        $segments.Count -eq 0 -or
        @($segments | Where-Object {
            [string]::IsNullOrEmpty($_) -or $_ -in @(".", "..")
        }).Count -ne 0
    ) {
        throw "Git ignore contract probe contains an unsafe segment: $RelativePath"
    }

    $canonicalRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $target = [System.IO.Path]::GetFullPath(
        (Join-Path $canonicalRoot $RelativePath)
    )
    $requiredPrefix = "$canonicalRoot$([System.IO.Path]::DirectorySeparatorChar)"

    if (-not $target.StartsWith(
        $requiredPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Git ignore contract probe escapes its repository root: $RelativePath"
    }

    Assert-GitIgnoreProbeParentsSafe `
        -RepositoryRoot $canonicalRoot `
        -Target $target

    if (Test-Path -LiteralPath $target) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Tracked contract path is not a file: $RelativePath"
        }

        return
    }

    $parent = Split-Path $target -Parent

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $canonicalRoot = [System.IO.Path]::GetFullPath($canonicalRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $target = [System.IO.Path]::GetFullPath($target)
    $requiredPrefix = "$canonicalRoot$([System.IO.Path]::DirectorySeparatorChar)"

    if (-not $target.StartsWith(
        $requiredPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Git ignore contract probe escaped after parent creation: $RelativePath"
    }

    Assert-GitIgnoreProbeParentsSafe `
        -RepositoryRoot $canonicalRoot `
        -Target $target

    if (Test-Path -LiteralPath $target) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Tracked contract path is not a file: $RelativePath"
        }

        return
    }

    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        "gitignore contract probe`n"
    )
    $stream = [System.IO.File]::Open(
        $target,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )

    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally {
        $stream.Dispose()
    }
}

function Assert-GeneratedGitIgnoreContract {
    param(
        [Parameter(Mandatory)]
        [string]$BlueprintId,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$GlobalIgnorePath
    )

    & git -C $Destination init -b main --quiet

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to initialize generated Git ignore contract: $BlueprintId"
    }

    $commonIgnored = @(
        "node_modules/package/index.js",
        "systems/example/node_modules/package/index.js",
        ".pnpm-store/v3/files/content",
        ".env",
        ".env.local",
        "systems/example/.env.production",
        "debug.log",
        "git-bash.stackdump",
        ".idea/workspace.xml",
        "project.iml",
        "nested/.DS_Store",
        "nested/Thumbs.db",
        "nested/Thumbs.db:encryptable",
        "nested/Desktop.ini",
        "nested/desktop.ini"
    )
    $commonTracked = @(
        "package.json",
        "pnpm-lock.yaml",
        ".env.example",
        ".env.development.example",
        "build/asset.txt",
        "bin/tool.exe",
        "dist/index.js",
        "fixture.jar",
        "fixture.zip",
        "docs/README.md"
    )

    foreach ($relativePath in $commonIgnored) {
        Assert-GitIgnoreState `
            -RepositoryRoot $Destination `
            -GlobalIgnorePath $GlobalIgnorePath `
            -RelativePath $relativePath `
            -ExpectedIgnored $true
    }

    foreach ($relativePath in $commonTracked) {
        Assert-GitIgnoreState `
            -RepositoryRoot $Destination `
            -GlobalIgnorePath $GlobalIgnorePath `
            -RelativePath $relativePath `
            -ExpectedIgnored $false
    }

    $blueprintIgnored = @()
    $blueprintTracked = @()

    if ($BlueprintId -eq "web-hono") {
        $blueprintIgnored = @(
            "systems/web-frontend/dist/index.js",
            "systems/web-frontend/coverage/index.html",
            "systems/web-frontend/tsconfig.tsbuildinfo",
            "systems/api-bff/dist/index.js",
            "systems/api-bff/coverage/index.html",
            "systems/api-bff/tsconfig.tsbuildinfo"
        )

        foreach ($relativePath in $blueprintIgnored) {
            Assert-GitIgnoreState `
                -RepositoryRoot $Destination `
                -GlobalIgnorePath $GlobalIgnorePath `
                -RelativePath $relativePath `
                -ExpectedIgnored $true
        }

        $blueprintTracked = @(
            "systems/other/dist/asset.js",
            "systems/web-frontend/src/dist/Asset.ts",
            "systems/api-bff/src/coverage/fixture.ts"
        )

        foreach ($relativePath in $blueprintTracked) {
            Assert-GitIgnoreState `
                -RepositoryRoot $Destination `
                -GlobalIgnorePath $GlobalIgnorePath `
                -RelativePath $relativePath `
                -ExpectedIgnored $false
        }
    } else {
        $blueprintIgnored = @(
            "systems/api-server/.gradle/cache/file",
            "systems/api-server/.kotlin/cache/file",
            "systems/api-server/build/classes/App.class",
            "systems/api-server/out/classes/App.class",
            "systems/api-server/bin/App.class",
            "systems/api-server/hs_err_pid123",
            "systems/api-server/replay_pid123",
            "systems/api-server/java_pid123.hprof"
        )

        foreach ($relativePath in $blueprintIgnored) {
            Assert-GitIgnoreState `
                -RepositoryRoot $Destination `
                -GlobalIgnorePath $GlobalIgnorePath `
                -RelativePath $relativePath `
                -ExpectedIgnored $true
        }

        $blueprintTracked = @(
            "systems/api-server/gradlew",
            "systems/api-server/gradlew.bat",
            "systems/api-server/gradle/wrapper/gradle-wrapper.jar",
            "systems/api-server/gradle/wrapper/gradle-wrapper.properties",
            "systems/api-server/src/main/kotlin/example/build/Asset.kt",
            "systems/api-server/src/main/resources/db/migration/V1__init.sql",
            "systems/other/build/asset.txt",
            "systems/other/bin/tool.exe"
        )

        foreach ($relativePath in $blueprintTracked) {
            Assert-GitIgnoreState `
                -RepositoryRoot $Destination `
                -GlobalIgnorePath $GlobalIgnorePath `
                -RelativePath $relativePath `
                -ExpectedIgnored $false
        }
    }

    $allIgnored = @($commonIgnored) + @($blueprintIgnored)
    $allTracked = @($commonTracked) + @($blueprintTracked)

    foreach ($relativePath in $allIgnored) {
        if ($relativePath -eq "nested/Thumbs.db:encryptable") {
            continue
        }

        New-GitIgnoreTrackedProbe `
            -RepositoryRoot $Destination `
            -RelativePath $relativePath
    }

    foreach ($relativePath in $allTracked) {
        New-GitIgnoreTrackedProbe `
            -RepositoryRoot $Destination `
            -RelativePath $relativePath
    }

    & git `
        -c "core.excludesFile=$GlobalIgnorePath" `
        -C $Destination `
        add `
        --all `
        -- `
        .

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to stage generated Git ignore contract: $BlueprintId"
    }

    foreach ($relativePath in $allTracked) {
        $diagnostic = (
            & git `
                -c "core.excludesFile=$GlobalIgnorePath" `
                -C $Destination `
                ls-files `
                --error-unmatch `
                -- `
                $relativePath 2>&1
        ) -join "`n"
        $status = $LASTEXITCODE

        if ($status -ne 0) {
            throw (
                "Expected tracked path was not staged: '$relativePath' " +
                "(exit code $status): $diagnostic"
            )
        }
    }

    foreach ($relativePath in $allIgnored) {
        if ($relativePath -eq "nested/Thumbs.db:encryptable") {
            continue
        }

        $diagnostic = (
            & git `
                -c "core.excludesFile=$GlobalIgnorePath" `
                -C $Destination `
                ls-files `
                --error-unmatch `
                -- `
                $relativePath 2>&1
        ) -join "`n"
        $status = $LASTEXITCODE

        if ($status -eq 0) {
            throw "Ignored path was unexpectedly staged: '$relativePath': $diagnostic"
        }

        if ($status -ne 1) {
            throw (
                "git ls-files failed for ignored path '$relativePath' " +
                "with exit code $status`: $diagnostic"
            )
        }
    }

    Write-Host "[OK] $BlueprintId gitignore contract"
}

function Assert-GeneratedBlueprint {
    param(
        [Parameter(Mandatory)]
        [string]$BlueprintId,

        [Parameter(Mandatory)]
        [string]$ProjectId,

        [string]$BasePackage = "",

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$GlobalIgnorePath
    )

    & (Join-Path $repositoryRoot "bootstrap.ps1") `
        -Blueprint $BlueprintId `
        -ProjectId $ProjectId `
        -DisplayName 'Ibuki "Contract" <Project>' `
        -BasePackage $BasePackage `
        -Destination $Destination `
        -SkipGitHub `
        -NonInteractive `
        -Yes

    if ($LASTEXITCODE -ne 0) {
        throw "Blueprint generation failed with exit code $LASTEXITCODE`: $BlueprintId"
    }

    $manifestPath = Join-Path $repositoryRoot "blueprints/$BlueprintId/manifest.json"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $contractFiles = [System.Collections.Generic.List[object]]::new()

    foreach ($file in @($manifest.files)) {
        $contractFiles.Add($file)
    }

    foreach ($fileSetId in @($manifest.fileSets)) {
        $fileSetPath = Join-Path $repositoryRoot (
            "blueprints/_common/$fileSetId/manifest.json"
        )
        $fileSetManifest = Get-Content -LiteralPath $fileSetPath -Raw |
            ConvertFrom-Json

        foreach ($file in @($fileSetManifest.files)) {
            $contractFiles.Add($file)
        }
    }

    $generatedFiles = @(
        Get-ChildItem -LiteralPath $Destination -Recurse -File
    )

    if ($generatedFiles.Count -ne $contractFiles.Count) {
        throw (
            "Generated file count differs from the manifest for '$BlueprintId': " +
            "$($generatedFiles.Count) != $($contractFiles.Count)"
        )
    }

    foreach ($file in @($contractFiles)) {
        $relativeTarget = [string]$file.target

        if (
            @($file.PSObject.Properties.Name) -contains "targetTemplate" -and
            $file.targetTemplate
        ) {
            $basePackagePath = $BasePackage.Replace(".", "/")
            $relativeTarget = $relativeTarget.Replace(
                "__BASE_PACKAGE_PATH__",
                $basePackagePath
            )
        }

        $target = Join-Path $Destination $relativeTarget
        $destinationRoot = [System.IO.Path]::GetFullPath($Destination).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar
        )
        $canonicalTarget = [System.IO.Path]::GetFullPath($target)
        $requiredPrefix = "$destinationRoot$([System.IO.Path]::DirectorySeparatorChar)"

        if (-not $canonicalTarget.StartsWith(
            $requiredPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Manifest target escapes the generated project: $($file.target)"
        }

        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Generated contract artifact is missing: $target"
        }

        $bytes = [System.IO.File]::ReadAllBytes($target)

        if ($file.kind -eq "binary") {
            $actualHash = [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData($bytes)
            ).ToLowerInvariant()

            if ($actualHash -ne $file.sha256) {
                throw "Generated binary checksum mismatch: $($file.target)"
            }

            continue
        }

        if (
            $bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF
        ) {
            throw "Generated text contains a UTF-8 BOM: $($file.target)"
        }

        try {
            $content = $strictUtf8.GetString($bytes)
        } catch [System.Text.DecoderFallbackException] {
            throw "Generated text is not valid UTF-8: $($file.target)"
        }

        if ($content.Contains("`r")) {
            throw "Generated text does not use LF line endings: $($file.target)"
        }

        if ($content -match '__[A-Z0-9_]+__') {
            throw "Generated text contains an unresolved template token: $($file.target)"
        }
    }

    foreach ($unexpectedPath in @(
        "node_modules",
        "systems/web-frontend/dist",
        "systems/api-bff/dist",
        "systems/api-server/build"
    )) {
        if (Test-Path -LiteralPath (Join-Path $Destination $unexpectedPath)) {
            throw "Generation executed a project-owned build step: $unexpectedPath"
        }
    }

    Assert-GeneratedGitIgnoreContract `
        -BlueprintId $BlueprintId `
        -Destination $Destination `
        -GlobalIgnorePath $GlobalIgnorePath

    Write-Host "[OK] $BlueprintId generation contract"
}

function Assert-NoOverwriteContract {
    param(
        [Parameter(Mandatory)]
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination | Out-Null
    $sentinelPath = Join-Path $Destination "existing.txt"
    [System.IO.File]::WriteAllText(
        $sentinelPath,
        "keep",
        [System.Text.UTF8Encoding]::new($false)
    )

    & pwsh `
        -NoProfile `
        -File (Join-Path $repositoryRoot "bootstrap.ps1") `
        -Blueprint "web-hono" `
        -ProjectId "contract-no-overwrite" `
        -DisplayName "Contract no overwrite" `
        -Destination $Destination `
        -SkipGitHub `
        -NonInteractive `
        -Yes 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        throw "Generation unexpectedly accepted a non-empty destination."
    }

    if ([System.IO.File]::ReadAllText($sentinelPath) -ne "keep") {
        throw "Generation modified an existing destination file."
    }

    if (@(Get-ChildItem -LiteralPath $Destination -Force).Count -ne 1) {
        throw "Generation added files to a non-empty destination."
    }

    Write-Host "[OK] no-overwrite contract"
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $globalIgnorePath = Join-Path $testRoot "empty-global-ignore"
    [System.IO.File]::WriteAllBytes($globalIgnorePath, [byte[]]::new(0))
    Assert-GeneratedBlueprint `
        -BlueprintId "web-hono" `
        -ProjectId "contract-web" `
        -Destination (Join-Path $testRoot "web") `
        -GlobalIgnorePath $globalIgnorePath
    Assert-GeneratedBlueprint `
        -BlueprintId "api-spring" `
        -ProjectId "contract-api" `
        -BasePackage "net.rukaruka966.contractapi" `
        -Destination (Join-Path $testRoot "api") `
        -GlobalIgnorePath $globalIgnorePath
    Assert-GeneratedBlueprint `
        -BlueprintId "api-spring-postgres" `
        -ProjectId "contract-postgres" `
        -BasePackage "net.rukaruka966.contractpostgres" `
        -Destination (Join-Path $testRoot "pg") `
        -GlobalIgnorePath $globalIgnorePath
    Assert-NoOverwriteContract -Destination (Join-Path $testRoot "existing")
    Write-Host "Generated project contract test passed." -ForegroundColor Green
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
