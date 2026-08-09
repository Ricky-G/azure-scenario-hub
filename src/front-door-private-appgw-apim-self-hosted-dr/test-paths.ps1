#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$StateFile = (Join-Path $PSScriptRoot '.demo-state.json'),
    [int]$MaxAttempts = 30,
    [int]$RetryDelaySeconds = 20
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $StateFile)) {
    throw "Deployment state not found: $StateFile"
}

$state = Get-Content $StateFile -Raw | ConvertFrom-Json -Depth 20

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', received '$Actual'."
    }
    Write-Host "PASS  $Message" -ForegroundColor Green
}

function Invoke-PathWithRetry {
    param(
        [string]$Name,
        [string]$Url,
        [string]$ExpectedRoute,
        [string]$ExpectedGateway,
        [string]$ExpectedAppGatewayHop = ''
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $requestId = [guid]::NewGuid().ToString()
            $response = Invoke-WebRequest -Uri $Url -TimeoutSec 30 -Headers @{ 'Cache-Control' = 'no-cache'; 'X-Scenario-Request-Id' = $requestId }
            $body = $response.Content | ConvertFrom-Json
            $actualRoute = $response.Headers['X-Scenario-Route'] -join ','
            $actualGateway = $response.Headers['X-APIM-Gateway'] -join ','
            $actualApimService = $response.Headers['X-APIM-Service'] -join ','
            $actualAppGatewayHop = $response.Headers['X-AppGateway-Hop'] -join ','
            $actualBackendRequestId = $response.Headers['X-Backend-Request-Id'] -join ','
            Assert-Equal $response.StatusCode 200 "$Name returns HTTP 200."
            Assert-Equal $body.message 'Hello World' "$Name reaches the Hello World backend."
            Assert-Equal $body.backend 'mock-onprem-aks' "$Name reaches the AKS backend."
            Assert-Equal $actualBackendRequestId $requestId "$Name backend echoes the correlated request ID."
            Assert-Equal $body.requestId $requestId "$Name response body contains the correlated request ID."
            Assert-Equal $actualRoute $ExpectedRoute "$Name reports the expected APIM route."
            Assert-Equal $actualGateway $ExpectedGateway "$Name reports the expected APIM gateway."
            if ($ExpectedGateway -eq 'self-hosted') {
                $expectedApimService = $state.outputs.apimServiceName
            } else {
                $expectedApimService = "$($state.outputs.apimServiceName).azure-api.net"
            }
            Assert-Equal $actualApimService $expectedApimService "$Name reports the expected APIM service identity."
            if (-not [string]::IsNullOrWhiteSpace($ExpectedAppGatewayHop)) {
                Assert-Equal $actualAppGatewayHop $ExpectedAppGatewayHop "$Name reports the expected Application Gateway hop."
            }
            return [pscustomobject][ordered]@{
                name = $Name
                url = $Url
                status = $response.StatusCode
                route = $actualRoute
                gateway = $actualGateway
                appGatewayHop = $actualAppGatewayHop
                backend = $body.backend
                requestId = $requestId
            }
        } catch {
            $lastError = $_
            if ($attempt -lt $MaxAttempts) {
                Write-Host "WAIT  $Name is not ready (attempt $attempt/$MaxAttempts): $($_.Exception.Message)" -ForegroundColor DarkYellow
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }
    throw "$Name failed after $MaxAttempts attempts. Last error: $($lastError.Exception.Message)"
}

function Invoke-EvidenceWithRetry {
    param([string]$Route)

    $lastError = $null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return Invoke-RestMethod -Uri "$($state.outputs.testWebAppUrl)/api/test?route=$Route" -TimeoutSec 45
        } catch {
            $lastError = $_
            if ($attempt -lt $MaxAttempts) {
                Write-Host "WAIT  Web evidence endpoint '$Route' is not ready (attempt $attempt/$MaxAttempts)." -ForegroundColor DarkYellow
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }
    throw "Web evidence endpoint '$Route' failed after $MaxAttempts attempts. Last error: $($lastError.Exception.Message)"
}

Write-Host "`nInfrastructure assertions" -ForegroundColor Cyan
$appGatewayOperationalState = az network application-gateway show --resource-group $state.resourceGroupName --name $state.outputs.appGatewayName --query operationalState --output tsv
Assert-Equal $appGatewayOperationalState 'Running' 'Application Gateway is running.'

$aksPowerState = az aks show --resource-group $state.resourceGroupName --name $state.outputs.aksClusterName --query powerState.code --output tsv
Assert-Equal $aksPowerState 'Running' 'AKS is running.'

$apimVnetType = az apim show --resource-group $state.resourceGroupName --name $state.outputs.apimServiceName --query virtualNetworkType --output tsv
Assert-Equal $apimVnetType 'Internal' 'API Management uses internal VNet mode.'

$publicListenerCount = az network application-gateway show --resource-group $state.resourceGroupName --name $state.outputs.appGatewayName --query "length(httpListeners[?contains(frontendIPConfiguration.id, '/frontendIPConfigurations/public-frontend-no-listener')])" --output tsv
Assert-Equal $publicListenerCount '0' 'Application Gateway has no listener on its platform-required public frontend.'

$privateConnectionStatuses = @(az network private-endpoint-connection list --resource-group $state.resourceGroupName --name $state.outputs.appGatewayName --type Microsoft.Network/applicationGateways --query '[].properties.privateLinkServiceConnectionState.status' --output tsv)
if ($privateConnectionStatuses -notcontains 'Approved') {
    throw "Application Gateway has no approved Front Door private endpoint connection. Statuses: $($privateConnectionStatuses -join ', ')"
}
Write-Host 'PASS  Front Door Private Link connection is approved.' -ForegroundColor Green

$backendReady = kubectl get deployment hello-backend --output jsonpath='{.status.readyReplicas}'
Assert-Equal $backendReady '2' 'Both Hello World backend replicas are ready.'

$gatewayReady = kubectl get deployment apim-self-hosted-gateway --namespace apim-gateway --output jsonpath='{.status.readyReplicas}'
Assert-Equal $gatewayReady '1' 'The APIM self-hosted gateway pod is ready.'

$gatewayPublicIp = kubectl get service apim-self-hosted-gateway --namespace apim-gateway --output jsonpath='{.status.loadBalancer.ingress[0].ip}'
Assert-Equal $gatewayPublicIp $state.outputs.drPublicIpAddress 'The self-hosted gateway uses the reserved DR public IP.'

$aksSubnetId = az aks show --resource-group $state.resourceGroupName --name $state.outputs.aksClusterName --query 'agentPoolProfiles[0].vnetSubnetId' --output tsv
$aksSubnetNsgId = az network vnet subnet show --ids $aksSubnetId --query 'networkSecurityGroup.id' --output tsv
$frontDoorRuleSource = az rest --method get --url "https://management.azure.com${aksSubnetNsgId}/securityRules/Allow-AzureFrontDoor-To-SelfHostedGateway?api-version=2024-05-01" --query 'properties.sourceAddressPrefix' --output tsv
Assert-Equal $frontDoorRuleSource 'AzureFrontDoor.Backend' 'The AKS subnet permits the DR gateway only from Azure Front Door.'

$gatewayResourceUrl = "/subscriptions/$($state.subscriptionId)/resourceGroups/$($state.resourceGroupName)/providers/Microsoft.ApiManagement/service/$($state.outputs.apimServiceName)/gateways/$($state.outputs.selfHostedGatewayName)"
$registeredGatewayName = az rest --method get --url "${gatewayResourceUrl}?api-version=2024-05-01" --query name --output tsv
Assert-Equal $registeredGatewayName $state.outputs.selfHostedGatewayName 'The self-hosted gateway is registered with the APIM instance.'
$associatedApis = @(az rest --method get --url "${gatewayResourceUrl}/apis?api-version=2024-05-01" --query 'value[].name' --output tsv)
if ($associatedApis -notcontains 'dr-api') {
    throw "The self-hosted gateway is not associated with dr-api. Associations: $($associatedApis -join ', ')"
}
Write-Host 'PASS  The APIM self-hosted gateway is associated with dr-api.' -ForegroundColor Green

Write-Host "`nEnd-to-end assertions" -ForegroundColor Cyan
$results = @(
    Invoke-PathWithRetry -Name 'Happy path' -Url $state.outputs.happyPathUrl -ExpectedRoute 'happy-managed' -ExpectedGateway 'managed' -ExpectedAppGatewayHop 'private-waf-v2'
    Invoke-PathWithRetry -Name 'DR path' -Url $state.outputs.drPathUrl -ExpectedRoute 'dr-self-hosted' -ExpectedGateway 'self-hosted'
)

$uiResponse = Invoke-WebRequest -Uri $state.outputs.testWebAppUrl -TimeoutSec 30
Assert-Equal $uiResponse.StatusCode 200 'Hosted path tester UI returns HTTP 200.'

$happyEvidence = Invoke-EvidenceWithRetry -Route 'happy'
Assert-Equal $happyEvidence.ok $true 'Hosted UI evidence API verifies the happy path.'
Assert-Equal @($happyEvidence.hops | Where-Object verified).Count 4 'Hosted UI reports proof for all four happy-path hops.'

$drEvidence = Invoke-EvidenceWithRetry -Route 'dr'
Assert-Equal $drEvidence.ok $true 'Hosted UI evidence API verifies the DR path.'
Assert-Equal @($drEvidence.hops | Where-Object verified).Count 4 'Hosted UI reports proof for all four DR-path hops.'
Assert-Equal $drEvidence.controlPlane.verified $true 'Hosted UI verifies APIM self-hosted gateway registration through managed identity.'
if ($drEvidence.controlPlane.associatedApis -notcontains 'dr-api') {
    throw 'Hosted UI control-plane evidence does not include dr-api.'
}
Write-Host 'PASS  Hosted UI control-plane evidence includes dr-api.' -ForegroundColor Green

Write-Host "`nValidated routes" -ForegroundColor Cyan
$results | Format-Table name, status, route, gateway, appGatewayHop, backend -AutoSize