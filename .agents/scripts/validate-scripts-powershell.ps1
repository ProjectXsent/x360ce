<#
.SYNOPSIS
	Validates PowerShell scripts (*.ps1) using PSScriptAnalyzer with PS 5.1/7.x compatibility checks.
.DESCRIPTION
	Runs Invoke-ScriptAnalyzer on PowerShell scripts with embedded settings that:
	- Exclude project-specific rules (PSAvoidGlobalVars, PSReviewUnusedParameter,
	  PSAvoidUsingWriteHost, PSUseSingularNouns).
	- Report formatting issues without modifying files by default.
	- Check syntax compatibility with PowerShell 5.1 and 7.0.
	- Check command compatibility across PS 5.1 (Desktop) and PS 7.0 (Core).
	- Check type compatibility across PS 5.1 (Desktop) and PS 7.0 (Core).
.PARAMETER Path
	Optional. Directory path to validate scripts in. Defaults to the Docker setup directory
	(parent of .ai folder).
.PARAMETER FilePattern
	Optional. File pattern to match. Defaults to '*.ps1'.
.PARAMETER FixFormatting
	Optional. Applies PSScriptAnalyzer formatting fixes before validation. Without this
	switch, formatting issues are reported only and files are not modified.
.EXAMPLE
	.\.ai\scripts\validate-scripts-powershell.ps1
	Validates all *.ps1 files in the Docker setup directory without modifying them.
.EXAMPLE
	.\.ai\scripts\validate-scripts-powershell.ps1 -FilePattern "Setup_App_*.ps1"
	Validates only Setup_App_*.ps1 files.
.EXAMPLE
	.\.ai\scripts\validate-scripts-powershell.ps1 -Path "." -FilePattern "Setup_Core_1_WSL2.ps1"
	Validates a specific script file.
.EXAMPLE
	.\.ai\scripts\validate-scripts-powershell.ps1 -Path "." -FilePattern "Setup_Core_1_WSL2.ps1" -FixFormatting
	Applies formatting fixes, then validates a specific script file.
.NOTES
	Ensure PSScriptAnalyzer module is installed: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
#>

param(
	[Parameter(Mandatory = $false)]
	[string]$Path,

	[Parameter(Mandatory = $false)]
	[string]$FilePattern = '*.ps1',

	[Parameter(Mandatory = $false)]
	[switch]$FixFormatting
)

# Get the directory where the script is located
$scriptDir = $PSScriptRoot

# Default to the Docker setup directory (two levels up from .ai/scripts/)
if (-not $Path) {
	$Path = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
}

# Resolve to absolute path if relative
if (-not [System.IO.Path]::IsPathRooted($Path)) {
	$Path = (Resolve-Path $Path).Path
}

Write-Host "Starting script validation in directory: $Path (Pattern: $FilePattern)"

# Get all PowerShell script files in the directory matching pattern
$scriptFiles = Get-ChildItem -Path $Path -Filter $FilePattern -File

if (-not $scriptFiles) {
	Write-Warning "No PowerShell script files found in $Path matching '$FilePattern'."
	exit 0
}

Write-Host "Found $($scriptFiles.Count) script(s) to validate."

# Formatting rules for auto-fix pass
$formatRules = @(
	'PSAvoidTrailingWhitespace',
	'PSUseConsistentWhitespace',
	'PSUseConsistentIndentation',
	'PSPlaceOpenBrace',
	'PSPlaceCloseBrace',
	'AlignAssignmentStatement'
)

# Embedded settings: analysis rules + compatibility checks in a single pass
$analysisSettings = @{
	ExcludeRules = @(
		'PSAvoidGlobalVars'
		'PSReviewUnusedParameter'
		'PSAvoidUsingWriteHost'
		'PSUseSingularNouns'
	)
	Rules        = @{
		PSUseCompatibleSyntax   = @{
			Enable         = $true
			TargetVersions = @('5.1', '7.0')
		}
		PSUseCompatibleCommands = @{
			Enable         = $true
			TargetProfiles = @(
				'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
				'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
			)
		}
		PSUseCompatibleTypes    = @{
			Enable         = $true
			TargetProfiles = @(
				'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
				'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
			)
		}
	}
}

# Variable to track if any errors were found
$anyErrorsFound = $false

# Loop through each script file and run the analyzer
foreach ($file in $scriptFiles) {
	Write-Host "--------------------------------------------------"
	Write-Host "Validating: $($file.FullName)"
	Write-Host "--------------------------------------------------"
	try {
		if ($FixFormatting) {
			# Fix code formatting only when explicitly requested.
			[void](Invoke-ScriptAnalyzer -Path $file.FullName -IncludeRule $formatRules -Fix -ErrorAction Stop 6>&1 3>&1)
		}

		# Formatting analysis is report-only unless -FixFormatting is supplied.
		$formatIssues = Invoke-ScriptAnalyzer -Path $file.FullName -IncludeRule $formatRules -ErrorAction Stop 6>&1 3>&1

		# Single analysis pass: style rules + compatibility checks
		$results = Invoke-ScriptAnalyzer -Path $file.FullName -Settings $analysisSettings -ErrorAction Stop 6>&1 3>&1
		if ($results -or $formatIssues) {
			# Separate compatibility issues from other issues
			$compatRules = @('PSUseCompatibleSyntax', 'PSUseCompatibleCommands', 'PSUseCompatibleTypes')
			$compatIssues = $results | Where-Object { $_.RuleName -in $compatRules }
			$otherIssues = $results | Where-Object { $_.RuleName -notin $compatRules }
			if ($formatIssues) {
				Write-Warning "Formatting issues found in $($file.Name). Re-run with -FixFormatting to apply formatting fixes:" 3>&1
				$formatIssues | Format-Table RuleName, Severity, Line, Message -AutoSize
			}
			if ($otherIssues) {
				Write-Warning "Issues found in $($file.Name):" 3>&1
				$otherIssues | Format-Table RuleName, Severity, Line, Message -AutoSize
			}
			if ($compatIssues) {
				Write-Warning "Compatibility issues in $($file.Name):" 3>&1
				$compatIssues | Format-Table RuleName, Severity, Line, Message -AutoSize
			}
			if (-not $formatIssues -and -not $otherIssues -and -not $compatIssues) {
				Write-Host "No issues found in $($file.Name)."
			}
			else {
				$anyErrorsFound = $true
			}
		}
		else {
			Write-Host "No issues found in $($file.Name)."
		}
	}
	catch {
		Write-Error "Failed to analyze $($file.Name): $_" 2>&1
		$anyErrorsFound = $true
	}
	Write-Host ""
}

Write-Host "=================================================="
if ($anyErrorsFound) {
	Write-Warning "Validation complete. Some issues were found." 3>&1
}
else {
	Write-Host "Validation complete. No issues found."
}
Write-Host "=================================================="
