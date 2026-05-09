################################################################################
# File         : Setup_App_5a_Qdrant_Core_Windows.ps1
# Description  : Installs and runs Qdrant on Windows without containers.
#                Downloads the official Qdrant Windows release binary to
#                C:\ProgramData\Qdrant and stores data under the same folder.
# Usage        : Run in PowerShell. Choose ports during setup. Then open the shown URL.
################################################################################

using namespace System
using namespace System.IO

param(
	[switch]$AutoApprove,
	[string]$Config = $null,
	[string]$ElevatedKey = ""
)

# Ensure script runs from its own directory
Set-Location -Path $PSScriptRoot

# Dot-source the necessary helper function files.
. "$PSScriptRoot\Setup_Helper_CoreFunctions.ps1"

# Load script settings and auto-approve list
$defaultConfigJson = @'
{
  "engine": null,
  "menuAction": "installapp",
  "autoApprove": [
    "deleteData",
    "deleteAll",
    "enableAutoStart",
    "startMode",
    "githubToken"
  ]
}
'@
$scriptSettings = Import-ScriptSettings -ConfigJson $Config -DefaultConfigJson $defaultConfigJson
$autoApproveList = if ($scriptSettings -and $scriptSettings.autoApprove) { @($scriptSettings.autoApprove) } else { @() }

#==============================================================================
# Global Configuration
#==============================================================================

$global:appName = "Qdrant"
$global:settingsVersion = 1

$global:defaultHttpPort = 6333
$global:defaultGrpcPort = 6334

$global:programDataRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
$global:installRoot = Join-Path $global:programDataRoot $global:appName
$global:storageRoot = Join-Path $global:installRoot "storage"
$global:downloadsRoot = Join-Path $global:installRoot "downloads"
$global:staticRoot = Join-Path $global:installRoot "static"
$global:settingsPath = Join-Path $global:installRoot "settings.json"
$global:qdrantExePath = Join-Path $global:installRoot "qdrant.exe"

$global:githubRepoOwner = "qdrant"
$global:githubRepoName = "qdrant"
$global:githubLatestReleaseApiUrl = "https://api.github.com/repos/$($global:githubRepoOwner)/$($global:githubRepoName)/releases/latest"
$global:githubLatestReleaseWebUrl = "https://github.com/$($global:githubRepoOwner)/$($global:githubRepoName)/releases/latest"
$global:githubUserAgent = "VsAiCompanion-Qdrant-Windows-Setup"

# Optional: GitHub token to avoid API rate limiting.
# If missing, the script will prompt for it (for this run only) when needed.
$global:githubTokenEnvVarName = "GITHUB_TOKEN"

$global:qdrantWebUiRepoOwner = "qdrant"
$global:qdrantWebUiRepoName = "qdrant-web-ui"
$global:qdrantWebUiLatestReleaseApiUrl = "https://api.github.com/repos/$($global:qdrantWebUiRepoOwner)/$($global:qdrantWebUiRepoName)/releases/latest"
$global:qdrantWebUiZipAssetName = "dist-qdrant.zip"
$global:qdrantWebUiVersionFile = Join-Path $global:installRoot ".qdrant-web-ui-version"

$global:dashboardPath = "/dashboard"

$global:qdrantServiceTaskName = "VsAiCompanion-Qdrant"
$global:qdrantServiceWrapperPath = Join-Path $global:installRoot "service-wrapper.ps1"
$global:qdrantServiceVbsShimPath = Join-Path $global:installRoot "service-wrapper.vbs"
$global:qdrantServiceLogPath = Join-Path $global:installRoot "service.log"
$global:qdrantServicePidPath = Join-Path $global:installRoot "service.pid"

#==============================================================================
# Function: New-Directory
#==============================================================================
<#
.SYNOPSIS
	Creates a directory if it does not exist.
.DESCRIPTION
	Ensures the specified directory exists, creating it (and parents) if needed.
.PARAMETER Path
	Directory path to ensure exists.
.OUTPUTS
	[void]
#>
function New-Directory {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	if (-not (Test-Path -LiteralPath $Path)) {
		if ($PSCmdlet.ShouldProcess($Path, "Create directory")) {
			New-Item -ItemType Directory -Path $Path -Force | Out-Null
			Write-Host "Created directory: $Path" -ForegroundColor DarkGray
		}
	}
}

#==============================================================================
# Function: Test-TcpPortAvailable
#==============================================================================
<#
.SYNOPSIS
	Tests if a local TCP port is available.
.DESCRIPTION
	Attempts to bind a TcpListener to localhost on the specified port.
	Returns $true if the bind succeeds; otherwise $false.
.PARAMETER Port
	TCP port to test.
.OUTPUTS
	[bool]
#>
function Test-TcpPortAvailable {
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[int]$Port
	)

	try {
		$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
		$listener.Start()
		$listener.Stop()
		return $true
	}
	catch {
		return $false
	}
}

#==============================================================================
# Function: Get-DefaultQdrantPorts
#==============================================================================
<#
.SYNOPSIS
	Returns sensible default HTTP and gRPC ports for Qdrant.
.DESCRIPTION
	Returns saved port settings when they exist. When no settings are saved,
	checks whether the standard ports (6333/6334) are available. If either is
	in use (e.g. a container instance is running), falls back to the alternate
	pair (6335/6336) so the caller can suggest those as defaults without
	prompting the user with a conflict warning.
.OUTPUTS
	[pscustomobject] with HttpPort [int] and GrpcPort [int].
#>
function Get-DefaultQdrantPorts {
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param()

	$settings = Get-QdrantSetting
	if (Test-Path -LiteralPath $global:settingsPath) {
		return [PSCustomObject]@{ HttpPort = $settings.HttpPort; GrpcPort = $settings.GrpcPort }
	}

	$httpPort = if (Test-TcpPortAvailable -Port $global:defaultHttpPort) { $global:defaultHttpPort } else { $global:defaultHttpPort + 2 }
	$grpcPort = if (Test-TcpPortAvailable -Port $global:defaultGrpcPort) { $global:defaultGrpcPort } else { $global:defaultGrpcPort + 2 }
	return [PSCustomObject]@{ HttpPort = $httpPort; GrpcPort = $grpcPort }
}

#==============================================================================
# Function: Read-ValidatedPort
#==============================================================================
<#
.SYNOPSIS
	Prompts the user for a TCP port number.
.DESCRIPTION
	Prompts for a port with a default value. Validates range (1..65535) and availability.
.PARAMETER Prompt
	Prompt text.
.PARAMETER DefaultPort
	Default port to use when the user presses Enter.
.OUTPUTS
	[int]
#>
function Read-ValidatedPort {
	[CmdletBinding()]
	[OutputType([int])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Prompt,

		[Parameter(Mandatory = $true)]
		[int]$DefaultPort
	)

	while ($true) {
		$raw = Read-Host "$Prompt [default: $DefaultPort]"
		if ([string]::IsNullOrWhiteSpace($raw)) {
			$port = $DefaultPort
		}
		else {
			$parsed = 0
			if (-not [int]::TryParse($raw, [ref]$parsed)) {
			Write-Warning "Invalid port '$raw'. Please enter a number between 1 and 65535."
			continue
		}
			$port = $parsed
		}

		if ($port -lt 1 -or $port -gt 65535) {
			Write-Warning "Port must be between 1 and 65535."
			continue
		}

		if (-not (Test-TcpPortAvailable -Port $port)) {
			Write-Warning "Port $port is already in use on this machine. Choose another port."
			continue
		}

		return $port
	}
}

#==============================================================================
# Function: Get-QdrantSetting
#==============================================================================
<#
.SYNOPSIS
	Loads persisted Qdrant Windows settings.
.DESCRIPTION
	Reads settings from $global:settingsPath if present. Returns defaults when missing/invalid.
.OUTPUTS
	[pscustomobject]
#>
function Get-QdrantSetting {
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param()

	if (Test-Path -LiteralPath $global:settingsPath) {
		try {
			$content = Get-Content -LiteralPath $global:settingsPath -Raw -Encoding UTF8
			$settings = $content | ConvertFrom-Json
			if ($null -ne $settings -and $null -ne $settings.HttpPort -and $null -ne $settings.GrpcPort) {
				return [PSCustomObject]@{
					Version  = $settings.Version
					HttpPort  = [int]$settings.HttpPort
					GrpcPort  = [int]$settings.GrpcPort
				}
			}
		}
		catch {
			Write-Warning "Failed to load settings from '$($global:settingsPath)'. Using defaults. Details: $_"
		}
	}

	return [PSCustomObject]@{
		Version  = $global:settingsVersion
		HttpPort = $global:defaultHttpPort
		GrpcPort = $global:defaultGrpcPort
	}
}

#==============================================================================
# Function: Set-QdrantSetting
#==============================================================================
<#
.SYNOPSIS
	Saves persisted Qdrant Windows settings.
.DESCRIPTION
	Writes a small JSON file to $global:settingsPath.
.PARAMETER HttpPort
	HTTP port used by Qdrant.
.PARAMETER GrpcPort
	gRPC port used by Qdrant.
.OUTPUTS
	[void]
#>
function Set-QdrantSetting {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Mandatory = $true)]
		[int]$HttpPort,

		[Parameter(Mandatory = $true)]
		[int]$GrpcPort
	)

	New-Directory -Path $global:installRoot
	New-Directory -Path $global:storageRoot
	New-Directory -Path $global:downloadsRoot

	$settings = [PSCustomObject]@{
		Version     = $global:settingsVersion
		UpdatedUtc  = (Get-Date).ToUniversalTime().ToString("o")
		InstallRoot = $global:installRoot
		Storage     = $global:storageRoot
		HttpPort    = $HttpPort
		GrpcPort    = $GrpcPort
	}

	if ($PSCmdlet.ShouldProcess($global:settingsPath, "Save settings")) {
		$settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $global:settingsPath -Encoding UTF8
		Write-Host "Saved settings to: $($global:settingsPath)" -ForegroundColor DarkGray
	}
}

#==============================================================================
# Function: Read-GitHubTokenForThisRun
#==============================================================================
<#
.SYNOPSIS
	Prompts for a GitHub token and stores it in the process environment.
.DESCRIPTION
	Asks the user for a token only when needed. The token is stored in $env:GITHUB_TOKEN
	for this PowerShell process only (not persisted).
.OUTPUTS
	[void]
#>
function Read-GitHubTokenForThisRun {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[array]$AutoApproveList = @(),

		[Parameter(Mandatory = $false)]
		[bool]$IsAutoApprove = $false
	)

	$token = [Environment]::GetEnvironmentVariable($global:githubTokenEnvVarName, "Process")
	if ([string]::IsNullOrWhiteSpace($token)) {
		$token = [Environment]::GetEnvironmentVariable($global:githubTokenEnvVarName, "User")
	}

	if (-not [string]::IsNullOrWhiteSpace($token)) {
		return
	}

	Write-Host ""
	Write-Host "GitHub API rate limits can block downloads." -ForegroundColor Yellow
	Write-Host "Provide a GitHub Personal Access Token (classic or fine-grained) with read access to public repos." -ForegroundColor DarkGray
	Write-Host "Leave blank to continue unauthenticated (may fail if rate limited)." -ForegroundColor DarkGray
	$token = Invoke-AutoApprovedPrompt -Description "Enter GitHub token (will be used for this run only)" `
		-Key "githubToken" -DefaultValue "" `
		-AutoApproveList $AutoApproveList -IsAutoApprove:$IsAutoApprove

	if (-not [string]::IsNullOrWhiteSpace($token)) {
		[Environment]::SetEnvironmentVariable($global:githubTokenEnvVarName, $token, "Process")
	}
}

#==============================================================================
# Function: Get-GitHubApiHeaders
#==============================================================================
<#
.SYNOPSIS
	Builds GitHub API headers.
.DESCRIPTION
	Creates a User-Agent header and, if present, adds an Authorization header using
	the token from $env:GITHUB_TOKEN to increase rate limits.
.OUTPUTS
	[hashtable]
#>
function Get-GitHubApiHeaders {
	[CmdletBinding()]
	[OutputType([hashtable])]
	param()

	$headers = @{
		"User-Agent" = $global:githubUserAgent
		"Accept"     = "application/vnd.github+json"
	}

	$token = [Environment]::GetEnvironmentVariable($global:githubTokenEnvVarName, "Process")
	if ([string]::IsNullOrWhiteSpace($token)) {
		$token = [Environment]::GetEnvironmentVariable($global:githubTokenEnvVarName, "User")
	}

	if (-not [string]::IsNullOrWhiteSpace($token)) {
		$headers["Authorization"] = "Bearer $token"
	}

	return $headers
}

#==============================================================================
# Function: Get-QdrantLatestRelease
#==============================================================================
<#
.SYNOPSIS
	Fetches the latest Qdrant release metadata from GitHub.
.DESCRIPTION
	Uses the GitHub REST API to retrieve the latest release and its assets.
	Falls back to parsing the GitHub Releases page when the API rate limit is exceeded.
.OUTPUTS
	[object]
#>
function Get-QdrantLatestRelease {
	[CmdletBinding()]
	[OutputType([object])]
	param()

	try {
		$headers = Get-GitHubApiHeaders
		return Invoke-RestMethod -Uri $global:githubLatestReleaseApiUrl -Headers $headers -Method Get -ErrorAction Stop
	}
	catch {
		$errText = "$_"
		if ($errText -match "API rate limit exceeded") {
			Read-GitHubTokenForThisRun
			try {
				$headers = Get-GitHubApiHeaders
				return Invoke-RestMethod -Uri $global:githubLatestReleaseApiUrl -Headers $headers -Method Get -ErrorAction Stop
			}
			catch {
				$errText2 = "$_"
				if ($errText2 -match "API rate limit exceeded") {
					Write-Warning "GitHub API rate limit exceeded. Falling back to parsing $($global:githubLatestReleaseWebUrl)."
					$tag = Get-GitHubLatestReleaseTagFromWeb -LatestReleaseUrl $global:githubLatestReleaseWebUrl
					return Get-GitHubReleaseByTag -Owner $global:githubRepoOwner -Repo $global:githubRepoName -Tag $tag
				}
				throw
			}
		}

		throw "Failed to query GitHub latest release API: $_"
	}
}

#==============================================================================
# Function: Get-GitHubLatestReleaseTagFromWeb
#==============================================================================
<#
.SYNOPSIS
	Gets the latest GitHub release tag from the /releases/latest redirect.
.DESCRIPTION
	Uses an HTTP request to the GitHub web UI endpoint (not the API), then extracts
	the tag from the final redirected URL.
.PARAMETER LatestReleaseUrl
	The GitHub releases/latest URL.
.OUTPUTS
	[string]
#>
function Get-GitHubLatestReleaseTagFromWeb {
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$LatestReleaseUrl
	)

	try {
		$headers = @{ "User-Agent" = $global:githubUserAgent }
		$response = Invoke-WebRequest -Uri $LatestReleaseUrl -Headers $headers -MaximumRedirection 0 -ErrorAction SilentlyContinue

		# If MaximumRedirection=0, GitHub should respond with 302 and a Location header.
		$location = $null
		if ($response -and $response.Headers) {
			$location = $response.Headers["Location"]
		}

		# Some environments follow redirects anyway; fall back to the final ResponseUri.
		if ([string]::IsNullOrWhiteSpace($location) -and $response -and $response.BaseResponse -and $response.BaseResponse.ResponseUri) {
			$location = [string]$response.BaseResponse.ResponseUri.AbsoluteUri
		}

		if ([string]::IsNullOrWhiteSpace($location)) {
			throw "No redirect location returned."
		}

		if ($location -match "/tag/(?<tag>[^/?#]+)") {
			return $Matches["tag"]
		}

		throw "Could not extract tag from redirect URL '$location'."
	}
	catch {
		throw "Failed to determine latest release tag from '$LatestReleaseUrl': $_"
	}
}

#==============================================================================
# Function: Get-GitHubReleaseByTag
#==============================================================================
<#
.SYNOPSIS
	Fetches a GitHub release by tag.
.DESCRIPTION
	Calls the GitHub REST API endpoint /releases/tags/{tag}.
.PARAMETER Owner
	GitHub organization/user.
.PARAMETER Repo
	Repository name.
.PARAMETER Tag
	Release tag.
.OUTPUTS
	[object]
#>
function Get-GitHubReleaseByTag {
	[CmdletBinding()]
	[OutputType([object])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Owner,

		[Parameter(Mandatory = $true)]
		[string]$Repo,

		[Parameter(Mandatory = $true)]
		[string]$Tag
	)

	$uri = "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag"
	try {
		$headers = Get-GitHubApiHeaders
		return Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
	}
	catch {
		throw "Failed to query GitHub release by tag API ($uri): $_"
	}
}

#==============================================================================
# Function: Get-QdrantWebUiLatestRelease
#==============================================================================
<#
.SYNOPSIS
	Fetches the latest Qdrant Web UI release metadata from GitHub.
.DESCRIPTION
	Uses the GitHub REST API to retrieve the latest release and its assets.
	Falls back to HTML scraping of the GitHub Releases page when the API rate limit is exceeded.
.OUTPUTS
	[object]
#>
function Get-QdrantWebUiLatestRelease {
	[CmdletBinding()]
	[OutputType([object])]
	param()

	try {
		$headers = Get-GitHubApiHeaders
		return Invoke-RestMethod -Uri $global:qdrantWebUiLatestReleaseApiUrl -Headers $headers -Method Get -ErrorAction Stop
	}
	catch {
		$errText = "$_"
		if ($errText -match "API rate limit exceeded") {
			Read-GitHubTokenForThisRun
			try {
				$headers = Get-GitHubApiHeaders
				return Invoke-RestMethod -Uri $global:qdrantWebUiLatestReleaseApiUrl -Headers $headers -Method Get -ErrorAction Stop
			}
			catch {
				$errText2 = "$_"
				if ($errText2 -match "API rate limit exceeded") {
					$webLatest = "https://github.com/$($global:qdrantWebUiRepoOwner)/$($global:qdrantWebUiRepoName)/releases/latest"
					Write-Warning "GitHub API rate limit exceeded. Falling back to parsing $webLatest."
					$tag = Get-GitHubLatestReleaseTagFromWeb -LatestReleaseUrl $webLatest
					return Get-GitHubReleaseByTag -Owner $global:qdrantWebUiRepoOwner -Repo $global:qdrantWebUiRepoName -Tag $tag
				}
				throw
			}
		}

		throw "Failed to query GitHub Qdrant Web UI latest release API: $_"
	}
}

#==============================================================================
# Function: Select-QdrantWindowsZipAsset
#==============================================================================
<#
.SYNOPSIS
	Selects the best matching Windows zip asset from a GitHub release.
.DESCRIPTION
	Attempts to find a Windows x64 zip asset. Falls back to any Windows zip.
.PARAMETER Release
	Release object returned by the GitHub API.
.OUTPUTS
	[object]
#>
function Select-QdrantWindowsZipAsset {
	[CmdletBinding()]
	[OutputType([object])]
	param(
		[Parameter(Mandatory = $true)]
		[object]$Release
	)

	$assets = @($Release.assets)
	if (-not $assets -or $assets.Count -eq 0) {
		throw "GitHub release has no assets."
	}

	$zip64 = @(
		$assets | Where-Object {
			$_.name -match "(?i)windows" -and
			$_.name -match "(?i)(x86_64|amd64|x64)" -and
			$_.name -match "(?i)\.zip$"
		}
	)
	if ($zip64 -and $zip64.Count -gt 0) { return $zip64[0] }

	$zipAny = @(
		$assets | Where-Object {
			$_.name -match "(?i)windows" -and
			$_.name -match "(?i)\.zip$"
		}
	)
	if ($zipAny -and $zipAny.Count -gt 0) { return $zipAny[0] }

	$names = ($assets | Select-Object -ExpandProperty name) -join ", "
	throw "No Windows .zip asset found in latest release. Assets: $names"
}

#==============================================================================
# Function: Select-QdrantWebUiZipAsset
#==============================================================================
<#
.SYNOPSIS
	Selects the Qdrant Web UI distribution zip from a GitHub release.
.DESCRIPTION
	Finds the 'dist-qdrant.zip' asset in the latest qdrant-web-ui release.
.PARAMETER Release
	Release object returned by the GitHub API.
.OUTPUTS
	[object]
#>
function Select-QdrantWebUiZipAsset {
	[CmdletBinding()]
	[OutputType([object])]
	param(
		[Parameter(Mandatory = $true)]
		[object]$Release
	)

	$assets = @($Release.assets)
	if (-not $assets -or $assets.Count -eq 0) {
		throw "GitHub Qdrant Web UI release has no assets."
	}

	$asset = $assets | Where-Object { $_.name -eq $global:qdrantWebUiZipAssetName } | Select-Object -First 1
	if ($null -ne $asset) {
		return $asset
	}

	$names = ($assets | Select-Object -ExpandProperty name) -join ", "
	throw "Asset '$($global:qdrantWebUiZipAssetName)' was not found in latest Qdrant Web UI release. Assets: $names"
}

#==============================================================================
# Function: Invoke-DownloadFile
#==============================================================================
<#
.SYNOPSIS
	Downloads a file from a URL.
.DESCRIPTION
	Downloads a file using Invoke-WebRequest with a User-Agent header.
.PARAMETER SourceUrl
	Source URL.
.PARAMETER DestinationPath
	Local destination file path.
.PARAMETER ForceDownload
	If specified, downloads even when the destination already exists.
.OUTPUTS
	[void]
#>
function Invoke-DownloadFile {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$SourceUrl,

		[Parameter(Mandatory = $true)]
		[string]$DestinationPath,

		[switch]$ForceDownload
	)

	if ((Test-Path -LiteralPath $DestinationPath) -and (-not $ForceDownload)) {
		Write-Host "File already exists: $DestinationPath" -ForegroundColor DarkGray
		return
	}

	New-Directory -Path (Split-Path -Parent $DestinationPath)

	try {
		$headers = @{ "User-Agent" = $global:githubUserAgent }
		$ProgressPreference = 'SilentlyContinue'
		Write-Host "Downloading: $SourceUrl" -ForegroundColor Yellow
		$invokeParams = @{
			Uri         = $SourceUrl
			Headers     = $headers
			OutFile     = $DestinationPath
			ErrorAction = 'Stop'
		}
		$cmd = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
		if ($cmd -and $cmd.Parameters.ContainsKey('UseBasicParsing')) {
			$invokeParams['UseBasicParsing'] = $true
		}
		Invoke-WebRequest @invokeParams
		$ProgressPreference = 'Continue'
		Write-Host "Downloaded to: $DestinationPath" -ForegroundColor Green
	}
	catch {
		$ProgressPreference = 'Continue'
		throw "Failed to download '$SourceUrl' to '$DestinationPath': $_"
	}
}

#==============================================================================
# Function: Install-QdrantWebUiIfMissing
#==============================================================================
<#
.SYNOPSIS
	Installs Qdrant Web UI static files (dashboard) if missing.
.DESCRIPTION
	Downloads the qdrant-web-ui distribution zip and extracts it into .\static under
	$global:installRoot, which Qdrant serves at /dashboard.
.OUTPUTS
	[void]
#>
function Install-QdrantWebUiIfMissing {
	[CmdletBinding()]
	param()

	New-Directory -Path $global:installRoot
	New-Directory -Path $global:downloadsRoot

	$indexPath = Join-Path $global:staticRoot "index.html"
	if (Test-Path -LiteralPath $indexPath) {
		Write-Host "Qdrant Web UI is already installed: $($global:staticRoot)" -ForegroundColor Green
		return
	}

	Write-Host "Qdrant Web UI not found. Downloading latest Web UI..." -ForegroundColor Yellow
	$release = Get-QdrantWebUiLatestRelease
	$asset = Select-QdrantWebUiZipAsset -Release $release

	$zipPath = Join-Path $global:downloadsRoot $asset.name
	Invoke-DownloadFile -SourceUrl $asset.browser_download_url -DestinationPath $zipPath

	$tempExtract = Join-Path $global:downloadsRoot "webui-extract"
	if (Test-Path -LiteralPath $tempExtract) {
		Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
	}
	New-Directory -Path $tempExtract

	Write-Host "Extracting Web UI: $zipPath" -ForegroundColor Yellow
	Expand-Archive -Path $zipPath -DestinationPath $tempExtract -Force

	$index = Get-ChildItem -LiteralPath $tempExtract -Recurse -Filter "index.html" -File -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $index) {
		throw "Qdrant Web UI package did not contain an index.html."
	}

	$uiSourceRoot = Split-Path -Parent $index.FullName
	if (Test-Path -LiteralPath $global:staticRoot) {
		Remove-Item -LiteralPath $global:staticRoot -Recurse -Force -ErrorAction SilentlyContinue
	}
	New-Directory -Path $global:staticRoot
	Copy-Item -Path (Join-Path $uiSourceRoot '*') -Destination $global:staticRoot -Recurse -Force

	Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

	Set-Content -LiteralPath $global:qdrantWebUiVersionFile -Value $release.tag_name -Encoding UTF8

	if (-not (Test-Path -LiteralPath $indexPath)) {
		throw "Qdrant Web UI installation failed: '$indexPath' not found after extraction."
	}

	Write-Host "Installed Qdrant Web UI: $($global:staticRoot)  (version: $($release.tag_name))" -ForegroundColor Green
}

#==============================================================================
# Function: Install-QdrantIfMissing
#==============================================================================
<#
.SYNOPSIS
	Installs Qdrant into ProgramData if missing.
.DESCRIPTION
	Downloads the latest Windows .zip release from GitHub and extracts it to $global:installRoot.
.OUTPUTS
	[void]
#>
function Install-QdrantIfMissing {
	[CmdletBinding()]
	param()

	New-Directory -Path $global:installRoot
	New-Directory -Path $global:storageRoot
	New-Directory -Path $global:downloadsRoot

	if (Test-Path -LiteralPath $global:qdrantExePath) {
		Write-Host "Qdrant is already installed: $($global:qdrantExePath)" -ForegroundColor Green
		return
	}

	Write-Host "Qdrant not found. Downloading latest release..." -ForegroundColor Yellow
	$release = Get-QdrantLatestRelease
	$asset = Select-QdrantWindowsZipAsset -Release $release

	$zipPath = Join-Path $global:downloadsRoot $asset.name
	Invoke-DownloadFile -SourceUrl $asset.browser_download_url -DestinationPath $zipPath

	$tempExtract = Join-Path $global:downloadsRoot "extract"
	if (Test-Path -LiteralPath $tempExtract) {
		Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
	}
	New-Directory -Path $tempExtract

	Write-Host "Extracting: $zipPath" -ForegroundColor Yellow
	Expand-Archive -Path $zipPath -DestinationPath $tempExtract -Force

	$exe = Get-ChildItem -LiteralPath $tempExtract -Recurse -Filter "qdrant.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $exe) {
		throw "Extracted archive did not contain qdrant.exe."
	}

	$distRoot = Split-Path -Parent $exe.FullName
	Write-Host "Installing files from: $distRoot" -ForegroundColor DarkGray

	# Copy distribution contents to install root (keeps storage/settings under install root as separate folders/files)
	Copy-Item -Path (Join-Path $distRoot '*') -Destination $global:installRoot -Recurse -Force

	# Cleanup extraction folder
	Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

	if (-not (Test-Path -LiteralPath $global:qdrantExePath)) {
		throw "Install failed: qdrant.exe not found at '$($global:qdrantExePath)' after extraction."
	}

	Write-Host "Installed: $($global:qdrantExePath)" -ForegroundColor Green
}

#==============================================================================
# Function: Install-Qdrant
#==============================================================================
<#
.SYNOPSIS
	Installs Qdrant prerequisites and persists configuration.
.DESCRIPTION
	Prompts for HTTP and gRPC ports (saved under ProgramData), ensures required folders exist,
	and downloads Qdrant + Web UI if missing.
.OUTPUTS
	[void]
#>
function Install-Qdrant {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[bool]$IsAutoApprove = $false
	)

	Install-QdrantIfMissing
	Install-QdrantWebUiIfMissing

	$defaults = Get-DefaultQdrantPorts

	Write-Host ""
	Write-Host "Qdrant ports (default: HTTP $($global:defaultHttpPort), gRPC $($global:defaultGrpcPort)):" -ForegroundColor White
	if (-not (Test-TcpPortAvailable -Port $global:defaultHttpPort) -or -not (Test-TcpPortAvailable -Port $global:defaultGrpcPort)) {
		Write-Host "  Standard ports are in use (container instance running?). Suggesting alternate pair." -ForegroundColor DarkGray
	}
	Write-Host ""

	if ($IsAutoApprove) {
		$httpPort = $defaults.HttpPort
		$grpcPort = $defaults.GrpcPort
		Write-Host "Using Qdrant HTTP port: $httpPort, gRPC port: $grpcPort" -ForegroundColor DarkGray
	}
	else {
		$httpPort = Read-ValidatedPort -Prompt "Enter Qdrant HTTP port" -DefaultPort $defaults.HttpPort
		$grpcPort = Read-ValidatedPort -Prompt "Enter Qdrant gRPC port" -DefaultPort $defaults.GrpcPort
	}

	if ($httpPort -eq $grpcPort) {
		Write-Warning "HTTP and gRPC ports cannot be the same."
		return
	}

	Set-QdrantSetting -HttpPort $httpPort -GrpcPort $grpcPort
	New-Directory -Path $global:storageRoot
}

#==============================================================================
# Function: Start-QdrantConsole
#==============================================================================
<#
.SYNOPSIS
	Starts Qdrant in the current console (foreground).
.DESCRIPTION
	Loads saved settings, sets environment variables and launches Qdrant in the foreground.
.OUTPUTS
	[void]
#>
function Start-QdrantConsole {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param()

	$settings = Get-QdrantSetting
	$httpPort = [int]$settings.HttpPort
	$grpcPort = [int]$settings.GrpcPort

	if (-not $PSCmdlet.ShouldProcess("Qdrant", "Start Console")) {
		return
	}

	if (-not (Test-Path -LiteralPath $global:qdrantExePath)) {
		Write-Warning "Qdrant is not installed. Run 'Install' first."
		return
	}

	$env:QDRANT__SERVICE__HTTP_PORT = $httpPort.ToString()
	$env:QDRANT__SERVICE__GRPC_PORT = $grpcPort.ToString()
	$env:QDRANT__STORAGE__STORAGE_PATH = $global:storageRoot

	Write-Host ""
	Write-Host "Starting Qdrant in the foreground (Ctrl+C to stop)..." -ForegroundColor Yellow
	Write-Host "HTTP API   : http://localhost:$httpPort" -ForegroundColor Green
	Write-Host "Dashboard  : http://localhost:$httpPort$($global:dashboardPath)" -ForegroundColor Green
	Write-Host "gRPC       : localhost:$grpcPort" -ForegroundColor Green

	Push-Location -LiteralPath $global:installRoot
	try {
		& $global:qdrantExePath
	}
	finally {
		Pop-Location
	}
}

#==============================================================================
# Function: Write-QdrantServiceWrapper
#==============================================================================
<#
.SYNOPSIS
	Writes the Scheduled Task wrapper script for Qdrant.
.DESCRIPTION
	Creates a PowerShell script under ProgramData which sets environment variables from saved settings
	and starts Qdrant with stdout/stderr appended to a log file.
.OUTPUTS
	[void]
#>
function Write-QdrantServiceWrapper {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param()

	New-Directory -Path $global:installRoot

	$settings = Get-QdrantSetting
	$httpPort = [int]$settings.HttpPort
	$grpcPort = [int]$settings.GrpcPort

	$vbs = @"
CreateObject("WScript.Shell").Run "PowerShell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & "$($global:qdrantServiceWrapperPath.Replace('"','""'))" & """", 0, False
"@

	if ($PSCmdlet.ShouldProcess($global:qdrantServiceVbsShimPath, "Write VBS shim")) {
		Set-Content -LiteralPath $global:qdrantServiceVbsShimPath -Value $vbs -Encoding ASCII
	}

	$wrapper = @"
`$ErrorActionPreference = 'Stop'

`$installRoot = '$($global:installRoot)'
`$exePath = '$($global:qdrantExePath)'
`$storageRoot = '$($global:storageRoot)'
`$logPath = '$($global:qdrantServiceLogPath)'
`$pidPath = '$($global:qdrantServicePidPath)'

`$env:QDRANT__SERVICE__HTTP_PORT = '$httpPort'
`$env:QDRANT__SERVICE__GRPC_PORT = '$grpcPort'
`$env:QDRANT__STORAGE__STORAGE_PATH = `"`$storageRoot`"

New-Item -ItemType Directory -Path `"`$installRoot`" -Force | Out-Null
New-Item -ItemType Directory -Path `"`$storageRoot`" -Force | Out-Null

`"[`$(Get-Date -Format o)] Starting Qdrant...`" | Out-File -FilePath `"`$logPath`" -Append -Encoding UTF8

if (Test-Path -LiteralPath `"`$pidPath`" ) {
	try {
		`$oldPid = [int](Get-Content -LiteralPath `"`$pidPath`" -ErrorAction SilentlyContinue | Select-Object -First 1)
		if (`$oldPid -gt 0) {
			`$pOld = Get-Process -Id `$oldPid -ErrorAction SilentlyContinue
			if (`$pOld) {
				`"[`$(Get-Date -Format o)] Existing PID found (`$oldPid). Stopping it...`" | Out-File -FilePath `"`$logPath`" -Append -Encoding UTF8
				Stop-Process -Id `$oldPid -Force -ErrorAction SilentlyContinue
			}
		}
	}
	catch { }
}

Push-Location -LiteralPath `"`$installRoot`"
try {
	`$stdoutPath = `"`$logPath`"
	`$stderrPath = `"`$logPath`" + ".err"
	`$p = Start-Process -FilePath `"`$exePath`" -WindowStyle Hidden -RedirectStandardOutput `"`$stdoutPath`" -RedirectStandardError `"`$stderrPath`" -PassThru
	Set-Content -LiteralPath `"`$pidPath`" -Value `$p.Id -Encoding UTF8
	`"[`$(Get-Date -Format o)] Qdrant started. PID=`$(`$p.Id)`" | Out-File -FilePath `"`$logPath`" -Append -Encoding UTF8
}
finally {
	Pop-Location
}
"@

	if ($PSCmdlet.ShouldProcess($global:qdrantServiceWrapperPath, "Write Qdrant service wrapper script")) {
		Set-Content -LiteralPath $global:qdrantServiceWrapperPath -Value $wrapper -Encoding UTF8
	}
}

#==============================================================================
# Function: Get-QdrantTaskInfo
#==============================================================================
<#
.SYNOPSIS
	Returns information about the currently registered Qdrant scheduled task.
.DESCRIPTION
	Checks if the task exists in Task Scheduler and whether it was registered
	as a pre-login (AtStartup/S4U) or post-login (AtLogon) task.
.OUTPUTS
	[pscustomobject] with Exists [bool] and IsPreLogin [bool].
#>
function Get-QdrantTaskInfo {
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param()

	$task = Get-ScheduledTask -TaskName $global:qdrantServiceTaskName -ErrorAction SilentlyContinue
	if (-not $task) {
		return [PSCustomObject]@{ Exists = $false; IsPreLogin = $false }
	}

	$isPreLogin = [bool]($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskBootTrigger' })
	return [PSCustomObject]@{ Exists = $true; IsPreLogin = $isPreLogin }
}

#==============================================================================
# Function: Install-QdrantService
#==============================================================================
<#
.SYNOPSIS
	Installs a Scheduled Task as a non-interactive auto-start for Qdrant.
.DESCRIPTION
	Installs Qdrant, writes a service wrapper script, and registers a Scheduled Task
	using the shared Install-ScheduledTaskService helper.
	Without -PreLogin, registers an AtLogon/S4U task (no admin required).
	With -PreLogin, registers an AtStartup/S4U task (triggers inline UAC).
.PARAMETER PreLogin
	Register as a pre-login (AtStartup) task. Requires admin; triggers inline UAC.
.PARAMETER IsAutoApprove
	Suppress interactive prompts and use defaults.
.OUTPUTS
	[void]
#>
function Install-QdrantService {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$PreLogin,

		[Parameter(Mandatory = $false)]
		[bool]$IsAutoApprove = $false
	)

	Install-Qdrant -IsAutoApprove:$IsAutoApprove
	Write-QdrantServiceWrapper

	if (-not (Test-Path -LiteralPath $global:qdrantServiceWrapperPath)) {
		throw "Wrapper script was not created: $($global:qdrantServiceWrapperPath)"
	}

	$installParams = @{
		TaskName          = $global:qdrantServiceTaskName
		WrapperScriptPath = $global:qdrantServiceWrapperPath
		AutoStart         = $true
	}
	if ($PreLogin) {
		$installParams.PreLogin = $true
	}
	else {
		$installParams.VbsShimPath = $global:qdrantServiceVbsShimPath
	}

	if ($PSCmdlet.ShouldProcess($global:qdrantServiceTaskName, "Install Qdrant Scheduled Task")) {
		Install-ScheduledTaskService @installParams
	}
}

#==============================================================================
# Function: Uninstall-QdrantService
#==============================================================================
<#
.SYNOPSIS
	Uninstalls the Scheduled Task "service" for Qdrant.
.DESCRIPTION
	Delegates to the shared Uninstall-ScheduledTaskService helper.
	Stops the task, unregisters it, and removes the wrapper script.
.OUTPUTS
	[void]
#>
function Uninstall-QdrantService {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Mandatory = $false)]
		[bool]$IsAutoApprove = $false
	)

	$taskInfo = Get-QdrantTaskInfo
	if ($taskInfo.IsPreLogin -and -not (Test-IsAdministrator)) {
		if (Invoke-AsAdministrator -Key "uninstalltask" -IsAutoApprove:$IsAutoApprove) { return }
	}

	if ($PSCmdlet.ShouldProcess($global:qdrantServiceTaskName, "Uninstall Qdrant Scheduled Task")) {
		Uninstall-ScheduledTaskService -TaskName $global:qdrantServiceTaskName -WrapperScriptPath $global:qdrantServiceWrapperPath
	}
}

#==============================================================================
# Function: Start-QdrantService
#==============================================================================
<#
.SYNOPSIS
	Starts the Qdrant Scheduled Task "service".
.DESCRIPTION
	Starts the scheduled task by name.
.OUTPUTS
	[void]
#>
function Start-QdrantService {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param()

	$taskName = $global:qdrantServiceTaskName
	if ($PSCmdlet.ShouldProcess($taskName, "Start Scheduled Task")) {
		Start-ScheduledTask -TaskName $taskName
	}
}

#==============================================================================
# Function: Stop-QdrantService
#==============================================================================
<#
.SYNOPSIS
	Stops the Qdrant Scheduled Task "service".
.DESCRIPTION
	Stops the scheduled task by name.
.OUTPUTS
	[void]
#>
function Stop-QdrantService {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param()

	$taskName = $global:qdrantServiceTaskName
	if ($PSCmdlet.ShouldProcess($taskName, "Stop Scheduled Task")) {
		Stop-ScheduledTask -TaskName $taskName
	}

	$killed = $false

	if (Test-Path -LiteralPath $global:qdrantServicePidPath) {
		try {
			$pidRaw = Get-Content -LiteralPath $global:qdrantServicePidPath -ErrorAction SilentlyContinue | Select-Object -First 1
			[int]$procId = 0
			if ([int]::TryParse([string]$pidRaw, [ref]$procId) -and $procId -gt 0) {
				$proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
				if ($proc -and $proc.Path -and $proc.Path -like "*qdrant.exe") {
					if ($PSCmdlet.ShouldProcess("PID $procId", "Stop Qdrant process")) {
						Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
						$killed = $true
					}
				}
				elseif ($proc) {
					Write-Warning "PID file points to '$($proc.ProcessName)' (PID $procId), not qdrant. Ignoring PID file."
				}
			}
		}
		catch {
			Write-Verbose "Failed to stop Qdrant process by PID."
		}
	}

	if (-not $killed) {
		$procs = @(Get-Process qdrant -ErrorAction SilentlyContinue)
		if ($procs.Count -gt 0) {
			foreach ($p in $procs) {
				if ($p.Path -and $p.Path -like "*\\ProgramData\\Qdrant\\qdrant.exe") {
					if ($PSCmdlet.ShouldProcess("PID $($p.Id)", "Stop Qdrant process")) {
						Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
					}
				}
			}
		}
	}
}

#==============================================================================
# Function: Uninstall-Qdrant
#==============================================================================
<#
.SYNOPSIS
	Uninstalls Qdrant from ProgramData.
.DESCRIPTION
	Prompts the user to remove Qdrant binaries/config and optionally delete storage.
.OUTPUTS
	[void]
#>
function Uninstall-Qdrant {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[array]$AutoApproveList = @(),

		[Parameter(Mandatory = $false)]
		[bool]$IsAutoApprove = $false,

		[Parameter(Mandatory = $false)]
		[switch]$SkipAppRemoval
	)

	Write-Host ""
	Write-Host "Qdrant uninstall" -ForegroundColor White
	Write-Host "-------------------------------------------" -ForegroundColor Yellow
	Write-Host "Install root : $global:installRoot" -ForegroundColor Cyan
	Write-Host "Storage      : $global:storageRoot" -ForegroundColor Cyan
	Write-Host "Settings     : $global:settingsPath" -ForegroundColor Cyan

	if (-not (Test-Path -LiteralPath $global:installRoot)) {
		Write-Host "Nothing to uninstall (folder not found)." -ForegroundColor DarkGray
		return
	}

	$deleteDataBool = Invoke-AutoApprovedYesNo -Description "Delete Qdrant data folder '$($global:storageRoot)'" `
		-Key "deleteData" -DefaultValue $false `
		-AutoApproveList $AutoApproveList -IsAutoApprove:$IsAutoApprove
	$deleteAllBool = if ($SkipAppRemoval) { $false } else {
		Invoke-AutoApprovedYesNo -Description "Delete ALL Qdrant files under '$($global:installRoot)'" `
			-Key "deleteAll" -DefaultValue $true `
			-AutoApproveList $AutoApproveList -IsAutoApprove:$IsAutoApprove
	}
	$deleteData = if ($deleteDataBool) { "Y" } else { "N" }
	$deleteAll = if ($deleteAllBool) { "Y" } else { "N" }

	try {
		if ($deleteAll -eq "Y") {
			if ($deleteData -eq "Y") {
				Remove-Item -LiteralPath $global:installRoot -Recurse -Force -ErrorAction Stop
				Write-Host "Removed: $($global:installRoot)" -ForegroundColor Green
				return
			}

			# Delete everything except storage
			$items = Get-ChildItem -LiteralPath $global:installRoot -Force -ErrorAction SilentlyContinue
			foreach ($item in $items) {
				if ($item.FullName -ieq $global:storageRoot) { continue }
				Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
			}
			Write-Host "Removed Qdrant files (kept storage)." -ForegroundColor Green
		}
		elseif ($deleteData -eq "Y") {
			Remove-Item -LiteralPath $global:storageRoot -Recurse -Force -ErrorAction SilentlyContinue
			Write-Host "Removed storage folder." -ForegroundColor Green
		}
		else {
			Write-Host "No changes made." -ForegroundColor DarkGray
		}
	}
	catch {
		Write-Warning "Uninstall encountered an error: $_"
	}
}

#==============================================================================
# Function: Invoke-AsAdministrator
#==============================================================================
<#
.SYNOPSIS
	Re-launches the script elevated for a specific menu choice.
.DESCRIPTION
	When the current session is not running as Administrator, starts a new elevated
	PowerShell process that re-runs this script with the -AutoChoice parameter.
	Returns $true if elevation was attempted (caller should skip local execution),
	or $false if already elevated (caller should execute locally).
.PARAMETER Choice
	The menu choice number to pass to the elevated process.
.OUTPUTS
	[bool]
#>
function Invoke-AsAdministrator {
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Key,

		[Parameter(Mandatory = $false)]
		[bool]$IsAutoApprove = $false
	)

	if (Test-IsAdministrator) {
		return $false
	}

	Write-Host "This operation requires Administrator privileges. Elevating..." -ForegroundColor Yellow
	try {
		$argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-ElevatedKey", $Key)
		if ($IsAutoApprove) { $argList += @("-AutoApprove") }
		$proc = Start-Process -FilePath "PowerShell.exe" `
			-ArgumentList $argList `
			-Verb RunAs -Wait -PassThru
		if ($proc.ExitCode -ne 0) {
			Write-Warning "Elevated operation completed with exit code $($proc.ExitCode)."
		}
	}
	catch {
		Write-Warning "UAC elevation was declined or failed: $_"
	}
	return $true
}

#==============================================================================
# Function: Write-QdrantStatus
#==============================================================================
<#
.SYNOPSIS
	Prints the current Qdrant installation and service state to the console.
.DESCRIPTION
	Shows whether the binary is installed, which ports are configured, whether
	a scheduled task exists (and its type), and whether qdrant.exe is running.
	Displayed before the menu on each loop iteration.
.OUTPUTS
	[void]
#>
function Write-QdrantStatus {
	[CmdletBinding()]
	param()

	$appInstalled = Test-Path -LiteralPath $global:qdrantExePath
	$settings = Get-QdrantSetting
	$taskInfo = Get-QdrantTaskInfo
	$proc = Get-Process qdrant -ErrorAction SilentlyContinue |
		Where-Object { $_.Path -and $_.Path -like "*\ProgramData\Qdrant\qdrant.exe" } |
		Select-Object -First 1

	Write-Host ""
	Write-Host "--- Qdrant Status ---" -ForegroundColor Yellow
	if ($appInstalled) {
		Write-Host "  App     : Installed  ($($global:qdrantExePath))" -ForegroundColor Green
	}
	else {
		Write-Host "  App     : Not installed" -ForegroundColor DarkGray
	}

	if (Test-Path -LiteralPath $global:storageRoot) {
		Write-Host "  Data    : $global:storageRoot" -ForegroundColor Cyan
	}
	else {
		Write-Host "  Data    : Not found  ($global:storageRoot)" -ForegroundColor DarkGray
	}

	if (Test-Path -LiteralPath $global:settingsPath) {
		Write-Host "  Ports   : HTTP $($settings.HttpPort)  gRPC $($settings.GrpcPort)" -ForegroundColor Cyan
	}
	else {
		Write-Host "  Ports   : Not configured" -ForegroundColor DarkGray
	}

	if ($taskInfo.Exists) {
		$taskLabel = if ($taskInfo.IsPreLogin) { "System Task (pre-login)" } else { "User Task (post-login)" }
		$task = Get-ScheduledTask -TaskName $global:qdrantServiceTaskName -ErrorAction SilentlyContinue
		$taskState = if ($task) { $task.State } else { "Unknown" }
		Write-Host "  Task    : $taskLabel  [$taskState]" -ForegroundColor Cyan
	}
	else {
		Write-Host "  Task    : Not registered" -ForegroundColor DarkGray
	}

	if ($proc) {
		Write-Host "  Process : Running  (PID $($proc.Id))" -ForegroundColor Green
	}
	else {
		Write-Host "  Process : Not running" -ForegroundColor DarkGray
	}
	Write-Host "---------------------" -ForegroundColor Yellow
}

#==============================================================================
# Main
#==============================================================================

if (-not [string]::IsNullOrWhiteSpace($ElevatedKey)) {
	switch ($ElevatedKey) {
		"uninstalltask" { Uninstall-QdrantService -IsAutoApprove:$AutoApprove.IsPresent }
		default         { Write-Warning "Unknown elevated key: $ElevatedKey" }
	}
	Write-Host ""
	Write-Host "Press any key to close..." -ForegroundColor DarkGray
	$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
	return
}

$existingTask  = Get-QdrantTaskInfo
$taskTypeLabel = if ($existingTask.Exists -and $existingTask.IsPreLogin) { "System Task (admin)" } elseif ($existingTask.Exists) { "User Task" } else { "Task" }

$menuItems = @(
	[PSCustomObject]@{ key = "installapp";        name = "Install App" }
	[PSCustomObject]@{ key = "startconsole";      name = "Start Console" }
	[PSCustomObject]@{ key = "installsystemtask"; name = "Install System Task (pre-login, admin)" }
	[PSCustomObject]@{ key = "installusertask";   name = "Install User Task (post-login)" }
	[PSCustomObject]@{ key = "starttask";         name = "Start $taskTypeLabel" }
	[PSCustomObject]@{ key = "stoptask";          name = "Stop $taskTypeLabel" }
	[PSCustomObject]@{ key = "uninstalltask";     name = "Uninstall $taskTypeLabel" }
	[PSCustomObject]@{ key = "uninstallapp";      name = "Uninstall App" }
	[PSCustomObject]@{ key = "uninstalldata";     name = "Uninstall Data" }
	[PSCustomObject]@{ key = "exit";              name = "Exit" }
) | ConvertTo-Json | ConvertFrom-Json

$menuAutoRun = if ($AutoApprove.IsPresent -and $scriptSettings -and $scriptSettings.menuAction) { $scriptSettings.menuAction } else { $null }

$menuActions = @{
	"installapp"        = { Install-Qdrant -IsAutoApprove:$AutoApprove.IsPresent }
	"startconsole"      = { Start-QdrantConsole }
	"uninstallapp"      = { Uninstall-Qdrant -AutoApproveList $autoApproveList -IsAutoApprove:$AutoApprove.IsPresent }
	"uninstalldata"     = { Uninstall-Qdrant -SkipAppRemoval -AutoApproveList $autoApproveList -IsAutoApprove:$AutoApprove.IsPresent }
	"installsystemtask" = { Install-QdrantService -PreLogin -IsAutoApprove:$AutoApprove.IsPresent }
	"installusertask"   = { Install-QdrantService -IsAutoApprove:$AutoApprove.IsPresent }
	"starttask"         = { if (-not (Test-Path -LiteralPath $global:settingsPath)) { Write-Warning "Qdrant requires saved settings. Run 'Install App' first." } else { Start-QdrantService } }
	"stoptask"          = { Stop-QdrantService }
	"uninstalltask"     = { Uninstall-QdrantService -IsAutoApprove:$AutoApprove.IsPresent }
}

Invoke-MenuLoop -MenuTitle "Qdrant (Windows)" -MenuItems $menuItems -ActionMap $menuActions `
	-ExitKey "exit" -AutoRunKey $menuAutoRun -StatusBlock { Write-QdrantStatus }
