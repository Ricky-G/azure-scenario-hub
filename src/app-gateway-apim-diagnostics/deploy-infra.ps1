#Requires -Version 7.0
<#
.SYNOPSIS
    Deploys the Application Gateway + API Management diagnostics scenario.

.DESCRIPTION
    Creates a resource group and deploys a Log Analytics Workspace, a virtual
    network, API Management (with a Hello World API), and an Application Gateway
    (WAF_v2) that routes public traffic to APIM. Full diagnostic settings on
    both the Application Gateway and APIM stream to the Log Analytics Workspace.

.PARAMETER ResourceGroupName
    Name of the resource group to create/use. Default: rg-app-gateway-apim-diagnostics

.PARAMETER Location
    Azure region. Default: eastus2

.PARAMETER NamePrefix
    Short prefix (3-8 chars) applied to all resource names. Default: agwdiag

.PARAMETER PublisherEmail
    Publisher email for API Management notifications. Default: admin@example.com

.EXAMPLE
    ./deploy-infra.ps1 -PublisherEmail "you@contoso.com"
#>
[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'rg-app-gateway-apim-diagnostics',
    [string]$Location = 'eastus2',
    [ValidateLength(3, 8)]
    [string]$NamePrefix = 'agwdiag',
    [string]$PublisherEmail = 'admin@example.com'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateFile = Join-Path $scriptDir 'bicep/main.bicep'

Write-Host "==> Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Cyan
az group create --name $ResourceGroupName --location $Location --output none

Write-Host "==> Deploying infrastructure (APIM provisioning can take 30-45 minutes)..." -ForegroundColor Cyan
az deployment group create `
    --resource-group $ResourceGroupName `
    --name 'appgw-apim-diag-deploy' `
    --template-file $templateFile `
    --parameters namePrefix=$NamePrefix publisherEmail=$PublisherEmail `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error 'Deployment failed.'
    exit 1
}

Write-Host "==> Deployment complete. Outputs:" -ForegroundColor Green
$outputs = az deployment group show `
    --resource-group $ResourceGroupName `
    --name 'appgw-apim-diag-deploy' `
    --query properties.outputs `
    --output json | ConvertFrom-Json

$helloUrl = $outputs.helloWorldUrlViaAppGateway.value
Write-Host ("    Log Analytics Workspace : {0}" -f $outputs.logAnalyticsWorkspaceName.value)
Write-Host ("    API Management          : {0}" -f $outputs.apimName.value)
Write-Host ("    App Gateway Public IP   : {0}" -f $outputs.appGatewayPublicIp.value)
Write-Host ("    Hello World URL         : {0}" -f $helloUrl)

Write-Host "`n==> Testing the end-to-end route..." -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri $helloUrl -Method Get -TimeoutSec 30
    Write-Host "    Success! Response:" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 5
}
catch {
    Write-Warning "    Initial call failed (the Application Gateway backend can take a few minutes to report healthy). Try again shortly:"
    Write-Host "    curl $helloUrl"
}
