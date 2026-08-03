#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$StateFile = (Join-Path $PSScriptRoot '.demo-state.json'),
    [switch]$SkipConfirmation
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $StateFile)) {
    throw "Deployment state not found: $StateFile"
}

$state = Get-Content $StateFile -Raw | ConvertFrom-Json -Depth 100
$scenarioResourceGroupName = $state.parameters.scenarioResourceGroupName

if (-not $SkipConfirmation) {
    $answer = Read-Host "Delete APIM Federated Workspaces resources from '$scenarioResourceGroupName' (y/N)"
    if ($answer -notin @('y', 'Y')) {
        Write-Host 'Cleanup cancelled.' -ForegroundColor Yellow
        return
    }
}

if ($state.parameters.createApimService) {
    az group delete --name $scenarioResourceGroupName --yes --no-wait
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to start resource group deletion.'
    }
} else {
    foreach ($workspaceId in @($state.outputs.dataScienceWorkspaceId.value, $state.outputs.websiteWorkspaceId.value)) {
        az rest --method delete --url "$workspaceId?api-version=2024-05-01" --output none
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to delete workspace: $workspaceId"
        }
    }
    az group delete --name $scenarioResourceGroupName --yes --no-wait
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to start scenario resource group deletion.'
    }
}

Remove-Item $StateFile
Write-Host 'Cleanup started. APIM and workspace gateway deletion can take an extended period.' -ForegroundColor Green
