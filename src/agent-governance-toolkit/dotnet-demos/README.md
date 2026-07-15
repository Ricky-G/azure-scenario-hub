# Agent Governance Toolkit - live C# notebooks

Two presenter-ready, offline C# notebooks for the
[Microsoft Agent Governance Toolkit](https://github.com/microsoft/agent-governance-toolkit),
built with [Verso](https://github.com/DataficationSDK/Verso). They mirror the Python live-demo
flow while using the real `Microsoft.AgentGovernance` 4.0.0 NuGet package.

| Notebook | What it demonstrates | Typical runtime |
|---|---|---:|
| [`1-agt-overview.verso`](./1-agt-overview.verso) | Runtime preflight, deterministic YAML policy decisions, 10,000 live evaluations, and a zero-trust gate over every tool call | ~5 seconds |
| [`2-owasp-agentic-top-10.verso`](./2-owasp-agentic-top-10.verso) | All ten OWASP Agentic Applications 2026 risks attacked and defended inside Contoso Bank | ~10 seconds |

Both notebooks run without a model, API key, Azure subscription, or deployed service. The first
run needs internet access to restore the pinned NuGet package; subsequent runs use Verso's cache.

## Prerequisites

- .NET 8 or later (`dotnet --version`)
- The **Verso Notebook** VS Code extension (`Datafication.verso-notebook`)
- Internet access for the first NuGet restore

The optional CLI enables a final headless check:

```powershell
dotnet tool install -g Verso.Cli
```

## Present in VS Code

1. Open `1-agt-overview.verso`.
2. Choose **Run All** from the Verso toolbar.
3. Present the four acts, then open `2-owasp-agentic-top-10.verso`.
4. Choose **Run All**, or run only the OWASP scenarios you want to discuss.

State persists from the setup cell, so always run the setup cell before an individual scenario
after restarting the notebook session.

## Verify before the session

From the repository root:

```powershell
verso run .\src\agent-governance-toolkit\dotnet-demos\1-agt-overview.verso --fail-fast
verso run .\src\agent-governance-toolkit\dotnet-demos\2-owasp-agentic-top-10.verso --fail-fast
```

Expected summaries:

```text
1-agt-overview.verso:          11 total, 11 succeeded, 0 failed
2-owasp-agentic-top-10.verso: 23 total, 23 succeeded, 0 failed
```

## What is native AGT and what is host wiring?

The notebooks label this explicitly:

- Native .NET AGT controls include policy evaluation, prompt-injection detection, ECDSA agent
  identities, MCP tool scanning, execution rings, circuit breaking, hash-chained audit logging,
  lifecycle quarantine, and the kill switch.
- ASI-07 adds a small in-memory nonce set around the AGT signature to demonstrate replay rejection.
- ASI-06 places the native injection detector at the application's memory-write boundary.
- ASI-09 uses AGT's native immutable audit entries and `AuditLogger.Verify()`; the extra verifier
  checks a simulated altered serialized copy with the same documented hash algorithm.

The ASI-09 hash chain is tamper-evident. It is not encryption or a digital signature. A production
deployment should persist the audit log durably and separately sign or anchor the chain head.

## Recommended live-demo order

1. In the overview, pause on **How a decision is made**: the model proposes an action, but C# owns
   execution and calls AGT before the tool.
2. Run the 10,000-evaluation benchmark live rather than quoting a saved number.
3. In the OWASP notebook, prioritize ASI-01, ASI-02, ASI-04, ASI-07, ASI-09, and ASI-10 if time is short.
4. End on the shared pattern: **inspect, decide, enforce before execution, retain evidence**.

> These notebooks are optimized for learning and live demonstration, not production deployment.