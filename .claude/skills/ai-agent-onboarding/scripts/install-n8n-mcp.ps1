<#
.SYNOPSIS
Prepares the n8n-mcp server (by czlonkowski) for first launch via npx.

.DESCRIPTION
n8n-mcp is distributed as an npm package and launched on demand via
`npx -y n8n-mcp`. No global install or per-project tree is required.
This script:

  1. Verifies Node.js and npm are on PATH.
  2. Smoke-tests the current `npx -y n8n-mcp` install. The smoke test
     spawns the MCP server with stdin closed and checks for module
     resolution failures in stderr (e.g. partial installs leaving
     `ajv` missing `_limitProperties`). File-presence checks are
     unreliable: a cache can have package.json + bin shim and still
     fail to load due to a dependency tree corruption deep below.
  3. If the smoke test fails, escalates through three repair stages:
        a) Remove cache directories that contain a partial n8n-mcp
           install AND `npm cache verify` to fix npm content cache.
        b) Pre-warm a fresh install via `npx -y n8n-mcp`.
        c) On second failure, `npm cache clean --force` and retry.
     Each stage re-runs the smoke test to confirm recovery.
  4. Checks that N8N_API_URL and N8N_API_KEY user environment variables
     are present, prompting the user to set them if missing.
  5. Optionally probes /healthz on the configured n8n instance.

.PARAMETER N8nUrl
Optional. Default n8n base URL. Used to populate N8N_API_URL if unset.
Defaults to http://127.0.0.1:5678.

.PARAMETER Probe
Optional. If set, attempts a GET on {N8nUrl}/healthz after setup.

.PARAMETER ForceClean
Optional. Skip the initial smoke test; always start by purging all
n8n-mcp caches and reinstalling.

.EXAMPLE
# Defaults (http://127.0.0.1:5678, no probe)
.\install-n8n-mcp.ps1

# Custom URL and probe the instance is reachable
.\install-n8n-mcp.ps1 -N8nUrl http://localhost:5678 -Probe

# Recover from a known-broken state — start fresh
.\install-n8n-mcp.ps1 -ForceClean

.NOTES
- Requires Node.js LTS and npm on PATH.
- Idempotent — safe to run again.
- Self-healing — re-running fixes broken installs without manual cleanup.
- Does NOT require Administrator rights.
- Source: https://github.com/czlonkowski/n8n-mcp
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$N8nUrl = 'http://127.0.0.1:5678',

    [Parameter(Mandatory = $false)]
    [switch]$Probe,

    [Parameter(Mandatory = $false)]
    [switch]$ForceClean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Helpers ------------------------------------------------------------------

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[Install-N8nMcp] $Message" -ForegroundColor Cyan
}

function Write-Heading {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "  $Message" -ForegroundColor Yellow
    Write-Host ('  ' + ('-' * $Message.Length)) -ForegroundColor DarkYellow
}

function Write-Warn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  WARN: $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  FAIL: $Message" -ForegroundColor Red
}

# Spawn `npx -y n8n-mcp` with stdin closed and capture exit code + stderr.
# Returns a hashtable: @{ Healthy = $bool; ExitCode = <int>; StdErr = <string>; ElapsedSeconds = <int> }
#
# Behavior of n8n-mcp under stdio mode:
#   - If module resolution succeeds: server runs until stdin closes (we close it
#     immediately), then exits 0.
#   - If module resolution fails (partial install, ajv corruption, etc.): node
#     throws synchronously, prints "Error: Cannot find module '<x>'" to stderr,
#     exits non-zero.
#
# This is a real smoke test — file-presence checks miss deep-tree corruption.
#
# Two non-obvious requirements when launching via .NET Process.Start:
#   1. Pass the FULL absolute path to npx.cmd. Bare 'npx.cmd' relies on
#      CreateProcess search rules that, in some environments, route the
#      bootstrap through the wrong directory and fail with a misleading
#      "Cannot find module '<cwd>\node_modules\npm\bin\npm-prefix.js'".
#   2. Set WorkingDirectory to a neutral folder ($env:TEMP). Inheriting cwd
#      from the script can confuse npm's prefix-detection logic when the
#      caller is inside a project tree.
function Invoke-N8nMcpSmokeTest {
    param(
        [Parameter(Mandatory)][string]$NpxPath,
        [int]$TimeoutSeconds = 60,
        [string]$N8nUrl = 'http://127.0.0.1:5678'
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $NpxPath
    $psi.Arguments = '-y n8n-mcp'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $env:TEMP
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['MCP_MODE']                   = 'stdio'
    $psi.EnvironmentVariables['LOG_LEVEL']                  = 'error'
    $psi.EnvironmentVariables['DISABLE_CONSOLE_OUTPUT']     = 'true'
    $psi.EnvironmentVariables['N8N_MCP_TELEMETRY_DISABLED'] = 'true'
    $psi.EnvironmentVariables['N8N_API_URL']                = $N8nUrl
    $psi.EnvironmentVariables['N8N_API_KEY']                = '_smoketest_'

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = $null
    $stderrText = ''
    $exitCode = -1
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        # Closing stdin signals MCP server to exit gracefully when transport closes.
        $proc.StandardInput.Close()

        $stderrTask = $proc.StandardError.ReadToEndAsync()

        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill($true) | Out-Null } catch { }
            $proc.WaitForExit(5000) | Out-Null
        }
        $exitCode = $proc.ExitCode
        try { $stderrText = $stderrTask.GetAwaiter().GetResult() } catch { $stderrText = '' }
    }
    catch {
        $stderrText = "smoke-test launcher exception: $($_.Exception.Message)"
    }
    finally {
        if ($proc) { try { $proc.Dispose() } catch { } }
        $stopwatch.Stop()
    }

    # Heuristic: a healthy install exits 0 with empty/quiet stderr.
    # Module-not-found patterns are conclusive failure markers, even if the
    # exit code happens to be 0 (defensive against future server changes).
    $brokenModule = $stderrText -match 'Cannot find module|MODULE_NOT_FOUND|Cannot read properties of undefined .reading .require'
    $healthy = ($exitCode -eq 0) -and (-not $brokenModule)

    return @{
        Healthy        = $healthy
        ExitCode       = $exitCode
        StdErr         = $stderrText
        BrokenModule   = $brokenModule
        ElapsedSeconds = [int]$stopwatch.Elapsed.TotalSeconds
    }
}

# Remove every npx cache directory that contains a `node_modules\n8n-mcp` folder.
# Returns the number of directories removed.
function Remove-N8nMcpCaches {
    $npxRoot = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
    if (-not (Test-Path -LiteralPath $npxRoot)) { return 0 }

    $removed = 0
    Get-ChildItem -LiteralPath $npxRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $pkgDir = Join-Path $_.FullName 'node_modules\n8n-mcp'
        if (Test-Path -LiteralPath $pkgDir) {
            Write-Info "Removing cache: $($_.FullName)"
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }
    return $removed
}

# Print stderr with sensible truncation for the user.
function Show-StdErr {
    param([string]$StdErr)
    if ([string]::IsNullOrWhiteSpace($StdErr)) {
        Write-Host '    (stderr was empty)' -ForegroundColor DarkGray
        return
    }
    $lines = $StdErr -split "(`r`n|`r|`n)" | Where-Object { $_ -and ($_ -notmatch '^[\s\r\n]*$') }
    $shown = $lines | Select-Object -First 8
    foreach ($line in $shown) { Write-Host "    $line" -ForegroundColor DarkGray }
    if ($lines.Count -gt $shown.Count) {
        Write-Host "    ... ($($lines.Count - $shown.Count) more line(s) suppressed)" -ForegroundColor DarkGray
    }
}

# -- Check prerequisites -----------------------------------------------------

Write-Heading 'Checking prerequisites'

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Fail 'Node.js is not installed or not on PATH.'
    Write-Host '  Install Node.js LTS via:' -ForegroundColor Yellow
    Write-Host '    winget install OpenJS.NodeJS.LTS' -ForegroundColor Yellow
    throw 'Node.js is required but not found.'
}

$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npm) {
    throw 'npm is required but not found on PATH.'
}

Write-Info "Node.js: $(node --version)"
Write-Info "npm:     $(npm --version)"

# Resolve the absolute path to npx.cmd. Process.Start needs the full path so
# the .cmd's `%~dp0` self-reference points at the real Node.js install dir,
# not whichever cwd a child cmd.exe ends up in. Prefer .cmd over .ps1; the
# Get-Command lookup may resolve to npx.ps1 first because PowerShell treats
# .ps1 as a script command type ahead of .cmd in some environments.
$npxCandidates = @(
    (Join-Path (Split-Path -Parent (Get-Command node).Source) 'npx.cmd'),
    (Get-Command npx.cmd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $npxCandidates) {
    throw 'Could not locate npx.cmd. Re-install Node.js and ensure it is on PATH.'
}
$NpxPath = $npxCandidates
Write-Info "npx.cmd: $NpxPath"

# -- Stage 0: smoke-test current state ---------------------------------------

if ($ForceClean) {
    Write-Heading 'Force-clean requested — skipping initial smoke test'
    $stage0Healthy = $false
} else {
    Write-Heading 'Smoke-testing current n8n-mcp install'
    Write-Info 'Spawning npx -y n8n-mcp with stdin closed (timeout 60s)...'
    $stage0 = Invoke-N8nMcpSmokeTest -NpxPath $NpxPath -TimeoutSeconds 60 -N8nUrl $N8nUrl
    $stage0Healthy = $stage0.Healthy
    if ($stage0Healthy) {
        Write-Info "Smoke test passed (exit=$($stage0.ExitCode), $($stage0.ElapsedSeconds)s)."
    } else {
        Write-Warn "Smoke test failed (exit=$($stage0.ExitCode), $($stage0.ElapsedSeconds)s). Stderr:"
        Show-StdErr $stage0.StdErr
    }
}

# -- Stage 1: targeted cache cleanup + verify --------------------------------

if (-not $stage0Healthy) {
    Write-Heading 'Stage 1 — Removing n8n-mcp cache entries and verifying npm cache'
    $removed = Remove-N8nMcpCaches
    if ($removed -eq 0) { Write-Info 'No n8n-mcp cache entries to remove.' }
    else                 { Write-Info "Removed $removed cache entr$(if ($removed -eq 1) {'y'} else {'ies'})." }

    Write-Info 'Running npm cache verify (cleans corrupt content cache; can take ~30s)...'
    $verifyOut = & npm cache verify 2>&1
    $verifyOut | Select-Object -Last 6 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    Write-Heading 'Stage 1 — Pre-warming fresh install'
    Write-Info 'Spawning npx -y n8n-mcp (timeout 180s; downloads on first run)...'
    $stage1 = Invoke-N8nMcpSmokeTest -NpxPath $NpxPath -TimeoutSeconds 180 -N8nUrl $N8nUrl
    $stage1Healthy = $stage1.Healthy
    if ($stage1Healthy) {
        Write-Info "Stage 1 succeeded (exit=$($stage1.ExitCode), $($stage1.ElapsedSeconds)s)."
    } else {
        Write-Warn "Stage 1 failed (exit=$($stage1.ExitCode), $($stage1.ElapsedSeconds)s). Stderr:"
        Show-StdErr $stage1.StdErr
    }
} else {
    $stage1Healthy = $true
}

# -- Stage 2: nuclear option (full npm cache wipe) ---------------------------

if (-not $stage1Healthy) {
    Write-Heading 'Stage 2 — npm cache clean --force and retry'
    Write-Info 'Removing every n8n-mcp cache entry again...'
    Remove-N8nMcpCaches | Out-Null

    Write-Info 'Running npm cache clean --force (wipes the npm content cache)...'
    & npm cache clean --force 2>&1 | Select-Object -Last 4 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    Write-Info 'Spawning npx -y n8n-mcp (timeout 240s)...'
    $stage2 = Invoke-N8nMcpSmokeTest -NpxPath $NpxPath -TimeoutSeconds 240 -N8nUrl $N8nUrl
    $stage2Healthy = $stage2.Healthy
    if ($stage2Healthy) {
        Write-Info "Stage 2 succeeded (exit=$($stage2.ExitCode), $($stage2.ElapsedSeconds)s)."
    } else {
        Write-Fail "Stage 2 failed (exit=$($stage2.ExitCode), $($stage2.ElapsedSeconds)s). Stderr:"
        Show-StdErr $stage2.StdErr
    }
} else {
    $stage2Healthy = $true
}

$mcpHealthy = $stage0Healthy -or $stage1Healthy -or $stage2Healthy

# -- Verify a usable cache entry now exists ----------------------------------

$npxCacheRoot = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
if (Test-Path -LiteralPath $npxCacheRoot) {
    $okCache = Get-ChildItem -LiteralPath $npxCacheRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $shim = Join-Path $_.FullName 'node_modules\.bin\n8n-mcp.cmd'
            Test-Path -LiteralPath $shim
        } | Select-Object -First 1
    if ($okCache) {
        $pj = Join-Path $okCache.FullName 'node_modules\n8n-mcp\package.json'
        $ver = if (Test-Path -LiteralPath $pj) { (Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json).version } else { '(unknown)' }
        Write-Info "Cache entry: $($okCache.FullName) (n8n-mcp v$ver)"
    }
}

# -- Environment variables ---------------------------------------------------

Write-Heading 'Checking environment variables'

$existingUrl = [Environment]::GetEnvironmentVariable('N8N_API_URL', 'User')
if ([string]::IsNullOrWhiteSpace($existingUrl)) {
    Write-Info "Setting N8N_API_URL = $N8nUrl (User scope)"
    [Environment]::SetEnvironmentVariable('N8N_API_URL', $N8nUrl, 'User')
} else {
    Write-Info "N8N_API_URL already set: $existingUrl"
}

$existingKey = [Environment]::GetEnvironmentVariable('N8N_API_KEY', 'User')
if ([string]::IsNullOrWhiteSpace($existingKey)) {
    Write-Host '' -ForegroundColor Yellow
    Write-Host '  N8N_API_KEY is NOT set.' -ForegroundColor Red
    Write-Host '  Create one in n8n: Settings -> n8n API -> Create an API key' -ForegroundColor Yellow
    Write-Host '  Then run:' -ForegroundColor Yellow
    Write-Host "    [Environment]::SetEnvironmentVariable('N8N_API_KEY', '<your-token>', 'User')" -ForegroundColor Yellow
    Write-Host '  Restart all VS Code instances after setting it (terminal PATH/env).' -ForegroundColor Yellow
} else {
    Write-Info 'N8N_API_KEY is set.'
}

# -- Optional health probe ---------------------------------------------------

if ($Probe) {
    Write-Heading "Probing $N8nUrl/healthz"
    try {
        $resp = Invoke-RestMethod -Uri "$N8nUrl/healthz" -TimeoutSec 5
        Write-Info "Health: $($resp | ConvertTo-Json -Compress)"
    }
    catch {
        Write-Warn "Health probe failed: $($_.Exception.Message)"
        Write-Host '  Is n8n running? Start it before launching the MCP host.' -ForegroundColor Yellow
    }
}

# -- Summary -----------------------------------------------------------------

Write-Heading 'Installation complete'

if ($mcpHealthy) {
    Write-Host '  n8n-mcp smoke test PASSED.' -ForegroundColor Green
} else {
    Write-Host '  n8n-mcp smoke test FAILED after all repair stages.' -ForegroundColor Red
    Write-Host '  Manual investigation required. Try:' -ForegroundColor Yellow
    Write-Host '    1. npm install -g n8n-mcp@latest    (use a global install instead of npx cache)' -ForegroundColor Yellow
    Write-Host '    2. Inspect stderr above for the specific module that failed to load.' -ForegroundColor Yellow
    Write-Host '    3. Re-run with -ForceClean to bypass the initial smoke test.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '  MCP config example (RooCode / Claude Code / Cline):' -ForegroundColor White
Write-Host ''
Write-Host '    "n8n-mcp": {' -ForegroundColor Green
Write-Host '      "command": "npx",' -ForegroundColor Green
Write-Host '      "args": ["-y", "n8n-mcp"],' -ForegroundColor Green
Write-Host '      "env": {' -ForegroundColor Green
Write-Host '        "MCP_MODE": "stdio",' -ForegroundColor Green
Write-Host '        "LOG_LEVEL": "error",' -ForegroundColor Green
Write-Host '        "DISABLE_CONSOLE_OUTPUT": "true",' -ForegroundColor Green
Write-Host '        "N8N_MCP_TELEMETRY_DISABLED": "true",' -ForegroundColor Green
Write-Host '        "N8N_API_URL": "${env:N8N_API_URL}",' -ForegroundColor Green
Write-Host '        "N8N_API_KEY": "${env:N8N_API_KEY}"' -ForegroundColor Green
Write-Host '      },' -ForegroundColor Green
Write-Host '      "disabled": false,' -ForegroundColor Green
Write-Host '      "alwaysAllow": []' -ForegroundColor Green
Write-Host '    }' -ForegroundColor Green
Write-Host ''
Write-Host '  Required user environment variables:' -ForegroundColor White
Write-Host '    N8N_API_URL - n8n base URL (e.g. http://127.0.0.1:5678)' -ForegroundColor DarkGray
Write-Host '    N8N_API_KEY - n8n API key created in Settings -> n8n API' -ForegroundColor DarkGray
Write-Host ''

if (-not $mcpHealthy) {
    exit 1
}
Write-Info 'Done.'
