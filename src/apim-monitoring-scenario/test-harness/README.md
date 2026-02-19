# APIM Load Test Harness

Generate realistic API traffic to Azure API Management for monitoring and dashboard testing.

## 📋 Prerequisites

- **PowerShell 7.0+** ([Download](https://learn.microsoft.com/powershell/scripting/install/installing-powershell))
- **Azure API Management instance** with subscription key

## 🚀 Quick Start

### 1. Configure Your APIM Instance

Copy [config.example.json](./config.example.json) to `config.json` and update with your values:

```json
{
  "apimBaseUrl": "https://your-apim-instance.azure-api.net",
  "subscriptionKey": "your-subscription-key-here"
}
```

**Find your values:** Azure Portal → Your APIM → Overview (Gateway URL) / Subscriptions (Key)

⚠️ **Security Note:** `config.json` is git-ignored. Never commit real credentials to version control.

### 2. Run Load Test

```powershell
# Quick test (2 min, 5 users)
.\Start-ApimLoadTest.ps1 -Duration quick -Concurrency light -ShowProgress

# Standard test (5 min, 15 users) 
.\Start-ApimLoadTest.ps1 -Duration standard -Concurrency moderate -ShowProgress

# Extended test (15 min, 30 users)
.\Start-ApimLoadTest.ps1 -Duration extended -Concurrency heavy -ShowProgress

# Custom duration/concurrency
.\Start-ApimLoadTest.ps1 -Duration 10 -Concurrency 20 -ShowProgress
```

## 📊 What Gets Tested

The harness generates realistic traffic across 6 API patterns:

| API | Traffic % | Purpose |
|-----|-----------|---------|
| Weather Data | 25% | Cache hit/miss patterns, response times |
| Product Search | 20% | Rate limiting, throttling (429 errors) |
| User Validation | 15% | Validation errors (4xx responses) |
| Currency Convert | 15% | Cache effectiveness, policy execution |
| Health Monitor | 15% | Fast response baseline, uptime |
| Delay Simulator | 10% | Latency distribution, performance alerts | 

**Generated Metrics:**
- Cache hit ratios and patterns
- Rate limiting (429 throttling errors)
- Validation errors (4xx responses)
- Response time distributions
- Success/failure rates
- Requests per second

## ⚙️ Configuration

### Duration Presets
- `quick` = 2 minutes | `standard` = 5 minutes | `extended` = 15 minutes
- Or use custom number: `-Duration 10`

### Concurrency Presets
- `light` = 5 users | `moderate` = 15 users | `heavy` = 30 users  
- Or use custom number: `-Concurrency 20`

### Advanced Options

```powershell
# Override config values at runtime
.\Start-ApimLoadTest.ps1 `
    -ApimBaseUrl "https://my-apim.azure-api.net" `
    -SubscriptionKey "key123..." `
    -Duration 10 `
    -Concurrency 20

# Use custom config file
.\Start-ApimLoadTest.ps1 -ConfigPath ".\my-config.json"

# Silent mode (no progress output)
.\Start-ApimLoadTest.ps1 -Duration standard -Concurrency moderate
```

## 📈 Viewing Results

After running the test, view metrics in **Azure Portal → Your APIM → Metrics/Analytics**:

- **Requests:** Total volume, success/failure rates
- **Performance:** Response times, latency percentiles (P50, P95, P99)
- **Caching:** Cache hits/misses, hit ratios
- **Errors:** 4xx/5xx distribution, rate limit (429) events
- **APIs:** Usage breakdown by endpoint

## 🔍 Troubleshooting

| Issue | Solution |
|-------|----------|
| PowerShell version error | Install [PowerShell 7.0+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) |
| Config file not found | Run from `test-harness` directory or use `-ConfigPath` |
| Authentication failed (401) | Verify subscription key is correct and has API access |
| Connection timeout | Check APIM URL format and instance availability |
| Low/missing metrics | Run longer test (`-Duration extended`) and wait 2-3 minutes |

## 🎨 Customization

**Add custom APIs** by editing [config.json](./config.json):

```json
{
  "apis": {
    "myApi": {
      "path": "/my/endpoint",
      "method": "GET",
      "weight": 10,
      "description": "Custom API"
    }
  }
}
```

**Adjust traffic distribution** by modifying `weight` values (higher = more traffic).

---

For more details on APIM monitoring, see [Azure API Management Documentation](https://learn.microsoft.com/azure/api-management/).
