#!/usr/bin/env bash
# =====================================================================================
# Deploys the App Service Easy Auth query-string round-trip scenario. (Bash version)
# =====================================================================================
set -euo pipefail

LOCATION="${LOCATION:-eastus2}"
NAME_PREFIX="${NAME_PREFIX:-easyauth}"
RG_NAME="${RG_NAME:-rg-easyauth-demo}"
APP_REG_NAME="${APP_REG_NAME:-easyauth-demo-app}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== App Service Easy Auth — Query String Round-Trip Demo ==="

TENANT_ID="$(az account show --query tenantId -o tsv)"
SUB_NAME="$(az account show --query name -o tsv)"
SUB_ID="$(az account show --query id -o tsv)"
echo "Subscription : $SUB_NAME ($SUB_ID)"
echo "Tenant       : $TENANT_ID"
echo "Location     : $LOCATION"
echo "Resource group: $RG_NAME"

echo ""
echo "[1/5] Ensuring resource group..."
az group create --name "$RG_NAME" --location "$LOCATION" --output none

echo ""
echo "[2/5] Ensuring Entra app registration '$APP_REG_NAME'..."
APP_ID="$(az ad app list --display-name "$APP_REG_NAME" --query '[0].appId' -o tsv)"
if [[ -z "$APP_ID" ]]; then
    APP_ID="$(az ad app create \
        --display-name "$APP_REG_NAME" \
        --sign-in-audience AzureADMyOrg \
        --enable-id-token-issuance true \
        --query appId -o tsv)"
    echo "  Created: $APP_ID"
    az ad sp create --id "$APP_ID" --output none 2>/dev/null || true
else
    echo "  Reusing: $APP_ID"
fi
OBJECT_ID="$(az ad app show --id "$APP_ID" --query id -o tsv)"

echo "  Creating client secret..."
CLIENT_SECRET="$(az ad app credential reset \
    --id "$APP_ID" \
    --display-name "easyauth-demo-$(date +%Y%m%d%H%M%S)" \
    --years 1 \
    --query password -o tsv)"

echo ""
echo "[3/5] Deploying Bicep..."
DEPLOY_NAME="easyauth-$(date +%Y%m%d%H%M%S)"
DEPLOY_OUT="$(az deployment group create \
    --resource-group "$RG_NAME" \
    --name "$DEPLOY_NAME" \
    --template-file "$SCRIPT_DIR/bicep/main.bicep" \
    --parameters \
        location="$LOCATION" \
        namePrefix="$NAME_PREFIX" \
        entraClientId="$APP_ID" \
        entraTenantId="$TENANT_ID" \
        entraClientSecret="$CLIENT_SECRET" \
    --output json)"

WEB_APP_NAME="$(echo "$DEPLOY_OUT" | jq -r '.properties.outputs.webAppName.value')"
WEB_APP_URL="$(echo "$DEPLOY_OUT"  | jq -r '.properties.outputs.webAppUrl.value')"
CALLBACK_URL="$(echo "$DEPLOY_OUT" | jq -r '.properties.outputs.authCallbackUrl.value')"
echo "  Web App  : $WEB_APP_NAME"
echo "  URL      : $WEB_APP_URL"
echo "  Callback : $CALLBACK_URL"

echo ""
echo "[4/5] Updating app registration redirect URI..."
BODY=$(cat <<EOF
{ "web": { "redirectUris": ["$CALLBACK_URL"], "implicitGrantSettings": { "enableIdTokenIssuance": true } } }
EOF
)
echo "$BODY" | az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
    --headers "Content-Type=application/json" \
    --body @- --output none

echo ""
echo "[5/5] Packaging and deploying the Node app..."
APP_DIR="$SCRIPT_DIR/app"
ZIP_PATH="/tmp/easyauth-app-$(date +%Y%m%d%H%M%S).zip"
(cd "$APP_DIR" && zip -q "$ZIP_PATH" index.js package.json)
az webapp deploy \
    --resource-group "$RG_NAME" \
    --name "$WEB_APP_NAME" \
    --src-path "$ZIP_PATH" \
    --type zip \
    --async false \
    --output none
rm -f "$ZIP_PATH"

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Open in a browser (in this order):"
echo "  1. $WEB_APP_URL/?nhi=12345&tenant=acme&view=dashboard"
echo "  2. $WEB_APP_URL/?login_hint=alice@contoso.com&nhi=99999&feature=beta"
echo "  3. $WEB_APP_URL/landing?orderId=ABC-7788&source=email"
echo ""
echo "Cleanup:  az group delete --name $RG_NAME --yes --no-wait"
echo "          az ad app delete --id $APP_ID"
