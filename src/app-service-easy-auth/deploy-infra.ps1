# =====================================================================================
# Deploys the App Service Easy Auth query-string round-trip scenario.
#
# Steps:
#   1. Create resource group
#   2. Create / reuse Entra app registration (web platform with Easy Auth callback URL)
#   3. Create client secret
#   4. Deploy Bicep (App Service + Easy Auth v2)
#   5. Zip-deploy the Node sample app
#   6. Print test URLs
# =====================================================================================
[CmdletBinding()]
param(
    [string]$Location          = 'eastus2',
    [string]$Sku               = 'P3v3',
    [string]$NamePrefix        = 'easyauth',
    [string]$ResourceGroupName = "rg-easyauth-demo",
    [string]$AppRegName        = "easyauth-demo-app"
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Make az CLI nonzero exit codes throw
function Invoke-AzSafe {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    & az @Args
    if ($LASTEXITCODE -ne 0) { throw "az command failed (exit $LASTEXITCODE): az $($Args -join ' ')" }
}

Write-Host "=== App Service Easy Auth — Query String Round-Trip Demo ===" -ForegroundColor Cyan

# --- 0. Sanity checks --------------------------------------------------------
$account = az account show --output json | ConvertFrom-Json
if (-not $account) { throw "Not logged in. Run 'az login' first." }
$tenantId       = $account.tenantId
$subscriptionId = $account.id
Write-Host "Subscription : $($account.name)  ($subscriptionId)"
Write-Host "Tenant       : $tenantId"
Write-Host "Location     : $Location"
Write-Host "Resource group: $ResourceGroupName"

# --- 1. Resource group -------------------------------------------------------
Write-Host "`n[1/5] Ensuring resource group..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location --output none

# --- 2. Entra app registration ----------------------------------------------
Write-Host "`n[2/5] Ensuring Entra app registration '$AppRegName'..." -ForegroundColor Yellow

# Pre-compute the predictable webapp hostname so we can register the redirect URI up front.
# Bicep uses uniqueString(resourceGroup().id) — derived from the RG resource ID.
# We can't compute that locally without ARM, so we use a two-pass approach:
#   - Create app registration with NO redirect URI initially (or a placeholder)
#   - After Bicep deploy, patch the registration with the real Easy Auth callback URL.

$appList = az ad app list --display-name $AppRegName --output json | ConvertFrom-Json
if ($appList.Count -gt 0) {
    $appId   = $appList[0].appId
    $objectId = $appList[0].id
    Write-Host "  Reusing existing app registration: $appId"
} else {
    $created = az ad app create `
        --display-name $AppRegName `
        --sign-in-audience AzureADMyOrg `
        --enable-id-token-issuance true `
        --output json | ConvertFrom-Json
    $appId    = $created.appId
    $objectId = $created.id
    Write-Host "  Created app registration: $appId"
    # Ensure service principal exists in this tenant
    az ad sp create --id $appId --output none 2>$null
}

# Create a fresh client secret (1 year)
Write-Host "  Creating client secret..."
$secret = az ad app credential reset `
    --id $appId `
    --display-name "easyauth-demo-$(Get-Date -Format yyyyMMddHHmmss)" `
    --years 1 `
    --output json | ConvertFrom-Json
$clientSecret = $secret.password

# --- 3. Bicep deployment -----------------------------------------------------
Write-Host "`n[3/5] Deploying Bicep..." -ForegroundColor Yellow
$deployName = "easyauth-$(Get-Date -Format yyyyMMddHHmmss)"

$deployment = az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deployName `
    --template-file "$scriptDir/bicep/main.bicep" `
    --parameters `
        location=$Location `
        namePrefix=$NamePrefix `
        appServicePlanSku=$Sku `
        entraClientId=$appId `
        entraTenantId=$tenantId `
        entraClientSecret=$clientSecret `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0 -or -not $deployment) { throw "Bicep deployment failed." }

$webAppName     = $deployment.properties.outputs.webAppName.value
$webAppUrl      = $deployment.properties.outputs.webAppUrl.value
$callbackUrl    = $deployment.properties.outputs.authCallbackUrl.value
Write-Host "  Web App  : $webAppName"
Write-Host "  URL      : $webAppUrl"
Write-Host "  Callback : $callbackUrl"

# --- 4. Patch app registration redirect URI ----------------------------------
Write-Host "`n[4/5] Updating app registration redirect URI..." -ForegroundColor Yellow
$graphBody = @{
    web = @{
        redirectUris = @($callbackUrl)
        implicitGrantSettings = @{
            enableIdTokenIssuance = $true
        }
    }
} | ConvertTo-Json -Depth 5 -Compress

# Use az rest to PATCH via Microsoft Graph
$tmpFile = New-TemporaryFile
$graphBody | Out-File -FilePath $tmpFile -Encoding utf8 -NoNewline
az rest --method PATCH `
    --uri "https://graph.microsoft.com/v1.0/applications/$objectId" `
    --headers "Content-Type=application/json" `
    --body "@$tmpFile" --output none
Remove-Item $tmpFile -Force

# --- 5. Zip-deploy the Node app ---------------------------------------------
Write-Host "`n[5/5] Packaging and deploying the Node app..." -ForegroundColor Yellow
$appDir = Join-Path $scriptDir 'app'
$zipPath = Join-Path $env:TEMP "easyauth-app-$(Get-Date -Format yyyyMMddHHmmss).zip"

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Push-Location $appDir
try {
    # Exclude node_modules — Oryx will install during SCM build
    Compress-Archive -Path 'index.js','package.json' -DestinationPath $zipPath -Force
} finally {
    Pop-Location
}
Write-Host "  Zip: $zipPath"

az webapp deploy `
    --resource-group $ResourceGroupName `
    --name $webAppName `
    --src-path $zipPath `
    --type zip `
    --async false `
    --output none

Remove-Item $zipPath -Force

# --- Done --------------------------------------------------------------------
Write-Host "`n=== Deployment complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Open in a browser (in this order):" -ForegroundColor Cyan
Write-Host "  1. $webAppUrl/?nhi=12345&tenant=acme&view=dashboard"
Write-Host "  2. $webAppUrl/?login_hint=alice@contoso.com&nhi=99999&feature=beta"
Write-Host "  3. $webAppUrl/landing?orderId=ABC-7788&source=email"
Write-Host ""
Write-Host "Each URL: you'll be redirected to Entra (sign in if first time), then back here." -ForegroundColor Cyan
Write-Host "The page will show that the ENTIRE query string survived the round trip." -ForegroundColor Cyan
Write-Host ""
Write-Host "Cleanup:  az group delete --name $ResourceGroupName --yes --no-wait" -ForegroundColor DarkGray
Write-Host "          az ad app delete --id $appId" -ForegroundColor DarkGray
