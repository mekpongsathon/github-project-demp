#!/usr/bin/env bash
# update-deploy-status.sh — Update a Project V2 deploy field for all issues linked to a PR
#
# Resolves FIELD_ID and OPTION_ID from DEPLOY_ENVIRONMENT + DEPLOY_STATUS.
# Option IDs differ per environment because each deploy field (dev/uat/prod)
# has its own independent set of single-select options.
#
# Required environment variables:
#   GH_TOKEN              — PAT with read:org + project scope
#   PROJECT_ID            — GitHub Project V2 node ID  (PVT_...)
#   PR_NUMBER             — Pull request number
#   DEPLOY_ENVIRONMENT    — "dev", "uat", or "prod"
#   DEPLOY_STATUS         — "waiting", "deploying", "deployed", or "failed"
#
#   Per-environment field IDs:
#   DEPLOY_DEV_FIELD_ID, DEPLOY_UAT_FIELD_ID, DEPLOY_PROD_FIELD_ID
#
#   Per-environment option IDs (pattern: DEPLOY_{ENV}_{STATUS}_OPTION_ID):
#   DEPLOY_DEV_WAITING_OPTION_ID, DEPLOY_DEV_DEPLOYED_OPTION_ID, ...
#   DEPLOY_UAT_WAITING_OPTION_ID, DEPLOY_UAT_DEPLOYED_OPTION_ID, ...
#   DEPLOY_PROD_WAITING_OPTION_ID, DEPLOY_PROD_DEPLOYED_OPTION_ID, ...

set -euo pipefail

: "${DEPLOY_ENVIRONMENT:?Missing DEPLOY_ENVIRONMENT (dev|uat|prod)}"
: "${DEPLOY_STATUS:?Missing DEPLOY_STATUS (waiting|deploying|deployed|failed)}"

# ── resolve field ID from environment ─────────────────────────────────────────
case "$DEPLOY_ENVIRONMENT" in
  dev)  FIELD_ID="${DEPLOY_DEV_FIELD_ID:?Missing DEPLOY_DEV_FIELD_ID}" ;;
  uat)  FIELD_ID="${DEPLOY_UAT_FIELD_ID:?Missing DEPLOY_UAT_FIELD_ID}" ;;
  prod) FIELD_ID="${DEPLOY_PROD_FIELD_ID:?Missing DEPLOY_PROD_FIELD_ID}" ;;
  *)    echo "ERROR: Unknown environment '${DEPLOY_ENVIRONMENT}' (must be dev|uat|prod)" >&2; exit 1 ;;
esac

# ── resolve option ID using per-env naming convention ─────────────────────────
# Pattern: DEPLOY_{ENV}_{STATUS}_OPTION_ID  (e.g. DEPLOY_DEV_DEPLOYED_OPTION_ID)
ENV_UPPER=$(echo "$DEPLOY_ENVIRONMENT" | tr '[:lower:]' '[:upper:]')
STATUS_UPPER=$(echo "$DEPLOY_STATUS"   | tr '[:lower:]' '[:upper:]')
OPTION_VAR="DEPLOY_${ENV_UPPER}_${STATUS_UPPER}_OPTION_ID"
OPTION_ID="${!OPTION_VAR:-}"

if [[ -z "$OPTION_ID" ]]; then
  echo "ERROR: ${OPTION_VAR} is not set or empty." >&2
  echo "       Add this option to your Project V2 deploy field and set the ID in your workflow vars." >&2
  exit 1
fi

echo ">> Deploy update: env=${DEPLOY_ENVIRONMENT} status=${DEPLOY_STATUS}"
echo "   Field ID:  ${FIELD_ID}"
echo "   Option ID: ${OPTION_ID}"
echo ""

export FIELD_ID
export OPTION_ID

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/update-project-field.sh"
