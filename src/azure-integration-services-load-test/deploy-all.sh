#!/bin/bash
set -e

echo "=========================================="
echo "Azure Integration Services Load Test"
echo "Complete Deployment Script"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v az >/dev/null 2>&1 || { echo "Error: Azure CLI is not installed. Please install it first."; exit 1; }
command -v dotnet >/dev/null 2>&1 || { echo "Error: .NET SDK is not installed. Please install it first."; exit 1; }
command -v func >/dev/null 2>&1 || { echo "Error: Azure Functions Core Tools is not installed. Please install it first."; exit 1; }

# Set variables
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ais-loadtest}"
export LOCATION="${LOCATION:-eastus2}"

echo "Configuration:"
echo "  - Resource Group: $RESOURCE_GROUP"
echo "  - Location: $LOCATION"
echo ""

# Login check
echo "Checking Azure login status..."
if ! az account show >/dev/null 2>&1; then
  echo "You need to login to Azure first."
  az login
fi

SUBSCRIPTION=$(az account show --query name -o tsv)
echo "Using subscription: $SUBSCRIPTION"
echo ""

# Step 1: Deploy Infrastructure
echo "=========================================="
echo "Step 1: Deploying Infrastructure"
echo "=========================================="
echo ""

# Create resource group
echo "Creating resource group..."
az group create --name $RESOURCE_GROUP --location $LOCATION --output none
echo "Resource group created: $RESOURCE_GROUP"

# Deploy infrastructure
echo "Deploying infrastructure (this takes ~10-15 minutes)..."
DEPLOYMENT_OUTPUT=$(az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file bicep/main.bicep \
  --parameters location=$LOCATION \
  --output json)

if [ $? -ne 0 ]; then
  echo "Error: Infrastructure deployment failed"
  exit 1
fi

echo "Infrastructure deployment complete!"
echo ""

# Step 2: Deploy Functions
echo "=========================================="
echo "Step 2: Deploying Functions"
echo "=========================================="
echo ""

# Run the function deployment script
./deploy-functions.sh

echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
echo "Your Azure Integration Services Load Test environment is fully deployed and ready to use!"
echo ""
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo ""
echo "To test the deployment, run:"
echo "  ./test-deployment.sh"
echo ""
echo "To clean up all resources, run:"
echo "  az group delete --name $RESOURCE_GROUP --yes --no-wait"
echo ""