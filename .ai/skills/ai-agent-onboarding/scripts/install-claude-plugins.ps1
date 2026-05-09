<#
.SYNOPSIS
Installs Claude Code plugins listed in install-claude-plugins.json via the
'claude plugin' CLI.

.DESCRIPTION
Reads ../install-claude-plugins.json and runs:
  - 'claude plugin marketplace add <source>' for each marketplace
  - 'claude plugin install <plugin>'         for each plugin

Plugins install at user (global) scope so they're picked up by every Claude
Code host — standalone CLI, VS Code native extension, JetBrains plugin, etc.

After install, restart all VS Code / JetBrains / CLI sessions so the host
re-scans ~/.claude/plugins/.

.PARAMETER ConfigPath
Path to the JSON config. Defaults to install-claude-plugins.json next to this
script's parent folder.

.PARAMETER DryRun
Print what would run without executing.

.PARAMETER ClaudeCommand
Override the path/name of the Claude Code CLI. Defaults to 'claude' (must be on
PATH).

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-claude-plugins.ps1

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-claude-plugins.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [string]$ConfigPath,

    [switch]$DryRun,

    [string]$ClaudeCommand = 'claude'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfigPath) {
    $ConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install-claude-plugins.json'
}

Write-Host 'Claude Code plugin installer' -ForegroundColor Cyan
Write-Host "Config: $ConfigPath" -ForegroundColor Gray

# Verify CLI is available.
$claude = Get-Command $ClaudeCommand -ErrorAction SilentlyContinue
if (-not $claude) {
    throw "Claude Code CLI '$ClaudeCommand' not found on PATH. Install it (npm install -g @anthropic-ai/claude-code) or pass -ClaudeCommand <path>."
}

$versionOutput = & $ClaudeCommand --version 2>&1
Write-Host "CLI: $($claude.Source)  ($versionOutput)" -ForegroundColor Gray
Write-Host ''

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$marketplaces = @()
if ($config.PSObject.Properties.Name -contains 'marketplaces' -and $config.marketplaces) {
    $marketplaces = @($config.marketplaces)
}

$plugins = @()
if ($config.PSObject.Properties.Name -contains 'plugins' -and $config.plugins) {
    $plugins = @($config.plugins)
}

Write-Host "Marketplaces to add: $($marketplaces.Count)"
Write-Host "Plugins to install:  $($plugins.Count)"
Write-Host ''

function Invoke-Claude {
    param([string[]]$Arguments)

    $display = "$ClaudeCommand " + ($Arguments -join ' ')
    if ($DryRun) {
        Write-Host "  [DRY RUN] $display" -ForegroundColor Yellow
        return $true
    }

    Write-Host "  > $display" -ForegroundColor Gray
    $output = & $ClaudeCommand @Arguments 2>&1
    $exit = $LASTEXITCODE
    foreach ($line in $output) { Write-Host "    $line" }
    return ($exit -eq 0)
}

function Get-InstalledPluginNames {
    $output = & $ClaudeCommand plugin list 2>&1 | Out-String
    $names = New-Object System.Collections.Generic.HashSet[string]
    # Each enabled entry looks like: "  > skill-creator@claude-plugins-official"
    foreach ($line in ($output -split "`r?`n")) {
        if ($line -match '^\s*>\s*([A-Za-z0-9._-]+)@([A-Za-z0-9._-]+)\s*$') {
            $null = $names.Add("$($Matches[1])@$($Matches[2])".ToLower())
            $null = $names.Add($Matches[1].ToLower())  # also match short form (no @marketplace)
        }
    }
    return $names
}

function Test-PluginInstalled {
    param([string]$PluginSpec, [System.Collections.Generic.HashSet[string]]$Installed)
    if (-not $Installed) { return $false }
    return $Installed.Contains($PluginSpec.ToLower())
}

# ── Marketplaces ────────────────────────────────────────────────────────────
if ($marketplaces.Count -gt 0) {
    Write-Host '── Adding marketplaces ──' -ForegroundColor Cyan
    foreach ($mp in $marketplaces) {
        if (-not $mp) { continue }
        $ok = Invoke-Claude -Arguments @('plugin', 'marketplace', 'add', $mp)
        if (-not $ok) {
            Write-Host "  WARNING: marketplace add failed (may already exist): $mp" -ForegroundColor Yellow
        }
    }
    Write-Host ''
}

# ── Plugins ─────────────────────────────────────────────────────────────────
if ($plugins.Count -gt 0) {
    Write-Host '── Installing plugins ──' -ForegroundColor Cyan

    $alreadyInstalled = $null
    if (-not $DryRun) { $alreadyInstalled = Get-InstalledPluginNames }

    $installed = 0
    $skipped = 0
    $failed = @()
    foreach ($p in $plugins) {
        if (-not $p) { continue }
        if ((-not $DryRun) -and (Test-PluginInstalled -PluginSpec $p -Installed $alreadyInstalled)) {
            Write-Host "  - skip (already installed): $p" -ForegroundColor DarkGray
            $skipped++
            continue
        }
        $ok = Invoke-Claude -Arguments @('plugin', 'install', $p)
        if ($ok) {
            $installed++
        } else {
            # EACCES on cache rm = plugin's MCP server / hooks are running. Not fatal: install state is intact.
            $failed += $p
        }
    }
    Write-Host ''
    Write-Host "Installed: $installed | Already present: $skipped | Failed: $($failed.Count)" -ForegroundColor Green
    if ($failed.Count -gt 0) {
        Write-Host "Failed (may be running plugins — restart Claude Code hosts and retry):" -ForegroundColor Yellow
        foreach ($f in $failed) { Write-Host "  - $f" -ForegroundColor Yellow }
    }
}

Write-Host ''
Write-Host 'Restart all Claude Code hosts (CLI sessions, VS Code windows, JetBrains IDEs) so they re-scan ~/.claude/plugins/.' -ForegroundColor Yellow

if (-not $DryRun) {
    Write-Host ''
    Write-Host '── Currently installed ──' -ForegroundColor Cyan
    & $ClaudeCommand plugin list

    Write-Host ''
    Write-Host '── MCP server runtime validation ──' -ForegroundColor Cyan

    # Map of well-known runtime commands to install hints.
    $runtimeHints = @{
        'bun'    = 'winget install Oven-sh.Bun  (or run install-bun.ps1)'
        'node'   = 'winget install OpenJS.NodeJS  (or install-node.ps1 if added)'
        'python' = 'winget install Python.Python.3  (or run install-python.ps1)'
        'uv'     = 'winget install astral-sh.uv'
        'deno'   = 'winget install DenoLand.Deno'
        'npx'    = 'install Node.js (provides npx)'
        'uvx'    = 'install uv (provides uvx)'
        'dotnet' = 'install .NET SDK'
    }

    $cacheRoot = Join-Path $env:USERPROFILE '.claude\plugins\cache'
    $missing = @()

    if (Test-Path -LiteralPath $cacheRoot) {
        # Recursive search for .mcp.json under each plugin cache.
        $mcpFiles = Get-ChildItem -LiteralPath $cacheRoot -Recurse -Filter '.mcp.json' -File -ErrorAction SilentlyContinue
        foreach ($mcpFile in $mcpFiles) {
            try {
                $mcp = Get-Content -LiteralPath $mcpFile.FullName -Raw | ConvertFrom-Json
            } catch {
                Write-Host "  WARN: cannot parse $($mcpFile.FullName)" -ForegroundColor Yellow
                continue
            }
            if (-not $mcp.PSObject.Properties.Name -contains 'mcpServers' -or -not $mcp.mcpServers) { continue }

            # Plugin path under cache: <plugin author>/<plugin name>/<version>/.mcp.json
            $rel = $mcpFile.FullName.Substring($cacheRoot.Length).TrimStart('\','/')
            $pluginLabel = ($rel -split '[\\/]')[0..1] -join '/'

            foreach ($serverName in $mcp.mcpServers.PSObject.Properties.Name) {
                $cmd = $mcp.mcpServers.$serverName.command
                if (-not $cmd) { continue }
                $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($cmd)
                $found = Get-Command $cmd -ErrorAction SilentlyContinue
                if ($found) {
                    Write-Host "  [OK]   $pluginLabel -> $serverName (command: $cmd)" -ForegroundColor Green
                } else {
                    $hint = if ($runtimeHints.ContainsKey($cmdName.ToLower())) { $runtimeHints[$cmdName.ToLower()] } else { 'unknown command — check plugin docs' }
                    Write-Host "  [FAIL] $pluginLabel -> $serverName : '$cmd' not on PATH" -ForegroundColor Red
                    Write-Host "         hint: $hint" -ForegroundColor Yellow
                    $missing += [pscustomobject]@{
                        Plugin = $pluginLabel
                        Server = $serverName
                        Command = $cmd
                        Hint = $hint
                    }
                }
            }
        }
    }

    Write-Host ''
    if ($missing.Count -eq 0) {
        Write-Host 'All MCP server runtimes resolved.' -ForegroundColor Green
    } else {
        Write-Host "Missing runtimes: $($missing.Count). Install the listed runtimes, then restart all Claude Code hosts." -ForegroundColor Yellow
    }
}
