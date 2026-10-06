#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Show APIM's response cache hit/miss behaviour for the AI Gateway.

.DESCRIPTION
    Sends the same chat-completion request three times against a chosen
    route. The first call should be a MISS (and a real backend call), the
    second + third should HIT the APIM internal cache and return in
    milliseconds without burning any model tokens.

.EXAMPLE
    ./Invoke-Cache.ps1 -ResourceGroupName rg-ai-gateway-demo `
        -ApimName aigw-apim-xxxx -Route global
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ResourceGroupName,
    [Parameter(Mandatory = $true)] [string]$ApimName,
    [Parameter(Mandatory = $false)] [ValidateSet('aue','global')] [string]$Route = 'global',
    [Parameter(Mandatory = $false)] [string]$Product = 'retail-smart-shopping',
    [Parameter(Mandatory = $false)] [string]$Deployment = 'gpt-4.1-mini',
    [Parameter(Mandatory = $false)] [int]$Calls = 3,
    [Parameter(Mandatory = $false)] [string]$ApiVersion = '2024-10-21'
)
$ErrorActionPreference = 'Stop'

$gatewayUrl = az apim show -g $ResourceGroupName -n $ApimName --query gatewayUrl -o tsv
$subId = az account show --query id -o tsv
$secretsUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$Product-demo-sub/listSecrets?api-version=2023-05-01-preview"
$key = (az rest --method post --url $secretsUrl -o json | ConvertFrom-Json).primaryKey
$url = "$gatewayUrl/$Route/openai/deployments/$Deployment/chat/completions?api-version=$ApiVersion"

# Identical body each call. Set temperature=0 so the model would also be
# deterministic if cache missed - makes the demo unambiguous.
$body = @{
    messages = @(
        @{ role = 'system'; content = 'You are a concise demo assistant.' }
        @{ role = 'user';   content = 'In one sentence, what is the AI Gateway demo showing?' }
    )
    max_tokens  = 60
    temperature = 0.0
} | ConvertTo-Json -Depth 5 -Compress

Write-Host "==> POST $url" -ForegroundColor Cyan
Write-Host "    (identical body each call - first should MISS, the next two HIT)" -ForegroundColor Gray
Write-Host ""

1..$Calls | ForEach-Object {
    $i = $_
    $headers = @{
        'api-key'      = $key
        'Content-Type' = 'application/json'
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $resp = Invoke-WebRequest -Method Post -Uri $url -Headers $headers -Body $body -TimeoutSec 60 -SkipHttpErrorCheck
    $sw.Stop()

    $cacheHdr = $resp.Headers['x-ai-gateway-cache']
    if ($cacheHdr -is [System.Collections.IEnumerable] -and $cacheHdr -isnot [string]) { $cacheHdr = ($cacheHdr | Select-Object -First 1) }
    $cacheStr = if ($cacheHdr) { $cacheHdr } else { '-' }

    if ($resp.StatusCode -eq 200) {
        $payload = $resp.Content | ConvertFrom-Json
        $usage = $payload.usage
        $msg = ($payload.choices[0].message.content -replace "\s+", ' ').Trim()
        Write-Host ("  call {0}  cache={1,-4}  duration={2,4}ms  tokens={3,-3}  '{4}'" -f $i, $cacheStr, $sw.ElapsedMilliseconds, ($usage.total_tokens ?? '-'), $msg) -ForegroundColor Green
    }
    else {
        Write-Host ("  call {0}  status={1}  cache={2}  body={3}" -f $i, $resp.StatusCode, $cacheStr, $resp.Content) -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "If you ran this within 5 minutes of a previous identical call, every call would HIT." -ForegroundColor Yellow
Write-Host "Cache TTL is 5 minutes (set in frag-cache-store.xml)." -ForegroundColor Yellow
