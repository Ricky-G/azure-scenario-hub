#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.demo-state.json"
SKIP_CONFIRMATION=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --yes) SKIP_CONFIRMATION=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null || { echo 'jq is required.' >&2; exit 1; }
[[ -f "$STATE_FILE" ]] || { echo "Deployment state not found: $STATE_FILE" >&2; exit 1; }

SCENARIO_RG="$(jq -r '.parameters.scenarioResourceGroupName' "$STATE_FILE")"
if [[ "$SKIP_CONFIRMATION" != true ]]; then
  read -r -p "Delete APIM Federated Workspaces resources from '$SCENARIO_RG' (y/N)? " answer
  [[ "$answer" == 'y' || "$answer" == 'Y' ]] || exit 0
fi

if [[ "$(jq -r '.parameters.createApimService' "$STATE_FILE")" == 'true' ]]; then
  az group delete --name "$SCENARIO_RG" --yes --no-wait
else
  for workspace_id in \
    "$(jq -r '.outputs.dataScienceWorkspaceId.value' "$STATE_FILE")" \
    "$(jq -r '.outputs.websiteWorkspaceId.value' "$STATE_FILE")"; do
    az rest --method delete --url "$workspace_id?api-version=2024-05-01" --output none
  done
  az group delete --name "$SCENARIO_RG" --yes --no-wait
fi

rm -f "$STATE_FILE"
echo 'Cleanup started. APIM and workspace gateway deletion can take an extended period.'
