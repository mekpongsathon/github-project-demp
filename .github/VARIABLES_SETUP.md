# GitHub Variables Setup Guide

ตั้งค่า Repository Variables ต่อไปนี้ใน:
**Settings → Secrets and variables → Actions → Variables**

## Required Variables

| Variable | Description | Example |
|---|---|---|
| `WORKFLOW_PROJECT_ID` | GitHub Project V2 Node ID | `PVT_kwHO...` |
| `WORKFLOW_STATUS_FIELD_ID` | Status field Node ID | `PVTSSF_lAHO...` |
| `WORKFLOW_IN_PROGRESS_OPTION_ID` | "In Progress" option ID | `47fc9ee4` |
| `WORKFLOW_CODE_REVIEW_OPTION_ID` | "Code Review" option ID | `98ab1234` |
| `WORKFLOW_DONE_OPTION_ID` | "Done" option ID | `c1d2e3f4` |

## Deploy Variables (Optional)

| Variable | Description |
|---|---|
| `WORKFLOW_DEPLOY_DEV_FIELD_ID` | Deploy-Dev field Node ID |
| `WORKFLOW_DEPLOY_UAT_FIELD_ID` | Deploy-UAT field Node ID |
| `WORKFLOW_DEPLOY_PROD_FIELD_ID` | Deploy-Prod field Node ID |
| `WORKFLOW_DEPLOY_WAITING_OPTION_ID` | "waiting" option ID |
| `WORKFLOW_DEPLOY_DEPLOYING_OPTION_ID` | "deploying" option ID |
| `WORKFLOW_DEPLOY_DEPLOYED_OPTION_ID` | "deployed" option ID |
| `WORKFLOW_DEPLOY_FAILED_OPTION_ID` | "failed" option ID |

## Required Secret

| Secret | Description |
|---|---|
| `PAT_TOKEN` | GitHub Personal Access Token with `project` + `repo` scopes |

## วิธีหา Node IDs

รันผ่าน GitHub CLI:

```bash
# หา Project ID
gh api graphql -f query='
  query($login: String!) {
    organization(login: $login) {
      projectsV2(first: 10) {
        nodes { id title }
      }
    }
  }
' -f login="YOUR_ORG"

# หา Field IDs และ Option IDs
gh api graphql -f query='
  query($project: ID!) {
    node(id: $project) {
      ... on ProjectV2 {
        fields(first: 20) {
          nodes {
            ... on ProjectV2SingleSelectField {
              id
              name
              options { id name }
            }
          }
        }
      }
    }
  }
' -f project="YOUR_PROJECT_ID"
```
