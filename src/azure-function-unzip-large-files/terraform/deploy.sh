#!/bin/bash

echo "Initializing Terraform..."
terraform init

echo "Planning Terraform deployment..."
terraform plan

read -p "Do you want to apply these changes? (yes/no): " confirm
if [ "$confirm" == "yes" ]; then
    echo "Applying Terraform configuration..."
    terraform apply -auto-approve
    
    echo ""
    echo "Deployment complete!"
    echo "To get the storage connection string, run:"
    echo "terraform output -raw storage_account_primary_connection_string"
else
    echo "Deployment cancelled."
fi