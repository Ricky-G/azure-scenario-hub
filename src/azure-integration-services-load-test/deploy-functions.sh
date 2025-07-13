#!/bin/bash
set -e

# Check if RESOURCE_GROUP is set
if [ -z "$RESOURCE_GROUP" ]; then
  echo "Error: RESOURCE_GROUP environment variable is not set"
  echo "Please run: export RESOURCE_GROUP=\"rg-ais-loadtest\""
  exit 1
fi

# Get function app names from deployment
echo "Getting function app names from Azure deployment..."
AUDITS_ADAPTOR=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name main \
  --query 'properties.outputs.auditsAdaptorFunctionName.value' -o tsv)

AUDIT_STORE=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name main \
  --query 'properties.outputs.auditStoreFunctionName.value' -o tsv)

HISTORY_ADAPTOR=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name main \
  --query 'properties.outputs.historyAdaptorFunctionName.value' -o tsv)

HISTORY_STORE=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name main \
  --query 'properties.outputs.historyStoreFunctionName.value' -o tsv)

AVAILABILITY_CHECKER=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name main \
  --query 'properties.outputs.availabilityCheckerFunctionName.value' -o tsv)

echo "Function app names retrieved:"
echo "  - Audits Adaptor: $AUDITS_ADAPTOR"
echo "  - Audit Store: $AUDIT_STORE"
echo "  - History Adaptor: $HISTORY_ADAPTOR"
echo "  - History Store: $HISTORY_STORE"
echo "  - Availability Checker: $AVAILABILITY_CHECKER"
echo ""

# Build all functions
echo "Building all functions..."
for func in audits-adaptor audit-store history-adaptor history-store availability-checker; do
  echo "Building $func..."
  (cd functions/$func && dotnet build -c Release) || exit 1
done
echo "All functions built successfully!"
echo ""

# Deploy all functions in parallel
echo "Deploying all functions in parallel..."
(cd functions/audits-adaptor && func azure functionapp publish $AUDITS_ADAPTOR --dotnet-isolated) &
PID1=$!
(cd functions/audit-store && func azure functionapp publish $AUDIT_STORE --dotnet-isolated) &
PID2=$!
(cd functions/history-adaptor && func azure functionapp publish $HISTORY_ADAPTOR --dotnet-isolated) &
PID3=$!
(cd functions/history-store && func azure functionapp publish $HISTORY_STORE --dotnet-isolated) &
PID4=$!
(cd functions/availability-checker && func azure functionapp publish $AVAILABILITY_CHECKER --dotnet-isolated) &
PID5=$!

# Wait for all deployments to complete
echo "Waiting for all deployments to complete..."
wait $PID1 $PID2 $PID3 $PID4 $PID5

echo ""
echo "=========================================="
echo "All functions deployed successfully!"
echo "=========================================="
echo ""
echo "Your Azure Integration Services Load Test environment is ready!"
echo ""
echo "Test the deployment by visiting:"
echo "  - Audits API: https://$AUDITS_ADAPTOR.azurewebsites.net/api/health"
echo "  - Audit Store: https://$AUDIT_STORE.azurewebsites.net/api/health"
echo "  - History API: https://$HISTORY_ADAPTOR.azurewebsites.net/api/health"
echo "  - History Store: https://$HISTORY_STORE.azurewebsites.net/api/health"
echo "  - Availability: https://$AVAILABILITY_CHECKER.azurewebsites.net/api/health"
echo ""