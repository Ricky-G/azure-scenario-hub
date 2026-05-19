# Methodology

This benchmark is designed so that the **only** variable between the two test groups is the pattern under test (shared-backend + `rewrite-uri` vs one-backend-per-API). Everything else is deliberately held constant.

## Controlled variables

| Variable | Value | Why |
|---|---|---|
| Region | Same for both APIMs, the Function App, and the load generator (default `australiaeast`) | Eliminate WAN latency and regional capacity differences |
| APIM SKU | `Premium`, 1 unit, both instances | Match the customer's production tier; ensures dedicated gateway, no shared-tenant noise |
| Backend | One Function App, Premium **EP1**, `alwaysReady = 1`, `minimumElasticInstanceCount = 1` | Eliminate cold-start variance; confirmed via `instanceId` custom dimension that both APIMs hit the same instance(s) |
| Backend artificial delay | `await Task.Delay(5)` on every request | Gives a stable non-zero baseline so APIM overhead is visible above measurement noise |
| API surface | 10 APIs per APIM, identical base paths (`/svc01/v1` … `/svc10/v1`), identical operation (`GET /resource/{id}`) | Same routing complexity on both sides |
| Policies | Both sides apply a **policy fragment** at the API scope | Ensures fragment compilation cost is constant; the only diff is the fragment body (`rewrite-uri` present vs absent) |
| Subscription / auth | `subscriptionRequired = false`, no auth, no products | No JWT validation, no rate-limit policy, no quota counter writes — those would dominate the signal |
| Diagnostics | Both APIMs use the same App Insights logger, `sampling = 100%`, **bodies disabled** | Body logging is expensive and would distort latency |
| Load harness | k6, identical script (`common.js`), identical RNG seed, identical VU profile | Removes load-generator variance |
| Network path | Load generator in the same region (recommended: small Azure VM in `australiaeast`) | Removes home-broadband / cross-region jitter from the signal |

## Why a policy fragment on both sides?

If APIM-B had no API-level policy at all and APIM-A had an inline `<rewrite-uri>` block, we'd also be measuring "policy compilation + fragment resolution" overhead, not just `rewrite-uri`. Both sides use a fragment so that variable is controlled.

## Test profile

- **Warm-up:** 30 s @ 10 VUs — **discarded** from all metrics.
- **Steady-state (3 stages, sequential):**
  - Stage 1: 5 min @ 50 VUs
  - Stage 2: 5 min @ 100 VUs
  - Stage 3: 5 min @ 200 VUs
- **Cool-down:** 60 s between APIM-A and APIM-B runs.
- Each VU iteration round-robins across all 10 APIs so load is evenly spread across all APIs / backend entities.

## Metrics captured

Per request (from k6):

- `http_req_duration` (total time the load gen saw)
- `http_req_waiting` (TTFB)
- HTTP status
- Tags: `{ apim: "A"|"B", api: "svc01"…"svc10", stage: "50vu"|"100vu"|"200vu" }`

From APIM diagnostics in App Insights:

- `BackendTime` — time APIM spent waiting on the backend
- `ClientTime` — total time APIM took to return to the client
- `ClientTime − BackendTime` ≈ **APIM overhead** (the number we actually care about)

## Pass / fail thresholds

The auto-generated report uses these thresholds to render a verdict:

| Threshold | Trigger |
|---|---|
| `|Δ p95 latency|` ≤ **3 ms** | … and … |
| `|Δ throughput|` ≤ **2 %** | … and … |
| `|Δ error rate|` ≤ **0.1 %** | → **"No measurable penalty."** |

If any threshold is exceeded, the report names it and reports the magnitude.

## Explicit non-goals

To keep the measurement clean, this scenario deliberately does **not** include:

- VNet integration, private endpoints, or APIM internal-mode networking
- WAF or Front Door
- Any authentication (no JWT, no subscription key requirements)
- Caching, throttling, validation, or transformation policies
- Multi-region failover or backend pools

Adding any of those would change what is being measured. They can be layered on top in follow-up scenarios.
