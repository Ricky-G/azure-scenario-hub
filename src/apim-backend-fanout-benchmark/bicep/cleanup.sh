#!/usr/bin/env bash
###############################################################################
# Delete the APIM Backend Fan-out Benchmark resource group.
###############################################################################
set -euo pipefail

RESOURCE_GROUP="${1:-rg-apimfo-benchmark}"
SKIP_CONFIRM="${2:-}"

echo
echo "=== Cleanup ==="
echo "  Resource Group: $RESOURCE_GROUP"

if [ "$(az group exists --name "$RESOURCE_GROUP")" != "true" ]; then
    echo "Resource group '$RESOURCE_GROUP' not found. Nothing to do."
    exit 0
fi

if [ "$SKIP_CONFIRM" != "--yes" ]; then
    echo "This will DELETE all resources in '$RESOURCE_GROUP'."
    read -r -p "Continue? (y/N) " REPLY
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

echo "Deleting resource group (this runs async)..."
az group delete --name "$RESOURCE_GROUP" --yes --no-wait
echo "Delete submitted. APIM Premium soft-delete takes ~45 min to complete."
