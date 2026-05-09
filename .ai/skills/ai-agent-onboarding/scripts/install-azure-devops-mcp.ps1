<#
.SYNOPSIS
Installs the official Azure DevOps MCP server with self-hosted URL support.

.DESCRIPTION
Installs `@azure-devops/mcp` (Microsoft official) from npm into:

  %LOCALAPPDATA%\mcp-servers\azure-devops-mcp\

Then applies a one-line patch to support self-hosted Azure DevOps Server
URLs via the `ADO_MCP_ORG_URL` environment variable. Without the patch,
the package only connects to `https://dev.azure.com/{org}`.

The patch is safe and minimal — it changes the hardcoded URL to:
  `process.env.ADO_MCP_ORG_URL || ("https://dev.azure.com/" + orgName)`

If `ADO_MCP_ORG_URL` is not set, the original cloud behavior is preserved.

.PARAMETER Version
Optional. The npm package version to install. Defaults to 'latest'.

.EXAMPLE
# Install latest version
.\install-azure-devops-mcp.ps1

# Install specific version
.\install-azure-devops-mcp.ps1 -Version 2.5.0

.NOTES
- Requires Node.js (node and npm on PATH).
- Idempotent — safe to run again to update to a newer version.
- Source: https://github.com/microsoft/azure-devops-mcp
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Version = 'latest'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[Install-AzureDevOpsMcp] $Message" -ForegroundColor Cyan
}

function Write-Heading {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "  $Message" -ForegroundColor Yellow
    Write-Host ('  ' + ('-' * $Message.Length)) -ForegroundColor DarkYellow
}

# ── Check prerequisites ─────────────────────────────────────────────────────

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    throw 'Node.js is required. Install it with: winget install OpenJS.NodeJS.LTS'
}

$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npm) {
    throw 'npm is required. It ships with Node.js — ensure Node.js is installed and on PATH.'
}

Write-Info "Node.js: $(node --version)"
Write-Info "npm: $(npm --version)"

# ── Resolve install path ────────────────────────────────────────────────────

$installRoot = Join-Path $env:LOCALAPPDATA 'mcp-servers\azure-devops-mcp'

Write-Info "Install path: $installRoot"

if (-not (Test-Path -LiteralPath $installRoot)) {
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
}

# ── Install npm package ─────────────────────────────────────────────────────

$packageSpec = if ($Version -eq 'latest') { '@azure-devops/mcp' } else { "@azure-devops/mcp@$Version" }

Write-Info "Installing $packageSpec ..."

Push-Location $installRoot
try {
    # Ensure package.json exists
    if (-not (Test-Path 'package.json')) {
        & npm init -y 2>&1 | Out-Null
    }

    & npm install $packageSpec 2>&1 | Out-Host

    $indexJs = Join-Path $installRoot 'node_modules\@azure-devops\mcp\dist\index.js'
    if (-not (Test-Path -LiteralPath $indexJs)) {
        throw "index.js not found after install: $indexJs"
    }

    # ── Apply self-hosted URL patch ──────────────────────────────────────────

    $content = Get-Content -LiteralPath $indexJs -Raw

    $originalLine = 'const orgUrl = "https://dev.azure.com/" + orgName;'
    $patchedLine  = 'const orgUrl = process.env.ADO_MCP_ORG_URL || ("https://dev.azure.com/" + orgName);'

    if ($content.Contains($patchedLine)) {
        Write-Info "Self-hosted URL patch already applied."
    }
    elseif ($content.Contains($originalLine)) {
        $content = $content.Replace($originalLine, $patchedLine)
        Set-Content -LiteralPath $indexJs -Value $content -NoNewline
        Write-Info "Applied self-hosted URL patch (ADO_MCP_ORG_URL support)."
    }
    else {
        Write-Host "  WARNING: Could not find the expected orgUrl line to patch." -ForegroundColor Red
        Write-Host "  The package may have changed. Self-hosted URLs may not work." -ForegroundColor Red
        Write-Host "  Expected: $originalLine" -ForegroundColor DarkGray
    }

    # ── Apply PAT-as-Basic-auth patch (for self-hosted with envvar auth) ─────
    # The stock package wraps the PAT in a Bearer header (getBearerHandler),
    # which Azure DevOps Server rejects as anonymous (TF400813). PATs must be
    # sent as HTTP Basic auth. Cloud dev.azure.com accepts both, so this patch
    # is safe for both cloud and self-hosted.

    $content = Get-Content -LiteralPath $indexJs -Raw

    $originalImport = 'import { getBearerHandler, WebApi } from "azure-devops-node-api";'
    $patchedImport  = 'import { getBearerHandler, getPersonalAccessTokenHandler, WebApi } from "azure-devops-node-api";'

    $originalHandler = 'const authHandler = getBearerHandler(accessToken);'
    $patchedHandler  = 'const authHandler = argv.authentication === "envvar" ? getPersonalAccessTokenHandler(accessToken) : getBearerHandler(accessToken);'

    if ($content.Contains($patchedHandler)) {
        Write-Info "PAT-as-Basic-auth patch already applied."
    }
    elseif ($content.Contains($originalImport) -and $content.Contains($originalHandler)) {
        $content = $content.Replace($originalImport, $patchedImport)
        $content = $content.Replace($originalHandler, $patchedHandler)
        Set-Content -LiteralPath $indexJs -Value $content -NoNewline
        Write-Info "Applied PAT-as-Basic-auth patch (envvar mode uses getPersonalAccessTokenHandler)."
    }
    else {
        Write-Host "  WARNING: Could not find the expected Bearer-handler lines to patch." -ForegroundColor Red
        Write-Host "  Self-hosted Azure DevOps Server will return TF400813 with envvar auth." -ForegroundColor Red
    }

    # ── Verify ───────────────────────────────────────────────────────────────

    Write-Info "Verifying..."
    $versionOutput = & node $indexJs --version 2>&1
    Write-Info "Installed: $versionOutput"

    # ── Summary ──────────────────────────────────────────────────────────────

    Write-Heading 'Installation complete'
    Write-Host ''
    Write-Host "  Entry point: $indexJs" -ForegroundColor White
    Write-Host ''
    Write-Host '  MCP config example (single org):' -ForegroundColor White
    Write-Host ''
    Write-Host '    "azure-devops": {' -ForegroundColor Green
    Write-Host '      "type": "stdio",' -ForegroundColor Green
    Write-Host '      "command": "node",' -ForegroundColor Green
    Write-Host '      "args": [' -ForegroundColor Green
    Write-Host "        `"$($indexJs.Replace('\','\\'))`"," -ForegroundColor Green
    Write-Host '        "${env:AZDO_ORG}",' -ForegroundColor Green
    Write-Host '        "--authentication", "envvar",' -ForegroundColor Green
    Write-Host '        "-d", "core", "work", "work-items"' -ForegroundColor Green
    Write-Host '      ],' -ForegroundColor Green
    Write-Host '      "env": {' -ForegroundColor Green
    Write-Host '        "ADO_MCP_AUTH_TOKEN": "${env:AZDO_PAT}",' -ForegroundColor Green
    Write-Host '        "ADO_MCP_ORG_URL": "${env:AZDO_URL}/${env:AZDO_ORG}"' -ForegroundColor Green
    Write-Host '      }' -ForegroundColor Green
    Write-Host '    }' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Required environment variables:' -ForegroundColor White
    Write-Host '    AZDO_ORG  - Azure DevOps organization name' -ForegroundColor DarkGray
    Write-Host '    AZDO_PAT  - Personal Access Token' -ForegroundColor DarkGray
    Write-Host '    AZDO_URL  - Server URL (only for self-hosted, omit for dev.azure.com)' -ForegroundColor DarkGray
    Write-Host ''
    Write-Info 'Done.'
}
finally {
    Pop-Location
}
