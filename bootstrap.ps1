[CmdletBinding()]
param(
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

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8WithoutBom
$OutputEncoding = $utf8WithoutBom
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:BootstrapperVersion = "0.1.3"
$script:BootstrapperRepository = "rukaruka966/ibuki-bootstrapper"
$script:RawBaseUrl = "https://raw.githubusercontent.com/$($script:BootstrapperRepository)/main"
$script:CreatedFiles = [System.Collections.Generic.List[string]]::new()
$script:CreatedRepository = ""
$script:CurrentPhase = "Start"

function Write-Phase {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $script:CurrentPhase = $Name
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
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $gitDirectory = Join-Path $PSScriptRoot ".git"

        if ((Test-Path -LiteralPath $gitDirectory) -and (Get-Command git -ErrorAction SilentlyContinue)) {
            $commit = & git -C $PSScriptRoot rev-parse --short=12 HEAD 2>$null

            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($commit -join ""))) {
                return ($commit -join "").Trim()
            }
        }
    }

    try {
        $commitInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$($script:BootstrapperRepository)/commits/main"
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
    return [string]::IsNullOrWhiteSpace($answer) -or $answer.Trim().ToLowerInvariant() -eq "y"
}

function Get-TemplateContent {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$LocalBlueprintRoot
    )

    $localPath = Join-Path $LocalBlueprintRoot ($Source -replace '/', [System.IO.Path]::DirectorySeparatorChar)

    if (Test-Path -LiteralPath $localPath) {
        return Get-Content -LiteralPath $localPath -Raw
    }

    $uri = "$($script:RawBaseUrl)/blueprints/web-hono/$Source"
    return (Invoke-WebRequest -Uri $uri -UseBasicParsing).Content
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

    if (Test-Path -LiteralPath $targetPath) {
        throw "Refusing to overwrite an existing path: $targetPath"
    }

    $parent = Split-Path -Parent $targetPath

    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $normalizedContent = $Content -replace "`r`n", "`n"
    Set-Content -LiteralPath $targetPath -Value $normalizedContent -Encoding utf8NoBOM -NoNewline
    $script:CreatedFiles.Add($targetPath)
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
    $script:CreatedRepository = "https://github.com/$repository"
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
    Write-Host "Release/Tag : v$($script:BootstrapperVersion)"
    Write-Host "Commit ID   : $sourceCommitId"
    Write-Host "Channel     : main"
    Write-Host "Source      : $($script:BootstrapperRepository)"
    Write-Host "------------------------------------------------------------"

    if ($UseCurrentDirectory -and -not [string]::IsNullOrWhiteSpace($Destination)) {
        throw "Use either -UseCurrentDirectory or -Destination, not both."
    }

    Write-Phase -Name "Preflight"
    Assert-Command -Name git
    Assert-Command -Name node
    Assert-Command -Name pnpm

    $nodeVersion = Get-CommandOutput -FilePath node -Arguments @("--version") -WorkingDirectory (Get-Location).Path
    $nodeMajor = [int](($nodeVersion.TrimStart("v") -split "\.")[0])

    if ($nodeMajor -lt 24) {
        throw "Node.js 24 or later is required. Found: $nodeVersion"
    }

    $owner = ""

    if (-not $SkipGitHub) {
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
    }

    Write-Phase -Name "Project"

    if ([string]::IsNullOrWhiteSpace($ProjectId)) {
        if ($NonInteractive) {
            throw "-ProjectId is required in non-interactive mode."
        }

        $ProjectId = Read-Host "Project ID (lowercase kebab-case)"
    }

    Assert-ProjectId -Value $ProjectId -Label "Project ID"

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        if ($NonInteractive) {
            $DisplayName = $ProjectId
        } else {
            $DisplayName = Read-Host "Display name [$ProjectId]"

            if ([string]::IsNullOrWhiteSpace($DisplayName)) {
                $DisplayName = $ProjectId
            }
        }
    }

    if ($DisplayName -match "[`r`n]") {
        throw "Display name cannot contain newlines."
    }

    if ($UseCurrentDirectory) {
        $Destination = (Get-Location).Path
    } elseif ([string]::IsNullOrWhiteSpace($Destination)) {
        if ($NonInteractive) {
            throw "-Destination or -UseCurrentDirectory is required in non-interactive mode."
        }

        $locationChoice = Read-Host "Destination: [1] new '$ProjectId' folder, [2] current empty folder [default: 1]"

        if ($locationChoice -eq "2") {
            $Destination = (Get-Location).Path
        } else {
            $Destination = Join-Path (Get-Location).Path $ProjectId
        }
    }

    $Destination = [System.IO.Path]::GetFullPath($Destination)

    if (-not (Test-EmptyDirectory -Path $Destination)) {
        throw "Destination must be an empty directory: $Destination"
    }

    if ([string]::IsNullOrWhiteSpace($RepositoryName)) {
        $RepositoryName = $ProjectId
    }

    Assert-ProjectId -Value $RepositoryName -Label "Repository name"

    if (-not $SkipGitHub) {
        & gh repo view "$owner/$RepositoryName" --json name 2>$null | Out-Null

        if ($LASTEXITCODE -eq 0) {
            throw "GitHub repository already exists: $owner/$RepositoryName"
        }
    }

    Write-Host ""
    Write-Host "Project ID        : $ProjectId"
    Write-Host "Display name      : $DisplayName"
    Write-Host "Destination       : $Destination"
    Write-Host "Blueprint         : web-hono"

    if ($SkipGitHub) {
        Write-Host "GitHub            : skipped"
    } else {
        Write-Host "GitHub account    : $owner"
        Write-Host "GitHub repository : $owner/$RepositoryName (private)"
        Write-Host "Branches          : main, develop"
    }

    if (-not (Confirm-Action -Prompt "Generate this project?")) {
        Write-Host "Cancelled."
        return
    }

    Write-Phase -Name "Generate"

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $localBlueprintRoot = ""

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $candidate = Join-Path $PSScriptRoot "blueprints/web-hono"

        if (Test-Path -LiteralPath $candidate) {
            $localBlueprintRoot = $candidate
        }
    }

    if ([string]::IsNullOrWhiteSpace($localBlueprintRoot)) {
        $manifest = Invoke-RestMethod -Uri "$($script:RawBaseUrl)/blueprints/web-hono/manifest.json"
        $localBlueprintRoot = Join-Path $Destination ".ibuki-remote-source"
    } else {
        $manifestPath = Join-Path $localBlueprintRoot "manifest.json"
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }

    $displayNameYaml = $DisplayName.Replace("\", "\\").Replace('"', '\"')
    $displayNameJson = $DisplayName | ConvertTo-Json -Compress
    $displayNameHtml = [System.Net.WebUtility]::HtmlEncode($DisplayName)
    $tokens = @{
        "__BOOTSTRAPPER_VERSION__" = $script:BootstrapperVersion
        "__PROJECT_ID__" = $ProjectId
        "__PROJECT_DISPLAY_NAME__" = $DisplayName
        "__PROJECT_DISPLAY_NAME_YAML__" = $displayNameYaml
        "__PROJECT_DISPLAY_NAME_JSON__" = $displayNameJson
        "__PROJECT_DISPLAY_NAME_HTML__" = $displayNameHtml
    }

    foreach ($file in $manifest.files) {
        $content = Get-TemplateContent -Source $file.source -LocalBlueprintRoot $localBlueprintRoot

        if ($file.template) {
            $content = Convert-TemplateContent -Content $content -Tokens $tokens
        }

        Write-GeneratedFile `
            -DestinationRoot $Destination `
            -RelativePath $file.target `
            -Content $content
    }

    Write-Host "Generated $($script:CreatedFiles.Count) file(s)."

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

    if (-not $SkipGitHub) {
        $provisioningResult = Invoke-GitHubProvisioning `
            -ProjectRoot $Destination `
            -Owner $owner `
            -RepoName $RepositoryName `
            -Description $RepositoryDescription
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
    Write-Host "Phase   : $($script:CurrentPhase)"
    Write-Host "Version : $($script:BootstrapperVersion)"
    Write-Host "Error   : $($_.Exception.Message)"

    if ($script:CreatedFiles.Count -gt 0) {
        Write-Host ""
        Write-Host "Created files were preserved:"

        foreach ($createdFile in $script:CreatedFiles) {
            Write-Host "  $createdFile"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:CreatedRepository)) {
        Write-Host ""
        Write-Host "Created GitHub repository was preserved:"
        Write-Host "  $($script:CreatedRepository)"
    }

    throw
}
