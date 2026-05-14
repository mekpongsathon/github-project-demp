#!/usr/bin/env bash
# update-project-field.sh — Update a Project V2 single-select field for all issues linked to a PR
#
# This is the core shared script used by status and deploy workflows.
# The caller sets FIELD_ID and OPTION_ID — this script handles the rest.
#
# Required environment variables:
#   GH_TOKEN       — PAT with read:org + project scope (auto-used by gh CLI)
#   PROJECT_ID     — GitHub Project V2 node ID  (PVT_...)
#   FIELD_ID       — Target field node ID        (PVTSSF_...)
#   OPTION_ID      — Target single-select option ID
#   PR_NUMBER      — Pull request number
#
# Auto-set by GitHub Actions:
#   GITHUB_REPOSITORY_OWNER  — repo owner (org or user)
#   GITHUB_REPOSITORY        — "owner/repo"

set -euo pipefail

# ── validation ────────────────────────────────────────────────────────────────
: "${PROJECT_ID:?Missing PROJECT_ID}"
: "${FIELD_ID:?Missing FIELD_ID}"
: "${OPTION_ID:?Missing OPTION_ID}"
: "${PR_NUMBER:?Missing PR_NUMBER}"
: "${GITHUB_REPOSITORY_OWNER:?Missing GITHUB_REPOSITORY_OWNER}"
: "${GITHUB_REPOSITORY:?Missing GITHUB_REPOSITORY}"

OWNER="$GITHUB_REPOSITORY_OWNER"
REPO="${GITHUB_REPOSITORY#*/}"

# ── step 1: get linked issues from PR ─────────────────────────────────────────
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

# ── step 2: get all project items (up to 100) ─────────────────────────────────
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

# ── step 3: update each linked issue ──────────────────────────────────────────
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

  gh api graphql \
    -f query='
      mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
        updateProjectV2ItemFieldValue(input: {
          projectId: $project
          itemId: $item
          fieldId: $field
          value: { singleSelectOptionId: $option }
        }) {
          projectV2Item { id }
        }
      }
    ' \
    -f project="$PROJECT_ID" \
    -f item="$ITEM_ID" \
    -f field="$FIELD_ID" \
    -f option="$OPTION_ID" \
    --jq '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null

  echo "   OK  Issue #${ISSUE_NUM} updated"
  UPDATED=$((UPDATED + 1))

done < <(echo "$LINKED_ISSUES" | jq -c '.[]')

echo ""
echo "DONE: ${UPDATED} issue(s) updated, ${SKIPPED} skipped"
