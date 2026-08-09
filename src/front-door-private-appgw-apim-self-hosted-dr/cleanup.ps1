#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$StateFile = (Join-Path $PSScriptRoot '.demo-state.json'),
    [string]$ResourceGroupName = '',
    [switch]$SkipConfirmation
)

$ErrorActionPreference = 'Stop'

if (Test-Path $StateFile) {
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json -Depth 20
    if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
        $ResourceGroupName = $state.resourceGroupName
    }
}

if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    throw 'Specify -ResourceGroupName or provide a valid deployment state file.'
}

if (-not $SkipConfirmation) {
    $answer = Read-Host "Delete all scenario resources in '$ResourceGroupName' (y/N)"
    if ($answer -notin @('y', 'Y')) {
        Write-Host 'Cleanup cancelled.' -ForegroundColor Yellow
        return
    }
}

az group delete --name $ResourceGroupName --yes --no-wait
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to start resource group deletion.'
}

if (Test-Path $StateFile) {
    Remove-Item $StateFile -Force
}
Write-Host "Cleanup started for '$ResourceGroupName'." -ForegroundColor Green