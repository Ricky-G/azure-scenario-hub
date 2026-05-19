#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Aggregate k6 results + App Insights data into REPORT.md.

.DESCRIPTION
    Reads:
      - <ResultsDir>/k6-a.json, k6-b.json (k6 summary-export)
      - <ResultsDir>/run.json (metadata written by Run-Benchmark.ps1)
    Queries App Insights for BackendTime / ClientTime by APIM service.
    Writes <ResultsDir>/REPORT.md using docs/report-template.md.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResultsDir,
    [Parameter(Mandatory)][string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$run    = Get-Content (Join-Path $ResultsDir 'run.json') -Raw | ConvertFrom-Json
$summaryA = Get-Content (Join-Path $ResultsDir 'k6-a.json') -Raw | ConvertFrom-Json
$summaryB = Get-Content (Join-Path $ResultsDir 'k6-b.json') -Raw | ConvertFrom-Json

function Get-Metric { param($summary, $name, $stat)
    $m = $summary.metrics.$name
    if (-not $m) { return 0 }
    return [math]::Round($m.$stat, 2)
}

# Latencies in ms (k6 uses ms for http_req_duration)
$aP50 = Get-Metric $summaryA 'http_req_duration' 'med'
$aP95 = Get-Metric $summaryA 'http_req_duration' 'p(95)'
$aP99 = Get-Metric $summaryA 'http_req_duration' 'p(99)'
$aMax = Get-Metric $summaryA 'http_req_duration' 'max'
$bP50 = Get-Metric $summaryB 'http_req_duration' 'med'
$bP95 = Get-Metric $summaryB 'http_req_duration' 'p(95)'
$bP99 = Get-Metric $summaryB 'http_req_duration' 'p(99)'
$bMax = Get-Metric $summaryB 'http_req_duration' 'max'

$aReqs = [int]$summaryA.metrics.http_reqs.count
$bReqs = [int]$summaryB.metrics.http_reqs.count
$aRps  = Get-Metric $summaryA 'http_reqs' 'rate'
$bRps  = Get-Metric $summaryB 'http_reqs' 'rate'
$aErr  = [math]::Round(($summaryA.metrics.http_req_failed.value * 100), 3)
$bErr  = [math]::Round(($summaryB.metrics.http_req_failed.value * 100), 3)

# Query App Insights for APIM BackendTime / ClientTime if configured
$aBackend = 'n/a'; $bBackend = 'n/a'; $aOverhead = 'n/a'; $bOverhead = 'n/a'
$instanceIds = 'n/a'
$appInsightsResults = ''

if ($config.appInsightsName -and $config.resourceGroupName) {
    Write-Host "Querying App Insights..." -ForegroundColor Cyan
    $kqlDir = Join-Path $PSScriptRoot 'kql'
    $kql = (Get-Content (Join-Path $kqlDir 'apim-backend-time.kql') -Raw)
    try {
        $appId = az monitor app-insights component show `
            --app $config.appInsightsName `
            --resource-group $config.resourceGroupName `
            --query appId -o tsv

        $resJson = az monitor app-insights query `
            --app $appId `
            --analytics-query $kql `
            --offset 2h `
            -o json | ConvertFrom-Json

        if ($resJson.tables -and $resJson.tables[0].rows.Count -gt 0) {
            $appInsightsResults = ($resJson.tables[0].rows | ConvertTo-Json -Depth 10)
            $appInsightsResults | Set-Content (Join-Path $ResultsDir 'appinsights.json')

            foreach ($row in $resJson.tables[0].rows) {
                $svc = [string]$row[0]
                $be  = [double]$row[1]
                $ct  = [double]$row[2]
                if ($svc -like "*$($run.apimAGatewayUrl.Split('.')[0].Split('/')[-1])*") {
                    $aBackend = [math]::Round($be, 2); $aOverhead = [math]::Round($ct - $be, 2)
                } elseif ($svc -like "*$($run.apimBGatewayUrl.Split('.')[0].Split('/')[-1])*") {
                    $bBackend = [math]::Round($be, 2); $bOverhead = [math]::Round($ct - $be, 2)
                }
            }
        }
    } catch {
        Write-Warning "App Insights query failed: $($_.Exception.Message)"
    }
}

function Delta { param($a, $b)
    if ($a -eq 'n/a' -or $b -eq 'n/a') { return 'n/a' }
    return [math]::Round($a - $b, 2)
}
function DeltaPct { param($a, $b)
    if ($a -eq 'n/a' -or $b -eq 'n/a' -or $b -eq 0) { return 'n/a' }
    return [math]::Round((($a - $b) / $b) * 100, 2)
}

# Verdict
$thresholdsBroken = @()
if ([math]::Abs($aP95 - $bP95) -gt 3) { $thresholdsBroken += "Δ p95 = $([math]::Abs($aP95 - $bP95)) ms (> 3 ms)" }
if ($bRps -gt 0 -and [math]::Abs(($aRps - $bRps) / $bRps * 100) -gt 2) {
    $thresholdsBroken += "Δ throughput = $([math]::Round((($aRps - $bRps) / $bRps) * 100, 2))% (> 2%)"
}
if ([math]::Abs($aErr - $bErr) -gt 0.1) { $thresholdsBroken += "Δ error rate = $([math]::Round([math]::Abs($aErr - $bErr), 3))% (> 0.1%)" }

if ($thresholdsBroken.Count -eq 0) {
    $verdict = 'No measurable penalty. Shared-backend + rewrite-uri pattern is performance-equivalent.'
    $verdictDetail = 'All three thresholds (Δ p95 ≤ 3 ms, Δ throughput ≤ 2 %, Δ error rate ≤ 0.1 %) satisfied.'
} else {
    $verdict = 'Measurable penalty detected.'
    $verdictDetail = "Thresholds exceeded:`n`n- " + ($thresholdsBroken -join "`n- ")
}

# Render report
$report = @"
# APIM Backend Fan-out Benchmark — Report

## Run metadata

| Field | Value |
|---|---|
| Run timestamp (UTC) | $($run.timestampUtc) |
| Region | (see deploy parameters) |
| APIM-A SKU / units | Premium / 1 |
| APIM-B SKU / units | Premium / 1 |
| Backend SKU | Premium EP1 (alwaysReady=1) |
| Backend artificial delay | 5 ms |
| k6 version | $(if (Get-Command k6 -ErrorAction SilentlyContinue) { (k6 version) -replace '\r?\n', ' ' } else { 'n/a' }) |
| VU profile | 30s @ 10 warm-up → 5m @ 50 → 5m @ 100 → 5m @ 200 |
| Total requests (A) | $aReqs |
| Total requests (B) | $bReqs |
| API count | $($run.apiCount) |

## Headline comparison

| Metric | APIM-A (shared + rewrite) | APIM-B (per-API) | Δ | Δ % |
|---|---:|---:|---:|---:|
| p50 latency (ms) | $aP50 | $bP50 | $(Delta $aP50 $bP50) | $(DeltaPct $aP50 $bP50) |
| p95 latency (ms) | $aP95 | $bP95 | $(Delta $aP95 $bP95) | $(DeltaPct $aP95 $bP95) |
| p99 latency (ms) | $aP99 | $bP99 | $(Delta $aP99 $bP99) | $(DeltaPct $aP99 $bP99) |
| Max latency (ms) | $aMax | $bMax | $(Delta $aMax $bMax) | $(DeltaPct $aMax $bMax) |
| Throughput (req/s) | $aRps | $bRps | $(Delta $aRps $bRps) | $(DeltaPct $aRps $bRps) |
| Error rate (%) | $aErr | $bErr | $(Delta $aErr $bErr) | — |
| Avg APIM ``BackendTime`` (ms) | $aBackend | $bBackend | $(Delta $aBackend $bBackend) | $(DeltaPct $aBackend $bBackend) |
| Avg APIM overhead ``ClientTime − BackendTime`` (ms) | $aOverhead | $bOverhead | $(Delta $aOverhead $bOverhead) | $(DeltaPct $aOverhead $bOverhead) |

## Verdict

**$verdict**

$verdictDetail

Thresholds applied:

- ``|Δ p95 latency|`` ≤ **3 ms**
- ``|Δ throughput|`` ≤ **2 %**
- ``|Δ error rate|`` ≤ **0.1 %**

## Raw artifacts

- k6 JSON summary (APIM-A): [``./k6-a.json``](./k6-a.json)
- k6 JSON summary (APIM-B): [``./k6-b.json``](./k6-b.json)
- k6 raw NDJSON (APIM-A): [``./k6-a.ndjson``](./k6-a.ndjson)
- k6 raw NDJSON (APIM-B): [``./k6-b.ndjson``](./k6-b.ndjson)
- App Insights query results: [``./appinsights.json``](./appinsights.json)
- KQL used: see [``../../kql/``](../../kql/)
"@

$reportPath = Join-Path $ResultsDir 'REPORT.md'
$report | Set-Content -Path $reportPath -Encoding UTF8
Write-Host "Report written: $reportPath" -ForegroundColor Green
