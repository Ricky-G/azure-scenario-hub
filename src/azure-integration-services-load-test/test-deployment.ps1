# PowerShell test deployment script
param(
    [string]$ResourceGroup = $env:RESOURCE_GROUP
)

# Check if RESOURCE_GROUP is set
if ([string]::IsNullOrEmpty($ResourceGroup)) {
    $ResourceGroup = "rg-ais-loadtest"
}

Write-Host "Testing Azure Integration Services Load Test Deployment"
Write-Host "Resource Group: $ResourceGroup"
Write-Host ""

# Get function app names
Write-Host "Getting function app URLs..."
$AUDITS_ADAPTOR = az deployment group show -g $ResourceGroup -n main --query 'properties.outputs.auditsAdaptorFunctionName.value' -o tsv
$AUDIT_STORE = az deployment group show -g $ResourceGroup -n main --query 'properties.outputs.auditStoreFunctionName.value' -o tsv
$HISTORY_ADAPTOR = az deployment group show -g $ResourceGroup -n main --query 'properties.outputs.historyAdaptorFunctionName.value' -o tsv
$HISTORY_STORE = az deployment group show -g $ResourceGroup -n main --query 'properties.outputs.historyStoreFunctionName.value' -o tsv
$AVAILABILITY_CHECKER = az deployment group show -g $ResourceGroup -n main --query 'properties.outputs.availabilityCheckerFunctionName.value' -o tsv

Write-Host ""
Write-Host "Testing health endpoints..."
Write-Host "=========================================="

# Test each health endpoint
function Test-Endpoint {
    param($Name, $Url)
    
    Write-Host -NoNewline "Testing $Name... "
    
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Host "✓ OK (HTTP $($response.StatusCode))" -ForegroundColor Green
        } else {
            Write-Host "✗ FAILED (HTTP $($response.StatusCode))" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ FAILED (Error: $($_.Exception.Message))" -ForegroundColor Red
    }
}

Test-Endpoint "Audits Adaptor" "https://$AUDITS_ADAPTOR.azurewebsites.net/api/health"
Test-Endpoint "Audit Store" "https://$AUDIT_STORE.azurewebsites.net/api/health"
Test-Endpoint "History Adaptor" "https://$HISTORY_ADAPTOR.azurewebsites.net/api/health"
Test-Endpoint "History Store" "https://$HISTORY_STORE.azurewebsites.net/api/health"
Test-Endpoint "Availability Checker" "https://$AVAILABILITY_CHECKER.azurewebsites.net/api/health"

Write-Host ""
Write-Host "Testing message flow..."
Write-Host "=========================================="

# Test audit message flow
Write-Host "Sending test audit message..."
$auditBody = @{
    action = "test.deployment"
    user = "deployment-script"
    details = "Testing audit message flow"
} | ConvertTo-Json

try {
    $auditResponse = Invoke-RestMethod -Uri "https://$AUDITS_ADAPTOR.azurewebsites.net/api/audits" `
        -Method Post `
        -ContentType "application/json" `
        -Body $auditBody
    
    if ($auditResponse.success) {
        Write-Host "✓ Audit message sent successfully" -ForegroundColor Green
        Write-Host "  Response: $($auditResponse | ConvertTo-Json -Compress)"
    } else {
        Write-Host "✗ Failed to send audit message" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Failed to send audit message: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test history message flow
Write-Host "Sending test history message..."
$historyBody = @{
    eventType = "deployment.test"
    entityId = "test-123"
    entityType = "deployment"
    operation = "create"
    changes = @{
        after = @{
            status = "deployed"
            version = "1.0.0"
        }
    }
} | ConvertTo-Json -Depth 3

try {
    $historyResponse = Invoke-RestMethod -Uri "https://$HISTORY_ADAPTOR.azurewebsites.net/api/history" `
        -Method Post `
        -ContentType "application/json" `
        -Body $historyBody
    
    if ($historyResponse.success) {
        Write-Host "✓ History message sent successfully" -ForegroundColor Green
        Write-Host "  Response: $($historyResponse | ConvertTo-Json -Compress)"
    } else {
        Write-Host "✗ Failed to send history message" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Failed to send history message: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=========================================="
Write-Host "Deployment test complete!"
Write-Host ""
Write-Host "Check Application Insights for:"
Write-Host "  - Function execution logs"
Write-Host "  - Custom events (AuditMessageSent, HistoryMessageSent)"
Write-Host "  - Service Bus message processing"
Write-Host ""