<#
.SYNOPSIS
Enables long path support on Windows and Git.

.DESCRIPTION
- Checks Windows registry setting: HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled
  If not enabled, the script will prompt for elevation (admin) and set it.

- Checks Git setting: core.longpaths
  If not enabled, the script will set it (default scope: --global).

.PARAMETER GitScope
Where to set Git core.longpaths. Supported values:
- Global: sets in the current user's global config (git config --global)
- Local: sets in the current repository only (git config --local)
- System: sets in the system config (git config --system) - requires elevation typically

.PARAMETER Force
If specified, do not prompt before applying changes.

.EXAMPLE
./.ai/scripts/Setup_Util_EnableLongPaths_WindowsAndGit.ps1

.EXAMPLE
./.ai/scripts/Setup_Util_EnableLongPaths_WindowsAndGit.ps1 -GitScope Local

.EXAMPLE
./.ai/scripts/Setup_Util_EnableLongPaths_WindowsAndGit.ps1 -Force
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Global', 'Local', 'System')]
    [string]$GitScope = 'Global',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Invoke-SelfElevated {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = ($ArgumentList -join ' ')
    $psi.Verb = 'runas'
    $psi.UseShellExecute = $true

    [System.Diagnostics.Process]::Start($psi) | Out-Null
}

function Get-WindowsLongPathsEnabled {
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    $name = 'LongPathsEnabled'

    try {
        $value = (Get-ItemProperty -Path $regPath -Name $name -ErrorAction Stop).$name
        return [int]$value
    } catch {
        return $null
    }
}

function Set-WindowsLongPathsEnabled {
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    $name = 'LongPathsEnabled'

    if ($PSCmdlet.ShouldProcess("$regPath\\$name", 'Set to 1')) {
        New-ItemProperty -Path $regPath -Name $name -PropertyType DWord -Value 1 -Force | Out-Null
    }
}

function Get-GitCoreLongPaths {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Global', 'Local', 'System')]
        [string]$Scope
    )

    $scopeArg = switch ($Scope) {
        'Global' { '--global' }
        'Local'  { '--local' }
        'System' { '--system' }
    }

    try {
        $value = (git config $scopeArg --get core.longpaths 2>$null).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $null
        }

        return $value
    } catch {
        return $null
    }
}

function Set-GitCoreLongPaths {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Global', 'Local', 'System')]
        [string]$Scope
    )

    $scopeArg = switch ($Scope) {
        'Global' { '--global' }
        'Local'  { '--local' }
        'System' { '--system' }
    }

    if ($PSCmdlet.ShouldProcess("git config $scopeArg core.longpaths", 'Set to true')) {
        git config $scopeArg core.longpaths true | Out-Null
    }
}

Write-Host 'Long path support setup (Windows + Git)' -ForegroundColor Cyan
Write-Host ''

# --- Current status ---
$windowsValue = Get-WindowsLongPathsEnabled
$windowsStatus = if ($windowsValue -eq 1) { 'Enabled (1)' } elseif ($windowsValue -eq 0) { 'Disabled (0)' } else { 'Missing (not set)' }
Write-Host "Status (Windows): LongPathsEnabled = $windowsStatus" -ForegroundColor Gray

try {
    $gitVersion = (git --version)
    Write-Host "Status (Git): $gitVersion" -ForegroundColor Gray
} catch {
    Write-Host 'Status (Git): not found on PATH' -ForegroundColor Gray
    $gitVersion = $null
}

if ($gitVersion) {
    foreach ($scope in @('System', 'Global', 'Local')) {
        if ($scope -eq 'Local' -and -not (Test-Path -Path (Join-Path -Path (Get-Location) -ChildPath '.git'))) {
            Write-Host "Status (Git): core.longpaths ($scope) = <not a repo>" -ForegroundColor Gray
            continue
        }

        $value = Get-GitCoreLongPaths -Scope $scope
        if ($null -eq $value) {
            Write-Host "Status (Git): core.longpaths ($scope) = <not set>" -ForegroundColor Gray
        } else {
            Write-Host "Status (Git): core.longpaths ($scope) = $value" -ForegroundColor Gray
        }
    }
}

Write-Host ''

# If script was run without explicit intent, ask once whether to apply necessary changes.
$applyChanges = $Force
if (-not $Force) {
    $needsWindowsChange = ($windowsValue -ne 1)
    $needsGitChange = $false

    if ($gitVersion) {
        $selectedGitValue = Get-GitCoreLongPaths -Scope $GitScope
        $needsGitChange = -not ($selectedGitValue -and ($selectedGitValue -match '^(true|1|yes|on)$'))
    }

    if ($needsWindowsChange -or $needsGitChange) {
        $targets = @()
        if ($needsWindowsChange) { $targets += 'Windows' }
        if ($needsGitChange) { $targets += "Git ($GitScope)" }
        $targetText = ($targets -join ' and ')

        $choice = Read-Host "Apply required long path changes for ${targetText}? (Y/N)"
        if ($choice -in @('Y', 'y', 'Yes', 'yes')) {
            $applyChanges = $true
        } else {
            Write-Host 'No changes will be applied.' -ForegroundColor DarkYellow
        }
    } else {
        Write-Host 'No changes required.' -ForegroundColor Green
        $applyChanges = $false
    }
}

# --- Windows setting ---
if ($windowsValue -eq 1) {
    Write-Host 'Windows: LongPathsEnabled is already enabled (1).' -ForegroundColor Green
} elseif ($windowsValue -eq 0) {
    Write-Host 'Windows: LongPathsEnabled is currently disabled (0).' -ForegroundColor Yellow

    $needsElevation = -not (Test-IsAdministrator)
    if ($needsElevation) {
        Write-Host 'Windows: Registry change requires Administrator privileges.' -ForegroundColor Yellow

        if (-not $applyChanges) {
            Write-Host 'Skipping Windows registry change.' -ForegroundColor DarkYellow
            $needsElevation = $false
        } elseif (-not $Force) {
            $choice = Read-Host 'Relaunch this script as Administrator to enable it? (Y/N)'
            if ($choice -notin @('Y', 'y', 'Yes', 'yes')) {
                Write-Host 'Skipping Windows registry change.' -ForegroundColor DarkYellow
                $needsElevation = $false
            }
        }

        if ($needsElevation) {
            $scriptPath = $MyInvocation.MyCommand.Path
            $argList = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', ('"' + $scriptPath + '"'),
                '-GitScope', $GitScope
            )

            if ($Force) {
                $argList += '-Force'
            }

            Write-Host 'Re-launching elevated...' -ForegroundColor Yellow
            Invoke-SelfElevated -ArgumentList $argList
            return
        }
    }

    if ($applyChanges -and (Test-IsAdministrator)) {
        Set-WindowsLongPathsEnabled
        Write-Host 'Windows: LongPathsEnabled set to 1.' -ForegroundColor Green
    } elseif (-not $applyChanges) {
        Write-Host 'Windows: no change applied.' -ForegroundColor DarkYellow
    }
} else {
    Write-Host 'Windows: LongPathsEnabled is not set (registry value missing).' -ForegroundColor Yellow

    $needsElevation = -not (Test-IsAdministrator)
    if ($needsElevation) {
        Write-Host 'Windows: Registry change requires Administrator privileges.' -ForegroundColor Yellow

        if (-not $applyChanges) {
            Write-Host 'Skipping Windows registry change.' -ForegroundColor DarkYellow
            $needsElevation = $false
        } elseif (-not $Force) {
            $choice = Read-Host 'Relaunch this script as Administrator to create and enable it? (Y/N)'
            if ($choice -notin @('Y', 'y', 'Yes', 'yes')) {
                Write-Host 'Skipping Windows registry change.' -ForegroundColor DarkYellow
                $needsElevation = $false
            }
        }

        if ($needsElevation) {
            $scriptPath = $MyInvocation.MyCommand.Path
            $argList = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', ('"' + $scriptPath + '"'),
                '-GitScope', $GitScope
            )

            if ($Force) {
                $argList += '-Force'
            }

            Write-Host 'Re-launching elevated...' -ForegroundColor Yellow
            Invoke-SelfElevated -ArgumentList $argList
            return
        }
    }

    if ($applyChanges -and (Test-IsAdministrator)) {
        Set-WindowsLongPathsEnabled
        Write-Host 'Windows: LongPathsEnabled created and set to 1.' -ForegroundColor Green
    } elseif (-not $applyChanges) {
        Write-Host 'Windows: no change applied.' -ForegroundColor DarkYellow
    }
}

Write-Host ''

# --- Git setting ---
if (-not $gitVersion) {
    Write-Warning 'Git: not found on PATH. Skipping Git configuration.'
    return
}

Write-Host "Git: detected ($gitVersion)" -ForegroundColor Gray

if ($GitScope -eq 'Local') {
    if (-not (Test-Path -Path (Join-Path -Path (Get-Location) -ChildPath '.git'))) {
        Write-Warning "GitScope=Local but current directory does not appear to be a Git repository (.git not found): $(Get-Location)"
        Write-Warning 'Skipping Git configuration.'
        return
    }
}

$gitValue = Get-GitCoreLongPaths -Scope $GitScope
if ($gitValue -and ($gitValue -match '^(true|1|yes|on)$')) {
    Write-Host "Git ($GitScope): core.longpaths is already enabled ($gitValue)." -ForegroundColor Green
} elseif ($gitValue) {
    Write-Host "Git ($GitScope): core.longpaths is set to '$gitValue' (not enabled)." -ForegroundColor Yellow

    if (-not $applyChanges) {
        Write-Host 'Skipping Git configuration.' -ForegroundColor DarkYellow
    } elseif ($Force -or $PSCmdlet.ShouldContinue("Set Git ($GitScope) core.longpaths to true?", 'Git configuration')) {
        Set-GitCoreLongPaths -Scope $GitScope
        Write-Host "Git ($GitScope): core.longpaths set to true." -ForegroundColor Green
    } else {
        Write-Host 'Skipping Git configuration.' -ForegroundColor DarkYellow
    }
} else {
    Write-Host "Git ($GitScope): core.longpaths is not set." -ForegroundColor Yellow

    if (-not $applyChanges) {
        Write-Host 'Skipping Git configuration.' -ForegroundColor DarkYellow
    } elseif ($Force -or $PSCmdlet.ShouldContinue("Set Git ($GitScope) core.longpaths to true?", 'Git configuration')) {
        Set-GitCoreLongPaths -Scope $GitScope
        Write-Host "Git ($GitScope): core.longpaths set to true." -ForegroundColor Green
    } else {
        Write-Host 'Skipping Git configuration.' -ForegroundColor DarkYellow
    }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan
