<#
.SYNOPSIS
    Enables or disables local git tracking for selected repository folders.

.DESCRIPTION
    Supports `.ai`, `.github`, `.roo`, and `.cline`.

    Disable mode applies two local-only changes:
    - adds entries to `.git/info/exclude` so new untracked files are ignored
    - marks tracked files with `git update-index --skip-worktree`

    Enable mode removes the local exclude entries and clears `skip-worktree`.

    If no action is supplied, the script opens an interactive menu.
    The script can be launched from any working directory because it resolves
    the repository root from its own location under `.ai/scripts`.

.PARAMETER Action
    Disable, Enable, or Status. If omitted, an interactive menu is shown.

.PARAMETER Target
    All, `.ai`, `.github`, `.roo`, or `.cline`. Defaults to All.

.EXAMPLE
    .\.ai\scripts\Set-GitTracking-AgentFolders.ps1

.EXAMPLE
    .\.ai\scripts\Set-GitTracking-AgentFolders.ps1 -Action Disable -Target .ai

.EXAMPLE
    .\.ai\scripts\Set-GitTracking-AgentFolders.ps1 -Action Enable -Target All
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Disable', 'Enable', 'Status')]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', '.ai', '.github', '.roo', '.cline')]
    [string]$Target = 'All'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$aiDirectory = Join-Path $repoRoot '.ai'
$gitDirectory = Join-Path $repoRoot '.git'
$excludeFilePath = Join-Path (Join-Path $gitDirectory 'info') 'exclude'
$managedFolderNames = @('.ai', '.github', '.roo', '.cline')
$excludeMarkerStart = '# >>> local-git-tracking-managed-folders >>>'
$excludeMarkerEnd = '# <<< local-git-tracking-managed-folders <<<'

function Test-Preconditions {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is not installed or not available in PATH.'
    }

    if (-not (Test-Path -LiteralPath $repoRoot -PathType Container)) {
        throw "Repository root was not found: $repoRoot"
    }

    if (-not (Test-Path -LiteralPath $gitDirectory -PathType Container)) {
        throw "Git directory was not found: $gitDirectory"
    }

    if (-not (Test-Path -LiteralPath $aiDirectory -PathType Container)) {
        throw ".ai directory was not found: $aiDirectory"
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git -C $repoRoot @Arguments 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git -C `"$repoRoot`" $($Arguments -join ' ')`n$output"
    }

    return @($output)
}

function Get-OrderedManagedFolderNames {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$FolderNames = @()
    )

    return @($managedFolderNames | Where-Object { $FolderNames -contains $_ })
}

function Get-SelectedFolderNames {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Selection
    )

    if ($Selection -eq 'All') {
        return @($managedFolderNames)
    }

    return @($Selection)
}

function Get-ExcludeSegments {
    if (-not (Test-Path -LiteralPath $excludeFilePath -PathType Leaf)) {
        return [PSCustomObject]@{
            Lines = @()
            StartIndex = -1
            EndIndex = -1
        }
    }

    $lines = @(Get-Content -LiteralPath $excludeFilePath)
    $startMatches = New-Object 'System.Collections.Generic.List[int]'
    $endMatches = New-Object 'System.Collections.Generic.List[int]'

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $trimmedLine = $lines[$index].Trim()

        if ($trimmedLine -eq $excludeMarkerStart) {
            $startMatches.Add($index)
            continue
        }

        if ($trimmedLine -eq $excludeMarkerEnd) {
            $endMatches.Add($index)
        }
    }

    if ($startMatches.Count -gt 1 -or $endMatches.Count -gt 1) {
        throw "Managed block in $excludeFilePath contains duplicate markers."
    }

    if ($startMatches.Count -ne $endMatches.Count) {
        throw "Managed block in $excludeFilePath is malformed."
    }

    $startIndex = -1
    $endIndex = -1

    if ($startMatches.Count -eq 1) {
        $startIndex = $startMatches[0]
        $endIndex = $endMatches[0]

        if ($endIndex -lt $startIndex) {
            throw "Managed block in $excludeFilePath is malformed."
        }
    }

    return [PSCustomObject]@{
        Lines = $lines
        StartIndex = $startIndex
        EndIndex = $endIndex
    }
}

function Get-ManagedExcludedFolders {
    $segments = Get-ExcludeSegments

    if ($segments.StartIndex -lt 0) {
        return @()
    }

    $folders = New-Object 'System.Collections.Generic.List[string]'

    for ($index = $segments.StartIndex + 1; $index -lt $segments.EndIndex; $index++) {
        $trimmedLine = $segments.Lines[$index].Trim()

        if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
            continue
        }

        $folderName = $trimmedLine.Trim('/')

        if ($managedFolderNames -contains $folderName) {
            $folders.Add($folderName)
        }
    }

    return @(Get-OrderedManagedFolderNames -FolderNames $folders.ToArray())
}

function Set-ManagedExcludedFolders {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$FolderNames = @()
    )

    $segments = Get-ExcludeSegments
    $orderedFolderNames = @(Get-OrderedManagedFolderNames -FolderNames $FolderNames)
    $updatedLines = New-Object 'System.Collections.Generic.List[string]'

    if ($segments.StartIndex -ge 0) {
        if ($segments.StartIndex -gt 0) {
            foreach ($line in $segments.Lines[0..($segments.StartIndex - 1)]) {
                $updatedLines.Add($line)
            }
        }
    }
    else {
        foreach ($line in $segments.Lines) {
            $updatedLines.Add($line)
        }
    }

    if ($orderedFolderNames.Count -gt 0) {
        if ($updatedLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($updatedLines[$updatedLines.Count - 1])) {
            $updatedLines.Add('')
        }

        $updatedLines.Add($excludeMarkerStart)

        foreach ($folderName in $orderedFolderNames) {
            $updatedLines.Add("/$folderName/")
        }

        $updatedLines.Add($excludeMarkerEnd)
    }

    if ($segments.StartIndex -ge 0 -and $segments.EndIndex + 1 -lt $segments.Lines.Count) {
        if (
            $orderedFolderNames.Count -gt 0 -and
            $updatedLines.Count -gt 0 -and
            -not [string]::IsNullOrWhiteSpace($segments.Lines[$segments.EndIndex + 1])
        ) {
            $updatedLines.Add('')
        }

        foreach ($line in $segments.Lines[($segments.EndIndex + 1)..($segments.Lines.Count - 1)]) {
            $updatedLines.Add($line)
        }
    }

    $excludeDirectory = Split-Path -Path $excludeFilePath -Parent

    if (-not (Test-Path -LiteralPath $excludeDirectory -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($excludeDirectory, 'Create exclude directory')) {
            New-Item -ItemType Directory -Path $excludeDirectory | Out-Null
        }
    }

    if ($PSCmdlet.ShouldProcess($excludeFilePath, 'Write managed exclude entries')) {
        Set-Content -LiteralPath $excludeFilePath -Value $updatedLines -Encoding UTF8
    }
}

function Update-ManagedExcludedFolders {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Disable', 'Enable')]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string[]]$FolderNames
    )

    $currentFolders = @(Get-ManagedExcludedFolders)

    if ($Mode -eq 'Disable') {
        $foldersToManage = @($currentFolders + $FolderNames)
    }
    else {
        $foldersToManage = @($currentFolders | Where-Object { $FolderNames -notcontains $_ })
    }

    $updatedFolders = @(Get-OrderedManagedFolderNames -FolderNames $foldersToManage)

    Set-ManagedExcludedFolders -FolderNames $updatedFolders

    return $updatedFolders
}

function Get-TrackedFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$FolderNames
    )

    $trackedFiles = Invoke-Git -Arguments (@('ls-files', '--') + $FolderNames)

    return @($trackedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-SkipWorktreeFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$FolderNames
    )

    $taggedFiles = Invoke-Git -Arguments (@('ls-files', '-t', '--') + $FolderNames)
    $skipWorktreeFiles = New-Object 'System.Collections.Generic.List[string]'

    foreach ($line in $taggedFiles) {
        if ($line -match '^(?<tag>\S)\s+(?<path>.+)$' -and $Matches['tag'] -eq 'S') {
            $skipWorktreeFiles.Add($Matches['path'])
        }
    }

    return @($skipWorktreeFiles)
}

function Update-SkipWorktreeState {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Disable', 'Enable')]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string[]]$Files
    )

    if ($Files.Count -eq 0) {
        return 0
    }

    $switch = if ($Mode -eq 'Disable') { '--skip-worktree' } else { '--no-skip-worktree' }
    $actionDescription = if ($Mode -eq 'Disable') {
        'Mark tracked files as skip-worktree'
    }
    else {
        'Clear skip-worktree from tracked files'
    }

    if (-not $PSCmdlet.ShouldProcess("$($Files.Count) tracked file(s)", $actionDescription)) {
        return 0
    }

    $batchSize = 200

    for ($index = 0; $index -lt $Files.Count; $index += $batchSize) {
        $batch = @($Files | Select-Object -Skip $index -First $batchSize)
        [void](Invoke-Git -Arguments (@('update-index', $switch, '--') + $batch))
    }

    return $Files.Count
}

function Format-FolderList {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$FolderNames = @()
    )

    if ($FolderNames.Count -eq 0) {
        return '<none>'
    }

    return ($FolderNames -join ', ')
}

function Show-Status {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$FolderNames
    )

    $excludedFolders = @(Get-ManagedExcludedFolders)
    $statusRows = foreach ($folderName in (Get-OrderedManagedFolderNames -FolderNames $FolderNames)) {
        $fullPath = Join-Path $repoRoot $folderName
        $trackedFiles = @(Get-TrackedFiles -FolderNames @($folderName))
        $skipWorktreeFiles = @(Get-SkipWorktreeFiles -FolderNames @($folderName))

        [PSCustomObject]@{
            Folder = $folderName
            Exists = Test-Path -LiteralPath $fullPath -PathType Container
            UntrackedIgnored = $excludedFolders -contains $folderName
            TrackedFiles = $trackedFiles.Count
            SkipWorktreeFiles = $skipWorktreeFiles.Count
        }
    }

    Write-Host ''
    Write-Host "Repository root: $repoRoot"
    Write-Host "AI folder      : $aiDirectory"
    Write-Host "Exclude file   : $excludeFilePath"
    Write-Host ''
    $statusRows | Format-Table -AutoSize
}

function Read-SingleFolderFromMenu {
    while ($true) {
        Write-Host ''
        Write-Host '1. .ai'
        Write-Host '2. .github'
        Write-Host '3. .roo'
        Write-Host '4. .cline'

        $selection = (Read-Host 'Choose a folder').Trim()

        switch ($selection) {
            '1' { return @('.ai') }
            '2' { return @('.github') }
            '3' { return @('.roo') }
            '4' { return @('.cline') }
            default { Write-Warning 'Invalid selection.' }
        }
    }
}

function Invoke-SelectedAction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Disable', 'Enable', 'Status')]
        [string]$SelectedAction,

        [Parameter(Mandatory = $true)]
        [string[]]$SelectedFolderNames
    )

    $orderedFolderNames = @(Get-OrderedManagedFolderNames -FolderNames $SelectedFolderNames)

    switch ($SelectedAction) {
        'Disable' {
            $trackedFiles = @(Get-TrackedFiles -FolderNames $orderedFolderNames)
            $updatedTrackedFileCount = Update-SkipWorktreeState -Mode 'Disable' -Files $trackedFiles
            $updatedExcludedFolders = @(Update-ManagedExcludedFolders -Mode 'Disable' -FolderNames $orderedFolderNames)

            Write-Host ''
            Write-Host "Disabled local git tracking for: $(Format-FolderList -FolderNames $orderedFolderNames)"
            Write-Host "Tracked files updated          : $updatedTrackedFileCount"
            Write-Host "Exclude entries managed       : $(Format-FolderList -FolderNames $updatedExcludedFolders)"
            Show-Status -FolderNames $orderedFolderNames
            return
        }

        'Enable' {
            $trackedFiles = @(Get-TrackedFiles -FolderNames $orderedFolderNames)
            $updatedTrackedFileCount = Update-SkipWorktreeState -Mode 'Enable' -Files $trackedFiles
            $updatedExcludedFolders = @(Update-ManagedExcludedFolders -Mode 'Enable' -FolderNames $orderedFolderNames)

            Write-Host ''
            Write-Host "Enabled local git tracking for: $(Format-FolderList -FolderNames $orderedFolderNames)"
            Write-Host "Tracked files updated         : $updatedTrackedFileCount"
            Write-Host "Exclude entries remaining    : $(Format-FolderList -FolderNames $updatedExcludedFolders)"
            Show-Status -FolderNames $orderedFolderNames
            return
        }

        'Status' {
            Show-Status -FolderNames $orderedFolderNames
            return
        }
    }
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host "Repository root: $repoRoot"
        Write-Host "AI folder      : $aiDirectory"
        Write-Host ''
        Write-Host '1. Disable local git tracking for all managed folders'
        Write-Host '2. Enable local git tracking for all managed folders'
        Write-Host '3. Show status for all managed folders'
        Write-Host '4. Disable local git tracking for one folder'
        Write-Host '5. Enable local git tracking for one folder'
        Write-Host '6. Show status for one folder'
        Write-Host '0. Exit'

        $selection = (Read-Host 'Select an option').Trim()

        switch ($selection) {
            '1' {
                Invoke-SelectedAction -SelectedAction 'Disable' -SelectedFolderNames $managedFolderNames
                return
            }

            '2' {
                Invoke-SelectedAction -SelectedAction 'Enable' -SelectedFolderNames $managedFolderNames
                return
            }

            '3' {
                Invoke-SelectedAction -SelectedAction 'Status' -SelectedFolderNames $managedFolderNames
                return
            }

            '4' {
                Invoke-SelectedAction -SelectedAction 'Disable' -SelectedFolderNames (Read-SingleFolderFromMenu)
                return
            }

            '5' {
                Invoke-SelectedAction -SelectedAction 'Enable' -SelectedFolderNames (Read-SingleFolderFromMenu)
                return
            }

            '6' {
                Invoke-SelectedAction -SelectedAction 'Status' -SelectedFolderNames (Read-SingleFolderFromMenu)
                return
            }

            '0' {
                return
            }

            default {
                Write-Warning 'Invalid selection.'
            }
        }
    }
}

Test-Preconditions

if (-not $PSBoundParameters.ContainsKey('Action')) {
    Show-Menu
    exit 0
}

$selectedFolderNames = Get-SelectedFolderNames -Selection $Target
Invoke-SelectedAction -SelectedAction $Action -SelectedFolderNames $selectedFolderNames
