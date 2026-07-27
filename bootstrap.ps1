# IBUKI_BOOTSTRAPPER_ENTRYPOINT_V1
& {
param(
    [string]$BootstrapRoot,
    [string]$InvocationPath,
    [object[]]$RawArguments
)

$core = {
[CmdletBinding()]
param(
    [Parameter(DontShow)]
    [bool]$IsInvokeExpression,
    [string]$Blueprint,
    [string]$ProjectId,
    [string]$DisplayName,
    [string]$BasePackage,
    [string]$Destination,
    [string]$RepositoryName,
    [string]$RepositoryDescription,
    [switch]$UseCurrentDirectory,
    [switch]$SkipGitHub,
    [switch]$NonInteractive,
    [switch]$Yes
)

$previousConsoleOutputEncoding = [Console]::OutputEncoding
$lastExitCodeVariable = if ($IsInvokeExpression) {
    Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
} else {
    $null
}
$lastExitCodeExisted = $null -ne $lastExitCodeVariable
$previousLastExitCode = if ($lastExitCodeExisted) {
    $lastExitCodeVariable.Value
} else {
    $null
}

try {
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8WithoutBom
$OutputEncoding = $utf8WithoutBom
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$state = [PSCustomObject]@{
    BootstrapperVersion = "0.2.0"
    BootstrapperRepository = "rukaruka966/ibuki-bootstrapper"
    RawBaseUrl = "https://raw.githubusercontent.com/rukaruka966/ibuki-bootstrapper/main"
    BlueprintRevision = "main"
    UseAuthenticatedGitHubApi = $false
    RemoteMetadataDiagnostic = ""
    CreatedFiles = [System.Collections.Generic.List[string]]::new()
    CreatedRepository = ""
    CurrentPhase = "Start"
    CancelRequested = $false
    MaximumDestinationLength = 96
    MaximumBlueprintFiles = 256
    MaximumBlueprintSourceBytes = 10MB
    MaximumBlueprintTotalBytes = 50MB
    MaximumGeneratedPathLength = 240
}

function Write-Phase {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $state.CurrentPhase = $Name
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory)]
        [string]$WorkingDirectory
    )

    Push-Location -LiteralPath $WorkingDirectory

    try {
        & $FilePath @Arguments | ForEach-Object {
            Write-Host $_
        }
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            $argumentText = $Arguments -join " "
            throw "Command failed with exit code $exitCode`: $FilePath $argumentText"
        }
    } finally {
        Pop-Location
    }
}

function Get-CommandOutput {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory)]
        [string]$WorkingDirectory
    )

    Push-Location -LiteralPath $WorkingDirectory

    try {
        $output = & $FilePath @Arguments

        if ($LASTEXITCODE -ne 0) {
            $argumentText = $Arguments -join " "
            throw "Command failed with exit code $LASTEXITCODE`: $FilePath $argumentText"
        }

        return ($output -join "`n").Trim()
    } finally {
        Pop-Location
    }
}

function Assert-Command {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }

    Write-Host "[OK] $Name"
}

function Test-WindowsDeviceName {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    return $Value.ToLowerInvariant() -match '^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])$'
}

function Assert-ProjectId {
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Label
    )

    if ($Value -notmatch '^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$') {
        throw "$Label must start with a lowercase letter and contain only lowercase letters, numbers, and single hyphens."
    }

    if (Test-WindowsDeviceName -Value $Value) {
        throw "$Label cannot be a reserved Windows device name: '$Value'."
    }
}

function Get-JavaKotlinReservedWords {
    return @(
        "abstract", "actual", "annotation", "as", "assert", "boolean", "break",
        "by", "byte", "case", "catch", "char", "class", "companion", "const",
        "constructor", "continue", "crossinline", "data", "default", "delegate",
        "do", "double", "dynamic", "else", "enum", "expect", "exports", "extends",
        "external", "false", "field", "file", "final", "finally", "float", "for",
        "fun", "get", "goto", "if", "implements", "import", "in", "infix", "init",
        "inline", "inner", "instanceof", "int", "interface", "internal", "is",
        "lateinit", "long", "module", "native", "new", "noinline", "non-sealed",
        "null", "object", "open", "opens", "operator", "out", "override", "package",
        "param", "permits", "private", "property", "protected", "public", "receiver",
        "record", "reified", "requires", "return", "sealed", "set", "setparam",
        "short", "static", "strictfp", "super", "suspend", "switch", "synchronized",
        "tailrec", "this", "throw", "throws", "to", "transient", "transitive", "true",
        "try", "typealias", "typeof", "uses", "val", "var", "vararg", "void",
        "volatile", "when", "where", "while", "with", "yield"
    )
}

function Assert-BasePackage {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value -notmatch '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$') {
        throw "Base package must contain at least two lowercase Java/Kotlin identifier segments separated by dots."
    }

    foreach ($segment in $Value.Split(".")) {
        if ((Get-JavaKotlinReservedWords) -contains $segment) {
            throw "Base package contains a reserved Java/Kotlin word: '$segment'."
        }

        if (Test-WindowsDeviceName -Value $segment) {
            throw "Base package contains a reserved Windows device name: '$segment'."
        }
    }
}

function ConvertTo-BootstrapperVersion {
    param(
        [string]$Tag
    )

    if ($Tag -match '(?:^v|latest:\s*v)(?<Version>\d+\.\d+\.\d+)(?:\)|$)') {
        return $Matches.Version
    }

    return "unavailable"
}

function Test-LocalBlueprintAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [string]$BlueprintId = ""
    )

    $blueprintsRoot = Join-Path $Root "blueprints"

    if (-not (Test-Path -LiteralPath $blueprintsRoot -PathType Container)) {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($BlueprintId)) {
        $manifestPath = Join-Path $blueprintsRoot "$BlueprintId/manifest.json"
        return (Test-Path -LiteralPath $manifestPath -PathType Leaf)
    }

    foreach ($directory in @(Get-ChildItem -LiteralPath $blueprintsRoot -Directory)) {
        if (Test-Path -LiteralPath (Join-Path $directory.FullName "manifest.json") -PathType Leaf) {
            return $true
        }
    }

    return $false
}

function Get-LocalReleaseMetadata {
    if ([string]::IsNullOrWhiteSpace($BootstrapRoot)) {
        return $null
    }

    $gitDirectory = Join-Path $BootstrapRoot ".git"

    if (
        -not (Test-LocalBlueprintAvailable -Root $BootstrapRoot) -or
        -not (Test-Path -LiteralPath $gitDirectory) -or
        -not (Get-Command git -ErrorAction SilentlyContinue)
    ) {
        return $null
    }

    $commit = & git -C $BootstrapRoot rev-parse HEAD 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($commit -join ""))) {
        return $null
    }

    $fullCommitId = ($commit -join "").Trim()
    $branch = (& git -C $BootstrapRoot branch --show-current 2>$null) -join ""

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
        $branch = "local"
    } else {
        $branch = $branch.Trim()
    }

    $workingTreeStatus = (& git -C $BootstrapRoot status --porcelain 2>$null) -join ""
    $isWorkingTreeDirty = $LASTEXITCODE -ne 0 -or
        -not [string]::IsNullOrWhiteSpace($workingTreeStatus)
    $pointingTags = @(
        & git -C $BootstrapRoot tag --points-at HEAD --list "v[0-9]*" 2>$null |
            Where-Object { $_ -match '^v\d+\.\d+\.\d+$' } |
            Sort-Object { [version]($_.Substring(1)) } -Descending
    )
    $releaseTag = if ($pointingTags.Count -gt 0 -and -not $isWorkingTreeDirty) {
        $pointingTags[0]
    } else {
        $latestTag = & git -C $BootstrapRoot describe `
            --tags `
            --match "v[0-9]*" `
            --abbrev=0 `
            HEAD `
            2>$null

        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($latestTag -join ""))) {
            $latestTagName = ($latestTag -join "").Trim()

            if ($isWorkingTreeDirty) {
                "Unreleased (working tree; latest: $latestTagName)"
            } else {
                "Unreleased (latest: $latestTagName)"
            }
        } else {
            "Unreleased (no previous tag)"
        }
    }

    return [PSCustomObject]@{
        ReleaseTag = $releaseTag
        CommitId = $fullCommitId.Substring(0, [Math]::Min(12, $fullCommitId.Length))
        FullCommitId = $fullCommitId
        Channel = $branch
        Version = ConvertTo-BootstrapperVersion -Tag $releaseTag
        IsLocal = $true
        Diagnostic = ""
    }
}

function Get-GitHubResponseHeader {
    param(
        [object]$Headers,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $Headers) {
        return ""
    }

    try {
        $values = @($Headers.GetValues($Name))

        if ($values.Count -gt 0) {
            return [string]$values[0]
        }
    } catch {
        try {
            return [string]$Headers[$Name]
        } catch {
            return ""
        }
    }

    return ""
}

function Get-GitHubApiFailureDiagnostic {
    param(
        [Parameter(Mandatory)]
        [object]$ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    $response = if (@($exception.PSObject.Properties.Name) -contains "Response") {
        $exception.Response
    } else {
        $null
    }
    $statusCode = if ($null -ne $response) {
        try {
            [int]$response.StatusCode
        } catch {
            0
        }
    } else {
        0
    }
    if (
        $statusCode -eq 0 -and
        $null -ne $exception.Data -and
        $exception.Data.Contains("StatusCode")
    ) {
        $statusCode = [int]$exception.Data["StatusCode"]
    }
    $remaining = if ($null -ne $response) {
        Get-GitHubResponseHeader -Headers $response.Headers -Name "X-RateLimit-Remaining"
    } elseif (
        $null -ne $exception.Data -and
        $exception.Data.Contains("RateLimitRemaining")
    ) {
        [string]$exception.Data["RateLimitRemaining"]
    } else {
        ""
    }

    if ($statusCode -eq 403 -and $remaining -eq "0") {
        $resetValue = if ($null -ne $response) {
            Get-GitHubResponseHeader `
                -Headers $response.Headers `
                -Name "X-RateLimit-Reset"
        } elseif (
            $null -ne $exception.Data -and
            $exception.Data.Contains("RateLimitReset")
        ) {
            [string]$exception.Data["RateLimitReset"]
        } else {
            ""
        }
        $retryText = ""
        $resetSeconds = [long]0

        if ([long]::TryParse($resetValue, [ref]$resetSeconds)) {
            $resetTime = [DateTimeOffset]::FromUnixTimeSeconds($resetSeconds).ToLocalTime()
            $retryText = " Retry after $($resetTime.ToString('yyyy-MM-dd HH:mm:ss zzz'))."
        }

        return "Anonymous GitHub API rate limit exceeded.$retryText"
    }

    if ($statusCode -gt 0) {
        return "Anonymous GitHub API request failed (HTTP $statusCode)."
    }

    return "Anonymous GitHub API request failed."
}

function Invoke-AuthenticatedGitHubApi {
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint
    )

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI fallback is unavailable."
    }

    $output = & gh api `
        --hostname github.com `
        --method GET `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2026-03-10" `
        $Endpoint `
        2>$null
    $exitCode = $LASTEXITCODE
    $json = ($output -join "`n").Trim()

    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
        throw "Authenticated GitHub CLI fallback failed."
    }

    try {
        return ($json | ConvertFrom-Json)
    } catch {
        throw "Authenticated GitHub CLI fallback returned invalid JSON."
    }
}

function Invoke-RemoteGitHubApi {
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint
    )

    if ($state.UseAuthenticatedGitHubApi) {
        return Invoke-AuthenticatedGitHubApi -Endpoint $Endpoint
    }

    $headers = @{
        Accept = "application/vnd.github+json"
        "User-Agent" = "Ibuki-Bootstrapper"
        "X-GitHub-Api-Version" = "2026-03-10"
    }
    $uri = "https://api.github.com/$Endpoint"

    try {
        return Invoke-RestMethod -Uri $uri -Headers $headers
    } catch {
        $anonymousDiagnostic = Get-GitHubApiFailureDiagnostic -ErrorRecord $_
    }

    try {
        $result = Invoke-AuthenticatedGitHubApi -Endpoint $Endpoint
        $state.UseAuthenticatedGitHubApi = $true
        $state.RemoteMetadataDiagnostic = (
            "$anonymousDiagnostic Used authenticated GitHub CLI fallback."
        )
        return $result
    } catch {
        $fallbackDiagnostic = if (Get-Command gh -ErrorAction SilentlyContinue) {
            "Authenticated GitHub CLI fallback failed or is not logged in."
        } else {
            "GitHub CLI fallback is unavailable."
        }
        throw "$anonymousDiagnostic $fallbackDiagnostic"
    }
}

function Get-RemoteReleaseMetadata {
    $apiBasePath = "repos/$($state.BootstrapperRepository)"
    $fullCommitId = ""
    $diagnostic = $state.RemoteMetadataDiagnostic

    try {
        $commitInfo = Invoke-RemoteGitHubApi -Endpoint "$apiBasePath/commits/main"
        $fullCommitId = [string]$commitInfo.sha

        if ($fullCommitId -notmatch '^[0-9a-f]{40}$') {
            throw "GitHub metadata returned an invalid main Commit SHA."
        }
    } catch {
        $diagnostic = $_.Exception.Message
        return [PSCustomObject]@{
            ReleaseTag = "unavailable"
            CommitId = "unavailable"
            FullCommitId = ""
            Channel = "main"
            Version = "unavailable"
            IsLocal = $false
            Diagnostic = $diagnostic
        }
    }

    $releaseTag = "unavailable"

    try {
        $latestRelease = Invoke-RemoteGitHubApi -Endpoint "$apiBasePath/releases/latest"
        $latestTag = [string]$latestRelease.tag_name

        if ($latestTag -notmatch '^v\d+\.\d+\.\d+$') {
            throw "GitHub metadata returned an invalid Release Tag."
        }

        $encodedTag = [uri]::EscapeDataString($latestTag)
        $tagCommit = Invoke-RemoteGitHubApi -Endpoint "$apiBasePath/commits/$encodedTag"
        $tagCommitId = [string]$tagCommit.sha

        if ($tagCommitId -notmatch '^[0-9a-f]{40}$') {
            throw "GitHub metadata returned an invalid Release Commit SHA."
        }

        $releaseTag = if ($tagCommitId -eq $fullCommitId) {
            $latestTag
        } else {
            "Unreleased (latest: $latestTag)"
        }
    } catch {
        $diagnostic = $_.Exception.Message
        $releaseTag = "unavailable"
    }

    if (-not [string]::IsNullOrWhiteSpace($state.RemoteMetadataDiagnostic)) {
        $diagnostic = $state.RemoteMetadataDiagnostic
    }

    return [PSCustomObject]@{
        ReleaseTag = $releaseTag
        CommitId = $fullCommitId.Substring(0, [Math]::Min(12, $fullCommitId.Length))
        FullCommitId = $fullCommitId
        Channel = "main"
        Version = ConvertTo-BootstrapperVersion -Tag $releaseTag
        IsLocal = $false
        Diagnostic = $diagnostic
    }
}

function Get-BootstrapReleaseMetadata {
    $localMetadata = Get-LocalReleaseMetadata

    if ($null -ne $localMetadata) {
        return $localMetadata
    }

    return Get-RemoteReleaseMetadata
}

function Write-BootstrapReleaseMetadata {
    param(
        [Parameter(Mandatory)]
        [object]$Metadata
    )

    Write-Host "------------------------------------------------------------"
    Write-Host "Ibuki Bootstrapper"
    Write-Host ""
    Write-Host "Release/Tag : $($Metadata.ReleaseTag)"
    Write-Host "Commit ID   : $($Metadata.CommitId)"
    Write-Host "Channel     : $($Metadata.Channel)"
    Write-Host "Source      : $($state.BootstrapperRepository)"

    if (-not [string]::IsNullOrWhiteSpace($Metadata.Diagnostic)) {
        Write-Host "Metadata    : $($Metadata.Diagnostic)" -ForegroundColor Yellow
    }

    Write-Host "------------------------------------------------------------"
}

function Test-EmptyDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $true
    }

    $item = Get-Item -LiteralPath $Path

    if (-not $item.PSIsContainer) {
        return $false
    }

    return -not [bool](Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)
}

function Confirm-Action {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    if ($Yes) {
        return $true
    }

    if ($NonInteractive) {
        throw "Confirmation was required in non-interactive mode. Pass -Yes to confirm."
    }

    $answer = Read-Host "$Prompt [Y/n]"

    if ($null -eq $answer) {
        $state.CancelRequested = $true
        return $false
    }

    return $answer -eq "" -or $answer.Trim().ToLowerInvariant() -eq "y"
}

function Select-Blueprint {
    while ($true) {
        Write-Host ""
        Write-Host "Select a project configuration:"
        Write-Host "  [1] Web: React + Hono (available)"
        Write-Host "  [2] Web: React + Hono + Spring Boot (Coming soon)"
        Write-Host "  [3] Web API: Spring Boot (available)"
        Write-Host "  [4] Web API: Spring Boot + PostgreSQL (available)"
        Write-Host "  [5] Android: Jetpack Compose (Coming soon)"
        Write-Host "  [6] Windows Desktop: Compose Multiplatform (Coming soon)"
        Write-Host "  [0] Cancel"

        $selection = Read-Host "Configuration [default: 1]"

        if ($null -eq $selection) {
            $state.CancelRequested = $true
            return $null
        }

        switch ($selection) {
            { $_ -eq "" -or $_ -eq "1" } {
                return "web-hono"
            }
            "2" {
                Write-Warning "Web: React + Hono + Spring Boot is Coming soon. Select an available configuration."
                continue
            }
            "3" {
                return "api-spring"
            }
            "4" {
                return "api-spring-postgres"
            }
            "5" {
                Write-Warning "Android: Jetpack Compose is Coming soon. Select an available configuration."
                continue
            }
            "6" {
                Write-Warning "Windows Desktop: Compose Multiplatform is Coming soon. Select an available configuration."
                continue
            }
            { $_ -eq "0" -or $_.Trim().ToLowerInvariant() -eq "q" } {
                return $null
            }
            default {
                Write-Warning "Unknown selection '$selection'. Enter 0, 1, 2, 3, 4, 5, or 6."
                continue
            }
        }
    }
}

function Read-GitHubChoice {
    while ($true) {
        $answer = Read-Host "Create a private GitHub repository? [Y/n]"

        if ($null -eq $answer) {
            $state.CancelRequested = $true
            return $false
        }

        if ($answer -eq "" -or $answer.Trim().ToLowerInvariant() -eq "y") {
            return $true
        }

        if ($answer.Trim().ToLowerInvariant() -eq "n") {
            return $false
        }

        Write-Warning "Enter 'y' or 'n'."
    }
}

function Resolve-BootstrapConfiguration {
    $resolvedBlueprint = $Blueprint
    $resolvedProjectId = $ProjectId
    $resolvedDisplayName = $DisplayName
    $resolvedBasePackage = $BasePackage
    $resolvedDestination = $Destination
    $resolvedRepositoryName = $RepositoryName

    if ($NonInteractive) {
        if ([string]::IsNullOrWhiteSpace($resolvedBlueprint)) {
            $resolvedBlueprint = "web-hono"
        }
    } else {
        $resolvedBlueprint = Select-Blueprint

        if ($null -eq $resolvedBlueprint) {
            return $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedProjectId)) {
        if ($NonInteractive) {
            throw "-ProjectId is required in non-interactive mode."
        }

        $resolvedProjectId = Read-Host "Project ID (lowercase kebab-case)"

        if ($null -eq $resolvedProjectId) {
            $state.CancelRequested = $true
            return $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedDisplayName)) {
        if ($NonInteractive) {
            $resolvedDisplayName = $resolvedProjectId
        } else {
            $resolvedDisplayName = Read-Host "Display name [$resolvedProjectId]"

            if ($null -eq $resolvedDisplayName) {
                $state.CancelRequested = $true
                return $null
            }

            if ([string]::IsNullOrWhiteSpace($resolvedDisplayName)) {
                $resolvedDisplayName = $resolvedProjectId
            }
        }
    }

    $isSpringBlueprint = @("api-spring", "api-spring-postgres") -contains $resolvedBlueprint

    if ($isSpringBlueprint) {
        if ([string]::IsNullOrWhiteSpace($resolvedBasePackage)) {
            $normalizedProjectId = $resolvedProjectId.Replace("-", "").ToLowerInvariant()

            if (
                (Get-JavaKotlinReservedWords) -contains $normalizedProjectId -or
                (Test-WindowsDeviceName -Value $normalizedProjectId)
            ) {
                $normalizedProjectId = "${normalizedProjectId}app"
            }

            $defaultBasePackage = "net.rukaruka966.$normalizedProjectId"

            if ($NonInteractive) {
                $resolvedBasePackage = $defaultBasePackage
            } else {
                $resolvedBasePackage = Read-Host "Base package [$defaultBasePackage]"

                if ($null -eq $resolvedBasePackage) {
                    $state.CancelRequested = $true
                    return $null
                }

                if ([string]::IsNullOrWhiteSpace($resolvedBasePackage)) {
                    $resolvedBasePackage = $defaultBasePackage
                }
            }
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($resolvedBasePackage)) {
        throw "-BasePackage can only be used with a Spring Blueprint."
    }

    if ($UseCurrentDirectory) {
        $resolvedDestination = (Get-Location).Path
    } elseif ([string]::IsNullOrWhiteSpace($resolvedDestination)) {
        if ($NonInteractive) {
            throw "-Destination or -UseCurrentDirectory is required in non-interactive mode."
        }

        $locationChoice = Read-Host "Destination: [1] new '$resolvedProjectId' folder, [2] current empty folder [default: 1]"

        if ($null -eq $locationChoice) {
            $state.CancelRequested = $true
            return $null
        }

        if ($locationChoice -eq "2") {
            $resolvedDestination = (Get-Location).Path
        } else {
            $resolvedDestination = Join-Path (Get-Location).Path $resolvedProjectId
        }
    }

    if ($NonInteractive) {
        $createGitHub = -not [bool]$SkipGitHub
    } elseif ($SkipGitHub) {
        $createGitHub = $false
    } else {
        $createGitHub = Read-GitHubChoice

        if ($state.CancelRequested) {
            return $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedRepositoryName)) {
        $resolvedRepositoryName = $resolvedProjectId
    }

    return [PSCustomObject]@{
        BlueprintId = $resolvedBlueprint
        ProjectId = $resolvedProjectId
        DisplayName = $resolvedDisplayName
        BasePackage = $resolvedBasePackage
        BasePackagePath = if ($isSpringBlueprint) {
            $resolvedBasePackage.Replace(".", "/")
        } else {
            ""
        }
        Destination = [System.IO.Path]::GetFullPath($resolvedDestination)
        CreateGitHub = $createGitHub
        GitHubOwner = ""
        RepositoryName = $resolvedRepositoryName
        RepositoryDescription = $RepositoryDescription
    }
}

function Assert-BootstrapConfiguration {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    if (@("web-hono", "api-spring", "api-spring-postgres") -notcontains $Configuration.BlueprintId) {
        throw "Blueprint '$($Configuration.BlueprintId)' is not available. Available blueprints: web-hono, api-spring, api-spring-postgres."
    }

    Assert-ProjectId -Value $Configuration.ProjectId -Label "Project ID"
    Assert-ProjectId -Value $Configuration.RepositoryName -Label "Repository name"

    if ($Configuration.DisplayName -match "[`r`n]") {
        throw "Display name cannot contain newlines."
    }

    if (@("api-spring", "api-spring-postgres") -contains $Configuration.BlueprintId) {
        Assert-BasePackage -Value $Configuration.BasePackage
    } elseif (-not [string]::IsNullOrWhiteSpace($Configuration.BasePackage)) {
        throw "Base package is not supported by Blueprint '$($Configuration.BlueprintId)'."
    }

    $destinationLength = $Configuration.Destination.Length

    if ($destinationLength -gt $state.MaximumDestinationLength) {
        throw (
            "Destination path is too long ($destinationLength characters; " +
            "maximum $($state.MaximumDestinationLength)). " +
            "Choose a shorter destination, such as C:\workspace\$($Configuration.ProjectId)."
        )
    }

    if (-not (Test-EmptyDirectory -Path $Configuration.Destination)) {
        throw "Destination must be an empty directory: $($Configuration.Destination)"
    }
}

function Show-BootstrapConfiguration {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory)]
        [object]$Manifest
    )

    Write-Phase -Name "Confirmation"
    Write-Host "Blueprint ID      : $($Configuration.BlueprintId)"
    Write-Host "Configuration     : $($Manifest.displayName)"
    Write-Host "Project ID        : $($Configuration.ProjectId)"
    Write-Host "Display name      : $($Configuration.DisplayName)"

    if (-not [string]::IsNullOrWhiteSpace($Configuration.BasePackage)) {
        Write-Host "Base package      : $($Configuration.BasePackage)"
    }
    Write-Host "Destination       : $($Configuration.Destination)"

    if ($Configuration.CreateGitHub) {
        Write-Host "GitHub repository : $($Configuration.GitHubOwner)/$($Configuration.RepositoryName) (private)"
        Write-Host "Branches          : main, develop"
    } else {
        Write-Host "GitHub            : skipped"
        Write-Host "Branches          : none (local generation only)"
    }

    foreach ($requirementGroup in @(
        [PSCustomObject]@{
            Category = "repository"
            Heading = "Repository operation requirements (not checked by Ibuki):"
        },
        [PSCustomObject]@{
            Category = "application"
            Heading = "Application development requirements (not checked by Ibuki):"
        }
    )) {
        $requirements = @(
            $Manifest.projectRequirements | Where-Object {
                $_.category -eq $requirementGroup.Category
            }
        )

        if ($requirements.Count -gt 0) {
            Write-Host $requirementGroup.Heading

            foreach ($requirement in $requirements) {
                $versionRequirement = if (
                    @($requirement.PSObject.Properties.Name) -contains "requiredMajor"
                ) {
                    "major version $($requirement.requiredMajor) required " +
                        "(minimum $($requirement.minimumVersion))"
                } else {
                    ">= $($requirement.minimumVersion)"
                }
                Write-Host "  $($requirement.id) : $versionRequirement"
            }
        }
    }

    Write-Host "Project-owned checks (not run by Ibuki):"

    foreach ($step in @($Manifest.recommendedCommands)) {
        Write-Host "  $($step.command) $(@($step.arguments) -join ' ')"
    }
}

function Get-BlueprintSourceBytes {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [string]$LocalBlueprintRoot = "",

        [Parameter(Mandatory)]
        [string]$BlueprintId,

        [string]$RemoteAssetRoot = "",

        [switch]$UseLocalBlueprint
    )

    if ($UseLocalBlueprint) {
        Assert-SafeBlueprintRelativePath -Value $Source -Label "source"
        $localPath = Join-Path $LocalBlueprintRoot (
            $Source -replace '/', [System.IO.Path]::DirectorySeparatorChar
        )
        $canonicalBlueprintRoot = [System.IO.Path]::GetFullPath($LocalBlueprintRoot)
        $canonicalSource = [System.IO.Path]::GetFullPath($localPath)
        $sourcePrefix = $canonicalBlueprintRoot.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ) + [System.IO.Path]::DirectorySeparatorChar

        if (-not $canonicalSource.StartsWith(
            $sourcePrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Local blueprint source escapes its root: $Source"
        }

        if (-not (Test-Path -LiteralPath $canonicalSource -PathType Leaf)) {
            throw "Local blueprint '$BlueprintId' is missing its manifest source: $Source"
        }

        Assert-NoReparsePoint `
            -DestinationRoot $canonicalBlueprintRoot `
            -TargetParent (Split-Path -Parent $canonicalSource)

        if (
            (Get-Item -LiteralPath $canonicalSource).Attributes.HasFlag(
                [System.IO.FileAttributes]::ReparsePoint
            )
        ) {
            throw "Local blueprint source must not be a reparse point: $Source"
        }

        return ,([System.IO.File]::ReadAllBytes($canonicalSource))
    }

    $assetRoot = if ([string]::IsNullOrWhiteSpace($RemoteAssetRoot)) {
        "blueprints/$BlueprintId"
    } else {
        $RemoteAssetRoot
    }
    $uri = "$($state.RawBaseUrl)/$assetRoot/$Source"
    $client = [System.Net.Http.HttpClient]::new()

    try {
        return ,($client.GetByteArrayAsync($uri).GetAwaiter().GetResult())
    } finally {
        $client.Dispose()
    }
}

function ConvertFrom-BlueprintTextBytes {
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes,

        [Parameter(Mandatory)]
        [string]$Source
    )

    if (
        $Bytes.Length -ge 3 -and
        $Bytes[0] -eq 0xEF -and
        $Bytes[1] -eq 0xBB -and
        $Bytes[2] -eq 0xBF
    ) {
        throw "Blueprint text source must not contain a UTF-8 BOM: $Source"
    }

    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

    try {
        $content = $strictUtf8.GetString($Bytes)
    } catch [System.Text.DecoderFallbackException] {
        throw "Blueprint text source is not valid UTF-8: $Source"
    }

    if ($content.Contains("`r")) {
        throw "Blueprint text source must use LF line endings: $Source"
    }

    return $content
}

function Read-BlueprintManifest {
    param(
        [Parameter(Mandatory)]
        [string]$BlueprintId,

        [string]$LocalBlueprintRoot = "",

        [string]$RemoteAssetRoot = "",

        [switch]$UseLocalBlueprint
    )

    $bytes = Get-BlueprintSourceBytes `
        -Source "manifest.json" `
        -LocalBlueprintRoot $LocalBlueprintRoot `
        -BlueprintId $BlueprintId `
        -RemoteAssetRoot $RemoteAssetRoot `
        -UseLocalBlueprint:$UseLocalBlueprint

    if ($bytes.Length -gt $state.MaximumBlueprintSourceBytes) {
        throw "Blueprint manifest exceeds the size limit."
    }

    $json = ConvertFrom-BlueprintTextBytes `
        -Bytes $bytes `
        -Source "manifest.json"

    try {
        return $json | ConvertFrom-Json
    } catch {
        throw "Blueprint manifest '$BlueprintId' is not valid JSON."
    }
}

function Get-Sha256Hex {
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)
    ).ToLowerInvariant()
}

function Assert-SafeBlueprintRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Label,

        [switch]$AllowCurrentDirectory
    )

    if ($AllowCurrentDirectory -and $Value -eq ".") {
        return
    }

    if (
        [string]::IsNullOrWhiteSpace($Value) -or
        [System.IO.Path]::IsPathRooted($Value) -or
        $Value -match '[\x00-\x1f\\:*?"<>|%#]' -or
        $Value.StartsWith("\\")
    ) {
        throw "Blueprint manifest contains an unsafe $Label path: '$Value'."
    }

    $segments = @($Value -split '/')

    foreach ($segment in $segments) {
        $baseName = $segment.Split(".")[0]

        if (
            [string]::IsNullOrWhiteSpace($segment) -or
            @(".", "..") -contains $segment -or
            $segment.EndsWith(".") -or
            $segment.EndsWith(" ") -or
            $baseName -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])$'
        ) {
            throw "Blueprint manifest contains an unsafe $Label path: '$Value'."
        }
    }
}

function Assert-BlueprintManifest {
    param(
        [Parameter(Mandatory)]
        [object]$Manifest,

        [Parameter(Mandatory)]
        [string]$BlueprintId,

        [string]$LocalBlueprintRoot = "",

        [switch]$UseLocalBlueprint
    )

    $manifestProperties = @($Manifest.PSObject.Properties.Name)
    $allowedManifestProperties = @(
        "schemaVersion",
        "id",
        "version",
        "displayName",
        "projectRequirements",
        "recommendedCommands",
        "fileSets",
        "files"
    )
    $unknownManifestProperties = @(
        $manifestProperties | Where-Object {
            $allowedManifestProperties -notcontains $_
        }
    )

    if ($unknownManifestProperties.Count -gt 0) {
        throw "Blueprint manifest '$BlueprintId' contains unknown top-level properties."
    }

    foreach ($requiredProperty in $allowedManifestProperties) {
        if ($manifestProperties -notcontains $requiredProperty) {
            throw "Blueprint manifest '$BlueprintId' is missing '$requiredProperty'."
        }
    }

    if (
        (
            $Manifest.schemaVersion -isnot [int] -and
            $Manifest.schemaVersion -isnot [long]
        ) -or
            $Manifest.schemaVersion -ne 5
    ) {
        throw "Blueprint manifest '$BlueprintId' must use schemaVersion 5."
    }

    if (
        $Manifest.id -isnot [string] -or
        $Manifest.version -isnot [string] -or
        $Manifest.displayName -isnot [string] -or
        $Manifest.projectRequirements -isnot [System.Array] -or
        $Manifest.recommendedCommands -isnot [System.Array] -or
        $Manifest.fileSets -isnot [System.Array] -or
        $Manifest.files -isnot [System.Array]
    ) {
        throw "Blueprint manifest '$BlueprintId' has invalid top-level property types."
    }

    if ($Manifest.id -ne $BlueprintId) {
        throw "Blueprint manifest ID '$($Manifest.id)' does not match '$BlueprintId'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$Manifest.displayName)) {
        throw "Blueprint manifest '$BlueprintId' does not have a displayName."
    }

    if ([string]::IsNullOrWhiteSpace([string]$Manifest.version)) {
        throw "Blueprint manifest '$BlueprintId' does not have a version."
    }

    $fileSetIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($fileSetId in @($Manifest.fileSets)) {
        if (
            $fileSetId -isnot [string] -or
            [string]$fileSetId -notmatch '^[a-z][a-z0-9-]{0,63}$' -or
            -not $fileSetIds.Add([string]$fileSetId)
        ) {
            throw "Blueprint manifest '$BlueprintId' has an invalid or duplicate file set ID."
        }
    }

    $requirementIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($requirement in @($Manifest.projectRequirements)) {
        $requirementProperties = @($requirement.PSObject.Properties.Name)
        $allowedRequirementProperties = @(
            "id",
            "command",
            "versionArguments",
            "minimumVersion",
            "versionPattern",
            "category",
            "requiredMajor"
        )

        if (@(
            $requirementProperties | Where-Object {
                $allowedRequirementProperties -notcontains $_
            }
        ).Count -gt 0) {
            throw "Blueprint manifest '$BlueprintId' has unknown project requirement properties."
        }

        foreach ($requiredProperty in @(
            "id",
            "command",
            "versionArguments",
            "minimumVersion",
            "versionPattern",
            "category"
        )) {
            if ($requirementProperties -notcontains $requiredProperty) {
                throw "Blueprint manifest '$BlueprintId' has an incomplete project requirement declaration."
            }
        }

        if (
            [string]::IsNullOrWhiteSpace([string]$requirement.id) -or
            -not $requirementIds.Add([string]$requirement.id)
        ) {
            throw "Blueprint manifest '$BlueprintId' has a duplicate or empty project requirement ID."
        }

        if ([string]::IsNullOrWhiteSpace([string]$requirement.command)) {
            throw "Blueprint manifest '$BlueprintId' has an empty project requirement command."
        }

        if (
            $requirement.id -isnot [string] -or
            $requirement.command -isnot [string] -or
            $requirement.minimumVersion -isnot [string] -or
            $requirement.versionPattern -isnot [string] -or
            $requirement.category -isnot [string] -or
            $requirement.versionArguments -isnot [System.Array]
        ) {
            throw "Blueprint manifest '$BlueprintId' has invalid project requirement property types."
        }

        if (@("repository", "application") -notcontains $requirement.category) {
            throw "Blueprint manifest '$BlueprintId' has an invalid project requirement category."
        }

        try {
            $null = [version]$requirement.minimumVersion
            $null = [regex]::new([string]$requirement.versionPattern)
        } catch {
            throw "Blueprint manifest '$BlueprintId' has invalid project requirement version metadata."
        }

        if (
            @($requirement.PSObject.Properties.Name) -contains "requiredMajor" -and
            $requirement.requiredMajor -isnot [int] -and
            $requirement.requiredMajor -isnot [long]
        ) {
            throw "Blueprint manifest '$BlueprintId' has an invalid requiredMajor."
        }

        if (@($requirement.versionArguments | Where-Object { $_ -isnot [string] }).Count -gt 0) {
            throw "Blueprint manifest '$BlueprintId' has non-string project requirement arguments."
        }
    }

    foreach ($step in @($Manifest.recommendedCommands)) {
        $stepProperties = @($step.PSObject.Properties.Name)
        $allowedStepProperties = @("command", "arguments", "workingDirectory")

        if (
            @(
                $stepProperties | Where-Object {
                    $allowedStepProperties -notcontains $_
                }
            ).Count -gt 0 -or
            $stepProperties -notcontains "command" -or
            $stepProperties -notcontains "arguments" -or
            $stepProperties -notcontains "workingDirectory" -or
            $step.command -isnot [string] -or
            $step.arguments -isnot [System.Array] -or
            $step.workingDirectory -isnot [string] -or
            [string]::IsNullOrWhiteSpace([string]$step.command) -or
            @($step.arguments | Where-Object { $_ -isnot [string] }).Count -gt 0
        ) {
            throw "Blueprint manifest '$BlueprintId' has an invalid recommended command."
        }

        Assert-SafeBlueprintRelativePath `
            -Value ([string]$step.workingDirectory) `
            -Label "recommended command working directory" `
            -AllowCurrentDirectory
    }

    if (@($Manifest.files).Count -eq 0) {
        throw "Blueprint manifest '$BlueprintId' does not contain any files."
    }

    if (@($Manifest.files).Count -gt $state.MaximumBlueprintFiles) {
        throw "Blueprint manifest '$BlueprintId' contains too many files."
    }

    $targets = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $validationRoot = [System.IO.Path]::GetFullPath(
        (Join-Path ([System.IO.Path]::GetTempPath()) "ibuki-manifest-validation")
    )
    $validationPrefix = $validationRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    foreach ($file in @($Manifest.files)) {
        $propertyNames = @($file.PSObject.Properties.Name)
        $allowedFileProperties = @(
            "kind",
            "source",
            "target",
            "template",
            "targetTemplate",
            "sha256"
        )

        if (@(
            $propertyNames | Where-Object {
                $allowedFileProperties -notcontains $_
            }
        ).Count -gt 0) {
            throw "Blueprint manifest '$BlueprintId' has unknown file properties."
        }

        foreach ($requiredProperty in @("kind", "source", "target", "template")) {
            if ($propertyNames -notcontains $requiredProperty) {
                throw "Blueprint manifest '$BlueprintId' contains an entry without '$requiredProperty'."
            }
        }

        if ($file.source -isnot [string] -or $file.target -isnot [string]) {
            throw "Blueprint manifest '$BlueprintId' source and target values must be strings."
        }

        if ($file.kind -isnot [string]) {
            throw "Blueprint manifest '$BlueprintId' file kind must be a string."
        }

        Assert-SafeBlueprintRelativePath -Value $file.source -Label "source"
        Assert-SafeBlueprintRelativePath -Value $file.target -Label "target"

        $canonicalTarget = [System.IO.Path]::GetFullPath(
            (Join-Path $validationRoot $file.target)
        )

        if (-not $canonicalTarget.StartsWith(
            $validationPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Blueprint manifest '$BlueprintId' contains an unsafe target path: '$($file.target)'."
        }

        foreach ($existingTarget in $targets) {
            $existingPrefix = $existingTarget.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar
            $candidatePrefix = $canonicalTarget.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar

            if (
                $canonicalTarget.StartsWith(
                    $existingPrefix,
                    [System.StringComparison]::OrdinalIgnoreCase
                ) -or
                $existingTarget.StartsWith(
                    $candidatePrefix,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            ) {
                throw "Blueprint manifest '$BlueprintId' has a file/directory target collision."
            }
        }

        if (-not $targets.Add($canonicalTarget)) {
            throw "Blueprint manifest '$BlueprintId' contains a duplicate target: '$($file.target)'."
        }

        if ($file.template -isnot [bool]) {
            throw "Blueprint manifest '$BlueprintId' has a non-boolean template flag for '$($file.target)'."
        }

        if (
            $propertyNames -contains "targetTemplate" -and
            $file.targetTemplate -isnot [bool]
        ) {
            throw "Blueprint manifest '$BlueprintId' has a non-boolean targetTemplate flag for '$($file.target)'."
        }

        $targetTemplate = $propertyNames -contains "targetTemplate" -and $file.targetTemplate
        $targetTokens = @(
            [regex]::Matches([string]$file.target, '__[A-Z0-9_]+__') |
                ForEach-Object { $_.Value }
        )

        if ($targetTemplate) {
            if (
                $targetTokens.Count -eq 0 -or
                @(
                    $targetTokens |
                        Where-Object { $_ -ne "__BASE_PACKAGE_PATH__" }
                ).Count -gt 0
            ) {
                throw "Blueprint target template may only use __BASE_PACKAGE_PATH__: '$($file.target)'."
            }
        } elseif ($targetTokens.Count -gt 0) {
            throw "Blueprint target contains a token without targetTemplate: '$($file.target)'."
        }

        if (@("text", "binary") -notcontains $file.kind) {
            throw "Blueprint manifest '$BlueprintId' has an invalid file kind for '$($file.target)'."
        }

        if ($file.kind -eq "binary") {
            if ($file.template) {
                throw "Blueprint binary source cannot be a template: '$($file.source)'."
            }

            if (
                @($file.PSObject.Properties.Name) -notcontains "sha256" -or
                $file.sha256 -isnot [string] -or
                [string]$file.sha256 -notmatch '^[0-9a-fA-F]{64}$'
            ) {
                throw "Blueprint binary source requires a SHA-256 checksum: '$($file.source)'."
            }
        }

        if ($UseLocalBlueprint) {
            $localSource = Join-Path $LocalBlueprintRoot (
                $file.source -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            $canonicalBlueprintRoot = [System.IO.Path]::GetFullPath($LocalBlueprintRoot)
            $canonicalSource = [System.IO.Path]::GetFullPath($localSource)
            $sourcePrefix = $canonicalBlueprintRoot.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar

            if (-not $canonicalSource.StartsWith(
                $sourcePrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
                throw "Local blueprint source escapes its root: $($file.source)"
            }

            if (-not (Test-Path -LiteralPath $localSource -PathType Leaf)) {
                throw "Local blueprint '$BlueprintId' is missing its manifest source: $($file.source)"
            }

            Assert-NoReparsePoint `
                -DestinationRoot $canonicalBlueprintRoot `
                -TargetParent (Split-Path -Parent $canonicalSource)

            if (
                (Get-Item -LiteralPath $canonicalSource).Attributes.HasFlag(
                    [System.IO.FileAttributes]::ReparsePoint
                )
            ) {
                throw "Local blueprint source must not be a reparse point: $($file.source)"
            }
        }
    }
}

function Resolve-BlueprintFiles {
    param(
        [Parameter(Mandatory)]
        [object]$Manifest,

        [Parameter(Mandatory)]
        [string]$BlueprintId,

        [string]$LocalBlueprintRoot = "",

        [string]$LocalBlueprintsRoot = "",

        [switch]$UseLocalBlueprint
    )

    $resolvedFiles = [System.Collections.Generic.List[object]]::new()
    $combinedFiles = [System.Collections.Generic.List[object]]::new()

    foreach ($file in @($Manifest.files)) {
        $resolvedFiles.Add([PSCustomObject]@{
            File = $file
            SourceKey = "$BlueprintId::$($file.source)"
            AssetId = $BlueprintId
            LocalAssetRoot = $LocalBlueprintRoot
            RemoteAssetRoot = "blueprints/$BlueprintId"
        })
        $combinedFiles.Add($file)
    }

    foreach ($fileSetId in @($Manifest.fileSets)) {
        $localFileSetRoot = if ($UseLocalBlueprint) {
            Join-Path $LocalBlueprintsRoot "_common/$fileSetId"
        } else {
            ""
        }
        $remoteFileSetRoot = "blueprints/_common/$fileSetId"
        $fileSetManifest = Read-BlueprintManifest `
            -BlueprintId $fileSetId `
            -LocalBlueprintRoot $localFileSetRoot `
            -RemoteAssetRoot $remoteFileSetRoot `
            -UseLocalBlueprint:$UseLocalBlueprint

        Assert-BlueprintManifest `
            -Manifest $fileSetManifest `
            -BlueprintId $fileSetId `
            -LocalBlueprintRoot $localFileSetRoot `
            -UseLocalBlueprint:$UseLocalBlueprint

        if (
            @($fileSetManifest.fileSets).Count -ne 0 -or
            @($fileSetManifest.projectRequirements).Count -ne 0 -or
            @($fileSetManifest.recommendedCommands).Count -ne 0
        ) {
            throw "Blueprint file set '$fileSetId' may only declare files."
        }

        foreach ($file in @($fileSetManifest.files)) {
            $resolvedFiles.Add([PSCustomObject]@{
                File = $file
                SourceKey = "$fileSetId::$($file.source)"
                AssetId = $fileSetId
                LocalAssetRoot = $localFileSetRoot
                RemoteAssetRoot = $remoteFileSetRoot
            })
            $combinedFiles.Add($file)
        }
    }

    $combinedManifest = [PSCustomObject]@{
        schemaVersion = 5
        id = $Manifest.id
        version = $Manifest.version
        displayName = $Manifest.displayName
        projectRequirements = @($Manifest.projectRequirements)
        recommendedCommands = @($Manifest.recommendedCommands)
        fileSets = @()
        files = @($combinedFiles)
    }
    Assert-BlueprintManifest `
        -Manifest $combinedManifest `
        -BlueprintId $BlueprintId

    return ,$resolvedFiles
}

function Read-BlueprintSources {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$ResolvedFiles,

        [switch]$UseLocalBlueprint
    )

    $sources = [System.Collections.Generic.Dictionary[string, byte[]]]::new(
        [System.StringComparer]::Ordinal
    )
    $totalBytes = [long]0

    foreach ($resolvedFile in @($ResolvedFiles)) {
        $file = $resolvedFile.File
        $sourceKey = [string]$resolvedFile.SourceKey

        if (-not $sources.ContainsKey($sourceKey)) {
            $bytes = Get-BlueprintSourceBytes `
                -Source $file.source `
                -LocalBlueprintRoot $resolvedFile.LocalAssetRoot `
                -BlueprintId $resolvedFile.AssetId `
                -RemoteAssetRoot $resolvedFile.RemoteAssetRoot `
                -UseLocalBlueprint:$UseLocalBlueprint

            if ($bytes.Length -gt $state.MaximumBlueprintSourceBytes) {
                throw "Blueprint source exceeds the per-file size limit: $($file.source)"
            }

            $totalBytes += $bytes.Length

            if ($totalBytes -gt $state.MaximumBlueprintTotalBytes) {
                throw "Blueprint sources exceed the total size limit."
            }

            $sources.Add($sourceKey, $bytes)
        }

        $sourceBytes = $sources[$sourceKey]

        if ($file.kind -eq "text") {
            $null = ConvertFrom-BlueprintTextBytes `
                -Bytes $sourceBytes `
                -Source $file.source
        } else {
            $actualChecksum = Get-Sha256Hex -Bytes $sourceBytes

            if ($actualChecksum -ne ([string]$file.sha256).ToLowerInvariant()) {
                throw (
                    "Blueprint binary checksum mismatch for '$($file.source)'. " +
                    "Expected: $($file.sha256); actual: $actualChecksum"
                )
            }
        }
    }

    return ,$sources
}

function Convert-TemplateContent {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [hashtable]$Tokens
    )

    $tokenPattern = '__[A-Z0-9_]+__'

    foreach ($match in [regex]::Matches($Content, $tokenPattern)) {
        if (-not $Tokens.ContainsKey($match.Value)) {
            throw "Blueprint template contains an unsupported token: $($match.Value)"
        }
    }

    return [regex]::Replace(
        $Content,
        $tokenPattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            return [string]$Tokens[$match.Value]
        }
    )
}

function Assert-PreparedTargetPaths {
    param(
        [Parameter(Mandatory)]
        [string]$DestinationRoot,

        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$PreparedFiles
    )

    $canonicalRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
    $rootPrefix = $canonicalRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $targets = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($preparedFile in $PreparedFiles) {
        Assert-SafeBlueprintRelativePath `
            -Value $preparedFile.Target `
            -Label "rendered target"
        $canonicalTarget = [System.IO.Path]::GetFullPath(
            (Join-Path $canonicalRoot $preparedFile.Target)
        )

        if (-not $canonicalTarget.StartsWith(
            $rootPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Rendered Blueprint target escapes the destination: '$($preparedFile.Target)'."
        }

        if ($canonicalTarget.Length -gt $state.MaximumGeneratedPathLength) {
            throw (
                "Rendered Blueprint target path is too long " +
                "($($canonicalTarget.Length) characters; " +
                "maximum $($state.MaximumGeneratedPathLength)): '$($preparedFile.Target)'."
            )
        }

        foreach ($existingTarget in $targets) {
            $existingPrefix = $existingTarget.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar
            $candidatePrefix = $canonicalTarget.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar

            if (
                $canonicalTarget.StartsWith(
                    $existingPrefix,
                    [System.StringComparison]::OrdinalIgnoreCase
                ) -or
                $existingTarget.StartsWith(
                    $candidatePrefix,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            ) {
                throw "Rendered Blueprint targets have a file/directory collision."
            }
        }

        if (-not $targets.Add($canonicalTarget)) {
            throw "Rendered Blueprint contains a duplicate target: '$($preparedFile.Target)'."
        }
    }
}

function Write-GeneratedFile {
    param(
        [Parameter(Mandatory)]
        [string]$DestinationRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    $normalizedRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
    $targetPath = [System.IO.Path]::GetFullPath((Join-Path $normalizedRoot $RelativePath))
    $rootPrefix = $normalizedRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $targetPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Blueprint target escapes the destination: $RelativePath"
    }

    $parent = Split-Path -Parent $targetPath

    Assert-NoReparsePoint `
        -DestinationRoot $normalizedRoot `
        -TargetParent $parent

    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Assert-NoReparsePoint `
        -DestinationRoot $normalizedRoot `
        -TargetParent $parent

    $stream = $null

    try {
        $stream = [System.IO.File]::Open(
            $targetPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $stream.Write($Bytes, 0, $Bytes.Length)
    } catch [System.IO.IOException] {
        throw "Refusing to overwrite or race with an existing path: $targetPath"
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }

    $state.CreatedFiles.Add($targetPath)
}

function Write-GeneratedBinaryFile {
    param(
        [Parameter(Mandatory)]
        [string]$DestinationRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    $normalizedRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
    $targetPath = [System.IO.Path]::GetFullPath((Join-Path $normalizedRoot $RelativePath))
    $rootPrefix = $normalizedRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $targetPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Blueprint target escapes the destination: $RelativePath"
    }

    $parent = Split-Path -Parent $targetPath

    Assert-NoReparsePoint `
        -DestinationRoot $normalizedRoot `
        -TargetParent $parent

    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Assert-NoReparsePoint `
        -DestinationRoot $normalizedRoot `
        -TargetParent $parent

    $stream = $null

    try {
        $stream = [System.IO.File]::Open(
            $targetPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $stream.Write($Bytes, 0, $Bytes.Length)
    } catch [System.IO.IOException] {
        throw "Refusing to overwrite or race with an existing path: $targetPath"
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }

    $state.CreatedFiles.Add($targetPath)
}

function Assert-NoReparsePoint {
    param(
        [Parameter(Mandatory)]
        [string]$DestinationRoot,

        [Parameter(Mandatory)]
        [string]$TargetParent
    )

    $relativeParent = [System.IO.Path]::GetRelativePath($DestinationRoot, $TargetParent)
    $current = $DestinationRoot
    $paths = @($DestinationRoot)

    if ($relativeParent -ne ".") {
        foreach ($segment in $relativeParent -split '[\\/]') {
            $current = Join-Path $current $segment
            $paths += $current
        }
    }

    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        $item = Get-Item -LiteralPath $path -Force

        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to generate through a reparse point: $path"
        }
    }
}

function New-ProtectionRuleset {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Branch,

        [Parameter(Mandatory)]
        [ValidateSet("merge", "squash")]
        [string]$MergeMethod,

        [Parameter(Mandatory)]
        [string[]]$RequiredContexts,

        [Parameter(Mandatory)]
        [bool]$StrictRequiredChecks
    )

    $requiredStatusChecks = @(
        $RequiredContexts | ForEach-Object {
            @{
                context = $_
            }
        }
    )

    $payload = @{
        name = "Protect $Branch"
        target = "branch"
        enforcement = "active"
        conditions = @{
            ref_name = @{
                include = @("refs/heads/$Branch")
                exclude = @()
            }
        }
        rules = @(
            @{
                type = "deletion"
            },
            @{
                type = "non_fast_forward"
            },
            @{
                type = "pull_request"
                parameters = @{
                    allowed_merge_methods = @($MergeMethod)
                    dismiss_stale_reviews_on_push = $false
                    require_code_owner_review = $false
                    require_last_push_approval = $false
                    required_approving_review_count = 0
                    required_review_thread_resolution = $true
                }
            },
            @{
                type = "required_status_checks"
                parameters = @{
                    do_not_enforce_on_create = $true
                    required_status_checks = $requiredStatusChecks
                    strict_required_status_checks_policy = $StrictRequiredChecks
                }
            }
        )
    }

    $json = $payload | ConvertTo-Json -Depth 20 -Compress
    $payloadPath = [System.IO.Path]::GetTempFileName()

    try {
        $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($payloadPath, $json, $utf8WithoutBom)

        & gh api `
            --method POST `
            "repos/$Repository/rulesets" `
            -H "Accept: application/vnd.github+json" `
            -H "X-GitHub-Api-Version: 2026-03-10" `
            --input $payloadPath `
            --silent

        if ($LASTEXITCODE -ne 0) {
            throw "Unable to create the '$Branch' repository ruleset."
        }
    } finally {
        if (Test-Path -LiteralPath $payloadPath) {
            Remove-Item -LiteralPath $payloadPath -Force
        }
    }
}

function Assert-ProtectionRuleset {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Branch,

        [Parameter(Mandatory)]
        [ValidateSet("merge", "squash")]
        [string]$ExpectedMergeMethod,

        [Parameter(Mandatory)]
        [string[]]$ExpectedContexts,

        [Parameter(Mandatory)]
        [bool]$ExpectedStrictRequiredChecks,

        [Parameter(Mandatory)]
        [object[]]$Rulesets
    )

    $expectedName = "Protect $Branch"
    $matches = @($Rulesets | Where-Object { $_.name -eq $expectedName })

    if ($matches.Count -ne 1) {
        throw "Ruleset verification failed: expected exactly one '$expectedName' ruleset."
    }

    $rulesetId = $matches[0].id
    $detailsJson = & gh api `
        "repos/$Repository/rulesets/$rulesetId" `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2026-03-10"

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect the '$expectedName' repository ruleset."
    }

    $details = ($detailsJson -join "`n") | ConvertFrom-Json
    $includedRefs = @($details.conditions.ref_name.include)
    $excludedRefs = @($details.conditions.ref_name.exclude)

    if ($details.enforcement -ne "active") {
        throw "Ruleset verification failed: '$expectedName' is not active."
    }

    if ($includedRefs.Count -ne 1 -or $includedRefs[0] -ne "refs/heads/$Branch") {
        throw "Ruleset verification failed: '$expectedName' does not target only '$Branch'."
    }

    if ($excludedRefs.Count -ne 0) {
        throw "Ruleset verification failed: '$expectedName' unexpectedly excludes refs."
    }

    $rules = @($details.rules)
    $ruleTypes = @($rules | ForEach-Object { $_.type })
    $expectedRuleTypes = @(
        "deletion",
        "non_fast_forward",
        "pull_request",
        "required_status_checks"
    )
    $unexpectedRuleTypes = @(
        Compare-Object `
            -ReferenceObject @($expectedRuleTypes | Sort-Object) `
            -DifferenceObject @($ruleTypes | Sort-Object)
    )

    if (
        $ruleTypes.Count -ne $expectedRuleTypes.Count -or
        $unexpectedRuleTypes.Count -ne 0
    ) {
        throw "Ruleset verification failed: '$expectedName' has unexpected or duplicate rule types."
    }

    $pullRequestRule = @($rules | Where-Object { $_.type -eq "pull_request" })[0]

    if (-not $pullRequestRule.parameters.required_review_thread_resolution) {
        throw "Ruleset verification failed: '$expectedName' does not require resolved review threads."
    }

    if ([int]$pullRequestRule.parameters.required_approving_review_count -ne 0) {
        throw "Ruleset verification failed: '$expectedName' requires an unexpected approval count."
    }

    $allowedMergeMethods = @($pullRequestRule.parameters.allowed_merge_methods)

    if ($allowedMergeMethods.Count -ne 1 -or $allowedMergeMethods -notcontains $ExpectedMergeMethod) {
        throw "Ruleset verification failed: '$expectedName' does not allow only '$ExpectedMergeMethod' merges."
    }

    $statusRule = @($rules | Where-Object { $_.type -eq "required_status_checks" })[0]
    $requiredContexts = @($statusRule.parameters.required_status_checks | ForEach-Object { $_.context })

    $unexpectedContexts = @(
        Compare-Object `
            -ReferenceObject @($ExpectedContexts | Sort-Object -Unique) `
            -DifferenceObject @($requiredContexts | Sort-Object -Unique)
    )

    if (
        $requiredContexts.Count -ne $ExpectedContexts.Count -or
        $unexpectedContexts.Count -ne 0
    ) {
        throw "Ruleset verification failed: '$expectedName' has unexpected required status checks."
    }

    if (
        [bool]$statusRule.parameters.strict_required_status_checks_policy -ne
        $ExpectedStrictRequiredChecks
    ) {
        throw "Ruleset verification failed: '$expectedName' has an unexpected strict status check policy."
    }
}

function Invoke-GitHubProvisioning {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$RepoName,

        [string]$Description
    )

    $repository = "$Owner/$RepoName"

    Write-Phase -Name "Git"
    Invoke-CheckedCommand -FilePath git -Arguments @("init", "-b", "main") -WorkingDirectory $ProjectRoot
    Invoke-CheckedCommand -FilePath git -Arguments @(
        "commit",
        "--allow-empty",
        "-m",
        "chore: initialize repository",
        "-m",
        "Initialize the local and remote repository."
    ) -WorkingDirectory $ProjectRoot
    Invoke-CheckedCommand -FilePath git -Arguments @("add", "--all") -WorkingDirectory $ProjectRoot

    $gradleWrapper = Join-Path $ProjectRoot "systems/api-server/gradlew"

    if (Test-Path -LiteralPath $gradleWrapper -PathType Leaf) {
        Invoke-CheckedCommand -FilePath git -Arguments @(
            "update-index",
            "--chmod=+x",
            "systems/api-server/gradlew"
        ) -WorkingDirectory $ProjectRoot
    }

    Invoke-CheckedCommand -FilePath git -Arguments @(
        "commit",
        "-m",
        "feat: generate initial project scaffold",
        "-m",
        "Add the selected systems, CI, and project configuration."
    ) -WorkingDirectory $ProjectRoot

    $initialStatus = Get-CommandOutput `
        -FilePath git `
        -Arguments @("status", "--porcelain") `
        -WorkingDirectory $ProjectRoot

    if (-not [string]::IsNullOrWhiteSpace($initialStatus)) {
        throw "Generated repository is not clean before GitHub creation."
    }

    Write-Phase -Name "GitHub"
    $createArguments = @(
        "repo",
        "create",
        $repository,
        "--private",
        "--source",
        $ProjectRoot,
        "--remote",
        "origin"
    )

    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $createArguments += @("--description", $Description)
    }

    Invoke-CheckedCommand -FilePath gh -Arguments $createArguments -WorkingDirectory $ProjectRoot
    $state.CreatedRepository = "https://github.com/$repository"
    Invoke-CheckedCommand -FilePath git -Arguments @("push", "-u", "origin", "main") -WorkingDirectory $ProjectRoot
    Write-Host "GitHub Actions Quality runs independently after the push."

    Invoke-CheckedCommand -FilePath git -Arguments @("switch", "-c", "develop") -WorkingDirectory $ProjectRoot
    Invoke-CheckedCommand -FilePath git -Arguments @("push", "-u", "origin", "develop") -WorkingDirectory $ProjectRoot

    & gh api `
        --method PATCH `
        "repos/$repository" `
        -F "default_branch=main" `
        -F "has_issues=true" `
        -F "has_wiki=false" `
        -F "allow_squash_merge=true" `
        -F "allow_merge_commit=true" `
        -F "allow_rebase_merge=false" `
        -F "delete_branch_on_merge=true" `
        --silent

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to configure repository merge settings."
    }

    $repositoryJson = & gh api `
        "repos/$repository" `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2026-03-10"

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to verify repository merge settings."
    }

    $repositoryDetails = ($repositoryJson -join "`n") | ConvertFrom-Json

    if (
        -not $repositoryDetails.allow_merge_commit -or
        -not $repositoryDetails.allow_squash_merge -or
        $repositoryDetails.allow_rebase_merge -or
        $repositoryDetails.default_branch -ne "main" -or
        -not $repositoryDetails.delete_branch_on_merge
    ) {
        throw "Repository merge settings verification failed."
    }

    Write-Host "[OK] Repository merge settings"

    $protectionComplete = $true

    try {
        New-ProtectionRuleset `
            -Repository $repository `
            -Branch "main" `
            -MergeMethod "merge" `
            -RequiredContexts @("Quality") `
            -StrictRequiredChecks $false
        New-ProtectionRuleset `
            -Repository $repository `
            -Branch "develop" `
            -MergeMethod "squash" `
            -RequiredContexts @("Quality") `
            -StrictRequiredChecks $true

        $rulesetsJson = & gh api `
            "repos/$repository/rulesets" `
            -H "Accept: application/vnd.github+json" `
            -H "X-GitHub-Api-Version: 2026-03-10"

        if ($LASTEXITCODE -ne 0) {
            throw "Unable to verify repository rulesets."
        }

        $rulesets = @(($rulesetsJson -join "`n") | ConvertFrom-Json)

        Assert-ProtectionRuleset `
            -Repository $repository `
            -Branch "main" `
            -ExpectedMergeMethod "merge" `
            -ExpectedContexts @("Quality") `
            -ExpectedStrictRequiredChecks $false `
            -Rulesets $rulesets
        Assert-ProtectionRuleset `
            -Repository $repository `
            -Branch "develop" `
            -ExpectedMergeMethod "squash" `
            -ExpectedContexts @("Quality") `
            -ExpectedStrictRequiredChecks $true `
            -Rulesets $rulesets

        Write-Host "[OK] Repository rulesets"
    } catch {
        Write-Warning $_

        if ($NonInteractive) {
            throw
        }

        if (-not (Confirm-Action -Prompt "Ruleset configuration failed. Keep the repository without complete protection?")) {
            throw "Repository provisioning stopped because protection is incomplete."
        }

        $protectionComplete = $false
    }

    $status = Get-CommandOutput -FilePath git -Arguments @("status", "--porcelain") -WorkingDirectory $ProjectRoot

    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw "Generated repository is not clean after provisioning."
    }

    $currentBranch = Get-CommandOutput `
        -FilePath git `
        -Arguments @("branch", "--show-current") `
        -WorkingDirectory $ProjectRoot

    if ($currentBranch -ne "develop") {
        throw "Generated repository ended on '$currentBranch' instead of 'develop'."
    }

    return [PSCustomObject]@{
        Repository = $repository
        ProtectionComplete = $protectionComplete
    }
}

function Invoke-IbukiBootstrap {
    $releaseMetadata = Get-BootstrapReleaseMetadata
    $releaseMetadataDisplayed = $false
    $state.BootstrapperVersion = $releaseMetadata.Version

    if (
        [string]::IsNullOrWhiteSpace($BootstrapRoot) -and
        -not [string]::IsNullOrWhiteSpace($releaseMetadata.FullCommitId)
    ) {
        $state.BlueprintRevision = $releaseMetadata.FullCommitId
        $state.RawBaseUrl = (
            "https://raw.githubusercontent.com/" +
            "$($state.BootstrapperRepository)/$($state.BlueprintRevision)"
        )
    }

    if (-not $releaseMetadata.IsLocal) {
        Write-BootstrapReleaseMetadata -Metadata $releaseMetadata
        $releaseMetadataDisplayed = $true
    }

    if ($UseCurrentDirectory -and -not [string]::IsNullOrWhiteSpace($Destination)) {
        throw "Use either -UseCurrentDirectory or -Destination, not both."
    }

    Write-Phase -Name "Preflight"

    if ($PSVersionTable.PSVersion -lt [version]"7.6") {
        throw "PowerShell 7.6 or later is required. Found: $($PSVersionTable.PSVersion)"
    }

    Write-Host ""
    Write-Host "Detected environment:"
    Write-Host "  PowerShell : $($PSVersionTable.PSVersion)"

    Write-Phase -Name "Project"
    $configuration = Resolve-BootstrapConfiguration

    if ($null -eq $configuration) {
        Write-Host "Cancelled."
        return
    }

    Assert-BootstrapConfiguration -Configuration $configuration

    $localBlueprintRoot = ""
    $localBlueprintsRoot = ""
    $useLocalBlueprint = $false

    if (-not [string]::IsNullOrWhiteSpace($BootstrapRoot)) {
        $localBlueprintsRoot = Join-Path $BootstrapRoot "blueprints"
        $candidate = Join-Path $BootstrapRoot "blueprints/$($configuration.BlueprintId)"

        if (Test-LocalBlueprintAvailable -Root $BootstrapRoot -BlueprintId $configuration.BlueprintId) {
            $localBlueprintRoot = $candidate
            $useLocalBlueprint = $true
        }
    }

    if (-not $useLocalBlueprint) {
        if ($releaseMetadata.IsLocal) {
            $releaseMetadata = Get-RemoteReleaseMetadata
            $state.BootstrapperVersion = $releaseMetadata.Version
        }

        if ([string]::IsNullOrWhiteSpace($releaseMetadata.FullCommitId)) {
            $diagnostic = if ([string]::IsNullOrWhiteSpace($releaseMetadata.Diagnostic)) {
                ""
            } else {
                " $($releaseMetadata.Diagnostic)"
            }
            throw (
                "Unable to resolve an immutable Bootstrapper commit for Blueprint retrieval." +
                $diagnostic
            )
        }

        $state.BlueprintRevision = $releaseMetadata.FullCommitId
        $state.RawBaseUrl = (
            "https://raw.githubusercontent.com/" +
            "$($state.BootstrapperRepository)/$($state.BlueprintRevision)"
        )
    }

    if (-not $releaseMetadataDisplayed) {
        Write-BootstrapReleaseMetadata -Metadata $releaseMetadata
        $releaseMetadataDisplayed = $true
    }

    $manifest = Read-BlueprintManifest `
        -BlueprintId $configuration.BlueprintId `
        -LocalBlueprintRoot $localBlueprintRoot `
        -UseLocalBlueprint:$useLocalBlueprint

    Assert-BlueprintManifest `
        -Manifest $manifest `
        -BlueprintId $configuration.BlueprintId `
        -LocalBlueprintRoot $localBlueprintRoot `
        -UseLocalBlueprint:$useLocalBlueprint

    $resolvedFiles = Resolve-BlueprintFiles `
        -Manifest $manifest `
        -BlueprintId $configuration.BlueprintId `
        -LocalBlueprintRoot $localBlueprintRoot `
        -LocalBlueprintsRoot $localBlueprintsRoot `
        -UseLocalBlueprint:$useLocalBlueprint

    $blueprintSources = Read-BlueprintSources `
        -ResolvedFiles $resolvedFiles `
        -UseLocalBlueprint:$useLocalBlueprint

    if ($configuration.CreateGitHub) {
        Assert-Command -Name git
        Assert-Command -Name gh
        Invoke-CheckedCommand -FilePath gh -Arguments @(
            "auth",
            "status",
            "--active",
            "--hostname",
            "github.com"
        ) -WorkingDirectory (Get-Location).Path

        $owner = Get-CommandOutput -FilePath gh -Arguments @(
            "api",
            "user",
            "--jq",
            ".login"
        ) -WorkingDirectory (Get-Location).Path
        $configuration.GitHubOwner = $owner

        $gitUserName = Get-CommandOutput -FilePath git -Arguments @(
            "config",
            "user.name"
        ) -WorkingDirectory (Get-Location).Path
        $gitUserEmail = Get-CommandOutput -FilePath git -Arguments @(
            "config",
            "user.email"
        ) -WorkingDirectory (Get-Location).Path

        if ([string]::IsNullOrWhiteSpace($gitUserName) -or [string]::IsNullOrWhiteSpace($gitUserEmail)) {
            throw "Git user.name and user.email must be configured before GitHub provisioning."
        }

        & gh repo view "$owner/$($configuration.RepositoryName)" --json name 2>$null | Out-Null

        if ($LASTEXITCODE -eq 0) {
            throw "GitHub repository already exists: $owner/$($configuration.RepositoryName)"
        }
    }

    Show-BootstrapConfiguration `
        -Configuration $configuration `
        -Manifest $manifest

    if (-not (Confirm-Action -Prompt "Generate this project?")) {
        Write-Host "Cancelled."
        return
    }

    if (-not (Test-EmptyDirectory -Path $configuration.Destination)) {
        throw "Destination changed after confirmation and is no longer empty: $($configuration.Destination)"
    }

    $Blueprint = $configuration.BlueprintId
    $ProjectId = $configuration.ProjectId
    $DisplayName = $configuration.DisplayName
    $BasePackage = $configuration.BasePackage
    $Destination = $configuration.Destination
    $RepositoryName = $configuration.RepositoryName

    Write-Phase -Name "Generate"

    if (-not (Test-EmptyDirectory -Path $Destination)) {
        throw "Destination changed before generation and is no longer empty: $Destination"
    }

    $displayNameYaml = $DisplayName.Replace("\", "\\").Replace('"', '\"')
    $displayNameJson = $DisplayName | ConvertTo-Json -Compress
    $displayNameHtml = [System.Net.WebUtility]::HtmlEncode($DisplayName)
    $tokens = @{
        "__BOOTSTRAPPER_VERSION__" = $state.BootstrapperVersion
        "__PROJECT_ID__" = $ProjectId
        "__PROJECT_DISPLAY_NAME__" = $DisplayName
        "__PROJECT_DISPLAY_NAME_YAML__" = $displayNameYaml
        "__PROJECT_DISPLAY_NAME_JSON__" = $displayNameJson
        "__PROJECT_DISPLAY_NAME_HTML__" = $displayNameHtml
        "__BASE_PACKAGE__" = $configuration.BasePackage
        "__BASE_PACKAGE_PATH__" = $configuration.BasePackagePath
    }
    $preparedFiles = [System.Collections.Generic.List[object]]::new()
    $strictUtf8WithoutBom = [System.Text.UTF8Encoding]::new($false, $true)

    foreach ($resolvedFile in $resolvedFiles) {
        $file = $resolvedFile.File
        $sourceBytes = $blueprintSources[[string]$resolvedFile.SourceKey]
        $target = [string]$file.target

        if (
            @($file.PSObject.Properties.Name) -contains "targetTemplate" -and
            $file.targetTemplate
        ) {
            $target = Convert-TemplateContent -Content $target -Tokens $tokens
        }

        if ($file.kind -eq "binary") {
            $preparedFiles.Add([PSCustomObject]@{
                Kind = "binary"
                Target = $target
                Bytes = $sourceBytes
            })
        } else {
            $content = ConvertFrom-BlueprintTextBytes `
                -Bytes $sourceBytes `
                -Source $file.source

            if ($file.template) {
                $content = Convert-TemplateContent -Content $content -Tokens $tokens
            }

            $normalizedContent = $content -replace "`r`n", "`n"
            $renderedBytes = $strictUtf8WithoutBom.GetBytes($normalizedContent)
            $preparedFiles.Add([PSCustomObject]@{
                Kind = "text"
                Target = $target
                Bytes = $renderedBytes
            })
        }
    }

    Assert-PreparedTargetPaths `
        -DestinationRoot $Destination `
        -PreparedFiles $preparedFiles

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    foreach ($preparedFile in $preparedFiles) {
        if ($preparedFile.Kind -eq "binary") {
            Write-GeneratedBinaryFile `
                -DestinationRoot $Destination `
                -RelativePath $preparedFile.Target `
                -Bytes $preparedFile.Bytes
        } else {
            Write-GeneratedFile `
                -DestinationRoot $Destination `
                -RelativePath $preparedFile.Target `
                -Bytes $preparedFile.Bytes
        }
    }

    Write-Host "Generated $($state.CreatedFiles.Count) file(s)."

    $repository = ""
    $repositoryProtectionComplete = $true

    if ($configuration.CreateGitHub) {
        $provisioningResult = Invoke-GitHubProvisioning `
            -ProjectRoot $Destination `
            -Owner $configuration.GitHubOwner `
            -RepoName $RepositoryName `
            -Description $configuration.RepositoryDescription
        $repository = $provisioningResult.Repository
        $repositoryProtectionComplete = $provisioningResult.ProtectionComplete
    }

    Write-Phase -Name "Complete"

    if ($repositoryProtectionComplete) {
        Write-Host "Project created successfully." -ForegroundColor Green
    } else {
        Write-Host "Project created with warnings." -ForegroundColor Yellow
        Write-Warning "Repository protection is incomplete because one or more rulesets were not configured."
    }

    Write-Host "Location   : $Destination"
    $escapedDestination = $Destination.Replace("'", "''")
    Write-Host "Next       : Set-Location -LiteralPath '$escapedDestination'"
    Write-Host "Project-owned checks below were not run by Ibuki:"

    if (@($manifest.recommendedCommands).Count -eq 0) {
        Write-Host "  (none)"
    } else {
        foreach ($step in @($manifest.recommendedCommands)) {
            $workingDirectory = if ($step.workingDirectory -eq ".") {
                "."
            } else {
                $step.workingDirectory
            }
            Write-Host "  [$workingDirectory] $($step.command) $(@($step.arguments) -join ' ')"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($repository)) {
        Write-Host "Repository : https://github.com/$repository"
        Write-Host "Branch     : develop"

        if (-not $repositoryProtectionComplete) {
            Write-Host "Protection : INCOMPLETE" -ForegroundColor Yellow
        }
    }
}

try {
    Invoke-IbukiBootstrap
    $global:LASTEXITCODE = 0
} catch {
    Write-Host ""
    Write-Host "Ibuki Bootstrapper failed." -ForegroundColor Red
    Write-Host "Phase   : $($state.CurrentPhase)"
    Write-Host "Version : $($state.BootstrapperVersion)"
    Write-Host "Error   : $($_.Exception.Message)"

    if ($state.CreatedFiles.Count -gt 0) {
        Write-Host ""
        Write-Host "Created files were preserved:"

        foreach ($createdFile in $state.CreatedFiles) {
            Write-Host "  $createdFile"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($state.CreatedRepository)) {
        Write-Host ""
        Write-Host "Created GitHub repository was preserved:"
        Write-Host "  $($state.CreatedRepository)"
    }

    throw
}
} finally {
    [Console]::OutputEncoding = $previousConsoleOutputEncoding

    if ($IsInvokeExpression) {
        if ($lastExitCodeExisted) {
            Set-Variable -Name LASTEXITCODE -Scope Global -Value $previousLastExitCode
        } else {
            Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        }
    }
}
}

function ConvertTo-CoreParameterSplat {
    param(
        [object[]]$Arguments = @()
    )

    $definitions = @{
        "blueprint" = @{ Name = "Blueprint"; IsSwitch = $false }
        "projectid" = @{ Name = "ProjectId"; IsSwitch = $false }
        "displayname" = @{ Name = "DisplayName"; IsSwitch = $false }
        "basepackage" = @{ Name = "BasePackage"; IsSwitch = $false }
        "destination" = @{ Name = "Destination"; IsSwitch = $false }
        "repositoryname" = @{ Name = "RepositoryName"; IsSwitch = $false }
        "repositorydescription" = @{ Name = "RepositoryDescription"; IsSwitch = $false }
        "usecurrentdirectory" = @{ Name = "UseCurrentDirectory"; IsSwitch = $true }
        "skipgithub" = @{ Name = "SkipGitHub"; IsSwitch = $true }
        "noninteractive" = @{ Name = "NonInteractive"; IsSwitch = $true }
        "yes" = @{ Name = "Yes"; IsSwitch = $true }
    }
    $parameters = @{}

    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $token = [string]$Arguments[$index]
        $match = [regex]::Match($token, '^-([^:]+)(?::(.*))?$')

        if (-not $match.Success) {
            throw "Expected a named bootstrap parameter but found '$token'."
        }

        $lookupName = $match.Groups[1].Value.ToLowerInvariant()

        if (-not $definitions.ContainsKey($lookupName)) {
            throw "Unknown bootstrap parameter '$token'."
        }

        $definition = $definitions[$lookupName]
        $parameterName = $definition.Name

        if ($parameters.ContainsKey($parameterName)) {
            throw "Bootstrap parameter '-$parameterName' was specified more than once."
        }

        if ($definition.IsSwitch) {
            $switchValue = $true

            if ($match.Groups[2].Success) {
                $rawSwitchValue = $match.Groups[2].Value.ToLowerInvariant()

                $switchValue = switch ($rawSwitchValue) {
                    { $_ -in @('$true', 'true', '1') } { $true; break }
                    { $_ -in @('$false', 'false', '0') } { $false; break }
                    default {
                        throw "Bootstrap switch '-$parameterName' requires true or false."
                    }
                }
            }

            $parameters[$parameterName] = $switchValue
            continue
        }

        if ($match.Groups[2].Success) {
            $parameters[$parameterName] = $match.Groups[2].Value
            continue
        }

        $index++

        if ($index -ge $Arguments.Count) {
            throw "Bootstrap parameter '-$parameterName' requires a value."
        }

        $parameterValue = [string]$Arguments[$index]

        if ($parameterValue -match '^-([^:]+)(?::(.*))?$') {
            throw "Bootstrap parameter '-$parameterName' requires a value."
        }

        $parameters[$parameterName] = $parameterValue
    }

    return $parameters
}

$isPhysicalBootstrapFile = $false

if (
    -not [string]::IsNullOrWhiteSpace($InvocationPath) -and
    (Test-Path -LiteralPath $InvocationPath -PathType Leaf)
) {
    $entrypointMarker = [System.IO.File]::ReadLines($InvocationPath) |
        Select-Object -First 1
    $isPhysicalBootstrapFile = $entrypointMarker -eq "# IBUKI_BOOTSTRAPPER_ENTRYPOINT_V1"
}

$isInvokeExpression = -not $isPhysicalBootstrapFile
$effectiveBootstrapRoot = if ($isPhysicalBootstrapFile) {
    $BootstrapRoot
} else {
    ""
}
$BootstrapRoot = $effectiveBootstrapRoot

if ($isInvokeExpression) {
    & $core -IsInvokeExpression $true
} else {
    $fileArguments = @($RawArguments[0])
    $fileParameters = ConvertTo-CoreParameterSplat -Arguments $fileArguments
    & $core -IsInvokeExpression $false @fileParameters
}
} $PSScriptRoot $PSCommandPath (, $args)
