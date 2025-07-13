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
| [Function App with Key Vault Private Endpoint](./src/function-app-private-endpoints-access-keyvault-scenario/) | Serverless functions accessing secrets securely via private network | ✅ Ready | Managed Identity, VNet integration, no internet traffic |
| [Private Container Apps Environment](./src/private-container-apps-environment-scenario/) | Microservices platform with complete network isolation | 🚧 Coming Soon | Internal load balancing, private ingress |
| [Public Container Apps Environment](./src/public-container-apps-environment-scenario/) | Container hosting with public accessibility | 🚧 Coming Soon | Auto-scaling, public endpoints |

### Integration & Messaging

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [Azure Integration Services Load Test](./src/azure-integration-services-load-test/) | Microservices architecture with Function Apps and Service Bus Premium | ✅ Ready | 5 independent functions, Service Bus topics, private endpoints, Application Insights telemetry |

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
- **Azure CLI** - [Install guide](https://docs.microsoft.com/cli/azure/install-azure-cli)
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