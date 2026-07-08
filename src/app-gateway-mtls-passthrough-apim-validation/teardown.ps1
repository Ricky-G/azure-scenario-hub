#Requires -Version 7.0
<#
.SYNOPSIS
    Tears down the mTLS passthrough POC to stop billing.

.DESCRIPTION
    Deletes the resource group (all resources) and optionally removes the
    locally generated certificate material.

.PARAMETER ResourceGroupName
    Resource group to delete. Default: rg-appgw-passthrough-mtls-poc

.PARAMETER KeepCerts
    Keep the local ./certs directory (default removes it).

.PARAMETER Yes
    Skip the confirmation prompt.
#>
[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'rg-appgw-passthrough-mtls-poc',
    [switch]$KeepCerts,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $Yes) {
    $confirm = Read-Host "This will DELETE resource group '$ResourceGroupName' and all its resources. Type 'yes' to continue"
    if ($confirm -ne 'yes') { Write-Host 'Aborted.'; exit 0 }
}

Write-Host "==> Deleting resource group '$ResourceGroupName' (runs in background)..." -ForegroundColor Cyan
az group delete --name $ResourceGroupName --yes --no-wait
Write-Host '==> Deletion started. It continues server-side; verify in the portal or with:' -ForegroundColor Green
Write-Host "    az group show -n $ResourceGroupName"

# Key Vault uses soft-delete (7 days). Purge to fully reclaim the name if needed:
Write-Host ''
Write-Host '==> NOTE: Key Vault is soft-deleted for 7 days. To purge immediately:' -ForegroundColor Yellow
Write-Host '    az keyvault purge --name <keyVaultName>'

if (-not $KeepCerts) {
    $certDir = Join-Path $scriptDir 'certs'
    if (Test-Path $certDir) {
        Remove-Item $certDir -Recurse -Force
        Write-Host '==> Removed local ./certs directory.' -ForegroundColor Green
    }
}
