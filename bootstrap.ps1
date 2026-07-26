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
    CreatedFiles = [System.Collections.Generic.List[string]]::new()
    CreatedRepository = ""
    CurrentPhase = "Start"
    CancelRequested = $false
    MaximumDestinationLength = 96
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
}

function Get-SourceCommitId {
    if (-not [string]::IsNullOrWhiteSpace($BootstrapRoot)) {
        $gitDirectory = Join-Path $BootstrapRoot ".git"

        if ((Test-Path -LiteralPath $gitDirectory) -and (Get-Command git -ErrorAction SilentlyContinue)) {
            $commit = & git -C $BootstrapRoot rev-parse --short=12 HEAD 2>$null

            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($commit -join ""))) {
                return ($commit -join "").Trim()
            }
        }
    }

    try {
        $commitInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$($state.BootstrapperRepository)/commits/main"
        return ([string]$commitInfo.sha).Substring(0, 12)
    } catch {
        return "unavailable"
    }
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
        Write-Host "  [3] Web API: Spring Boot (Coming soon)"
        Write-Host "  [4] Android: Jetpack Compose (Coming soon)"
        Write-Host "  [5] Windows Desktop: Compose Multiplatform (Coming soon)"
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
                Write-Warning "Web API: Spring Boot is Coming soon. Select an available configuration."
                continue
            }
            "4" {
                Write-Warning "Android: Jetpack Compose is Coming soon. Select an available configuration."
                continue
            }
            "5" {
                Write-Warning "Windows Desktop: Compose Multiplatform is Coming soon. Select an available configuration."
                continue
            }
            { $_ -eq "0" -or $_.Trim().ToLowerInvariant() -eq "q" } {
                return $null
            }
            default {
                Write-Warning "Unknown selection '$selection'. Enter 0, 1, 2, 3, 4, or 5."
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

    if ($Configuration.BlueprintId -ne "web-hono") {
        throw "Blueprint '$($Configuration.BlueprintId)' is not available. Available blueprint: web-hono."
    }

    Assert-ProjectId -Value $Configuration.ProjectId -Label "Project ID"
    Assert-ProjectId -Value $Configuration.RepositoryName -Label "Repository name"

    if ($Configuration.DisplayName -match "[`r`n]") {
        throw "Display name cannot contain newlines."
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
        [PSCustomObject]$Configuration
    )

    Write-Phase -Name "Confirmation"
    Write-Host "Blueprint ID      : $($Configuration.BlueprintId)"
    Write-Host "Project ID        : $($Configuration.ProjectId)"
    Write-Host "Display name      : $($Configuration.DisplayName)"
    Write-Host "Destination       : $($Configuration.Destination)"

    if ($Configuration.CreateGitHub) {
        Write-Host "GitHub repository : $($Configuration.GitHubOwner)/$($Configuration.RepositoryName) (private)"
        Write-Host "Branches          : main, develop"
    } else {
        Write-Host "GitHub            : skipped"
        Write-Host "Branches          : none (local generation only)"
    }

    Write-Host "Local verification:"
    Write-Host "  pnpm install"
    Write-Host "  pnpm run lint"
    Write-Host "  pnpm run test"
    Write-Host "  pnpm run typecheck"
    Write-Host "  pnpm run build"
    Write-Host "  pnpm run smoke"
    Write-Host "  pnpm run doctor"
}

function Get-TemplateContent {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [string]$LocalBlueprintRoot = "",

        [Parameter(Mandatory)]
        [string]$BlueprintId,

        [switch]$UseLocalBlueprint
    )

    if ($UseLocalBlueprint) {
        $localPath = Join-Path $LocalBlueprintRoot (
            $Source -replace '/', [System.IO.Path]::DirectorySeparatorChar
        )

        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            throw "Local blueprint '$BlueprintId' is missing its manifest source: $Source"
        }

        return Get-Content -LiteralPath $localPath -Raw
    }

    $uri = "$($state.RawBaseUrl)/blueprints/$BlueprintId/$Source"
    return (Invoke-WebRequest -Uri $uri -UseBasicParsing).Content
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

    if ($Manifest.id -ne $BlueprintId) {
        throw "Blueprint manifest ID '$($Manifest.id)' does not match '$BlueprintId'."
    }

    if (@($Manifest.files).Count -eq 0) {
        throw "Blueprint manifest '$BlueprintId' does not contain any files."
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

        foreach ($requiredProperty in @("source", "target", "template")) {
            if ($propertyNames -notcontains $requiredProperty) {
                throw "Blueprint manifest '$BlueprintId' contains an entry without '$requiredProperty'."
            }
        }

        if ($file.source -isnot [string] -or $file.target -isnot [string]) {
            throw "Blueprint manifest '$BlueprintId' source and target values must be strings."
        }

        if (
            [string]::IsNullOrWhiteSpace($file.source) -or
            [System.IO.Path]::IsPathRooted($file.source) -or
            @($file.source -split '[\\/]').Contains("..")
        ) {
            throw "Blueprint manifest '$BlueprintId' contains an unsafe source path: '$($file.source)'."
        }

        if (
            [string]::IsNullOrWhiteSpace($file.target) -or
            [System.IO.Path]::IsPathRooted($file.target) -or
            @($file.target -split '[\\/]').Contains("..")
        ) {
            throw "Blueprint manifest '$BlueprintId' contains an unsafe target path: '$($file.target)'."
        }

        $canonicalTarget = [System.IO.Path]::GetFullPath(
            (Join-Path $validationRoot $file.target)
        )

        if (-not $canonicalTarget.StartsWith(
            $validationPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Blueprint manifest '$BlueprintId' contains an unsafe target path: '$($file.target)'."
        }

        if (-not $targets.Add($canonicalTarget)) {
            throw "Blueprint manifest '$BlueprintId' contains a duplicate target: '$($file.target)'."
        }

        if ($file.template -isnot [bool]) {
            throw "Blueprint manifest '$BlueprintId' has a non-boolean template flag for '$($file.target)'."
        }

        if ($UseLocalBlueprint) {
            $localSource = Join-Path $LocalBlueprintRoot (
                $file.source -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )

            if (-not (Test-Path -LiteralPath $localSource -PathType Leaf)) {
                throw "Local blueprint '$BlueprintId' is missing its manifest source: $($file.source)"
            }
        }
    }
}

function Convert-TemplateContent {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [hashtable]$Tokens
    )

    $result = $Content

    foreach ($entry in $Tokens.GetEnumerator()) {
        $result = $result.Replace($entry.Key, [string]$entry.Value)
    }

    if ($result -match '__[A-Z0-9_]+__') {
        throw "Generated content contains an unresolved template token: $($Matches[0])"
    }

    return $result
}

function Write-GeneratedFile {
    param(
        [Parameter(Mandatory)]
        [string]$DestinationRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string]$Content
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

    $normalizedContent = $Content -replace "`r`n", "`n"
    $stream = $null
    $writer = $null

    try {
        $stream = [System.IO.File]::Open(
            $targetPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $writer = [System.IO.StreamWriter]::new(
            $stream,
            [System.Text.UTF8Encoding]::new($false)
        )
        $writer.Write($normalizedContent)
    } catch [System.IO.IOException] {
        throw "Refusing to overwrite or race with an existing path: $targetPath"
    } finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        } elseif ($null -ne $stream) {
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

function Wait-ForQualityWorkflow {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Branch,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory
    )

    Write-Host "Waiting for the first Quality workflow on '$Branch'..."

    for ($attempt = 0; $attempt -lt 60; $attempt += 1) {
        $json = & gh run list `
            --repo $Repository `
            --branch $Branch `
            --workflow ci.yml `
            --limit 1 `
            --json status,conclusion,databaseId

        if ($LASTEXITCODE -ne 0) {
            throw "Unable to inspect GitHub Actions runs."
        }

        if (-not [string]::IsNullOrWhiteSpace(($json -join ""))) {
            $runs = @(($json -join "`n") | ConvertFrom-Json)

            if ($runs.Count -gt 0) {
                $run = $runs[0]

                if ($run.status -eq "completed") {
                    if ($run.conclusion -ne "success") {
                        throw "Initial GitHub Actions run concluded with '$($run.conclusion)'."
                    }

                    Write-Host "[OK] GitHub Actions Quality workflow"
                    return
                }
            }
        }

        Start-Sleep -Seconds 5
    }

    throw "Timed out waiting for the initial GitHub Actions run."
}

function New-ProtectionRuleset {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Branch
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
                    allowed_merge_methods = @("squash")
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
                    required_status_checks = @(
                        @{
                            context = "Quality"
                        }
                    )
                    strict_required_status_checks_policy = $true
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

    if ($details.enforcement -ne "active") {
        throw "Ruleset verification failed: '$expectedName' is not active."
    }

    if ($includedRefs -notcontains "refs/heads/$Branch") {
        throw "Ruleset verification failed: '$expectedName' does not target '$Branch'."
    }

    $rules = @($details.rules)
    $ruleTypes = @($rules | ForEach-Object { $_.type })

    foreach ($requiredType in @("deletion", "non_fast_forward", "pull_request", "required_status_checks")) {
        if ($ruleTypes -notcontains $requiredType) {
            throw "Ruleset verification failed: '$expectedName' is missing '$requiredType'."
        }
    }

    $pullRequestRule = @($rules | Where-Object { $_.type -eq "pull_request" })[0]

    if (-not $pullRequestRule.parameters.required_review_thread_resolution) {
        throw "Ruleset verification failed: '$expectedName' does not require resolved review threads."
    }

    if ([int]$pullRequestRule.parameters.required_approving_review_count -ne 0) {
        throw "Ruleset verification failed: '$expectedName' requires an unexpected approval count."
    }

    $allowedMergeMethods = @($pullRequestRule.parameters.allowed_merge_methods)

    if ($allowedMergeMethods.Count -ne 1 -or $allowedMergeMethods -notcontains "squash") {
        throw "Ruleset verification failed: '$expectedName' does not allow only squash merges."
    }

    $statusRule = @($rules | Where-Object { $_.type -eq "required_status_checks" })[0]
    $requiredContexts = @($statusRule.parameters.required_status_checks | ForEach-Object { $_.context })

    if ($requiredContexts -notcontains "Quality") {
        throw "Ruleset verification failed: '$expectedName' does not require the Quality status check."
    }

    if (-not $statusRule.parameters.strict_required_status_checks_policy) {
        throw "Ruleset verification failed: '$expectedName' does not require an up-to-date branch."
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
    Invoke-CheckedCommand -FilePath git -Arguments @(
        "commit",
        "-m",
        "feat: generate initial project scaffold",
        "-m",
        "Add the React frontend, Hono backend, CI, and project configuration."
    ) -WorkingDirectory $ProjectRoot

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
    Wait-ForQualityWorkflow -Repository $repository -Branch "main" -WorkingDirectory $ProjectRoot

    Invoke-CheckedCommand -FilePath git -Arguments @("switch", "-c", "develop") -WorkingDirectory $ProjectRoot
    Invoke-CheckedCommand -FilePath git -Arguments @("push", "-u", "origin", "develop") -WorkingDirectory $ProjectRoot

    & gh api `
        --method PATCH `
        "repos/$repository" `
        -F "default_branch=main" `
        -F "has_issues=true" `
        -F "has_wiki=false" `
        -F "allow_squash_merge=true" `
        -F "allow_merge_commit=false" `
        -F "allow_rebase_merge=false" `
        -F "delete_branch_on_merge=true" `
        --silent

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to configure repository merge settings."
    }

    $protectionComplete = $true

    try {
        New-ProtectionRuleset -Repository $repository -Branch "main"
        New-ProtectionRuleset -Repository $repository -Branch "develop"

        $rulesetsJson = & gh api `
            "repos/$repository/rulesets" `
            -H "Accept: application/vnd.github+json" `
            -H "X-GitHub-Api-Version: 2026-03-10"

        if ($LASTEXITCODE -ne 0) {
            throw "Unable to verify repository rulesets."
        }

        $rulesets = @(($rulesetsJson -join "`n") | ConvertFrom-Json)

        foreach ($branch in @("main", "develop")) {
            Assert-ProtectionRuleset -Repository $repository -Branch $branch -Rulesets $rulesets
        }

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
    $sourceCommitId = Get-SourceCommitId

    Write-Host "------------------------------------------------------------"
    Write-Host "Ibuki Bootstrapper"
    Write-Host ""
    Write-Host "Release/Tag : v$($state.BootstrapperVersion)"
    Write-Host "Commit ID   : $sourceCommitId"
    Write-Host "Channel     : main"
    Write-Host "Source      : $($state.BootstrapperRepository)"
    Write-Host "------------------------------------------------------------"

    if ($UseCurrentDirectory -and -not [string]::IsNullOrWhiteSpace($Destination)) {
        throw "Use either -UseCurrentDirectory or -Destination, not both."
    }

    Write-Phase -Name "Preflight"

    if ($PSVersionTable.PSVersion -lt [version]"7.6") {
        throw "PowerShell 7.6 or later is required. Found: $($PSVersionTable.PSVersion)"
    }

    Assert-Command -Name git
    Assert-Command -Name node
    Assert-Command -Name pnpm

    $nodeVersion = Get-CommandOutput -FilePath node -Arguments @("--version") -WorkingDirectory (Get-Location).Path
    $pnpmVersion = Get-CommandOutput -FilePath pnpm -Arguments @("--version") -WorkingDirectory (Get-Location).Path
    $gitVersion = Get-CommandOutput -FilePath git -Arguments @("--version") -WorkingDirectory (Get-Location).Path
    $nodeMajor = [int](($nodeVersion.TrimStart("v") -split "\.")[0])
    $pnpmMajor = [int](($pnpmVersion -split "\.")[0])

    if ($nodeMajor -lt 24) {
        throw "Node.js 24 or later is required. Found: $nodeVersion"
    }

    if ($pnpmMajor -lt 11) {
        throw "pnpm 11 or later is required. Found: $pnpmVersion"
    }

    Write-Host ""
    Write-Host "Detected environment:"
    Write-Host "  PowerShell : $($PSVersionTable.PSVersion)"
    Write-Host "  Node.js    : $nodeVersion"
    Write-Host "  pnpm       : $pnpmVersion"
    Write-Host "  Git        : $gitVersion"

    Write-Phase -Name "Project"
    $configuration = Resolve-BootstrapConfiguration

    if ($null -eq $configuration) {
        Write-Host "Cancelled."
        return
    }

    Assert-BootstrapConfiguration -Configuration $configuration

    if ($configuration.CreateGitHub) {
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

    Show-BootstrapConfiguration -Configuration $configuration

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
    $Destination = $configuration.Destination
    $RepositoryName = $configuration.RepositoryName

    Write-Phase -Name "Generate"

    $localBlueprintRoot = ""
    $useLocalBlueprint = $false

    if (-not [string]::IsNullOrWhiteSpace($BootstrapRoot)) {
        $candidate = Join-Path $BootstrapRoot "blueprints/$Blueprint"

        if (Test-Path -LiteralPath $candidate) {
            $localBlueprintRoot = $candidate
            $useLocalBlueprint = $true
        }
    }

    if ([string]::IsNullOrWhiteSpace($localBlueprintRoot)) {
        $manifest = Invoke-RestMethod -Uri "$($state.RawBaseUrl)/blueprints/$Blueprint/manifest.json"
    } else {
        $manifestPath = Join-Path $localBlueprintRoot "manifest.json"
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }

    Assert-BlueprintManifest `
        -Manifest $manifest `
        -BlueprintId $Blueprint `
        -LocalBlueprintRoot $localBlueprintRoot `
        -UseLocalBlueprint:$useLocalBlueprint

    if (-not (Test-EmptyDirectory -Path $Destination)) {
        throw "Destination changed before generation and is no longer empty: $Destination"
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
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
    }

    foreach ($file in $manifest.files) {
        $content = Get-TemplateContent `
            -Source $file.source `
            -LocalBlueprintRoot $localBlueprintRoot `
            -BlueprintId $Blueprint `
            -UseLocalBlueprint:$useLocalBlueprint

        if ($file.template) {
            $content = Convert-TemplateContent -Content $content -Tokens $tokens
        }

        Write-GeneratedFile `
            -DestinationRoot $Destination `
            -RelativePath $file.target `
            -Content $content
    }

    Write-Host "Generated $($state.CreatedFiles.Count) file(s)."

    Write-Phase -Name "Verify"
    Invoke-CheckedCommand -FilePath pnpm -Arguments @("install") -WorkingDirectory $Destination
    Invoke-CheckedCommand -FilePath pnpm -Arguments @("run", "lint") -WorkingDirectory $Destination
    Invoke-CheckedCommand -FilePath pnpm -Arguments @("run", "test") -WorkingDirectory $Destination
    Invoke-CheckedCommand -FilePath pnpm -Arguments @("run", "typecheck") -WorkingDirectory $Destination
    Invoke-CheckedCommand -FilePath pnpm -Arguments @("run", "build") -WorkingDirectory $Destination
    Invoke-CheckedCommand -FilePath pnpm -Arguments @("run", "smoke") -WorkingDirectory $Destination
    Invoke-CheckedCommand -FilePath pnpm -Arguments @("run", "doctor") -WorkingDirectory $Destination

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
