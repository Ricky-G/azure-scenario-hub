#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$ResourceGroupName = 'rg-front-door-private-appgw-apim-dr',
    [string]$Location = 'newzealandnorth',
    [ValidateLength(3, 10)]
    [string]$NamePrefix = 'fdapimdr',
    [ValidateSet('Premium', 'Developer')]
    [string]$ApimSku = 'Premium',
    [string]$PublisherEmail = '',
    [string]$PublisherName = 'Azure Scenario Hub',
    [string]$FrontDoorPrivateLinkLocation = 'australiaeast',
    [string]$KubernetesVersion = '1.34',
    [string]$NodeVmSize = 'Standard_D2s_v5',
    [string]$SelfHostedGatewayChartVersion = '1.15.1',
    [switch]$SkipConfirmation,
    [switch]$SkipWhatIf
)

$ErrorActionPreference = 'Stop'
$templateFile = Join-Path $PSScriptRoot 'bicep/main.bicep'
$manifestFile = Join-Path $PSScriptRoot 'manifests/hello-backend.yaml'
$appDirectory = Join-Path $PSScriptRoot 'app'
$stateFile = Join-Path $PSScriptRoot '.demo-state.json'

function Assert-LastExitCode {
    param([string]$Operation)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE."
    }
}

foreach ($command in @('az', 'kubectl', 'helm')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found."
    }
}

$accountJson = az account show --output json 2>$null
Assert-LastExitCode 'Azure login check'
$account = $accountJson | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($PublisherEmail)) {
    $PublisherEmail = $account.user.name -match '@' ? $account.user.name : 'admin@example.com'
}

Write-Host "`nFront Door + private App Gateway + APIM hybrid DR scenario" -ForegroundColor Cyan
Write-Host "Subscription:   $($account.name)" -ForegroundColor Gray
Write-Host "Resource group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "Location:       $Location" -ForegroundColor Gray
Write-Host "APIM SKU:       $ApimSku" -ForegroundColor Gray

if (-not $SkipConfirmation) {
    Write-Warning 'This deploys APIM Premium, Front Door Premium, Application Gateway WAF_v2, AKS, and App Service. Costs accrue until cleanup.'
    $answer = Read-Host 'Continue (y/N)'
    if ($answer -notin @('y', 'Y')) {
        Write-Host 'Deployment cancelled.' -ForegroundColor Yellow
        return
    }
}

Write-Host "`n[1/10] Compiling Bicep..." -ForegroundColor Yellow
az bicep build --file $templateFile --stdout | Out-Null
Assert-LastExitCode 'Bicep compilation'

Write-Host "[2/10] Creating resource group..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location --tags Project=AzureScenarioHub Scenario=FrontDoor-Private-AppGateway-APIM-SelfHosted-DR --output none
Assert-LastExitCode 'Resource group creation'

$parameters = @(
    "location=$Location"
    "namePrefix=$NamePrefix"
    "apimSku=$ApimSku"
    "publisherEmail=$PublisherEmail"
    "publisherName=$PublisherName"
    "frontDoorPrivateLinkLocation=$FrontDoorPrivateLinkLocation"
    "kubernetesVersion=$KubernetesVersion"
    "nodeVmSize=$NodeVmSize"
)

if (-not $SkipWhatIf) {
    Write-Host '[3/10] Running Azure deployment what-if...' -ForegroundColor Yellow
    az deployment group what-if `
        --resource-group $ResourceGroupName `
        --template-file $templateFile `
        --parameters @parameters `
        --result-format ResourceIdOnly `
        --output table
    Assert-LastExitCode 'Azure deployment what-if'
} else {
    Write-Host '[3/10] Skipping Azure deployment what-if.' -ForegroundColor DarkYellow
}

$deploymentName = "front-door-apim-dr-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "[4/10] Deploying Azure resources. APIM is the long-running step..." -ForegroundColor Yellow
$deploymentJson = az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroupName `
    --template-file $templateFile `
    --parameters @parameters `
    --mode Incremental `
    --output json
Assert-LastExitCode 'Azure resource deployment'
$deployment = $deploymentJson | ConvertFrom-Json -Depth 100
$outputs = $deployment.properties.outputs

& (Join-Path $PSScriptRoot 'restore-baseline.ps1') `
    -ResourceGroupName $ResourceGroupName `
    -AppGatewayName $outputs.appGatewayName.value `
    -AksClusterName $outputs.aksClusterName.value

Write-Host '[5/10] Approving the Front Door private endpoint connection...' -ForegroundColor Yellow
$privateEndpointConnectionId = ''
$privateEndpointConnectionStatus = ''
for ($attempt = 1; $attempt -le 30 -and [string]::IsNullOrWhiteSpace($privateEndpointConnectionStatus); $attempt++) {
    $connectionJson = az network private-endpoint-connection list `
        --name $outputs.appGatewayName.value `
        --resource-group $ResourceGroupName `
        --type Microsoft.Network/applicationGateways `
        --query "[?properties.privateLinkServiceConnectionState.status=='Approved' || properties.privateLinkServiceConnectionState.status=='Pending'] | [0].{id:id,status:properties.privateLinkServiceConnectionState.status}" `
        --output json
    $connection = $connectionJson | ConvertFrom-Json
    if ($connection) {
        $privateEndpointConnectionId = $connection.id
        $privateEndpointConnectionStatus = $connection.status
    } else {
        Start-Sleep -Seconds 20
    }
}
if ([string]::IsNullOrWhiteSpace($privateEndpointConnectionStatus)) {
    throw 'Front Door private endpoint request did not appear on Application Gateway.'
}
if ($privateEndpointConnectionStatus -eq 'Pending') {
    az network private-endpoint-connection approve --id $privateEndpointConnectionId --description 'Approved by scenario deployment automation.' --output none
    Assert-LastExitCode 'Front Door private endpoint approval'
} else {
    Write-Host '  Front Door private endpoint is already approved.' -ForegroundColor Green
}

Write-Host '[6/10] Deploying the AKS Hello World backend...' -ForegroundColor Yellow
az aks get-credentials --resource-group $ResourceGroupName --name $outputs.aksClusterName.value --overwrite-existing --only-show-errors
Assert-LastExitCode 'AKS credential retrieval'
kubectl apply --dry-run=server -f $manifestFile --output name
Assert-LastExitCode 'Hello World server-side manifest validation'
kubectl apply -f $manifestFile
Assert-LastExitCode 'Hello World manifest deployment'
kubectl rollout restart deployment/hello-backend
Assert-LastExitCode 'Hello World restart'
kubectl rollout status deployment/hello-backend --timeout=5m
Assert-LastExitCode 'Hello World rollout'

Write-Host '[7/10] Generating the APIM self-hosted gateway token...' -ForegroundColor Yellow
$tokenExpiry = (Get-Date).ToUniversalTime().AddDays(29).ToString('yyyy-MM-ddTHH:mm:ssZ')
$tokenBody = @{ keyType = 'primary'; expiry = $tokenExpiry } | ConvertTo-Json -Compress
$gatewayTokenUri = "/subscriptions/$($account.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$($outputs.apimServiceName.value)/gateways/$($outputs.selfHostedGatewayName.value)/generateToken?api-version=2024-05-01"
$tokenRequestFile = Join-Path ([System.IO.Path]::GetTempPath()) "apim-token-request-$([Guid]::NewGuid().ToString('N')).json"
try {
    Set-Content -Path $tokenRequestFile -Value $tokenBody -Encoding utf8
    $tokenResponseJson = az rest --method post --uri $gatewayTokenUri --body "@$tokenRequestFile" --output json
    Assert-LastExitCode 'Self-hosted gateway token generation'
} finally {
    if (Test-Path $tokenRequestFile) {
        Remove-Item $tokenRequestFile -Force
    }
}
$rawGatewayToken = ($tokenResponseJson | ConvertFrom-Json).value
$gatewayToken = $rawGatewayToken.StartsWith('GatewayKey ') ? $rawGatewayToken : "GatewayKey $rawGatewayToken"

Write-Host '[8/10] Installing the APIM self-hosted gateway with Helm...' -ForegroundColor Yellow
$valuesFile = Join-Path ([System.IO.Path]::GetTempPath()) "apim-gateway-$([Guid]::NewGuid().ToString('N')).json"
try {
        $values = [ordered]@{
                fullnameOverride = 'apim-self-hosted-gateway'
                replicaCount = 1
                gateway = [ordered]@{
                        configuration = @{ uri = $outputs.selfHostedGatewayConfigurationUri.value }
                        auth = @{ type = 'GatewayToken'; key = $gatewayToken }
                        deployment = @{
                                dns = @{
                                        hostAliases = @(
                                                @{
                                                        ip = $outputs.apimPrivateIpAddress.value
                                                        hostnames = @("$($outputs.apimServiceName.value).configuration.azure-api.net")
                                                }
                                        )
                                }
                        }
                }
                service = [ordered]@{
                        type = 'LoadBalancer'
                        ports = @{ http = 80 }
                        annotations = @{
                                'service.beta.kubernetes.io/azure-pip-name' = $outputs.drPublicIpName.value
                                'service.beta.kubernetes.io/azure-load-balancer-resource-group' = $ResourceGroupName
                        }
                }
                highAvailability = @{ enabled = $false }
                resources = @{
                        requests = @{ cpu = '100m'; memory = '128Mi' }
                        limits = @{ cpu = '500m'; memory = '512Mi' }
                }
        } | ConvertTo-Json -Depth 20
    Set-Content -Path $valuesFile -Value $values -Encoding utf8
    helm upgrade --install apim-self-hosted-gateway azure-api-management-gateway `
        --repo https://azure.github.io/api-management-self-hosted-gateway/helm-charts/ `
        --version $SelfHostedGatewayChartVersion `
        --namespace apim-gateway `
        --create-namespace `
        --values $valuesFile `
        --wait `
        --timeout 10m
    Assert-LastExitCode 'Self-hosted gateway Helm deployment'
} finally {
    if (Test-Path $valuesFile) {
        Remove-Item $valuesFile -Force
    }
}

Write-Host '[9/10] Publishing the browser test UI...' -ForegroundColor Yellow
$appZip = Join-Path ([System.IO.Path]::GetTempPath()) "front-door-path-tester-$([Guid]::NewGuid().ToString('N')).zip"
try {
    Compress-Archive -Path (Join-Path $appDirectory '*') -DestinationPath $appZip -CompressionLevel Optimal
    az webapp deploy `
        --resource-group $ResourceGroupName `
        --name $outputs.testWebAppName.value `
        --src-path $appZip `
        --type zip `
        --clean true `
        --restart true `
        --output none
    Assert-LastExitCode 'Test UI deployment'
} finally {
    if (Test-Path $appZip) {
        Remove-Item $appZip -Force
    }
}

$normalizedOutputs = [ordered]@{}
foreach ($property in $outputs.PSObject.Properties) {
    $normalizedOutputs[$property.Name] = $property.Value.value
}
$state = [ordered]@{
    deploymentName = $deploymentName
    subscriptionId = $account.id
    subscriptionName = $account.name
    resourceGroupName = $ResourceGroupName
    location = $Location
    createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    selfHostedGatewayTokenExpiresUtc = $tokenExpiry
    outputs = $normalizedOutputs
}
$state | ConvertTo-Json -Depth 20 | Set-Content -Path $stateFile -Encoding utf8

Write-Host '[10/10] Running end-to-end validation...' -ForegroundColor Yellow
& (Join-Path $PSScriptRoot 'test-paths.ps1') -StateFile $stateFile

Write-Host "`nDeployment and validation completed." -ForegroundColor Green
Write-Host "Test UI:    $($outputs.testWebAppUrl.value)" -ForegroundColor Cyan
Write-Host "Happy path: $($outputs.happyPathUrl.value)" -ForegroundColor Cyan
Write-Host "DR path:    $($outputs.drPathUrl.value)" -ForegroundColor Cyan
Write-Host "State file: $stateFile" -ForegroundColor Gray