# Variables
$ResourceGroupName = "rg-function-unzip-large-files"
$FunctionDir = "function-unzip-large-zip-files"

# Get function app name from deployment
Write-Host "Getting function app name..." -ForegroundColor Green
$FunctionAppName = az functionapp list --resource-group $ResourceGroupName --query "[0].name" -o tsv

if ([string]::IsNullOrEmpty($FunctionAppName)) {
    Write-Host "Error: No function app found in resource group $ResourceGroupName" -ForegroundColor Red
    Write-Host "Please run .\deploy-infra.ps1 first" -ForegroundColor Yellow
    exit 1
}

Write-Host "Function App Name: $FunctionAppName" -ForegroundColor Yellow

# Install Python dependencies
Write-Host "Installing Python dependencies..." -ForegroundColor Green
Set-Location $FunctionDir
pip install --target=".python_packages/lib/site-packages" -r requirements.txt

# Create deployment package
Write-Host "Creating deployment package..." -ForegroundColor Green
Compress-Archive -Path * -DestinationPath ..\function-app.zip -Force -CompressionLevel Optimal `
    -Exclude @("*.env", "__pycache__", ".venv", ".vscode", "*.pyc", "*.pyo")

# Deploy to Azure
Write-Host "Deploying function to Azure..." -ForegroundColor Green
Set-Location ..
az functionapp deployment source config-zip `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --src function-app.zip

# Clean up
Remove-Item function-app.zip

Write-Host ""
Write-Host "Function deployment completed!" -ForegroundColor Green
Write-Host "Your function is now live at: https://$FunctionAppName.azurewebsites.net" -ForegroundColor Yellow
Write-Host ""
Write-Host "To test:" -ForegroundColor Cyan
Write-Host "1. Upload a password-protected ZIP file to the 'zipped' container" -ForegroundColor White
Write-Host "2. The function will automatically extract files to the 'unzipped' container" -ForegroundColor White