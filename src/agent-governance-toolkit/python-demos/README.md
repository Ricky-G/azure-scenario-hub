# Agent Governance Toolkit — live demos

A presenter-ready set of self-contained, **offline** notebooks for the **Agent Governance Toolkit
(AGT)**, plus a code companion guide. Every notebook cell runs the **real** toolkit (`agent_os`) — no
mocks, no API keys, no network.

| File | What it is | Run / read |
|---|---|---|
| [`1-agt-overview.ipynb`](./1-agt-overview.ipynb) | **Notebook** — what AGT is and how it works: the `agt doctor` health check, how a policy decision is made, **10,000 live policy evaluations** at sub-millisecond latency, and a zero-trust gate in front of every tool call | ~2 min |
| [`2-owasp-agentic-top-10-v3.ipynb`](./2-owasp-agentic-top-10-v3.ipynb) | **Recommended live runbook** — a projector-friendly Contoso Bank walkthrough with compact boundary cues, responsive evidence boards, and a one-screen 10/10 summary | ~10 min |
| [`2-owasp-agentic-top-10-v2.ipynb`](./2-owasp-agentic-top-10-v2.ipynb) | **Previous live runbook** — the same ten checks in the original, more detailed presentation layout | ~10 min |
| [`2-owasp-agentic-top-10.ipynb`](./2-owasp-agentic-top-10.ipynb) | **Notebook** — the **OWASP Agentic Top 10** (ASI-01 … ASI-10) as a story inside a fictional bank, each risk attacked and **stopped by a real AGT control** | ~3 min |
| [`2-owasp-agentic-top-10-companion-guide.md`](./2-owasp-agentic-top-10-companion-guide.md) | **Companion guide** — read alongside notebook 2: what each control is, what the code does, whether it comes out of the box, YAML-configurability, and the questions an audience is likely to ask | reference |

Present notebook 1 first to establish the mental model, then use the **V3 runbook** for the clearest live
walkthrough of all ten risks. The original notebook and its **companion guide** remain available as the
short-form demo and detailed API reference.

## The OWASP Agentic Top 10, mapped to real controls

| # | Risk | AGT control (real `agent_os` API) |
|---|------|-----------------------------------|
| ASI-01 | Agent Goal Hijack | `prompt_injection.PromptInjectionDetector` |
| ASI-02 | Tool Misuse and Exploitation | `integrations.base.GovernancePolicy` + `PolicyInterceptor` |
| ASI-03 | Identity and Privilege Abuse | `mcp_message_signer.MCPMessageSigner` |
| ASI-04 | Agentic Supply Chain Vulnerabilities | `mcp_security.MCPSecurityScanner` |
| ASI-05 | Unexpected Code Execution | `sandbox.ExecutionSandbox` |
| ASI-06 | Memory and Context Poisoning | `memory_guard.MemoryGuard` |
| ASI-07 | Insecure Inter-Agent Communication | `mcp_message_signer.MCPMessageSigner` |
| ASI-08 | Cascading Failures | `circuit_breaker.CircuitBreaker` |
| ASI-09 | Human-Agent Trust Exploitation | `PolicyInterceptor` + `audit_logger.GovernanceAuditLogger` |
| ASI-10 | Rogue Agents | `adversarial.AdversarialEvaluator` + `PolicyInterceptor` |

## Prerequisites

- **Python 3.10+**
- The Agent Governance Toolkit installed in the kernel you select:

```bash
python -m venv .venv
.\.venv\Scripts\Activate.ps1        # Windows PowerShell
#  source .venv/bin/activate        # macOS / Linux
pip install -r requirements.txt
```

Use the dedicated environment above as the notebook kernel. Virtual environments are intentionally
excluded from source control, so each clone should create its own from `requirements.txt`.

## Run it

1. Open a notebook in VS Code (or Jupyter).
2. Select a kernel whose Python has `agent-governance-toolkit` installed.
3. **Run All** — the setup cell confirms the toolkit is present, then each demo cell runs top to bottom.

The first cell prints a friendly install hint if the toolkit isn't found in the selected kernel.

### VS Code stage setup

1. Run V3 once before presenting and confirm the final board says **10 / 10 LIVE CONTROL CHECKS PASSED**.
2. From the Command Palette, run **Notebook: Collapse All Cell Inputs** so the evidence boards lead the story.
3. Enter Zen Mode, zoom to roughly 150%, and rerun one check at a time when you want to demonstrate live execution.

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
