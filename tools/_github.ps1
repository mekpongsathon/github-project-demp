# _github.ps1 — Shared GitHub API utilities
# Dot-source this file in other scripts: . "$PSScriptRoot\_github.ps1"

# Global dry-run flag — set before dot-sourcing or pass -DryRun to workflows
$global:DryRun = $false

function Get-EnvConfig {
    # Dry-run mode — skip token validation
    if ($global:DryRun) {
        Write-Host "  [DRY-RUN] Skipping env validation" -ForegroundColor DarkGray
        $defaults = @{
            GITHUB_OWNER                    = "mekpongsathon"
            GITHUB_REPO                     = "github-project-demp"
            WORKFLOW_PROJECT_ID             = "PVT_kwHOApQkuM4BXcog"
            WORKFLOW_STATUS_FIELD_ID        = "PVTSSF_lAHOApQkuM4BXcogzhSpamg"
            WORKFLOW_IN_PROGRESS_OPTION_ID  = "47fc9ee4"
            WORKFLOW_CODE_REVIEW_OPTION_ID  = "<CODE_REVIEW_OPTION_ID>"
            WORKFLOW_DONE_OPTION_ID         = "<DONE_OPTION_ID>"
        }
        foreach ($kv in $defaults.GetEnumerator()) {
            if (-not [System.Environment]::GetEnvironmentVariable($kv.Key)) {
                [System.Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "Process")
            }
        }
        return
    }
    # Load .env file if present — always overwrite to avoid stale process vars
    $envFile = Join-Path (Get-Location) ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match "^\s*([^#][^=]+)=(.+)$") {
                $key = $Matches[1].Trim()
                $val = $Matches[2].Trim().Trim('"').Trim("'")
                [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
            }
        }
    }

    $required = @(
        "GITHUB_TOKEN", "GITHUB_OWNER", "GITHUB_REPO",
        "WORKFLOW_PROJECT_ID", "WORKFLOW_STATUS_FIELD_ID",
        "WORKFLOW_IN_PROGRESS_OPTION_ID",
        "WORKFLOW_CODE_REVIEW_OPTION_ID",
        "WORKFLOW_DONE_OPTION_ID"
    )
    $missing = $required | Where-Object { -not [System.Environment]::GetEnvironmentVariable($_) }
    if ($missing) {
        Write-Error "Missing required environment variables:`n$($missing -join "`n")`n`nCopy .env.example to .env and fill in the values."
        exit 1
    }
}

function Invoke-GitHubGraphQL {
    param(
        [string]$Query,
        [hashtable]$Variables = @{}
    )
    if ($global:DryRun) {
        Write-Host "  [DRY-RUN] GraphQL mutation — variables: $($Variables | ConvertTo-Json -Compress)" -ForegroundColor DarkGray
        return @{}
    }
    $token = [System.Environment]::GetEnvironmentVariable("GITHUB_TOKEN")
    $body  = @{ query = $Query; variables = $Variables } | ConvertTo-Json -Depth 10
    $headers = @{
        Authorization  = "bearer $token"
        "Content-Type" = "application/json"
        "User-Agent"   = "github-workflow-ps"
    }
    $response = Invoke-RestMethod -Uri "https://api.github.com/graphql" `
        -Method POST -Headers $headers -Body $body
    if ($response.errors) {
        $msgs = ($response.errors | ForEach-Object { $_.message }) -join "; "
        Write-Error "GraphQL error: $msgs"
        exit 1
    }
    return $response.data
}

function Invoke-GitHubREST {
    param(
        [string]$Path,
        [string]$Method = "GET",
        [hashtable]$Body = $null
    )
    if ($global:DryRun) {
        Write-Host "  [DRY-RUN] REST $Method $Path" -ForegroundColor DarkGray
        if ($Path -match "/pulls$") {
            return [PSCustomObject]@{ number = 99; html_url = "https://github.com/mekpongsathon/github-project-demp/pull/99"; title = "dry-run PR" }
        }
        return @{}
    }
    $token = [System.Environment]::GetEnvironmentVariable("GITHUB_TOKEN")
    $headers = @{
        Authorization         = "bearer $token"
        Accept                = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent"          = "github-workflow-ps"
    }
    $params = @{
        Uri     = "https://api.github.com$Path"
        Method  = $Method
        Headers = $headers
    }
    if ($Body) {
        $params.Body        = ($Body | ConvertTo-Json -Depth 10)
        $params.ContentType = "application/json"
    }
    return Invoke-RestMethod @params
}

function Get-IssueNodeId {
    param([int]$IssueNumber)
    if ($global:DryRun) {
        Write-Host "  [DRY-RUN] Get-IssueNodeId #$IssueNumber" -ForegroundColor DarkGray
        return [PSCustomObject]@{ id = "DRY_ISSUE_${IssueNumber}"; number = $IssueNumber }
    }
    $owner = [System.Environment]::GetEnvironmentVariable("GITHUB_OWNER")
    $repo  = [System.Environment]::GetEnvironmentVariable("GITHUB_REPO")
    $data  = Invoke-GitHubGraphQL -Query @"
query(`$owner: String!, `$repo: String!, `$number: Int!) {
  repository(owner: `$owner, name: `$repo) {
    issue(number: `$number) { id number }
  }
}
"@ -Variables @{ owner = $owner; repo = $repo; number = $IssueNumber }
    return $data.repository.issue
}

function Get-ProjectItemId {
    param([string]$IssueNodeId)
    if ($global:DryRun) {
        Write-Host "  [DRY-RUN] Get-ProjectItemId for $IssueNodeId" -ForegroundColor DarkGray
        return "DRY_ITEM_${IssueNodeId}"
    }
    $projectId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_PROJECT_ID")
    $data = Invoke-GitHubGraphQL -Query @"
query(`$project: ID!) {
  node(id: `$project) {
    ... on ProjectV2 {
      items(first: 100) {
        nodes {
          id
          content { ... on Issue { id } }
        }
      }
    }
  }
}
"@ -Variables @{ project = $projectId }
    $item = $data.node.items.nodes | Where-Object { $_.content.id -eq $IssueNodeId }
    if ($item) { return $item.id } else { return $null }
}

function Update-ProjectField {
    param(
        [string]$ItemId,
        [string]$FieldId,
        [string]$OptionId
    )
    $projectId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_PROJECT_ID")
    Invoke-GitHubGraphQL -Query @"
mutation(`$project: ID!, `$item: ID!, `$field: ID!, `$option: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: `$project
    itemId: `$item
    fieldId: `$field
    value: { singleSelectOptionId: `$option }
  }) {
    projectV2Item { id }
  }
}
"@ -Variables @{
        project = $projectId
        item    = $ItemId
        field   = $FieldId
        option  = $OptionId
    } | Out-Null
}

function Get-ProjectFields {
    # Returns all fields of the configured Project V2 (useful for discovering IDs)
    $projectId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_PROJECT_ID")
    $data = Invoke-GitHubGraphQL -Query @"
query(`$project: ID!) {
  node(id: `$project) {
    ... on ProjectV2 {
      fields(first: 30) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id name
            options { id name }
          }
          ... on ProjectV2Field {
            id name
          }
        }
      }
    }
  }
}
"@ -Variables @{ project = $projectId }
    return $data.node.fields.nodes
}

function Update-IssuesStatus {
    param(
        [int[]]$IssueNumbers,
        [string]$OptionId,
        [string]$Label
    )
    $fieldId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_STATUS_FIELD_ID")
    foreach ($num in $IssueNumbers) {
        $issue  = Get-IssueNodeId -IssueNumber $num
        $itemId = Get-ProjectItemId -IssueNodeId $issue.id
        if (-not $itemId) {
            Write-Warning "  WARN:  Issue #$num not found in Project V2 — skipped"
            continue
        }
        Update-ProjectField -ItemId $itemId -FieldId $fieldId -OptionId $OptionId
        Write-Host "  OK  Issue #$num -> $Label"
    }
}

# ── UAT Deploy helpers ─────────────────────────────────────────────────────────

function Update-ProjectTextField {
    # Updates a free-text Project V2 field (value: { text: "..." })
    param(
        [string]$ItemId,
        [string]$FieldId,
        [string]$Text
    )
    if ($global:DryRun) {
        Write-Host "  [DRY-RUN] Update-ProjectTextField item=$ItemId field=$FieldId text=$Text" -ForegroundColor DarkGray
        return
    }
    $projectId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_PROJECT_ID")
    Invoke-GitHubGraphQL -Query @"
mutation(`$project: ID!, `$item: ID!, `$field: ID!, `$text: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: `$project
    itemId:    `$item
    fieldId:   `$field
    value: { text: `$text }
  }) {
    projectV2Item { id }
  }
}
"@ -Variables @{
        project = $projectId
        item    = $ItemId
        field   = $FieldId
        text    = $Text
    } | Out-Null
}

function Get-ProjectFieldByName {
    # Returns the first field whose name matches $FieldName, or $null.
    param([string]$FieldName)
    $projectId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_PROJECT_ID")
    $data = Invoke-GitHubGraphQL -Query @"
query(`$project: ID!) {
  node(id: `$project) {
    ... on ProjectV2 {
      fields(first: 50) {
        nodes {
          __typename
          ... on ProjectV2Field             { id name }
          ... on ProjectV2SingleSelectField { id name options { id name } }
          ... on ProjectV2IterationField    { id name }
        }
      }
    }
  }
}
"@ -Variables @{ project = $projectId }
    return $data.node.fields.nodes | Where-Object { $_.name -eq $FieldName } | Select-Object -First 1
}

function Invoke-UATDeployUpdate {
    # High-level: update UAT Deploy Status (single-select) and optionally
    # UAT Deploy Version (text) for a list of issue numbers.
    param(
        [int[]]$IssueNumbers,
        [string]$Status,         # "deploying" | "success" | "failed"
        [string]$Version = ""    # only applied when Status = "success"
    )
    $statusFieldId  = [System.Environment]::GetEnvironmentVariable("WORKFLOW_UAT_DEPLOY_STATUS_FIELD_ID")
    $versionFieldId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_UAT_DEPLOY_VERSION_FIELD_ID")

    $optionEnvMap = @{
        "deploying" = "WORKFLOW_DEPLOYING_OPTION_ID"
        "success"   = "WORKFLOW_DEPLOY_SUCCESS_OPTION_ID"
        "failed"    = "WORKFLOW_DEPLOY_FAILED_OPTION_ID"
    }
    $optionEnvVar = $optionEnvMap[$Status.ToLower()]
    if (-not $optionEnvVar) {
        Write-Error "Unknown Status '$Status'. Valid values: deploying, success, failed"
        exit 1
    }
    $optionId = [System.Environment]::GetEnvironmentVariable($optionEnvVar)

    if (-not $statusFieldId) {
        Write-Error "WORKFLOW_UAT_DEPLOY_STATUS_FIELD_ID not set. Run .\tools\setup-uat-fields.ps1 first."
        exit 1
    }
    if (-not $optionId) {
        Write-Error "$optionEnvVar not set. Run .\tools\setup-uat-fields.ps1 first."
        exit 1
    }

    foreach ($num in $IssueNumbers) {
        $issue  = Get-IssueNodeId -IssueNumber $num
        $itemId = Get-ProjectItemId -IssueNodeId $issue.id
        if (-not $itemId) {
            Write-Warning "  WARN:  Issue #$num not found in Project V2 — skipped"
            continue
        }

        # Update single-select status
        Update-ProjectField -ItemId $itemId -FieldId $statusFieldId -OptionId $optionId

        # Update text version (only on success, only when version provided and field ID known)
        $versionSuffix = ""
        if ($Status.ToLower() -eq "success" -and $Version -and $versionFieldId) {
            Update-ProjectTextField -ItemId $itemId -FieldId $versionFieldId -Text $Version
            $versionSuffix = " | version: $Version"
        }

        Write-Host "  OK  Issue #$num -> UAT: $Status$versionSuffix"
    }
}
