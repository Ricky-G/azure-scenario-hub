#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Smoke-test all 10 endpoints on both APIMs. Aborts on any non-200.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

function Test-Apim {
    param([string]$Side, [string]$GatewayUrl, [int]$ApiCount)

    Write-Host "`n--- APIM-$Side : $GatewayUrl ---" -ForegroundColor Cyan
    $failed = 0
    for ($i = 1; $i -le $ApiCount; $i++) {
        $svc = 'svc{0:D2}' -f $i
        $url = "$GatewayUrl/$svc/v1/resource/1"
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
            $sw.Stop()
            if ($r.StatusCode -eq 200) {
                Write-Host ("  OK  {0,-8} {1,5} ms" -f $svc, $sw.ElapsedMilliseconds) -ForegroundColor Green
            } else {
                Write-Host ("  FAIL {0,-8} status={1}" -f $svc, $r.StatusCode) -ForegroundColor Red
                $failed++
            }
        } catch {
            Write-Host ("  FAIL {0,-8} {1}" -f $svc, $_.Exception.Message) -ForegroundColor Red
            $failed++
        }
    }
    return $failed
}

$failedA = Test-Apim -Side 'A' -GatewayUrl $config.apimAGatewayUrl -ApiCount $config.apiCount
$failedB = Test-Apim -Side 'B' -GatewayUrl $config.apimBGatewayUrl -ApiCount $config.apiCount

$total = $failedA + $failedB
if ($total -gt 0) {
    Write-Host "`n$total endpoint(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll endpoints OK on both APIMs." -ForegroundColor Green
