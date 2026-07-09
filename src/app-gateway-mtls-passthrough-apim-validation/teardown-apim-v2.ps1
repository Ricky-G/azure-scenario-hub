#Requires -Version 7.0
<#
.SYNOPSIS
    Removes ONLY the PremiumV2 SKU-parity proof instance (leaves the classic
    scenario stack intact).

.DESCRIPTION
    Deletes the standalone PremiumV2 API Management service created by
    validate-apim-v2.ps1. PremiumV2 is a premium-priced tier, so remove it
    promptly after capturing the evidence. The classic-tier scenario and its
    Key Vault are untouched.
#>
[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'rg-appgw-passthrough-mtls-poc'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$certDir = Join-Path $scriptDir 'certs'

$apimV2Name = $null
$resultsV2 = Join-Path $certDir 'results-v2.json'
if (Test-Path $resultsV2) { $apimV2Name = (Get-Content $resultsV2 -Raw | ConvertFrom-Json).apimName }
if (-not $apimV2Name) {
    $apimV2Name = az deployment group show -g $ResourceGroupName -n 'mtls-apim-v2-proof' --query 'properties.outputs.apimV2Name.value' -o tsv 2>$null
}
if (-not $apimV2Name) {
    Write-Host 'No PremiumV2 instance found (nothing to remove).' -ForegroundColor Yellow
    exit 0
}

Write-Host "==> Deleting v2 API Management instance '$apimV2Name'..." -ForegroundColor Cyan
az apim delete --name $apimV2Name --resource-group $ResourceGroupName --yes --no-wait 2>$null
if ($LASTEXITCODE -ne 0) {
    # Fall back to the generic resource delete if 'az apim delete' is unavailable for v2.
    az resource delete --resource-group $ResourceGroupName --name $apimV2Name `
        --resource-type 'Microsoft.ApiManagement/service' --no-wait 2>$null
}
Write-Host "==> Deletion started for '$apimV2Name' (runs in the background)." -ForegroundColor Green
Write-Host '    The classic-tier scenario stack is untouched.' -ForegroundColor DarkGray
