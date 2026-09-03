#!/bin/bash

# Check if RESOURCE_GROUP is set
if [ -z "$RESOURCE_GROUP" ]; then
  export RESOURCE_GROUP="rg-ais-loadtest"
fi

echo "Testing Azure Integration Services Load Test Deployment"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Get function app names
echo "Getting function app URLs..."
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

echo ""
echo "Testing health endpoints..."
echo "=========================================="

# Test each health endpoint
test_endpoint() {
  local name=$1
  local url=$2
  echo -n "Testing $name... "
  
  response=$(curl -s -o /dev/null -w "%{http_code}" $url)
  if [ "$response" = "200" ]; then
    echo "✓ OK (HTTP $response)"
  else
    echo "✗ FAILED (HTTP $response)"
  fi
}

test_endpoint "Audits Adaptor" "https://$AUDITS_ADAPTOR.azurewebsites.net/api/health"
test_endpoint "Audit Store" "https://$AUDIT_STORE.azurewebsites.net/api/health"
test_endpoint "History Adaptor" "https://$HISTORY_ADAPTOR.azurewebsites.net/api/health"
test_endpoint "History Store" "https://$HISTORY_STORE.azurewebsites.net/api/health"
test_endpoint "Availability Checker" "https://$AVAILABILITY_CHECKER.azurewebsites.net/api/health"

echo ""
echo "Testing message flow..."
echo "=========================================="

# Test audit message flow
echo "Sending test audit message..."
AUDIT_RESPONSE=$(curl -s -X POST https://$AUDITS_ADAPTOR.azurewebsites.net/api/audits \
  -H "Content-Type: application/json" \
  -d '{
    "action": "test.deployment",
    "user": "deployment-script",
    "details": "Testing audit message flow"
  }')

if echo "$AUDIT_RESPONSE" | grep -q "success"; then
  echo "✓ Audit message sent successfully"
  echo "  Response: $AUDIT_RESPONSE"
else
  echo "✗ Failed to send audit message"
fi

echo ""

# Test history message flow
echo "Sending test history message..."
HISTORY_RESPONSE=$(curl -s -X POST https://$HISTORY_ADAPTOR.azurewebsites.net/api/history \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "deployment.test",
    "entityId": "test-123",
    "entityType": "deployment",
    "operation": "create",
    "changes": {
      "after": {
        "status": "deployed",
        "version": "1.0.0"
      }
    }
  }')

if echo "$HISTORY_RESPONSE" | grep -q "success"; then
  echo "✓ History message sent successfully"
  echo "  Response: $HISTORY_RESPONSE"
else
  echo "✗ Failed to send history message"
fi

echo ""
echo "=========================================="
echo "Deployment test complete!"
echo ""
echo "Check Application Insights for:"
echo "  - Function execution logs"
echo "  - Custom events (AuditMessageSent, HistoryMessageSent)"
echo "  - Service Bus message processing"
echo ""