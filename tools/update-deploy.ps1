<#
.SYNOPSIS
    Update Project V2 deploy field for issues linked to a PR.

.DESCRIPTION
    Usage:
        .\tools\update-deploy.ps1 -PR 42 -Env dev -Status deployed
        .\tools\update-deploy.ps1 -PR 42 -Env uat -Status deploying

.PARAMETER PR
    PR number to look up linked issues from.

.PARAMETER Env
    Deployment environment: dev, uat, or prod.

.PARAMETER Status
    Deploy status: waiting, deploying, deployed, or failed.
#>
param(
    [Parameter(Mandatory)][int]$PR,
    [Parameter(Mandatory)][ValidateSet("dev","uat","prod")][string]$Env,
    [Parameter(Mandatory)][ValidateSet("waiting","deploying","deployed","failed")][string]$Status
)

. "$PSScriptRoot\_github.ps1"
Get-EnvConfig

$owner = [System.Environment]::GetEnvironmentVariable("GITHUB_OWNER")
$repo  = [System.Environment]::GetEnvironmentVariable("GITHUB_REPO")

$fieldEnvMap = @{
    dev  = "WORKFLOW_DEPLOY_DEV_FIELD_ID"
    uat  = "WORKFLOW_DEPLOY_UAT_FIELD_ID"
    prod = "WORKFLOW_DEPLOY_PROD_FIELD_ID"
}

# Option IDs differ per environment (each deploy field has its own option IDs)
$optionEnvVar = "WORKFLOW_DEPLOY_$($Env.ToUpper())_$($Status.ToUpper())_OPTION_ID"

$fieldId  = [System.Environment]::GetEnvironmentVariable($fieldEnvMap[$Env])
$optionId = [System.Environment]::GetEnvironmentVariable($optionEnvVar)

if (-not $fieldId) {
    Write-Error "Missing field ID for env=$Env. Set $($fieldEnvMap[$Env]) in .env"
    exit 1
}
if (-not $optionId) {
    Write-Error "Missing option ID for env=$Env status=$Status. Set $optionEnvVar in .env"
    exit 1
}

Write-Host "`n>> update-deploy: PR #$PR -> $Env: $Status`n"

# Get linked issues from PR
$data = Invoke-GitHubGraphQL -Query @"
query(`$owner: String!, `$repo: String!, `$number: Int!) {
  repository(owner: `$owner, name: `$repo) {
    pullRequest(number: `$number) {
      closingIssuesReferences(first: 20) {
        nodes { id number }
      }
    }
  }
}
"@ -Variables @{ owner = $owner; repo = $repo; number = $PR }

$issues = $data.repository.pullRequest.closingIssuesReferences.nodes

if (-not $issues -or $issues.Count -eq 0) {
    Write-Host "No linked issues found on PR #$PR — skipping"
    exit 0
}

Write-Host "Linked issues: $($issues | ForEach-Object { "#$($_.number)" })"

foreach ($issue in $issues) {
    $itemId = Get-ProjectItemId -IssueNodeId $issue.id
    if (-not $itemId) {
        Write-Warning "  WARN:  Issue #$($issue.number) not in Project V2 — skipped"
        continue
    }
    Update-ProjectField -ItemId $itemId -FieldId $fieldId -OptionId $optionId
    Write-Host "  OK  Issue #$($issue.number) -> $Env: $Status"
}

Write-Host "`nDONE: update-deploy complete"
