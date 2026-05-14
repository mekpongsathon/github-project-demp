<#
.SYNOPSIS
    Create a branch, push it, and update linked issues to In Progress.

.DESCRIPTION
    Usage:
        .\tools\start-work.ps1 -Issues 2,3,4
        .\tools\start-work.ps1 -Issues 12 -Branch "feat/my-custom-branch"

.PARAMETER Issues
    One or more issue numbers to start work on.

.PARAMETER Branch
    Optional branch name. Auto-generated as feat/issues-{n1}-{n2}-... if omitted.
#>
param(
    [Parameter(Mandatory)][int[]]$Issues,
    [string]$Branch,
    [switch]$DryRun
)

. "$PSScriptRoot\_github.ps1"
if ($DryRun) { $global:DryRun = $true; Write-Host "[DRY-RUN MODE]" -ForegroundColor Yellow }
Get-EnvConfig

$branchName = if ($Branch) { $Branch } else { "feat/issues-$($Issues -join '-')" }

Write-Host "`n>> start-work: issues $($Issues | ForEach-Object { "#$_" }) "
Write-Host "  Branch: $branchName`n"

# Step 1: create and push branch
Write-Host "-> Creating and pushing branch..."
if ($DryRun) {
    Write-Host "  [DRY-RUN] git checkout -b $branchName" -ForegroundColor DarkGray
    Write-Host "  [DRY-RUN] git push -u origin $branchName" -ForegroundColor DarkGray
} else {
    git checkout -b $branchName
    git push -u origin $branchName
}
Write-Host "  OK Branch `"$branchName`" pushed`n"

# Step 2: update Project V2 -> In Progress
$optionId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_IN_PROGRESS_OPTION_ID")
Write-Host "-> Updating Project V2 statuses -> In Progress..."
Update-IssuesStatus -IssueNumbers $Issues -OptionId $optionId -Label "In Progress"

Write-Host "`nDONE: start-work complete"
Write-Host "   Branch: $branchName"
Write-Host "   Issues: $($Issues | ForEach-Object { "#$_" }) -> In Progress"
