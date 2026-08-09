#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${STATE_FILE:-${SCRIPT_DIR}/.demo-state.json}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
APP_GATEWAY_NAME="${APP_GATEWAY_NAME:-}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-}"

if [[ -f "$STATE_FILE" ]]; then
  [[ -n "$RESOURCE_GROUP" ]] || RESOURCE_GROUP="$(jq -r '.resourceGroupName' "$STATE_FILE")"
  [[ -n "$APP_GATEWAY_NAME" ]] || APP_GATEWAY_NAME="$(jq -r '.outputs.appGatewayName' "$STATE_FILE")"
  [[ -n "$AKS_CLUSTER_NAME" ]] || AKS_CLUSTER_NAME="$(jq -r '.outputs.aksClusterName' "$STATE_FILE")"
fi

[[ -n "$RESOURCE_GROUP" && -n "$APP_GATEWAY_NAME" && -n "$AKS_CLUSTER_NAME" ]] || {
  echo "Provide STATE_FILE or set RESOURCE_GROUP, APP_GATEWAY_NAME, and AKS_CLUSTER_NAME." >&2
  exit 1
}

SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
APP_GATEWAY_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/applicationGateways/${APP_GATEWAY_NAME}"
AKS_CLUSTER_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME}"

APP_GATEWAY_STATE="$(az network application-gateway show --resource-group "$RESOURCE_GROUP" --name "$APP_GATEWAY_NAME" --query operationalState --output tsv)"
if [[ "$APP_GATEWAY_STATE" == "Stopping" ]]; then
  echo "Application Gateway '${APP_GATEWAY_NAME}' is stopping; waiting before restart..."
  az resource wait --ids "$APP_GATEWAY_ID" --api-version 2024-05-01 --custom "properties.operationalState=='Stopped'" --interval 15 --timeout 1800
  APP_GATEWAY_STATE="Stopped"
fi
if [[ "$APP_GATEWAY_STATE" == "Stopped" ]]; then
  echo "Starting Application Gateway '${APP_GATEWAY_NAME}'..."
  az rest --method post --url "https://management.azure.com${APP_GATEWAY_ID}/start?api-version=2024-05-01" --output none
elif [[ "$APP_GATEWAY_STATE" == "Starting" ]]; then
  echo "Application Gateway '${APP_GATEWAY_NAME}' is already starting..."
elif [[ "$APP_GATEWAY_STATE" != "Running" ]]; then
  echo "Application Gateway has unexpected operational state '${APP_GATEWAY_STATE}'." >&2
  exit 1
fi
if [[ "$APP_GATEWAY_STATE" != "Running" ]]; then
  az resource wait --ids "$APP_GATEWAY_ID" --api-version 2024-05-01 --custom "properties.operationalState=='Running'" --interval 15 --timeout 1800
fi
echo "Application Gateway: Running"

AKS_POWER_STATE="$(az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --query powerState.code --output tsv)"
if [[ "$AKS_POWER_STATE" == "Stopping" ]]; then
  echo "AKS cluster '${AKS_CLUSTER_NAME}' is stopping; waiting before restart..."
  az resource wait --ids "$AKS_CLUSTER_ID" --api-version 2024-09-01 --custom "properties.powerState.code=='Stopped'" --interval 15 --timeout 1800
  AKS_POWER_STATE="Stopped"
fi
if [[ "$AKS_POWER_STATE" == "Stopped" ]]; then
  echo "Starting AKS cluster '${AKS_CLUSTER_NAME}'..."
  az rest --method post --url "https://management.azure.com${AKS_CLUSTER_ID}/start?api-version=2024-09-01" --output none
elif [[ "$AKS_POWER_STATE" == "Starting" ]]; then
  echo "AKS cluster '${AKS_CLUSTER_NAME}' is already starting..."
elif [[ "$AKS_POWER_STATE" != "Running" ]]; then
  echo "AKS has unexpected power state '${AKS_POWER_STATE}'." >&2
  exit 1
fi
if [[ "$AKS_POWER_STATE" != "Running" ]]; then
  az resource wait --ids "$AKS_CLUSTER_ID" --api-version 2024-09-01 --custom "properties.powerState.code=='Running' && properties.provisioningState=='Succeeded'" --interval 15 --timeout 1800
fi
echo "AKS: Running"