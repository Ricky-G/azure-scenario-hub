#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$ApimServiceName = '',
    [string]$ApimResourceGroupName = '',
    [string]$ScenarioResourceGroupName = 'rg-apim-federated-workspaces',
    [string]$Location = 'westus',
    [ValidateSet('Dedicated', 'Shared')]
    [string]$GatewayTopology = 'Shared',
    [string]$NamePrefix = 'apimwsdemo',
    [string]$PublisherEmail = '',
    [string]$PublisherName = 'Contoso',
    [string]$DataScienceTeamPrincipalId = '',
    [string]$WebsiteTeamPrincipalId = '',
    [ValidateSet('Group', 'User', 'ServicePrincipal')]
    [string]$TeamPrincipalType = 'Group',
    [switch]$CreateApimService,
    [switch]$ConfigureGlobalPolicy,
    [switch]$SkipConfirmation
)

$ErrorActionPreference = 'Stop'
$templateFile = Join-Path $PSScriptRoot 'bicep/main.bicep'
$stateFile = Join-Path $PSScriptRoot '.demo-state.json'

function Assert-LastExitCode {
    param([string]$Operation)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE."
    }
}

Write-Host "`nAPIM Federated Workspaces deployment" -ForegroundColor Cyan

$accountJson = az account show --output json 2>$null
Assert-LastExitCode 'Azure login check'
$account = $accountJson | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($PublisherEmail)) {
    $PublisherEmail = $account.user.name -match '@' ? $account.user.name : 'admin@example.com'
}

$configureDemoGlobalPolicy = $ConfigureGlobalPolicy.IsPresent

if ($CreateApimService) {
    if ([string]::IsNullOrWhiteSpace($ApimServiceName)) {
        $ApimServiceName = "apimwsdemo$((New-Guid).ToString('N').Substring(0, 10))"
    }
    $ApimResourceGroupName = $ScenarioResourceGroupName
    $configureDemoGlobalPolicy = $true
} else {
    if ([string]::IsNullOrWhiteSpace($ApimServiceName) -or [string]::IsNullOrWhiteSpace($ApimResourceGroupName)) {
        throw 'Specify -ApimServiceName and -ApimResourceGroupName, or use -CreateApimService for a disposable Premium instance.'
    }

    $serviceJson = az apim show --name $ApimServiceName --resource-group $ApimResourceGroupName --output json
    Assert-LastExitCode 'Existing API Management lookup'
    $service = $serviceJson | ConvertFrom-Json
    if ($service.sku.name -notin @('Premium', 'PremiumV2')) {
        throw "APIM workspaces with Premium workspace gateways require Premium or PremiumV2. '$ApimServiceName' uses '$($service.sku.name)'."
    }
    $Location = $service.location
}

Write-Host "Subscription:       $($account.name)" -ForegroundColor Gray
Write-Host "APIM service:       $ApimServiceName" -ForegroundColor Gray
Write-Host "APIM resource group: $ApimResourceGroupName" -ForegroundColor Gray
Write-Host "Scenario group:     $ScenarioResourceGroupName" -ForegroundColor Gray
Write-Host "Location:           $Location" -ForegroundColor Gray
Write-Host "Gateway topology:   $GatewayTopology" -ForegroundColor Gray
Write-Host "Create APIM:        $($CreateApimService.IsPresent)" -ForegroundColor Gray
Write-Host "Demo global policy: $configureDemoGlobalPolicy" -ForegroundColor Gray

if (-not $SkipConfirmation) {
    Write-Warning 'Workspace gateways incur additional charges and can take up to three hours to provision.'
    $answer = Read-Host 'Continue (y/N)'
    if ($answer -notin @('y', 'Y')) {
        Write-Host 'Deployment cancelled.' -ForegroundColor Yellow
        return
    }
}

Write-Host "`nCompiling Bicep..." -ForegroundColor Yellow
az bicep build --file $templateFile --stdout | Out-Null
Assert-LastExitCode 'Bicep compilation'

$parameters = @(
    "location=$Location"
    "scenarioResourceGroupName=$ScenarioResourceGroupName"
    "apimServiceName=$ApimServiceName"
    "apimResourceGroupName=$ApimResourceGroupName"
    "createApimService=$($CreateApimService.IsPresent.ToString().ToLowerInvariant())"
    "configureGlobalPolicy=$($configureDemoGlobalPolicy.ToString().ToLowerInvariant())"
    "gatewayTopology=$GatewayTopology"
    "namePrefix=$NamePrefix"
    "publisherEmail=$PublisherEmail"
    "publisherName=$PublisherName"
    "dataScienceTeamPrincipalId=$DataScienceTeamPrincipalId"
    "websiteTeamPrincipalId=$WebsiteTeamPrincipalId"
    "teamPrincipalType=$TeamPrincipalType"
)

Write-Host 'Running subscription deployment preflight...' -ForegroundColor Yellow
az deployment sub what-if `
    --name 'apim-federated-workspaces-preflight' `
    --location $Location `
    --template-file $templateFile `
    --parameters @parameters `
    --result-format ResourceIdOnly `
    --output table
Assert-LastExitCode 'Deployment preflight'

$deploymentName = "apim-federated-workspaces-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "`nStarting deployment '$deploymentName'. Keep this terminal open." -ForegroundColor Yellow
$deploymentJson = az deployment sub create `
    --name $deploymentName `
    --location $Location `
    --template-file $templateFile `
    --parameters @parameters `
    --output json
Assert-LastExitCode 'Scenario deployment'
$deployment = $deploymentJson | ConvertFrom-Json -Depth 100

$state = [ordered]@{
    deploymentName = $deploymentName
    subscriptionId = $account.id
    subscriptionName = $account.name
    createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    parameters = [ordered]@{
        createApimService = $CreateApimService.IsPresent
        configureGlobalPolicy = $configureDemoGlobalPolicy
        location = $Location
        gatewayTopology = $GatewayTopology
        scenarioResourceGroupName = $ScenarioResourceGroupName
        apimResourceGroupName = $ApimResourceGroupName
        apimServiceName = $ApimServiceName
    }
    outputs = $deployment.properties.outputs
}
$state | ConvertTo-Json -Depth 100 | Set-Content -Path $stateFile -Encoding utf8

$outputs = $deployment.properties.outputs
Write-Host "`nDeployment completed." -ForegroundColor Green
Write-Host "Data Science API: $($outputs.dataScienceApiUrl.value)" -ForegroundColor Cyan
Write-Host "Website API:      $($outputs.websiteApiUrl.value)" -ForegroundColor Cyan
Write-Host "State file:       $stateFile" -ForegroundColor Gray
Write-Host "`nRun: ./test-workspaces.ps1" -ForegroundColor Yellow
