<#
.SYNOPSIS
Upgrades pip to the latest version for the current Python installation.

.DESCRIPTION
This script:
  1. Checks if python.exe is on PATH.
  2. Reports the current pip version.
  3. Upgrades pip to the latest version using python -m pip install --upgrade pip.
  4. Reports the result.

pip is the standard Python package manager. AI agents use it to install dependencies
such as requests, numpy, pandas, and other libraries.

Requires Python to be installed first (see install-python.ps1).

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-pip.ps1
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

function Get-PipVersion {
    try {
        $output = (python -m pip --version 2>&1) | Out-String
        if ($output -match 'pip\s+(\S+)') {
            return $Matches[1]
        }
    }
    catch { }
    return $null
}

# --- Main ---
Write-Host 'pip (Python package manager) setup' -ForegroundColor Cyan
Write-Host ''

$pythonVersion = Get-PythonVersion
if (-not $pythonVersion) {
    throw 'Python is not available on PATH. Please run install-python.ps1 first (and restart all VS Code instances if Python was freshly installed).'
}

Write-Host "Python is installed: v$pythonVersion" -ForegroundColor Green

$currentVersion = Get-PipVersion
if ($currentVersion) {
    Write-Host "pip is installed: v$currentVersion" -ForegroundColor Green
}
else {
    Write-Host 'pip is not installed or not working.' -ForegroundColor Yellow
}

Write-Host 'Upgrading pip to the latest version...' -ForegroundColor Gray

$upgradeOutput = python -m pip install --upgrade pip 2>&1 | Out-String
$exitCode = $LASTEXITCODE

$newVersion = Get-PipVersion

if ($exitCode -ne 0) {
    Write-Host "WARNING: pip upgrade exited with code $exitCode." -ForegroundColor Yellow
    Write-Host $upgradeOutput -ForegroundColor Gray
}
elseif ($newVersion -and $currentVersion -and $newVersion -ne $currentVersion) {
    Write-Host "pip updated: v$currentVersion -> v$newVersion" -ForegroundColor Green
}
elseif ($newVersion) {
    Write-Host "pip is already up-to-date: v$newVersion" -ForegroundColor Green
}
else {
    Write-Host 'WARNING: Could not verify pip version after upgrade.' -ForegroundColor Yellow
    Write-Host $upgradeOutput -ForegroundColor Gray
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan
