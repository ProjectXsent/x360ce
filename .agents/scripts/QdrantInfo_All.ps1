<#
.SYNOPSIS
  Sets Qdrant collection aliases for all repositories under a root folder.

.DESCRIPTION
  1) Lists all Qdrant collections matching "ws-*" in a single API call.
  2) Scans directories at depth 2 and 3 under Root for repository folders.
  3) For each candidate, computes the ws-{hash} collection name (same algorithm
     as QdrantInfo.ps1) and derives the alias from the path.
  4) Matches computed hashes against existing Qdrant collections.
  5) Sets all aliases in a single bulk API call.

.PARAMETER Root
  Root folder that contains organization folders.
  Default: c:\Projects

.PARAMETER QdrantUrl
  The URL of the Qdrant instance. Defaults to "http://127.0.0.1:6333".

.PARAMETER ApiKey
  The API Key for Qdrant authentication.

.PARAMETER WhatIf
  Shows what would be executed without making any changes.

.EXAMPLE
  .\QdrantInfo_All.ps1

.EXAMPLE
  .\QdrantInfo_All.ps1 -Root c:\Projects -ApiKey "xyz"

.EXAMPLE
  .\QdrantInfo_All.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$Root = 'c:\Projects',
  [string]$QdrantUrl = 'http://127.0.0.1:6333',
  [string]$ApiKey = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- 1. Fetch all ws-* collections from Qdrant ---

Write-Host "Connecting to $QdrantUrl..." -ForegroundColor Gray

$headers = @{}
if (-not [string]::IsNullOrEmpty($ApiKey)) {
  $headers['api-key'] = $ApiKey
}

try {
  $collectionsResponse = Invoke-RestMethod -Uri "$QdrantUrl/collections" -Method Get -Headers $headers -ErrorAction Stop
}
catch {
  Write-Error "Failed to connect to Qdrant at $QdrantUrl : $_"
  exit 1
}

$wsCollections = @{}
foreach ($col in $collectionsResponse.result.collections) {
  if ($col.name -like 'ws-*') {
    $wsCollections[$col.name] = $true
  }
}

Write-Host "Found $($wsCollections.Count) workspace collections in Qdrant." -ForegroundColor Cyan

# --- 2. Scan directories and build hash -> alias map ---

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
  Write-Error "Root folder does not exist: $Root"
  exit 1
}

$sha256 = [System.Security.Cryptography.SHA256]::Create()
$encoding = [System.Text.Encoding]::UTF8

# Directories to skip during recursive scan (heavy, never contain workspaces).
# Dot-prefixed directories (e.g. .git, .vs, .nuget) are skipped separately.
$skipNames = [System.Collections.Generic.HashSet[string]]::new(
  [string[]]@('node_modules', 'bin', 'obj', 'packages', 'dist', 'out',
               'build', 'vendor', '__pycache__', 'TestResults', 'coverage',
               'target', 'artifacts'),
  [System.StringComparer]::OrdinalIgnoreCase
)

# collection name -> { Path, Alias }
$matched = @{}
$candidateCount = 0
$remaining = $wsCollections.Count

Write-Host "Scanning $Root for repositories..." -ForegroundColor Gray

# Recursive scan using a stack with depth tracking.
# Max depth relative to Root (e.g. Root\Org\Project\Repo\Sub1\Sub2 = depth 5).
$maxDepth = 8
$rootDepth = $Root.Split('\').Count

# Stack stores directory paths; depth is derived from path segment count.
$stack = [System.Collections.Generic.Stack[string]]::new()
foreach ($org in Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop) {
  $stack.Push($org.FullName)
}

while ($stack.Count -gt 0 -and $remaining -gt 0) {
  $dir = $stack.Pop()
  $currentDepth = $dir.Split('\').Count - $rootDepth

  $children = @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)
  if ($children.Count -gt 64) { continue }

  foreach ($sub in $children) {
    if ($sub.Name.StartsWith('.') -or $skipNames.Contains($sub.Name)) { continue }

    $candidateCount++
    $p = $sub.FullName
    $hp = $p
    if ($p -match '^([a-zA-Z]):(.*)$') { $hp = $Matches[1].ToLower() + ':' + $Matches[2] }
    $bytes = $encoding.GetBytes($hp)
    $hashBytes = $sha256.ComputeHash($bytes)
    $hashHex = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
    $cn = 'ws-' + $hashHex.Substring(0, 16)

    if ($wsCollections.ContainsKey($cn) -and -not $matched.ContainsKey($cn)) {
      $alias = $p
      if ($p -match '^[a-zA-Z]:[\\/]Projects[\\/](.+)$') { $alias = $Matches[1] }
      $matched[$cn] = [PSCustomObject]@{ Path = $p; Alias = $alias }
      $remaining--
    }

    # Only recurse deeper if below max depth
    if ($currentDepth -lt $maxDepth) {
      $stack.Push($sub.FullName)
    }
  }
}

Write-Host "Scanned $candidateCount candidate folders." -ForegroundColor Gray
Write-Host "Matched $($matched.Count) of $($wsCollections.Count) collections to local repositories." -ForegroundColor Cyan

if ($matched.Count -eq 0) {
  Write-Host "Nothing to do." -ForegroundColor Yellow
  return
}

# --- 3. Display matches ---

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
$index = 0
foreach ($kv in $matched.GetEnumerator()) {
  $index++
  Write-Host "[$index] " -NoNewline -ForegroundColor DarkGray
  Write-Host "$($kv.Key)" -NoNewline -ForegroundColor Green
  Write-Host " -> " -NoNewline
  Write-Host "$($kv.Value.Alias)" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Magenta

# Report unmatched collections
$unmatched = $wsCollections.Keys | Where-Object { -not $matched.ContainsKey($_) }
if ($unmatched) {
  Write-Host ""
  Write-Host "Unmatched collections (no local repo found):" -ForegroundColor DarkYellow
  foreach ($u in $unmatched) {
    Write-Host "  $u" -ForegroundColor DarkGray
  }
}

# --- 4. Set all aliases in a single bulk API call ---

$actions = @()
foreach ($kv in $matched.GetEnumerator()) {
  $actions += @{
    create_alias = @{
      collection_name = $kv.Key
      alias_name      = $kv.Value.Alias
    }
  }
}

$body = @{ actions = $actions } | ConvertTo-Json -Depth 4

if ($PSCmdlet.ShouldProcess("$($actions.Count) aliases", 'Set Qdrant aliases')) {
  try {
    $response = Invoke-RestMethod -Uri "$QdrantUrl/collections/aliases" -Method Post -Body $body -ContentType 'application/json' -Headers $headers -ErrorAction Stop
    if ($response.result -eq $true) {
      Write-Host ""
      Write-Host "SUCCESS: All $($actions.Count) aliases set." -ForegroundColor Cyan
    }
    else {
      Write-Error "Unexpected response: $($response | ConvertTo-Json -Depth 2)"
    }
  }
  catch {
    Write-Error "Failed to set aliases: $_"
  }
}
