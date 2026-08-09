#!/usr/bin/env bash
set -euo pipefail

RESOURCE_GROUP="rg-front-door-private-appgw-apim-dr"
LOCATION="newzealandnorth"
NAME_PREFIX="fdapimdr"
APIM_SKU="Premium"
PUBLISHER_EMAIL=""
PUBLISHER_NAME="Azure Scenario Hub"
PRIVATE_LINK_LOCATION="australiaeast"
KUBERNETES_VERSION="1.34"
NODE_VM_SIZE="Standard_D2s_v5"
CHART_VERSION="1.15.1"
SKIP_CONFIRMATION=false
SKIP_WHAT_IF=false

usage() {
  echo "Usage: $0 [--resource-group NAME] [--location NAME] [--name-prefix PREFIX] [--apim-sku Premium|Developer] [--publisher-email EMAIL] [--skip-confirmation] [--skip-what-if]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --name-prefix) NAME_PREFIX="$2"; shift 2 ;;
    --apim-sku) APIM_SKU="$2"; shift 2 ;;
    --publisher-email) PUBLISHER_EMAIL="$2"; shift 2 ;;
    --publisher-name) PUBLISHER_NAME="$2"; shift 2 ;;
    --private-link-location) PRIVATE_LINK_LOCATION="$2"; shift 2 ;;
    --kubernetes-version) KUBERNETES_VERSION="$2"; shift 2 ;;
    --node-vm-size) NODE_VM_SIZE="$2"; shift 2 ;;
    --chart-version) CHART_VERSION="$2"; shift 2 ;;
    --skip-confirmation) SKIP_CONFIRMATION=true; shift ;;
    --skip-what-if) SKIP_WHAT_IF=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ ${#NAME_PREFIX} -lt 3 || ${#NAME_PREFIX} -gt 10 ]]; then
  echo "--name-prefix must contain 3-10 characters." >&2
  exit 1
fi
if [[ "$APIM_SKU" != "Premium" && "$APIM_SKU" != "Developer" ]]; then
  echo "--apim-sku must be Premium or Developer." >&2
  exit 1
fi

for command in az kubectl helm jq zip curl; do
  command -v "$command" >/dev/null || { echo "Required command '$command' was not found." >&2; exit 1; }
done

date_utc_plus_days() {
  local days="$1"
  if date -u -d "+${days} days" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -d "+${days} days" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -v+"${days}"d +%Y-%m-%dT%H:%M:%SZ
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/bicep/main.bicep"
MANIFEST_FILE="${SCRIPT_DIR}/manifests/hello-backend.yaml"
APP_DIRECTORY="${SCRIPT_DIR}/app"
STATE_FILE="${SCRIPT_DIR}/.demo-state.json"

ACCOUNT_JSON="$(az account show --output json)"
SUBSCRIPTION_ID="$(jq -r '.id' <<<"$ACCOUNT_JSON")"
SUBSCRIPTION_NAME="$(jq -r '.name' <<<"$ACCOUNT_JSON")"
if [[ -z "$PUBLISHER_EMAIL" ]]; then
  ACCOUNT_NAME="$(jq -r '.user.name' <<<"$ACCOUNT_JSON")"
  [[ "$ACCOUNT_NAME" == *"@"* ]] && PUBLISHER_EMAIL="$ACCOUNT_NAME" || PUBLISHER_EMAIL="admin@example.com"
fi

echo
echo "Front Door + private App Gateway + APIM hybrid DR scenario"
echo "Subscription:   ${SUBSCRIPTION_NAME}"
echo "Resource group: ${RESOURCE_GROUP}"
echo "Location:       ${LOCATION}"
echo "APIM SKU:       ${APIM_SKU}"

if [[ "$SKIP_CONFIRMATION" == false ]]; then
  echo "WARNING: APIM Premium, Front Door Premium, Application Gateway WAF_v2, AKS, and App Service accrue costs until cleanup."
  read -r -p "Continue (y/N) " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Deployment cancelled."; exit 0; }
fi

echo "[1/10] Compiling Bicep..."
az bicep build --file "$TEMPLATE_FILE" --stdout >/dev/null

echo "[2/10] Creating resource group..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags Project=AzureScenarioHub Scenario=FrontDoor-Private-AppGateway-APIM-SelfHosted-DR --output none

PARAMETERS=(
  "location=${LOCATION}"
  "namePrefix=${NAME_PREFIX}"
  "apimSku=${APIM_SKU}"
  "publisherEmail=${PUBLISHER_EMAIL}"
  "publisherName=${PUBLISHER_NAME}"
  "frontDoorPrivateLinkLocation=${PRIVATE_LINK_LOCATION}"
  "kubernetesVersion=${KUBERNETES_VERSION}"
  "nodeVmSize=${NODE_VM_SIZE}"
)

if [[ "$SKIP_WHAT_IF" == false ]]; then
  echo "[3/10] Running Azure deployment what-if..."
  az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "${PARAMETERS[@]}" \
    --result-format ResourceIdOnly \
    --output table
else
  echo "[3/10] Skipping Azure deployment what-if."
fi

DEPLOYMENT_NAME="front-door-apim-dr-$(date -u +%Y%m%d-%H%M%S)"
echo "[4/10] Deploying Azure resources. APIM is the long-running step..."
OUTPUTS_JSON="$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "${PARAMETERS[@]}" \
  --mode Incremental \
  --query properties.outputs \
  --output json)"

output_value() {
  jq -r --arg name "$1" '.[$name].value' <<<"$OUTPUTS_JSON"
}

APP_GATEWAY_NAME="$(output_value appGatewayName)"
AKS_CLUSTER_NAME="$(output_value aksClusterName)"
APIM_SERVICE_NAME="$(output_value apimServiceName)"
APIM_PRIVATE_IP="$(output_value apimPrivateIpAddress)"
SELF_HOSTED_GATEWAY_NAME="$(output_value selfHostedGatewayName)"
CONFIGURATION_URI="$(output_value selfHostedGatewayConfigurationUri)"
DR_PUBLIC_IP_NAME="$(output_value drPublicIpName)"
TEST_WEB_APP_NAME="$(output_value testWebAppName)"

RESOURCE_GROUP="$RESOURCE_GROUP" \
APP_GATEWAY_NAME="$APP_GATEWAY_NAME" \
AKS_CLUSTER_NAME="$AKS_CLUSTER_NAME" \
bash "${SCRIPT_DIR}/restore-baseline.sh"

echo "[5/10] Approving the Front Door private endpoint connection..."
PRIVATE_ENDPOINT_CONNECTION_ID=""
PRIVATE_ENDPOINT_CONNECTION_STATUS=""
for _ in $(seq 1 30); do
  CONNECTION_JSON="$(az network private-endpoint-connection list \
    --name "$APP_GATEWAY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --type Microsoft.Network/applicationGateways \
    --query "[?properties.privateLinkServiceConnectionState.status=='Approved' || properties.privateLinkServiceConnectionState.status=='Pending'] | [0].{id:id,status:properties.privateLinkServiceConnectionState.status}" \
    --output json)"
  PRIVATE_ENDPOINT_CONNECTION_ID="$(jq -r '.id // empty' <<<"$CONNECTION_JSON")"
  PRIVATE_ENDPOINT_CONNECTION_STATUS="$(jq -r '.status // empty' <<<"$CONNECTION_JSON")"
  [[ -n "$PRIVATE_ENDPOINT_CONNECTION_STATUS" ]] && break
  sleep 20
done
[[ -n "$PRIVATE_ENDPOINT_CONNECTION_STATUS" ]] || { echo "Front Door private endpoint request did not appear." >&2; exit 1; }
if [[ "$PRIVATE_ENDPOINT_CONNECTION_STATUS" == "Pending" ]]; then
  az network private-endpoint-connection approve --id "$PRIVATE_ENDPOINT_CONNECTION_ID" --description "Approved by scenario deployment automation." --output none
else
  echo "  Front Door private endpoint is already approved."
fi

echo "[6/10] Deploying the AKS Hello World backend..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --overwrite-existing --only-show-errors
kubectl apply --dry-run=server -f "$MANIFEST_FILE" --output name
kubectl apply -f "$MANIFEST_FILE"
kubectl rollout restart deployment/hello-backend
kubectl rollout status deployment/hello-backend --timeout=5m

echo "[7/10] Generating the APIM self-hosted gateway token..."
TOKEN_EXPIRY="$(date_utc_plus_days 29)"
GATEWAY_TOKEN_URI="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_SERVICE_NAME}/gateways/${SELF_HOSTED_GATEWAY_NAME}/generateToken?api-version=2024-05-01"
RAW_GATEWAY_TOKEN="$(az rest --method post --uri "$GATEWAY_TOKEN_URI" --body "{\"keyType\":\"primary\",\"expiry\":\"${TOKEN_EXPIRY}\"}" --query value --output tsv)"
[[ "$RAW_GATEWAY_TOKEN" == "GatewayKey "* ]] && GATEWAY_TOKEN="$RAW_GATEWAY_TOKEN" || GATEWAY_TOKEN="GatewayKey ${RAW_GATEWAY_TOKEN}"

echo "[8/10] Installing the APIM self-hosted gateway with Helm..."
VALUES_FILE="$(mktemp)"
APP_ZIP_BASE="$(mktemp "${TMPDIR:-/tmp}/front-door-path-tester.XXXXXX")"
rm -f "$APP_ZIP_BASE"
APP_ZIP="${APP_ZIP_BASE}.zip"
cleanup_temp() {
  rm -f "$VALUES_FILE" "$APP_ZIP"
}
trap cleanup_temp EXIT

cat >"$VALUES_FILE" <<EOF
fullnameOverride: apim-self-hosted-gateway
replicaCount: 1
gateway:
  configuration:
    uri: '${CONFIGURATION_URI}'
  auth:
    type: GatewayToken
    key: '${GATEWAY_TOKEN//\'/\'\'}'
  deployment:
    dns:
      hostAliases:
        - ip: '${APIM_PRIVATE_IP}'
          hostnames:
            - '${APIM_SERVICE_NAME}.configuration.azure-api.net'
service:
  type: LoadBalancer
  ports:
    http: 80
  annotations:
    service.beta.kubernetes.io/azure-pip-name: '${DR_PUBLIC_IP_NAME}'
    service.beta.kubernetes.io/azure-load-balancer-resource-group: '${RESOURCE_GROUP}'
highAvailability:
  enabled: false
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
EOF

helm upgrade --install apim-self-hosted-gateway azure-api-management-gateway \
  --repo https://azure.github.io/api-management-self-hosted-gateway/helm-charts/ \
  --version "$CHART_VERSION" \
  --namespace apim-gateway \
  --create-namespace \
  --values "$VALUES_FILE" \
  --wait \
  --timeout 10m
rm -f "$VALUES_FILE"

echo "[9/10] Publishing the browser test UI..."
(cd "$APP_DIRECTORY" && zip -qr "$APP_ZIP" .)
az webapp deploy \
  --resource-group "$RESOURCE_GROUP" \
  --name "$TEST_WEB_APP_NAME" \
  --src-path "$APP_ZIP" \
  --type zip \
  --clean true \
  --restart true \
  --output none
rm -f "$APP_ZIP"

jq -n \
  --arg deploymentName "$DEPLOYMENT_NAME" \
  --arg subscriptionId "$SUBSCRIPTION_ID" \
  --arg subscriptionName "$SUBSCRIPTION_NAME" \
  --arg resourceGroupName "$RESOURCE_GROUP" \
  --arg location "$LOCATION" \
  --arg createdAtUtc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg tokenExpiry "$TOKEN_EXPIRY" \
  --argjson outputs "$(jq 'with_entries(.value = .value.value)' <<<"$OUTPUTS_JSON")" \
  '{deploymentName:$deploymentName,subscriptionId:$subscriptionId,subscriptionName:$subscriptionName,resourceGroupName:$resourceGroupName,location:$location,createdAtUtc:$createdAtUtc,selfHostedGatewayTokenExpiresUtc:$tokenExpiry,outputs:$outputs}' \
  >"$STATE_FILE"

echo "[10/10] Running end-to-end validation..."
"${SCRIPT_DIR}/test-paths.sh" "$STATE_FILE"

echo
echo "Deployment and validation completed."
echo "Test UI:    $(output_value testWebAppUrl)"
echo "Happy path: $(output_value happyPathUrl)"
echo "DR path:    $(output_value drPathUrl)"
echo "State file: ${STATE_FILE}"