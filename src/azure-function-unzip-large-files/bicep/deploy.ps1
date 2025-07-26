# Variables
$ResourceGroupName = "rg-function-unzip-large-files"
$Location = "eastus"
$DeploymentName = "deploy-storage-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Create resource group if it doesn't exist
Write-Host "Creating resource group..." -ForegroundColor Green
az group create --name $ResourceGroupName --location $Location

# Deploy the Bicep template
Write-Host "Deploying storage account and function app..." -ForegroundColor Green
az deployment group create `
  --name $DeploymentName `
  --resource-group $ResourceGroupName `
  --template-file main.bicep `
  --parameters main.parameters.json

# Get the outputs
Write-Host "Getting deployment outputs..." -ForegroundColor Green
$StorageAccountName = az deployment group show `
  --name $DeploymentName `
  --resource-group $ResourceGroupName `
  --query properties.outputs.storageAccountName.value -o tsv

$ConnectionString = az deployment group show `
  --name $DeploymentName `
  --resource-group $ResourceGroupName `
  --query properties.outputs.storageAccountConnectionString.value -o tsv

$FunctionAppName = az deployment group show `
  --name $DeploymentName `
  --resource-group $ResourceGroupName `
  --query properties.outputs.functionAppName.value -o tsv

Write-Host ""
Write-Host "Deployment completed successfully!" -ForegroundColor Green
Write-Host "Storage Account Name: $StorageAccountName" -ForegroundColor Yellow
Write-Host "Function App Name: $FunctionAppName" -ForegroundColor Yellow
Write-Host "Connection String: $ConnectionString" -ForegroundColor Yellow
Write-Host ""
Write-Host "Update your .env file with the connection string above" -ForegroundColor Cyan