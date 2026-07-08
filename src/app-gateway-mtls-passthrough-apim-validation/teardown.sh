#!/usr/bin/env bash
# =====================================================================
# Tear down the mTLS passthrough POC (Linux/macOS)
# =====================================================================
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-appgw-passthrough-mtls-poc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read -r -p "This will DELETE resource group '$RESOURCE_GROUP' and all resources. Type 'yes' to continue: " confirm
if [[ "$confirm" != "yes" ]]; then echo "Aborted."; exit 0; fi

echo "==> Deleting resource group '$RESOURCE_GROUP' (runs in background)..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo "==> Deletion started. Key Vault is soft-deleted for 7 days; purge with:"
echo "    az keyvault purge --name <keyVaultName>"

if [[ "${KEEP_CERTS:-0}" != "1" ]]; then
  rm -rf "$SCRIPT_DIR/certs"
  echo "==> Removed local ./certs directory."
fi
