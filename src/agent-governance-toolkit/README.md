# Learn the Agent Governance Toolkit with Runnable Demos

A hands-on learning scenario for exploring the
[Microsoft Agent Governance Toolkit (AGT)](https://github.com/microsoft/agent-governance-toolkit)
in **.NET/C# and Python**. If you are new to agent governance, this folder takes you from the core
mental model to live security controls and then to a real agent-framework integration.

AGT places a deterministic control point between an agent's proposed action and its execution:

```text
Model proposes a tool call -> AGT evaluates policy -> allow, deny, or escalate -> execute and audit
```

> The key idea: prompt instructions ask a stochastic model to follow the rules. AGT enforces the
> rules in application code before a prompt reaches a model or a tool creates a side effect.

## What's included

| Asset | Purpose | Start here |
|---|---|---|
| **Presentation deck** | Explains agents, tool calling, the governance gap, AGT architecture, and the OWASP Top 10 for Agentic Applications 2026 | [Download the PowerPoint](./Agent-Governance-Toolkit_v5.pptx) |
| **C# learning demos** | Two [Verso](https://github.com/DataficationSDK/Verso) notebooks: an AGT overview and all ten OWASP agentic risks demonstrated inside Contoso Bank | [C# / Verso guide](./dotnet-demos/README.md) |
| **Python learning demos** | Equivalent Jupyter notebooks using the real `agent_os` APIs, plus an OWASP companion guide that explains each control | [Python / Jupyter guide](./python-demos/README.md) |
| **Microsoft Agent Framework integration** | Complete Python and .NET implementations with prompt middleware, tool and argument governance, workflows, and audit evidence | [MAF integration guide](./microsoft-agent-framework-demos/README.md) |

All runnable demos are deterministic and require no model endpoint, API key, or Azure deployment.
Install or restore dependencies once, then the demonstrations run offline.

## Suggested learning path

1. **Understand the problem.** Read the opening sections of [the presentation deck](./Agent-Governance-Toolkit_v5.pptx) to learn how agents request tools, where execution happens, and why prompt-only safety is insufficient.
2. **Learn the AGT fundamentals.** Run the overview notebook in [C#](./dotnet-demos/1-agt-overview.verso) or [Python](./python-demos/1-agt-overview.ipynb). You will see policy evaluation, enforcement latency, and a zero-trust tool gate.
3. **Apply the controls to real risks.** Work through the OWASP notebook in [C#](./dotnet-demos/2-owasp-agentic-top-10.verso) or [Python](./python-demos/2-owasp-agentic-top-10.ipynb).
4. **Study a framework integration.** Explore the [Microsoft Agent Framework demos](./microsoft-agent-framework-demos/README.md) to see where governance middleware belongs in a real agent runtime.
5. **Experiment.** Change a policy rule, tool argument, trust level, or attack input and rerun the relevant scenario to observe the new deterministic decision.

You can follow the whole path or start directly in the runtime you already know.

## Hands-on notebooks

| Runtime | Start with the overview | Continue with OWASP 2026 | Guide |
|---|---|---|---|
| **.NET / C#** | [`1-agt-overview.verso`](./dotnet-demos/1-agt-overview.verso) | [`2-owasp-agentic-top-10.verso`](./dotnet-demos/2-owasp-agentic-top-10.verso) | [Verso run guide](./dotnet-demos/README.md) |
| **Python** | [`1-agt-overview.ipynb`](./python-demos/1-agt-overview.ipynb) | [`2-owasp-agentic-top-10.ipynb`](./python-demos/2-owasp-agentic-top-10.ipynb) | [Companion guide](./python-demos/2-owasp-agentic-top-10-companion-guide.md) |

### Verify the C# notebooks

Install the optional Verso CLI, then execute both notebooks headlessly from the repository root:

```powershell
dotnet tool install -g Verso.Cli
verso run .\src\agent-governance-toolkit\dotnet-demos\1-agt-overview.verso --fail-fast
verso run .\src\agent-governance-toolkit\dotnet-demos\2-owasp-agentic-top-10.verso --fail-fast
```

For an interactive learning experience, install the **Verso Notebook** VS Code extension, open a
`.verso` file, and choose **Run All**. See the [C# guide](./dotnet-demos/README.md) for the tested
cell counts and implementation notes.

### Run the Python notebooks

```powershell
cd .\src\agent-governance-toolkit\python-demos
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Open either `.ipynb` file, select the new environment as the kernel, and choose **Run All**.

## Learn from the Microsoft Agent Framework integration

The MAF integration demonstrates the production-shaped boundary around a real agent runtime:

- deterministic prompt governance before the model call;
- default-deny tool capability policy;
- one agent-level middleware that inspects **tool-call argument values**;
- allow, deny, and human-approval escalation paths;
- governed multi-agent workflows; and
- tamper-evident audit evidence.

Choose an implementation:

- [Python MAF demo](./microsoft-agent-framework-demos/python/README.md) - package, notebook, seven focused scripts, and offline verification.
- [.NET MAF demo](./microsoft-agent-framework-demos/dotnet/README.md) - class library, console application, policy files, and offline verification.

## Repository map

```text
agent-governance-toolkit/
|-- Agent-Governance-Toolkit_v5.pptx    # Presentation deck
|-- dotnet-demos/                       # C# Verso notebooks
|-- python-demos/                       # Python Jupyter notebooks + companion guide
|-- microsoft-agent-framework-demos/
|   |-- dotnet/                         # .NET MAF integration
|   `-- python/                         # Python MAF integration
`-- README.md
```

## What you will learn

- **The model proposes; the governed runtime disposes.** The model does not execute tools itself.
- **Policy is deterministic and explainable.** The same action and context produce the same decision.
- **Governance applies to arguments, not only tool names.** Amounts, targets, regions, and other values can be bounded centrally.
- **Controls compose.** Identity, MCP scanning, execution boundaries, circuit breakers, lifecycle controls, and auditing reinforce the policy gate.
- **Evidence matters.** Decisions can be inspected and tampering can be detected after the fact.

## Production note

These assets are optimized for learning and experimentation. A production
implementation must additionally address durable audit storage, identity and key management,
approval workflows, observability, availability, data protection, and organization-specific
security and compliance requirements.

## Learn more

- [Agent Governance Toolkit](https://github.com/microsoft/agent-governance-toolkit)
- [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
- [OWASP Top 10 for Agentic Applications 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)
- [Verso](https://github.com/DataficationSDK/Verso)
- [Back to Azure Scenario Hub](../../README.md)
