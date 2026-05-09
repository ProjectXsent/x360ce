<#
.SYNOPSIS
Installs or updates Git for Windows using winget.

.DESCRIPTION
This script:
  1. Checks if git.exe is on PATH and reports the current version.
  2. Uses winget to install or update Git for Windows (Git.Git) to the latest version.
  3. Reports whether Git was freshly installed (PATH restart needed) or updated.
  4. Detects and reports upgrade failures (technology mismatch, etc.).

Requires winget to be installed first (see install-winget.ps1).

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-git.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GitVersion {
    try {
        $output = (git --version 2>&1) | Out-String
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
Write-Host 'Git for Windows setup' -ForegroundColor Cyan
Write-Host ''

if (-not (Test-WinGetAvailable)) {
    throw 'WinGet is not available. Please run install-winget.ps1 first.'
}

$currentVersion = Get-GitVersion
$freshInstall = $false

if ($currentVersion) {
    Write-Host "Git is installed: v$currentVersion" -ForegroundColor Green
    Write-Host 'Checking for updates via winget...' -ForegroundColor Gray

    $availableVersion = Get-WinGetAvailableVersion -PackageId 'Git.Git'
    if ($availableVersion) {
        Write-Host "Latest available version: v$availableVersion" -ForegroundColor Gray
    }

    # Use winget upgrade for existing installs
    $upgradeOutput = winget upgrade --id Git.Git --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
}
else {
    Write-Host 'Git is not installed.' -ForegroundColor Yellow
    Write-Host 'Installing via winget...' -ForegroundColor Cyan
    $freshInstall = $true

    $upgradeOutput = winget install --id Git.Git --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
}

$newVersion = Get-GitVersion

if ($freshInstall) {
    if ($newVersion) {
        Write-Host "Git installed: v$newVersion" -ForegroundColor Green
        Write-Host ''
        Write-Host 'NOTE: Git was freshly installed. Close and reopen all VS Code instances for PATH to take effect.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Git was installed but is not yet on PATH.' -ForegroundColor Yellow
        Write-Host 'Please close and reopen all VS Code instances so the PATH update takes effect.' -ForegroundColor Yellow
    }
}
elseif ($upgradeOutput -match 'install technology is different') {
    Write-Host '' -ForegroundColor Yellow
    Write-Host 'WARNING: A newer version exists but uses a different install technology (e.g. MSI vs MSIX).' -ForegroundColor Yellow
    Write-Host 'This causes version inconsistencies between terminals. Fixing by uninstalling and reinstalling...' -ForegroundColor Yellow
    Write-Host ''

    Write-Host 'Uninstalling current version...' -ForegroundColor Cyan
    $uninstallOutput = winget uninstall --id Git.Git --silent 2>&1 | Out-String
    $uninstallExit = $LASTEXITCODE

    if ($uninstallExit -ne 0) {
        Write-Host "WARNING: Uninstall exited with code $uninstallExit. Manual intervention may be needed." -ForegroundColor Yellow
        Write-Host $uninstallOutput -ForegroundColor Gray
    }
    else {
        Write-Host 'Installing latest version...' -ForegroundColor Cyan
        $reinstallOutput = winget install --id Git.Git --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
        $reinstallExit = $LASTEXITCODE

        $newVersion = Get-GitVersion
        if ($newVersion -and $newVersion -ne $currentVersion) {
            Write-Host "Git upgraded: v$currentVersion -> v$newVersion" -ForegroundColor Green
            Write-Host ''
            Write-Host 'NOTE: Close and reopen all VS Code instances for PATH to take effect.' -ForegroundColor Yellow
        }
        elseif ($reinstallExit -ne 0) {
            Write-Host "WARNING: Reinstall exited with code $reinstallExit." -ForegroundColor Yellow
            Write-Host $reinstallOutput -ForegroundColor Gray
        }
        else {
            Write-Host 'Reinstall completed. Close and reopen all VS Code instances for changes to take effect.' -ForegroundColor Yellow
        }
    }
}
elseif ($newVersion -and $newVersion -ne $currentVersion) {
    Write-Host "Git updated: v$currentVersion -> v$newVersion" -ForegroundColor Green
}
elseif ($upgradeOutput -match 'No available upgrade' -or $upgradeOutput -match 'No newer package versions') {
    Write-Host 'Git is already up-to-date.' -ForegroundColor Green
}
elseif ($exitCode -ne 0) {
    Write-Host "WARNING: winget exited with code $exitCode. Upgrade may have failed." -ForegroundColor Yellow
    Write-Host $upgradeOutput -ForegroundColor Gray
}
else {
    Write-Host 'Git is already up-to-date.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan
