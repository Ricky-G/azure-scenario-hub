<#
.SYNOPSIS
    Deploys AKS Static Egress Gateway demo scenario end-to-end.

.DESCRIPTION
    Creates AKS cluster with Static Egress Gateway, ACR, builds container images,
    deploys Kubernetes manifests, and prints the dashboard URL.

.PARAMETER ResourceGroupName
    Name of the Azure resource group. Default: rg-aks-egress-demo

.PARAMETER Location
    Azure region. Default: westus3

.PARAMETER NamePrefix
    Short prefix for resource names. Default: egressdemo
#>
param(
    [string]$ResourceGroupName = "rg-aks-egress-demo",
    [string]$Location = "westus3",
    [string]$NamePrefix = "egressdemo"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== AKS Static Egress Gateway Demo ===" -ForegroundColor Cyan

# Step 1: Install aks-preview extension and register preview feature
Write-Host "`n[1/11] Installing aks-preview extension and registering feature..." -ForegroundColor Yellow
az extension add --name aks-preview --only-show-errors 2>$null
az feature register --namespace Microsoft.ContainerService --name StaticEgressGatewayPreview --only-show-errors 2>$null
az provider register --namespace Microsoft.ContainerService --only-show-errors

# Step 2: Create resource group
Write-Host "`n[2/11] Creating resource group '$ResourceGroupName'..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location --only-show-errors | Out-Null

# Step 3: Deploy Bicep (AKS + ACR)
Write-Host "`n[3/11] Deploying Bicep template (AKS + ACR)..." -ForegroundColor Yellow
$deployment = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file "$ScriptDir/bicep/main.bicep" `
    --parameters namePrefix=$NamePrefix location=$Location `
    --query "properties.outputs" `
    --output json | ConvertFrom-Json

$clusterName = $deployment.clusterName.value
$acrName = $deployment.acrName.value
$acrLoginServer = $deployment.acrLoginServer.value

Write-Host "  AKS Cluster: $clusterName" -ForegroundColor Green
Write-Host "  ACR: $acrName ($acrLoginServer)" -ForegroundColor Green

# Step 4: Enable Static Egress Gateway on the cluster (requires aks-preview)
Write-Host "`n[4/11] Enabling Static Egress Gateway on cluster..." -ForegroundColor Yellow
az aks update -n $clusterName -g $ResourceGroupName --enable-static-egress-gateway --only-show-errors | Out-Null

# Step 5: Add gateway node pool
Write-Host "`n[5/11] Adding gateway node pool..." -ForegroundColor Yellow
az aks nodepool add `
    --cluster-name $clusterName `
    --name gateway `
    --resource-group $ResourceGroupName `
    --mode gateway `
    --node-count 2 `
    --gateway-prefix-size 28 `
    --vm-size Standard_D2s_v5 `
    --only-show-errors

# Step 6: Get AKS credentials
Write-Host "`n[6/11] Getting AKS credentials..." -ForegroundColor Yellow
az aks get-credentials --resource-group $ResourceGroupName --name $clusterName --overwrite-existing --only-show-errors

# Step 7-8: Build container images in ACR
Write-Host "`n[7/11] Building egress-checker image in ACR..." -ForegroundColor Yellow
az acr build `
    --registry $acrName `
    --image egress-checker:latest `
    "$ScriptDir/app/egress-checker" `
    --only-show-errors

Write-Host "`n[8/11] Building dashboard image in ACR..." -ForegroundColor Yellow
az acr build `
    --registry $acrName `
    --image dashboard:latest `
    "$ScriptDir/app/dashboard" `
    --only-show-errors

# Step 9: Apply gateway configs (namespaces + StaticGatewayConfiguration)
Write-Host "`n[9/11] Applying gateway configurations..." -ForegroundColor Yellow
kubectl apply -f "$ScriptDir/manifests/gateway-configs.yaml"

Write-Host "  Waiting 60s for gateway IPs to provision..." -ForegroundColor Gray
Start-Sleep -Seconds 60

# Step 10: Collect cluster network info and egress prefixes for dashboard
Write-Host "`n[10/11] Collecting network info and deploying workloads..." -ForegroundColor Yellow
$mcRg = "MC_${ResourceGroupName}_${clusterName}_${Location}"
$nodeSubnet = az network vnet list -g $mcRg --query "[0].subnets[0].addressPrefix" -o tsv 2>$null
if (-not $nodeSubnet) { $nodeSubnet = "10.224.0.0/16" }
$podCidr = az aks show -n $clusterName -g $ResourceGroupName --query "networkProfile.podCidr" -o tsv 2>$null
if (-not $podCidr) { $podCidr = "192.168.0.0/16" }
$serviceCidr = az aks show -n $clusterName -g $ResourceGroupName --query "networkProfile.serviceCidr" -o tsv 2>$null
if (-not $serviceCidr) { $serviceCidr = "10.0.0.0/16" }

# Collect egress prefixes from StaticGatewayConfiguration status
$namespaces = @("egress-team-alpha","egress-team-bravo","egress-team-charlie","egress-team-delta","egress-team-echo")
$prefixParts = @()
foreach ($ns in $namespaces) {
    $prefix = kubectl get staticgatewayconfiguration egress-config -n $ns -o jsonpath='{.status.egressIpPrefix}' 2>$null
    if ($prefix) { $prefixParts += "${ns}=${prefix}" }
}
$egressPrefixes = $prefixParts -join ","

# Deploy workloads
$workloadsContent = Get-Content "$ScriptDir/manifests/workloads.yaml" -Raw
$workloadsContent = $workloadsContent -replace "__ACR_LOGIN_SERVER__", $acrLoginServer
$workloadsContent | kubectl apply -f -

# Deploy dashboard with network context
$dashboardContent = Get-Content "$ScriptDir/manifests/dashboard.yaml" -Raw
$dashboardContent = $dashboardContent -replace "__ACR_LOGIN_SERVER__", $acrLoginServer
$dashboardContent = $dashboardContent -replace "__NODE_SUBNET__", $nodeSubnet
$dashboardContent = $dashboardContent -replace "__POD_CIDR__", $podCidr
$dashboardContent = $dashboardContent -replace "__SERVICE_CIDR__", $serviceCidr
$dashboardContent = $dashboardContent -replace "__EGRESS_PREFIXES__", $egressPrefixes
$dashboardContent | kubectl apply -f -

# Step 11: Wait for pods and show access instructions
Write-Host "`n[11/11] Waiting for pods to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 30
kubectl get pods -A -l "app in (egress-checker, dashboard)" --no-headers

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan
Write-Host "Access the dashboard with:" -ForegroundColor Green
Write-Host "  kubectl port-forward svc/dashboard -n dashboard 8080:80" -ForegroundColor White
Write-Host "  Then open: http://localhost:8080" -ForegroundColor White

Write-Host "`nVerify egress IPs:" -ForegroundColor Green
Write-Host "  kubectl get staticgatewayconfiguration -A" -ForegroundColor Gray

Write-Host "`nCleanup:" -ForegroundColor Yellow
Write-Host "  az group delete --name $ResourceGroupName --yes --no-wait" -ForegroundColor Gray
