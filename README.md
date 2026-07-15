# Azure Scenario Hub 🚀

A collection of tested Azure cloud and Microsoft AI engineering scenarios: deployable architectures, runnable demos, and evidence-backed experiments.

[![Live Site](https://img.shields.io/badge/Live%20Site-clouddev.blog-2ea44f?style=for-the-badge&logo=github&logoColor=white)](https://clouddev.blog/azure-scenario-hub/) [![Scenarios](https://img.shields.io/badge/Scenarios-23-4ea3ff?style=for-the-badge)](https://clouddev.blog/azure-scenario-hub/#scenarios) ![Formats](https://img.shields.io/badge/Formats-IaC%20%2B%20Demos%20%2B%20Reports-9b8cff?style=for-the-badge)

> 🌐 **Browse every scenario in the interactive gallery → [clouddev.blog/azure-scenario-hub](https://clouddev.blog/azure-scenario-hub/)** — featuring the styled [mTLS passthrough → APIM report](https://clouddev.blog/azure-scenario-hub/reports/app-gateway-mtls-passthrough-apim-validation/) and the [Terraform drift report](https://clouddev.blog/azure-scenario-hub/reports/terraform-drift-detection-shared-platform/).

> [!IMPORTANT]
> **These scenarios are built for experimentation, learning, and lab environments — not production.**
> For production infrastructure, use [Azure Verified Modules](https://aka.ms/avm). Before adapting any application or AI demo for production, apply your organization's security, identity, reliability, and compliance requirements.

## 🎯 What is this?

A focused catalog of reproducible Azure and Microsoft AI engineering work. Each entry provides working code, tested commands, and the evidence or documentation needed to understand what it proves.

### Use cases:
- **Deployable Architecture** - Provision Azure patterns with Bicep or Terraform
- **AI Engineering** - Run focused Azure AI and Microsoft agent framework examples
- **Architecture Validation** - Test designs with working reference implementations
- **Evidence-Based Research** - Reproduce benchmarks, diagnostics, and platform behavior
- **Hands-On Learning** - Start from complete examples instead of empty projects

## ⭐ Featured Scenario

<table>
<tr>
<td width="55%" valign="top">

### [APIM Backend Fan-out Benchmark](./src/apim-backend-fanout-benchmark/)

Head-to-head benchmark of **shared-`Backend` + `rewrite-uri`** vs **one-`Backend`-per-API** on APIM Premium.

**Result after 1.67M requests:** No measurable difference. **882 vs 874 req/s, 146 vs 153 ms p95, 0 errors** on both sides. Pick the pattern based on operational simplicity, not performance.

- 2× APIM Premium · .NET 10 mock backend on Flex Consumption FC1
- k6 stepped load: 50 → 100 → 200 VUs over ~32 min
- App Insights `BackendTime` / `ClientTime` KQL
- Interactive HTML dashboard + auto-generated Markdown report
- Includes the methodology trap that nearly made me publish the wrong answer

</td>
<td width="45%" valign="top">
<a href="./src/apim-backend-fanout-benchmark/"><img src="./src/apim-backend-fanout-benchmark/docs/dashboard.png" alt="APIM Backend Fan-out Benchmark dashboard"></a>
</td>
</tr>
</table>

## 🏗️ Available Scenarios

### Networking & Security

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [App Gateway PASSTHROUGH mTLS &rarr; APIM](./src/app-gateway-mtls-passthrough-apim-validation/) | How to do **true client-certificate (mTLS) validation in API Management** when App Gateway (WAF_v2) sits in front in **passthrough** mode: the gateway forwards the cert, **APIM validates it as a real credential** (possession + trust + per-client authorization), not a spoofable header. Includes the proof-of-possession analysis and an HTML report | ✅ Ready | mTLS passthrough (`verifyClientAuthMode`), server-variable header rewrite, APIM internal-VNet validation in policy, Key Vault-sourced Root CA + pinned allow list, WAF_v2 retained, evidence suite + styled report |
| [Event Grid with Private Endpoints](./src/eventgrid-private-endpoints-scenario/) | Secure event-driven architecture with Event Grid behind private endpoints | ✅ Ready | Zero public exposure, Logic Apps integration |
| [Event Grid Confidential Compute](./src/eventgrid-confidential-compute/) | Event Grid System Topic with Azure Confidential Compute enabled for enhanced data protection | ✅ Ready | Hardware-based encryption, preview feature, Korea Central & UAE North only |
| [Function App with Key Vault Private Endpoint](./src/function-app-private-endpoints-access-keyvault-scenario/) | Serverless functions accessing secrets securely via private network | ✅ Ready | Managed Identity, VNet integration, no internet traffic |
| [Private Container Apps Environment](./src/private-container-apps-environment-scenario/) | Microservices platform with complete network isolation | 🚧 Coming Soon | Internal load balancing, private ingress |
| [Public Container Apps Environment](./src/public-container-apps-environment-scenario/) | Container hosting with public accessibility | 🚧 Coming Soon | Auto-scaling, public endpoints |
| [AKS Static Egress Gateway](./src/aks-unique-egress-ip-per-namespace/) | Unique static egress IP per Kubernetes namespace, replicating OpenShift's EgressIP | ✅ Ready | Static Egress Gateway, per-namespace public/private IPs, gateway node pool, live dashboard |
| [AKS Namespace Create](./src/aks-namespace-create/) | Automated AKS namespace provisioning with Terraform and test manifests | 🚧 Coming Soon | Namespace bootstrap, RBAC scaffolding, test workloads |
| [App Service Easy Auth — Query String Round-Trip](./src/app-service-easy-auth/) | Proves App Service Easy Auth preserves arbitrary custom query string params (`nhi`, `login_hint`, `view`, …) across the full Microsoft Entra ID sign-in redirect — with **zero auth code in the app** | ✅ Ready | Easy Auth v2 + Entra ID, hybrid OAuth flow (`code+id_token` / `form_post`), `login_hint` auto-forwarded to Entra, claims via `x-ms-client-principal`, Mermaid sequence diagram, captured-traffic validation, Node 20 sample app |

### Integration, API Management & Messaging

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [APIM Backend Fan-out Benchmark](./src/apim-backend-fanout-benchmark/) | Head-to-head benchmark of **shared-backend + `rewrite-uri`** vs **one-backend-per-API** on APIM Premium. **Result: no measurable difference** — 882 vs 874 req/s, 146 vs 153 ms p95 over 1.67M requests | ✅ Ready | 2× APIM Premium, .NET 10 mock backend on Flex Consumption FC1, k6 stepped load (50→100→200 VUs), interactive HTML dashboard, App Insights `BackendTime`/`ClientTime` KQL, auto-generated Markdown report |
| [APIM Monitoring](./src/apim-monitoring-scenario/) | APIM Developer SKU with 6 mock APIs, Application Insights, Log Analytics, and an Azure Workbook dashboard — no backend services required | ✅ Ready | Full request/response capture, 6 mock APIs (caching, rate limiting, JWT, etc.), KQL queries, Azure Workbook |
| [App Gateway + APIM Diagnostics](./src/app-gateway-apim-diagnostics/) | Application Gateway (WAF_v2) fronting APIM with **every diagnostic setting enabled** on both resources, streaming to one Log Analytics Workspace. Includes a self-contained Hello World API routed end-to-end through the gateway | ✅ Ready | Full App Gateway + APIM diagnostic categories, WAF firewall logs, mock Hello World API (no backend), public route through App Gateway → APIM, ready-to-run KQL queries |
| [Azure Integration Services Load Test](./src/azure-integration-services-load-test/) | Load testing scenario for microservices architecture with Function Apps and Service Bus Premium | ✅ Ready | 5 independent functions, Service Bus topics, private endpoints, comprehensive load testing tools |

### Data Processing

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [Azure Function - Unzip Large Files](./src/azure-function-unzip-large-files/) | Stream-process large password-protected ZIP files (up to 10GB+) in serverless Functions | ✅ Ready | Streaming architecture, constant memory usage, handles files larger than available RAM, staged blob uploads |

### AI

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [Azure Communication Services with Voice Live API](./src/azure-communication-services-integrate-voice-live-api/) | Real-time conversational AI over phone calls with ACS Call Automation and Azure OpenAI Voice Live API | ✅ Ready | Phone call automation, real-time audio streaming, voice AI interactions, dual implementation ([.NET](./src/azure-communication-services-integrate-voice-live-api/dotnet/README.md) & [Python](./src/azure-communication-services-integrate-voice-live-api/python/README.md)) |
| [AI Gateway (APIM in front of Foundry)](./src/ai-gateway/) | API Management as an AI Gateway fronting an existing Azure AI Foundry account. Two customer-facing regional APIs (`/aue`, `/global`) over a shared backend pool, per-app token chargeback, per-product TPM throttling, response cache, and a runnable Polyglot Notebook walkthrough | ✅ Ready | Two regional APIs over one backend pool with circuit breakers, managed-identity backend auth, per-product TPM throttling, response cache, edge request validation, mock fallback, structured tracing, `azure-openai-emit-token-metric` chargeback, KQL queries, demo notebook |
| [Azure OpenAI Realtime Transcription](./src/azure-openai-realtime-transcription/) | **Runnable demo.** Streams 24 kHz microphone audio to a deployed `gpt-realtime-whisper` model over the GA Realtime API | ✅ Runnable | Entra ID with API-key fallback, async WebSockets, PCM16 capture, transcript events, language and delay controls |
| [Azure OpenAI Realtime Text to Speech](./src/azure-openai-realtime-text-to-speech/) | **Runnable demo.** Sends terminal text to a GA realtime model and plays its native audio response while streaming the transcript | ✅ Runnable | Current OpenAI realtime client, Entra ID with API-key fallback, direct PCM speaker output, explicit deployment and voice selection |
| [Azure Speech SSML Voice Consistency](./src/azure-speech-ssml-voice-consistency/) | **Runnable demo.** Applies one escaped, reusable SSML voice profile to every Azure Speech synthesis request | ✅ Runnable | Structured XML generation, consistent voice/rate/pitch/volume, WAV output, cancellation diagnostics |
| [Semantic Kernel Agent Retry Limit (Legacy Support)](./src/semantic-kernel-agent-retry-limit/) | **Legacy support demo.** Retained for existing Semantic Kernel applications and migration reference. [Microsoft Agent Framework](https://learn.microsoft.com/agent-framework/overview/) is the direct successor and recommended path for new agent development | 🟠 Legacy | Semantic Kernel `ChatCompletionAgent`, deterministic retry state machine, offline tests, links to the official Agent Framework migration guide |
| [Agent Governance Toolkit - Governed Agents](./src/agent-governance-toolkit/) | Offline, ready-to-run examples for the **Microsoft Agent Governance Toolkit**, including paired live notebooks in [C# with Verso](./src/agent-governance-toolkit/dotnet-demos/README.md) and [Python with Jupyter](./src/agent-governance-toolkit/python-demos/README.md), plus a **[Microsoft Agent Framework](./src/agent-governance-toolkit/microsoft-agent-framework-demos/README.md)** integration in both languages. Demonstrates one agent-level policy intercepting prompts and tool calls, including argument values, before execution | ✅ Ready | C# and Python live notebooks, OWASP Agentic Top 10 2026, agent-level tool-argument boundaries, prompt + tool middleware, default-deny capability sandbox, governed workflows, tamper-evident audit |

### App Hosting

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [Simple App Service with Sample App](./src/simple-app-service-with-sample-app/) | Lightweight App Service hosting a Python sample application | ✅ Ready | Zero-to-deployed in minutes, configurable SKU, VNet integration option |

### Governance & Operations

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [Terraform Drift Detection — Shared Platform vs. App Team](./src/terraform-drift-detection-shared-platform/) | Pinpoints **exactly where Terraform drift triggers** between a platform team's Terraform landing zone and an app team's Bicep additions. **Result from a real run:** adding child resources (Foundry projects, Cosmos databases, blob containers) causes **zero drift** — only changing a *managed attribute* (e.g. a tag) crosses the line. Includes a styled HTML report of every run | ✅ Ready | Platform Terraform (azurerm + azapi) vs app-team Bicep, serverless Cosmos + project-capable Foundry, full-`plan` drift checks, child-resource vs managed-attribute boundary, `ignore_changes` escape hatch, Azure Policy drift finding, HTML report + raw run captures |

### More scenarios coming soon!
Have a specific scenario request? [Open an issue](https://github.com/Ricky-G/azure-scenario-hub/issues) to suggest it.

## 🚀 Get Started in 3 Steps

### 1. Clone this repo
```bash
git clone https://github.com/Ricky-G/azure-scenario-hub.git
cd azure-scenario-hub
```

### 2. Pick a scenario
Browse the `src/` directory and choose the architecture, demo, benchmark, or investigation you need.

### 3. Deploy or run
Follow that scenario's README. Infrastructure scenarios provide deployment commands; application demos provide isolated setup and run commands.

## 📋 What You'll Need

- **Azure Subscription** - Required by scenarios that call or deploy Azure services; [create one here](https://azure.microsoft.com/free/)
- **Azure CLI** - Used for deployments and recommended keyless authentication; [installation guide](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **Scenario Runtime** - Check the selected README for Python, .NET, PowerShell, Bash, notebook, or load-testing prerequisites

## 🛠️ Tech Stack

The catalog uses the tool that best fits the scenario:
- **Bicep and Terraform** - Reproducible Azure infrastructure
- **Python and .NET** - Runnable applications, AI integrations, and test harnesses
- **PowerShell and Bash** - Deployment, validation, and cleanup automation
- **Jupyter and Verso** - Executable walkthroughs and offline demos
- **KQL and HTML reports** - Diagnostics, benchmarks, and captured evidence

## 📂 What's in Each Scenario?

```
scenario-name/
├── README.md              # Quick start guide
├── bicep/                 # Optional infrastructure code
├── terraform/             # Optional Terraform alternative
├── app/ or app.py         # Optional runnable implementation
├── tests/                 # Optional validation or load harness
└── docs/ or report/       # Optional diagrams and evidence
```

## 💡 Pro Tips

- **Choose the Scenario Type** - Deployable, runnable, benchmark, and investigation entries have different prerequisites
- **Customize Freely** - Use these as starting templates for your needs
- **Cost Conscious** - Each scenario notes estimated costs
- **Clean Up** - Follow each README to stop local processes and remove billable Azure resources

## 🤝 Contributing

To contribute a new Azure scenario:

1. Fork this repository
2. Create your scenario following the established structure
3. Test the deployment or runnable demo in a clean environment
4. Submit a pull request

Check the [Contributing Guide](CONTRIBUTING.md) for detailed requirements.

## 📞 Need Help?

- **Questions?** [Open an issue](https://github.com/Ricky-G/azure-scenario-hub/issues)
- **Bug reports** - Submit detailed reproduction steps
- **General discussion** - Use [discussions](https://github.com/Ricky-G/azure-scenario-hub/discussions)

## 📝 License

MIT License - feel free to use these scenarios however you like!

## 🔒 Security

- Scenarios use security best practices but are optimized for learning
- Always review and harden configurations before production use
- Found a security issue? See [SECURITY.md](SECURITY.md)

---

<p align="center">
  Made with ❤️ for the Azure community<br/>
  <strong>Star ⭐ this repo if you find it helpful!</strong>
</p>