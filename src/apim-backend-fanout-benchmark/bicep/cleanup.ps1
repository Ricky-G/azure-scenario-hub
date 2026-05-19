#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Delete the APIM Backend Fan-out Benchmark resource group.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'rg-apimfo-benchmark',
    [switch]$SkipConfirmation
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Cleanup ===" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Yellow

$exists = az group exists --name $ResourceGroupName | ConvertFrom-Json
if (-not $exists) {
    Write-Host "Resource group '$ResourceGroupName' not found. Nothing to do." -ForegroundColor Yellow
    exit 0
}

if (-not $SkipConfirmation) {
    Write-Host "This will DELETE all resources in '$ResourceGroupName'." -ForegroundColor Red
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -notmatch '^[Yy]$') { exit 0 }
}

Write-Host "Deleting resource group (this runs async)..." -ForegroundColor Yellow
az group delete --name $ResourceGroupName --yes --no-wait
Write-Host "Delete submitted. APIM Premium soft-delete takes ~45 min to complete." -ForegroundColor Green
