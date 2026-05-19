#!/usr/bin/env bash
###############################################################################
# Deploy the APIM Backend Fan-out Benchmark scenario.
###############################################################################
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 <location> <name-prefix> [--publisher-email EMAIL] [--publisher-name NAME] [--api-count N] [--yes]

Arguments:
  location       Azure region (e.g. australiaeast)
  name-prefix    3-8 char prefix used to derive all resource names

Options:
  --publisher-email EMAIL   APIM publisher email (default: admin@example.com)
  --publisher-name NAME     APIM publisher name (default: Benchmark)
  --api-count N             Number of APIs per APIM (default: 10)
  --yes                     Skip confirmation prompt
EOF
    exit 1
}

[[ $# -lt 2 ]] && usage

LOCATION="$1"
NAME_PREFIX="$2"
shift 2

PUBLISHER_EMAIL="admin@example.com"
PUBLISHER_NAME="Benchmark"
API_COUNT=10
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --publisher-email) PUBLISHER_EMAIL="$2"; shift 2 ;;
        --publisher-name)  PUBLISHER_NAME="$2";  shift 2 ;;
        --api-count)       API_COUNT="$2";       shift 2 ;;
        --yes)             SKIP_CONFIRM=true;    shift ;;
        -h|--help)         usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

RESOURCE_GROUP="rg-${NAME_PREFIX}-benchmark"

echo
echo "=== APIM Backend Fan-out Benchmark — Deploy ==="
echo "  Location:        $LOCATION"
echo "  Resource Group:  $RESOURCE_GROUP"
echo "  Name Prefix:     $NAME_PREFIX"
echo "  API Count:       $API_COUNT"
echo "  Publisher Email: $PUBLISHER_EMAIL"
echo

if ! az account show >/dev/null 2>&1; then
    az login >/dev/null
fi
SUB=$(az account show --query "[name, id]" -o tsv | tr '\n' ' ')
echo "Subscription: $SUB"

if [ "$SKIP_CONFIRM" = false ]; then
    echo
    echo "Deployment provisions 2 x Premium APIMs (~45 min) and an EP1 Function App."
    echo "Estimated cost: ~\$1,300/month. Run cleanup.sh promptly when done."
    read -r -p "Continue? (y/N) " REPLY
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

DEPLOYMENT_NAME="apim-fanout-$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "Starting deployment '$DEPLOYMENT_NAME'..."

az deployment sub create \
    --name "$DEPLOYMENT_NAME" \
    --location "$LOCATION" \
    --template-file "$SCRIPT_DIR/main.bicep" \
    --parameters \
        location="$LOCATION" \
        namePrefix="$NAME_PREFIX" \
        resourceGroupName="$RESOURCE_GROUP" \
        publisherEmail="$PUBLISHER_EMAIL" \
        publisherName="$PUBLISHER_NAME" \
        apiCount="$API_COUNT" \
    --output none

OUTPUTS=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query properties.outputs -o json)

echo
echo "=== Deployment complete ==="
echo "  Resource Group: $(echo "$OUTPUTS" | jq -r '.resourceGroupName.value')"
echo "  Function App:   $(echo "$OUTPUTS" | jq -r '.functionAppName.value')"
echo "  Function Host:  $(echo "$OUTPUTS" | jq -r '.functionAppHostname.value')"
echo "  APIM-A:         $(echo "$OUTPUTS" | jq -r '.apimAName.value')"
echo "    Gateway URL:  $(echo "$OUTPUTS" | jq -r '.apimAGatewayUrl.value')"
echo "  APIM-B:         $(echo "$OUTPUTS" | jq -r '.apimBName.value')"
echo "    Gateway URL:  $(echo "$OUTPUTS" | jq -r '.apimBGatewayUrl.value')"
echo "  App Insights:   $(echo "$OUTPUTS" | jq -r '.appInsightsName.value')"
echo "  Log Analytics:  $(echo "$OUTPUTS" | jq -r '.logAnalyticsWorkspaceName.value')"
echo
echo "Next step — publish the Function App code:"
echo "  cd ../backend/MockBackend"
echo "  func azure functionapp publish $(echo "$OUTPUTS" | jq -r '.functionAppName.value')"
echo
echo "Then run the benchmark from ../test-harness with Run-Benchmark.ps1."
