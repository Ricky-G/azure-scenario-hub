#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Orchestrate the full benchmark: smoke → warm-up → APIM-A → cool-down → APIM-B → report.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [switch]$SkipSmokeTest,
    [switch]$SkipReport
)

$ErrorActionPreference = 'Stop'
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultsDir = Join-Path $PSScriptRoot "results/$timestamp"
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

Write-Host "`n=== APIM Backend Fan-out Benchmark ===" -ForegroundColor Cyan
Write-Host "  Timestamp:   $timestamp"
Write-Host "  Results dir: $resultsDir"
Write-Host "  APIM-A:      $($config.apimAGatewayUrl)"
Write-Host "  APIM-B:      $($config.apimBGatewayUrl)"
Write-Host ""

# 1. Smoke test
if (-not $SkipSmokeTest) {
    & (Join-Path $PSScriptRoot 'Smoke-Test.ps1') -ConfigPath $ConfigPath
}

# 2. Run APIM-A
Write-Host "`n>>> Stage: APIM-A (shared backend + rewrite-uri)" -ForegroundColor Yellow
$startA = Get-Date
& (Join-Path $PSScriptRoot 'Invoke-LoadTest.ps1') `
    -GatewayUrl $config.apimAGatewayUrl -Side 'A' -OutDir $resultsDir
$endA = Get-Date

# 3. Cool-down
Write-Host "`nCooling down for 60s before APIM-B..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

# 4. Run APIM-B
Write-Host "`n>>> Stage: APIM-B (one backend per API)" -ForegroundColor Yellow
$startB = Get-Date
& (Join-Path $PSScriptRoot 'Invoke-LoadTest.ps1') `
    -GatewayUrl $config.apimBGatewayUrl -Side 'B' -OutDir $resultsDir
$endB = Get-Date

# Persist run metadata
@{
    timestampUtc      = (Get-Date).ToUniversalTime().ToString('o')
    apimAGatewayUrl   = $config.apimAGatewayUrl
    apimBGatewayUrl   = $config.apimBGatewayUrl
    apimAStartUtc     = $startA.ToUniversalTime().ToString('o')
    apimAEndUtc       = $endA.ToUniversalTime().ToString('o')
    apimBStartUtc     = $startB.ToUniversalTime().ToString('o')
    apimBEndUtc       = $endB.ToUniversalTime().ToString('o')
    appInsightsName   = $config.appInsightsName
    resourceGroupName = $config.resourceGroupName
    subscriptionId    = $config.subscriptionId
    apiCount          = $config.apiCount
} | ConvertTo-Json | Set-Content (Join-Path $resultsDir 'run.json')

# 5. Wait for App Insights ingestion
if (-not $SkipReport) {
    Write-Host "`nWaiting 120s for App Insights ingestion..." -ForegroundColor Yellow
    Start-Sleep -Seconds 120

    # 6. Build report
    & (Join-Path $PSScriptRoot 'Build-Report.ps1') -ResultsDir $resultsDir -ConfigPath $ConfigPath
}

Write-Host "`n=== Benchmark complete ===" -ForegroundColor Green
Write-Host "Results: $resultsDir"
