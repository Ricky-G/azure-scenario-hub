#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${1:-$SCRIPT_DIR/.demo-state.json}"
API_VERSION='2024-05-01'
CONNECTION_API_VERSION='2024-06-01-preview'

command -v az >/dev/null || { echo 'Azure CLI is required.' >&2; exit 1; }
command -v jq >/dev/null || { echo 'jq is required.' >&2; exit 1; }
command -v curl >/dev/null || { echo 'curl is required.' >&2; exit 1; }
[[ -f "$STATE_FILE" ]] || { echo "Deployment state not found: $STATE_FILE" >&2; exit 1; }

pass() { printf 'PASS  %s\n' "$1"; }
assert_eq() {
  local actual="$1" expected="$2" message="$3"
  [[ "$actual" == "$expected" ]] || { echo "FAIL  $message (expected '$expected', got '$actual')" >&2; exit 1; }
  pass "$message"
}

DS_WORKSPACE_ID="$(jq -r '.outputs.dataScienceWorkspaceId.value' "$STATE_FILE")"
WEB_WORKSPACE_ID="$(jq -r '.outputs.websiteWorkspaceId.value' "$STATE_FILE")"
SCENARIO_RG="$(jq -r '.outputs.scenarioResourceGroupName.value' "$STATE_FILE")"
TOPOLOGY="$(jq -r '.outputs.gatewayTopology.value' "$STATE_FILE")"
DS_URL="$(jq -r '.outputs.dataScienceApiUrl.value' "$STATE_FILE")"
WEB_URL="$(jq -r '.outputs.websiteApiUrl.value' "$STATE_FILE")"

echo 'Control-plane validation'
assert_eq "$(az rest --method get --url "$DS_WORKSPACE_ID?api-version=$API_VERSION" --query properties.displayName --output tsv)" 'Data Science Team' 'Data Science workspace exists'
assert_eq "$(az rest --method get --url "$WEB_WORKSPACE_ID?api-version=$API_VERSION" --query properties.displayName --output tsv)" 'Website Experience Team' 'Website Experience workspace exists'
assert_eq "$(az rest --method get --url "$DS_WORKSPACE_ID/apis?api-version=$API_VERSION" --query "contains(value[].name, 'ds-fraud-risk-api')" --output tsv)" 'true' 'Data Science workspace owns its inference API'
assert_eq "$(az rest --method get --url "$WEB_WORKSPACE_ID/apis?api-version=$API_VERSION" --query "contains(value[].name, 'web-personalization-api')" --output tsv)" 'true' 'Website workspace owns its experience API'
assert_eq "$(az rest --method get --url "$DS_WORKSPACE_ID/products?api-version=$API_VERSION" --query "contains(value[].name, 'ds-model-products')" --output tsv)" 'true' 'Data Science team published its product'
assert_eq "$(az rest --method get --url "$WEB_WORKSPACE_ID/products?api-version=$API_VERSION" --query "contains(value[].name, 'web-experience-products')" --output tsv)" 'true' 'Website team published its product'

GATEWAYS_JSON="$(az resource list --resource-group "$SCENARIO_RG" --resource-type Microsoft.ApiManagement/gateways --output json)"
EXPECTED_GATEWAYS=2
[[ "$TOPOLOGY" == 'Shared' ]] && EXPECTED_GATEWAYS=1
assert_eq "$(jq 'length' <<<"$GATEWAYS_JSON")" "$EXPECTED_GATEWAYS" "$EXPECTED_GATEWAYS workspace gateway resource(s) use the selected topology"

CONNECTION_COUNT=0
while IFS= read -r gateway_id; do
  count="$(az rest --method get --url "$gateway_id/configConnections?api-version=$CONNECTION_API_VERSION" --query 'length(value)' --output tsv)"
  CONNECTION_COUNT=$((CONNECTION_COUNT + count))
done < <(jq -r '.[].id' <<<"$GATEWAYS_JSON")
assert_eq "$CONNECTION_COUNT" '2' 'Both workspaces are connected to runtime gateways'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

wait_api() {
  local url="$1" name="$2" deadline=$((SECONDS + 1200)) status
  while (( SECONDS < deadline )); do
    status="$(curl -sS -D "$TMP_DIR/$name.headers" -o "$TMP_DIR/$name.body" -w '%{http_code}' -H "X-Demo-Client: readiness-$RANDOM-$SECONDS" "$url" || true)"
    [[ "$status" == '200' ]] && return 0
    echo "Waiting for gateway configuration propagation: $url"
    sleep 20
  done
  echo "API did not become ready: $url" >&2
  exit 1
}

header_value() {
  local file="$1" header="$2"
  grep -i "^$header:" "$file" | tail -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//;s/ *$//'
}

echo 'Runtime validation'
wait_api "$DS_URL" ds
wait_api "$WEB_URL" web
assert_eq "$(jq -r '.servedBy' "$TMP_DIR/ds.body")" 'data-science' 'Data Science API returns the expected team payload'
assert_eq "$(jq -r '.servedBy' "$TMP_DIR/web.body")" 'website-experience' 'Website API returns the expected team payload'
assert_eq "$(header_value "$TMP_DIR/ds.headers" X-Workspace-Owner)" 'Data Science Team' 'Data Science workspace policy supplies team ownership'
assert_eq "$(header_value "$TMP_DIR/web.headers" X-Workspace-Owner)" 'Website Experience Team' 'Website workspace policy supplies team ownership'
assert_eq "$(header_value "$TMP_DIR/ds.headers" X-Team-Policy)" 'ds-standards-v1' 'Data Science reusable policy fragment executed'
assert_eq "$(header_value "$TMP_DIR/web.headers" X-Team-Policy)" 'web-standards-v1' 'Website reusable policy fragment executed'

EXPECTED_GOVERNANCE='customer-managed-global-policy'
[[ "$(jq -r '.parameters.configureGlobalPolicy' "$STATE_FILE")" == 'true' ]] && EXPECTED_GOVERNANCE='central-platform-baseline-v1'
assert_eq "$(header_value "$TMP_DIR/ds.headers" X-Platform-Governance)" "$EXPECTED_GOVERNANCE" 'Platform governance is visible on the Data Science API'
assert_eq "$(header_value "$TMP_DIR/web.headers" X-Platform-Governance)" "$EXPECTED_GOVERNANCE" 'Platform governance is visible on the Website API'

RATE_KEY="rate-test-$RANDOM-$SECONDS"
for attempt in 1 2 3 4 5; do
  assert_eq "$(curl -sS -o /dev/null -w '%{http_code}' -H "X-Demo-Client: $RATE_KEY" "$DS_URL")" '200' "Data Science rate-limit request $attempt is accepted"
done
THROTTLE_STATUS=''
for attempt in 6 7 8 9 10; do
  status="$(curl -sS -o /dev/null -w '%{http_code}' -H "X-Demo-Client: $RATE_KEY" "$DS_URL")"
  if [[ "$status" == '429' ]]; then
    THROTTLE_STATUS="$status"
    break
  fi
  assert_eq "$status" '200' "Data Science distributed counter request $attempt is accepted before throttling"
done
assert_eq "$THROTTLE_STATUS" '429' 'Data Science gateway begins returning 429 after the configured threshold'

echo 'All APIM workspace checks passed.'
echo "Data Science API: $DS_URL"
echo "Website API:      $WEB_URL"
