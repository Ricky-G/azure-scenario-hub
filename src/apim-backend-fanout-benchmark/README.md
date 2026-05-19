# APIM Backend Fan-out Benchmark 🧪

Head-to-head benchmark answering a real customer question:

> *"If I point 100+ APIs at a **single** APIM Backend entity and use `rewrite-uri` to reconstruct the path, do I pay a measurable latency / throughput / reliability penalty versus modelling **one Backend entity per API**?"*

This scenario deploys **two identical APIM Premium instances** (`APIM-A` shared-backend + `rewrite-uri`, `APIM-B` one-backend-per-API) pointed at the **same** mock Function App backend, runs the **same** k6 load against both, and produces a Markdown + HTML report comparing latency, throughput, error rate, and measured APIM overhead.

## 🎯 TL;DR — Result

> ✅ **No measurable difference between the two patterns.** Across **1.67 million requests** over ~32 minutes of stepped load (50 → 100 → 200 VUs), APIM-A and APIM-B produced equivalent latency and throughput. All three pass/fail thresholds satisfied.

![Benchmark dashboard](docs/dashboard.png)

| Metric | APIM-A (shared + rewrite) | APIM-B (per-API) | Δ | Verdict |
|---|---:|---:|---:|---|
| Throughput (req/s) | **882.2** | **874.3** | +0.9 % | ✅ |
| p50 latency (ms) | 119.8 | 120.0 | −0.2 | ✅ |
| p95 latency (ms) | **146.4** | **153.4** | −7.0 (A faster) | ✅ |
| avg latency (ms) | 124.6 | 125.7 | −1.1 | ✅ |
| Total requests | 842,609 | 835,121 | +7,488 | — |
| Errors | 0 | 0 | 0 | ✅ |

**Bottom line:** either pattern is fine for performance. Choose on operational grounds (one backend entity to manage vs ten), not perf.

For the full interactive dashboard, open [`test-harness/results/index.html`](test-harness/results/index.html) in a browser. Full numeric report: [`test-harness/results/20260518-232153/REPORT.md`](test-harness/results/20260518-232153/REPORT.md).

## 🏗️ What Gets Deployed

| Resource | Purpose | SKU |
|---|---|---|
| Resource Group | Container for everything | — |
| Log Analytics Workspace | Shared log store for both APIMs + Function | PerGB2018 |
| Application Insights | APM for APIM diagnostics + Function instrumentation | Workspace-based |
| Storage Account | Function deployment container (identity-based, no shared keys) | Standard_LRS |
| Function App (mock backend) | `.NET 10` isolated, `/api/echo/{*path}` + `/api/time`, 5 ms artificial delay | **Flex Consumption FC1** (alwaysReady=1) |
| APIM-A | Shared-backend pattern: **1** Backend + **10** APIs + `rewrite-uri` policy fragment | **Premium**, 1 unit |
| APIM-B | Per-API pattern: **10** Backends + **10** APIs, no rewrite | **Premium**, 1 unit |

> 💸 **Cost note:** Two Premium APIMs dominate the cost at **~$7.95 / hour** while deployed (mostly the 2× APIM Premium units). A full deploy → benchmark → cleanup cycle is **~$13–20** end-to-end. Run [`cleanup`](#-clean-up) the moment your benchmark is complete.

> 🔑 **Why Flex Consumption (FC1), not EP1?** Some Azure subscriptions enforce an Azure Policy that auto-disables `allowSharedKeyAccess` on storage accounts. Functions Elastic Premium (EP) requires shared-key access to mount its content file share, so it fails to provision in those subscriptions. Flex Consumption uses identity-based blob deployment and has no file-share dependency, so it works regardless of that policy — while still giving us a pre-warmed always-ready instance with no cold starts.

## 📐 Architecture

```
                                        ┌────────────────────────────────────┐
                                        │  Mock Backend (Function App, .NET) │
                                        │  Flex Consumption FC1, always-ready=1│
                                        │    GET /api/echo/{anything*}       │
                                        │    GET /api/time                   │
                                        └────────────────┬───────────────────┘
                                                         │ Same backend instance
                ┌────────────────────────────────────────┼────────────────────────────────────────┐
                │                                        │                                        │
   ┌────────────┴─────────────┐                          │                          ┌─────────────┴────────────┐
   │  APIM-A (Premium, 1 unit)│                          │                          │  APIM-B (Premium, 1 unit)│
   │  PATTERN: shared backend │                          │                          │  PATTERN: backend-per-api │
   │  • 1 Backend entity      │                          │                          │  • 10 Backend entities    │
   │  • 10 APIs               │                          │                          │  • 10 APIs                │
   │  • set-backend-service   │                          │                          │  • set-backend-service    │
   │    + rewrite-uri         │                          │                          │    only (no rewrite)      │
   └──────────────────────────┘                          │                          └───────────────────────────┘
                ▲                                        │                                        ▲
                │                                        │                                        │
                └──────────────── Same k6 harness, same RPS, same payloads ──────────────────────┘
```

See [`docs/architecture.md`](docs/architecture.md) and [`docs/methodology.md`](docs/methodology.md) for the design rationale and the controls that make this a fair test.

## ✅ Prerequisites

- An Azure subscription with quota for **2 × APIM Premium** units in your chosen region
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) ≥ 2.55
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) ≥ 0.24 (`az bicep install`)
- PowerShell 7+ **or** Bash
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) (to build the Function App — the .NET 8 SDK also works since the project pins Worker SDK 2.x)
- [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local) (to publish the Function App)
- [k6](https://k6.io/docs/get-started/installation/) (to run the benchmark — portable zip works fine, no admin required)

## 🚀 Deploy

> APIM Premium provisioning takes **~45 minutes**. Both APIMs deploy in parallel so total wall-clock time is roughly that, not 90 min.

**PowerShell:**

```powershell
cd src/apim-backend-fanout-benchmark/bicep
./deploy.ps1 -Location australiaeast -NamePrefix apimfo
```

**Bash:**

```bash
cd src/apim-backend-fanout-benchmark/bicep
./deploy.sh australiaeast apimfo
```

Then publish the Function App code (the Bicep deploys an *empty* Function App shell):

```powershell
cd ../backend/MockBackend
func azure functionapp publish <function-app-name-from-deploy-output>
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `location` | `australiaeast` | Azure region. Must support APIM Premium and Functions Flex Consumption (FC1) |
| `namePrefix` | `apimfo` | 3–8 char prefix used to derive all resource names |
| `resourceGroupName` | `rg-{namePrefix}-benchmark` | Resource group name (created by the script) |
| `publisherEmail` | `admin@example.com` | APIM publisher contact |
| `publisherName` | `Benchmark` | APIM publisher org |
| `apiCount` | `10` | Number of APIs to deploy per APIM (kept identical between A and B) |

## 🧪 Run the Benchmark

```powershell
cd src/apim-backend-fanout-benchmark/test-harness
Copy-Item config.example.json config.json
# Edit config.json with your two APIM gateway URLs (printed by the deploy script)

./Run-Benchmark.ps1 -ConfigPath ./config.json
```

The orchestrator will:

1. Smoke-test all 20 endpoints (10 on each APIM).
2. Warm both APIMs for 30 s @ 10 VUs (discarded).
3. Run a stepped load (5 min @ 50 / 100 / 200 VUs) against **APIM-A**.
4. Cool down 60 s.
5. Run the **identical** load against **APIM-B**.
6. Query App Insights for `BackendTime` / `ClientTime`.
7. Write `test-harness/results/<timestamp>/REPORT.md`.

See [`test-harness/README.md`](test-harness/README.md) for full options and the [report template](docs/report-template.md) for the expected output format.

## 🧹 Clean Up

```powershell
cd bicep
./cleanup.ps1 -ResourceGroupName rg-apimfo-benchmark
```

```bash
cd bicep
./cleanup.sh rg-apimfo-benchmark
```

## 📂 File Structure

```
src/apim-backend-fanout-benchmark/
├── README.md                       ← you are here
├── docs/
│   ├── architecture.md
│   ├── methodology.md
│   └── report-template.md
├── bicep/
│   ├── main.bicep                  Subscription-scoped entry point
│   ├── main.parameters.json
│   ├── deploy.ps1 / deploy.sh
│   ├── cleanup.ps1 / cleanup.sh
│   └── modules/
│       ├── monitoring.bicep        Log Analytics + App Insights
│       ├── backend-functionapp.bicep
│       ├── apim.bicep              Reusable Premium APIM
│       ├── apim-a-shared-backend.bicep
│       ├── apim-b-per-api-backend.bicep
│       └── policy-fragments/
│           ├── shared-backend-rewrite.xml
│           └── per-api-passthrough.xml
├── backend/
│   └── MockBackend/                .NET 10 isolated Function App
├── test-harness/
│   ├── README.md
│   ├── config.example.json
│   ├── Run-Benchmark.ps1
│   ├── Invoke-LoadTest.ps1
│   ├── Smoke-Test.ps1
│   ├── Build-Report.ps1
│   ├── k6/
│   │   ├── apim-a-shared.js
│   │   ├── apim-b-perapi.js
│   │   └── common.js
│   ├── kql/
│   │   ├── apim-latency-percentiles.kql
│   │   ├── apim-backend-time.kql
│   │   └── apim-failures.kql
│   └── results/
│       ├── index.html              Interactive dashboard (open in browser)
│       └── 20260518-232153/        Sample run with REPORT.md
└── KQL-QUERIES.md
```
