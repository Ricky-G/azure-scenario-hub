# APIM Monitoring Scenario

Deploys Azure API Management (Developer SKU) with 6 mock APIs, Application Insights, Log Analytics Workspace, and an Azure Workbook dashboard. All APIs run on APIM policies only — no backend services required.

## What Gets Deployed

| Resource | Details |
|---|---|
| API Management | Developer SKU, 1 unit |
| Resource Group | Configurable name, default: `rg-apim-monitoring` |
| Log Analytics Workspace | Central log store for all requests and responses |
| Application Insights | Full request/response capture (bodies up to 8KB) |
| Azure Workbook | Monitoring dashboard with charts and KQL-backed metrics |

### 6 Sample APIs

| API | Path | Policy Feature |
|---|---|---|
| Weather Data | `/weather/{city}` | Response caching |
| Product Search | `/products/search` | Rate limiting (10 req/60s) + quotas |
| User Validation | `/users/validate/{userId}` | JWT validation |
| Currency Conversion | `/currency/convert` | Cache lookup + expressions |
| Health Monitor | `/health` | No auth, plain health check |
| Delay Simulator | `/simulate/delay` | Configurable latency + status codes |

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- PowerShell 7+ or Bash
- An Azure subscription

## Deploy

**PowerShell:**
```powershell
cd bicep
./deploy.ps1
```

**Bash:**
```bash
cd bicep
./deploy.sh
```

The scripts will prompt for a service name and deploy everything. Deployment takes ~45 minutes due to APIM provisioning.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `apimServiceName` | `apim-demo-{unique}` | APIM instance name (must be globally unique) |
| `resourceGroupName` | `rg-apim-monitoring` | Resource group to create |
| `location` | `eastus` | Azure region |
| `publisherEmail` | `admin@example.com` | APIM publisher email |
| `publisherName` | `APIM Demo` | APIM publisher name |
| `enableApplicationInsights` | `true` | Deploy App Insights + Log Analytics + Workbook |

## Test the APIs

Get your subscription key from **Azure Portal → APIM → Subscriptions → Built-in all-access**.

```bash
APIM_URL="https://<your-apim-name>.azure-api.net"
KEY="<your-subscription-key>"

# Cache demo - call twice, second should be faster
curl "$APIM_URL/weather/Seattle" -H "Ocp-Apim-Subscription-Key: $KEY"

# Rate limit demo - call 11+ times in 60s to trigger 429
curl "$APIM_URL/products/search?q=laptop" -H "Ocp-Apim-Subscription-Key: $KEY"

# Currency conversion
curl "$APIM_URL/currency/convert?from=USD&to=EUR&amount=100" -H "Ocp-Apim-Subscription-Key: $KEY"

# Health check (no key required)
curl "$APIM_URL/health"

# Simulate slow response (2s delay)
curl "$APIM_URL/simulate/delay?delay=2000"
```

## Load Testing

Use the included test harness to generate traffic for the monitoring dashboard:

```powershell
cd test-harness

# Copy the example config and fill in your APIM URL and key
Copy-Item config.example.json config.json

# Run a 3-minute load test with 5 concurrent workers
./Start-ApimLoadTest.ps1 -Duration 3 -Concurrency 5
```

See [test-harness/README.md](test-harness/README.md) for full options.

## View Monitoring Data

After traffic is generated:

- **Azure Workbook**: Portal → API Management → `<your-apim>` → Workbooks → *APIM Monitoring Dashboard*
- **Live Metrics**: Portal → Application Insights → Live Metrics
- **Log Analytics**: See [KQL-QUERIES.md](KQL-QUERIES.md) for ready-to-use queries

## Clean Up

```powershell
cd bicep
./cleanup.ps1
```

```bash
cd bicep
./cleanup.sh
```

> **Cost note:** APIM Developer SKU is ~$50/month. Always run cleanup when done.

## File Structure

```
bicep/
  main.bicep              # Subscription-scoped entry point
  main.parameters.json    # Default parameter values
  deploy.ps1 / deploy.sh  # Deployment scripts
  cleanup.ps1 / cleanup.sh
  modules/
    apim.bicep            # APIM service + diagnostics + products
    apim-apis.bicep       # All 6 APIs with policy XML
    app-insights.bicep    # Log Analytics + Application Insights
    apim-workbook.bicep   # Azure Workbook resource
    workbook-template.json
test-harness/
  Start-ApimLoadTest.ps1  # Load test script
  config.example.json     # Config template (copy to config.json)
KQL-QUERIES.md            # KQL query reference for Log Analytics
```
