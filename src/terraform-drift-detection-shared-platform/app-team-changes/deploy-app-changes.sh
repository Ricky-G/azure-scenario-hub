#!/usr/bin/env bash
# =============================================================================
# APP TEAM deploy script (Bash)
# =============================================================================
# Simulates the app team deploying child resources via Bicep into the
# platform-owned resources, OUT OF BAND from the platform Terraform workspace.
#
# It reads the platform resource names straight from the Terraform outputs, then
# runs `az deployment group create` against the same resource group.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
BICEP_FILE="$SCRIPT_DIR/main.bicep"

echo "Reading platform resource names from Terraform outputs..."
pushd "$TERRAFORM_DIR" > /dev/null
RG=$(terraform output -raw resource_group_name)
STORAGE=$(terraform output -raw storage_account_name)
COSMOS=$(terraform output -raw cosmos_account_name)
FOUNDRY=$(terraform output -raw foundry_account_name)
popd > /dev/null

echo "  Resource group : $RG"
echo "  Storage account: $STORAGE"
echo "  Cosmos account : $COSMOS"
echo "  Foundry account: $FOUNDRY"

echo "Deploying app-team child resources (Bicep)..."
az deployment group create \
  --resource-group "$RG" \
  --template-file "$BICEP_FILE" \
  --parameters \
    storageAccountName="$STORAGE" \
    cosmosAccountName="$COSMOS" \
    foundryAccountName="$FOUNDRY" \
  --query 'properties.provisioningState' -o tsv

echo ""
echo "App-team changes deployed."
echo "Now run ../scripts/check-drift.sh to see whether Terraform notices."
