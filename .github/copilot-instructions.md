# GitHub Workflow MCP — Copilot Instructions

## Context

This repository uses a structured engineering workflow:
- **GitHub Issues** = tasks (source of truth)
- **GitHub Project V2** = workflow states
- **GitHub Actions** = lifecycle automation
- **MCP Server** (`mcp-server/`) = orchestration tools for Copilot

## Workflow States

```
Todo → In Progress → Code Review → Done
```

Deploy states (per environment):
```
waiting → deploying → deployed → failed
```

## Available MCP Tools

When the user asks to start work, create a branch, or update issues, use these MCP tools:

### `start_work`
- Creates a branch and pushes it
- Updates all linked issues to **In Progress**
- Input: `issueNumbers[]`, optional `branchName`

Example triggers:
> "start issues 12 15 18"
> "เริ่มทำ issue 5 และ 7"

### `open_pr`
- Creates a PR with `Closes #xx` references
- Input: `title`, `issueNumbers[]`, optional `reviewers[]`

Example triggers:
> "open PR for issues 12 15 18"
> "สร้าง PR สำหรับ issue ที่กำลังทำอยู่"

### `update_deploy_status`
- Updates deploy field in Project V2
- Input: `prNumber`, `environment` (dev/uat/prod), `status` (waiting/deploying/deployed/failed)

Example triggers:
> "mark PR 42 as deployed to dev"
> "อัพเดต deploy status ของ PR 42 เป็น deployed บน uat"

### `check_work_status`
- Summarizes current branch, PR, and linked issues
- No input required

Example triggers:
> "what am I working on?"
> "สถานะงานตอนนี้คืออะไร"

## Branch Naming Convention

Branches are auto-named: `feat/issues-{n1}-{n2}-...`  
Example: `feat/issues-12-15-18`

## Source of Truth Rules

- **Do NOT parse branch names** to determine linked issues
- **PR description** with `Closes #xx` = authoritative issue linkage
- **GitHub Project V2** = authoritative workflow state
- Always use MCP tools — do NOT call GitHub APIs directly

## PR Description Format

```
Closes #12
Closes #15
Closes #18

---
Brief description of changes
```
