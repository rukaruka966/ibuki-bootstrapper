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

function Assert-GeneratedBlueprint {
    param(
        [Parameter(Mandatory)]
        [string]$BlueprintId,

        [Parameter(Mandatory)]
        [string]$ProjectId,

        [string]$BasePackage = "",

        [Parameter(Mandatory)]
        [string]$Destination
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
    Assert-GeneratedBlueprint `
        -BlueprintId "web-hono" `
        -ProjectId "contract-web" `
        -Destination (Join-Path $testRoot "web")
    Assert-GeneratedBlueprint `
        -BlueprintId "api-spring" `
        -ProjectId "contract-api" `
        -BasePackage "net.rukaruka966.contractapi" `
        -Destination (Join-Path $testRoot "api")
    Assert-GeneratedBlueprint `
        -BlueprintId "api-spring-postgres" `
        -ProjectId "contract-postgres" `
        -BasePackage "net.rukaruka966.contractpostgres" `
        -Destination (Join-Path $testRoot "pg")
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
