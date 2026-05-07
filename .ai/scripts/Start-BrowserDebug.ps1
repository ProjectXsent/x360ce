<#
.SYNOPSIS
  Launches Microsoft Edge with Chrome DevTools Protocol (CDP) enabled on a fixed port.

.DESCRIPTION
  Starts an interactive browser session (not automated/headless by default) so the user can:
  - sign in
  - accept cookies
  - complete MFA / other auth flows

  This is useful when automation tools (e.g., puppeteer) struggle with consent dialogs.

  The script launches Edge with:
    --remote-debugging-port=<Port>
    --user-data-dir=<UserDataDir>

  Using a dedicated user profile directory keeps the session isolated and makes it easy to clean up.

.PARAMETER Url
  Optional. URL to open on launch.

.PARAMETER Port
  Optional. Remote debugging port (default: 9222).

.PARAMETER UserDataDir
  Optional. User-data-dir folder to store the temporary Edge profile.
  Defaults to: %TEMP%\EdgeDebug_<Port>

.PARAMETER InPrivate
  Optional. Launch Edge InPrivate. Note: InPrivate may not persist logins.

.PARAMETER CleanUserDataDir
  Optional. Deletes the UserDataDir before launching.

.PARAMETER Headless
  Optional. Launch Edge headless. Not recommended for interactive login/cookie acceptance.

.EXAMPLE
  .\.ai\scripts\Start-BrowserDebug.ps1 -Url 'https://docs.n8n.io/'

.EXAMPLE
  .\.ai\scripts\Start-BrowserDebug.ps1 -Port 9222 -CleanUserDataDir
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [string]$Url,

  [Parameter(Mandatory = $false)]
  [int]$Port = 9222,

  [Parameter(Mandatory = $false)]
  [string]$UserDataDir,

  [Parameter(Mandatory = $false)]
  [switch]$InPrivate,

  [Parameter(Mandatory = $false)]
  [switch]$CleanUserDataDir,

  [Parameter(Mandatory = $false)]
  [switch]$Headless
)

function Write-Info([string]$Msg) { Write-Host "[INFO]  $Msg" -ForegroundColor Cyan }
function Write-Warn([string]$Msg) { Write-Host "[WARN]  $Msg" -ForegroundColor Yellow }
function Write-Err([string]$Msg)  { Write-Host "[ERROR] $Msg" -ForegroundColor Red }

$ErrorActionPreference = 'Stop'

if (-not $UserDataDir -or [string]::IsNullOrWhiteSpace($UserDataDir)) {
  $UserDataDir = Join-Path $env:TEMP ("EdgeDebug_{0}" -f $Port)
}

if ($CleanUserDataDir -and (Test-Path $UserDataDir)) {
  Write-Info "Deleting user data dir: $UserDataDir"
  Remove-Item $UserDataDir -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $UserDataDir)) {
  New-Item -ItemType Directory -Path $UserDataDir | Out-Null
}

# Find Edge
$edgeCandidates = @(
  (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"),
  (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe")
) | Where-Object { $_ -and (Test-Path $_) }

if ($edgeCandidates.Count -eq 0) {
  Write-Err "Microsoft Edge (msedge.exe) not found under Program Files."
  throw "Edge not found"
}

# Ensure we pass a real string path to Start-Process (not an array/char[])
$edgeExe = [string]($edgeCandidates | Select-Object -First 1)

$args = @(
  "--remote-debugging-port=$Port",
  "--user-data-dir=$UserDataDir",
  "--no-first-run",
  "--no-default-browser-check",
  "--disable-features=Translate"
)

if ($InPrivate) { $args += "--inprivate" }
if ($Headless)  { $args += "--headless=new"; $args += "--disable-gpu" }

if ($Url -and -not [string]::IsNullOrWhiteSpace($Url)) {
  $args += $Url
}

Write-Info "Launching Edge with CDP on port $Port"
Write-Info "Edge: $edgeExe"
Write-Info "UserDataDir: $UserDataDir"
if ($Url) { Write-Info "URL: $Url" }

$proc = Start-Process -FilePath $edgeExe -ArgumentList $args -PassThru

Write-Host "PID: $($proc.Id)"
Write-Host "CDP endpoint (usually): http://127.0.0.1:$Port/json/version"
Write-Host "Tip: keep this browser window open while using tools that attach to port $Port."