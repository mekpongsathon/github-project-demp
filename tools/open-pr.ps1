<#
.SYNOPSIS
    Create a PR with Closes references, and update linked issues to Code Review.

.DESCRIPTION
    Usage:
        .\tools\open-pr.ps1 -Issues 2,3,4
        .\tools\open-pr.ps1 -Issues 2,3,4 -Title "feat: my PR title" -Reviewers "user1","user2"

.PARAMETER Issues
    Issue numbers to reference with Closes #.

.PARAMETER Title
    PR title. Auto-generated if omitted.

.PARAMETER Reviewers
    Optional GitHub usernames to request review from.
#>
param(
    [Parameter(Mandatory)][int[]]$Issues,
    [string]$Title,
    [string[]]$Reviewers = @(),
    [switch]$DryRun
)

. "$PSScriptRoot\_github.ps1"
if ($DryRun) { $global:DryRun = $true; Write-Host "[DRY-RUN MODE]" -ForegroundColor Yellow }
Get-EnvConfig

$owner  = [System.Environment]::GetEnvironmentVariable("GITHUB_OWNER")
$repo   = [System.Environment]::GetEnvironmentVariable("GITHUB_REPO")
$branch = git branch --show-current

$prTitle    = if ($Title) { $Title } else { "feat: implement issues $($Issues | ForEach-Object { "#$_" })" }
$closingRefs = ($Issues | ForEach-Object { "Closes #$_" }) -join "`n"
$body        = "$closingRefs`n`n---`n_PR created via github-workflow-ps_"

Write-Host "`n>> open-pr"
Write-Host "  Branch: $branch"
Write-Host "  Issues: $($Issues | ForEach-Object { "#$_" })"
Write-Host "  Title:  $prTitle`n"

# Step 1: create PR via REST API
Write-Host "-> Creating PR..."
$pr = Invoke-GitHubREST -Path "/repos/$owner/$repo/pulls" -Method POST -Body @{
    title = $prTitle
    head  = $branch
    base  = "main"
    body  = $body
    draft = $false
}
Write-Host "  OK PR #$($pr.number) created: $($pr.html_url)`n"

# Step 2: assign reviewers if provided
if ($Reviewers.Count -gt 0) {
    Write-Host "-> Assigning reviewers: $($Reviewers -join ', ')..."
    Invoke-GitHubREST -Path "/repos/$owner/$repo/pulls/$($pr.number)/requested_reviewers" `
        -Method POST -Body @{ reviewers = $Reviewers } | Out-Null
    Write-Host "  OK Reviewers assigned`n"
}

# Step 3: update Project V2 -> Code Review
$optionId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_CODE_REVIEW_OPTION_ID")
Write-Host "-> Updating Project V2 statuses -> Code Review..."
Update-IssuesStatus -IssueNumbers $Issues -OptionId $optionId -Label "Code Review"

Write-Host "`nDONE: open-pr complete"
Write-Host "   PR:     #$($pr.number) — $prTitle"
Write-Host "   URL:    $($pr.html_url)"
Write-Host "   Issues: $($Issues | ForEach-Object { "#$_" }) -> Code Review"
