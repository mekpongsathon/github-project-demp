Architecture update / implementation correction:

หลัง review architecture อีกครั้ง เราจะเปลี่ยน implementation direction จาก:

❌ MCP Server first
→ ไปเป็น
✅ CLI-first orchestration

เหตุผล:

* current workflow requirements ยังไม่จำเป็นต้องมี long-running orchestration server
* ต้องการ simpler setup
* easier onboarding
* easier debugging
* reusable across repos
* avoid local background runtime complexity

==================================================
NEW TARGET ARCHITECTURE
=======================

Developer
↓
Copilot
↓
TypeScript CLI Commands
↓
GitHub APIs / GraphQL
↓
GitHub Project V2

และ GitHub Actions:

* handle repository lifecycle events only
* PR opened
* PR merged
* deploy success

==================================================
IMPORTANT CHANGE
================

❌ DO NOT implement MCP server now
❌ DO NOT create persistent local server/runtime
❌ DO NOT create tool registry or MCP transport layer

Instead:

✅ Implement reusable TypeScript CLI commands
✅ Copilot will invoke CLI commands
✅ CLI commands orchestrate workflows
✅ GitHub Actions remain thin event handlers

==================================================
NEW IMPLEMENTATION STRUCTURE
============================

Suggested structure:

tools/
github/
graphql.ts
project.ts
issues.ts
pullRequests.ts

workflows/
start-work.ts
open-pr.ts
update-deploy.ts
check-status.ts

shared/
git.ts
github.ts
config.ts
logger.ts

.github/
workflows/
pr-opened.yml
pr-merged.yml
deploy-status.yml

==================================================
CLI COMMANDS
============

1. start-work

Example:
npm run start-work -- 12 15 18

Behavior:

* create branch
* push branch
* update issues/project statuses → In Progress

==================================================

2. open-pr

Example:
npm run open-pr

Behavior:

* create PR
* generate:
  Closes #12
  Closes #15
* assign reviewers
* update statuses → Code Review

==================================================

3. update-deploy

Example:
npm run update-deploy -- --env dev --status deployed

Behavior:

* update deploy fields in Project V2

==================================================

4. check-status

Example:
npm run check-status

Behavior:

* summarize:

  * current branch
  * linked issues
  * PR state
  * deploy states

==================================================
IMPORTANT ARCHITECTURE RULES
============================

1. GitHub Project V2 remains source of truth

2. PR metadata remains issue linkage source:
   Closes #12

3. Multi-issue branch must be supported

4. DO NOT rely on branch-name parsing

5. GitHub Actions must remain thin:

   * event handlers only
   * no business orchestration logic

6. Business logic must live in reusable TypeScript utilities

7. CLI commands must be:

   * idempotent
   * retry-safe
   * reusable across repositories

==================================================
PACKAGE.JSON REQUIREMENTS
=========================

Please generate package scripts:

{
"scripts": {
"start-work": "tsx tools/workflows/start-work.ts",
"open-pr": "tsx tools/workflows/open-pr.ts",
"update-deploy": "tsx tools/workflows/update-deploy.ts",
"check-status": "tsx tools/workflows/check-status.ts"
}
}

==================================================
MIGRATION REQUIREMENTS
======================

Please refactor any MCP-specific implementation plan into:

* reusable CLI utilities
* shared TypeScript modules
* GitHub Actions + CLI architecture

while keeping:

* reusable workflow goals
* multi-issue support
* Project V2 integration
* GraphQL utilities
* deployment lifecycle tracking

Start by updating:

1. architecture diagrams
2. implementation plan
3. folder structure
4. runtime model
5. reusable workflow strategy
