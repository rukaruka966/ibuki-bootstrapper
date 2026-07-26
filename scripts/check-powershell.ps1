[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$scripts = @(
    (Join-Path $repositoryRoot "bootstrap.ps1")
    Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.ps1" -File
    Get-ChildItem `
        -LiteralPath (Join-Path $repositoryRoot "blueprints") `
        -Recurse `
        -Filter "*.ps1.tpl" `
        -File
) | ForEach-Object {
    if ($_ -is [System.IO.FileInfo]) {
        $_.FullName
    } else {
        [string]$_
    }
} | Sort-Object -Unique

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
