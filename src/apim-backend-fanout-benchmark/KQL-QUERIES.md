# KQL Queries

Ready-to-paste KQL for analyzing the benchmark results in **Log Analytics** (workspace `log-apimfo-*`) or the **App Insights** instance (`appi-apimfo-*`).

> All queries assume APIM diagnostics with `sampling = 100%` (configured by [`bicep/modules/apim.bicep`](bicep/modules/apim.bicep)).

## 1. Confirm both APIMs hit the same backend instances

```kql
traces
| where timestamp > ago(2h)
| where message startswith "EchoRequest"
| extend instanceId = tostring(customDimensions["instanceId"])
| summarize requests = count(), apims = make_set(cloud_RoleName) by instanceId
| order by requests desc
```

If the `apims` set for each `instanceId` contains both APIM service names, the backend is being shared — which is what the methodology requires.

## 2. APIM overhead per service

See [`test-harness/kql/apim-backend-time.kql`](test-harness/kql/apim-backend-time.kql).

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(2h)
| extend serviceName = tostring(split(_ResourceId, "/")[8])
| summarize
    avg_backend_ms  = avg(BackendTime),
    avg_client_ms   = avg(TotalTime),
    avg_overhead_ms = avg(TotalTime - BackendTime),
    p95_overhead_ms = percentile(TotalTime - BackendTime, 95)
    by serviceName
```

## 3. Per-API p95 latency

See [`test-harness/kql/apim-latency-percentiles.kql`](test-harness/kql/apim-latency-percentiles.kql).

## 4. Failures

See [`test-harness/kql/apim-failures.kql`](test-harness/kql/apim-failures.kql).

## 5. Throughput over time (1-minute buckets)

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(2h)
| extend serviceName = tostring(split(_ResourceId, "/")[8])
| summarize rps = count() / 60.0 by bin(TimeGenerated, 1m), serviceName
| render timechart
```

## 6. Backend time distribution histogram

```kql
ApiManagementGatewayLogs
| where TimeGenerated > ago(2h)
| extend serviceName = tostring(split(_ResourceId, "/")[8])
| summarize count() by serviceName, BackendBucket = bin(BackendTime, 5)
| order by serviceName, BackendBucket
| render columnchart
```
