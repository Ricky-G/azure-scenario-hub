#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$StateFile = (Join-Path $PSScriptRoot '.demo-state.json'),
    [int]$RuntimeWaitMinutes = 20
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
    Write-Host "PASS  $Message" -ForegroundColor Green
}

function Get-HeaderValue {
    param($Response, [string]$Name)
    return [string]@($Response.Headers[$Name])[0]
}

function Invoke-AzRestJson {
    param([string]$Url)
    $json = az rest --method get --url $Url --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure REST request failed: $Url"
    }
    return $json | ConvertFrom-Json -Depth 100
}

function Wait-Api {
    param([string]$Url)
    $deadline = (Get-Date).AddMinutes($RuntimeWaitMinutes)
    do {
        try {
            $response = Invoke-WebRequest -Uri $Url -Headers @{ 'X-Demo-Client' = "readiness-$([guid]::NewGuid())" } -SkipHttpErrorCheck
            if ($response.StatusCode -eq 200) {
                return $response
            }
        } catch {
            Write-Verbose $_.Exception.Message
        }
        Write-Host "Waiting for gateway configuration propagation: $Url" -ForegroundColor Yellow
        Start-Sleep -Seconds 20
    } while ((Get-Date) -lt $deadline)
    throw "API did not become ready within $RuntimeWaitMinutes minutes: $Url"
}

if (-not (Test-Path $StateFile)) {
    throw "Deployment state not found: $StateFile. Run deploy-infra.ps1 first."
}

$state = Get-Content $StateFile -Raw | ConvertFrom-Json -Depth 100
$outputs = $state.outputs
$apiVersion = '2024-05-01'
$connectionApiVersion = '2024-06-01-preview'

Write-Host "`nControl-plane validation" -ForegroundColor Cyan
$dataScienceWorkspace = Invoke-AzRestJson "$($outputs.dataScienceWorkspaceId.value)?api-version=$apiVersion"
$websiteWorkspace = Invoke-AzRestJson "$($outputs.websiteWorkspaceId.value)?api-version=$apiVersion"
Assert-True ($dataScienceWorkspace.properties.displayName -eq 'Data Science Team') 'Data Science workspace exists'
Assert-True ($websiteWorkspace.properties.displayName -eq 'Website Experience Team') 'Website Experience workspace exists'

$dataScienceApis = Invoke-AzRestJson "$($outputs.dataScienceWorkspaceId.value)/apis?api-version=$apiVersion"
$websiteApis = Invoke-AzRestJson "$($outputs.websiteWorkspaceId.value)/apis?api-version=$apiVersion"
$dataScienceProducts = Invoke-AzRestJson "$($outputs.dataScienceWorkspaceId.value)/products?api-version=$apiVersion"
$websiteProducts = Invoke-AzRestJson "$($outputs.websiteWorkspaceId.value)/products?api-version=$apiVersion"
Assert-True ($dataScienceApis.value.name -contains 'ds-fraud-risk-api') 'Data Science workspace owns its inference API'
Assert-True ($websiteApis.value.name -contains 'web-personalization-api') 'Website workspace owns its experience API'
Assert-True ($dataScienceProducts.value.name -contains 'ds-model-products') 'Data Science team published its product'
Assert-True ($websiteProducts.value.name -contains 'web-experience-products') 'Website team published its product'

$gatewaysJson = az resource list `
    --resource-group $outputs.scenarioResourceGroupName.value `
    --resource-type Microsoft.ApiManagement/gateways `
    --output json
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to list workspace gateways.'
}
$gateways = @($gatewaysJson | ConvertFrom-Json -Depth 100)
$expectedGatewayCount = $outputs.gatewayTopology.value -eq 'Dedicated' ? 2 : 1
Assert-True ($gateways.Count -eq $expectedGatewayCount) "$expectedGatewayCount workspace gateway resource(s) use the selected topology"

$connectionCount = 0
foreach ($gateway in $gateways) {
    $connections = Invoke-AzRestJson "$($gateway.id)/configConnections?api-version=$connectionApiVersion"
    $connectionCount += @($connections.value).Count
}
Assert-True ($connectionCount -eq 2) 'Both workspaces are connected to runtime gateways'

Write-Host "`nRuntime validation" -ForegroundColor Cyan
$dataScienceResponse = Wait-Api $outputs.dataScienceApiUrl.value
$websiteResponse = Wait-Api $outputs.websiteApiUrl.value
$dataScienceBody = $dataScienceResponse.Content | ConvertFrom-Json
$websiteBody = $websiteResponse.Content | ConvertFrom-Json

Assert-True ($dataScienceBody.servedBy -eq 'data-science') 'Data Science API returns the expected team payload'
Assert-True ($websiteBody.servedBy -eq 'website-experience') 'Website API returns the expected team payload'
Assert-True ((Get-HeaderValue $dataScienceResponse 'X-Workspace-Owner') -eq 'Data Science Team') 'Data Science workspace policy supplies team ownership'
Assert-True ((Get-HeaderValue $websiteResponse 'X-Workspace-Owner') -eq 'Website Experience Team') 'Website workspace policy supplies team ownership'
Assert-True ((Get-HeaderValue $dataScienceResponse 'X-Team-Policy') -eq 'ds-standards-v1') 'Data Science reusable policy fragment executed'
Assert-True ((Get-HeaderValue $websiteResponse 'X-Team-Policy') -eq 'web-standards-v1') 'Website reusable policy fragment executed'

$expectedGovernance = $state.parameters.configureGlobalPolicy ? 'central-platform-baseline-v1' : 'customer-managed-global-policy'
Assert-True ((Get-HeaderValue $dataScienceResponse 'X-Platform-Governance') -eq $expectedGovernance) 'Platform governance is visible on the Data Science API'
Assert-True ((Get-HeaderValue $websiteResponse 'X-Platform-Governance') -eq $expectedGovernance) 'Platform governance is visible on the Website API'

$rateLimitKey = "rate-test-$([guid]::NewGuid())"
$statusCodes = for ($attempt = 1; $attempt -le 10; $attempt++) {
    (Invoke-WebRequest -Uri $outputs.dataScienceApiUrl.value -Headers @{ 'X-Demo-Client' = $rateLimitKey } -SkipHttpErrorCheck).StatusCode
}
Assert-True (($statusCodes[0..4] | Where-Object { $_ -ne 200 }).Count -eq 0) 'First five Data Science requests are accepted'
Assert-True (($statusCodes[5..9] | Where-Object { $_ -eq 429 }).Count -ge 1) 'Data Science gateway begins returning 429 after the configured threshold'

Write-Host "`nAll APIM workspace checks passed." -ForegroundColor Green
Write-Host "Data Science API: $($outputs.dataScienceApiUrl.value)" -ForegroundColor Cyan
Write-Host "Website API:      $($outputs.websiteApiUrl.value)" -ForegroundColor Cyan
