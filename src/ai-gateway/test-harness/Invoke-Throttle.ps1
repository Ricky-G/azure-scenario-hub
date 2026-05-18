#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Hammer the gateway with a single product subscription to demonstrate the
    per-product `azure-openai-token-limit` policy returning 429 once the TPM
    threshold is crossed.

.EXAMPLE
    .\Invoke-Throttle.ps1 -ResourceGroupName rg-ai-gateway-demo `
        -ApimName aigw-apim-xxxx -Product finance-smart-analysis -Calls 30
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ResourceGroupName,
    [Parameter(Mandatory = $true)] [string]$ApimName,
    [Parameter(Mandatory = $false)] [string]$Product = 'finance-smart-analysis',
    [Parameter(Mandatory = $false)] [string]$Deployment = 'gpt-4.1',
    [Parameter(Mandatory = $false)] [int]$Calls = 25,
    [Parameter(Mandatory = $false)] [ValidateSet('aue','global')] [string]$Route = 'global',
    [Parameter(Mandatory = $false)] [string]$ApiVersion = '2024-10-21'
)
$ErrorActionPreference = 'Stop'

$gatewayUrl = az apim show -g $ResourceGroupName -n $ApimName --query gatewayUrl -o tsv
$subscriptionId = az account show --query id -o tsv
$secretsUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$Product-demo-sub/listSecrets?api-version=2023-05-01-preview"
$key = (az rest --method post --url $secretsUrl -o json | ConvertFrom-Json).primaryKey
$url = "$gatewayUrl/$Route/openai/deployments/$Deployment/chat/completions?api-version=$ApiVersion"

$ok = 0; $throttled = 0; $other = 0
1..$Calls | ForEach-Object {
    $i = $_
    # Make every call body unique so we don't hit the response cache; that
    # ensures the per-product TPM ceiling is the only thing that can throttle.
    $body = @{
        messages = @(
            @{ role = 'system'; content = 'You are an expert finance analyst. Provide thorough, multi-paragraph answers.' }
            @{ role = 'user';   content = ("Call $i / $Calls. Discuss in detail the impact of macro-economic factors on equity valuations. " * 6) }
        )
        max_tokens  = 800
        temperature = 0.7
    } | ConvertTo-Json -Depth 5 -Compress

    $headers = @{
        'api-key'      = $key
        'Content-Type' = 'application/json'
        'x-session-id' = "throttle-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        'x-user-id'    = "loaduser-$i"
    }
    try {
        $resp = Invoke-WebRequest -Method Post -Uri $url -Headers $headers -Body $body -TimeoutSec 60 -SkipHttpErrorCheck
        $code = $resp.StatusCode
        switch ($code) {
            200     { $ok++;        Write-Host "  call $i OK"        -ForegroundColor Green }
            429     { $throttled++; Write-Host "  call $i THROTTLED"  -ForegroundColor Yellow }
            default { $other++;     Write-Host "  call $i status=$code" -ForegroundColor Red }
        }
    } catch {
        $other++
        Write-Host "  call $i EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host ""
Write-Host "Done. ok=$ok throttled=$throttled other=$other" -ForegroundColor Cyan
Write-Host "Check the throttling KQL query (..\kql\throttling-events.kql)." -ForegroundColor Yellow
