# Project Description: GitHub Project V2 Workflow Automation
# คำอธิบายโปรเจค: ระบบ Workflow อัตโนมัติสำหรับ GitHub Project V2

---

## What We Built / สิ่งที่เราสร้าง

A developer workflow automation system that automatically tracks GitHub Issue status through Project V2 using PowerShell CLI tools + GitHub Actions — with Copilot as the conversational interface.

ระบบ automation สำหรับ developer workflow ที่ track สถานะ GitHub Issue ผ่าน Project V2 โดยอัตโนมัติ โดยใช้ PowerShell CLI tools + GitHub Actions — และใช้ Copilot เป็น interface รับคำสั่ง

---

## Problem Solved / ปัญหาที่แก้

Developers forget to update issue status when they switch tasks. This system makes status updates automatic and tied to actual git actions.

Developer มักลืมอัปเดตสถานะ issue เมื่อเปลี่ยน task ระบบนี้ทำให้การอัปเดตสถานะเกิดขึ้นอัตโนมัติ ผูกกับ git actions จริง

---

## Core Concept / แนวคิดหลัก

```
GitHub Issues    = source of truth for tasks
GitHub Project V2 = workflow state board
GitHub Actions   = automation on PR events
PowerShell tools = developer CLI (invoked by Copilot)
Copilot          = conversational interface (Thai / English)
```

---

## Automated Status Flow / สถานะที่เปลี่ยนอัตโนมัติ

```
[Issue created] → Todo
      ↓  (run start-work.ps1)
  In Progress        ← branch created + pushed
      ↓  (run open-pr.ps1)
  Code Review        ← PR created with "Closes #X" in body
      ↓  (user merges PR manually)
     Done            ← GitHub Actions pr-merged.yml fires
```

**Key rule:** `Closes #X` in the PR body is the authoritative link between PR and issues. The bash script reads `closingIssuesReferences` via GraphQL to find linked issues after merge.

---

## File Structure / โครงสร้างไฟล์

```
.env                              ← secrets + config (not committed)
.env.example                      ← template for new setups
.github/
  copilot-instructions.md         ← teaches Copilot which scripts to call
  scripts/
    update-project-field.sh       ← core bash: updates Project V2 field via GraphQL
  workflows/
    pr-opened.yml                 ← trigger: PR opened → Code Review
    pr-merged.yml                 ← trigger: PR merged → Done
    deploy-status.yml             ← trigger: manual → deploy field update
tools/
  _github.ps1                     ← shared GitHub API library (GraphQL + REST)
  start-work.ps1                  ← create branch + push + In Progress
  open-pr.ps1                     ← create PR + Code Review
  update-status.ps1               ← manual status override
  update-deploy.ps1               ← update deploy field (dev/uat/prod)
  check-status.ps1                ← show current branch / PR / issues
  discover-ids.ps1                ← query Project V2 field & option IDs
WORKFLOW-BLUEPRINT.en.md          ← setup guide (English) for Copilot to follow
WORKFLOW-BLUEPRINT.th.md          ← setup guide (Thai)
WORKFLOW-USAGE.md                 ← bilingual user guide (TH/EN)
```

---

## How Each Part Works / วิธีที่แต่ละส่วนทำงาน

### 1. `tools/_github.ps1` — Shared API Library
- Loads `.env` file into process environment variables
- Validates required vars on startup (fails fast with clear error)
- `Invoke-GitHubGraphQL` — wraps GraphQL calls with auth
- `Invoke-GitHubREST` — wraps REST API calls
- `Get-IssueNodeId` — resolves issue number → GitHub node ID
- `Get-ProjectItemId` — finds Project V2 item ID for an issue
- `Update-ProjectField` — runs the `updateProjectV2ItemFieldValue` mutation
- `Update-IssuesStatus` — loops issues and updates all in one call

### 2. `tools/start-work.ps1`
- Calls `git checkout -b feat/issues-N` + `git push -u origin`
- Calls `Update-IssuesStatus` → sets status to **In Progress**

### 3. `tools/open-pr.ps1`
- Creates PR via REST API
- PR body always contains `Closes #N` for each issue (critical for auto-Done)
- Calls `Update-IssuesStatus` → sets status to **Code Review**

### 4. `.github/scripts/update-project-field.sh`
- Runs inside GitHub Actions (bash + `gh` CLI)
- Step 1: GraphQL query `closingIssuesReferences` on the PR → get linked issue IDs
- Step 2: GraphQL query to get all Project V2 items (up to 100)
- Step 3: Match each issue → find its Project item ID → run `updateProjectV2ItemFieldValue` mutation
- Skips issues not in Project V2 (WARN, does not fail)

### 5. GitHub Actions Workflows
- `pr-opened.yml` — triggers on PR open/reopen → sets OPTION_ID to Code Review option
- `pr-merged.yml` — triggers on PR close WHERE merged==true → sets OPTION_ID to Done option
- Both use `vars.*` (Repository Variables) — not hardcoded — for portability
- Use `secrets.PAT_TOKEN` (not default GITHUB_TOKEN) because Project V2 mutations require elevated scopes

### 6. `.github/copilot-instructions.md`
- Teaches Copilot which script to call for which intent
- Bilingual trigger examples (Thai + English)
- Declares source-of-truth rules (don't parse branch names, use PR body)

---

## Configuration Required / สิ่งที่ต้อง Configure

### `.env` file (local, not committed)
```
GITHUB_TOKEN=<PAT with repo + project + workflow scopes>
GITHUB_OWNER=<org or username>
GITHUB_REPO=<repo name>
WORKFLOW_PROJECT_ID=<PVT_...>
WORKFLOW_STATUS_FIELD_ID=<PVTSSF_...>
WORKFLOW_IN_PROGRESS_OPTION_ID=<hex ID>
WORKFLOW_CODE_REVIEW_OPTION_ID=<hex ID>
WORKFLOW_DONE_OPTION_ID=<hex ID>
```

### GitHub Repository Settings (manual, one-time)
1. **Secret** `PAT_TOKEN` — same PAT as in `.env`
2. **Variables** (5 items) — mirror the `WORKFLOW_*` values from `.env`
   - Required because `vars.*` in Actions cannot read secrets

---

## Design Decisions / การตัดสินใจออกแบบ

| Decision | Reason |
|----------|--------|
| PR body `Closes #X` = source of truth for issue linkage | GitHub's `closingIssuesReferences` API only reads body, not title |
| PAT_TOKEN secret instead of default GITHUB_TOKEN | Project V2 mutations require `project` scope not available in default token |
| Repository Variables (not hardcoded IDs in workflow YAML) | Portability — copy workflow files to new repo, only set vars |
| Bash script for Actions, PowerShell for local CLI | gh CLI available natively on ubuntu runners; PowerShell for Windows devs |
| Merge is manual | Preserves review accountability; Actions only run after the fact |
| Copilot as interface via copilot-instructions.md | Natural language → script invocation without custom plugins |

---

## How to Adapt to Another Project / วิธีนำไปใช้กับโปรเจคอื่น

1. Copy these files into the new repo:
   - `tools/` folder (all `.ps1` files)
   - `.github/scripts/update-project-field.sh`
   - `.github/workflows/pr-merged.yml`
   - `.github/workflows/pr-opened.yml`
   - `.github/copilot-instructions.md`
   - `.env.example`

2. Create `.env` from `.env.example` — fill in token, owner, repo

3. Fill in `WORKFLOW_PROJECT_ID` then run `.\tools\discover-ids.ps1` to get field/option IDs

4. On GitHub: add `PAT_TOKEN` secret + 5 Repository Variables

5. Commit and push — workflow is live

Reference files: `WORKFLOW-BLUEPRINT.en.md` (full step-by-step with code templates)

---

## Limitations / ข้อจำกัด

- Project V2 item lookup fetches up to 100 items — large boards need pagination
- `closingIssuesReferences` only works when PR body contains `Closes #X` — not from title, comments, or sidebar links
- GitHub Actions may have propagation delay (~30s) between variable update and runner availability
- Windows-only CLI (PowerShell) — bash/zsh equivalent not included
- No rollback if `git push` fails after `start-work` updates the status
