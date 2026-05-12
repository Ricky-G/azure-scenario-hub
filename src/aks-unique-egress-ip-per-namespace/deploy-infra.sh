#!/usr/bin/env bash
# Deploys AKS Static Egress Gateway demo scenario end-to-end.
set -euo pipefail

RESOURCE_GROUP="${1:-rg-aks-egress-demo}"
LOCATION="${2:-westus3}"
NAME_PREFIX="${3:-egressdemo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== AKS Static Egress Gateway Demo ==="

# Step 1: Install aks-preview extension and register preview feature
echo -e "\n[1/11] Installing aks-preview extension and registering feature..."
az extension add --name aks-preview --only-show-errors 2>/dev/null || true
az feature register --namespace Microsoft.ContainerService --name StaticEgressGatewayPreview --only-show-errors 2>/dev/null || true
az provider register --namespace Microsoft.ContainerService --only-show-errors

# Step 2: Create resource group
echo -e "\n[2/11] Creating resource group '${RESOURCE_GROUP}'..."
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --only-show-errors -o none

# Step 3: Deploy Bicep (AKS + ACR)
echo -e "\n[3/11] Deploying Bicep template (AKS + ACR)..."
OUTPUTS=$(az deployment group create \
    --resource-group "${RESOURCE_GROUP}" \
    --template-file "${SCRIPT_DIR}/bicep/main.bicep" \
    --parameters namePrefix="${NAME_PREFIX}" location="${LOCATION}" \
    --query "properties.outputs" \
    --output json)

CLUSTER_NAME=$(echo "${OUTPUTS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['clusterName']['value'])")
ACR_NAME=$(echo "${OUTPUTS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['acrName']['value'])")
ACR_LOGIN_SERVER=$(echo "${OUTPUTS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['acrLoginServer']['value'])")

echo "  AKS Cluster: ${CLUSTER_NAME}"
echo "  ACR: ${ACR_NAME} (${ACR_LOGIN_SERVER})"

# Step 4: Enable Static Egress Gateway (requires aks-preview)
echo -e "\n[4/11] Enabling Static Egress Gateway on cluster..."
az aks update -n "${CLUSTER_NAME}" -g "${RESOURCE_GROUP}" --enable-static-egress-gateway --only-show-errors -o none

# Step 5: Add gateway node pool
echo -e "\n[5/11] Adding gateway node pool..."
az aks nodepool add \
    --cluster-name "${CLUSTER_NAME}" \
    --name gateway \
    --resource-group "${RESOURCE_GROUP}" \
    --mode gateway \
    --node-count 2 \
    --gateway-prefix-size 28 \
    --vm-size Standard_D2s_v5 \
    --only-show-errors

# Step 6: Get AKS credentials
echo -e "\n[6/11] Getting AKS credentials..."
az aks get-credentials --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" --overwrite-existing --only-show-errors

# Step 7-8: Build container images in ACR
echo -e "\n[7/11] Building egress-checker image in ACR..."
az acr build \
    --registry "${ACR_NAME}" \
    --image egress-checker:latest \
    "${SCRIPT_DIR}/app/egress-checker" \
    --only-show-errors

echo -e "\n[8/11] Building dashboard image in ACR..."
az acr build \
    --registry "${ACR_NAME}" \
    --image dashboard:latest \
    "${SCRIPT_DIR}/app/dashboard" \
    --only-show-errors

# Step 9: Apply gateway configs
echo -e "\n[9/11] Applying gateway configurations..."
kubectl apply -f "${SCRIPT_DIR}/manifests/gateway-configs.yaml"
echo "  Waiting 60s for gateway IPs to provision..."
sleep 60

# Step 10: Collect network info and deploy workloads
echo -e "\n[10/11] Collecting network info and deploying workloads..."
MC_RG="MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${LOCATION}"
NODE_SUBNET=$(az network vnet list -g "${MC_RG}" --query "[0].subnets[0].addressPrefix" -o tsv 2>/dev/null || echo "10.224.0.0/16")
POD_CIDR=$(az aks show -n "${CLUSTER_NAME}" -g "${RESOURCE_GROUP}" --query "networkProfile.podCidr" -o tsv 2>/dev/null || echo "192.168.0.0/16")
SERVICE_CIDR=$(az aks show -n "${CLUSTER_NAME}" -g "${RESOURCE_GROUP}" --query "networkProfile.serviceCidr" -o tsv 2>/dev/null || echo "10.0.0.0/16")

# Collect egress prefixes
EGRESS_PREFIXES=""
for NS in egress-team-alpha egress-team-bravo egress-team-charlie egress-team-delta egress-team-echo; do
    PREFIX=$(kubectl get staticgatewayconfiguration egress-config -n "${NS}" -o jsonpath='{.status.egressIpPrefix}' 2>/dev/null || true)
    if [ -n "${PREFIX}" ]; then
        [ -n "${EGRESS_PREFIXES}" ] && EGRESS_PREFIXES="${EGRESS_PREFIXES},"
        EGRESS_PREFIXES="${EGRESS_PREFIXES}${NS}=${PREFIX}"
    fi
done

sed "s|__ACR_LOGIN_SERVER__|${ACR_LOGIN_SERVER}|g" "${SCRIPT_DIR}/manifests/workloads.yaml" | kubectl apply -f -
sed -e "s|__ACR_LOGIN_SERVER__|${ACR_LOGIN_SERVER}|g" \
    -e "s|__NODE_SUBNET__|${NODE_SUBNET}|g" \
    -e "s|__POD_CIDR__|${POD_CIDR}|g" \
    -e "s|__SERVICE_CIDR__|${SERVICE_CIDR}|g" \
    -e "s|__EGRESS_PREFIXES__|${EGRESS_PREFIXES}|g" \
    "${SCRIPT_DIR}/manifests/dashboard.yaml" | kubectl apply -f -

# Step 11: Wait for pods and show access instructions
echo -e "\n[11/11] Waiting for pods to be ready..."
sleep 30
kubectl get pods -A -l "app in (egress-checker, dashboard)" --no-headers

echo -e "\n=== Deployment Complete ==="
echo "Access the dashboard with:"
echo "  kubectl port-forward svc/dashboard -n dashboard 8080:80"
echo "  Then open: http://localhost:8080"

echo -e "\nVerify egress IPs:"
echo "  kubectl get staticgatewayconfiguration -A"

echo -e "\nCleanup:"
echo "  az group delete --name ${RESOURCE_GROUP} --yes --no-wait"
