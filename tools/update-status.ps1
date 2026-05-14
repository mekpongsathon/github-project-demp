<#
.SYNOPSIS
    Update Project V2 status for issues without touching git.

.DESCRIPTION
    Usage:
        .\tools\update-status.ps1 -Issues 2,3,4 -Status "In Progress"
        .\tools\update-status.ps1 -Issues 2,3,4 -Status "Code Review"
        .\tools\update-status.ps1 -Issues 2,3,4 -Status "Done"

.PARAMETER Issues
    Issue numbers to update.

.PARAMETER Status
    Target status: "In Progress", "Code Review", or "Done".
#>
param(
    [Parameter(Mandatory)][int[]]$Issues,
    [Parameter(Mandatory)]
    [ValidateSet("In Progress", "Code Review", "Done")]
    [string]$Status,
    [switch]$DryRun
)

. "$PSScriptRoot\_github.ps1"
if ($DryRun) { $global:DryRun = $true; Write-Host "[DRY-RUN MODE]" -ForegroundColor Yellow }
Get-EnvConfig

$optionEnvMap = @{
    "In Progress" = "WORKFLOW_IN_PROGRESS_OPTION_ID"
    "Code Review" = "WORKFLOW_CODE_REVIEW_OPTION_ID"
    "Done"        = "WORKFLOW_DONE_OPTION_ID"
}

$optionId = [System.Environment]::GetEnvironmentVariable($optionEnvMap[$Status])
if (-not $optionId) {
    Write-Error "Option ID for `"$Status`" is not configured. Set $($optionEnvMap[$Status]) in .env"
    exit 1
}

Write-Host "`n>> update-status: issues $($Issues | ForEach-Object { "#$_" }) -> $Status`n"
Update-IssuesStatus -IssueNumbers $Issues -OptionId $optionId -Label $Status

Write-Host "`nDONE: Done: $($Issues.Count) issue(s) -> $Status"
