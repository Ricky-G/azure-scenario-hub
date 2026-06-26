# Agent Governance Toolkit — live demos

A presenter-ready set for the **Agent Governance Toolkit (AGT)**: two self-contained, **offline**
notebooks plus a code companion guide. Every notebook cell runs the **real** toolkit (`agent_os`) — no
mocks, no API keys, no network.

| File | What it is | Run / read |
|---|---|---|
| [`1-agt-overview.ipynb`](./1-agt-overview.ipynb) | **Notebook** — what AGT is and how it works: the `agt doctor` health check, how a policy decision is made, **10,000 live policy evaluations** at sub-millisecond latency, and a zero-trust gate in front of every tool call | ~2 min |
| [`2-owasp-agentic-top-10.ipynb`](./2-owasp-agentic-top-10.ipynb) | **Notebook** — the **OWASP Agentic Top 10** (ASI-01 … ASI-10) as a story inside a fictional bank, each risk attacked and **stopped by a real AGT control** | ~3 min |
| [`2-owasp-agentic-top-10-companion-guide.md`](./2-owasp-agentic-top-10-companion-guide.md) | **Companion guide** — read alongside notebook 2: what each control is, what the code does, whether it comes out of the box, YAML-configurability, and the questions an audience is likely to ask | reference |

Present the notebooks in order — notebook 1 sets up the mental model, notebook 2 applies it to the ten
risks — and keep the **companion guide** open beside notebook 2 to answer "what is this code actually doing?".

## The OWASP Agentic Top 10, mapped to real controls

| # | Risk | AGT control (real `agent_os` API) |
|---|------|-----------------------------------|
| ASI-01 | Agent Goal Hijacking | `prompt_injection.PromptInjectionDetector` |
| ASI-02 | Excessive Capabilities | `trust_root.TrustRoot` + `GovernancePolicy` |
| ASI-03 | Identity & Privilege Abuse | `mcp_message_signer.MCPMessageSigner` |
| ASI-04 | Uncontrolled Code Execution | `sandbox.ExecutionSandbox` |
| ASI-05 | Insecure Output Handling | `mute_agent.MuteAgent` |
| ASI-06 | Memory Poisoning | `memory_guard.MemoryGuard` |
| ASI-07 | Unsafe Inter-Agent Communication | `mcp_message_signer.MCPMessageSigner` |
| ASI-08 | Cascading Failures | `circuit_breaker.CircuitBreaker` |
| ASI-09 | Human-Agent Trust Deficit | `audit_logger.GovernanceAuditLogger` |
| ASI-10 | Rogue Agents & Shadow AI | `adversarial.AdversarialEvaluator` + `PolicyInterceptor` |

## Prerequisites

- **Python 3.10+**
- The Agent Governance Toolkit installed in the kernel you select:

```bash
python -m venv .venv
.\.venv\Scripts\Activate.ps1        # Windows PowerShell
#  source .venv/bin/activate        # macOS / Linux
pip install -r requirements.txt
```

> A virtual environment with these packages already exists at
> [`../microsoft-agent-framework/python/.venv`](../microsoft-agent-framework/python) — you can
> select that one as the notebook kernel instead of creating a new environment.

## Run it

1. Open a notebook in VS Code (or Jupyter).
2. Select a kernel whose Python has `agent-governance-toolkit` installed.
3. **Run All** — the setup cell confirms the toolkit is present, then each demo cell runs top to bottom.

The first cell prints a friendly install hint if the toolkit isn't found in the selected kernel.

## A note on accuracy

These notebooks deliberately call the **installed** toolkit APIs so the demo and the claims match.
Where the live API differs from a production deployment, the notebook says so inline — for example,
ASI-03/07 use the toolkit's message signer (integrity + replay protection); production AGT mesh can
swap in Ed25519 / post-quantum ML-DSA-65 keys with the same verify-before-trust flow, and message
confidentiality is handled by the transport.

## Learn more

- [Agent Governance Toolkit](https://github.com/microsoft/agent-governance-toolkit)
- [OWASP GenAI Security Project](https://genai.owasp.org/) · [Agentic AI — Threats and Mitigations](https://genai.owasp.org/resource/agentic-ai-threats-and-mitigations/)
- [Back to the Agent Governance Toolkit hub](../README.md)

> Optimised for learning, demos and live presentation, **not** production.
