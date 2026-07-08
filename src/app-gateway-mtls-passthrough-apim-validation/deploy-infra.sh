#!/usr/bin/env bash
# =====================================================================
# Deploy the App Gateway PASSTHROUGH mTLS -> APIM POC (Linux/macOS)
# APIM Internal VNet provisioning takes ~30-45 minutes.
# =====================================================================
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-appgw-passthrough-mtls-poc}"
LOCATION="${LOCATION:-eastus2}"
NAME_PREFIX="${NAME_PREFIX:-mtlspoc}"
PUBLISHER_EMAIL="${PUBLISHER_EMAIL:-admin@example.com}"
FRONTEND_HOST="${FRONTEND_HOST:-api.mtls-poc.local}"
CERT_VALIDATION_MODE="${CERT_VALIDATION_MODE:-pinned}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-mtls-passthrough-poc}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/certs"
TEMPLATE="$SCRIPT_DIR/bicep/main.bicep"

# 1. Certificates
if [[ ! -f "$CERT_DIR/manifest.env" ]]; then
  echo "==> Generating certificate set..."
  "$SCRIPT_DIR/generate-certs.sh" "$FRONTEND_HOST"
fi
# shellcheck source=/dev/null
source "$CERT_DIR/manifest.env"

# 2. Resource group
echo "==> Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

# 3. ARM parameters file (avoids CLI length limit for the PFX base64)
PARAM_FILE="$CERT_DIR/deploy.parameters.json"
cat > "$PARAM_FILE" <<EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "namePrefix":          { "value": "$NAME_PREFIX" },
    "publisherEmail":      { "value": "$PUBLISHER_EMAIL" },
    "frontendHostName":    { "value": "$FRONTEND_HOST" },
    "serverCertData":      { "value": "$SERVER_CERT_PFX_B64" },
    "serverCertPassword":  { "value": "$SERVER_CERT_PASSWORD" },
    "trustedRootCaDerB64": { "value": "$TRUSTED_ROOT_CA_DER_B64" },
    "clientCertAllowlist": { "value": "$CLIENT_CERT_ALLOWLIST" },
    "certValidationMode":  { "value": "$CERT_VALIDATION_MODE" }
  }
}
EOF

# 4. Deploy
echo "==> Deploying. API Management provisioning takes 30-45 minutes; please wait..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$TEMPLATE" \
  --parameters "@$PARAM_FILE" \
  --output none

# 5. Capture outputs
az deployment group show --resource-group "$RESOURCE_GROUP" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs -o json > "$CERT_DIR/deploy-outputs.raw.json"

python3 - "$CERT_DIR/deploy-outputs.raw.json" "$CERT_DIR/deploy-output.json" "$RESOURCE_GROUP" "$LOCATION" <<'PY'
import json, sys
raw = json.load(open(sys.argv[1]))
out = {k: v["value"] for k, v in raw.items()}
out["resourceGroup"] = sys.argv[3]
out["location"] = sys.argv[4]
json.dump(out, open(sys.argv[2], "w"), indent=2)
PY

echo ""
echo "==> Deployment complete. Outputs saved to $CERT_DIR/deploy-output.json"
echo "==> Next: run ./run-tests.sh"
echo "==> REMEMBER: run ./teardown.sh when finished to stop billing."
