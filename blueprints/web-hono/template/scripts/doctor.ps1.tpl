[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()

function Test-CommandAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$Optional
    )

    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        Write-Host "[OK] $Name"
        return
    }

    if ($Optional) {
        Write-Warning "$Name is not installed. GitHub automation will be unavailable."
        return
    }

    Write-Host "[MISSING] $Name" -ForegroundColor Red
    $failures.Add($Name)
}

Write-Host "Project environment doctor"
Write-Host ""

Test-CommandAvailable -Name node
Test-CommandAvailable -Name pnpm
Test-CommandAvailable -Name git
Test-CommandAvailable -Name gh -Optional

$requiredPaths = @(
    "systems/web-frontend/package.json",
    "systems/api-bff/package.json",
    "project.config.yaml",
    "pnpm-lock.yaml"
)

foreach ($requiredPath in $requiredPaths) {
    if (Test-Path -LiteralPath $requiredPath) {
        Write-Host "[OK] $requiredPath"
    } else {
        Write-Host "[MISSING] $requiredPath" -ForegroundColor Red
        $failures.Add($requiredPath)
    }
}

if ($failures.Count -gt 0) {
    throw "Doctor found $($failures.Count) required item(s) missing."
}

Write-Host ""
Write-Host "Environment is ready." -ForegroundColor Green
