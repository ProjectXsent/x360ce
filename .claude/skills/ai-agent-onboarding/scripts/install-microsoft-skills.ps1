<#
.SYNOPSIS
Downloads Microsoft skills into global and/or project skill folders.

.DESCRIPTION
Reads install-microsoft-skills.json and installs skills from
https://github.com/microsoft/skills into:
  - .ai/.global/skills/  (global tier)
  - .ai/skills/          (project tier)

Microsoft skills come from two locations in the repo:
  - .github/skills/{name}/           (core skills)
  - .github/plugins/{plugin}/skills/ (plugin-wrapped — same SKILL.md format)

Both use standard SKILL.md format and are copied as-is.

.PARAMETER RepoRoot
Override the repository root. Defaults to the working directory.

.PARAMETER Tier
Install only 'global', only 'project', or 'all' (default).

.PARAMETER DryRun
If set, shows what would be installed without copying files.

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-microsoft-skills.ps1

.EXAMPLE
.\.ai\skills\ai-agent-onboarding\scripts\install-microsoft-skills.ps1 -Tier global -DryRun
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
$configPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install-microsoft-skills.json'

Write-Host 'Microsoft Skills installer' -ForegroundColor Cyan
Write-Host "Source: https://github.com/microsoft/skills" -ForegroundColor Gray
Write-Host ''

Install-SkillsFromConfig -ConfigPath $configPath -RepoRoot $RepoRoot -Tier $Tier -DryRun:$DryRun
