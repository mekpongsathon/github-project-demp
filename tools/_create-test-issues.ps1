param([string]$TitleA = "[Test] Feature A", [string]$TitleB = "[Test] Feature B")

$token = (Get-Content "$PSScriptRoot\..\env" -ErrorAction SilentlyContinue) 
if (-not $token) { $token = (Get-Content "$PSScriptRoot\..\.env") }
$token = ($token | Where-Object { $_ -match "^GITHUB_TOKEN=" }) -replace "GITHUB_TOKEN=", ""

$h = @{
    Authorization = "bearer $token"
    Accept = "application/vnd.github+json"
    "User-Agent" = "ps"
    "Content-Type" = "application/json"
}

$repo = "mekpongsathon/github-project-demp"

$r1 = Invoke-RestMethod "https://api.github.com/repos/$repo/issues" -Method POST -Headers $h `
    -Body (ConvertTo-Json @{title=$TitleA; body="Test issue for workflow e2e"})
Write-Host "Created Issue #$($r1.number): $($r1.title)"

$r2 = Invoke-RestMethod "https://api.github.com/repos/$repo/issues" -Method POST -Headers $h `
    -Body (ConvertTo-Json @{title=$TitleB; body="Test issue for workflow e2e"})
Write-Host "Created Issue #$($r2.number): $($r2.title)"

Write-Host ""
Write-Host "Issue numbers: $($r1.number), $($r2.number)"
Write-Host "Run: .\tools\start-work.ps1 -Issues $($r1.number),$($r2.number)"
