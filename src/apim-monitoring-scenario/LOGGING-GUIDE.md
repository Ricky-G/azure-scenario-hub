# APIM Logging & Monitoring Guide

## 📊 What's Being Logged

Your APIM instance is now configured with **comprehensive diagnostic logging** to Application Insights.

### Captured Data:
- ✅ **Full Request Bodies** (up to 8KB)
- ✅ **Full Response Bodies** (up to 8KB)
- ✅ **Request Headers** (Content-Type, User-Agent, Authorization)
- ✅ **Response Headers** (Content-Type, Content-Length)
- ✅ **Client IP Addresses**
- ✅ **Request/Response Duration**
- ✅ **Status Codes**
- ✅ **All Errors** (automatically logged)
- ✅ **100% Sampling** (all requests captured)

## 🔍 Viewing Logs in Log Analytics Workspace

### Access Your Logs:
1. **Azure Portal** → **Log Analytics workspace** → **log-appi-{your-apim-instance}**
2. Click **Logs** (under General)
3. Run KQL queries below

### Useful KQL Queries:

#### View All Recent API Requests
```kql
AppRequests
| where TimeGenerated > ago(1h)
| project TimeGenerated, Name, Url, ResultCode, DurationMs, ClientIP
| order by TimeGenerated desc
```

#### View Requests with Full Request/Response Bodies
```kql
AppDependencies
| where TimeGenerated > ago(1h)
| extend RequestBody = tostring(Properties.RequestBody)
| extend ResponseBody = tostring(Properties.ResponseBody)
| project TimeGenerated, Name, Data, ResultCode, DurationMs, RequestBody, ResponseBody
| order by TimeGenerated desc
```

#### View Only Failed Requests (4xx, 5xx)
```kql
AppRequests
| where TimeGenerated > ago(1h)
| where ResultCode >= 400
| project TimeGenerated, Name, Url, ResultCode, DurationMs
| order by TimeGenerated desc
```

#### View Requests by API
```kql
AppRequests
| where TimeGenerated > ago(1h)
| summarize Count=count(), AvgDuration=avg(DurationMs) by Name
| order by Count desc
```

#### View Request/Response Details for Specific API
```kql
AppDependencies
| where TimeGenerated > ago(1h)
| where Name contains "weather-api"
| extend RequestBody = tostring(Properties.RequestBody)
| extend ResponseBody = tostring(Properties.ResponseBody)
| project TimeGenerated, Name, ResultCode, RequestBody, ResponseBody
```

#### Performance Analysis - Slowest APIs
```kql
AppRequests
| where TimeGenerated > ago(24h)
| summarize 
    Count=count(),
    AvgDuration=avg(DurationMs),
    P50=percentile(DurationMs, 50),
    P95=percentile(DurationMs, 95),
    P99=percentile(DurationMs, 99)
    by Name
| order by P95 desc
```

#### Error Breakdown by API
```kql
AppRequests
| where TimeGenerated > ago(24h)
| summarize 
    TotalRequests=count(),
    FailedRequests=countif(Success == false),
    FailureRate=100.0*countif(Success == false)/count()
    by Name
| order by FailureRate desc
```

#### View Raw Traces from APIM Policies
```kql
AppTraces
| where TimeGenerated > ago(1h)
| where Message contains "Request" or Message contains "Response"
| project TimeGenerated, SeverityLevel, Message, Properties
| order by TimeGenerated desc
```

## 📈 In Application Insights

You can also view the same data in Application Insights:

**Portal** → **Application Insights** → **appi-{your-apim-instance}**

### Useful Views:
- **Live Metrics**: Real-time request monitoring
- **Transaction Search**: Search individual requests
- **Performance**: Analyze operation performance
- **Failures**: View all failed requests
- **Logs**: Run KQL queries (same as LAW)

## 🎯 What Each API Logs

All 6 APIs log the following automatically:

1. **Weather API** (`/weather/{city}`)
   - Cached responses demonstration
   - Request: City parameter
   - Response: Temperature, conditions, humidity

2. **Product Search API** (`/products/search`)
   - Rate limiting demonstration (10 calls/minute)
   - Request: Query parameters
   - Response: Product list

3. **User Validation API** (`/users/validate/{userId}`)
   - JWT validation demonstration
   - Request: User ID, Authorization header
   - Response: User validation result

4. **Currency Conversion API** (`/currency/convert`)
   - Cache lookup demonstration
   - Request: From/to currencies, amount
   - Response: Converted amount

5. **Health Monitor API** (`/health`)
   - Simple health check (no auth required)
   - Request: None
   - Response: Health status

6. **Delay Simulator API** (`/simulate/delay`)
   - Performance testing tool
   - Request: delay (ms), status parameters
   - Response: Simulated response

## ⚙️ Configuration Details

The logging configuration is stored in `apim-diagnostic.json`:

```json
{
  "logClientIp": true,
  "verbosity": "information",
  "sampling": {
    "samplingType": "fixed",
    "percentage": 100
  },
  "frontend": {
    "request": { "body": { "bytes": 8192 } },
    "response": { "body": { "bytes": 8192 } }
  },
  "backend": {
    "request": { "body": { "bytes": 8192 } },
    "response": { "body": { "bytes": 8192 } }
  }
}
```

**Note**: 8192 bytes (8KB) is the maximum allowed by APIM for request/response body capture.

## 🔄 Reapplying Configuration

To update the logging configuration:

```powershell
cd src/apim-monitoring-scenario/bicep
az rest --method put `
  --uri "/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.ApiManagement/service/{apim-instance-name}/diagnostics/applicationinsights?api-version=2023-05-01-preview" `
  --body '@apim-diagnostic.json'
```

## 📝 Log Retention

- **Application Insights**: 90 days (default)
- **Log Analytics Workspace**: Configurable (default 30 days)

To extend retention:
- Portal → Log Analytics workspace → Usage and estimated costs → Data Retention

## 📊 Cost Considerations

Enhanced logging captures more data which increases costs:
- **Data Ingestion**: ~$2.76/GB
- **Data Retention**: Based on retention period
- **Expected Volume**: Varies by API traffic

Monitor costs at: Portal → Log Analytics workspace → Usage and estimated costs

---

**Last Updated**: February 13, 2026  
**APIM Instance**: {your-apim-instance}  
**Application Insights**: appi-{your-apim-instance}  
**Log Analytics**: log-appi-{your-apim-instance}
