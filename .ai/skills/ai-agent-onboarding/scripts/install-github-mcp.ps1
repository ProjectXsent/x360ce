<#
.SYNOPSIS
Downloads and installs the official GitHub MCP server binary.

.DESCRIPTION
Downloads the latest release of `github-mcp-server` from the official
GitHub repository (https://github.com/github/github-mcp-server/releases)
and extracts it to:

  %LOCALAPPDATA%\mcp-servers\github-mcp-server\

No Docker or Go SDK required — uses pre-built Windows binaries published
by the github-actions bot under the official `github` org.

.PARAMETER Architecture
Optional. 'x86_64', 'arm64', or 'i386'. Defaults to auto-detect.

.EXAMPLE
# Auto-detect architecture
.\install-github-mcp.ps1

# Specify architecture
.\install-github-mcp.ps1 -Architecture x86_64

.NOTES
- Requires internet access to download from GitHub Releases.
- Overwrites any previous installation in the same folder.
- Idempotent — safe to run again to update to a newer version.
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('x86_64', 'arm64', 'i386', IgnoreCase = $true)]
    [string]$Architecture
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[Install-GitHubMcp] $Message" -ForegroundColor Cyan
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

# ── Detect architecture ─────────────────────────────────────────────────────

if ([string]::IsNullOrWhiteSpace($Architecture)) {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
    $Architecture = switch ($arch) {
        'x64'   { 'x86_64' }
        'arm64' { 'arm64' }
        'x86'   { 'i386' }
        default { 'x86_64' }
    }
    Write-Info "Detected architecture: $Architecture"
}

# ── Resolve install path ────────────────────────────────────────────────────

$installRoot = Join-Path $env:LOCALAPPDATA 'mcp-servers\github-mcp-server'

Write-Info "Install path: $installRoot"

# ── Find latest release ─────────────────────────────────────────────────────

$repo = 'github/github-mcp-server'
$apiUrl = "https://api.github.com/repos/$repo/releases/latest"

Write-Info "Fetching latest release from $repo ..."

$release = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'Install-GitHubMcp/1.0' }
$tagName = $release.tag_name
$version = $tagName -replace '^v', ''

Write-Info "Latest version: $tagName"

# ── Find matching asset ─────────────────────────────────────────────────────

$assetName = "github-mcp-server_Windows_${Architecture}.zip"
$asset = $release.assets | Where-Object { $_.name -eq $assetName }

if (-not $asset) {
    $available = ($release.assets | ForEach-Object { $_.name }) -join ', '
    throw "Asset '$assetName' not found in release $tagName. Available: $available"
}

$downloadUrl = $asset.browser_download_url

Write-Info "Downloading: $assetName"

# ── Download and extract ────────────────────────────────────────────────────

$tempZip = Join-Path ([System.IO.Path]::GetTempPath()) $assetName

try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing

    Write-Info "Extracting to: $installRoot"

    Assert-Directory -Path $installRoot

    Expand-Archive -LiteralPath $tempZip -DestinationPath $installRoot -Force

    # The zip may contain the exe directly or in a subfolder — find it
    $exe = Get-ChildItem -LiteralPath $installRoot -Filter 'github-mcp-server.exe' -Recurse |
        Select-Object -First 1

    if (-not $exe) {
        throw "github-mcp-server.exe not found after extraction in $installRoot"
    }

    # If the exe is in a subfolder, move everything up to installRoot
    if ($exe.DirectoryName -ne $installRoot) {
        Get-ChildItem -LiteralPath $exe.DirectoryName -File | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $installRoot $_.Name) -Force
        }
    }

    $exePath = Join-Path $installRoot 'github-mcp-server.exe'

    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "Installation failed: $exePath not found"
    }

    # ── Verify ───────────────────────────────────────────────────────────────

    Write-Info "Verifying binary..."
    $versionOutput = & $exePath --version 2>&1
    Write-Info "Installed: $versionOutput"

    # ── Summary ──────────────────────────────────────────────────────────────

    Write-Heading 'Installation complete'
    Write-Host ''
    Write-Host "  Binary: $exePath" -ForegroundColor White
    Write-Host ''
    Write-Host '  MCP config example:' -ForegroundColor White
    Write-Host ''
    Write-Host '    "github-{YourUser}": {' -ForegroundColor Green
    Write-Host '      "type": "stdio",' -ForegroundColor Green
    Write-Host "      `"command`": `"$($exePath.Replace('\','\\'))`"," -ForegroundColor Green
    Write-Host '      "args": ["stdio"],' -ForegroundColor Green
    Write-Host '      "env": {' -ForegroundColor Green
    Write-Host '        "GITHUB_PERSONAL_ACCESS_TOKEN": "${env:GITHUB_PERSONAL_ACCESS_TOKEN}"' -ForegroundColor Green
    Write-Host '      }' -ForegroundColor Green
    Write-Host '    }' -ForegroundColor Green
    Write-Host ''

    # Check if PAT is set
    $pat = [Environment]::GetEnvironmentVariable('GITHUB_PERSONAL_ACCESS_TOKEN', 'User')
    if ($pat) {
        Write-Host '  GITHUB_PERSONAL_ACCESS_TOKEN is set.' -ForegroundColor Green
    }
    else {
        Write-Host '  WARNING: GITHUB_PERSONAL_ACCESS_TOKEN is NOT set.' -ForegroundColor Red
        Write-Host '  Create a token at: https://github.com/settings/tokens' -ForegroundColor Yellow
        Write-Host '  Then set it:' -ForegroundColor Yellow
        Write-Host "  [Environment]::SetEnvironmentVariable('GITHUB_PERSONAL_ACCESS_TOKEN', '<token>', 'User')" -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Info 'Done.'
}
finally {
    if (Test-Path -LiteralPath $tempZip) {
        Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    }
}
