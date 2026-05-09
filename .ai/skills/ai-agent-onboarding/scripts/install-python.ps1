<#
.SYNOPSIS
Installs or updates Python 3 (latest stable) using winget.

.DESCRIPTION
This script:
  1. Checks if python.exe is on PATH and reports the current version.
  2. Determines the latest stable Python 3.x minor series available in winget.
  3. Uses winget to install or update Python to the latest version.
  4. Detects and reports upgrade failures (technology mismatch, etc.).

AI agents frequently depend on Python for tools, scripts, and package installation.

Requires winget to be installed first (see install-winget.ps1).

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-python.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PythonVersion {
    try {
        $output = (python --version 2>&1) | Out-String
        if ($output -match '(\d+\.\d+\.\d+)') {
            return $Matches[1]
        }
    }
    catch { }
    return $null
}

function Get-PythonMinorVersion {
    param([string]$Version)
    if ($Version -match '^(\d+\.\d+)') {
        return $Matches[1]
    }
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

function Get-LatestPythonPackageId {
    # Find the highest stable Python 3.x minor series in winget (skip preview/pre-release).
    try {
        $output = winget search Python.Python.3 --source winget --accept-source-agreements 2>&1 | Out-String
        # Match lines like: Python 3.13 Python.Python.3.13 3.13.12
        $ids = [regex]::Matches($output, 'Python\.Python\.3\.(\d+)\s+\d+\.\d+\.\d+')
        if ($ids.Count -eq 0) { return $null }
        $maxMinor = ($ids | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Descending | Select-Object -First 1)
        return "Python.Python.3.$maxMinor"
    }
    catch { }
    return $null
}

# --- Main ---
Write-Host 'Python 3 setup' -ForegroundColor Cyan
Write-Host ''

if (-not (Test-WinGetAvailable)) {
    throw 'WinGet is not available. Please run install-winget.ps1 first.'
}

$currentVersion = Get-PythonVersion
$freshInstall = $false

# Determine the best package ID
$packageId = $null
if ($currentVersion) {
    $minor = Get-PythonMinorVersion $currentVersion
    $packageId = "Python.Python.$minor"
    Write-Host "Python is installed: v$currentVersion (package: $packageId)" -ForegroundColor Green
}

# Check what the latest stable minor series is
$latestPackageId = Get-LatestPythonPackageId
if ($latestPackageId) {
    $latestAvailable = Get-WinGetAvailableVersion -PackageId $latestPackageId
    Write-Host "Latest stable series: $latestPackageId (v$latestAvailable)" -ForegroundColor Gray
}

$newSeriesInstall = $false

if ($currentVersion) {
    # If installed minor is older than the latest series, install the new series
    if ($latestPackageId -and $packageId -ne $latestPackageId) {
        Write-Host ''
        Write-Host "A newer Python series is available: $latestPackageId (v$latestAvailable)" -ForegroundColor Yellow
        Write-Host "Installing $latestPackageId..." -ForegroundColor Cyan
        $packageId = $latestPackageId
        $newSeriesInstall = $true

        $upgradeOutput = winget install --id $packageId --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
    else {
        Write-Host 'Checking for updates via winget...' -ForegroundColor Gray

        $availableVersion = Get-WinGetAvailableVersion -PackageId $packageId
        if ($availableVersion) {
            Write-Host "Latest available version: v$availableVersion" -ForegroundColor Gray
        }

        # Use winget upgrade for existing installs
        $upgradeOutput = winget upgrade --id $packageId --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
}
else {
    if (-not $latestPackageId) {
        throw 'Could not determine the latest Python package ID from winget.'
    }
    $packageId = $latestPackageId
    Write-Host 'Python is not installed.' -ForegroundColor Yellow
    Write-Host "Installing $packageId via winget..." -ForegroundColor Cyan
    $freshInstall = $true

    $upgradeOutput = winget install --id $packageId --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
}

$newVersion = Get-PythonVersion

if ($freshInstall -or $newSeriesInstall) {
    # For new series installs, PATH in the current session may still point to the old version.
    # Check if the new package was actually installed by querying winget.
    $installedVersion = Get-WinGetAvailableVersion -PackageId $packageId
    # Exit code 0 = success, -1978335189 (0x8A150017) = already installed / no upgrade available
    $alreadyInstalled = ($upgradeOutput -match 'No available upgrade' -or $upgradeOutput -match 'No newer package versions' -or $upgradeOutput -match 'already installed')
    $successIndicator = ($upgradeOutput -match 'Successfully installed' -or $exitCode -eq 0 -or $alreadyInstalled)

    if ($upgradeOutput -match 'install technology is different') {
        Write-Host '' -ForegroundColor Yellow
        Write-Host 'WARNING: Install failed due to technology mismatch. Fixing by uninstalling old version and reinstalling...' -ForegroundColor Yellow

        # Uninstall old series
        $oldPackageId = "Python.Python.$(Get-PythonMinorVersion $currentVersion)"
        Write-Host "Uninstalling $oldPackageId..." -ForegroundColor Cyan
        $uninstallOutput = winget uninstall --id $oldPackageId --silent 2>&1 | Out-String

        Write-Host "Installing $packageId..." -ForegroundColor Cyan
        $reinstallOutput = winget install --id $packageId --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
        $reinstallExit = $LASTEXITCODE

        if ($reinstallExit -eq 0) {
            Write-Host "Python $packageId installed successfully (v$installedVersion)." -ForegroundColor Green
            Write-Host ''
            Write-Host 'NOTE: Close and reopen all VS Code instances for PATH to take effect.' -ForegroundColor Yellow
        }
        else {
            Write-Host "WARNING: Reinstall exited with code $reinstallExit." -ForegroundColor Yellow
            Write-Host $reinstallOutput -ForegroundColor Gray
        }
    }
    elseif ($successIndicator) {
        if ($newSeriesInstall) {
            Write-Host "Python $packageId installed (v$installedVersion). Previous v$currentVersion remains on PATH in this session." -ForegroundColor Green
        }
        else {
            Write-Host "Python installed (v$installedVersion)." -ForegroundColor Green
        }
        Write-Host ''
        Write-Host 'NOTE: Close and reopen all VS Code instances for PATH to take effect.' -ForegroundColor Yellow
    }
    elseif ($exitCode -ne 0) {
        Write-Host "WARNING: winget exited with code $exitCode. Install may have failed." -ForegroundColor Yellow
        Write-Host $upgradeOutput -ForegroundColor Gray
    }
    else {
        Write-Host "Python $packageId is already installed." -ForegroundColor Green
    }
}
elseif ($upgradeOutput -match 'install technology is different') {
    Write-Host '' -ForegroundColor Yellow
    Write-Host 'WARNING: A newer version exists but uses a different install technology (e.g. MSI vs MSIX).' -ForegroundColor Yellow
    Write-Host 'This causes version inconsistencies between terminals. Fixing by uninstalling and reinstalling...' -ForegroundColor Yellow
    Write-Host ''

    Write-Host 'Uninstalling current version...' -ForegroundColor Cyan
    $uninstallOutput = winget uninstall --id $packageId --silent 2>&1 | Out-String
    $uninstallExit = $LASTEXITCODE

    if ($uninstallExit -ne 0) {
        Write-Host "WARNING: Uninstall exited with code $uninstallExit. Manual intervention may be needed." -ForegroundColor Yellow
        Write-Host $uninstallOutput -ForegroundColor Gray
    }
    else {
        Write-Host 'Installing latest version...' -ForegroundColor Cyan
        $reinstallOutput = winget install --id $packageId --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-String
        $reinstallExit = $LASTEXITCODE

        $newVersion = Get-PythonVersion
        if ($newVersion -and $newVersion -ne $currentVersion) {
            Write-Host "Python upgraded: v$currentVersion -> v$newVersion" -ForegroundColor Green
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
    Write-Host "Python updated: v$currentVersion -> v$newVersion" -ForegroundColor Green
}
elseif ($upgradeOutput -match 'No available upgrade' -or $upgradeOutput -match 'No newer package versions') {
    Write-Host 'Python is already up-to-date.' -ForegroundColor Green
}
elseif ($exitCode -ne 0) {
    Write-Host "WARNING: winget exited with code $exitCode. Upgrade may have failed." -ForegroundColor Yellow
    Write-Host $upgradeOutput -ForegroundColor Gray
}
else {
    Write-Host 'Python is already up-to-date.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan
