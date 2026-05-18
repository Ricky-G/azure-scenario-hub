#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Deploy the AI Gateway scenario.

.DESCRIPTION
    Compiles main.bicep and deploys it at the subscription scope. Creates the
    AI Gateway resource group, APIM, Application Insights, Log Analytics, the
    AOAI API on APIM and grants APIM's MI access to the existing Foundry
    account.

.EXAMPLE
    .\deploy-infra.ps1 `
        -Location swedencentral `
        -ResourceGroupName rg-ai-gateway-demo `
        -FoundryResourceGroupName <foundry-resource-group> `
        -FoundryAccountName <your-foundry-account> `
        -OpenAiEndpoint 'https://<your-foundry-account>.cognitiveservices.azure.com/'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = 'rg-ai-gateway-demo',

    [Parameter(Mandatory = $false)]
    [ValidateLength(3, 8)]
    [string]$NamePrefix = 'aigw',

    [Parameter(Mandatory = $false)]
    [string]$PublisherEmail = 'admin@contoso.com',

    [Parameter(Mandatory = $false)]
    [string]$PublisherName = 'Contoso',

    [Parameter(Mandatory = $true)]
    [string]$FoundryResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$FoundryAccountName,

    [Parameter(Mandatory = $true)]
    [string]$OpenAiEndpoint,

    [Parameter(Mandatory = $false)]
    [string]$OpenAiApiVersion = '2024-10-21',

    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = "ai-gateway-$(Get-Date -Format 'yyyyMMddHHmmss')"
)

$ErrorActionPreference = 'Stop'
$bicepDir = Join-Path $PSScriptRoot 'bicep'
$mainBicep = Join-Path $bicepDir 'main.bicep'

if (-not (Test-Path $mainBicep)) {
    throw "main.bicep not found at $mainBicep"
}

Write-Host "==> Validating Azure CLI session..." -ForegroundColor Cyan
$account = az account show -o json | ConvertFrom-Json
Write-Host "    Subscription : $($account.name) ($($account.id))" -ForegroundColor Gray
Write-Host "    User         : $($account.user.name)" -ForegroundColor Gray

Write-Host "==> Submitting deployment '$DeploymentName' at subscription scope..." -ForegroundColor Cyan
$deployment = az deployment sub create `
    --name $DeploymentName `
    --location $Location `
    --template-file $mainBicep `
    --parameters `
        location=$Location `
        resourceGroupName=$ResourceGroupName `
        namePrefix=$NamePrefix `
        publisherEmail=$PublisherEmail `
        publisherName=$PublisherName `
        foundryResourceGroupName=$FoundryResourceGroupName `
        foundryAccountName=$FoundryAccountName `
        openAiEndpoint=$OpenAiEndpoint `
        openAiApiVersion=$OpenAiApiVersion `
    -o json | ConvertFrom-Json

if (-not $deployment) {
    throw "Deployment failed."
}

$outputs = $deployment.properties.outputs

Write-Host ""
Write-Host "==> Deployment succeeded" -ForegroundColor Green
Write-Host "    Resource Group : $($outputs.resourceGroupName.value)"
Write-Host "    APIM           : $($outputs.apimName.value)"
Write-Host "    APIM Gateway   : $($outputs.apimGatewayUrl.value)"
Write-Host "    App Insights   : $($outputs.appInsightsName.value)"
Write-Host "    Log Analytics  : $($outputs.workspaceName.value)"
Write-Host ""
Write-Host "==> Demo subscriptions" -ForegroundColor Green
$subId = az account show --query id -o tsv
foreach ($pid in $outputs.productIds.value) {
    $secretsUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$($outputs.resourceGroupName.value)/providers/Microsoft.ApiManagement/service/$($outputs.apimName.value)/subscriptions/$pid-demo-sub/listSecrets?api-version=2023-05-01-preview"
    $secrets = az rest --method post --url $secretsUrl -o json 2>$null | ConvertFrom-Json
    if ($null -ne $secrets -and $secrets.primaryKey) {
        Write-Host "    $($pid.PadRight(28)) primaryKey: $($secrets.primaryKey.Substring(0,8))********"
    }
}

Write-Host ""
Write-Host "Next: run .\test-harness\Invoke-Demo.ps1 to drive traffic." -ForegroundColor Yellow
