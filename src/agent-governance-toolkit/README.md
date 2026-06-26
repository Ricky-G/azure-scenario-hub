# Agent Governance Toolkit — Governed Agent Scenarios

A hub of ready-to-run examples that wrap AI agent frameworks with the **Microsoft Agent Governance
Toolkit (AGT)** — so that **every prompt and every tool call an agent makes is intercepted and
evaluated by a real, deterministic policy** before it reaches a model or executes a tool.

The [Agent Governance Toolkit](https://github.com/microsoft/agent-governance-toolkit) is
Microsoft's open-source toolkit for governing autonomous agents: a deterministic policy engine,
prompt static-analysis, capability sandboxing, and tamper-evident audit primitives. This hub shows
how to apply it to real agent frameworks, with complete, runnable, **offline** demos.

> **Why governance, not just prompting?** Prompt-level safety ("please follow the rules") is a
> *request* to a stochastic system. AGT instead intercepts each action in deterministic
> application code — actions the policy denies are not "unlikely", they are **structurally
> impossible**.

---

## Start here — live demos

New to the toolkit? Two offline, presenter-ready notebooks introduce AGT and then walk the whole
**OWASP Agentic Top 10**, plus a companion guide that explains the code — every notebook cell runs the real toolkit:

| File | What it is |
|---|---|
| **[1 · AGT overview](./live-demos/1-agt-overview.ipynb)** | Notebook — what AGT is, the `agt doctor` health check, 10,000 live policy evaluations at sub-millisecond latency, and a zero-trust gate over every tool call |
| **[2 · OWASP Agentic Top 10](./live-demos/2-owasp-agentic-top-10.ipynb)** | Notebook — all ten ASI risks attacked, and stopped by a real AGT control, inside a fictional bank |
| **[Companion guide](./live-demos/2-owasp-agentic-top-10-companion-guide.md)** | Markdown — read beside notebook 2: what each control is, what the code does, out-of-the-box vs YAML config, and likely audience questions |

See [`live-demos/`](./live-demos/README.md) for prerequisites and how to run them.

---

## Integrations in this hub

| Integration | Languages | Highlights | Status |
|---|---|---|---|
| **[Microsoft Agent Framework (MAF)](./microsoft-agent-framework/README.md)** | Python · .NET/C# | Agent-level **tool-call argument** governance, prompt + tool middleware, default-deny capability sandbox, governed multi-agent workflow, tamper-evident audit log | ✅ Ready |

> More agent-framework and governance-pattern integrations will be added here over time. Each
> integration is self-contained and independently runnable.

---

## What every integration demonstrates

- **Prompt governance** — deterministic block of PII / secrets / prompt-injection before the model runs.
- **Tool capability sandbox** — a default-deny allowlist over *which* tools may run.
- **Argument-boundary governance** — one agent-level policy that inspects tool-call *argument values* (numeric ceilings, forbidden values, data-residency sets) with no per-tool code.
- **Governed multi-agent workflows** — one governance layer + one audit chain across multiple agents.
- **Tamper-evident audit trail** — a hash-chained log where editing any record breaks the chain.

All demos run with a deterministic scripted model (no API keys, no network), so results are
identical for everyone — and the same governance layer works unchanged in front of a live model.

---

## Quick start

Pick an integration and follow its README:

```bash
# Microsoft Agent Framework integration
cd microsoft-agent-framework

#   Python
cd python && python -m venv .venv && .\.venv\Scripts\Activate.ps1 && pip install -r requirements.txt && python demos/run_all.py

#   .NET / C#
cd dotnet && dotnet run --project AgtMaf.Demos -- all
```

---

## Learn more

- [Agent Governance Toolkit](https://github.com/microsoft/agent-governance-toolkit) — the toolkit this hub is built on.
- [Microsoft Agent Framework](https://github.com/microsoft/agent-framework) — agents, tools, middleware, multi-agent workflows.
- [Back to the Azure Scenario Hub](../../README.md).

> These templates are optimised for learning and experimentation, **not** production. For
> production-grade Azure infrastructure, see [Azure Verified Modules](https://aka.ms/avm).
