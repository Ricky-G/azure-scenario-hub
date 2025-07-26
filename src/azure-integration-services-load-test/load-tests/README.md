# Azure Integration Services Load Testing

This directory contains comprehensive load testing tools for the Azure Integration Services scenario.

## Quick Start

### 1. Install Dependencies

```bash
# Install Python dependencies
pip install locust requests azure-identity azure-monitor-opentelemetry
```

### 2. Set Environment Variables

```bash
# PowerShell
$env:AUDITS_FUNCTION_URL = "https://your-audits-function.azurewebsites.net"
$env:HISTORY_FUNCTION_URL = "https://your-history-function.azurewebsites.net"

# Bash
export AUDITS_FUNCTION_URL="https://your-audits-function.azurewebsites.net"
export HISTORY_FUNCTION_URL="https://your-history-function.azurewebsites.net"
```

### 3. Run Load Tests

#### Option A: Locust (Recommended for comprehensive testing)

```bash
# Basic load test - 10 users, 60 seconds
locust -f locustfile.py --headless -u 10 -r 2 -t 60s

# Peak load test - 50 users, 5 minutes  
locust -f locustfile.py --headless -u 50 -r 5 -t 300s

# Stress test - 100 users, 10 minutes
locust -f locustfile.py --headless -u 100 -r 10 -t 600s

# Interactive mode (with web UI)
locust -f locustfile.py
# Then open http://localhost:8089
```

#### Option B: Azure Load Testing

1. Upload `azure-load-test-config.yaml` to Azure Load Testing
2. Upload `locustfile.py` as the test script
3. Configure environment variables in Azure Load Testing
4. Run the test

#### Option C: PowerShell (Quick validation)

```bash
# Basic endpoint test
./quick-load-test.ps1 -Users 10 -Duration 60

# Stress test
./quick-load-test.ps1 -Users 50 -Duration 300 -IncludeHealthChecks
```

## Test Scenarios

### 1. Baseline Performance Test
- **Users**: 10 concurrent
- **Duration**: 60 seconds
- **Goal**: Establish baseline metrics

### 2. Normal Load Test  
- **Users**: 50 concurrent
- **Duration**: 5 minutes
- **Goal**: Test normal operating conditions

### 3. Peak Load Test
- **Users**: 100 concurrent  
- **Duration**: 10 minutes
- **Goal**: Test peak traffic scenarios

### 4. Stress Test
- **Users**: 200+ concurrent
- **Duration**: 15 minutes
- **Goal**: Find breaking points and scaling limits

## Monitoring Results

### Application Insights Queries

Use these KQL queries in Application Insights to analyze test results:

```kql
// Function execution summary
requests
| where timestamp > ago(30m)
| where name in ("AuditsAdaptor", "HistoryAdaptor")
| summarize 
    RequestCount = count(),
    AvgDuration = avg(duration),
    P95Duration = percentile(duration, 95),
    SuccessRate = avg(toint(success)) * 100
    by name
| order by RequestCount desc

// End-to-end message processing times
customEvents
| where timestamp > ago(30m)
| where name in ("AuditMessageProcessed", "HistoryMessageProcessed")
| extend CorrelationId = tostring(customDimensions.CorrelationId)
| extend ProcessingTime = todouble(customDimensions.ProcessingTimeMs)
| summarize 
    MessageCount = count(),
    AvgProcessingTime = avg(ProcessingTime),
    P95ProcessingTime = percentile(ProcessingTime, 95)
    by name

// Error analysis
exceptions
| where timestamp > ago(30m)
| where cloud_RoleName startswith "func-"
| summarize ErrorCount = count() by cloud_RoleName, type
| order by ErrorCount desc

// Service Bus metrics correlation
customMetrics
| where timestamp > ago(30m)
| where name in ("ServiceBus.MessagesSent", "ServiceBus.MessagesReceived")
| summarize 
    TotalMessages = sum(value)
    by name, bin(timestamp, 1m)
| render timechart
```

### Key Metrics to Monitor

1. **HTTP Response Times**
   - Target: < 500ms for 95% of requests
   - Monitor: Average, P95, P99 response times

2. **Error Rates**
   - Target: < 1% failure rate
   - Monitor: HTTP 4xx/5xx responses, exceptions

3. **End-to-End Latency**
   - Target: < 2 seconds from HTTP request to Service Bus processing
   - Monitor: Custom telemetry events with correlation IDs

4. **Throughput**
   - Monitor: Requests per second, messages per second
   - Compare: HTTP requests vs Service Bus messages processed

5. **Infrastructure Scaling**
   - Monitor: Function app instance count
   - Monitor: EP1 plan CPU/memory utilization
   - Monitor: Service Bus active message count

## Test Data Characteristics

### Audit Payloads
- **Size**: ~1-2KB typical, up to 10KB for stress tests
- **Fields**: auditId, userId, action, timestamp, details, correlationId
- **Frequency**: 70% of total traffic

### History Payloads  
- **Size**: ~2-5KB typical, up to 50KB for stress tests
- **Fields**: historyId, userId, changes array, timestamp, correlationId
- **Frequency**: 30% of total traffic

## Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| HTTP Response Time | < 500ms | 95th percentile |
| Error Rate | < 1% | Overall failure rate |
| E2E Message Latency | < 2s | HTTP to Service Bus processing complete |
| Throughput | 1000+ req/min | Sustained load |
| Cold Start | < 3s | Function initialization time |

## Troubleshooting

### Common Issues

1. **High Response Times**
   - Check: Function cold starts
   - Check: Service Bus throttling
   - Check: EP1 plan scaling behavior

2. **High Error Rates**
   - Check: Function app logs
   - Check: Service Bus dead letter queues
   - Check: Network connectivity to private endpoints

3. **Low Throughput**
   - Check: Function concurrency settings
   - Check: Service Bus message lock duration
   - Check: Application Insights sampling rate

### Debugging Commands

```bash
# Check function app status
az functionapp show --name <function-app-name> --resource-group <rg-name> --query state

# Check Service Bus metrics
az monitor metrics list --resource <servicebus-resource-id> --metric "ActiveMessages"

# Check Application Insights availability
az monitor app-insights component show --app <app-insights-name> --resource-group <rg-name>
```

## Cost Optimization

- Use Azure Load Testing for comprehensive tests (pay-per-use)
- Use Locust for development iterations (free)
- Run intensive tests during off-peak hours
- Clean up test resources after completion
- Use reserved capacity for App Service plans if running regular tests
