$token = (Get-Content "$PSScriptRoot\..\env" -ErrorAction SilentlyContinue)
if (-not $token) { $token = (Get-Content "$PSScriptRoot\..\.env") }
$token = ($token | Where-Object { $_ -match "^GITHUB_TOKEN=" }) -replace "GITHUB_TOKEN=", ""

$h = @{Authorization="bearer $token"; "Content-Type"="application/json"; "User-Agent"="ps"}
$projectId = "PVT_kwHOApQkuM4BXcog"

foreach ($num in @(23, 24)) {
    # Get issue node ID
    $gq = '{"query":"{ repository(owner:\"mekpongsathon\" name:\"github-project-demp\") { issue(number:' + $num + ') { id } } }"}'
    $r = Invoke-RestMethod -Uri https://api.github.com/graphql -Method POST -Headers $h -Body $gq
    $issueId = $r.data.repository.issue.id

    # Add to project
    $mq = '{"query":"mutation { addProjectV2ItemById(input: { projectId: \"' + $projectId + '\" contentId: \"' + $issueId + '\" }) { item { id } } }"}'
    $mr = Invoke-RestMethod -Uri https://api.github.com/graphql -Method POST -Headers $h -Body $mq
    Write-Host "Added issue #$num (itemId: $($mr.data.addProjectV2ItemById.item.id))"
}

Write-Host "Done. Now run: .\tools\start-work.ps1 -Issues 23,24"
