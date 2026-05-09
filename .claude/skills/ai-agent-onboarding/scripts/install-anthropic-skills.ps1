<#
.SYNOPSIS
Downloads Anthropic community skills into global and/or project skill folders.

.DESCRIPTION
Reads install-anthropic-skills.json and installs skills from
https://github.com/anthropics/skills into:
  - .ai/.global/skills/  (global tier)
  - .ai/skills/          (project tier)

.PARAMETER RepoRoot
Override the repository root. Defaults to the working directory.

.PARAMETER Tier
Install only 'global', only 'project', or 'all' (default).

.PARAMETER DryRun
If set, shows what would be installed without copying files.

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-anthropic-skills.ps1

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-anthropic-skills.ps1 -Tier global -DryRun
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
$configPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install-anthropic-skills.json'

Write-Host 'Anthropic Community Skills installer' -ForegroundColor Cyan
Write-Host "Source: https://github.com/anthropics/skills" -ForegroundColor Gray
Write-Host ''

Install-SkillsFromConfig -ConfigPath $configPath -RepoRoot $RepoRoot -Tier $Tier -DryRun:$DryRun
