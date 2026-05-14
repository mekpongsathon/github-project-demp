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

Write-Host "`n▶ discover-ids — Project: $projectId`n"

$data = Invoke-GitHubGraphQL -Query @"
query(`$project: ID!) {
  node(id: `$project) {
    ... on ProjectV2 {
      fields(first: 30) {
        nodes {
          __typename
          ... on ProjectV2SingleSelectField {
            id name
            options { id name }
          }
          ... on ProjectV2Field { id name }
        }
      }
    }
  }
}
"@ -Variables @{ project = $projectId }

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

Write-Host "Paste the above IDs into your .env file."
