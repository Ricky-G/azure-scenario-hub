#!/bin/bash

echo "========================================"
echo "Deploying Infrastructure using Bicep"
echo "========================================"

cd bicep
./deploy.sh
cd ..

echo ""
echo "Infrastructure deployment completed!"
echo "You can now deploy the function app using ./deploy-function.sh"