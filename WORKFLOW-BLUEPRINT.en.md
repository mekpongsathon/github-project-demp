# GitHub Project V2 — Workflow Automation Blueprint

> **For Copilot:** This file is a blueprint for setting up automated GitHub Project V2 workflow tracking.
> When the user asks to "setup workflow", follow the steps in [Setup Instructions for Copilot](#setup-instructions-for-copilot).

---

## Overview

This workflow automatically tracks GitHub Issue status through Project V2:

```
Todo → In Progress → Code Review → Done
```

| Trigger | Action |
|---------|--------|
| `start-work.ps1` | Creates branch + moves Issues → **In Progress** |
| `open-pr.ps1` | Creates PR + moves Issues → **Code Review** |
| PR merged | GitHub Actions → moves Issues → **Done** (automatically) |

---

## Setup Instructions for Copilot

When asked to set up this workflow, follow these phases in order:

### Phase 1 — Verify Prerequisites

Check the following and notify the user of anything missing:

```
[ ] 1. Git repository is initialized and has a remote origin
[ ] 2. GitHub Personal Access Token (PAT) — scopes: repo, project, workflow
[ ] 3. GitHub Project V2 exists and is linked to the repository
[ ] 4. Project V2 has a Status field (Single Select) with options: Todo, In Progress, Code Review, Done
[ ] 5. gh CLI is installed (required for GitHub Actions scripts)
```

**Show this message if the user does not have a PAT:**
```
⚠️  A GitHub Personal Access Token (PAT) is required.
    1. Go to GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
    2. Create a new token with scopes: Contents (R/W), Pull requests (R/W), Issues (R/W)
    3. Also grant Project permissions: Read and write
    4. Copy the token and paste it into your .env file at GITHUB_TOKEN=
```

**Show this message if the user does not have a Project V2:**
```
⚠️  A GitHub Project V2 is required.
    1. Go to GitHub → Projects → New project → Board
    2. Add a Status field (Single Select) with options: Todo, In Progress, Code Review, Done
    3. Link the project to your repository: Project settings → Manage access → Add repository
    4. Add the issues you want to track into the project
```

### Phase 2 — Create All Files

Create the following files using the templates in the [File Templates](#file-templates) section:

```
.env.example
.gitignore               (add .env entry if not already present)
tools/_github.ps1
tools/start-work.ps1
tools/open-pr.ps1
tools/update-status.ps1
tools/check-status.ps1
tools/discover-ids.ps1
.github/scripts/update-project-field.sh
.github/workflows/pr-merged.yml
.github/workflows/pr-opened.yml
```

### Phase 3 — Discover Project V2 IDs

After the user fills in `GITHUB_TOKEN` and `WORKFLOW_PROJECT_ID` in `.env`, run:

```powershell
.\tools\discover-ids.ps1
```

Then copy the output IDs into `.env`:
- `WORKFLOW_STATUS_FIELD_ID` = ID of the Status field
- `WORKFLOW_IN_PROGRESS_OPTION_ID` = option ID for "In Progress"
- `WORKFLOW_CODE_REVIEW_OPTION_ID` = option ID for "Code Review"
- `WORKFLOW_DONE_OPTION_ID` = option ID for "Done"

### Phase 4 — Configure GitHub Repository Settings

Notify the user of these **manual steps** that must be done on GitHub:

```
⚠️  The following steps must be completed manually on GitHub:

1. Repository Secret — PAT_TOKEN:
   → GitHub repo → Settings → Secrets and variables → Actions → New repository secret
   → Name: PAT_TOKEN
   → Value: [same GitHub PAT token as in your .env]

2. Repository Variables (5 variables):
   → GitHub repo → Settings → Secrets and variables → Actions → Variables tab
   → Add each of the following (values from your .env file):

   WORKFLOW_PROJECT_ID            = [value from .env]
   WORKFLOW_STATUS_FIELD_ID       = [value from .env]
   WORKFLOW_IN_PROGRESS_OPTION_ID = [value from .env]
   WORKFLOW_CODE_REVIEW_OPTION_ID = [value from .env]
   WORKFLOW_DONE_OPTION_ID        = [value from .env]
```

### Phase 5 — Commit and Push

```powershell
git add .
git commit -m "chore: add GitHub Project V2 workflow automation"
git push
```

### Phase 6 — End-to-End Test

```powershell
# 1. Add an issue to the Project V2 first (via GitHub UI or API)
# 2. Start work
.\tools\start-work.ps1 -Issues <issue_number>

# 3. Commit your work
git add .; git commit -m "feat: ..."; git push

# 4. Open a PR
.\tools\open-pr.ps1 -Issues <issue_number>

# 5. Merge the PR → verify that the issue automatically changes to Done
```

---

## File Templates

### `.env.example`

```
GITHUB_TOKEN=
GITHUB_OWNER=your-github-username-or-org
GITHUB_REPO=your-repo-name

# Project V2 IDs — run: .\tools\discover-ids.ps1 to find these
WORKFLOW_PROJECT_ID=
WORKFLOW_STATUS_FIELD_ID=
WORKFLOW_IN_PROGRESS_OPTION_ID=
WORKFLOW_CODE_REVIEW_OPTION_ID=
WORKFLOW_DONE_OPTION_ID=
```

---

### `tools/_github.ps1`

```powershell
# _github.ps1 — Shared GitHub API utilities
# Dot-source this file in other scripts: . "$PSScriptRoot\_github.ps1"

$global:DryRun = $false

function Get-EnvConfig {
    if ($global:DryRun) {
        Write-Host "  [DRY-RUN] Skipping env validation" -ForegroundColor DarkGray
        return
    }
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
    param([string]$Query, [hashtable]$Variables = @{})
    if ($global:DryRun) {
        Write-Host "  [DRY-RUN] GraphQL: $($Variables | ConvertTo-Json -Compress)" -ForegroundColor DarkGray
        return @{}
    }
    $token   = [System.Environment]::GetEnvironmentVariable("GITHUB_TOKEN")
    $body    = @{ query = $Query; variables = $Variables } | ConvertTo-Json -Depth 10
    $headers = @{ Authorization = "bearer $token"; "Content-Type" = "application/json"; "User-Agent" = "github-workflow-ps" }
    $response = Invoke-RestMethod -Uri "https://api.github.com/graphql" -Method POST -Headers $headers -Body $body
    if ($response.errors) {
        $msgs = ($response.errors | ForEach-Object { $_.message }) -join "; "
        Write-Error "GraphQL error: $msgs"; exit 1
    }
    return $response.data
}

function Invoke-GitHubREST {
    param([string]$Path, [string]$Method = "GET", [hashtable]$Body = $null)
    if ($global:DryRun) {
        Write-Host "  [DRY-RUN] REST $Method $Path" -ForegroundColor DarkGray
        if ($Path -match "/pulls$") {
            return [PSCustomObject]@{ number = 99; html_url = "https://github.com/dry-run/pull/99"; title = "dry-run PR" }
        }
        return @{}
    }
    $token   = [System.Environment]::GetEnvironmentVariable("GITHUB_TOKEN")
    $headers = @{
        Authorization          = "bearer $token"
        Accept                 = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent"           = "github-workflow-ps"
    }
    $params = @{ Uri = "https://api.github.com$Path"; Method = $Method; Headers = $headers }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10); $params.ContentType = "application/json" }
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
        nodes { id content { ... on Issue { id } } }
      }
    }
  }
}
"@ -Variables @{ project = $projectId }
    $item = $data.node.items.nodes | Where-Object { $_.content.id -eq $IssueNodeId }
    return $(if ($item) { $item.id } else { $null })
}

function Update-ProjectField {
    param([string]$ItemId, [string]$FieldId, [string]$OptionId)
    $projectId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_PROJECT_ID")
    Invoke-GitHubGraphQL -Query @"
mutation(`$project: ID!, `$item: ID!, `$field: ID!, `$option: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: `$project itemId: `$item fieldId: `$field
    value: { singleSelectOptionId: `$option }
  }) { projectV2Item { id } }
}
"@ -Variables @{ project = $projectId; item = $ItemId; field = $FieldId; option = $OptionId } | Out-Null
}

function Update-IssuesStatus {
    param([int[]]$IssueNumbers, [string]$OptionId, [string]$Label)
    $fieldId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_STATUS_FIELD_ID")
    foreach ($num in $IssueNumbers) {
        $issue  = Get-IssueNodeId -IssueNumber $num
        $itemId = Get-ProjectItemId -IssueNodeId $issue.id
        if (-not $itemId) { Write-Warning "  WARN:  Issue #$num not found in Project V2 — skipped"; continue }
        Update-ProjectField -ItemId $itemId -FieldId $fieldId -OptionId $OptionId
        Write-Host "  OK  Issue #$num -> $Label"
    }
}
```

---

### `tools/start-work.ps1`

```powershell
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

Write-Host "-> Creating and pushing branch..."
git checkout -b $branchName
git push -u origin $branchName
Write-Host "  OK Branch `"$branchName`" pushed`n"

$optionId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_IN_PROGRESS_OPTION_ID")
Write-Host "-> Updating Project V2 statuses -> In Progress..."
Update-IssuesStatus -IssueNumbers $Issues -OptionId $optionId -Label "In Progress"

Write-Host "`nDONE: start-work complete"
Write-Host "   Branch: $branchName"
Write-Host "   Issues: $($Issues | ForEach-Object { "#$_" }) -> In Progress"
```

---

### `tools/open-pr.ps1`

```powershell
param(
    [Parameter(Mandatory)][int[]]$Issues,
    [string]$Title,
    [string[]]$Reviewers = @(),
    [switch]$DryRun
)

. "$PSScriptRoot\_github.ps1"
if ($DryRun) { $global:DryRun = $true; Write-Host "[DRY-RUN MODE]" -ForegroundColor Yellow }
Get-EnvConfig

$owner       = [System.Environment]::GetEnvironmentVariable("GITHUB_OWNER")
$repo        = [System.Environment]::GetEnvironmentVariable("GITHUB_REPO")
$branch      = git branch --show-current
$prTitle     = if ($Title) { $Title } else { "feat: implement issues $($Issues | ForEach-Object { "#$_" })" }
$closingRefs = ($Issues | ForEach-Object { "Closes #$_" }) -join "`n"
$body        = "$closingRefs`n`n---`n_PR created via github-workflow-ps_"

Write-Host "`n>> open-pr"
Write-Host "  Branch: $branch"
Write-Host "  Issues: $($Issues | ForEach-Object { "#$_" })"
Write-Host "  Title:  $prTitle`n"

Write-Host "-> Creating PR..."
$pr = Invoke-GitHubREST -Path "/repos/$owner/$repo/pulls" -Method POST -Body @{
    title = $prTitle; head = $branch; base = "main"; body = $body; draft = $false
}
Write-Host "  OK PR #$($pr.number) created: $($pr.html_url)`n"

if ($Reviewers.Count -gt 0) {
    Invoke-GitHubREST -Path "/repos/$owner/$repo/pulls/$($pr.number)/requested_reviewers" `
        -Method POST -Body @{ reviewers = $Reviewers } | Out-Null
    Write-Host "  OK Reviewers assigned`n"
}

$optionId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_CODE_REVIEW_OPTION_ID")
Write-Host "-> Updating Project V2 statuses -> Code Review..."
Update-IssuesStatus -IssueNumbers $Issues -OptionId $optionId -Label "Code Review"

Write-Host "`nDONE: open-pr complete"
Write-Host "   PR:     #$($pr.number) — $prTitle"
Write-Host "   URL:    $($pr.html_url)"
Write-Host "   Issues: $($Issues | ForEach-Object { "#$_" }) -> Code Review"
```

---

### `tools/update-status.ps1`

```powershell
param(
    [Parameter(Mandatory)][int[]]$Issues,
    [Parameter(Mandatory)]
    [ValidateSet("In Progress", "Code Review", "Done")]
    [string]$Status,
    [switch]$DryRun
)

. "$PSScriptRoot\_github.ps1"
if ($DryRun) { $global:DryRun = $true }
Get-EnvConfig

$optionEnvMap = @{
    "In Progress" = "WORKFLOW_IN_PROGRESS_OPTION_ID"
    "Code Review" = "WORKFLOW_CODE_REVIEW_OPTION_ID"
    "Done"        = "WORKFLOW_DONE_OPTION_ID"
}
$optionId = [System.Environment]::GetEnvironmentVariable($optionEnvMap[$Status])
if (-not $optionId) { Write-Error "Option ID for `"$Status`" not configured"; exit 1 }

Write-Host "`n>> update-status: issues $($Issues | ForEach-Object { "#$_" }) -> $Status`n"
Update-IssuesStatus -IssueNumbers $Issues -OptionId $optionId -Label $Status
Write-Host "`nDONE: $($Issues.Count) issue(s) -> $Status"
```

---

### `tools/check-status.ps1`

```powershell
param([switch]$DryRun)

. "$PSScriptRoot\_github.ps1"
if ($DryRun) { $global:DryRun = $true }
Get-EnvConfig

$owner  = [System.Environment]::GetEnvironmentVariable("GITHUB_OWNER")
$repo   = [System.Environment]::GetEnvironmentVariable("GITHUB_REPO")
$branch = git branch --show-current

Write-Host "`n>> check-status"
Write-Host "  Branch: $branch`n"

$prs = Invoke-GitHubREST -Path "/repos/$owner/$repo/pulls?head=${owner}:${branch}&state=open"

if (-not $prs -or $prs.Count -eq 0) {
    Write-Host "  No open PR found for this branch."
    Write-Host "`nStatus: branch created, PR not yet opened."
    exit 0
}

$pr = $prs[0]
$linkedIssues = [System.Collections.Generic.List[int]]::new()
$matches = [System.Text.RegularExpressions.Regex]::Matches($pr.body, 'closes\s+#(\d+)', 'IgnoreCase')
foreach ($m in $matches) { $linkedIssues.Add([int]$m.Groups[1].Value) }

$issueText = if ($linkedIssues.Count -gt 0) { ($linkedIssues | ForEach-Object { "#$_" }) -join ", " } else { "(none)" }
Write-Host "PR:     #$($pr.number) — $($pr.title) ($($pr.state.ToUpper()))"
Write-Host "URL:    $($pr.html_url)"
Write-Host "Issues: $issueText"
```

---

### `tools/discover-ids.ps1`

```powershell
. "$PSScriptRoot\_github.ps1"

$envFile = Join-Path (Get-Location) ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^\s*([^#][^=]+)=(.+)$") {
            $key = $Matches[1].Trim(); $val = $Matches[2].Trim().Trim('"').Trim("'")
            [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
        }
    }
}

$projectId = [System.Environment]::GetEnvironmentVariable("WORKFLOW_PROJECT_ID")
if (-not $projectId) { Write-Error "Set WORKFLOW_PROJECT_ID in .env first"; exit 1 }

Write-Host "`n>> discover-ids — Project: $projectId`n"

$data = Invoke-GitHubGraphQL -Query @"
query(`$project: ID!) {
  node(id: `$project) {
    ... on ProjectV2 {
      fields(first: 30) {
        nodes {
          __typename
          ... on ProjectV2SingleSelectField {
            id name options { id name }
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
        Write-Host "Field: $($field.name)  ID: $($field.id)"
        foreach ($opt in $field.options) { Write-Host "  Option `"$($opt.name)`": $($opt.id)" }
        Write-Host ""
    }
}
Write-Host "Paste the above IDs into your .env file."
```

---

### `.github/scripts/update-project-field.sh`

```bash
#!/usr/bin/env bash
# update-project-field.sh — Update Project V2 field for all issues linked to a PR
set -euo pipefail

: "${PROJECT_ID:?Missing PROJECT_ID}"
: "${FIELD_ID:?Missing FIELD_ID}"
: "${OPTION_ID:?Missing OPTION_ID}"
: "${PR_NUMBER:?Missing PR_NUMBER}"
: "${GITHUB_REPOSITORY_OWNER:?Missing GITHUB_REPOSITORY_OWNER}"
: "${GITHUB_REPOSITORY:?Missing GITHUB_REPOSITORY}"

OWNER="$GITHUB_REPOSITORY_OWNER"
REPO="${GITHUB_REPOSITORY#*/}"

echo ">> Fetching linked issues for PR #${PR_NUMBER} in ${OWNER}/${REPO}..."

LINKED_ISSUES=$(gh api graphql \
  -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          closingIssuesReferences(first: 20) {
            nodes { id number }
          }
        }
      }
    }
  ' \
  -f owner="$OWNER" -f repo="$REPO" -F number="$PR_NUMBER" \
  --jq '.data.repository.pullRequest.closingIssuesReferences.nodes')

ISSUE_COUNT=$(echo "$LINKED_ISSUES" | jq 'length')
echo "   Found ${ISSUE_COUNT} linked issue(s)"
if [[ "$ISSUE_COUNT" -eq 0 ]]; then echo "   No linked issues — skipping"; exit 0; fi
echo "   Issues: $(echo "$LINKED_ISSUES" | jq -r '[.[].number] | map("#\(.)") | join(", ")')"

echo ">> Fetching Project V2 items..."
PROJECT_ITEMS=$(gh api graphql \
  -f query='
    query($project: ID!) {
      node(id: $project) {
        ... on ProjectV2 {
          items(first: 100) {
            nodes { id content { ... on Issue { id } } }
          }
        }
      }
    }
  ' \
  -f project="$PROJECT_ID" \
  --jq '.data.node.items.nodes')

UPDATED=0; SKIPPED=0

while IFS= read -r ISSUE; do
  ISSUE_ID=$(echo "$ISSUE" | jq -r '.id')
  ISSUE_NUM=$(echo "$ISSUE" | jq -r '.number')
  ITEM_ID=$(echo "$PROJECT_ITEMS" | jq -r --arg id "$ISSUE_ID" \
    '.[] | select(.content != null and .content.id == $id) | .id // empty')

  if [[ -z "$ITEM_ID" ]]; then
    echo "   WARN: Issue #${ISSUE_NUM} not found in Project V2 — skipped"
    SKIPPED=$((SKIPPED + 1)); continue
  fi

  gh api graphql \
    -f query='
      mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
        updateProjectV2ItemFieldValue(input: {
          projectId: $project itemId: $item fieldId: $field
          value: { singleSelectOptionId: $option }
        }) { projectV2Item { id } }
      }
    ' \
    -f project="$PROJECT_ID" -f item="$ITEM_ID" \
    -f field="$FIELD_ID" -f option="$OPTION_ID" \
    --jq '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null

  echo "   OK  Issue #${ISSUE_NUM} updated"
  UPDATED=$((UPDATED + 1))
done < <(echo "$LINKED_ISSUES" | jq -c '.[]')

echo ""
echo "DONE: ${UPDATED} issue(s) updated, ${SKIPPED} skipped"
```

---

### `.github/workflows/pr-merged.yml`

```yaml
name: PR Merged - Update Status to Done

on:
  pull_request:
    types: [closed]

permissions:
  contents: read

jobs:
  update-status:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ secrets.PAT_TOKEN }}
      PROJECT_ID: ${{ vars.WORKFLOW_PROJECT_ID }}
      FIELD_ID: ${{ vars.WORKFLOW_STATUS_FIELD_ID }}
      OPTION_ID: ${{ vars.WORKFLOW_DONE_OPTION_ID }}
      PR_NUMBER: ${{ github.event.pull_request.number }}
    steps:
      - uses: actions/checkout@v4
      - name: Update linked issues to Done
        run: bash .github/scripts/update-project-field.sh
```

---

### `.github/workflows/pr-opened.yml`

```yaml
name: PR Opened - Update Status to Code Review

on:
  pull_request:
    types: [opened, reopened]

permissions:
  contents: read

jobs:
  update-status:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ secrets.PAT_TOKEN }}
      PROJECT_ID: ${{ vars.WORKFLOW_PROJECT_ID }}
      FIELD_ID: ${{ vars.WORKFLOW_STATUS_FIELD_ID }}
      OPTION_ID: ${{ vars.WORKFLOW_CODE_REVIEW_OPTION_ID }}
      PR_NUMBER: ${{ github.event.pull_request.number }}
    steps:
      - uses: actions/checkout@v4
      - name: Update linked issues to Code Review
        run: bash .github/scripts/update-project-field.sh
```

---

## Quick Reference

### CLI Commands

```powershell
# Start working on issues
.\tools\start-work.ps1 -Issues 1,2,3

# Open a PR
.\tools\open-pr.ps1 -Issues 1,2,3

# Manually update status
.\tools\update-status.ps1 -Issues 1,2,3 -Status "In Progress"
.\tools\update-status.ps1 -Issues 1,2,3 -Status "Code Review"
.\tools\update-status.ps1 -Issues 1,2,3 -Status "Done"

# Check current status
.\tools\check-status.ps1

# Discover Project V2 IDs
.\tools\discover-ids.ps1
```

### PR Body Format (Critical)

The PR body must contain `Closes #X` for GitHub Actions to detect linked issues:

```
Closes #1
Closes #2
Closes #3

---
Brief description
```

> `open-pr.ps1` injects these lines automatically — no manual editing needed.

### Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Actions fail: `Missing PROJECT_ID` | Repository Variables not set | Go to Settings → Variables → add all 5 variables |
| Issue does not change to Done after merge | PR body missing `Closes #X` | Always use `open-pr.ps1`, or manually edit the PR body |
| Issue does not change status after merge | Issue not in Project V2 | Add the issue to the Project first |
| `WARN: Issue not found in Project V2` | Issue was never added to the project | Add via GitHub UI or API before running start-work |
| Token / authentication error | `PAT_TOKEN` secret not set | Settings → Secrets → add `PAT_TOKEN` |

---

## UAT Deploy Tracking

An optional extension that adds two Project V2 fields to track UAT deployment state per issue.

### New Fields

| Field | Type | Values |
|-------|------|--------|
| `UAT Deploy Status` | Single Select | Deploying (yellow) · Success (green) · Failed (red) |
| `UAT Deploy Version` | Text | e.g. `0.0.52` |

### Required Variables (add after running `setup-uat-fields.ps1`)

| Variable | Description |
|----------|-------------|
| `WORKFLOW_UAT_DEPLOY_STATUS_FIELD_ID` | Single-select field ID |
| `WORKFLOW_UAT_DEPLOY_VERSION_FIELD_ID` | Text field ID |
| `WORKFLOW_DEPLOYING_OPTION_ID` | Option ID for "Deploying" |
| `WORKFLOW_DEPLOY_SUCCESS_OPTION_ID` | Option ID for "Success" |
| `WORKFLOW_DEPLOY_FAILED_OPTION_ID` | Option ID for "Failed" |

### Deploy Status Lifecycle

```
PR Merged (or manual dispatch)
  │
  ├─ UAT Deploy Status = Deploying
  │
  ├─ (deployment runs)
  │
  ├─ success ──► UAT Deploy Status = Success
  │               UAT Deploy Version = <version>
  │
  └─ failure ──► UAT Deploy Status = Failed
```

### Phase 7 — Setup UAT Deploy Tracking (Optional)

**Step 1 — Validate/create Project V2 fields:**
```powershell
.\tools\setup-uat-fields.ps1
```
This script:
- Queries existing Project V2 fields
- Creates `UAT Deploy Version` (text) if missing
- Creates `UAT Deploy Status` (single-select with Deploying/Success/Failed options) if missing
- Writes discovered IDs into `.env`
- Prints the 5 values to set as GitHub Repository Variables

**Step 2 — Set Repository Variables** (same location as the 5 workflow variables):  
`Settings → Secrets and variables → Actions → Variables`

**Step 3 — Verify** by running:
```powershell
.\tools\discover-ids.ps1   # shows UAT Deploy Field Mapping section
```

### New CLI Commands

```powershell
# One-time field setup
.\tools\setup-uat-fields.ps1

# Manual deploy status update
.\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Status deploying
.\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Version "0.0.52" -Status success
.\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Status failed
```

### New Files

| File | Purpose |
|------|---------|
| `tools/setup-uat-fields.ps1` | One-time: validate/create UAT deploy fields |
| `tools/update-deploy.ps1` | CLI: update deploy status + version for issues |
| `.github/scripts/update-uat-deploy.sh` | Actions helper: update fields via GraphQL |
| `.github/workflows/uat-deploy.yml` | Workflow: triggered by PR merge or manual dispatch |
