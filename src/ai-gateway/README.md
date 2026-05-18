# AI Gateway Scenario (APIM in front of Azure AI Foundry)

> **Want to demo it?** Open
> [`AI-Gateway-Walkthrough.ipynb`](AI-Gateway-Walkthrough.ipynb) in VS Code
> (with the **Polyglot Notebooks** extension). Each section is a working
> PowerShell cell you can run live to demonstrate the gateway end-to-end.

A demo-ready Azure scenario that re-creates the most useful patterns from the
[AI Hub Gateway Solution Accelerator](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator)
using a single Azure API Management instance in front of an **existing**
Azure AI Foundry / Azure OpenAI account.

The goal is a customer-ready demo where you can:

1. Show APIM fronting Foundry models behind **two clearly-labelled customer
   APIs** — `Azure OpenAI - Australia East` and `Azure OpenAI - Global` — so
   the caller sees exactly which route to use for their data-residency or
   latency requirement, while the gateway abstracts away the actual backend.
2. Show APIM's **backend pool** with primary + secondary members, **circuit
   breakers** and automatic priority-based failover.
3. Show that the caller never holds an Azure OpenAI key — APIM authenticates
   to Foundry with its **system-assigned managed identity**.
4. Show **per-app / per-route token charge-back** in Application Insights and
   Log Analytics with rich KQL queries.
5. Show **per-product Tokens-Per-Minute throttling** kicking in independently
   for different business apps.
6. Show **response caching** delivering sub-second responses for repeat
   identical requests, with a `x-ai-gateway-cache: HIT|MISS` header so
   callers can see it.
7. Show **graceful 5xx fallback** via a structured mock response so client
   apps degrade cleanly when the model backend is unavailable.
8. Show **request validation, structured tracing, diagnostic logging** and
   **CORS** for browser-based clients.

> Production note: this scenario uses the APIM **Developer SKU** with a
> public-network deployment so you can stand it up in ~30 minutes. For
> production, follow the
> [AI Hub Gateway Landing Zone](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator)
> patterns (private endpoints, BYOVNET, Premium SKU, multi-region etc.).

---

## Architecture

```
                                     ┌────────────────────────────────────┐
                                     │           APIM (AI Gateway)        │
                                     │                                    │
                                     │  ┌──────────────────────────────┐  │
   App / harness                     │  │  CORS + service-level policy │  │
   sends api-key + body ────────────▶│  └─────────────┬────────────────┘  │
                                     │                ▼                   │
                  ┌──────────────────┤  ┌──────────────────────────────┐  │
                  │                  │  │ Azure OpenAI - Australia East│──┼──┐ MI
                  │                  │  │ /aue/openai/...              │  │  │
                  │                  │  └──────────────────────────────┘  │  │
                  │                  │  ┌──────────────────────────────┐  │  ▼
                  │                  │  │ Azure OpenAI - Global        │──┼─▶  Backend pool
                  │                  │  │ /global/openai/...           │  │   (primary + secondary)
                  │                  │  └──────────────────────────────┘  │   with circuit breakers
                  │                  └────────────────┬───────────────────┘   │
                  ▼                                   ▼                       ▼
        x-ai-gateway-route        Application       Log                  Azure AI Foundry
        x-ai-gateway-cache        Insights        Analytics              (gpt-4.1, gpt-4.1-mini, ...)
        x-ai-gateway-fallback     (metrics +      (gateway logs)
                                   traces)
```

What APIM does on every call:

| Stage    | Policy                                  | Purpose                                                                |
| -------- | --------------------------------------- | ---------------------------------------------------------------------- |
| service  | `cors`                                  | Allow browser-based clients to call the gateway.                       |
| inbound  | `set-variable apiRoute / apiRegion`     | Tag the call with the route the customer chose (per-API).              |
| inbound  | `validate body / messages array`        | Reject malformed chat requests at the edge with 400.                   |
| inbound  | streaming detection                     | Decide cache + buffering.                                              |
| inbound  | `cache-lookup` (frag)                   | Body-hash response cache; HIT short-circuits the call.                 |
| inbound  | `set-variable appId / useCase`          | Per-product policy tags caller business identity.                      |
| inbound  | `set-header api-key exists-action=delete` | Strip caller key — never forwarded.                                  |
| inbound  | `authentication-managed-identity`       | Get a Cognitive Services token on behalf of APIM's MI.                 |
| inbound  | `azure-openai-token-limit`              | Per-product TPM throttling (different limits per business app).        |
| inbound  | `azure-openai-emit-token-metric`        | Push token metrics with App ID / Use Case / Route / Region dimensions. |
| inbound  | `set-backend-service backend-id="openai-backend-pool"` | Routes to backend pool with circuit-breaker failover.   |
| outbound | `set-header x-ai-gateway-route/-region` | Stamp the response so callers see which APIM route handled them.       |
| outbound | `<trace>` via `frag-openai-usage`       | Structured per-call event in `traces` table for KQL.                   |
| outbound | `cache-store` (frag)                    | Persist response in APIM internal cache (5 min TTL).                   |
| on-error | `<trace>` via `frag-throttling-events`  | 429 events captured for alerting / KQL.                                |
| on-error | `frag-mock-fallback`                    | Graceful 503 mock response when backend pool is unhealthy.             |

---

## Customer-facing APIs

Two APIs share the same backend pool but are presented to callers as
distinct routes. The customer points their AOAI SDK at one base URL or the
other depending on use case:

| API                            | Base URL                                              | Tags                                                | Intended use                              |
| ------------------------------ | ----------------------------------------------------- | --------------------------------------------------- | ----------------------------------------- |
| `azure-openai-aue` (AU East)   | `https://<gateway>/aue/openai/...`                    | `region-australia-east`, `data-residency-au`        | Workloads requiring AU data residency.    |
| `azure-openai-global` (Global) | `https://<gateway>/global/openai/...`                 | `region-global`                                     | Cross-region / latency-tolerant workloads.|

Both APIs:

* Re-use **the same backend pool** (`openai-backend-pool`) which routes
  priority-1 → `openai-backend-primary`, falling back to priority-2
  `openai-backend-secondary` when the primary's circuit breaker trips.
* Carry the same APIM Products / subscriptions, so a single subscription
  key works against either route.
* Stamp the response with `x-ai-gateway-route: aue|global` and
  `x-ai-gateway-region: australiaeast|global` so the client (or a customer
  in a demo) can prove which gateway route served the call.

---

## Prerequisites

| Requirement                | Notes                                                                                  |
| -------------------------- | -------------------------------------------------------------------------------------- |
| Azure CLI 2.60+            | `az upgrade` if older.                                                                 |
| PowerShell 7.0+            | For the deploy + harness scripts.                                                      |
| Bicep 0.27+                | Bundled with Azure CLI (`az bicep upgrade`).                                           |
| Owner/Contributor + UAA    | Need permission to create role assignments at the Foundry resource group.              |
| Existing Foundry account   | The scenario expects an existing `Microsoft.CognitiveServices/accounts` (kind=AIServices or OpenAI) with at least one chat model deployed (e.g. `gpt-4.1`, `gpt-4.1-mini`). |

---

## Quick start

```powershell
cd src/ai-gateway

./deploy-infra.ps1 `
    -Location swedencentral `
    -ResourceGroupName rg-ai-gateway-demo `
    -FoundryResourceGroupName <foundry-resource-group> `
    -FoundryAccountName <your-foundry-account> `
    -OpenAiEndpoint 'https://<your-foundry-account>.cognitiveservices.azure.com/' `
    -PublisherEmail you@example.com
```

The deployment provisions:

* APIM Developer + Application Insights + Log Analytics.
* `Cognitive Services User` role for APIM's MI on the Foundry account.
* Service-level policy with CORS.
* All 5 policy fragments (`ai-gateway-openai-usage`,
  `ai-gateway-throttling-events`, `ai-gateway-cache-lookup`,
  `ai-gateway-cache-store`, `ai-gateway-mock-fallback`).
* Backend pool (primary + secondary, both pointing at the Foundry endpoint
  in this single-Foundry demo) with per-member circuit breakers.
* Two APIs (`azure-openai-aue`, `azure-openai-global`) with three operations
  each (chat completions / completions / embeddings) and tags for the
  developer portal.
* Three demo APIM Products + subscriptions (see the `products` array in
  `bicep/main.bicep`):

  | Product                     | App ID            | Use Case          | TPM ceiling |
  | --------------------------- | ----------------- | ----------------- | ----------- |
  | `retail-smart-shopping`     | `retail-app-001`  | `retail-shopping` | 20 000      |
  | `customer-care-chat`        | `care-chat-001`   | `customer-care`   | 10 000      |
  | `finance-smart-analysis`    | `finance-agent-001`| `finance-analysis`| 5 000      |

APIM provisioning takes 25-40 minutes on first deployment. Subsequent
deploys (policy changes, etc.) take ~1 minute.

### Drive demo traffic across both APIs

```powershell
./test-harness/Invoke-Demo.ps1 `
    -ResourceGroupName rg-ai-gateway-demo `
    -ApimName <apim-name> `
    -CallsPerProduct 3 `
    -Route both
```

The harness:

* Fetches the APIM gateway URL and per-product subscription keys via REST.
* For each product, sends `CallsPerProduct` chat completions to each of the
  two routes (`aue`, `global`).
* Adds `x-session-id` and `x-user-id` headers so the policies attach those
  to every telemetry record.
* Reads the APIM-injected response headers (`x-ai-gateway-route`,
  `x-ai-gateway-cache`) and prints them per-call so you can confirm which
  route served each request and whether the cache HIT.

### Show the response cache

```powershell
./test-harness/Invoke-Cache.ps1 `
    -ResourceGroupName rg-ai-gateway-demo `
    -ApimName <apim-name> `
    -Route aue
```

Sends an identical request three times. Expect:

```
call 1  cache=MISS  duration=~1500ms  tokens=50  '...real response...'
call 2  cache=HIT   duration=~600ms   tokens=50  '...same response...'
call 3  cache=HIT   duration=~700ms   tokens=50  '...same response...'
```

### Trip the per-product TPM throttle

```powershell
./test-harness/Invoke-Throttle.ps1 `
    -ResourceGroupName rg-ai-gateway-demo `
    -ApimName <apim-name> `
    -Product finance-smart-analysis `
    -Calls 30
```

Sends large prompts for `finance-smart-analysis` (5 000 TPM) until APIM's
`azure-openai-token-limit` returns 429. The 429s are captured by
`frag-throttling-events.xml` and visible via `kql/throttling-events.kql`.

### Inspect the data

Open Application Insights → **Logs** and run the queries in:

* [`kql/charge-back-by-app.kql`](kql/charge-back-by-app.kql) — token
  consumption + cost-estimate per app / use case / route / region, plus a
  cache-hit-rate query.
* [`kql/throttling-events.kql`](kql/throttling-events.kql) — 429 events
  per product, time-series.
* [`kql/apim-gateway-requests.kql`](kql/apim-gateway-requests.kql) — APIM
  gateway logs (latency p50/p90/p99, response codes).

---

## Verified end-to-end

This scenario has been deployed and exercised against a real Azure AI Foundry
account with `gpt-4.1` and `gpt-4.1-mini` deployments. Confirmed working:

| Capability | Verification |
| ---------- | ------------ |
| Two customer-facing APIs | `https://<gateway>/aue/openai/...` and `.../global/openai/...` both route to the backend pool and return 200. |
| Subscription-key auth | Per-product subscription keys retrieved via REST and accepted via `api-key` header. |
| Strip-key + MI backend auth | Caller `api-key` header removed; APIM MI auths to Foundry via `Cognitive Services User`. |
| Backend pool routing + circuit breaker | `openai-backend-pool` with priority-1 primary + priority-2 secondary configured; circuit breakers active on each member. |
| `azure-openai-token-limit` (per product) | 9/12 calls throttled with 429 once `finance-smart-analysis` (5K TPM) ceiling tripped. |
| `azure-openai-emit-token-metric` -> `customMetrics` | Per-app totals appear with `App ID`, `Use Case`, `Product Name`, `Deployment`, `Route`, `Region Label` dimensions. |
| Structured trace charge-back | `traces` table populated with `apiRoute`, `apiRegion`, model, token counts. |
| Response cache | Repeat identical requests across either route return `x-ai-gateway-cache: HIT` in <1s, with no token charge. |
| 429 trace events | `ai-gateway-throttling-event` logged per throttled request with `retryAfter`. |
| CORS at service level | `Access-Control-Allow-Origin: *` returned on OPTIONS preflights. |
| APIM gateway logs -> Log Analytics | `ApiManagementGatewayLogs`, `AppRequests`, `AppDependencies` populated. |

---

## What gets deployed

| Resource type                                        | Purpose                                                       |
| ---------------------------------------------------- | ------------------------------------------------------------- |
| `Microsoft.Resources/resourceGroups`                 | Container for the gateway resources.                          |
| `Microsoft.OperationalInsights/workspaces`           | Stores APIM gateway logs (`ApiManagementGatewayLogs`).        |
| `Microsoft.Insights/components`                      | Application Insights for token metrics + structured traces.   |
| `Microsoft.ApiManagement/service` (Developer)        | The AI Gateway with system-assigned MI.                       |
| `Microsoft.ApiManagement/service/loggers`            | App Insights logger used by the API diagnostic.               |
| `Microsoft.ApiManagement/service/policies` (service) | Service-level CORS.                                           |
| `Microsoft.ApiManagement/service/backends` x2        | `openai-backend-primary`, `openai-backend-secondary` (Single).|
| `Microsoft.ApiManagement/service/backends` (Pool)    | `openai-backend-pool` (priority-based + circuit breaker).     |
| `Microsoft.ApiManagement/service/apis` x2            | `azure-openai-aue`, `azure-openai-global` (chat / completions / embeddings). |
| `Microsoft.ApiManagement/service/policyFragments` x5 | Usage trace, throttling event, cache lookup/store, mock fallback. |
| `Microsoft.ApiManagement/service/products` x3        | One product per business app / use-case.                      |
| `Microsoft.ApiManagement/service/subscriptions` x3   | Demo subscriptions usable against either API.                 |
| `Microsoft.ApiManagement/service/tags`               | API tags for the developer portal grouping.                   |
| `Microsoft.Authorization/roleAssignments`            | `Cognitive Services User` for APIM MI on the Foundry account. |
| `Microsoft.Insights/diagnosticSettings`              | Sends APIM logs/metrics to Log Analytics.                     |

---

## Repository layout

```
src/ai-gateway/
├── README.md                    # This file
├── deploy-infra.ps1             # PowerShell deployment helper
├── deploy-infra.sh              # Bash deployment helper
├── cleanup.ps1                  # Tear down the resource group
├── bicep/
│   ├── main.bicep               # Subscription-scoped entry point
│   ├── bicepconfig.json
│   └── modules/
│       ├── log-analytics.bicep      # LAW + Application Insights
│       ├── apim.bicep               # APIM service + system MI + diagnostic
│       ├── apim-service-policy.bicep# Service-level CORS
│       ├── apim-fragments.bicep     # Reusable policy fragments
│       ├── apim-backends.bicep      # 2 backends + 1 pool with circuit breakers
│       ├── apim-openai-api.bicep    # ONE AOAI API; called twice for AUE + Global
│       ├── apim-products.bicep      # Products + subscriptions, attached to both APIs
│       └── rbac.bicep               # Foundry Cognitive Services User for APIM MI
├── policies/
│   ├── service-policy.xml           # Global CORS
│   ├── openai-api-policy.xml        # Shared API policy (route + region substituted)
│   ├── product-policy.xml           # Per-product (appId, useCase, TPM substituted)
│   ├── frag-openai-usage.xml        # Trace per non-streaming response
│   ├── frag-throttling-events.xml   # 429 trace
│   ├── frag-cache-lookup.xml        # Body-hash cache lookup (HIT short-circuit)
│   ├── frag-cache-store.xml         # Persist 200 response in APIM cache (5 min)
│   └── frag-mock-fallback.xml       # Graceful 503 on backend failure
├── test-harness/
│   ├── Invoke-Demo.ps1              # Drive both routes, prints cache header
│   ├── Invoke-Throttle.ps1          # Trip per-product TPM
│   └── Invoke-Cache.ps1             # MISS / HIT / HIT demo
└── kql/
    ├── charge-back-by-app.kql       # Per-app + per-route token roll-ups
    ├── throttling-events.kql        # 429 events per product
    └── apim-gateway-requests.kql    # Latency + status code analysis
```

---

## Production-hardening checklist

This scenario is optimised to be **deployable in 30 minutes for a demo or
PoC**. Several defaults are explicitly relaxed to keep the demo simple. Tighten
them before promoting any of this beyond a sandbox.

| Area | Demo default | Production hardening |
| --- | --- | --- |
| APIM SKU | `Developer` (no SLA, single-instance) | `Premium` for SLA, multi-region and VNet integration |
| Network | `publicNetworkAccess: Enabled` on APIM, App Insights and Log Analytics | Switch to private endpoints + `publicNetworkAccess: Disabled`. APIM Premium with VNet injection (or BYOVNET for AI Hub Gateway) |
| CORS | `<allowed-origins><origin>*</origin>` in `policies/service-policy.xml` | Replace `*` with the explicit list of approved origins |
| Subscription key transport | Header only (`api-key`); query-string disabled (avoids leaks via referrer / access logs) | Keep header-only and add JWT validation (`validate-jwt`) for caller identity on top |
| Backend auth | APIM system-assigned MI -> `Cognitive Services User` on Foundry | Same pattern; consider user-assigned MI for shared identity across services |
| Telemetry | `verbosity: verbose`, `metrics: true`, `logClientIp: false` (PII-safe), `sampling: 100%` | Drop sampling to ~10% in production; keep `logClientIp` off unless you have a privacy notice |
| Cache | APIM internal cache, 5 min TTL, key includes deployment id + product id + **subscription id** + body hash. Per-subscription isolation prevents one tenant from seeing another's cached responses, even within the same product | For semantic cache use `azure-openai-semantic-cache-lookup` + Redis Enterprise. Disable cache entirely for prompts that contain PII |
| Mock fallback | Returns `requestId`, `appId`, `useCase`, `route` in the 5xx body for support correlation | Audit the body fields against your error-response policy; drop any fields you don't want exposed externally |
| Subscription tracing | `allowTracing: true` on the demo subscriptions (so you can use APIM's `Trace` panel) | Set `allowTracing: false` for production subscriptions to avoid leaking internal policy state through the developer portal |
| Backend pool | Primary + secondary both point at the same Foundry endpoint | Point the secondary at a paired-region Foundry for true active/passive failover |

---

## Cleanup

```powershell
./cleanup.ps1 -ResourceGroupName rg-ai-gateway-demo
```

> APIM goes into a **soft-delete** state after the resource group is deleted.
> If you want to recreate APIM with the same name immediately, also purge it:
>
> ```powershell
> az apim deletedservice list -o table
> az apim deletedservice purge --service-name <name> --location <region>
> ```

---

## Troubleshooting

| Symptom                                                       | Likely cause                                                                                  |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `401 PermissionDenied` from the backend on the first call    | APIM MI role assignment hadn't propagated yet. Wait 1-2 min and retry.                        |
| `404 Resource not found` for a deployment                     | The deployment id you passed isn't on the Foundry account. List with `az cognitiveservices account deployment list`. |
| `404` on the gateway itself                                   | Wrong path. Use `/<route>/openai/deployments/<id>/chat/completions?api-version=...` where `<route>` is `aue` or `global`. |
| Token metrics not appearing in `customMetrics`                | API diagnostic must have `metrics: true` (verbosity verbose alone is not enough). Bicep already sets this. |
| Cache always MISSES                                           | Body must be byte-for-byte identical (including JSON whitespace). The harness compresses JSON for stable hashes. |
| `400 ai_gateway_invalid_request`                              | Request body must include a non-empty `messages` array - that's the gateway-level validation. |
| Throttling test never returns 429                             | Bump `Calls` higher or lower the product `tpmLimit`.                                          |
