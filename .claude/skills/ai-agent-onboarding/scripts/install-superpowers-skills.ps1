<#
.SYNOPSIS
Downloads Superpowers community skill folders into global and/or project skill folders.

.DESCRIPTION
Reads install-superpowers-skills.json and copies the SKILL.md folders from
https://github.com/obra/superpowers into:
  - .ai/.global/skills/  (global tier)
  - .ai/skills/          (project tier)

Only the portable 'skills/*' folders are copied. The Claude plugin wiring
(.claude-plugin/, commands/, hooks/, agents/) is NOT installed by this script.
For the full Claude plugin, see references/install-claude-extensions.md.

.PARAMETER RepoRoot
Override the repository root. Defaults to the working directory.

.PARAMETER Tier
Install only 'global', only 'project', or 'all' (default).

.PARAMETER DryRun
If set, shows what would be installed without copying files.

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-superpowers-skills.ps1

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-superpowers-skills.ps1 -Tier global -DryRun
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,

    [ValidateSet('all', 'global', 'project')]
    [string]$Tier = 'all',

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load shared functions
. "$PSScriptRoot\install-core.ps1"

# Resolve config path (JSON lives one level up from scripts/)
$configPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install-superpowers-skills.json'

Write-Host 'Superpowers Community Skills installer' -ForegroundColor Cyan
Write-Host "Source: https://github.com/obra/superpowers" -ForegroundColor Gray
Write-Host ''

Install-SkillsFromConfig -ConfigPath $configPath -RepoRoot $RepoRoot -Tier $Tier -DryRun:$DryRun
