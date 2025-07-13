# PowerShell complete deployment script
Write-Host "=========================================="
Write-Host "Azure Integration Services Load Test"
Write-Host "Complete Deployment Script"
Write-Host "=========================================="
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..."
$azInstalled = Get-Command az -ErrorAction SilentlyContinue
$dotnetInstalled = Get-Command dotnet -ErrorAction SilentlyContinue
$funcInstalled = Get-Command func -ErrorAction SilentlyContinue

if (-not $azInstalled) {
    Write-Error "Azure CLI is not installed. Please install it first."
    exit 1
}
if (-not $dotnetInstalled) {
    Write-Error ".NET SDK is not installed. Please install it first."
    exit 1
}
if (-not $funcInstalled) {
    Write-Error "Azure Functions Core Tools is not installed. Please install it first."
    exit 1
}

# Set variables
if ([string]::IsNullOrEmpty($env:RESOURCE_GROUP)) {
    $env:RESOURCE_GROUP = "rg-ais-loadtest"
}
if ([string]::IsNullOrEmpty($env:LOCATION)) {
    $env:LOCATION = "eastus2"
}

Write-Host "Configuration:"
Write-Host "  - Resource Group: $($env:RESOURCE_GROUP)"
Write-Host "  - Location: $($env:LOCATION)"
Write-Host ""

# Login check
Write-Host "Checking Azure login status..."
$account = az account show 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "You need to login to Azure first."
    az login
}

$subscription = az account show --query name -o tsv
Write-Host "Using subscription: $subscription"
Write-Host ""

# Step 1: Deploy Infrastructure
Write-Host "=========================================="
Write-Host "Step 1: Deploying Infrastructure"
Write-Host "=========================================="
Write-Host ""

# Create resource group
Write-Host "Creating resource group..."
az group create --name $env:RESOURCE_GROUP --location $env:LOCATION --output none
Write-Host "Resource group created: $($env:RESOURCE_GROUP)"

# Deploy infrastructure
Write-Host "Deploying infrastructure (this takes ~10-15 minutes)..."
$deploymentResult = az deployment group create `
    --resource-group $env:RESOURCE_GROUP `
    --template-file bicep/main.bicep `
    --parameters location=$env:LOCATION `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Infrastructure deployment failed"
    exit 1
}

Write-Host "Infrastructure deployment complete!"
Write-Host ""

# Step 2: Deploy Functions
Write-Host "=========================================="
Write-Host "Step 2: Deploying Functions"
Write-Host "=========================================="
Write-Host ""

# Run the function deployment script
.\deploy-functions.ps1 -ResourceGroup $env:RESOURCE_GROUP

Write-Host ""
Write-Host "=========================================="
Write-Host "DEPLOYMENT COMPLETE!"
Write-Host "=========================================="
Write-Host ""
Write-Host "Your Azure Integration Services Load Test environment is fully deployed and ready to use!"
Write-Host ""
Write-Host "Resource Group: $($env:RESOURCE_GROUP)"
Write-Host "Location: $($env:LOCATION)"
Write-Host ""
Write-Host "To test the deployment, run:"
Write-Host "  .\test-deployment.ps1"
Write-Host ""
Write-Host "To clean up all resources, run:"
Write-Host "  az group delete --name $($env:RESOURCE_GROUP) --yes --no-wait"
Write-Host ""