<#
.SYNOPSIS
    Validate and automatically create required UAT deploy fields in GitHub Project V2.

.DESCRIPTION
    Checks for "UAT Deploy Version" (text) and "UAT Deploy Status" (single-select)
    fields. Creates them via GitHub GraphQL API if missing.
    Writes discovered IDs to .env and prints the GitHub Repository Variables to set.

    Usage:
        .\tools\setup-uat-fields.ps1

    Requires in .env:
        GITHUB_TOKEN, WORKFLOW_PROJECT_ID
#>

. "$PSScriptRoot\_github.ps1"

# Load env manually — don't require all workflow vars for this setup script
$envFile = Join-Path (Get-Location) ".env"
if (-not (Test-Path $envFile)) {
    Write-Error "No .env file found. Copy .env.example to .env and set GITHUB_TOKEN + WORKFLOW_PROJECT_ID."
    exit 1
}
Get-Content $envFile | ForEach-Object {
    if ($_ -match "^\s*([^#][^=]+)=(.+)$") {
        $key = $Matches[1].Trim(); $val = $Matches[2].Trim().Trim('"').Trim("'")
        [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
    }
}

$token     = [System.Environment]::GetEnvironmentVariable("GITHUB_TOKEN")
$projectId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_PROJECT_ID")
if (-not $token)     { Write-Error "Set GITHUB_TOKEN in .env";          exit 1 }
if (-not $projectId) { Write-Error "Set WORKFLOW_PROJECT_ID in .env";   exit 1 }

Write-Host "`n>> setup-uat-fields — Project: $projectId`n"

# ── Query all existing fields ──────────────────────────────────────────────────
$data = Invoke-GitHubGraphQL -Query @"
query(`$project: ID!) {
  node(id: `$project) {
    ... on ProjectV2 {
      fields(first: 50) {
        nodes {
          __typename
          ... on ProjectV2Field              { id name }
          ... on ProjectV2SingleSelectField  { id name options { id name } }
          ... on ProjectV2IterationField     { id name }
        }
      }
    }
  }
}
"@ -Variables @{ project = $projectId }

$fields = $data.node.fields.nodes

# ── 1. Validate "UAT Deploy Version" (text field) ─────────────────────────────
Write-Host "-- Checking 'UAT Deploy Version' (text field)..."
$versionField = $fields | Where-Object { $_.name -eq "UAT Deploy Version" -and $_.__typename -eq "ProjectV2Field" }

if ($versionField) {
    Write-Host "   FOUND  ID: $($versionField.id)" -ForegroundColor Green
    $versionFieldId = $versionField.id
} else {
    # Check for name collision with wrong type
    $collision = $fields | Where-Object { $_.name -eq "UAT Deploy Version" }
    if ($collision) {
        Write-Host "   MISMATCH: field 'UAT Deploy Version' exists but type is $($collision.__typename), expected ProjectV2Field (text)" -ForegroundColor Red
        Write-Host "   Fix: rename or delete the existing field in GitHub UI → Project Settings → Fields" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "   MISSING — creating text field..." -ForegroundColor Yellow
    $createResult = Invoke-GitHubGraphQL -Query @"
mutation(`$project: ID!) {
  createProjectV2Field(input: {
    projectId: `$project
    dataType: TEXT
    name: "UAT Deploy Version"
  }) {
    projectV2Field {
      ... on ProjectV2Field { id name }
    }
  }
}
"@ -Variables @{ project = $projectId }
    $versionFieldId = $createResult.createProjectV2Field.projectV2Field.id
    if (-not $versionFieldId) {
        Write-Error "Failed to create 'UAT Deploy Version' field. Check API response."
        exit 1
    }
    Write-Host "   CREATED  ID: $versionFieldId" -ForegroundColor Green
}

# ── 2. Validate "UAT Deploy Status" (single-select) ───────────────────────────
Write-Host "`n-- Checking 'UAT Deploy Status' (single-select field)..."
$requiredOptions = @("Deploying", "Success", "Failed")
$statusField = $fields | Where-Object { $_.name -eq "UAT Deploy Status" -and $_.__typename -eq "ProjectV2SingleSelectField" }

$statusFieldId     = $null
$deployingOptionId = $null
$successOptionId   = $null
$failedOptionId    = $null

if ($statusField) {
    Write-Host "   FOUND  ID: $($statusField.id)" -ForegroundColor Green
    $statusFieldId = $statusField.id

    $existingOptionNames = $statusField.options | Select-Object -ExpandProperty name
    $missingOptions = $requiredOptions | Where-Object { $_ -notin $existingOptionNames }

    if ($missingOptions) {
        Write-Host "   MISMATCH: missing options: $($missingOptions -join ', ')" -ForegroundColor Red
        Write-Host "   Fix: add these options manually in GitHub UI → Project Settings → 'UAT Deploy Status' field:" -ForegroundColor Yellow
        foreach ($opt in $missingOptions) { Write-Host "     - $opt" -ForegroundColor Yellow }
        exit 1
    }

    Write-Host "   OK     options: $($requiredOptions -join ', ')" -ForegroundColor Green
    $deployingOptionId = ($statusField.options | Where-Object { $_.name -eq "Deploying" }).id
    $successOptionId   = ($statusField.options | Where-Object { $_.name -eq "Success" }).id
    $failedOptionId    = ($statusField.options | Where-Object { $_.name -eq "Failed" }).id

} else {
    $collision = $fields | Where-Object { $_.name -eq "UAT Deploy Status" }
    if ($collision) {
        Write-Host "   MISMATCH: field 'UAT Deploy Status' exists but type is $($collision.__typename), expected ProjectV2SingleSelectField" -ForegroundColor Red
        exit 1
    }

    Write-Host "   MISSING — creating single-select field with options..." -ForegroundColor Yellow
    $createResult = Invoke-GitHubGraphQL -Query @"
mutation(`$project: ID!) {
  createProjectV2Field(input: {
    projectId: `$project
    dataType: SINGLE_SELECT
    name: "UAT Deploy Status"
    singleSelectOptions: [
      { name: "Deploying", color: YELLOW, description: "Deployment in progress" }
      { name: "Success",   color: GREEN,  description: "Deployment succeeded"   }
      { name: "Failed",    color: RED,    description: "Deployment failed"      }
    ]
  }) {
    projectV2Field {
      ... on ProjectV2SingleSelectField {
        id name options { id name }
      }
    }
  }
}
"@ -Variables @{ project = $projectId }

    $newField = $createResult.createProjectV2Field.projectV2Field
    if (-not $newField) {
        Write-Error "Failed to create 'UAT Deploy Status' field. Check API response."
        exit 1
    }
    $statusFieldId     = $newField.id
    $deployingOptionId = ($newField.options | Where-Object { $_.name -eq "Deploying" }).id
    $successOptionId   = ($newField.options | Where-Object { $_.name -eq "Success" }).id
    $failedOptionId    = ($newField.options | Where-Object { $_.name -eq "Failed" }).id

    Write-Host "   CREATED  ID: $statusFieldId" -ForegroundColor Green
    Write-Host "     Option 'Deploying': $deployingOptionId" -ForegroundColor Green
    Write-Host "     Option 'Success':   $successOptionId"   -ForegroundColor Green
    Write-Host "     Option 'Failed':    $failedOptionId"    -ForegroundColor Green
}

# ── 3. Write IDs to .env ───────────────────────────────────────────────────────
$updates = [ordered]@{
    WORKFLOW_UAT_DEPLOY_VERSION_FIELD_ID = $versionFieldId
    WORKFLOW_UAT_DEPLOY_STATUS_FIELD_ID  = $statusFieldId
    WORKFLOW_DEPLOYING_OPTION_ID         = $deployingOptionId
    WORKFLOW_DEPLOY_SUCCESS_OPTION_ID    = $successOptionId
    WORKFLOW_DEPLOY_FAILED_OPTION_ID     = $failedOptionId
}

$envContent = Get-Content $envFile -Raw
foreach ($kv in $updates.GetEnumerator()) {
    if ($envContent -match "(?m)^$($kv.Key)=") {
        $envContent = $envContent -replace "(?m)^$($kv.Key)=.*$", "$($kv.Key)=$($kv.Value)"
    } else {
        $envContent = $envContent.TrimEnd() + "`n$($kv.Key)=$($kv.Value)`n"
    }
}
Set-Content $envFile $envContent -NoNewline
Write-Host "`n   OK  IDs written to .env" -ForegroundColor Green

# ── 4. Print GitHub Repository Variables to set ───────────────────────────────
Write-Host "`n>> Set these as GitHub Repository Variables:"
Write-Host "   Repo → Settings → Secrets and variables → Actions → Variables tab`n"
foreach ($kv in $updates.GetEnumerator()) {
    Write-Host "   $($kv.Key) = $($kv.Value)"
}

Write-Host "`nDONE: UAT deploy fields ready."
