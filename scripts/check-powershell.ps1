[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$scripts = @(
    (Join-Path $repositoryRoot "bootstrap.ps1"),
    (Join-Path $PSScriptRoot "check-powershell.ps1"),
    (Join-Path $PSScriptRoot "test-generated-project.ps1"),
    (Join-Path $repositoryRoot "blueprints/web-hono/template/scripts/doctor.ps1.tpl")
)

$failed = $false

foreach ($scriptPath in $scripts) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null

    if ($errors.Count -gt 0) {
        $failed = $true
        Write-Error "PowerShell parsing failed for $scriptPath"

        foreach ($parseError in $errors) {
            Write-Error "$($parseError.Extent.StartLineNumber): $($parseError.Message)"
        }
    } else {
        Write-Host "[OK] $scriptPath"
    }
}

if ($failed) {
    throw "PowerShell syntax validation failed."
}
