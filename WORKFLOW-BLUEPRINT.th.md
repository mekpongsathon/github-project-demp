# GitHub Project V2 — Workflow Automation Blueprint

> **สำหรับ Copilot:** ไฟล์นี้คือ blueprint สำหรับ setup workflow อัตโนมัติ  
> เมื่อผู้ใช้บอกให้ "setup workflow" ให้ทำตามขั้นตอนใน [Setup Instructions for Copilot](#setup-instructions-for-copilot)

---

## Overview

Workflow นี้ track สถานะ GitHub Issue ผ่าน Project V2 โดยอัตโนมัติ:

```
Todo → In Progress → Code Review → Done
```

| Trigger | Action |
|---------|--------|
| `start-work.ps1` | สร้าง branch + Issue → **In Progress** |
| `open-pr.ps1` | สร้าง PR + Issue → **Code Review** |
| PR merged | GitHub Actions → Issue → **Done** (auto) |

---

## Setup Instructions for Copilot

เมื่อได้รับคำสั่งให้ setup workflow นี้ ให้ทำตามขั้นตอนนี้:

### Phase 1 — ตรวจสอบ Prerequisites

ตรวจสอบสิ่งต่อไปนี้และแจ้งผู้ใช้ถ้ายังขาด:

```
[ ] 1. Git repository ถูก init และมี remote origin แล้ว
[ ] 2. GitHub Personal Access Token (PAT) — scopes: repo, project, workflow
[ ] 3. GitHub Project V2 ถูกสร้างแล้ว และ linked กับ repository
[ ] 4. Project V2 มี Status field (Single Select) ที่มี options: Todo, In Progress, Code Review, Done
[ ] 5. gh CLI ติดตั้งแล้ว (สำหรับ GitHub Actions scripts)
```

**แจ้งผู้ใช้ด้วยข้อความนี้ถ้ายังไม่มี PAT:**
```
⚠️  ต้องการ GitHub Personal Access Token (PAT)
    1. ไปที่ GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
    2. สร้าง token ใหม่ พร้อม scopes: Contents (R/W), Pull requests (R/W), Issues (R/W)
    3. ต้องเพิ่ม Project permissions: Read and write
    4. สร้างเสร็จแล้ว copy token มาใส่ใน .env ที่ GITHUB_TOKEN=
```

**แจ้งผู้ใช้ด้วยข้อความนี้ถ้ายังไม่มี Project V2:**
```
⚠️  ต้องการ GitHub Project V2
    1. ไปที่ GitHub → Projects → New project → Board
    2. เพิ่ม Status field (Single Select) ที่มี options: Todo, In Progress, Code Review, Done
    3. Link project กับ repository: Project settings → Manage access → Add repository
    4. เพิ่ม issues ที่ต้องการ track เข้า project
```

### Phase 2 — สร้างไฟล์ทั้งหมด

สร้างไฟล์ต่อไปนี้ตาม template ด้านล่าง (section [File Templates](#file-templates)):

```
.env.example
.gitignore               (เพิ่ม .env ถ้ายังไม่มี)
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

### Phase 3 — ค้นหา Project V2 IDs

หลังจากผู้ใช้กรอก GITHUB_TOKEN และ WORKFLOW_PROJECT_ID ใน `.env` แล้ว รัน:

```powershell
.\tools\discover-ids.ps1
```

แล้ว copy IDs ที่ได้มาใส่ใน `.env`:
- `WORKFLOW_STATUS_FIELD_ID` = ID ของ Status field
- `WORKFLOW_IN_PROGRESS_OPTION_ID` = option ID ของ "In Progress"
- `WORKFLOW_CODE_REVIEW_OPTION_ID` = option ID ของ "Code Review"  
- `WORKFLOW_DONE_OPTION_ID` = option ID ของ "Done"

### Phase 4 — ตั้งค่า GitHub Repository

แจ้งผู้ใช้ให้ทำ **manual steps** เหล่านี้บน GitHub:

```
⚠️  Manual steps บน GitHub ที่ต้องทำเอง:

1. Repository Secret — PAT_TOKEN:
   → GitHub repo → Settings → Secrets and variables → Actions → New repository secret
   → Name: PAT_TOKEN
   → Value: [GitHub PAT token เดียวกับใน .env]

2. Repository Variables (5 ตัว):
   → GitHub repo → Settings → Secrets and variables → Actions → Variables tab
   → เพิ่มตัวแปรต่อไปนี้ (ค่าจากไฟล์ .env ของคุณ):

   WORKFLOW_PROJECT_ID          = [ค่าจาก .env]
   WORKFLOW_STATUS_FIELD_ID     = [ค่าจาก .env]
   WORKFLOW_IN_PROGRESS_OPTION_ID = [ค่าจาก .env]
   WORKFLOW_CODE_REVIEW_OPTION_ID = [ค่าจาก .env]
   WORKFLOW_DONE_OPTION_ID      = [ค่าจาก .env]
```

### Phase 5 — Commit และ Push

```powershell
git add .
git commit -m "chore: add GitHub Project V2 workflow automation"
git push
```

### Phase 6 — ทดสอบ End-to-End

```powershell
# 1. เพิ่ม issue เข้า Project V2 ก่อน (ผ่าน GitHub UI หรือ API)
# 2. รัน start-work
.\tools\start-work.ps1 -Issues <issue_number>

# 3. commit งาน
git add .; git commit -m "feat: ..."; git push

# 4. เปิด PR
.\tools\open-pr.ps1 -Issues <issue_number>

# 5. Merge PR → ตรวจสอบว่า issue เปลี่ยนเป็น Done อัตโนมัติ
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
# เริ่มทำงาน
.\tools\start-work.ps1 -Issues 1,2,3

# เปิด PR
.\tools\open-pr.ps1 -Issues 1,2,3

# อัปเดต status ด้วยตนเอง
.\tools\update-status.ps1 -Issues 1,2,3 -Status "In Progress"
.\tools\update-status.ps1 -Issues 1,2,3 -Status "Code Review"
.\tools\update-status.ps1 -Issues 1,2,3 -Status "Done"

# ดู status ปัจจุบัน
.\tools\check-status.ps1

# ค้นหา Project V2 IDs
.\tools\discover-ids.ps1
```

### PR Body Format (สำคัญมาก)

PR body ต้องมี `Closes #X` เพื่อให้ GitHub Actions อ่านได้:

```
Closes #1
Closes #2
Closes #3

---
Brief description
```

> `open-pr.ps1` จะ inject บรรทัดนี้อัตโนมัติ — ไม่ต้องพิมพ์เอง

### Troubleshooting

| ปัญหา | สาเหตุ | วิธีแก้ |
|-------|--------|---------|
| Actions fail: `Missing PROJECT_ID` | Repository Variables ไม่ได้ set | ไปที่ Settings → Variables → เพิ่มค่าทั้ง 5 ตัว |
| Issue ไม่เปลี่ยน status หลัง merge | PR body ไม่มี `Closes #X` | ใช้ `open-pr.ps1` เสมอ หรือแก้ PR body |
| Issue ไม่เปลี่ยน status หลัง merge | Issue ไม่ได้อยู่ใน Project V2 | เพิ่ม issue เข้า Project ก่อน |
| `WARN: Issue not found in Project V2` | Issue ยังไม่ได้ add เข้า project | เพิ่ม issue เข้า Project V2 ผ่าน GitHub UI |
| Token error | PAT_TOKEN secret ไม่ได้ set | Settings → Secrets → เพิ่ม PAT_TOKEN |

---

## UAT Deploy Tracking / ติดตามการ Deploy UAT

Extension เสริมที่เพิ่ม 2 field ใน Project V2 เพื่อ track สถานะการ deploy UAT ต่อ issue

### Fields ที่เพิ่มขึ้น

| Field | ประเภท | ค่า |
|-------|--------|-----|
| `UAT Deploy Status` | Single Select | Deploying (เหลือง) · Success (เขียว) · Failed (แดง) |
| `UAT Deploy Version` | Text | เช่น `0.0.52` |

### Variables ที่ต้องเพิ่ม (หลังรัน `setup-uat-fields.ps1`)

| Variable | คำอธิบาย |
|----------|----------|
| `WORKFLOW_UAT_DEPLOY_STATUS_FIELD_ID` | ID ของ single-select field |
| `WORKFLOW_UAT_DEPLOY_VERSION_FIELD_ID` | ID ของ text field |
| `WORKFLOW_DEPLOYING_OPTION_ID` | Option ID สำหรับ "Deploying" |
| `WORKFLOW_DEPLOY_SUCCESS_OPTION_ID` | Option ID สำหรับ "Success" |
| `WORKFLOW_DEPLOY_FAILED_OPTION_ID` | Option ID สำหรับ "Failed" |

### Deploy Status Lifecycle

```
PR Merged (หรือ manual dispatch)
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

**Step 1 — Validate/สร้าง Project V2 fields:**
```powershell
.\tools\setup-uat-fields.ps1
```
Script นี้จะ:
- Query fields ที่มีอยู่ใน Project V2
- สร้าง `UAT Deploy Version` (text) ถ้าไม่มี
- สร้าง `UAT Deploy Status` (single-select: Deploying/Success/Failed) ถ้าไม่มี
- เขียน ID ที่ค้นพบลงไฟล์ `.env`
- Print 5 ค่าที่ต้องตั้งเป็น GitHub Repository Variables

**Step 2 — ตั้ง Repository Variables** (เพิ่มในที่เดิมกับ 5 workflow variables):  
`Settings → Secrets and variables → Actions → Variables`

**Step 3 — ตรวจสอบ** ด้วยการรัน:
```powershell
.\tools\discover-ids.ps1   # จะมี section "UAT Deploy Field Mapping" แสดง
```

### CLI Commands ใหม่

```powershell
# ตั้งค่า fields ครั้งแรก (ทำครั้งเดียว)
.\tools\setup-uat-fields.ps1

# อัปเดต deploy status ด้วยตนเอง
.\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Status deploying
.\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Version "0.0.52" -Status success
.\tools\update-deploy.ps1 -Issues "123,124" -Environment uat -Status failed
```

### ไฟล์ใหม่

| ไฟล์ | หน้าที่ |
|------|---------|
| `tools/setup-uat-fields.ps1` | ตั้งค่าครั้งเดียว: validate/สร้าง UAT deploy fields |
| `tools/update-deploy.ps1` | CLI: อัปเดต deploy status + version สำหรับ issues |
| `.github/scripts/update-uat-deploy.sh` | Actions helper: อัปเดต fields ผ่าน GraphQL |
| `.github/workflows/uat-deploy.yml` | Workflow: ทริกเกอร์จาก PR merge หรือ manual dispatch |
