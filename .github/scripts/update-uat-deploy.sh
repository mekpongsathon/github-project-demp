#!/usr/bin/env bash
# update-uat-deploy.sh — Update UAT Deploy Status + Version for all PR-linked issues
#
# Reads linked issues via closingIssuesReferences, then updates two Project V2
# fields: a single-select status field and (on success) a text version field.
#
# Required environment variables:
#   GH_TOKEN                        — PAT with read:org + project scope
#   PROJECT_ID                      — GitHub Project V2 node ID  (PVT_...)
#   PR_NUMBER                       — Pull request number
#   DEPLOY_STATUS                   — "deploying" | "success" | "failed"
#   UAT_DEPLOY_STATUS_FIELD_ID      — Single-select field ID   (PVTSSF_...)
#   UAT_DEPLOY_VERSION_FIELD_ID     — Text field ID            (PVF_...)
#   DEPLOYING_OPTION_ID             — Option ID for "Deploying"
#   DEPLOY_SUCCESS_OPTION_ID        — Option ID for "Success"
#   DEPLOY_FAILED_OPTION_ID         — Option ID for "Failed"
#   DEPLOY_VERSION                  — Version string (applied only when status=success)
#
# Auto-set by GitHub Actions:
#   GITHUB_REPOSITORY_OWNER
#   GITHUB_REPOSITORY

set -euo pipefail

# ── Validation ────────────────────────────────────────────────────────────────
: "${PROJECT_ID:?Missing PROJECT_ID}"
: "${PR_NUMBER:?Missing PR_NUMBER}"
: "${DEPLOY_STATUS:?Missing DEPLOY_STATUS (deploying|success|failed)}"
: "${UAT_DEPLOY_STATUS_FIELD_ID:?Missing UAT_DEPLOY_STATUS_FIELD_ID}"
: "${UAT_DEPLOY_VERSION_FIELD_ID:?Missing UAT_DEPLOY_VERSION_FIELD_ID}"
: "${GITHUB_REPOSITORY_OWNER:?Missing GITHUB_REPOSITORY_OWNER}"
: "${GITHUB_REPOSITORY:?Missing GITHUB_REPOSITORY}"

OWNER="$GITHUB_REPOSITORY_OWNER"
REPO="${GITHUB_REPOSITORY#*/}"
DEPLOY_VERSION="${DEPLOY_VERSION:-}"

# ── Resolve option ID from status ─────────────────────────────────────────────
case "$DEPLOY_STATUS" in
  deploying) OPTION_ID="${DEPLOYING_OPTION_ID:?Missing DEPLOYING_OPTION_ID}" ;;
  success)   OPTION_ID="${DEPLOY_SUCCESS_OPTION_ID:?Missing DEPLOY_SUCCESS_OPTION_ID}" ;;
  failed)    OPTION_ID="${DEPLOY_FAILED_OPTION_ID:?Missing DEPLOY_FAILED_OPTION_ID}" ;;
  *)
    echo "ERROR: Unknown DEPLOY_STATUS '${DEPLOY_STATUS}' — must be deploying|success|failed" >&2
    exit 1
    ;;
esac

echo ">> UAT Deploy Update: status=${DEPLOY_STATUS}$([ -n "$DEPLOY_VERSION" ] && echo " version=${DEPLOY_VERSION}" || true)"
echo ""

# ── Step 1: Get linked issues from PR via closingIssuesReferences ──────────────
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
  -f owner="$OWNER" \
  -f repo="$REPO" \
  -F number="$PR_NUMBER" \
  --jq '.data.repository.pullRequest.closingIssuesReferences.nodes')

ISSUE_COUNT=$(echo "$LINKED_ISSUES" | jq 'length')
echo "   Found ${ISSUE_COUNT} linked issue(s)"

if [[ "$ISSUE_COUNT" -eq 0 ]]; then
  echo "   No linked issues — skipping"
  exit 0
fi

echo "   Issues: $(echo "$LINKED_ISSUES" | jq -r '[.[].number] | map("#\(.)") | join(", ")')"

# ── Step 2: Get all Project V2 items ──────────────────────────────────────────
echo ">> Fetching Project V2 items..."

PROJECT_ITEMS=$(gh api graphql \
  -f query='
    query($project: ID!) {
      node(id: $project) {
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
  ' \
  -f project="$PROJECT_ID" \
  --jq '.data.node.items.nodes')

# ── Step 3: Update each linked issue ──────────────────────────────────────────
UPDATED=0
SKIPPED=0

while IFS= read -r ISSUE; do
  ISSUE_ID=$(echo "$ISSUE"  | jq -r '.id')
  ISSUE_NUM=$(echo "$ISSUE" | jq -r '.number')

  ITEM_ID=$(echo "$PROJECT_ITEMS" | jq -r --arg id "$ISSUE_ID" \
    '.[] | select(.content != null and .content.id == $id) | .id // empty')

  if [[ -z "$ITEM_ID" ]]; then
    echo "   WARN: Issue #${ISSUE_NUM} not found in Project V2 — skipped"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Update single-select "UAT Deploy Status"
  gh api graphql \
    -f query='
      mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
        updateProjectV2ItemFieldValue(input: {
          projectId: $project
          itemId:    $item
          fieldId:   $field
          value: { singleSelectOptionId: $option }
        }) { projectV2Item { id } }
      }
    ' \
    -f project="$PROJECT_ID" \
    -f item="$ITEM_ID" \
    -f field="$UAT_DEPLOY_STATUS_FIELD_ID" \
    -f option="$OPTION_ID" \
    --jq '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null

  echo "   OK  Issue #${ISSUE_NUM} UAT Deploy Status -> ${DEPLOY_STATUS}"

  # Update text "UAT Deploy Version" — only when success and version provided
  if [[ "$DEPLOY_STATUS" == "success" && -n "$DEPLOY_VERSION" ]]; then
    gh api graphql \
      -f query='
        mutation($project: ID!, $item: ID!, $field: ID!, $text: String!) {
          updateProjectV2ItemFieldValue(input: {
            projectId: $project
            itemId:    $item
            fieldId:   $field
            value: { text: $text }
          }) { projectV2Item { id } }
        }
      ' \
      -f project="$PROJECT_ID" \
      -f item="$ITEM_ID" \
      -f field="$UAT_DEPLOY_VERSION_FIELD_ID" \
      -f text="$DEPLOY_VERSION" \
      --jq '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null

    echo "   OK  Issue #${ISSUE_NUM} UAT Deploy Version -> ${DEPLOY_VERSION}"
  fi

  UPDATED=$((UPDATED + 1))

done < <(echo "$LINKED_ISSUES" | jq -c '.[]')

echo ""
echo "DONE: ${UPDATED} issue(s) updated, ${SKIPPED} skipped"
