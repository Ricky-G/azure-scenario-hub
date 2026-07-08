#Requires -Version 7.0
<#
.SYNOPSIS
    Deploys the App Gateway PASSTHROUGH mTLS -> APIM proof-of-concept.

.DESCRIPTION
    1. Ensures the certificate set exists (runs generate-certs.ps1 if needed).
    2. Creates the resource group.
    3. Deploys the Bicep template, injecting the generated certificates and
       trust material as secure parameters.
    4. Saves the deployment outputs to certs/deploy-output.json for the tests.

    NOTE: API Management Developer-tier Internal VNet provisioning takes
    ~30-45 minutes. The deployment polls until complete.

.PARAMETER ResourceGroupName
    Resource group to create/use. Default: rg-appgw-passthrough-mtls-poc

.PARAMETER Location
    Azure region. Default: eastus2

.PARAMETER Force
    Regenerate the certificate set even if a manifest already exists.

.EXAMPLE
    ./deploy-infra.ps1
#>
[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'rg-appgw-passthrough-mtls-poc',
    [string]$Location = 'eastus2',
    [ValidateLength(3, 8)]
    [string]$NamePrefix = 'mtlspoc',
    [string]$PublisherEmail = 'admin@example.com',
    [string]$FrontendHostName = 'api.mtls-poc.local',
    [ValidateSet('pinned', 'chain')]
    [string]$CertValidationMode = 'pinned',
    [string]$DeploymentName = 'mtls-passthrough-poc',
    [switch]$Force,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateFile = Join-Path $scriptDir 'bicep/main.bicep'
$certDir = Join-Path $scriptDir 'certs'
$manifestPath = Join-Path $certDir 'manifest.json'

# ---- 1. Certificates -------------------------------------------------
if ($Force -or -not (Test-Path $manifestPath)) {
    Write-Host '==> Generating certificate set...' -ForegroundColor Cyan
    & (Join-Path $scriptDir 'generate-certs.ps1') -FrontendHostName $FrontendHostName
}
else {
    Write-Host "==> Reusing existing certificate set ($manifestPath)." -ForegroundColor Cyan
}
$m = Get-Content $manifestPath -Raw | ConvertFrom-Json

# ---- 2. Resource group ----------------------------------------------
Write-Host "==> Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Cyan
az group create --name $ResourceGroupName --location $Location --output none

# ---- 3. Build an ARM parameters file --------------------------------
# The frontend server PFX is ~4 KB of base64; passing it inline overflows
# the az.cmd command-line limit, so we write a parameters file instead.
$paramFile = Join-Path $certDir 'deploy.parameters.json'
$paramObj = @{
    '$schema'     = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters    = @{
        namePrefix          = @{ value = $NamePrefix }
        publisherEmail      = @{ value = $PublisherEmail }
        frontendHostName    = @{ value = $FrontendHostName }
        serverCertData      = @{ value = $m.serverCertPfxB64 }
        serverCertPassword  = @{ value = $m.serverCertPassword }
        trustedRootCaDerB64 = @{ value = $m.trustedRootCaDerB64 }
        clientCertAllowlist = @{ value = $m.clientCertAllowlist }
        certValidationMode  = @{ value = $CertValidationMode }
    }
}
$paramObj | ConvertTo-Json -Depth 5 | Set-Content -Path $paramFile -Encoding ascii

if ($ValidateOnly) {
    Write-Host '==> Running preflight validation only...' -ForegroundColor Cyan
    az deployment group validate `
        --resource-group $ResourceGroupName `
        --name $DeploymentName `
        --template-file $templateFile `
        --parameters "@$paramFile" `
        --query 'properties.provisioningState' --output tsv
    if ($LASTEXITCODE -eq 0) { Write-Host '==> VALIDATION PASSED' -ForegroundColor Green }
    else { Write-Host '==> VALIDATION FAILED' -ForegroundColor Red }
    exit $LASTEXITCODE
}

# ---- 4. Deploy (APIM Internal VNet provisioning can take 30-45 min) --
Write-Host '==> Deploying infrastructure. API Management provisioning takes 30-45 minutes; please wait...' -ForegroundColor Cyan
az deployment group create `
    --resource-group $ResourceGroupName `
    --name $DeploymentName `
    --template-file $templateFile `
    --parameters "@$paramFile" `
    --output none
if ($LASTEXITCODE -ne 0) { Write-Error 'Deployment failed.'; exit 1 }

# ---- 4. Capture outputs ---------------------------------------------
$outputs = az deployment group show --resource-group $ResourceGroupName --name $DeploymentName `
    --query properties.outputs --output json | ConvertFrom-Json

$deployOut = [ordered]@{
    resourceGroup     = $ResourceGroupName
    location          = $Location
    appGatewayPublicIp = $outputs.appGatewayPublicIp.value
    appGatewayFqdn    = $outputs.appGatewayFqdn.value
    frontendHostName  = $outputs.frontendHostName.value
    apimName          = $outputs.apimName.value
    apimPrivateIp     = $outputs.apimPrivateIp.value
    keyVaultName      = $outputs.keyVaultName.value
    client1Url        = $outputs.client1Url.value
    client2Url        = $outputs.client2Url.value
}
$deployOut | ConvertTo-Json | Set-Content -Path (Join-Path $certDir 'deploy-output.json') -Encoding ascii

Write-Host ''
Write-Host '==> Deployment complete.' -ForegroundColor Green
Write-Host ("    App Gateway public IP : {0}" -f $deployOut.appGatewayPublicIp)
Write-Host ("    Frontend host (SNI)   : {0}" -f $deployOut.frontendHostName)
Write-Host ("    API Management        : {0}" -f $deployOut.apimName)
Write-Host ("    APIM private IP       : {0}" -f $deployOut.apimPrivateIp)
Write-Host ("    Key Vault             : {0}" -f $deployOut.keyVaultName)
Write-Host ("    Path A URL (client1)  : {0}" -f $deployOut.client1Url)
Write-Host ("    Path B URL (client2)  : {0}" -f $deployOut.client2Url)
Write-Host ''
Write-Host '==> Next: run ./run-tests.ps1 to execute the evidence suite.' -ForegroundColor Yellow
Write-Host '==> REMEMBER: run ./teardown.ps1 when finished to stop billing.' -ForegroundColor Yellow
