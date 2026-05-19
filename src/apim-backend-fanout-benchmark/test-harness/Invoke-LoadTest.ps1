#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Run a single k6 load test against one APIM gateway and emit JSON + NDJSON.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GatewayUrl,
    [Parameter(Mandatory)][ValidateSet('A', 'B')][string]$Side,
    [Parameter(Mandatory)][string]$OutDir
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    throw "k6 is not on PATH. Install: https://k6.io/docs/get-started/installation/"
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$scriptName = if ($Side -eq 'A') { 'apim-a-shared.js' } else { 'apim-b-perapi.js' }
$envVar = if ($Side -eq 'A') { "APIM_A_URL=$GatewayUrl" } else { "APIM_B_URL=$GatewayUrl" }
$scriptPath = Join-Path $PSScriptRoot "k6/$scriptName"
$summaryPath = Join-Path $OutDir "k6-$($Side.ToLower()).json"
$rawPath = Join-Path $OutDir "k6-$($Side.ToLower()).ndjson"

Write-Host "Running k6 for APIM-$Side against $GatewayUrl ..." -ForegroundColor Cyan

# --summary-export gives us aggregate metrics; --out json gives raw NDJSON.
& k6 run `
    --env $envVar `
    --summary-export $summaryPath `
    --out "json=$rawPath" `
    $scriptPath

if ($LASTEXITCODE -ne 0) {
    throw "k6 exited with code $LASTEXITCODE"
}

Write-Host "Wrote $summaryPath" -ForegroundColor Green
Write-Host "Wrote $rawPath"     -ForegroundColor Green
