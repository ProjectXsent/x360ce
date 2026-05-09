<#
.SYNOPSIS
Downloads, builds, and installs the Azure-Samples MssqlMcp project.

.DESCRIPTION
Clones `https://github.com/Azure-Samples/SQL-AI-samples.git` into a temporary
folder, builds `MssqlMcp\dotnet\MssqlMcp`, then copies the published output to
one of three install targets chosen via an interactive menu:

  1. Global        - %LOCALAPPDATA%\mcp-servers\MssqlMcp\
  2. Project       - {repo}\.ai\MCP\MssqlMcp\          (committed to Git)
  3. ProjectLocal  - {repo}\.ai\MCP\MssqlMcp\.bin\     (git-ignored)

.PARAMETER Target
Optional. Supply 'Global', 'Project', or 'ProjectLocal' to skip the interactive
menu. Case-insensitive. PowerShell tab-completion is supported.

.EXAMPLE
# Interactive menu
.\Install-MssqlMcp.ps1

# Non-interactive
.\Install-MssqlMcp.ps1 -Target Global
.\Install-MssqlMcp.ps1 -Target Project
.\Install-MssqlMcp.ps1 -Target ProjectLocal

.NOTES
- Requires Git for Windows (git.exe) and .NET 8 SDK.
- Uses Debug configuration to match existing repo config.
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Global', 'Project', 'ProjectLocal', IgnoreCase = $true)]
    [string]$Target
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[Install-MssqlMcp] $Message" -ForegroundColor Cyan
}

function Write-Heading {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "  $Message" -ForegroundColor Yellow
    Write-Host ('  ' + ('-' * $Message.Length)) -ForegroundColor DarkYellow
}

function Assert-Directory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Stop-MssqlMcpProcesses {
    <#
    .SYNOPSIS
    Best-effort: kills any running `dotnet` processes executing `MssqlMcp.dll`.
    Prevents file-lock issues while overwriting DLLs during install.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return }

    $processes = Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ieq 'dotnet.exe' -and
            $_.CommandLine -and
            ($_.CommandLine -match 'MssqlMcp\.dll')
        }

    foreach ($p in $processes) {
        try {
            $msg = "Stopping running MssqlMcp instance (PID $($p.ProcessId))"
            if ($PSCmdlet.ShouldProcess($p.ProcessId, $msg)) {
                Write-Info $msg
                Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            }
        }
        catch {
            # Best-effort cleanup; continue, but be explicit.
            Write-Verbose "Failed to stop PID $($p.ProcessId): $($_.Exception.Message)"
        }
    }
}

# ── Resolve paths ────────────────────────────────────────────────────────────

$repoRoot = (Resolve-Path -LiteralPath "$PSScriptRoot\..\..").Path

# Install-target directories
$paths = @{
    Global       = Join-Path $env:LOCALAPPDATA 'mcp-servers\MssqlMcp'
    Project      = Join-Path $repoRoot '.ai\MCP\MssqlMcp'
    ProjectLocal = Join-Path $repoRoot '.ai\MCP\MssqlMcp\.bin'
}

# ── Interactive menu ─────────────────────────────────────────────────────────

function Show-Menu {
    Write-Heading 'Install MssqlMcp - Choose install location'

    Write-Host ''
    Write-Host '  1. Global        (per-user, shared across all projects)' -ForegroundColor White
    Write-Host "     $($paths.Global)" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  2. Project       (committed to source control)' -ForegroundColor White
    Write-Host "     $($paths.Project)" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  3. ProjectLocal  (git-ignored, machine-local)' -ForegroundColor White
    Write-Host "     $($paths.ProjectLocal)" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Press Enter to cancel.' -ForegroundColor DarkGray
    Write-Host ''

    while ($true) {
        $key = Read-Host '  Selection (1-3)'
        if ([string]::IsNullOrWhiteSpace($key)) {
            Write-Host '  Cancelled.' -ForegroundColor DarkYellow
            exit 0
        }
        switch ($key.Trim()) {
            '1' { return 'Global' }
            '2' { return 'Project' }
            '3' { return 'ProjectLocal' }
            default { Write-Host '  Invalid choice. Enter 1, 2, or 3 (Enter to cancel).' -ForegroundColor Red }
        }
    }
}

$selectedTarget = if ([string]::IsNullOrWhiteSpace($Target)) { Show-Menu } else { $Target }
$installRoot = $paths[$selectedTarget]

Write-Info "Selected target : $selectedTarget"
Write-Info "Install path    : $installRoot"

# ── Ensure git-ignore for ProjectLocal target ────────────────────────────────

if ($selectedTarget -eq 'ProjectLocal') {
    # Ensure .ai/MCP/MssqlMcp/.bin/ is git-ignored via .ai/.gitignore
    $aiGitIgnore = Join-Path $repoRoot '.ai\.gitignore'
    $ignoreEntry = 'MCP/MssqlMcp/.bin/'

    if (Test-Path -LiteralPath $aiGitIgnore) {
        $content = Get-Content -LiteralPath $aiGitIgnore -Raw
        if ($content -notmatch [regex]::Escape($ignoreEntry)) {
            Write-Info "Adding '$ignoreEntry' to .ai/.gitignore"
            Add-Content -LiteralPath $aiGitIgnore -Value "`n# MssqlMcp binaries (local install)`n$ignoreEntry"
        }
    }
    else {
        Write-Info "Creating .ai/.gitignore with '$ignoreEntry'"
        Set-Content -LiteralPath $aiGitIgnore -Value "# MssqlMcp binaries (local install)`n$ignoreEntry"
    }
}

# ── Pre-install cleanup ─────────────────────────────────────────────────────

Stop-MssqlMcpProcesses

# ── Clone and build ─────────────────────────────────────────────────────────

$sourceRepoUrl   = 'https://github.com/Azure-Samples/SQL-AI-samples.git'
$subRepoRelative = 'MssqlMcp\dotnet\MssqlMcp'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('MssqlMcp-' + [System.Guid]::NewGuid().ToString('N'))

Write-Info "Repo root   : $repoRoot"
Write-Info "Temp folder : $tempRoot"

try {
    Assert-Directory -Path $tempRoot

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        throw 'git is required to download SQL-AI-samples. Install Git for Windows and ensure it is on PATH.'
    }

    Write-Info "Cloning $sourceRepoUrl ..."
    & git clone --depth 1 $sourceRepoUrl $tempRoot | Out-Null

    $projectDir = Join-Path $tempRoot $subRepoRelative
    if (-not (Test-Path -LiteralPath $projectDir)) {
        throw "Expected project directory not found: $projectDir"
    }

    Write-Info "Building: $projectDir"
    & dotnet publish $projectDir -c Debug -r win-x64 --self-contained false | Out-Host

    $publishDir = Join-Path $projectDir 'bin\Debug\net8.0\win-x64\publish\'

    if (-not (Test-Path -LiteralPath $publishDir)) {
        throw "Publish output folder not found: $publishDir"
    }

    $builtDll = Join-Path $publishDir 'MssqlMcp.dll'
    if (-not (Test-Path -LiteralPath $builtDll)) {
        throw "Build output not found: $builtDll"
    }

    # ── Copy to install target ───────────────────────────────────────────────

    Assert-Directory -Path $installRoot

    Write-Info "Copying publish output to: $installRoot"
    Get-ChildItem -LiteralPath $publishDir -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $installRoot $_.Name) -Force
    }

    # For the Project target, also maintain the legacy bin\ subfolder copy
    # (backwards compatibility with older configs that referenced .ai\MCP\MssqlMcp\bin\MssqlMcp.dll)
    if ($selectedTarget -eq 'Project') {
        $legacyBin = Join-Path $installRoot 'bin'
        Assert-Directory -Path $legacyBin
        $legacyDll = Join-Path $legacyBin 'MssqlMcp.dll'
        Write-Info "Legacy copy: $legacyDll"
        Copy-Item -LiteralPath $builtDll -Destination $legacyDll -Force
    }

    # ── Summary ──────────────────────────────────────────────────────────────

    $dllPath = Join-Path $installRoot 'MssqlMcp.dll'

    Write-Heading 'Installation complete'
    Write-Host ''
    Write-Host '  MCP config command example:' -ForegroundColor White
    Write-Host ''

    switch ($selectedTarget) {
        'Global' {
            Write-Host "    dotnet `"$dllPath`"" -ForegroundColor Green
            Write-Host ''
            Write-Host '  Tip: Reference this absolute path in your global MCP config' -ForegroundColor DarkGray
            Write-Host '       (e.g. VS Code settings.json or ~/.roo/mcp.json).' -ForegroundColor DarkGray
        }
        'Project' {
            $relative = '.ai\MCP\MssqlMcp\MssqlMcp.dll'
            Write-Host "    dotnet `"$relative`"" -ForegroundColor Green
            Write-Host ''
            Write-Host '  Tip: This path is relative to the repo root and committed to Git.' -ForegroundColor DarkGray
            Write-Host '       All team members will have the binaries after pulling.' -ForegroundColor DarkGray
        }
        'ProjectLocal' {
            $relative = '.ai\MCP\MssqlMcp\.bin\MssqlMcp.dll'
            Write-Host "    dotnet `"$relative`"" -ForegroundColor Green
            Write-Host ''
            Write-Host '  Tip: This path is git-ignored. Each developer must run this' -ForegroundColor DarkGray
            Write-Host '       script locally. The install script itself IS committed.' -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Info 'Done.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Write-Info "Cleaning temp folder: $tempRoot"
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
