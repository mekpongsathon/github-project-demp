<#
.SYNOPSIS
    Query GitHub API to discover Project V2 field and option IDs.

.DESCRIPTION
    Usage:
        .\tools\discover-ids.ps1

    Requires GITHUB_TOKEN and WORKFLOW_PROJECT_ID in .env
#>

. "$PSScriptRoot\_github.ps1"

# Load env (only need TOKEN and PROJECT_ID)
$envFile = Join-Path (Get-Location) ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^\s*([^#][^=]+)=(.+)$") {
            $key = $Matches[1].Trim(); $val = $Matches[2].Trim().Trim('"').Trim("'")
            if (-not [System.Environment]::GetEnvironmentVariable($key)) {
                [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
            }
        }
    }
}

$projectId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_PROJECT_ID")
if (-not $projectId) {
    Write-Error "Set WORKFLOW_PROJECT_ID in .env first"
    exit 1
}

Write-Host "`n>> discover-ids — Project: $projectId`n"

$data = Invoke-GitHubGraphQL -Query @"
query(`$project: ID!) {
  node(id: `$project) {
    ... on ProjectV2 {
      fields(first: 50) {
        nodes {
          __typename
          ... on ProjectV2SingleSelectField {
            id name
            options { id name }
          }
          ... on ProjectV2Field         { id name }
          ... on ProjectV2IterationField { id name }
        }
      }
    }
  }
}
"@ -Variables @{ project = $projectId }

Write-Host "=== Single-Select Fields ==="
foreach ($field in $data.node.fields.nodes) {
    if ($field.__typename -eq "ProjectV2SingleSelectField") {
        Write-Host "Field: $($field.name)"
        Write-Host "  ID: $($field.id)"
        foreach ($opt in $field.options) {
            Write-Host "  Option `"$($opt.name)`": $($opt.id)"
        }
        Write-Host ""
    }
}

Write-Host "=== Text / Number / Date Fields ==="
foreach ($field in $data.node.fields.nodes) {
    if ($field.__typename -eq "ProjectV2Field") {
        Write-Host "Field: $($field.name)  ID: $($field.id)"
    }
}

# ── UAT Deploy field summary ───────────────────────────────────────────────────
Write-Host "`n=== UAT Deploy Field Mapping ==="
$uatStatusField  = $data.node.fields.nodes | Where-Object { $_.name -eq "UAT Deploy Status" }
$uatVersionField = $data.node.fields.nodes | Where-Object { $_.name -eq "UAT Deploy Version" }

if ($uatStatusField) {
    Write-Host "WORKFLOW_UAT_DEPLOY_STATUS_FIELD_ID  = $($uatStatusField.id)"
    foreach ($opt in $uatStatusField.options) {
        $envVar = switch ($opt.name) {
            "Deploying" { "WORKFLOW_DEPLOYING_OPTION_ID" }
            "Success"   { "WORKFLOW_DEPLOY_SUCCESS_OPTION_ID" }
            "Failed"    { "WORKFLOW_DEPLOY_FAILED_OPTION_ID" }
            default     { "WORKFLOW_UAT_$(($opt.name).ToUpper())_OPTION_ID" }
        }
        Write-Host "$envVar = $($opt.id)"
    }
} else {
    Write-Host "(UAT Deploy Status field not found — run .\tools\setup-uat-fields.ps1)"
}

if ($uatVersionField) {
    Write-Host "WORKFLOW_UAT_DEPLOY_VERSION_FIELD_ID = $($uatVersionField.id)"
} else {
    Write-Host "(UAT Deploy Version field not found — run .\tools\setup-uat-fields.ps1)"
}

Write-Host "`nPaste the above IDs into your .env file."
Write-Host "Or run .\tools\setup-uat-fields.ps1 to auto-discover and write them."
