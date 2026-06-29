#!/usr/bin/env bash
# =====================================================================
# Deploys the Application Gateway + API Management diagnostics scenario.
#
# Creates a resource group and deploys a Log Analytics Workspace, a virtual
# network, API Management (with a Hello World API), and an Application Gateway
# (WAF_v2) that routes public traffic to APIM. Full diagnostic settings on
# both the Application Gateway and APIM stream to the Log Analytics Workspace.
#
# Usage:
#   ./deploy-infra.sh [-g resourceGroup] [-l location] [-p namePrefix] [-e publisherEmail]
# =====================================================================
set -euo pipefail

RESOURCE_GROUP="rg-app-gateway-apim-diagnostics"
LOCATION="eastus2"
NAME_PREFIX="agwdiag"
PUBLISHER_EMAIL="admin@example.com"

while getopts "g:l:p:e:" opt; do
  case $opt in
    g) RESOURCE_GROUP="$OPTARG" ;;
    l) LOCATION="$OPTARG" ;;
    p) NAME_PREFIX="$OPTARG" ;;
    e) PUBLISHER_EMAIL="$OPTARG" ;;
    *) echo "Usage: $0 [-g resourceGroup] [-l location] [-p namePrefix] [-e publisherEmail]" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/bicep/main.bicep"

echo "==> Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

echo "==> Deploying infrastructure (APIM provisioning can take 30-45 minutes)..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "appgw-apim-diag-deploy" \
  --template-file "$TEMPLATE_FILE" \
  --parameters namePrefix="$NAME_PREFIX" publisherEmail="$PUBLISHER_EMAIL" \
  --output none

echo "==> Deployment complete. Outputs:"
HELLO_URL=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "appgw-apim-diag-deploy" \
  --query "properties.outputs.helloWorldUrlViaAppGateway.value" \
  --output tsv)

az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "appgw-apim-diag-deploy" \
  --query "{LogAnalytics:properties.outputs.logAnalyticsWorkspaceName.value, APIM:properties.outputs.apimName.value, PublicIP:properties.outputs.appGatewayPublicIp.value, HelloUrl:properties.outputs.helloWorldUrlViaAppGateway.value}" \
  --output table

echo ""
echo "==> Testing the end-to-end route: $HELLO_URL"
if curl -fsS --max-time 30 "$HELLO_URL"; then
  echo ""
  echo "Success!"
else
  echo ""
  echo "Initial call failed (the Application Gateway backend can take a few minutes to report healthy)."
  echo "Try again shortly:  curl $HELLO_URL"
fi
