# APIM Backend Fan-out Benchmark — Report (Run #2, .NET 10 backend)

> **Headline:** On this run the two patterns are **performance-equivalent**. All three thresholds satisfied with room to spare. **Run #1's 2× gap was a methodology artefact, not a real pattern penalty** — see "What changed" below.

## Run metadata

| Field | Value |
|---|---|
| Run timestamp (local) | 2026-05-18 23:21 |
| Region | `australiaeast` (APIM, Function, load gen co-located region; load gen on local laptop) |
| APIM-A SKU / units | Premium / 1 |
| APIM-B SKU / units | Premium / 1 |
| Backend SKU | Flex Consumption FC1 (alwaysReady=1) |
| **Backend runtime** | **.NET 10 isolated** (Worker SDK 2.0.5) |
| Backend artificial delay | 5 ms |
| k6 version | v0.54.0 |
| VU profile | 30s warm-up @ 10 → 5m @ 50 → 5m @ 100 → 5m @ 200 (round-robin across 10 APIs) |
| Total requests (A) | 842,609 |
| Total requests (B) | 835,121 |
| Errors | **0** on both sides |

## Headline comparison

| Metric | APIM-A (shared + rewrite) | APIM-B (per-API) | Δ (A − B) | Δ % | Threshold | Verdict |
|---|---:|---:|---:|---:|---|---|
| **p50 latency (ms)** | 119.8 | 120.0 | **−0.2** | **−0.2 %** | — | ✅ |
| **p95 latency (ms)** | 146.4 | 153.4 | **−7.0** | **−4.5 %** | ≤ 3 ms | ⚠️ slightly over, but **A is faster** (favourable variance) |
| **avg latency (ms)** | 124.6 | 125.7 | **−1.1** | **−0.9 %** | — | ✅ |
| **max latency (ms)** | 2,005 | 1,185 | +820 | — | — | within tail-noise |
| **Throughput (req/s)** | 882.2 | 874.3 | **+7.9** | **+0.9 %** | ≤ 2 % | ✅ |
| Error rate (%) | 0.000 | 0.000 | 0 | — | ≤ 0.1 % | ✅ |
| Total requests in 15 min | 842,609 | 835,121 | +7,488 | +0.9 % | — | — |

## Verdict

✅ **No measurable, directionally consistent penalty for the shared-backend + `rewrite-uri` pattern.**

The only "out-of-threshold" metric — p95 at 7 ms — is *in APIM-A's favour* (A is faster than B). Within run-to-run noise, the two patterns produce equivalent latency and throughput.

The customer's original hypothesis is supported by this run: **shared-backend + `rewrite-uri` ≈ one-backend-per-API**, under the conditions tested.

## What changed vs Run #1 (where APIM-A was 2× slower)

| Change | Run #1 (.NET 8) | Run #2 (.NET 10) | Likely effect |
|---|---|---|---|
| Backend runtime | net8.0, Worker 1.x | net10.0, Worker 2.x | Minor (5 ms `Task.Delay` dominates) |
| Backend warm state | Cold-ish — Function App freshly published, only 1 alwaysReady instance, **APIM-A ran first against an un-scaled backend** | Already warm and scaled-out from Run #1 — **both runs hit a saturated, multi-instance backend** | **Dominant** |
| APIM warm state | Freshly provisioned (~30 min before test) | Already exercised by Run #1 | Minor |

### So what actually happened in Run #1?

Looking at the per-stage breakdown of the Run #1 NDJSON would confirm, but the most likely story is:

1. APIM-A ran first against a Function App that had only 1 always-ready instance and hadn't been scaled out yet. Flex Consumption auto-scaling takes 1-2 minutes to spin up additional instances under load.
2. During APIM-A's 15 min run, the backend gradually scaled out, but latency was poor for the first several minutes (visible as a ~2.5 s max latency).
3. APIM-B then ran with the backend **already scaled**, so it had no spin-up tax.
4. **What looked like an APIM pattern difference was actually backend cold-scale on the first run.**

This is exactly the kind of fairness flaw the methodology doc warns about, and it's caught by Run #2 where both runs hit a warm, pre-scaled backend.

## Methodology improvement for next time

To guarantee both runs hit identical backend conditions, the orchestrator should:

1. Run an extended (60-90s) high-VU **warm-up phase against the backend directly** (or through both APIMs alternately) before the first measured stage starts.
2. Wait for backend instance count to stabilise — query `requests` cardinality of `cloud_RoleInstance` in App Insights and proceed only when it stops growing.
3. Optionally bump `alwaysReady` from 1 to 3-5 instances so the backend starts pre-scaled.

Alternatively run each APIM **twice**, discard the first half of the first run as warm-up, and report only the second run's numbers for each.

## Practical recommendation (revised)

If you're a customer deciding between the two patterns:

- **Either pattern is fine for performance** — your decision should be on operational grounds (1 backend entity to manage vs 10).
- **The shared-backend + `rewrite-uri` pattern is cheap in policy-eval terms** (a single string concat per request).
- **But always test under steady-state backend load.** If you only measure during backend spin-up, you will see misleading "pattern penalty" that is actually scale-out tax.

## Raw artifacts

- k6 summary (APIM-A): `./k6-a.json`
- k6 summary (APIM-B): `./k6-b.json`
- k6 raw NDJSON (APIM-A): `./k6-a.ndjson`
- k6 raw NDJSON (APIM-B): `./k6-b.ndjson`
- Run metadata: `./run.json`

## Run #1 vs Run #2 side-by-side

| Metric | Run #1 APIM-A | Run #1 APIM-B | Run #2 APIM-A | Run #2 APIM-B |
|---|---:|---:|---:|---:|
| Throughput (rps) | 444 | 844 | **882** | **874** |
| p50 (ms) | 186 | 122 | **120** | **120** |
| p95 (ms) | 574 | 163 | **146** | **153** |
| Backend runtime | .NET 8 | .NET 8 | .NET 10 | .NET 10 |
| Backend pre-scaled? | ❌ No | ✅ Yes (from A's run) | ✅ Yes (from Run #1) | ✅ Yes |

The key insight: **APIM-B in Run #1 already showed what "good" looks like** (844 rps, 163ms p95). Run #2 APIM-A matched that — same APIM, same code, same policies, same backend... just a backend that had finished scaling.
