<#
.SYNOPSIS
Checks whether WinGet (Windows Package Manager) is installed and up-to-date.
Installs or updates it if needed when the App Installer/MSIX path is available.

.DESCRIPTION
WinGet ships as part of the "App Installer" package on Windows.
This script:
  1. Checks if winget.exe is on PATH.
  2. If missing, downloads the latest App Installer bundle, offline license, and dependency packages from the current winget-cli GitHub release.
  3. When running under PowerShell 7, tries the Appx module natively first and then through Windows PowerShell compatibility if needed.
  4. Installs the bundle with dependency paths, and falls back to offline provisioning with the bundled license when required on Windows Server.
  5. If present, checks the version and offers to update if a newer release exists.

Requires internet access. Does NOT require Administrator for the standard App Installer path.

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-winget.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WinGetVersion {
    try {
        $output = (winget --version 2>&1) | Out-String
        if ($output -match '^v?(\d+\.\d+\.\d+)') {
            return $Matches[1]
        }
    }
    catch { }
    return $null
}

function Get-OperatingSystemInfo {
    try {
        return Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    }
    catch { }
    return $null
}

function Import-AppxModule {
    try {
        Import-Module Appx -ErrorAction Stop | Out-Null
        return 'Native'
    }
    catch {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            try {
                Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                return 'WindowsPowerShellCompatibility'
            }
            catch { }
        }
    }

    return $null
}

function Get-AppInstallerUnsupportedReason {
    $os = Get-OperatingSystemInfo
    $platformName = if ($os) { $os.Caption } else { 'this platform' }
    return "The Appx module could not be loaded on $platformName, either natively or through Windows PowerShell compatibility."
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-ProcessorArchitectureFolder {
    $processorArchitecture = if ([string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITECTURE)) {
        'AMD64'
    }
    else {
        $env:PROCESSOR_ARCHITECTURE
    }

    switch ($processorArchitecture.ToUpperInvariant()) {
        'ARM64' { return 'arm64' }
        'AMD64' { return 'x64' }
        'X86' { return 'x86' }
        default { throw "Unsupported PROCESSOR_ARCHITECTURE value: $processorArchitecture" }
    }
}

function Get-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Release,

        [string]$Name,

        [string]$Pattern
    )

    $asset = if ($Name) {
        $Release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    }
    else {
        $Release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
    }

    if (-not $asset) {
        $searchText = if ($Name) { $Name } else { $Pattern }
        throw "Could not find release asset matching '$searchText'."
    }

    return $asset
}

function Install-WinGetFromGitHub {
    $appxImportMode = Import-AppxModule
    if (-not $appxImportMode) {
        Write-Warning "$(Get-AppInstallerUnsupportedReason) WinGet cannot be bootstrapped automatically here."
        return $false
    }

    if ($appxImportMode -eq 'WindowsPowerShellCompatibility') {
        Write-Host 'Using the Appx module through Windows PowerShell compatibility.' -ForegroundColor Gray
    }

    Write-Host 'Downloading latest WinGet release from GitHub...' -ForegroundColor Cyan

    $apiUrl = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    $headers = @{ 'User-Agent' = 'PowerShell-WinGet-Installer' }

    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
    $bundleAsset = Get-ReleaseAsset -Release $release -Name 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    $licenseAsset = Get-ReleaseAsset -Release $release -Pattern '_License1\.xml$'
    $dependenciesAsset = Get-ReleaseAsset -Release $release -Name 'DesktopAppInstaller_Dependencies.zip'

    $downloadDir = Join-Path $env:TEMP ('winget-install-' + [Guid]::NewGuid().ToString('N'))
    $bundlePath = Join-Path $downloadDir $bundleAsset.name
    $licensePath = Join-Path $downloadDir $licenseAsset.name
    $dependenciesZipPath = Join-Path $downloadDir $dependenciesAsset.name
    $dependenciesExtractPath = Join-Path $downloadDir 'dependencies'

    Ensure-Directory -Path $downloadDir
    Ensure-Directory -Path $dependenciesExtractPath

    try {
        Write-Host "Downloading: $($bundleAsset.name) ($([math]::Round($bundleAsset.size / 1MB, 1)) MB)..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $bundleAsset.browser_download_url -OutFile $bundlePath -UseBasicParsing -ErrorAction Stop

        Write-Host "Downloading: $($licenseAsset.name)..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $licenseAsset.browser_download_url -OutFile $licensePath -UseBasicParsing -ErrorAction Stop

        Write-Host "Downloading: $($dependenciesAsset.name)..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $dependenciesAsset.browser_download_url -OutFile $dependenciesZipPath -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $dependenciesZipPath -DestinationPath $dependenciesExtractPath -Force

        $architectureFolder = Get-ProcessorArchitectureFolder
        $dependencyRoot = Join-Path $dependenciesExtractPath $architectureFolder
        $dependencyPaths = Get-ChildItem -Path $dependencyRoot -Filter '*.appx' -File |
            Sort-Object -Property Name |
            Select-Object -ExpandProperty FullName

        if (-not $dependencyPaths) {
            throw "Could not find dependency packages for architecture '$architectureFolder'."
        }

        Write-Host "Using dependency packages for architecture '$architectureFolder'." -ForegroundColor Gray

        try {
            Write-Host 'Installing via Add-AppxPackage with dependency paths...' -ForegroundColor Cyan
            Add-AppxPackage -Path $bundlePath -DependencyPath $dependencyPaths -ForceUpdateFromAnyVersion -ErrorAction Stop
        }
        catch {
            Write-Host 'Add-AppxPackage failed. Trying Add-AppxProvisionedPackage with the offline license...' -ForegroundColor Yellow
            Add-AppxProvisionedPackage -Online -PackagePath $bundlePath -DependencyPackagePath $dependencyPaths -LicensePath $licensePath -ErrorAction Stop | Out-Null
        }
    }
    finally {
        if (Test-Path -LiteralPath $downloadDir) {
            Remove-Item -Path $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $installedVersion = Get-WinGetVersion
    if ($installedVersion) {
        Write-Host 'WinGet installed successfully.' -ForegroundColor Green
        return $true
    }

    Write-Warning 'WinGet installation completed but winget is not yet available on PATH. Close and reopen all VS Code instances, or sign out and sign back in if the package was provisioned.'
    return $true
}

# --- Main ---
Write-Host 'WinGet (Windows Package Manager) setup' -ForegroundColor Cyan
Write-Host ''

$currentVersion = Get-WinGetVersion

if ($currentVersion) {
    Write-Host "WinGet is installed: v$currentVersion" -ForegroundColor Green

    # Attempt self-update via winget itself
    Write-Host 'Checking for updates...' -ForegroundColor Gray
    try {
        $upgradeOutput = winget upgrade --id Microsoft.AppInstaller --source winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        # Check for technology mismatch
        if ($upgradeOutput -match 'install technology is different') {
            Write-Host ''
            Write-Host 'WARNING: A newer version exists but uses a different install technology (e.g. MSI vs MSIX).' -ForegroundColor Yellow
            Write-Host 'Fixing by uninstalling and reinstalling...' -ForegroundColor Yellow
            Write-Host ''

            Write-Host 'Uninstalling current version...' -ForegroundColor Cyan
            $uninstallOutput = winget uninstall --id Microsoft.AppInstaller --silent 2>&1 | Out-String
            $uninstallExit = $LASTEXITCODE

            if ($uninstallExit -ne 0) {
                Write-Host "WARNING: Uninstall exited with code $uninstallExit. Manual intervention may be needed." -ForegroundColor Yellow
                Write-Host $uninstallOutput -ForegroundColor Gray
            }
            else {
                Write-Host 'Installing latest version...' -ForegroundColor Cyan
                $installSucceeded = Install-WinGetFromGitHub
                if ($installSucceeded) {
                    $newVersion = Get-WinGetVersion
                    if ($newVersion -and $newVersion -ne $currentVersion) {
                        Write-Host "WinGet upgraded: v$currentVersion -> v$newVersion" -ForegroundColor Green
                    }
                    else {
                        Write-Host 'Reinstall completed. Close and reopen all VS Code instances for changes to take effect.' -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Host 'WinGet reinstall was skipped on this platform.' -ForegroundColor Yellow
                }
            }
        }
        else {
            $newVersion = Get-WinGetVersion
            if ($newVersion -and $newVersion -ne $currentVersion) {
                Write-Host "WinGet updated: v$currentVersion -> v$newVersion" -ForegroundColor Green
            }
            elseif ($upgradeOutput -match 'No available upgrade' -or $upgradeOutput -match 'No newer package versions') {
                Write-Host 'WinGet is already up-to-date.' -ForegroundColor Green
            }
            elseif ($exitCode -ne 0) {
                Write-Host "WARNING: winget upgrade exited with code $exitCode." -ForegroundColor Yellow
                Write-Host $upgradeOutput -ForegroundColor Gray
            }
            else {
                Write-Host 'WinGet is already up-to-date.' -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host 'Self-update check completed (may already be latest).' -ForegroundColor Gray
    }
}
else {
    Write-Host 'WinGet is not installed.' -ForegroundColor Yellow
    $installSucceeded = Install-WinGetFromGitHub

    if ($installSucceeded) {
        $installedVersion = Get-WinGetVersion
        if ($installedVersion) {
            Write-Host "WinGet is now available: v$installedVersion" -ForegroundColor Green
        }
        else {
            Write-Warning 'WinGet was installed but is not yet on PATH. Please close and reopen all VS Code instances for PATH to take effect.'
        }
    }
    else {
        Write-Host ''
        Write-Host 'Skipping WinGet bootstrap on this platform.' -ForegroundColor Yellow
        Write-Host 'Downstream onboarding scripts should use direct installer fallbacks when WinGet is unavailable.' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan
