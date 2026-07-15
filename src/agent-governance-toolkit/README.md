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

## Start here - live demos

New to the toolkit? Start with the offline, presenter-ready notebook pair in your preferred language.
Both editions introduce AGT and then walk the complete **OWASP Top 10 for Agentic Applications 2026**.

| Language | AGT overview | OWASP Agentic Top 10 | Run guide |
|---|---|---|---|
| **.NET / C# (Verso)** | [`1-agt-overview.verso`](./dotnet-demos/1-agt-overview.verso) | [`2-owasp-agentic-top-10.verso`](./dotnet-demos/2-owasp-agentic-top-10.verso) | [`dotnet-demos/README.md`](./dotnet-demos/README.md) |
| **Python (Jupyter)** | [`1-agt-overview.ipynb`](./python-demos/1-agt-overview.ipynb) | [`2-owasp-agentic-top-10.ipynb`](./python-demos/2-owasp-agentic-top-10.ipynb) | [`python-demos/README.md`](./python-demos/README.md) |

The Python edition also includes an
[`OWASP companion guide`](./python-demos/2-owasp-agentic-top-10-companion-guide.md).

---

## Integrations in this hub

| Integration | Languages | Highlights | Status |
|---|---|---|---|
| **[Microsoft Agent Framework (MAF)](./microsoft-agent-framework-demos/README.md)** | Python - .NET/C# | Agent-level **tool-call argument** governance, prompt + tool middleware, default-deny capability sandbox, governed multi-agent workflow, tamper-evident audit log | Ready |

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
cd microsoft-agent-framework-demos

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
