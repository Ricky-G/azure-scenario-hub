# Azure Scenario Hub 🚀

A collection of ready-to-deploy Azure architecture scenarios. Infrastructure-as-code templates for common patterns, designed for rapid deployment and learning.

> **Note**: These scenarios are designed for experimentation, learning, and lab environments. For production deployments, consider using [Azure Verified Modules](https://aka.ms/avm) and follow your organization's security and compliance requirements.

## 🎯 What is this?

A collection of Azure infrastructure templates for experimentation and learning. Each scenario provides complete working code for common architectural patterns, eliminating the need to build from scratch.

### Use cases:
- **Application Development** - Deploy infrastructure quickly to focus on application logic
- **Architecture Validation** - Test designs with working reference implementations  
- **Learning Azure** - Hands-on examples of Azure service integrations
- **Rapid Prototyping** - Pre-built infrastructure for PoCs and experiments

## 🏗️ Available Scenarios

### Networking & Security

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [Event Grid with Private Endpoints](./src/eventgrid-private-endpoints-scenario/) | Secure event-driven architecture with Event Grid behind private endpoints | ✅ Ready | Zero public exposure, Logic Apps integration |
| [Event Grid Confidential Compute](./src/eventgrid-confidential-compute/) | Event Grid System Topic with Azure Confidential Compute enabled for enhanced data protection | ✅ Ready | Hardware-based encryption, preview feature, Korea Central & UAE North only |
| [Function App with Key Vault Private Endpoint](./src/function-app-private-endpoints-access-keyvault-scenario/) | Serverless functions accessing secrets securely via private network | ✅ Ready | Managed Identity, VNet integration, no internet traffic |
| [Private Container Apps Environment](./src/private-container-apps-environment-scenario/) | Microservices platform with complete network isolation | 🚧 Coming Soon | Internal load balancing, private ingress |
| [Public Container Apps Environment](./src/public-container-apps-environment-scenario/) | Container hosting with public accessibility | 🚧 Coming Soon | Auto-scaling, public endpoints |
| [AKS Static Egress Gateway](./src/aks-unique-egress-ip-per-namespace/) | Unique static egress IP per Kubernetes namespace, replicating OpenShift's EgressIP | ✅ Ready | Static Egress Gateway, per-namespace public/private IPs, gateway node pool, live dashboard |

### Integration & Messaging

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [Azure Integration Services Load Test](./src/azure-integration-services-load-test/) | Load testing scenario for microservices architecture with Function Apps and Service Bus Premium | ✅ Ready | 5 independent functions, Service Bus topics, private endpoints, comprehensive load testing tools |

### Data Processing

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [Azure Function - Unzip Large Files](./src/azure-function-unzip-large-files/) | Stream-process large password-protected ZIP files (up to 10GB+) in serverless Functions | ✅ Ready | Streaming architecture, constant memory usage, handles files larger than available RAM, staged blob uploads |

### AI

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [Azure Communication Services with Voice Live API](./src/azure-communication-services-integrate-voice-live-api/) | Real-time conversational AI over phone calls with ACS Call Automation and Azure OpenAI Voice Live API | ✅ Ready | Phone call automation, real-time audio streaming, voice AI interactions, dual implementation ([.NET](./src/azure-communication-services-integrate-voice-live-api/dotnet/README.md) & [Python](./src/azure-communication-services-integrate-voice-live-api/python/README.md)) |

### App Hosting

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [App Service — Python with Private Networking](./src/azure-app-service-python-app-deploy/) | P1v3 Linux App Service in Australia East with private inbound (Private Endpoint) and private outbound (VNet Integration) | ✅ Ready | Private Endpoint, VNet Integration, `vnetRouteAllEnabled`, System-assigned MI, Python 3.11 Flask app |
| [Simple App Service with Sample App](./src/simple-app-service-with-sample-app/) | Lightweight App Service hosting a Python sample application | ✅ Ready | Zero-to-deployed in minutes, configurable SKU, VNet integration option |

### More scenarios coming soon! 
Have a specific scenario request? [Open an issue](https://github.com/Ricky-G/azure-scenario-hub/issues) to suggest it.

## 🚀 Get Started in 3 Steps

### 1. Clone this repo
```bash
git clone https://github.com/Ricky-G/azure-scenario-hub.git
cd azure-scenario-hub
```

### 2. Pick a scenario
Browse the `src/` directory and choose the architecture you need.

### 3. Deploy!
Each scenario includes deployment instructions with tested commands. Most deployments complete in under 5 minutes.

## 📋 What You'll Need

- **Azure Subscription** - [Get a free one here](https://azure.microsoft.com/free/)
- **Azure CLI** - [Install guide](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **5 minutes** - Standard deployment time

## 🛠️ Tech Stack

All scenarios are built with Infrastructure as Code:
- **Bicep** - Azure's native IaC language (primary)
- **Terraform** - Multi-cloud IaC (coming to more scenarios)
- **ARM Templates** - Available for all Bicep scenarios

## 📂 What's in Each Scenario?

```
scenario-name/
├── README.md              # Quick start guide
├── bicep/                 # Infrastructure code
│   ├── main.bicep        # One-click deployment
│   └── modules/          # Reusable components
├── terraform/            # Alternative IaC option
└── docs/                 # Architecture diagrams
```

## 💡 Pro Tips

- **Development First** - These scenarios prioritize ease of use and learning
- **Customize Freely** - Use these as starting templates for your needs
- **Cost Conscious** - Each scenario notes estimated costs
- **Clean Up** - Every scenario includes cleanup commands to avoid charges

## 🤝 Contributing

To contribute a new Azure scenario:

1. Fork this repository
2. Create your scenario following the established structure
3. Test deployment in a clean Azure subscription
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
  Made with ❤️ by the Azure community<br/>
  <strong>Star ⭐ this repo if you find it helpful!</strong>
</p>