<#
.SYNOPSIS
Installs or updates Bun (JavaScript runtime) using winget.

.DESCRIPTION
Bun is required by some Claude Code plugins — notably claude-mem, whose MCP
server (mcp-search) is wired with `"command": "bun"` in its .mcp.json. Without
Bun on PATH, those plugins' MCP servers fail to start (visible in Claude Code
as `plugin:<plugin>:<mcp-name> not working`).

This script:
  1. Checks if bun is on PATH and reports the current version.
  2. Uses winget to install or update Bun (Oven-sh.Bun) to the latest version.
  3. Falls back to Oven-sh.Bun.Baseline on CPUs without AVX2.
  4. Reports whether Bun was freshly installed (PATH restart needed) or updated.

Requires winget to be installed first (see install-winget.ps1).

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-bun.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BunVersion {
    try {
        $output = (bun --version 2>&1) | Out-String
        if ($output -match '(\d+\.\d+\.\d+)') {
            return $Matches[1]
        }
    }
    catch { }
    return $null
}

function Test-WinGetAvailable {
    try {
        $null = winget --version 2>$null
        return $true
    }
    catch {
        return $false
    }
}

function Get-WinGetAvailableVersion {
    param([string]$PackageId)
    try {
        $output = winget show --id $PackageId --source winget --accept-source-agreements 2>&1 | Out-String
        if ($output -match 'Version\s*:\s*(\S+)') {
            return $Matches[1]
        }
    }
    catch { }
    return $null
}

# --- Main ---
Write-Host 'Bun runtime setup' -ForegroundColor Cyan
Write-Host ''

if (-not (Test-WinGetAvailable)) {
    throw 'WinGet is not available. Please run install-winget.ps1 first.'
}

$currentVersion = Get-BunVersion
$freshInstall = $false
$packageId = 'Oven-sh.Bun'

if ($currentVersion) {
    Write-Host "Bun is installed: v$currentVersion" -ForegroundColor Green
    Write-Host 'Checking for updates via winget...' -ForegroundColor Gray

    $availableVersion = Get-WinGetAvailableVersion -PackageId $packageId
    if ($availableVersion) {
        Write-Host "Latest available version: v$availableVersion" -ForegroundColor Gray
    }

    $upgradeOutput = winget upgrade --id $packageId --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
}
else {
    Write-Host 'Bun is not installed.' -ForegroundColor Yellow
    Write-Host 'Installing via winget...' -ForegroundColor Cyan
    $freshInstall = $true

    $upgradeOutput = winget install --id $packageId --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    # Bun requires AVX2 — fall back to baseline build if the standard install fails on CPU support.
    if ($exitCode -ne 0 -and ($upgradeOutput -match 'AVX2|illegal instruction|cannot execute' -or $upgradeOutput -match 'Hash mismatch')) {
        Write-Host '' -ForegroundColor Yellow
        Write-Host 'Standard Bun build failed (likely no AVX2 on this CPU). Trying baseline build...' -ForegroundColor Yellow
        $packageId = 'Oven-sh.Bun.Baseline'
        $upgradeOutput = winget install --id $packageId --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
}

$newVersion = Get-BunVersion

if ($freshInstall) {
    if ($newVersion) {
        Write-Host "Bun installed: v$newVersion ($packageId)" -ForegroundColor Green
        Write-Host ''
        Write-Host 'NOTE: Bun was freshly installed. Close and reopen all VS Code instances and Claude Code sessions for PATH to take effect.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Bun was installed but is not yet on PATH.' -ForegroundColor Yellow
        Write-Host 'Please close and reopen all VS Code instances so the PATH update takes effect.' -ForegroundColor Yellow
    }
}
elseif ($newVersion -and $newVersion -ne $currentVersion) {
    Write-Host "Bun updated: v$currentVersion -> v$newVersion" -ForegroundColor Green
}
elseif ($upgradeOutput -match 'No available upgrade' -or $upgradeOutput -match 'No newer package versions') {
    Write-Host 'Bun is already up-to-date.' -ForegroundColor Green
}
elseif ($exitCode -ne 0) {
    Write-Host "WARNING: winget exited with code $exitCode. Upgrade may have failed." -ForegroundColor Yellow
    Write-Host $upgradeOutput -ForegroundColor Gray
}
else {
    Write-Host 'Bun is already up-to-date.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan
