#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${STATE_FILE:-${SCRIPT_DIR}/.demo-state.json}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
SKIP_CONFIRMATION=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --skip-confirmation) SKIP_CONFIRMATION=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$RESOURCE_GROUP" && -f "$STATE_FILE" ]]; then
  RESOURCE_GROUP="$(jq -r '.resourceGroupName' "$STATE_FILE")"
fi
[[ -n "$RESOURCE_GROUP" ]] || { echo "Specify --resource-group or provide a valid deployment state file." >&2; exit 1; }

if [[ "$SKIP_CONFIRMATION" == false ]]; then
  read -r -p "Delete all scenario resources in '${RESOURCE_GROUP}' (y/N) " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cleanup cancelled."; exit 0; }
fi

az group delete --name "$RESOURCE_GROUP" --yes --no-wait
rm -f "$STATE_FILE"
echo "Cleanup started for '${RESOURCE_GROUP}'."