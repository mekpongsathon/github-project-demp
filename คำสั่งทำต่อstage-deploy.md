Extend the existing GitHub Project V2 workflow automation system to support deployment status tracking.

Current system already supports:

* Issue workflow automation
* Project V2 status updates
* PR linkage via `Closes #X`
* GitHub Actions automation
* GitOps deployment flow via Kustomize repositories
* PowerShell + GraphQL helper architecture

Your task is ONLY to add deployment tracking support.

Requirements:

1. Add deployment fields support

Assume GitHub Project V2 now contains these text fields:

* Dev Deploy
* UAT Deploy
* Prod Deploy

Add support for these new environment variables:

WORKFLOW_DEV_DEPLOY_FIELD_ID
WORKFLOW_UAT_DEPLOY_FIELD_ID
WORKFLOW_PROD_DEPLOY_FIELD_ID

2. Extend PowerShell deployment tooling

Update:

* tools/_github.ps1
* tools/update-deploy.ps1

Requirements:

* Reuse existing GraphQL helper patterns
* Reuse existing Project V2 item lookup logic
* Keep implementation modular
* Do not duplicate existing code unnecessarily

Expected command usage:

pwsh ./tools/update-deploy.ps1 `  -Issues "123,124"`
-Environment "uat" `
-Version "0.0.52"

Expected behavior:

* Update the corresponding Project V2 deployment field
* Example:

  * Environment=uat
  * Field="UAT Deploy"
  * Value="0.0.52"

3. Add deployment workflow integration

Update existing deployment GitHub Actions workflows.

After successful Kustomize repo update:

* extract linked issues from merged PR
* call update-deploy.ps1
* update deployment field automatically

IMPORTANT:

* Do NOT parse branch names for issue numbers
* Use existing GraphQL `closingIssuesReferences`
* Preserve current architecture principles

4. Add environment → field mapping

Implement reusable logic for:

* dev -> WORKFLOW_DEV_DEPLOY_FIELD_ID
* uat -> WORKFLOW_UAT_DEPLOY_FIELD_ID
* prod -> WORKFLOW_PROD_DEPLOY_FIELD_ID

5. Update documentation

Update:

* WORKFLOW-USAGE.md
* WORKFLOW-BLUEPRINT.en.md
* WORKFLOW-BLUEPRINT.th.md

Document:

* deployment tracking flow
* new required variables
* how deploy status updates work

6. Preserve current architecture

IMPORTANT:

* Do not redesign the current system
* Do not hardcode field IDs
* Continue using .env + Repository Variables
* Preserve portability between repositories
* Reuse existing helper functions whenever possible

7. Expected output

Generate:

* updated PowerShell scripts
* updated workflow YAML
* helper functions if necessary
* documentation updates
* concise explanation of deployment tracking flow
