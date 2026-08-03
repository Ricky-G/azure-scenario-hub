#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/bicep/main.bicep"
STATE_FILE="$SCRIPT_DIR/.demo-state.json"

APIM_SERVICE_NAME=""
APIM_RESOURCE_GROUP_NAME=""
SCENARIO_RESOURCE_GROUP_NAME="rg-apim-federated-workspaces"
LOCATION="westus"
GATEWAY_TOPOLOGY="Shared"
NAME_PREFIX="apimwsdemo"
PUBLISHER_EMAIL=""
PUBLISHER_NAME="Contoso"
DATA_SCIENCE_TEAM_PRINCIPAL_ID=""
WEBSITE_TEAM_PRINCIPAL_ID=""
TEAM_PRINCIPAL_TYPE="Group"
CREATE_APIM=false
CONFIGURE_GLOBAL_POLICY=false
SKIP_CONFIRMATION=false

usage() {
  cat <<'EOF'
Usage: ./deploy-infra.sh [options]
  --create-apim                         Create a disposable Premium APIM service
  --apim-name NAME                     Existing or new APIM service name
  --apim-resource-group NAME           Resource group containing an existing APIM
  --scenario-resource-group NAME       Resource group for demo support resources
  --location LOCATION                  Region for a disposable APIM (default: westus)
  --gateway-topology Dedicated|Shared  Gateway isolation model (default: Shared)
  --configure-global-policy            Replace the existing service global policy with the demo policy
  --data-science-principal-id ID        Optional Data Science team Entra object ID
  --website-principal-id ID             Optional Website team Entra object ID
  --skip-confirmation                   Run non-interactively
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --create-apim) CREATE_APIM=true; shift ;;
    --apim-name) APIM_SERVICE_NAME="$2"; shift 2 ;;
    --apim-resource-group) APIM_RESOURCE_GROUP_NAME="$2"; shift 2 ;;
    --scenario-resource-group) SCENARIO_RESOURCE_GROUP_NAME="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --gateway-topology) GATEWAY_TOPOLOGY="$2"; shift 2 ;;
    --name-prefix) NAME_PREFIX="$2"; shift 2 ;;
    --publisher-email) PUBLISHER_EMAIL="$2"; shift 2 ;;
    --publisher-name) PUBLISHER_NAME="$2"; shift 2 ;;
    --configure-global-policy) CONFIGURE_GLOBAL_POLICY=true; shift ;;
    --data-science-principal-id) DATA_SCIENCE_TEAM_PRINCIPAL_ID="$2"; shift 2 ;;
    --website-principal-id) WEBSITE_TEAM_PRINCIPAL_ID="$2"; shift 2 ;;
    --team-principal-type) TEAM_PRINCIPAL_TYPE="$2"; shift 2 ;;
    --skip-confirmation) SKIP_CONFIRMATION=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

command -v az >/dev/null || { echo 'Azure CLI is required.' >&2; exit 1; }
command -v jq >/dev/null || { echo 'jq is required.' >&2; exit 1; }

ACCOUNT_JSON="$(az account show --output json)"
SUBSCRIPTION_ID="$(jq -r '.id' <<<"$ACCOUNT_JSON")"
SUBSCRIPTION_NAME="$(jq -r '.name' <<<"$ACCOUNT_JSON")"
if [[ -z "$PUBLISHER_EMAIL" ]]; then
  PUBLISHER_EMAIL="$(jq -r '.user.name' <<<"$ACCOUNT_JSON")"
  [[ "$PUBLISHER_EMAIL" == *'@'* ]] || PUBLISHER_EMAIL='admin@example.com'
fi

if [[ "$CREATE_APIM" == true ]]; then
  [[ -n "$APIM_SERVICE_NAME" ]] || APIM_SERVICE_NAME="apimwsdemo$(date +%s)"
  APIM_RESOURCE_GROUP_NAME="$SCENARIO_RESOURCE_GROUP_NAME"
  CONFIGURE_GLOBAL_POLICY=true
else
  if [[ -z "$APIM_SERVICE_NAME" || -z "$APIM_RESOURCE_GROUP_NAME" ]]; then
    echo 'Specify --apim-name and --apim-resource-group, or use --create-apim.' >&2
    exit 1
  fi
  SERVICE_JSON="$(az apim show --name "$APIM_SERVICE_NAME" --resource-group "$APIM_RESOURCE_GROUP_NAME" --output json)"
  SKU="$(jq -r '.sku.name' <<<"$SERVICE_JSON")"
  if [[ "$SKU" != 'Premium' && "$SKU" != 'PremiumV2' ]]; then
    echo "APIM '$APIM_SERVICE_NAME' uses unsupported SKU '$SKU'. Premium or PremiumV2 is required." >&2
    exit 1
  fi
  LOCATION="$(jq -r '.location' <<<"$SERVICE_JSON")"
fi

case "$GATEWAY_TOPOLOGY" in Dedicated|Shared) ;; *) echo 'Gateway topology must be Dedicated or Shared.' >&2; exit 1 ;; esac
case "$TEAM_PRINCIPAL_TYPE" in Group|User|ServicePrincipal) ;; *) echo 'Invalid team principal type.' >&2; exit 1 ;; esac

cat <<EOF

APIM Federated Workspaces deployment
Subscription:        $SUBSCRIPTION_NAME
APIM service:        $APIM_SERVICE_NAME
APIM resource group: $APIM_RESOURCE_GROUP_NAME
Scenario group:      $SCENARIO_RESOURCE_GROUP_NAME
Location:            $LOCATION
Gateway topology:    $GATEWAY_TOPOLOGY
Create APIM:         $CREATE_APIM
Demo global policy:  $CONFIGURE_GLOBAL_POLICY
EOF

if [[ "$SKIP_CONFIRMATION" != true ]]; then
  echo 'Workspace gateways incur additional charges and can take up to three hours to provision.'
  read -r -p 'Continue (y/N)? ' answer
  [[ "$answer" == 'y' || "$answer" == 'Y' ]] || exit 0
fi

az bicep build --file "$TEMPLATE_FILE" --stdout >/dev/null

PARAMETERS=(
  "location=$LOCATION"
  "scenarioResourceGroupName=$SCENARIO_RESOURCE_GROUP_NAME"
  "apimServiceName=$APIM_SERVICE_NAME"
  "apimResourceGroupName=$APIM_RESOURCE_GROUP_NAME"
  "createApimService=$CREATE_APIM"
  "configureGlobalPolicy=$CONFIGURE_GLOBAL_POLICY"
  "gatewayTopology=$GATEWAY_TOPOLOGY"
  "namePrefix=$NAME_PREFIX"
  "publisherEmail=$PUBLISHER_EMAIL"
  "publisherName=$PUBLISHER_NAME"
  "dataScienceTeamPrincipalId=$DATA_SCIENCE_TEAM_PRINCIPAL_ID"
  "websiteTeamPrincipalId=$WEBSITE_TEAM_PRINCIPAL_ID"
  "teamPrincipalType=$TEAM_PRINCIPAL_TYPE"
)

echo 'Running subscription deployment preflight...'
az deployment sub what-if \
  --name apim-federated-workspaces-preflight \
  --location "$LOCATION" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "${PARAMETERS[@]}" \
  --result-format ResourceIdOnly \
  --output table

DEPLOYMENT_NAME="apim-federated-workspaces-$(date +%Y%m%d-%H%M%S)"
echo "Starting deployment '$DEPLOYMENT_NAME'. Keep this terminal open."
DEPLOYMENT_JSON="$(az deployment sub create \
  --name "$DEPLOYMENT_NAME" \
  --location "$LOCATION" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "${PARAMETERS[@]}" \
  --output json)"

jq -n \
  --arg deploymentName "$DEPLOYMENT_NAME" \
  --arg subscriptionId "$SUBSCRIPTION_ID" \
  --arg subscriptionName "$SUBSCRIPTION_NAME" \
  --arg location "$LOCATION" \
  --arg gatewayTopology "$GATEWAY_TOPOLOGY" \
  --arg scenarioResourceGroupName "$SCENARIO_RESOURCE_GROUP_NAME" \
  --arg apimResourceGroupName "$APIM_RESOURCE_GROUP_NAME" \
  --arg apimServiceName "$APIM_SERVICE_NAME" \
  --argjson createApimService "$CREATE_APIM" \
  --argjson configureGlobalPolicy "$CONFIGURE_GLOBAL_POLICY" \
  --argjson outputs "$(jq '.properties.outputs' <<<"$DEPLOYMENT_JSON")" \
  '{deploymentName:$deploymentName,subscriptionId:$subscriptionId,subscriptionName:$subscriptionName,createdAtUtc:(now|todate),parameters:{createApimService:$createApimService,configureGlobalPolicy:$configureGlobalPolicy,location:$location,gatewayTopology:$gatewayTopology,scenarioResourceGroupName:$scenarioResourceGroupName,apimResourceGroupName:$apimResourceGroupName,apimServiceName:$apimServiceName},outputs:$outputs}' \
  >"$STATE_FILE"

echo 'Deployment completed.'
echo "Data Science API: $(jq -r '.properties.outputs.dataScienceApiUrl.value' <<<"$DEPLOYMENT_JSON")"
echo "Website API:      $(jq -r '.properties.outputs.websiteApiUrl.value' <<<"$DEPLOYMENT_JSON")"
echo 'Run: ./test-workspaces.sh'
