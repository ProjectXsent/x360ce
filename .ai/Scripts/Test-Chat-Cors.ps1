# PowerShell script to test CORS preflight and GET request.
$url = "https://chat.jocys.com/webhook/00000000-0000-0000-0000-000000000000"
$origin = "https://localhost:8080"

Write-Host "OPTIONS Preflight Request to $url with Origin $origin"
$response = Invoke-WebRequest -Uri $url -Method OPTIONS -Headers @{Origin = $origin }
Write-Host "Status: $($response.StatusCode)"
Write-Host "Response Headers:"
# Print response headers with names and values
# Enumerate and print header names and values correctly
$response.Headers.GetEnumerator() | ForEach-Object {
    $name = $_.Key
    $value = if ($_.Value -is [System.Array]) { $_.Value -join ", " } else { $_.Value }
    Write-Host "${name}: ${value}"
}

Write-Host ""
Write-Host "GET Request to $url with Origin $origin"
$response = Invoke-WebRequest -Uri $url -Method GET -Headers @{Origin = $origin }
Write-Host "Status: $($response.StatusCode)"
Write-Host "Response Headers:"
# Print response headers with names and values
# Enumerate and print header names and values
$response.Headers.GetEnumerator() | ForEach-Object {
    $name = $_.Key
    $value = if ($_.Value -is [System.Array]) { $_.Value -join ", " } else { $_.Value }
    Write-Host "${name}: ${value}"
}