<#
.SYNOPSIS
    Update UAT deploy status and version in Project V2 for specified issues.

.DESCRIPTION
    Usage:
        .\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Version "0.0.52" -Status success
        .\tools\update-deploy.ps1 -Issues "123"     -Environment uat -Status deploying
        .\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Status failed

    Requires setup-uat-fields.ps1 to have been run at least once.

.PARAMETER Issues
    Comma-separated issue numbers (e.g. "123,124").

.PARAMETER Environment
    Deployment environment. Currently supported: uat.

.PARAMETER Version
    Version string to record in "UAT Deploy Version" field (e.g. "0.0.52").
    Applied only when -Status is "success".

.PARAMETER Status
    Deploy status: deploying | success | failed.
#>
param(
    [Parameter(Mandatory)][string]$Issues,
    [Parameter(Mandatory)][ValidateSet("uat")][string]$Environment,
    [string]$Version = "",
    [Parameter(Mandatory)][ValidateSet("deploying","success","failed")][string]$Status
)

. "$PSScriptRoot\_github.ps1"
Get-EnvConfig

# Parse issue numbers from comma-separated string
$issueNumbers = $Issues -split "\s*,\s*" | ForEach-Object { [int]$_.Trim() }

Write-Host "`n>> update-deploy"
Write-Host "  Environment: $Environment"
Write-Host "  Issues:      $($issueNumbers | ForEach-Object { "#$_" })"
Write-Host "  Status:      $Status"
if ($Version -and $Status -eq "success") {
    Write-Host "  Version:     $Version"
}
Write-Host ""

Invoke-UATDeployUpdate -IssueNumbers $issueNumbers -Status $Status -Version $Version

Write-Host "`nDONE: update-deploy complete"
