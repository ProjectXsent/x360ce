<#
.SYNOPSIS
Shared functions for skill installation scripts.

.DESCRIPTION
Provides `Install-SkillsFromConfig` which reads a JSON config file
and installs skills from a GitHub repository into global and/or
project-level skill folders.

Config JSON format:
{
  "source": {
    "organisation": "microsoft",
    "repo": "skills",
    "branch": "main"
  },
  "global": [
    { "skill": "run-tests", "path": "skills/dotnet/general/run-tests" },
    { "skill": "azure-deploy", "path": ".github/plugins/azure-skills/skills/azure-deploy" }
  ],
  "project": [
    { "skill": "repository-analysis", "path": "skills/repository-analysis" }
  ]
}

- "global" skills are installed to .ai/.global/skills/{skill}/
- "project" skills are installed to .ai/skills/{skill}/
- "path" is the folder path inside the cloned repo (relative to repo root).
  If omitted, defaults to "skills/{skill}".
- Both arrays are optional (empty = skip that tier).

.NOTES
Dot-source this file, then call Install-SkillsFromConfig.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Helpers ------------------------------------------------------------------

function Write-SkillInfo {
    param([Parameter(Mandatory)][string]$Prefix, [Parameter(Mandatory)][string]$Message)
    Write-Host "[$Prefix] $Message" -ForegroundColor Cyan
}

function Write-SkillHeading {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "  $Message" -ForegroundColor Yellow
    Write-Host ('  ' + ('-' * $Message.Length)) -ForegroundColor DarkYellow
}

function Assert-Git {
    try {
        $null = git --version 2>$null
    }
    catch {
        throw 'Git is not available on PATH. Please run install-git.ps1 first (and restart VS Code if Git was freshly installed).'
    }
}

# -- Main function ------------------------------------------------------------

function Install-SkillsFromConfig {
    <#
    .SYNOPSIS
    Reads a JSON config and installs skills from a GitHub repo.

    .PARAMETER ConfigPath
    Path to the JSON config file.

    .PARAMETER RepoRoot
    The repository root where .ai/ lives. Defaults to the working directory.

    .PARAMETER Tier
    Install only 'global', only 'project', or 'all' (default).

    .PARAMETER DryRun
    If set, shows what would be installed without copying files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter()]
        [string]$RepoRoot = (Get-Location).Path,

        [Parameter()]
        [ValidateSet('all', 'global', 'project')]
        [string]$Tier = 'all',

        [Parameter()]
        [switch]$DryRun
    )

    Assert-Git

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $config = Get-Content -Raw $ConfigPath | ConvertFrom-Json
    $src = $config.source

    $label = "$($src.organisation)/$($src.repo)"
    Write-SkillHeading "Installing skills from $label"

    # Resolve target directories
    $globalRoot  = Join-Path $RepoRoot '.ai\.global\skills'
    $projectRoot = Join-Path $RepoRoot '.ai\skills'

    # Collect items to install
    $globalItems  = @()
    $projectItems = @()

    if ($config.PSObject.Properties['global'] -and $config.global -and ($Tier -in 'all', 'global')) {
        $globalItems = @($config.global)
    }
    if ($config.PSObject.Properties['project'] -and $config.project -and ($Tier -in 'all', 'project')) {
        $projectItems = @($config.project)
    }

    $totalCount = $globalItems.Count + $projectItems.Count
    if ($totalCount -eq 0) {
        Write-SkillInfo $label "No skills to install for tier '$Tier'."
        return
    }

    Write-SkillInfo $label "Global: $($globalItems.Count) skill(s), Project: $($projectItems.Count) skill(s)"

    if ($DryRun) {
        Write-Host ''
        Write-Host '  [DRY RUN] Would install:' -ForegroundColor Magenta
        foreach ($item in $globalItems)  { Write-Host "    GLOBAL:  $($item.skill)" -ForegroundColor Gray }
        foreach ($item in $projectItems) { Write-Host "    PROJECT: $($item.skill)" -ForegroundColor Gray }
        return
    }

    # Clone the repo (shallow)
    $branch = if ($src.PSObject.Properties['branch'] -and $src.branch) { $src.branch } else { 'main' }
    $repoUrl = "https://github.com/$($src.organisation)/$($src.repo)"
    $tmpDir = Join-Path $env:TEMP ("$($src.repo)-" + [guid]::NewGuid().ToString())

    Write-SkillInfo $label "Cloning $repoUrl (shallow, branch: $branch)..."
    git clone --depth 1 --branch $branch $repoUrl $tmpDir 2>&1 | Out-Null

    try {
        $script:installed = 0
        $script:skipped   = 0

        # -- Helper: install one skill ----------------------------------------
        function Install-OneSkill {
            param(
                [Parameter(Mandatory)][object]$Item,
                [Parameter(Mandatory)][string]$DestRoot,
                [Parameter(Mandatory)][string]$TierLabel
            )

            $skillName = $Item.skill
            $repoPath  = if ($Item.PSObject.Properties['path'] -and $Item.path) {
                $Item.path
            } else {
                "skills/$skillName"
            }

            $srcPath = Join-Path $tmpDir $repoPath

            if (-not (Test-Path $srcPath -PathType Container)) {
                Write-Host "  SKIP: $skillName ($TierLabel) - not found at $repoPath" -ForegroundColor Yellow
                $script:skipped++
                return
            }

            # Verify it has a SKILL.md (standard format)
            $skillMd = Join-Path $srcPath 'SKILL.md'
            if (-not (Test-Path $skillMd)) {
                Write-Host "  WARN: $skillName ($TierLabel) - no SKILL.md found, copying anyway" -ForegroundColor Yellow
            }

            # Ensure target root exists
            if (-not (Test-Path $DestRoot -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $DestRoot | Out-Null
            }

            $dstPath = Join-Path $DestRoot $skillName

            # Remove existing and replace
            if (Test-Path $dstPath) {
                Remove-Item -Recurse -Force $dstPath -ErrorAction SilentlyContinue
            }

            Copy-Item -Recurse -Force $srcPath $dstPath
            Write-Host "  OK: $skillName ($TierLabel)" -ForegroundColor Green
            $script:installed++
        }

        # -- Install global skills -------------------------------------------
        foreach ($item in $globalItems) {
            Install-OneSkill -Item $item -DestRoot $globalRoot -TierLabel 'global'
        }

        # -- Install project skills ------------------------------------------
        foreach ($item in $projectItems) {
            Install-OneSkill -Item $item -DestRoot $projectRoot -TierLabel 'project'
        }

        # -- Summary ----------------------------------------------------------
        Write-Host ''
        Write-Host "  Installed: $script:installed skill(s)" -ForegroundColor Green
        if ($script:skipped -gt 0) {
            Write-Host "  Skipped: $script:skipped skill(s) (not found in source repo)" -ForegroundColor Yellow
        }
    }
    finally {
        if (Test-Path $tmpDir) {
            Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
        }
    }

    Write-Host ''
    Write-SkillInfo $label 'Done.'
}
