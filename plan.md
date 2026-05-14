ตอนนี้เราจะเริ่ม implement reusable engineering workflow platform ตาม architecture ด้านล่างนี้

เป้าหมาย:

* reusable ข้ามหลาย repo
* support multi-issue branch
* GitHub Project V2 เป็น state source of truth
* Copilot เป็น orchestration interface
* GitHub Actions เป็น repository event automation
* MCP Server เป็น workflow orchestration layer

Architecture:

* GitHub Issues = tasks
* GitHub Project V2 = workflow states
* GitHub Actions = lifecycle automation
* MCP Server = orchestration tools
* GitHub GraphQL API = state update mechanism

Workflow:
Todo
→ In Progress
→ Code Review
→ Done

Deploy states:
waiting
→ deploying
→ deployed
→ failed

ตอนนี้ให้เริ่ม implementation phase โดยทำตามลำดับด้านล่างนี้

==================================================
PHASE 1 — FIX EXISTING STATUS WORKFLOW
======================================

ตรวจสอบ workflow ปัจจุบันที่ update GitHub Project V2 status

Requirements:

1. แก้ปัญหา multi-issue PR

2. เปลี่ยน GraphQL query:
   closingIssuesReferences(first:1)
   → closingIssuesReferences(first:20)

3. loop ทุก linked issue

4. update status ทุก issue ใน PR

5. refactor logic ให้ reusable

6. อย่า hardcode:

   * PROJECT_ID
   * STATUS_FIELD_ID
   * OPTION IDs

ย้ายไปใช้:

* GitHub Variables
  หรือ
* environment config

Expected:

* 1 PR สามารถ update status ได้หลาย issues

==================================================
PHASE 2 — CREATE CENTRALIZED GRAPHQL UTILITIES
==============================================

สร้าง reusable GraphQL utility layer

Structure proposal:

/tools/github/
graphql.ts
project.ts
issues.ts
pullRequests.ts

Requirements:

1. create reusable functions:

* getProjectItemIdFromIssue()
* updateProjectStatus()
* updateDeployStatus()
* getLinkedIssuesFromPR()

2. typed implementation
3. proper error handling
4. idempotent behavior
5. retry-safe mutations
6. no duplicated GraphQL strings

==================================================
PHASE 3 — CREATE MCP SERVER
===========================

สร้าง MCP server สำหรับ Copilot orchestration

Requirements:

* Node.js + TypeScript
* tool-based architecture
* stateless design
* reads state from GitHub ทุกครั้ง
* no local persistent state

Suggested tools:

1. start_work
   input:

* issueNumbers[]

behavior:

* create branch
* push branch
* update statuses → In Progress

2. open_pr
   behavior:

* create PR
* include Closes #xx references
* assign reviewers
* update statuses → Code Review

3. update_deploy_status
   behavior:

* update dev/uat/prod fields

4. check_work_status
   behavior:

* summarize:

  * current branch
  * linked issues
  * PR state
  * deploy states

==================================================
PHASE 4 — REUSABLE GITHUB ACTIONS
=================================

สร้าง reusable workflows

Repository structure proposal:

.github/workflows/
pr-opened.yml
pr-merged.yml
deploy-status.yml

Requirements:

1. PR Opened
   trigger:

* pull_request.opened
* pull_request.reopened

behavior:

* linked issues
* update → Code Review

2. PR Merged
   trigger:

* pull_request.closed

condition:

* merged == true

behavior:

* update → Done

3. Deploy Success
   trigger:

* workflow_run
  หรือ deployment success event

behavior:

* update deploy fields

Important:

* Actions ต้อง thin
* business logic อยู่ MCP/util layer
* reusable across repositories

==================================================
PHASE 5 — CREATE REPO TEMPLATE
==============================

สร้าง reusable bootstrap template

Template should include:

* reusable workflows
* copilot instructions
* MCP configuration
* environment variable examples
* GitHub Variables setup guide

==================================================
IMPORTANT ARCHITECTURE RULES
============================

1. DO NOT use branch-name parsing as source of truth

2. Multi-issue branch must be supported

3. PR metadata is source of truth:

* Closes #12
* Closes #15

4. GitHub Project V2 is workflow state source of truth

5. Copilot should orchestrate through MCP tools
   NOT directly through raw API calls

6. GitHub Actions should remain event handlers only
   NOT orchestration brains

7. All workflows must be reusable across repositories

==================================================
DELIVERABLES
============

Please generate:

1. proposed folder structure
2. implementation plan
3. MCP server structure
4. reusable workflow examples
5. GraphQL utility structure
6. environment variable strategy
7. migration strategy from current workflows
8. risks and edge cases
9. recommended conventions
10. phased rollout plan

Start with architecture + folder structure before implementation.
