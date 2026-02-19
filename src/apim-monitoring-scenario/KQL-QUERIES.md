# KQL Queries for APIM Incident Tracking

This document provides KQL queries for tracking and troubleshooting API requests in Log Analytics Workspace.

## 📊 Overview

All APIM request/response data is logged to the Application Insights workspace, which stores data in your Log Analytics Workspace. The primary table for API request tracking is `requests`.

## 🔍 Basic Incident Tracking Queries

### 1. Find Requests by Time Range with Full Details

```kusto
requests
| where timestamp between (datetime('2024-01-15 10:00:00') .. datetime('2024-01-15 11:00:00'))
| where cloud_RoleName == "your-apim-name"  // Your APIM service name
| project 
    timestamp,
    name,                          // API operation name
    url,                           // Full request URL
    resultCode,                    // HTTP status code
    duration,                      // Request duration in ms
    success,                       // true/false
    operation_Id,                  // Correlation ID for tracing
    customDimensions.Request,      // Request body (first 8KB)
    customDimensions.Response      // Response body (first 8KB)
| order by timestamp desc
```

### 2. Track Specific Request by Correlation ID

```kusto
requests
| where operation_Id == "your-correlation-id-here"
| project 
    timestamp,
    name,
    url,
    resultCode,
    duration,
    customDimensions.Request,
    customDimensions.Response,
    customDimensions
| extend RequestBody = tostring(customDimensions.Request)
| extend ResponseBody = tostring(customDimensions.Response)
```

### 3. Find Failed Requests with Request/Response Details

```kusto
requests
| where timestamp > ago(24h)
| where success == false
| project 
    timestamp,
    name,
    url,
    resultCode,
    duration,
    RequestBody = tostring(customDimensions['Request-Body']),
    ResponseBody = tostring(customDimensions['Response-Body']),
    ClientIP = client_IP,
    UserAgent = tostring(customDimensions['User-Agent'])
| order by timestamp desc
```

### 4. Search by Specific Request Content

```kusto
requests
| where timestamp > ago(7d)
| extend RequestBody = tostring(customDimensions['Request-Body'])
| extend ResponseBody = tostring(customDimensions['Response-Body'])
| where RequestBody contains "search-term" or ResponseBody contains "search-term"
| project 
    timestamp,
    name,
    url,
    resultCode,
    RequestBody,
    ResponseBody
```

### 5. Complete Incident Investigation Query

```kusto
// Perfect for support incidents - gives you everything in one view
requests
| where timestamp between (datetime('2024-01-15 10:30:00') .. datetime('2024-01-15 10:35:00'))
| project 
    // Timing
    Timestamp = timestamp,
    Duration_ms = duration,
    
    // Request Info
    API_Operation = name,
    HTTP_Method = tostring(customDimensions['Request-Method']),
    Request_URL = url,
    
    // Response Info
    HTTP_Status = resultCode,
    Success = success,
    
    // Payloads
    Request_Body = tostring(customDimensions['Request-Body']),
    Response_Body = tostring(customDimensions['Response-Body']),
    
    // Headers
    Content_Type = tostring(customDimensions['Content-Type']),
    User_Agent = tostring(customDimensions['User-Agent']),
    
    // Tracking
    Correlation_ID = operation_Id,
    Client_IP = client_IP,
    
    // All Custom Dimensions (for deep dive)
    All_Details = customDimensions
| order by Timestamp desc
```

## 📈 Performance Analysis Queries

### 6. Slow Requests with Details

```kusto
requests
| where timestamp > ago(1h)
| where duration > 1000  // Requests slower than 1 second
| project 
    timestamp,
    name,
    url,
    duration,
    resultCode,
    RequestBody = tostring(customDimensions['Request-Body']),
    ResponseBody = tostring(customDimensions['Response-Body'])
| order by duration desc
| take 50
```

### 7. API Performance Summary

```kusto
requests
| where timestamp > ago(24h)
| summarize 
    TotalRequests = count(),
    SuccessRate = countif(success == true) * 100.0 / count(),
    AvgDuration = avg(duration),
    P50Duration = percentile(duration, 50),
    P95Duration = percentile(duration, 95),
    P99Duration = percentile(duration, 99),
    FailedRequests = countif(success == false)
    by bin(timestamp, 1h), name
| order by timestamp desc
```

## 🔎 Advanced Correlation Queries

### 8. Trace Full Request Journey (APIM + Dependencies)

```kusto
// Get all telemetry for a specific operation
union requests, dependencies, traces, exceptions
| where operation_Id == "your-correlation-id"
| project 
    timestamp,
    itemType,
    name,
    resultCode,
    duration,
    message,
    customDimensions
| order by timestamp asc
```

### 9. Find Requests by Specific User/Client

```kusto
requests
| where timestamp > ago(7d)
| where client_IP == "203.0.113.45"  // Specific IP
// OR
// | where tostring(customDimensions['User-Agent']) contains "Mozilla"
| project 
    timestamp,
    name,
    url,
    resultCode,
    client_IP,
    UserAgent = tostring(customDimensions['User-Agent']),
    RequestBody = tostring(customDimensions['Request-Body'])
| order by timestamp desc
```

## 🎯 Specific Support Incident Scenarios

### 10. "Customer says they got an error at approximately 10:30 AM"

```kusto
requests
| where timestamp between (datetime('2024-01-15 10:25:00') .. datetime('2024-01-15 10:35:00'))
| where success == false
| project 
    timestamp,
    API = name,
    URL = url,
    StatusCode = resultCode,
    Duration_ms = duration,
    ClientIP = client_IP,
    Request = tostring(customDimensions['Request-Body']),
    Response = tostring(customDimensions['Response-Body']),
    ErrorDetails = tostring(customDimensions)
| order by timestamp desc
```

### 11. "Find all requests for user ID abc123"

```kusto
requests
| where timestamp > ago(30d)
| extend RequestBody = tostring(customDimensions['Request-Body'])
| extend ResponseBody = tostring(customDimensions['Response-Body'])
| where RequestBody contains "abc123" or url contains "abc123"
| project 
    timestamp,
    name,
    url,
    resultCode,
    RequestBody,
    ResponseBody
| order by timestamp desc
```

### 12. Export Data for External Analysis

```kusto
requests
| where timestamp > ago(1h)
| project 
    Timestamp = format_datetime(timestamp, 'yyyy-MM-dd HH:mm:ss.fff'),
    API = name,
    Method = tostring(customDimensions['Request-Method']),
    URL = url,
    StatusCode = resultCode,
    Duration_ms = duration,
    Success = success,
    Request = tostring(customDimensions['Request-Body']),
    Response = tostring(customDimensions['Response-Body']),
    ClientIP = client_IP,
    CorrelationID = operation_Id
// Can export to CSV from Azure Portal
```

## 🛡️ Security & Compliance Queries

### 13. Audit Trail - All API Access

```kusto
requests
| where timestamp > ago(7d)
| project 
    timestamp,
    API = name,
    Method = tostring(customDimensions['Request-Method']),
    URL = url,
    StatusCode = resultCode,
    ClientIP = client_IP,
    UserAgent = tostring(customDimensions['User-Agent']),
    CorrelationID = operation_Id
| order by timestamp desc
```

### 14. Detect Anomalous Traffic Patterns

```kusto
requests
| where timestamp > ago(1h)
| summarize 
    RequestCount = count(),
    UniqueIPs = dcount(client_IP),
    FailureRate = countif(success == false) * 100.0 / count()
    by bin(timestamp, 5m), name
| where RequestCount > 100 or FailureRate > 10
| order by timestamp desc
```

## 💡 Tips for Effective Incident Tracking

### Key Fields Reference:
- **`timestamp`** - When the request occurred (UTC)
- **`name`** - API operation name
- **`url`** - Full request URL (including query parameters)
- **`resultCode`** - HTTP status code (200, 404, 500, etc.)
- **`duration`** - Request duration in milliseconds
- **`success`** - Boolean indicating if request was successful
- **`operation_Id`** - Unique correlation ID (same across related telemetry)
- **`client_IP`** - Client IP address
- **`customDimensions['Request-Body']`** - Request payload (first 8KB)
- **`customDimensions['Response-Body']`** - Response payload (first 8KB)

### Best Practices:
1. **Always use time ranges** - Narrow your search to reduce query cost
2. **Use correlation IDs** - Track requests across multiple systems
3. **Filter by API operation** - Focus on specific APIs for performance
4. **Extract custom dimensions** - Use `tostring()` to parse JSON in customDimensions
5. **Create workbook dashboards** - Pin frequently used queries for quick access

## 🚀 Create a Workbook for Real-Time Monitoring

You can create an Azure Workbook with these queries for a real-time dashboard:

1. Go to Azure Portal → Your Log Analytics Workspace
2. Click "Workbooks" → "New"
3. Add query tiles using the queries above
4. Create visualizations (time charts, grids, pie charts)
5. Save and share with your team

## 📱 Set Up Alerts

Create alerts for critical scenarios:

```kusto
// Alert when error rate exceeds 5% in 5 minutes
requests
| where timestamp > ago(5m)
| summarize 
    Total = count(),
    Failures = countif(success == false)
| extend ErrorRate = (Failures * 100.0) / Total
| where ErrorRate > 5
```

---

## 🔗 Related Resources

- [Log Analytics Workspace Overview](https://docs.microsoft.com/azure/azure-monitor/logs/log-analytics-workspace-overview)
- [KQL Quick Reference](https://docs.microsoft.com/azure/data-explorer/kql-quick-reference)
- [APIM Diagnostic Logs](https://docs.microsoft.com/azure/api-management/diagnostic-logs-reference)
- [Application Insights Data Model](https://docs.microsoft.com/azure/azure-monitor/app/data-model)

