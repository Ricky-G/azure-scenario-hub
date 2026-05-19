# Test Harness

End-to-end benchmark runner for the APIM Backend Fan-out scenario.

## Prerequisites

- [k6](https://k6.io/docs/get-started/installation/) on `PATH` (`winget install k6.k6` or `brew install k6`)
- PowerShell 7+
- Azure CLI logged in (`az login`)
- The scenario already deployed via [`../bicep/deploy.ps1`](../bicep/deploy.ps1) and the Function App code published

> 🌏 **Run from the same Azure region as the deployment** (recommended: a small `Standard_D2s_v5` VM in the same region as APIM) to remove WAN/home-broadband jitter from the measurement. You can run from your laptop for a quick sanity check, but the published numbers should always come from an in-region runner.

## Files

| File | Purpose |
|---|---|
| `config.example.json` | Copy to `config.json` and fill in your two gateway URLs + App Insights name |
| `Run-Benchmark.ps1` | Orchestrator: smoke-test → warm-up → APIM-A → cool-down → APIM-B → report |
| `Invoke-LoadTest.ps1` | Single-instance load-runner (wraps `k6 run`) |
| `Smoke-Test.ps1` | Pings every endpoint on both APIMs, asserts 200 OK |
| `Build-Report.ps1` | Aggregates k6 JSON + App Insights data into `REPORT.md` |
| `k6/common.js` | Shared VU profile + iteration body (identical between A and B) |
| `k6/apim-a-shared.js` | k6 scenario targeting APIM-A |
| `k6/apim-b-perapi.js` | k6 scenario targeting APIM-B |
| `kql/*.kql` | KQL used by the report builder |

## Configure

```powershell
Copy-Item config.example.json config.json
# Edit config.json — set apimAGatewayUrl, apimBGatewayUrl, appInsightsName,
# resourceGroupName, subscriptionId. The deploy script printed these values.
```

## Smoke test

```powershell
./Smoke-Test.ps1 -ConfigPath ./config.json
```

Hits every `/{svcNN}/v1/resource/1` path on both APIMs and asserts `200 OK`.

## Run a full benchmark

```powershell
./Run-Benchmark.ps1 -ConfigPath ./config.json
```

This will:

1. Smoke-test both APIMs (abort on failure).
2. Run k6 against **APIM-A** with the full warm-up + 3-stage profile.
3. Cool down for 60 s.
4. Run the **identical** k6 profile against **APIM-B**.
5. Wait ~2 min for App Insights ingestion to settle.
6. Invoke `Build-Report.ps1` to produce `results/<timestamp>/REPORT.md`.

Total wall-clock time: **~40 minutes**.

## Run a single side only

```powershell
./Invoke-LoadTest.ps1 -GatewayUrl https://apim-...azure-api.net -Side A -OutDir ./results/manual
```

## Build a report from existing run data

```powershell
./Build-Report.ps1 -ResultsDir ./results/20260518-101530 -ConfigPath ./config.json
```
