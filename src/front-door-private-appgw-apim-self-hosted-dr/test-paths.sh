#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${1:-${SCRIPT_DIR}/.demo-state.json}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-30}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-20}"

[[ -f "$STATE_FILE" ]] || { echo "Deployment state not found: ${STATE_FILE}" >&2; exit 1; }
for command in az kubectl jq curl; do
  command -v "$command" >/dev/null || { echo "Required command '$command' was not found." >&2; exit 1; }
done

state_value() {
  jq -r "$1" "$STATE_FILE"
}

assert_equal() {
  local actual="$1" expected="$2" message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL  ${message} Expected '${expected}', received '${actual}'." >&2
    exit 1
  fi
  echo "PASS  ${message}"
}

RESOURCE_GROUP="$(state_value '.resourceGroupName')"
APIM_NAME="$(state_value '.outputs.apimServiceName')"
APP_GATEWAY_NAME="$(state_value '.outputs.appGatewayName')"

echo
echo "Infrastructure assertions"
APP_GATEWAY_OPERATIONAL_STATE="$(az network application-gateway show --resource-group "$RESOURCE_GROUP" --name "$APP_GATEWAY_NAME" --query operationalState --output tsv)"
assert_equal "$APP_GATEWAY_OPERATIONAL_STATE" "Running" "Application Gateway is running."

AKS_POWER_STATE="$(az aks show --resource-group "$RESOURCE_GROUP" --name "$(state_value '.outputs.aksClusterName')" --query powerState.code --output tsv)"
assert_equal "$AKS_POWER_STATE" "Running" "AKS is running."

APIM_VNET_TYPE="$(az apim show --resource-group "$RESOURCE_GROUP" --name "$APIM_NAME" --query virtualNetworkType --output tsv)"
assert_equal "$APIM_VNET_TYPE" "Internal" "API Management uses internal VNet mode."

PUBLIC_LISTENER_COUNT="$(az network application-gateway show --resource-group "$RESOURCE_GROUP" --name "$APP_GATEWAY_NAME" --query "length(httpListeners[?contains(frontendIPConfiguration.id, '/frontendIPConfigurations/public-frontend-no-listener')])" --output tsv)"
assert_equal "$PUBLIC_LISTENER_COUNT" "0" "Application Gateway has no listener on its platform-required public frontend."

CONNECTION_STATUSES="$(az network private-endpoint-connection list --resource-group "$RESOURCE_GROUP" --name "$APP_GATEWAY_NAME" --type Microsoft.Network/applicationGateways --query '[].properties.privateLinkServiceConnectionState.status' --output tsv)"
grep -q '^Approved$' <<<"$CONNECTION_STATUSES" || { echo "FAIL  Application Gateway has no approved Front Door private endpoint connection." >&2; exit 1; }
echo "PASS  Front Door Private Link connection is approved."

BACKEND_READY="$(kubectl get deployment hello-backend --output jsonpath='{.status.readyReplicas}')"
assert_equal "$BACKEND_READY" "2" "Both Hello World backend replicas are ready."

GATEWAY_READY="$(kubectl get deployment apim-self-hosted-gateway --namespace apim-gateway --output jsonpath='{.status.readyReplicas}')"
assert_equal "$GATEWAY_READY" "1" "The APIM self-hosted gateway pod is ready."

GATEWAY_PUBLIC_IP="$(kubectl get service apim-self-hosted-gateway --namespace apim-gateway --output jsonpath='{.status.loadBalancer.ingress[0].ip}')"
assert_equal "$GATEWAY_PUBLIC_IP" "$(state_value '.outputs.drPublicIpAddress')" "The self-hosted gateway uses the reserved DR public IP."

AKS_SUBNET_ID="$(az aks show --resource-group "$RESOURCE_GROUP" --name "$(state_value '.outputs.aksClusterName')" --query 'agentPoolProfiles[0].vnetSubnetId' --output tsv)"
AKS_SUBNET_NSG_ID="$(az network vnet subnet show --ids "$AKS_SUBNET_ID" --query 'networkSecurityGroup.id' --output tsv)"
FRONT_DOOR_RULE_SOURCE="$(az rest --method get --url "https://management.azure.com${AKS_SUBNET_NSG_ID}/securityRules/Allow-AzureFrontDoor-To-SelfHostedGateway?api-version=2024-05-01" --query 'properties.sourceAddressPrefix' --output tsv)"
assert_equal "$FRONT_DOOR_RULE_SOURCE" "AzureFrontDoor.Backend" "The AKS subnet permits the DR gateway only from Azure Front Door."

GATEWAY_RESOURCE_URL="/subscriptions/$(state_value '.subscriptionId')/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/gateways/$(state_value '.outputs.selfHostedGatewayName')"
REGISTERED_GATEWAY_NAME="$(az rest --method get --url "${GATEWAY_RESOURCE_URL}?api-version=2024-05-01" --query name --output tsv)"
assert_equal "$REGISTERED_GATEWAY_NAME" "$(state_value '.outputs.selfHostedGatewayName')" "The self-hosted gateway is registered with the APIM instance."
ASSOCIATED_APIS="$(az rest --method get --url "${GATEWAY_RESOURCE_URL}/apis?api-version=2024-05-01" --query 'value[].name' --output tsv)"
grep -q '^dr-api$' <<<"$ASSOCIATED_APIS" || { echo "FAIL  The self-hosted gateway is not associated with dr-api." >&2; exit 1; }
echo "PASS  The APIM self-hosted gateway is associated with dr-api."

invoke_path() {
  local name="$1" url="$2" expected_route="$3" expected_gateway="$4" expected_app_gateway_hop="${5:-}"
  local headers body status route gateway expected_apim_service apim_service app_gateway_hop backend_request_id message backend response_request_id request_id
  headers="$(mktemp)"
  body="$(mktemp)"
  [[ "$expected_gateway" == "self-hosted" ]] && expected_apim_service="$APIM_NAME" || expected_apim_service="${APIM_NAME}.azure-api.net"

  for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    request_id="$(cat /proc/sys/kernel/random/uuid)"
    status="$(curl --silent --show-error --dump-header "$headers" --output "$body" --write-out '%{http_code}' --max-time 30 --header 'Cache-Control: no-cache' --header "X-Scenario-Request-Id: ${request_id}" "$url" || true)"
    route="$(awk -F': ' 'tolower($1)=="x-scenario-route" {gsub("\r", "", $2); print $2}' "$headers" | tail -1)"
    gateway="$(awk -F': ' 'tolower($1)=="x-apim-gateway" {gsub("\r", "", $2); print $2}' "$headers" | tail -1)"
    apim_service="$(awk -F': ' 'tolower($1)=="x-apim-service" {gsub("\r", "", $2); print $2}' "$headers" | tail -1)"
    app_gateway_hop="$(awk -F': ' 'tolower($1)=="x-appgateway-hop" {gsub("\r", "", $2); print $2}' "$headers" | tail -1)"
    backend_request_id="$(awk -F': ' 'tolower($1)=="x-backend-request-id" {gsub("\r", "", $2); print $2}' "$headers" | tail -1)"
    message="$(jq -r '.message // empty' "$body" 2>/dev/null || true)"
    backend="$(jq -r '.backend // empty' "$body" 2>/dev/null || true)"
    response_request_id="$(jq -r '.requestId // empty' "$body" 2>/dev/null || true)"
    if [[ "$status" == "200" && "$message" == "Hello World" && "$backend" == "mock-onprem-aks" && "$route" == "$expected_route" && "$gateway" == "$expected_gateway" && "$apim_service" == "$expected_apim_service" && "$backend_request_id" == "$request_id" && "$response_request_id" == "$request_id" && ( -z "$expected_app_gateway_hop" || "$app_gateway_hop" == "$expected_app_gateway_hop" ) ]]; then
      echo "PASS  ${name} returns HTTP 200."
      echo "PASS  ${name} reaches the AKS Hello World backend."
      echo "PASS  ${name} reports route '${route}' through gateway '${gateway}'."
      echo "PASS  ${name} reports APIM service '${apim_service}'."
      echo "PASS  ${name} backend echoes request ID '${request_id}'."
      [[ -z "$expected_app_gateway_hop" ]] || echo "PASS  ${name} reports Application Gateway hop '${app_gateway_hop}'."
      rm -f "$headers" "$body"
      return 0
    fi
    echo "WAIT  ${name} is not ready (attempt ${attempt}/${MAX_ATTEMPTS}, HTTP ${status}, route '${route}', gateway '${gateway}')."
    sleep "$RETRY_DELAY_SECONDS"
  done

  echo "FAIL  ${name} did not produce the expected response." >&2
  cat "$body" >&2
  rm -f "$headers" "$body"
  return 1
}

echo
echo "End-to-end assertions"
invoke_path "Happy path" "$(state_value '.outputs.happyPathUrl')" "happy-managed" "managed" "private-waf-v2"
invoke_path "DR path" "$(state_value '.outputs.drPathUrl')" "dr-self-hosted" "self-hosted"

UI_STATUS="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 30 "$(state_value '.outputs.testWebAppUrl')")"
assert_equal "$UI_STATUS" "200" "Hosted path tester UI returns HTTP 200."

invoke_evidence() {
  local route="$1" result_file status verified_hops
  result_file="$(mktemp)"
  for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    status="$(curl --silent --show-error --output "$result_file" --write-out '%{http_code}' --max-time 45 "$(state_value '.outputs.testWebAppUrl')/api/test?route=${route}" || true)"
    verified_hops="$(jq '[.hops[]? | select(.verified == true)] | length' "$result_file" 2>/dev/null || echo 0)"
    if [[ "$status" == "200" && "$(jq -r '.ok // false' "$result_file")" == "true" && "$verified_hops" == "4" ]]; then
      cat "$result_file"
      rm -f "$result_file"
      return 0
    fi
    sleep "$RETRY_DELAY_SECONDS"
  done
  cat "$result_file" >&2
  rm -f "$result_file"
  return 1
}

HAPPY_EVIDENCE="$(invoke_evidence happy)"
assert_equal "$(jq -r '.ok' <<<"$HAPPY_EVIDENCE")" "true" "Hosted UI evidence API verifies all four happy-path hops."

DR_EVIDENCE="$(invoke_evidence dr)"
assert_equal "$(jq -r '.ok' <<<"$DR_EVIDENCE")" "true" "Hosted UI evidence API verifies all four DR-path hops."
assert_equal "$(jq -r '.controlPlane.verified' <<<"$DR_EVIDENCE")" "true" "Hosted UI verifies APIM self-hosted gateway registration through managed identity."
jq -e '.controlPlane.associatedApis | index("dr-api") != null' <<<"$DR_EVIDENCE" >/dev/null || { echo "FAIL  Hosted UI control-plane evidence does not include dr-api." >&2; exit 1; }
echo "PASS  Hosted UI control-plane evidence includes dr-api."