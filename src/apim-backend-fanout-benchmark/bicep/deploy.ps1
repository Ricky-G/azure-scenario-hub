#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Deploy the APIM Backend Fan-out Benchmark scenario.

.DESCRIPTION
    Subscription-scoped Bicep deployment of:
      - Resource Group
      - Log Analytics + App Insights
      - Mock backend Function App (Premium EP1)
      - APIM-A (shared-backend + rewrite-uri)
      - APIM-B (one-backend-per-API)

.PARAMETER Location
    Azure region (default: australiaeast)

.PARAMETER NamePrefix
    3-8 char prefix used to derive all resource names (default: apimfo)

.PARAMETER PublisherEmail
    APIM publisher email (default: admin@example.com)

.PARAMETER PublisherName
    APIM publisher name (default: Benchmark)

.PARAMETER ApiCount
    Number of APIs to deploy per APIM (default: 10)

.PARAMETER SkipConfirmation
    Skip the deployment confirmation prompt.

.EXAMPLE
    ./deploy.ps1 -Location australiaeast -NamePrefix apimfo
#>

[CmdletBinding()]
param(
    [string]$Location = 'australiaeast',
    [ValidateLength(3, 8)][string]$NamePrefix = 'apimfo',
    [string]$PublisherEmail = 'admin@example.com',
    [string]$PublisherName = 'Benchmark',
    [int]$ApiCount = 10,
    [switch]$SkipConfirmation
)

$ErrorActionPreference = 'Stop'
$ResourceGroupName = "rg-$NamePrefix-benchmark"

Write-Host "`n=== APIM Backend Fan-out Benchmark — Deploy ===" -ForegroundColor Cyan
Write-Host "  Location:          $Location"
Write-Host "  Resource Group:    $ResourceGroupName"
Write-Host "  Name Prefix:       $NamePrefix"
Write-Host "  API Count:         $ApiCount"
Write-Host "  Publisher Email:   $PublisherEmail"
Write-Host ""

# Ensure logged in
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-Host "Subscription: $($account.name) ($($account.id))" -ForegroundColor Green

if (-not $SkipConfirmation) {
    Write-Host "`nDeployment provisions 2 x Premium APIMs (~45 min) and an EP1 Function App." -ForegroundColor Yellow
    Write-Host "Estimated cost: ~`$1,300/month. Run cleanup.ps1 promptly when done." -ForegroundColor Yellow
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -notmatch '^[Yy]$') { exit 0 }
}

$deploymentName = "apim-fanout-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "`nStarting deployment '$deploymentName'..." -ForegroundColor Cyan

az deployment sub create `
    --name $deploymentName `
    --location $Location `
    --template-file (Join-Path $PSScriptRoot 'main.bicep') `
    --parameters `
        location=$Location `
        namePrefix=$NamePrefix `
        resourceGroupName=$ResourceGroupName `
        publisherEmail=$PublisherEmail `
        publisherName=$PublisherName `
        apiCount=$ApiCount `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "Deployment failed." -ForegroundColor Red
    exit 1
}

$outputs = az deployment sub show --name $deploymentName --query properties.outputs --output json | ConvertFrom-Json

Write-Host "`n=== Deployment complete ===" -ForegroundColor Green
Write-Host "  Resource Group:    $($outputs.resourceGroupName.value)"
Write-Host "  Function App:      $($outputs.functionAppName.value)"
Write-Host "  Function Host:     $($outputs.functionAppHostname.value)"
Write-Host "  APIM-A:            $($outputs.apimAName.value)"
Write-Host "    Gateway URL:     $($outputs.apimAGatewayUrl.value)" -ForegroundColor Cyan
Write-Host "  APIM-B:            $($outputs.apimBName.value)"
Write-Host "    Gateway URL:     $($outputs.apimBGatewayUrl.value)" -ForegroundColor Cyan
Write-Host "  App Insights:      $($outputs.appInsightsName.value)"
Write-Host "  Log Analytics:     $($outputs.logAnalyticsWorkspaceName.value)"

Write-Host "`nNext step — publish the Function App code:" -ForegroundColor Yellow
Write-Host "  cd ../backend/MockBackend"
Write-Host "  func azure functionapp publish $($outputs.functionAppName.value)"
Write-Host ""
Write-Host "Then run the benchmark from ../test-harness with Run-Benchmark.ps1." -ForegroundColor Yellow
