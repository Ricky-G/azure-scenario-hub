# Deploy Event Grid System Topic with Confidential Compute
# This script deploys the infrastructure to Azure

param(
    [string]$Location = "australiaeast",
    [string]$ResourceGroupName = "rg-event-grid-confidential-compute",
    [string]$DeploymentName = "eventgrid-confidential-compute-$(Get-Date -Format 'yyyyMMddHHmmss')"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Event Grid Confidential Compute Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Location: $Location" -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "Deployment Name: $DeploymentName" -ForegroundColor Yellow
Write-Host ""

# Check if logged into Azure
Write-Host "Checking Azure CLI login status..." -ForegroundColor Gray
$account = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not logged in to Azure. Please run 'az login' first." -ForegroundColor Red
    exit 1
}

Write-Host "Logged in to Azure subscription." -ForegroundColor Green
Write-Host ""

# Deploy the Bicep template
Write-Host "Starting deployment..." -ForegroundColor Cyan
Write-Host ""

$templateFile = Join-Path $PSScriptRoot "main.bicep"

az deployment sub create `
    --name $DeploymentName `
    --location $Location `
    --template-file $templateFile `
    --parameters location=$Location resourceGroupName=$ResourceGroupName

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Deployment completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Resources deployed to: $ResourceGroupName" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To view the resources:" -ForegroundColor Gray
    Write-Host "  az resource list --resource-group $ResourceGroupName --output table" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To clean up:" -ForegroundColor Gray
    Write-Host "  az group delete --name $ResourceGroupName --yes --no-wait" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Deployment failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    exit 1
}
