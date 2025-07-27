#!/bin/bash

# Variables
RESOURCE_GROUP_NAME="rg-function-unzip-large-files"
LOCATION="eastus"
DEPLOYMENT_NAME="deploy-storage-$(date +%Y%m%d%H%M%S)"

# Create resource group if it doesn't exist
echo "Creating resource group..."
az group create --name $RESOURCE_GROUP_NAME --location $LOCATION

# Deploy the Bicep template
echo "Deploying storage account..."
az deployment group create \
  --name $DEPLOYMENT_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --template-file main.bicep \
  --parameters main.parameters.json

# Get the outputs
echo "Getting deployment outputs..."
STORAGE_ACCOUNT_NAME=$(az deployment group show \
  --name $DEPLOYMENT_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --query properties.outputs.storageAccountName.value -o tsv)

CONNECTION_STRING=$(az deployment group show \
  --name $DEPLOYMENT_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --query properties.outputs.storageAccountConnectionString.value -o tsv)

FUNCTION_APP_NAME=$(az deployment group show \
  --name $DEPLOYMENT_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --query properties.outputs.functionAppName.value -o tsv)

echo ""
echo "Deployment completed successfully!"
echo "Storage Account Name: $STORAGE_ACCOUNT_NAME"
echo "Function App Name: $FUNCTION_APP_NAME"
echo "Connection String: $CONNECTION_STRING"
echo ""
echo "Update your .env file with the connection string above"