#!/bin/bash

# Variables
RESOURCE_GROUP_NAME="rg-function-unzip-large-files"
FUNCTION_DIR="function-unzip-large-zip-files"

# Get function app name from deployment
echo "Getting function app name..."
FUNCTION_APP_NAME=$(az functionapp list --resource-group $RESOURCE_GROUP_NAME --query "[0].name" -o tsv)

if [ -z "$FUNCTION_APP_NAME" ]; then
    echo "Error: No function app found in resource group $RESOURCE_GROUP_NAME"
    echo "Please run ./deploy-infra.sh first"
    exit 1
fi

echo "Function App Name: $FUNCTION_APP_NAME"

# Install Python dependencies
echo "Installing Python dependencies..."
cd $FUNCTION_DIR
pip install --target=".python_packages/lib/site-packages" -r requirements.txt

# Create deployment package
echo "Creating deployment package..."
zip -r ../function-app.zip . -x "*.env" -x "__pycache__/*" -x ".venv/*" -x ".vscode/*"

# Deploy to Azure
echo "Deploying function to Azure..."
cd ..
az functionapp deployment source config-zip \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $FUNCTION_APP_NAME \
    --src function-app.zip

# Clean up
rm function-app.zip

echo ""
echo "Function deployment completed!"
echo "Your function is now live at: https://$FUNCTION_APP_NAME.azurewebsites.net"
echo ""
echo "To test:"
echo "1. Upload a password-protected ZIP file to the 'zipped' container"
echo "2. The function will automatically extract files to the 'unzipped' container"