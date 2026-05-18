#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Drive demo traffic through the AI Gateway across one or both customer-
    facing routes (Australia East / Global) and showcase per-app token
    charge-back, regional dimension reporting, and APIM custom headers.

.DESCRIPTION
    Pulls the APIM gateway URL and the per-product subscription keys directly
    from the Azure deployment, then sends a configurable number of chat
    completions per product to the chosen route(s). The harness sets
    `x-session-id` and `x-user-id` headers so the policies tag every call
    with realistic correlation data, and prints the APIM-injected response
    headers (`x-ai-gateway-route`, `x-ai-gateway-cache`) so you can show
    the customer where the call landed.

.PARAMETER Route
    Which APIM route(s) to drive: aue, global, or both (default).

.EXAMPLE
    ./Invoke-Demo.ps1 -ResourceGroupName rg-ai-gateway-demo `
        -ApimName aigw-apim-xxxxxxxx -CallsPerProduct 3
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ApimName,

    [Parameter(Mandatory = $false)]
    [int]$CallsPerProduct = 3,

    [Parameter(Mandatory = $false)]
    [ValidateSet('aue', 'global', 'both')]
    [string]$Route = 'both',

    [Parameter(Mandatory = $false)]
    [string]$ApiVersion = '2024-10-21',

    [Parameter(Mandatory = $false)]
    [hashtable]$ProductDeploymentMap = @{
        'retail-smart-shopping'  = 'gpt-4.1-mini'
        'customer-care-chat'     = 'gpt-4.1-mini'
        'finance-smart-analysis' = 'gpt-4.1'
    }
)
$ErrorActionPreference = 'Stop'

# Resolve the routes to drive in this run.
$routes = switch ($Route) {
    'aue'    { @('aue') }
    'global' { @('global') }
    default  { @('aue', 'global') }
}

# Sample prompts per product so the demo conversation looks realistic.
$prompts = @{
    'retail-smart-shopping' = @(
        'Suggest a winter jacket under $200 for hiking in cold weather.',
        'What is a good gift for a 12 year old who likes science?',
        'Compare wireless earbuds for running.',
        'I need a birthday cake idea for a chocolate lover.',
        'Recommend three books like Project Hail Mary.'
    )
    'customer-care-chat' = @(
        'How do I reset my password?',
        'Where is my order #12345?',
        'I want to return an item I bought yesterday.',
        'My delivery is late, what can you do?',
        'Can you change my shipping address?'
    )
    'finance-smart-analysis' = @(
        'Summarise the impact of rising interest rates on tech stocks.',
        'Explain DCF in two sentences.',
        'Give a pros/cons list for ETFs vs mutual funds.',
        'What is EBITDA used for?',
        'Outline the key risks in a leveraged buyout.'
    )
}

Write-Host "==> Fetching APIM gateway URL..." -ForegroundColor Cyan
$gatewayUrl = az apim show -g $ResourceGroupName -n $ApimName --query gatewayUrl -o tsv
if (-not $gatewayUrl) { throw "Could not find APIM '$ApimName' in '$ResourceGroupName'." }
Write-Host "    $gatewayUrl" -ForegroundColor Gray
Write-Host "    Routes : $($routes -join ', ')" -ForegroundColor Gray

Write-Host "==> Fetching per-product subscription keys..." -ForegroundColor Cyan
$subscriptionId = az account show --query id -o tsv
$products = $ProductDeploymentMap.Keys
$keys = @{}
foreach ($product in $products) {
    $sid = "$product-demo-sub"
    $url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$sid/listSecrets?api-version=2023-05-01-preview"
    $secrets = az rest --method post --url $url -o json 2>$null | ConvertFrom-Json
    $primary = $secrets.primaryKey
    if (-not $primary) {
        Write-Warning "Subscription '$sid' not found - skipping product '$product'."
        continue
    }
    $keys[$product] = $primary
    Write-Host "    $product => $($primary.Substring(0,8))********" -ForegroundColor Gray
}
if ($keys.Count -eq 0) { throw "No subscriptions resolved. Did the deployment finish?" }

# Track per-product/route totals for a recap at the end.
$summary = @{}
foreach ($product in $keys.Keys) {
    foreach ($r in $routes) {
        $summary["$product|$r"] = [pscustomobject]@{
            Product = $product; Route = $r
            Calls = 0; PromptTokens = 0; CompletionTokens = 0; TotalTokens = 0
            CacheHits = 0; Errors = 0
        }
    }
}

Write-Host ""
Write-Host "==> Driving $CallsPerProduct calls per product per route..." -ForegroundColor Cyan

foreach ($product in $keys.Keys) {
    $deployment = $ProductDeploymentMap[$product]
    $key = $keys[$product]
    $promptList = $prompts[$product]

    foreach ($routePath in $routes) {
        $url = "$gatewayUrl/$routePath/openai/deployments/$deployment/chat/completions?api-version=$ApiVersion"
        for ($i = 1; $i -le $CallsPerProduct; $i++) {
            $userMsg = $promptList[ ($i - 1) % $promptList.Count ]
            $body = @{
                messages = @(
                    @{ role = 'system'; content = "You are a helpful assistant for the $product use case. Answer in under 50 words." }
                    @{ role = 'user'; content = $userMsg }
                )
                max_tokens  = 120
                temperature = 0.5
            } | ConvertTo-Json -Depth 5 -Compress

            $headers = @{
                'api-key'       = $key
                'Content-Type'  = 'application/json'
                'x-session-id'  = "demo-$product-$routePath-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
                'x-user-id'     = "user-$product-$i"
            }

            try {
                $resp = Invoke-WebRequest -Method Post -Uri $url -Headers $headers -Body $body -TimeoutSec 60 -SkipHttpErrorCheck
                $code = $resp.StatusCode
                $cacheHdr = $resp.Headers['x-ai-gateway-cache']
                if ($cacheHdr -is [System.Collections.IEnumerable] -and $cacheHdr -isnot [string]) { $cacheHdr = ($cacheHdr | Select-Object -First 1) }
                $routeHdr = $resp.Headers['x-ai-gateway-route']
                if ($routeHdr -is [System.Collections.IEnumerable] -and $routeHdr -isnot [string]) { $routeHdr = ($routeHdr | Select-Object -First 1) }
                $cacheStr = if ($cacheHdr) { $cacheHdr } else { '-' }

                if ($code -eq 200) {
                    $payload = $resp.Content | ConvertFrom-Json
                    $usage = $payload.usage
                    $key2 = "$product|$routePath"
                    $summary[$key2].Calls            += 1
                    $summary[$key2].PromptTokens     += [int]($usage.prompt_tokens     ?? 0)
                    $summary[$key2].CompletionTokens += [int]($usage.completion_tokens ?? 0)
                    $summary[$key2].TotalTokens      += [int]($usage.total_tokens      ?? 0)
                    if ($cacheHdr -eq 'HIT') { $summary[$key2].CacheHits += 1 }

                    $first = ($payload.choices[0].message.content -replace "\s+", ' ').Trim()
                    if ($first.Length -gt 60) { $first = $first.Substring(0,60) + '...' }
                    Write-Host ("    [{0}|{1}] call {2} ok  cache={3,-4}  total={4,-3}  '{5}'" -f $product, $routePath, $i, $cacheStr, $usage.total_tokens, $first) -ForegroundColor Green
                }
                else {
                    $summary["$product|$routePath"].Errors += 1
                    Write-Host ("    [{0}|{1}] call {2} status={3} cache={4}" -f $product, $routePath, $i, $code, $cacheStr) -ForegroundColor Red
                }
            }
            catch {
                $summary["$product|$routePath"].Errors += 1
                Write-Host ("    [{0}|{1}] call {2} EXCEPTION: {3}" -f $product, $routePath, $i, $_.Exception.Message) -ForegroundColor Red
            }
        }
    }
}

Write-Host ""
Write-Host "==> Local per-product/route totals" -ForegroundColor Cyan
$summary.Values | Sort-Object Product, Route | ForEach-Object {
    Write-Host ("    {0,-26} route={1,-6} calls={2,-3} total={3,-5} cacheHits={4,-3} errors={5}" -f $_.Product, $_.Route, $_.Calls, $_.TotalTokens, $_.CacheHits, $_.Errors)
}

Write-Host ""
Write-Host "==> Telemetry will appear in Application Insights / Log Analytics within ~1-2 minutes." -ForegroundColor Yellow
Write-Host "    See ..\kql\charge-back-by-app.kql for per-route + per-app token roll-ups." -ForegroundColor Yellow
