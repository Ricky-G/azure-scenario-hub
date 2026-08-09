#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$StateFile = (Join-Path $PSScriptRoot '.demo-state.json'),
    [string]$ResourceGroupName = '',
    [string]$AppGatewayName = '',
    [string]$AksClusterName = ''
)

$ErrorActionPreference = 'Stop'

function Assert-LastExitCode {
    param([string]$Operation)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE."
    }
}

if (Test-Path $StateFile) {
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json -Depth 20
    if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { $ResourceGroupName = $state.resourceGroupName }
    if ([string]::IsNullOrWhiteSpace($AppGatewayName)) { $AppGatewayName = $state.outputs.appGatewayName }
    if ([string]::IsNullOrWhiteSpace($AksClusterName)) { $AksClusterName = $state.outputs.aksClusterName }
}

if ([string]::IsNullOrWhiteSpace($ResourceGroupName) -or [string]::IsNullOrWhiteSpace($AppGatewayName) -or [string]::IsNullOrWhiteSpace($AksClusterName)) {
    throw 'Provide a deployment state file or specify ResourceGroupName, AppGatewayName, and AksClusterName.'
}

$subscriptionId = az account show --query id --output tsv
Assert-LastExitCode 'Azure account lookup'
$appGatewayId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/applicationGateways/$AppGatewayName"
$aksClusterId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ContainerService/managedClusters/$AksClusterName"

$appGatewayState = az network application-gateway show --resource-group $ResourceGroupName --name $AppGatewayName --query operationalState --output tsv
Assert-LastExitCode 'Application Gateway state lookup'
if ($appGatewayState -eq 'Stopping') {
    Write-Host "Application Gateway '$AppGatewayName' is stopping; waiting before restart..." -ForegroundColor Yellow
    az resource wait --ids $appGatewayId --api-version 2024-05-01 --custom "properties.operationalState=='Stopped'" --interval 15 --timeout 1800
    Assert-LastExitCode 'Application Gateway stop wait'
    $appGatewayState = 'Stopped'
}
if ($appGatewayState -eq 'Stopped') {
    Write-Host "Starting Application Gateway '$AppGatewayName'..." -ForegroundColor Yellow
    az rest --method post --url "https://management.azure.com${appGatewayId}/start?api-version=2024-05-01" --output none
    Assert-LastExitCode 'Application Gateway start'
} elseif ($appGatewayState -eq 'Starting') {
    Write-Host "Application Gateway '$AppGatewayName' is already starting..." -ForegroundColor Yellow
} elseif ($appGatewayState -ne 'Running') {
    throw "Application Gateway has unexpected operational state '$appGatewayState'."
}
if ($appGatewayState -ne 'Running') {
    az resource wait --ids $appGatewayId --api-version 2024-05-01 --custom "properties.operationalState=='Running'" --interval 15 --timeout 1800
    Assert-LastExitCode 'Application Gateway readiness wait'
}
Write-Host "Application Gateway: Running" -ForegroundColor Green

$aksPowerState = az aks show --resource-group $ResourceGroupName --name $AksClusterName --query powerState.code --output tsv
Assert-LastExitCode 'AKS state lookup'
if ($aksPowerState -eq 'Stopping') {
    Write-Host "AKS cluster '$AksClusterName' is stopping; waiting before restart..." -ForegroundColor Yellow
    az resource wait --ids $aksClusterId --api-version 2024-09-01 --custom "properties.powerState.code=='Stopped'" --interval 15 --timeout 1800
    Assert-LastExitCode 'AKS stop wait'
    $aksPowerState = 'Stopped'
}
if ($aksPowerState -eq 'Stopped') {
    Write-Host "Starting AKS cluster '$AksClusterName'..." -ForegroundColor Yellow
    az rest --method post --url "https://management.azure.com${aksClusterId}/start?api-version=2024-09-01" --output none
    Assert-LastExitCode 'AKS start'
} elseif ($aksPowerState -eq 'Starting') {
    Write-Host "AKS cluster '$AksClusterName' is already starting..." -ForegroundColor Yellow
} elseif ($aksPowerState -ne 'Running') {
    throw "AKS has unexpected power state '$aksPowerState'."
}
if ($aksPowerState -ne 'Running') {
    az resource wait --ids $aksClusterId --api-version 2024-09-01 --custom "properties.powerState.code=='Running' && properties.provisioningState=='Succeeded'" --interval 15 --timeout 1800
    Assert-LastExitCode 'AKS readiness wait'
}
Write-Host 'AKS: Running' -ForegroundColor Green