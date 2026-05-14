# _github.ps1 — Shared GitHub API utilities
# Dot-source this file in other scripts: . "$PSScriptRoot\_github.ps1"

function Get-EnvConfig {
    # Load .env file if present
    $envFile = Join-Path (Get-Location) ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match "^\s*([^#][^=]+)=(.+)$") {
                $key = $Matches[1].Trim()
                $val = $Matches[2].Trim().Trim('"').Trim("'")
                if (-not [System.Environment]::GetEnvironmentVariable($key)) {
                    [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
                }
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
    return $item?.id
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
            Write-Warning "  ⚠  Issue #$num not found in Project V2 — skipped"
            continue
        }
        Update-ProjectField -ItemId $itemId -FieldId $fieldId -OptionId $OptionId
        Write-Host "  ✓  Issue #$num → $Label"
    }
}
