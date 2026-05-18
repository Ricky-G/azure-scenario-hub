#!/usr/bin/env bash
# ============================================================================
# Deploy the AI Gateway scenario (Bash version of deploy-infra.ps1).
# ============================================================================
set -euo pipefail

LOCATION="${LOCATION:-swedencentral}"
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-rg-ai-gateway-demo}"
NAME_PREFIX="${NAME_PREFIX:-aigw}"
PUBLISHER_EMAIL="${PUBLISHER_EMAIL:-admin@contoso.com}"
PUBLISHER_NAME="${PUBLISHER_NAME:-Contoso}"
FOUNDRY_RG="${FOUNDRY_RG:?FOUNDRY_RG is required}"
FOUNDRY_NAME="${FOUNDRY_NAME:?FOUNDRY_NAME is required}"
OPENAI_ENDPOINT="${OPENAI_ENDPOINT:?OPENAI_ENDPOINT is required, e.g. https://your-foundry.cognitiveservices.azure.com/}"
OPENAI_API_VERSION="${OPENAI_API_VERSION:-2024-10-21}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-ai-gateway-$(date +%Y%m%d%H%M%S)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_BICEP="${SCRIPT_DIR}/bicep/main.bicep"

echo "==> Subscription: $(az account show --query name -o tsv)"
echo "==> Submitting deployment ${DEPLOYMENT_NAME}"

az deployment sub create \
    --name "${DEPLOYMENT_NAME}" \
    --location "${LOCATION}" \
    --template-file "${MAIN_BICEP}" \
    --parameters \
        location="${LOCATION}" \
        resourceGroupName="${RESOURCE_GROUP_NAME}" \
        namePrefix="${NAME_PREFIX}" \
        publisherEmail="${PUBLISHER_EMAIL}" \
        publisherName="${PUBLISHER_NAME}" \
        foundryResourceGroupName="${FOUNDRY_RG}" \
        foundryAccountName="${FOUNDRY_NAME}" \
        openAiEndpoint="${OPENAI_ENDPOINT}" \
        openAiApiVersion="${OPENAI_API_VERSION}" \
    --output table

echo ""
echo "Done. Run ./test-harness/Invoke-Demo.ps1 (PowerShell 7+) to drive traffic."
