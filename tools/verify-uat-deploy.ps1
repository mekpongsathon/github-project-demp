<#
.SYNOPSIS
    End-to-end verification of the UAT Deploy Tracking workflow.

.DESCRIPTION
    Phases:
      1. Validate Project V2 fields + options (auto-creates if missing)
      2. Validate repository configuration (Variables + Secrets)
      3. Resolve issues in Project V2
      4. Simulate Deploying -> Success flow
      5. Read-back verification
      6. Troubleshooting output + final checklist

    Usage:
        .\tools\verify-uat-deploy.ps1 -Issues "19,20"
        .\tools\verify-uat-deploy.ps1 -Issues "19,20" -Version "1.0.0-verify"

.PARAMETER Issues
    Comma-separated issue numbers (must already be in Project V2).

.PARAMETER Version
    Deploy version string written on success.
#>
param(
    [Parameter(Mandatory)][string]$Issues,
    [string]$Version = ("verify-" + (Get-Date -Format "yyyyMMddHHmm"))
)

. "$PSScriptRoot\_github.ps1"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
$script:checkList    = [ordered]@{}
$script:mutationErrs = [System.Collections.Generic.List[hashtable]]::new()
$script:gqlError     = $null

function Set-Check {
    param([string]$Key, [bool]$Pass, [string]$Note = "")
    $script:checkList[$Key] = @{ pass = $Pass; note = $Note }
}
function Write-Step { param([string]$Msg) Write-Host ("`n>>" + " " + $Msg) -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host ("  [OK]   " + $Msg) -ForegroundColor Green }
function Write-FAIL { param([string]$Msg) Write-Host ("  [FAIL] " + $Msg) -ForegroundColor Red }
function Write-WARN { param([string]$Msg) Write-Host ("  [WARN] " + $Msg) -ForegroundColor Yellow }
function Write-INFO { param([string]$Msg) Write-Host ("         " + $Msg) -ForegroundColor Gray }

function Invoke-SafeGQL {
    # Calls GitHub GraphQL. Sets $script:gqlError on failure, returns $null.
    param([string]$Query, [hashtable]$Variables = @{})
    $script:gqlError = $null
    $tkn  = [System.Environment]::GetEnvironmentVariable("GITHUB_TOKEN")
    $body = (@{ query = $Query; variables = $Variables } | ConvertTo-Json -Depth 10)
    $hdrs = @{
        Authorization  = "bearer $tkn"
        "Content-Type" = "application/json"
        "User-Agent"   = "github-workflow-ps"
    }
    try {
        $resp = Invoke-RestMethod -Uri "https://api.github.com/graphql" `
            -Method POST -Headers $hdrs -Body $body
        if ($resp.errors) {
            $script:gqlError = "GraphQL: " + (($resp.errors | ForEach-Object { $_.message }) -join "; ")
            return $null
        }
        return $resp.data
    } catch {
        $script:gqlError = "HTTP: " + $_.Exception.Message
        return $null
    }
}

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
$envFile = Join-Path (Get-Location) ".env"
if (-not (Test-Path $envFile)) {
    Write-Error "No .env file found. Copy .env.example to .env and configure it."
    exit 1
}
Get-Content $envFile | ForEach-Object {
    if ($_ -match "^\s*([^#][^=]+)=(.+)$") {
        $k = $Matches[1].Trim(); $v = $Matches[2].Trim().Trim('"').Trim("'")
        [System.Environment]::SetEnvironmentVariable($k, $v, "Process")
    }
}

$token     = [System.Environment]::GetEnvironmentVariable("GITHUB_TOKEN")
$projectId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_PROJECT_ID")
$owner     = [System.Environment]::GetEnvironmentVariable("GITHUB_OWNER")
$repo      = [System.Environment]::GetEnvironmentVariable("GITHUB_REPO")

if (-not $token -or -not $projectId -or -not $owner -or -not $repo) {
    Write-Error "GITHUB_TOKEN, WORKFLOW_PROJECT_ID, GITHUB_OWNER, GITHUB_REPO must all be set in .env"
    exit 1
}

$issueNumbers = $Issues -split "\s*,\s*" | ForEach-Object { [int]$_.Trim() }

Write-Host ""
Write-Host ("=" * 68) -ForegroundColor White
Write-Host "    UAT Deploy Tracking -- End-to-End Verification" -ForegroundColor White
Write-Host ("=" * 68) -ForegroundColor White
Write-Host ("  Project : " + $projectId)
Write-Host ("  Repo    : " + $owner + "/" + $repo)
Write-Host ("  Issues  : " + (($issueNumbers | ForEach-Object { "#$_" }) -join ", "))
Write-Host ("  Version : " + $Version)
Write-Host ""

# ===========================================================================
# PHASE 1 -- Validate Project V2 fields
# ===========================================================================
Write-Step "Phase 1 -- Validate Project V2 fields"

$q1 = @'
query($project: ID!) {
  node(id: $project) {
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
'@
$fieldsData = Invoke-SafeGQL -Query $q1 -Variables @{ project = $projectId }

if ($null -eq $fieldsData) {
    Write-FAIL ("Cannot query Project V2 fields: " + $script:gqlError)
    Write-INFO "Possible causes: invalid WORKFLOW_PROJECT_ID or GITHUB_TOKEN lacks 'project' scope"
    Set-Check "Project fields queryable" $false $script:gqlError
    exit 1
}
$fields = $fieldsData.node.fields.nodes
Set-Check "Project fields queryable" $true

# -- UAT Deploy Version (text) -----------------------------------------------
$versionField = $fields | Where-Object { $_.name -eq "UAT Deploy Version" -and $_.__typename -eq "ProjectV2Field" }
if ($versionField) {
    Write-OK ("UAT Deploy Version (text)  ID: " + $versionField.id)
    $versionFieldId = $versionField.id
    Set-Check "Field: UAT Deploy Version" $true
} else {
    $collision = $fields | Where-Object { $_.name -eq "UAT Deploy Version" }
    if ($collision) {
        Write-FAIL ("'UAT Deploy Version' wrong type: " + $collision.__typename + " (expected ProjectV2Field)")
        Write-INFO "Fix: rename/delete in GitHub UI -> Project Settings -> Fields"
        Set-Check "Field: UAT Deploy Version" $false ("type mismatch: " + $collision.__typename)
        exit 1
    }
    Write-WARN "'UAT Deploy Version' missing -- creating..."
    $mCreate = @'
mutation($project: ID!) {
  createProjectV2Field(input: {
    projectId: $project
    dataType: TEXT
    name: "UAT Deploy Version"
  }) {
    projectV2Field {
      ... on ProjectV2Field { id name }
    }
  }
}
'@
    $cd = Invoke-SafeGQL -Query $mCreate -Variables @{ project = $projectId }
    if ($null -eq $cd -or -not $cd.createProjectV2Field.projectV2Field.id) {
        $detail = if ($script:gqlError) { $script:gqlError } else { "Mutation returned no ID" }
        Write-FAIL ("Failed to create 'UAT Deploy Version': " + $detail)
        $script:mutationErrs.Add(@{ mutation = "createProjectV2Field(TEXT)"; cause = $detail; fix = "Ensure GITHUB_TOKEN has write:project scope" })
        Set-Check "Field: UAT Deploy Version" $false $detail
        exit 1
    }
    $versionFieldId = $cd.createProjectV2Field.projectV2Field.id
    Write-OK ("'UAT Deploy Version' created  ID: " + $versionFieldId)
    Set-Check "Field: UAT Deploy Version" $true "auto-created"
}

# -- UAT Deploy Status (single-select) ----------------------------------------
$requiredOpts = @("Deploying", "Success", "Failed")
$statusField = $fields | Where-Object { $_.name -eq "UAT Deploy Status" -and $_.__typename -eq "ProjectV2SingleSelectField" }
if ($statusField) {
    $existingNames = $statusField.options | Select-Object -ExpandProperty name
    $missingOpts   = $requiredOpts | Where-Object { $_ -notin $existingNames }
    if ($missingOpts) {
        Write-FAIL ("'UAT Deploy Status' missing options: " + ($missingOpts -join ", "))
        Write-INFO "Fix: add them in GitHub UI -> Project Settings -> 'UAT Deploy Status' field"
        Set-Check "Field: UAT Deploy Status" $false ("missing options: " + ($missingOpts -join ", "))
        exit 1
    }
    Write-OK ("UAT Deploy Status (single-select)  ID: " + $statusField.id)
    foreach ($opt in $statusField.options) { Write-INFO ("  Option '" + $opt.name + "'  ID: " + $opt.id) }
    $statusFieldId     = $statusField.id
    $deployingOptionId = ($statusField.options | Where-Object { $_.name -eq "Deploying" }).id
    $successOptionId   = ($statusField.options | Where-Object { $_.name -eq "Success"   }).id
    $failedOptionId    = ($statusField.options | Where-Object { $_.name -eq "Failed"    }).id
    Set-Check "Field: UAT Deploy Status" $true
    Set-Check "Status options: Deploying/Success/Failed" $true
} else {
    $collision = $fields | Where-Object { $_.name -eq "UAT Deploy Status" }
    if ($collision) {
        Write-FAIL ("'UAT Deploy Status' wrong type: " + $collision.__typename)
        Set-Check "Field: UAT Deploy Status" $false "type mismatch"
        exit 1
    }
    Write-WARN "'UAT Deploy Status' missing -- creating with Deploying/Success/Failed..."
    $mStatus = @'
mutation($project: ID!) {
  createProjectV2Field(input: {
    projectId: $project
    dataType: SINGLE_SELECT
    name: "UAT Deploy Status"
    singleSelectOptions: [
      { name: "Deploying", color: YELLOW, description: "Deployment in progress" }
      { name: "Success",   color: GREEN,  description: "Deployment succeeded"   }
      { name: "Failed",    color: RED,    description: "Deployment failed"      }
    ]
  }) {
    projectV2Field {
      ... on ProjectV2SingleSelectField { id name options { id name } }
    }
  }
}
'@
    $cd = Invoke-SafeGQL -Query $mStatus -Variables @{ project = $projectId }
    $newField = if ($cd) { $cd.createProjectV2Field.projectV2Field } else { $null }
    if ($null -eq $newField) {
        $detail = if ($script:gqlError) { $script:gqlError } else { "Mutation returned empty field" }
        Write-FAIL ("Failed to create 'UAT Deploy Status': " + $detail)
        $script:mutationErrs.Add(@{ mutation = "createProjectV2Field(SINGLE_SELECT)"; cause = $detail; fix = "Ensure GITHUB_TOKEN has write:project scope" })
        Set-Check "Field: UAT Deploy Status" $false $detail
        exit 1
    }
    $statusFieldId     = $newField.id
    $deployingOptionId = ($newField.options | Where-Object { $_.name -eq "Deploying" }).id
    $successOptionId   = ($newField.options | Where-Object { $_.name -eq "Success"   }).id
    $failedOptionId    = ($newField.options | Where-Object { $_.name -eq "Failed"    }).id
    Write-OK ("'UAT Deploy Status' created  ID: " + $statusFieldId)
    foreach ($opt in $newField.options) { Write-INFO ("  Option '" + $opt.name + "'  ID: " + $opt.id) }
    Set-Check "Field: UAT Deploy Status" $true "auto-created"
    Set-Check "Status options: Deploying/Success/Failed" $true "auto-created"
}

# Write IDs back to .env and process env
$uatUpdates = [ordered]@{
    WORKFLOW_UAT_DEPLOY_VERSION_FIELD_ID = $versionFieldId
    WORKFLOW_UAT_DEPLOY_STATUS_FIELD_ID  = $statusFieldId
    WORKFLOW_DEPLOYING_OPTION_ID         = $deployingOptionId
    WORKFLOW_DEPLOY_SUCCESS_OPTION_ID    = $successOptionId
    WORKFLOW_DEPLOY_FAILED_OPTION_ID     = $failedOptionId
}
$envContent = Get-Content $envFile -Raw
foreach ($kv in $uatUpdates.GetEnumerator()) {
    $pat = "(?m)^" + [regex]::Escape($kv.Key) + "=.*$"
    if ($envContent -match $pat) {
        $envContent = [regex]::Replace($envContent, $pat, ($kv.Key + "=" + $kv.Value))
    } else {
        $envContent = $envContent.TrimEnd() + "`n" + $kv.Key + "=" + $kv.Value + "`n"
    }
    [System.Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "Process")
}
try {
    Set-Content $envFile $envContent -NoNewline
    Write-INFO "IDs written to .env"
} catch {
    Write-WARN (".env write failed (file locked?) -- IDs still set in process env: " + $_.Exception.Message)
}

# ===========================================================================
# PHASE 2 -- Validate repository configuration
# ===========================================================================
Write-Step "Phase 2 -- Validate repository configuration"

$authHdrs = @{
    Authorization          = "bearer $token"
    Accept                 = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent"           = "github-workflow-ps"
}
$repoBase = "https://api.github.com/repos/" + $owner + "/" + $repo

$requiredVars = @(
    "WORKFLOW_PROJECT_ID",
    "WORKFLOW_STATUS_FIELD_ID",
    "WORKFLOW_IN_PROGRESS_OPTION_ID",
    "WORKFLOW_CODE_REVIEW_OPTION_ID",
    "WORKFLOW_DONE_OPTION_ID",
    "WORKFLOW_UAT_DEPLOY_STATUS_FIELD_ID",
    "WORKFLOW_UAT_DEPLOY_VERSION_FIELD_ID",
    "WORKFLOW_DEPLOYING_OPTION_ID",
    "WORKFLOW_DEPLOY_SUCCESS_OPTION_ID",
    "WORKFLOW_DEPLOY_FAILED_OPTION_ID"
)

try {
    $varsResp = Invoke-RestMethod -Uri ($repoBase + "/actions/variables?per_page=100") `
        -Method GET -Headers $authHdrs
    $existingVarNames = $varsResp.variables | Select-Object -ExpandProperty name
    $missingVars = $requiredVars | Where-Object { $_ -notin $existingVarNames }
    if ($missingVars) {
        Write-WARN (("Missing " + $missingVars.Count + "/" + $requiredVars.Count + " Repository Variables:"))
        foreach ($v in $missingVars) { Write-INFO ("  MISSING  " + $v) }
        Write-INFO "Set at: Repo -> Settings -> Secrets and variables -> Actions -> Variables"
        Write-INFO "Run .\tools\setup-uat-fields.ps1 to get the UAT field IDs."
        Set-Check "Repository Variables" $false ("missing: " + ($missingVars -join ", "))
    } else {
        Write-OK ("All " + $requiredVars.Count + " Repository Variables are set")
        Set-Check "Repository Variables" $true
    }
} catch {
    Write-WARN ("Cannot list Repository Variables: " + $_.Exception.Message)
    Set-Check "Repository Variables" $false "Cannot list -- check token permissions"
}

try {
    $secrResp = Invoke-RestMethod -Uri ($repoBase + "/actions/secrets?per_page=30") `
        -Method GET -Headers $authHdrs
    $existingSecrets = $secrResp.secrets | Select-Object -ExpandProperty name
    if ("PAT_TOKEN" -notin $existingSecrets) {
        Write-FAIL "Secret PAT_TOKEN is NOT set"
        Write-INFO "Set at: Repo -> Settings -> Secrets and variables -> Actions -> Secrets"
        Set-Check "Secret: PAT_TOKEN" $false "missing"
    } else {
        Write-OK "Secret PAT_TOKEN is set"
        Set-Check "Secret: PAT_TOKEN" $true
    }
} catch {
    Write-WARN ("Cannot list Secrets: " + $_.Exception.Message)
    Set-Check "Secret: PAT_TOKEN" $false "Cannot list -- check token permissions"
}

# ===========================================================================
# PHASE 3 -- Resolve issues in Project V2
# ===========================================================================
Write-Step "Phase 3 -- Resolve issues in Project V2"

$q2 = @'
query($project: ID!) {
  node(id: $project) {
    ... on ProjectV2 {
      items(first: 100) {
        nodes {
          id
          content { ... on Issue { id number title } }
        }
      }
    }
  }
}
'@
$piData = Invoke-SafeGQL -Query $q2 -Variables @{ project = $projectId }
if ($null -eq $piData) {
    Write-FAIL ("Cannot fetch Project V2 items: " + $script:gqlError)
    Set-Check "Issues resolved in Project V2" $false $script:gqlError
    exit 1
}
$allItems = $piData.node.items.nodes

$issueMap    = [ordered]@{}
$allResolved = $true

foreach ($num in $issueNumbers) {
    $q3 = @'
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) { id number title }
  }
}
'@
    $id = Invoke-SafeGQL -Query $q3 -Variables @{ owner = $owner; repo = $repo; number = $num }
    if ($null -eq $id -or $null -eq $id.repository.issue) {
        Write-FAIL ("Issue #" + $num + " not found: " + $script:gqlError)
        $allResolved = $false
        continue
    }
    $issueNode = $id.repository.issue
    $item = $allItems | Where-Object { $_.content -and $_.content.id -eq $issueNode.id }
    if (-not $item) {
        Write-FAIL ("Issue #" + $num + " '" + $issueNode.title + "' is NOT in Project V2")
        Write-INFO "Fix: add it via GitHub UI -> Project -> + Add item"
        $allResolved = $false
        continue
    }
    Write-OK ("Issue #" + $num + " '" + $issueNode.title + "'")
    Write-INFO ("  Issue node ID : " + $issueNode.id)
    Write-INFO ("  Project item  : " + $item.id)
    $issueMap["$num"] = @{ issueId = $issueNode.id; itemId = $item.id; title = $issueNode.title; number = $num }
}

Set-Check "Issues resolved in Project V2" $allResolved
if (-not $allResolved) {
    Write-FAIL "Cannot proceed -- one or more issues not found in Project V2"
    exit 1
}

# ===========================================================================
# PHASE 4 -- Simulation: Deploying -> Success
# ===========================================================================
Write-Step "Phase 4 -- Simulation: UAT Deploy flow"

$mSetSingleSelect = @'
mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $project
    itemId:    $item
    fieldId:   $field
    value: { singleSelectOptionId: $option }
  }) {
    projectV2Item { id }
  }
}
'@

$mSetText = @'
mutation($project: ID!, $item: ID!, $field: ID!, $text: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $project
    itemId:    $item
    fieldId:   $field
    value: { text: $text }
  }) {
    projectV2Item { id }
  }
}
'@

function Set-UATStatus {
    param([hashtable]$Issue, [string]$OptionId, [string]$Label)
    $r = Invoke-SafeGQL -Query $script:mSetSingleSelect -Variables @{
        project = $projectId; item = $Issue.itemId; field = $statusFieldId; option = $OptionId
    }
    if ($null -eq $r) {
        Write-FAIL ("Issue #" + $Issue.number + " status -> " + $Label + " FAILED: " + $script:gqlError)
        $script:mutationErrs.Add(@{
            mutation = ("updateProjectV2ItemFieldValue(singleSelect) status=" + $Label + " optionId=" + $OptionId)
            cause    = $script:gqlError
            fix      = ("Verify option ID '" + $OptionId + "' exists in field '" + $statusFieldId + "'")
        })
        return $false
    }
    return $true
}

function Set-UATVersion {
    param([hashtable]$Issue, [string]$VersionStr)
    $r = Invoke-SafeGQL -Query $script:mSetText -Variables @{
        project = $projectId; item = $Issue.itemId; field = $versionFieldId; text = $VersionStr
    }
    if ($null -eq $r) {
        Write-FAIL ("Issue #" + $Issue.number + " version -> '" + $VersionStr + "' FAILED: " + $script:gqlError)
        $script:mutationErrs.Add(@{
            mutation = ("updateProjectV2ItemFieldValue(text) version=" + $VersionStr)
            cause    = $script:gqlError
            fix      = ("Verify field ID '" + $versionFieldId + "' is a text field in the project")
        })
        return $false
    }
    return $true
}

# Step 1: Deploying
Write-Host ""
Write-Host "  Step 1/3 -- Set UAT Deploy Status = Deploying"
$deployingOk = $true
foreach ($entry in $issueMap.Values) {
    $ok = Set-UATStatus -Issue $entry -OptionId $deployingOptionId -Label "Deploying"
    if ($ok) { Write-OK ("Issue #" + $entry.number + " '" + $entry.title + "' -> Deploying") }
    else     { $deployingOk = $false }
}
Set-Check "Deploy status: Deploying" $deployingOk

# Step 2: Fake deploy
Write-Host ""
Write-Host "  Step 2/3 -- Fake deploy running..."
Write-INFO "[....] Pulling image..."
Start-Sleep -Milliseconds 600
Write-INFO "[....] Starting containers..."
Start-Sleep -Milliseconds 600
Write-INFO "[OK  ] Health check passed"
Write-INFO "[OK  ] Smoke test passed"

# Step 3: Success + version
Write-Host ""
Write-Host ("  Step 3/3 -- Set UAT Deploy Status = Success + version = " + $Version)
$successOk = $true
$versionOk  = $true
foreach ($entry in $issueMap.Values) {
    $ok = Set-UATStatus -Issue $entry -OptionId $successOptionId -Label "Success"
    if ($ok) {
        $vok = Set-UATVersion -Issue $entry -VersionStr $Version
        if ($vok) { Write-OK ("Issue #" + $entry.number + " '" + $entry.title + "' -> Success | version: " + $Version) }
        else      { $versionOk = $false }
    } else {
        $successOk = $false; $versionOk = $false
    }
}
Set-Check "Deploy status: Success" $successOk
Set-Check "Deploy version written" $versionOk

# ===========================================================================
# PHASE 5 -- Read-back verification
# ===========================================================================
Write-Step "Phase 5 -- Read-back verification"

$qReadBack = @'
query($item: ID!) {
  node(id: $item) {
    ... on ProjectV2Item {
      statusVal:  fieldValueByName(name: "UAT Deploy Status") {
        ... on ProjectV2ItemFieldSingleSelectValue { name }
      }
      versionVal: fieldValueByName(name: "UAT Deploy Version") {
        ... on ProjectV2ItemFieldTextValue { text }
      }
    }
  }
}
'@

$allVerified = $true
foreach ($entry in $issueMap.Values) {
    $rb = Invoke-SafeGQL -Query $qReadBack -Variables @{ item = $entry.itemId }
    if ($null -eq $rb) {
        Write-WARN ("Read-back failed for Issue #" + $entry.number + ": " + $script:gqlError)
        $allVerified = $false
        continue
    }
    $readStatus  = $rb.node.statusVal.name
    $readVersion = $rb.node.versionVal.text
    if (($readStatus -eq "Success") -and ($readVersion -eq $Version)) {
        Write-OK ("Issue #" + $entry.number + " -- Status: " + $readStatus + " | Version: " + $readVersion)
    } else {
        if ($readStatus  -ne "Success") { Write-FAIL ("Issue #" + $entry.number + " Status  = '" + $readStatus  + "' (expected 'Success')") }
        if ($readVersion -ne $Version)  { Write-FAIL ("Issue #" + $entry.number + " Version = '" + $readVersion + "' (expected '" + $Version + "')") }
        $allVerified = $false
    }
}
Set-Check "Read-back verified" $allVerified

# ===========================================================================
# PHASE 6A -- Troubleshooting output
# ===========================================================================
if ($script:mutationErrs.Count -gt 0) {
    Write-Step ("Troubleshooting -- " + $script:mutationErrs.Count + " mutation failure(s)")
    $i = 1
    foreach ($e in $script:mutationErrs) {
        Write-Host ("`n  Failure #" + $i) -ForegroundColor Red
        Write-INFO ("  Mutation : " + $e.mutation)
        Write-INFO ("  Cause    : " + $e.cause)
        Write-INFO ("  Fix      : " + $e.fix)
        $i++
    }
}

# ===========================================================================
# PHASE 6B -- Final verification checklist
# ===========================================================================
Write-Host ""
Write-Host ("=" * 68) -ForegroundColor White
Write-Host "    Final Verification Checklist" -ForegroundColor White
Write-Host ("=" * 68) -ForegroundColor White
Write-Host ""

$allPassed = $true
$failCount = 0
foreach ($kv in $script:checkList.GetEnumerator()) {
    $icon  = if ($kv.Value.pass) { "[PASS]" } else { "[FAIL]" }
    $color = if ($kv.Value.pass) { "Green" }  else { "Red"   }
    $note  = if ($kv.Value.note) { "  (" + $kv.Value.note + ")" } else { "" }
    Write-Host ("  " + ("{0,-8}" -f $icon) + " " + $kv.Key + $note) -ForegroundColor $color
    if (-not $kv.Value.pass) { $allPassed = $false; $failCount++ }
}

Write-Host ""
if ($allPassed) {
    Write-Host "  RESULT: All checks passed. UAT deploy tracking is working end-to-end." -ForegroundColor Green
} else {
    Write-Host ("  RESULT: " + $failCount + " check(s) failed. Review items above and re-run.") -ForegroundColor Red
}
Write-Host ""
