[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback,
        0
    )

    try {
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    } finally {
        $listener.Stop()
    }
}

function Get-ApplicationLogs {
    param(
        [Parameter(Mandatory)]
        [string]$StandardOutputPath,

        [Parameter(Mandatory)]
        [string]$StandardErrorPath
    )

    $standardOutput = if (Test-Path -LiteralPath $StandardOutputPath) {
        Get-Content -LiteralPath $StandardOutputPath -Raw
    } else {
        "<stdout unavailable>"
    }
    $standardError = if (Test-Path -LiteralPath $StandardErrorPath) {
        Get-Content -LiteralPath $StandardErrorPath -Raw
    } else {
        "<stderr unavailable>"
    }

    return "STDOUT:`n$standardOutput`nSTDERR:`n$standardError"
}

function ConvertTo-ResponseText {
    param(
        [Parameter(Mandatory)]
        [object]$Content
    )

    if ($Content -is [byte[]]) {
        return [System.Text.UTF8Encoding]::new($false, $true).GetString($Content)
    }

    return [string]$Content
}

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$port = Get-FreeTcpPort
$standardOutputPath = [System.IO.Path]::GetTempFileName()
$standardErrorPath = [System.IO.Path]::GetTempFileName()
$process = $null

try {
    & (Join-Path $repositoryRoot "gradlew.bat") bootJar

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to build the executable JAR."
    }

    $jars = @(
        Get-ChildItem -LiteralPath (Join-Path $repositoryRoot "build/libs") -Filter "*.jar" |
            Where-Object { $_.Name -notlike "*-plain.jar" }
    )

    if ($jars.Count -ne 1) {
        throw "Expected exactly one executable JAR, found $($jars.Count)."
    }

    $process = Start-Process `
        -FilePath "java" `
        -ArgumentList @(
            "-jar",
            "`"$($jars[0].FullName)`"",
            "--server.port=$port"
        ) `
        -WorkingDirectory $repositoryRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $standardOutputPath `
        -RedirectStandardError $standardErrorPath `
        -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    $healthResponse = $null

    while ([DateTime]::UtcNow -lt $deadline) {
        if ($process.HasExited) {
            $logs = Get-ApplicationLogs $standardOutputPath $standardErrorPath
            throw "The application exited before becoming ready.`n$logs"
        }

        try {
            $healthResponse = Invoke-WebRequest `
                "http://127.0.0.1:$port/internal/health" `
                -SkipHttpErrorCheck `
                -TimeoutSec 5
        } catch {
            Start-Sleep -Milliseconds 500
            continue
        }

        if ($healthResponse.StatusCode -ne 200) {
            $healthContent = ConvertTo-ResponseText $healthResponse.Content
            throw (
                "Health contract failed: expected HTTP 200, got " +
                "$($healthResponse.StatusCode). Body: $healthContent"
            )
        }

        $healthContent = ConvertTo-ResponseText $healthResponse.Content

        try {
            $health = $healthContent | ConvertFrom-Json
        } catch {
            throw "Health contract failed: response is not valid JSON. Body: $healthContent"
        }

        if ($health.status -ne "ok") {
            throw "Health contract failed: expected status 'ok'. Body: $healthContent"
        }

        break
    }

    if ($null -eq $healthResponse) {
        $logs = Get-ApplicationLogs $standardOutputPath $standardErrorPath
        throw "Timed out waiting for the health endpoint on port $port.`n$logs"
    }

    $notFoundResponse = Invoke-WebRequest `
        "http://127.0.0.1:$port/missing" `
        -SkipHttpErrorCheck `
        -TimeoutSec 5
    $notFoundContent = ConvertTo-ResponseText $notFoundResponse.Content
    $contentType = [string]$notFoundResponse.Headers["Content-Type"]

    if ($notFoundResponse.StatusCode -ne 404) {
        throw (
            "404 contract failed: expected HTTP 404, got " +
            "$($notFoundResponse.StatusCode). Body: $notFoundContent"
        )
    }

    if ($contentType -notmatch '^application/problem\+json(?:;|$)') {
        throw "404 contract failed: unexpected Content-Type '$contentType'."
    }

    try {
        $problem = $notFoundContent | ConvertFrom-Json
    } catch {
        throw "404 contract failed: response is not valid JSON. Body: $notFoundContent"
    }

    $problemErrors = @()

    if ($problem.type -ne "about:blank") {
        $problemErrors += "type='$($problem.type)'"
    }

    if ($problem.title -ne "Not Found") {
        $problemErrors += "title='$($problem.title)'"
    }

    if ($problem.status -ne 404) {
        $problemErrors += "status='$($problem.status)'"
    }

    if ($problem.instance -ne "/missing") {
        $problemErrors += "instance='$($problem.instance)'"
    }

    if ($problemErrors.Count -gt 0) {
        throw (
            "404 contract failed: " +
            ($problemErrors -join ", ") +
            ". Body: $notFoundContent"
        )
    }

    Write-Host "Smoke test passed on port $port."
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false

        try {
            & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
        } finally {
            $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
        }

        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }

        $process.WaitForExit()
    }

    Remove-Item -LiteralPath $standardOutputPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $standardErrorPath -Force -ErrorAction SilentlyContinue
}
