<#
.SYNOPSIS
Installs the Playwright MCP server and its browser dependencies.

.DESCRIPTION
Installs `@playwright/mcp` via npm and downloads the required browser
binaries using `npx playwright install`. The MCP server is then
launched on demand via `npx @playwright/mcp@latest`.

Optionally installs the Playwright Test runner (`@playwright/test`)
for UI mode testing (`npx playwright test --ui`).

.PARAMETER Browser
Optional. Default browser channel: 'msedge', 'chrome', 'chromium',
'firefox', or 'webkit'. Defaults to 'msedge' (recommended on Windows).

.PARAMETER SkipTest
Optional. If set, skips installing @playwright/test.

.EXAMPLE
# Install with defaults (Edge browser, includes test runner)
.\install-playwright-mcp.ps1

# Install with Chrome, skip test runner
.\install-playwright-mcp.ps1 -Browser chrome -SkipTest

.NOTES
- Requires Node.js (LTS) and npm on PATH.
- Idempotent - safe to run again to update to a newer version.
- Does NOT require Administrator rights.
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('msedge', 'chrome', 'chromium', 'firefox', 'webkit', IgnoreCase = $true)]
    [string]$Browser = 'msedge',

    [Parameter(Mandatory = $false)]
    [switch]$SkipTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Helpers ------------------------------------------------------------------

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[Install-PlaywrightMcp] $Message" -ForegroundColor Cyan
}

function Write-Heading {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "  $Message" -ForegroundColor Yellow
    Write-Host ('  ' + ('-' * $Message.Length)) -ForegroundColor DarkYellow
}

# -- Check prerequisites -----------------------------------------------------

Write-Heading 'Checking prerequisites'

$nodeVersion = $null
try {
    $nodeVersion = & node --version 2>&1
    Write-Info "Node.js: $nodeVersion"
} catch {
    Write-Host '  ERROR: Node.js is not installed or not on PATH.' -ForegroundColor Red
    Write-Host '  Install Node.js LTS from https://nodejs.org/ or via:' -ForegroundColor Yellow
    Write-Host '    winget install OpenJS.NodeJS.LTS' -ForegroundColor Yellow
    throw 'Node.js is required but not found.'
}

$npmVersion = $null
try {
    $npmVersion = & npm --version 2>&1
    Write-Info "npm: $npmVersion"
} catch {
    throw 'npm is required but not found on PATH.'
}

# -- Install @playwright/mcp -------------------------------------------------

Write-Heading 'Installing @playwright/mcp'

Write-Info 'Installing @playwright/mcp globally...'
& npm install -g @playwright/mcp@latest 2>&1 | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to install @playwright/mcp.'
}

# -- Install @playwright/test (optional) -------------------------------------

if (-not $SkipTest) {
    Write-Heading 'Installing @playwright/test'

    Write-Info 'Installing @playwright/test globally...'
    & npm install -g @playwright/test@latest 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  WARNING: Failed to install @playwright/test. UI mode will not be available.' -ForegroundColor Yellow
    } else {
        Write-Info '@playwright/test installed. Use: npx playwright test --ui'
    }
}

# -- Install browser ----------------------------------------------------------

Write-Heading "Installing browser: $Browser"

# Map channel names to Playwright install targets
$installTarget = switch ($Browser) {
    'msedge'   { 'msedge' }
    'chrome'   { 'chrome' }
    'chromium' { 'chromium' }
    'firefox'  { 'firefox' }
    'webkit'   { 'webkit' }
    default    { 'msedge' }
}

Write-Info "Running: npx playwright install $installTarget"
& npx playwright install $installTarget 2>&1 | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -ne 0) {
    Write-Host "  WARNING: Browser install returned non-zero exit code. The browser may already be installed." -ForegroundColor Yellow
}

# -- Verify -------------------------------------------------------------------

Write-Heading 'Verifying installation'

Write-Info 'Checking @playwright/mcp...'
try {
    $mcpHelp = & npx @playwright/mcp@latest --help 2>&1 | Select-Object -First 5
    $mcpHelp | ForEach-Object { Write-Host "  $_" }
    Write-Info '@playwright/mcp is available.'
} catch {
    Write-Host '  WARNING: Could not verify @playwright/mcp. It may still work via npx.' -ForegroundColor Yellow
}

# -- Summary ------------------------------------------------------------------

Write-Heading 'Installation complete'
Write-Host ''
Write-Host "  Browser: $Browser" -ForegroundColor White
Write-Host "  MCP command: npx @playwright/mcp@latest --browser $Browser" -ForegroundColor White
if (-not $SkipTest) {
    Write-Host '  UI mode: npx playwright test --ui' -ForegroundColor White
}
Write-Host ''
Write-Host '  MCP config example (RooCode / Cline):' -ForegroundColor White
Write-Host ''
Write-Host '    "playwright": {' -ForegroundColor Green
Write-Host '      "type": "stdio",' -ForegroundColor Green
Write-Host '      "command": "npx",' -ForegroundColor Green
Write-Host "      `"args`": [`"@playwright/mcp@latest`", `"--browser`", `"$Browser`"]," -ForegroundColor Green
Write-Host '      "disabled": false,' -ForegroundColor Green
Write-Host '      "alwaysAllow": []' -ForegroundColor Green
Write-Host '    }' -ForegroundColor Green
Write-Host ''
Write-Host '  Recommended VS Code extensions:' -ForegroundColor White
Write-Host '    - Playwright Test for VSCode (ms-playwright.playwright)' -ForegroundColor White
Write-Host '    - Playwright MCP Bridge extension (for connecting to existing Edge/Chrome)' -ForegroundColor White
Write-Host ''
Write-Info 'Done.'
