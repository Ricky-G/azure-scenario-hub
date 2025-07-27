# Variables
$ResourceGroupName = "rg-function-unzip-large-files"
$Location = "eastus2"
$DeploymentName = "deploy-storage-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Create resource group if it doesn't exist
Write-Host "Creating resource group..." -ForegroundColor Green
az group create --name $ResourceGroupName --location $Location

# Deploy the Bicep template
Write-Host "Deploying storage account and function app..." -ForegroundColor Green
$deploymentResult = az deployment group create `
  --name $DeploymentName `
  --resource-group $ResourceGroupName `
  --template-file main.bicep `
  --parameters main.parameters.json

# Check if deployment was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host "Deployment completed successfully! Waiting for outputs to be available..." -ForegroundColor Green
    Start-Sleep -Seconds 10  # Wait for deployment metadata to be available
} else {
    Write-Host "Deployment failed!" -ForegroundColor Red
    exit 1
}

# Get the outputs
Write-Host "Getting deployment outputs..." -ForegroundColor Green

# Try to get outputs with retry logic
$maxRetries = 3
$retryCount = 0

do {
    $retryCount++
    Write-Host "Attempt $retryCount of $maxRetries..." -ForegroundColor Yellow
    
    try {
        $StorageAccountName = az deployment group show `
          --name $DeploymentName `
          --resource-group $ResourceGroupName `
          --query properties.outputs.storageAccountName.value -o tsv 2>$null

        $ConnectionString = az deployment group show `
          --name $DeploymentName `
          --resource-group $ResourceGroupName `
          --query properties.outputs.storageAccountConnectionString.value -o tsv 2>$null

        $FunctionAppName = az deployment group show `
          --name $DeploymentName `
          --resource-group $ResourceGroupName `
          --query properties.outputs.functionAppName.value -o tsv 2>$null

        # Check if we got valid outputs
        if ($StorageAccountName -and $ConnectionString -and $FunctionAppName) {
            break
        }
    }
    catch {
        Write-Host "Error getting deployment outputs: $_" -ForegroundColor Red
    }
    
    if ($retryCount -lt $maxRetries) {
        Write-Host "Waiting 5 seconds before retry..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
} while ($retryCount -lt $maxRetries)

# If we still don't have outputs, try to get them directly from the resources
if (-not $StorageAccountName -or -not $ConnectionString -or -not $FunctionAppName) {
    Write-Host "Could not get deployment outputs, querying resources directly..." -ForegroundColor Yellow
    
    $StorageAccountName = az storage account list --resource-group $ResourceGroupName --query "[0].name" -o tsv
    $FunctionAppName = az functionapp list --resource-group $ResourceGroupName --query "[0].name" -o tsv
    
    if ($StorageAccountName) {
        $ConnectionString = az storage account show-connection-string --name $StorageAccountName --resource-group $ResourceGroupName --query connectionString -o tsv
    }
}

Write-Host ""
Write-Host "Deployment completed successfully!" -ForegroundColor Green
Write-Host "Storage Account Name: $StorageAccountName" -ForegroundColor Yellow
Write-Host "Function App Name: $FunctionAppName" -ForegroundColor Yellow
Write-Host "Connection String: $ConnectionString" -ForegroundColor Yellow
Write-Host ""
Write-Host "Update your .env file with the connection string above" -ForegroundColor Cyan