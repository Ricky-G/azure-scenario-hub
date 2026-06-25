#!/usr/bin/env pwsh
# =============================================================================
# APP TEAM deploy script (PowerShell)
# =============================================================================
# Simulates the app team deploying child resources via Bicep into the
# platform-owned resources, OUT OF BAND from the platform Terraform workspace.
#
# It reads the platform resource names straight from the Terraform outputs, then
# runs `az deployment group create` against the same resource group.
# =============================================================================

$ErrorActionPreference = 'Stop'

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$terraformDir = Join-Path (Join-Path $scriptDir '..') 'terraform'
$bicepFile    = Join-Path $scriptDir 'main.bicep'

Write-Host 'Reading platform resource names from Terraform outputs...' -ForegroundColor Cyan
Push-Location $terraformDir
try {
    $tf = terraform output -json | ConvertFrom-Json
}
finally {
    Pop-Location
}

$rg      = $tf.resource_group_name.value
$storage = $tf.storage_account_name.value
$cosmos  = $tf.cosmos_account_name.value
$foundry = $tf.foundry_account_name.value

Write-Host "  Resource group : $rg"
Write-Host "  Storage account: $storage"
Write-Host "  Cosmos account : $cosmos"
Write-Host "  Foundry account: $foundry"

Write-Host 'Deploying app-team child resources (Bicep)...' -ForegroundColor Cyan
az deployment group create `
    --resource-group $rg `
    --template-file $bicepFile `
    --parameters `
        storageAccountName=$storage `
        cosmosAccountName=$cosmos `
        foundryAccountName=$foundry `
    --query 'properties.provisioningState' -o tsv

Write-Host ''
Write-Host 'App-team changes deployed.' -ForegroundColor Green
Write-Host 'Now run ../scripts/check-drift.ps1 to see whether Terraform notices.' -ForegroundColor Green
