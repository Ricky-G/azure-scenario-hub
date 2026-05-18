#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Tear down the AI Gateway demo resource group.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = 'rg-ai-gateway-demo',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

if (-not $Force) {
    $confirm = Read-Host "This will DELETE resource group '$ResourceGroupName' and all resources within (incl. APIM soft-deleted). Type 'DELETE' to continue"
    if ($confirm -ne 'DELETE') {
        Write-Host "Aborted." -ForegroundColor Yellow
        return
    }
}

Write-Host "==> Deleting resource group $ResourceGroupName ..." -ForegroundColor Yellow
az group delete --name $ResourceGroupName --yes --no-wait
Write-Host "Delete request submitted. APIM may take 30-45 min to fully purge." -ForegroundColor Yellow
Write-Host "If you want to recreate APIM with the same name immediately, also purge the soft-deleted instance:" -ForegroundColor Yellow
Write-Host "    az apim deletedservice list -o table" -ForegroundColor Gray
Write-Host "    az apim deletedservice purge --service-name <name> --location <region>" -ForegroundColor Gray
