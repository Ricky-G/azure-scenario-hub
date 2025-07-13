# Azure Scenario Hub 🚀

Welcome to the Azure Scenario Hub - your one-stop collection of ready-to-deploy Azure architectures! Whether you're learning Azure, building a proof-of-concept, or need a quick start for your next project, you'll find battle-tested scenarios here.

## 🎯 What is this?

Think of this repository as your Azure cookbook. Each "recipe" is a complete, working scenario that demonstrates real-world Azure patterns. Just pick a scenario, deploy it, and start experimenting!

### Perfect for:
- **Developers** - Skip the boilerplate and focus on building your application
- **Architects** - Validate designs with working reference implementations  
- **Students** - Learn Azure with hands-on, practical examples
- **Teams** - Accelerate PoCs and demos with pre-built infrastructure

## 🏗️ Available Scenarios

### Networking & Security

| Scenario | Description | Status | Key Features |
|----------|-------------|--------|--------------|
| [Event Grid with Private Endpoints](./src/eventgrid-private-endpoints-scenario/) | Secure event-driven architecture with Event Grid behind private endpoints | ✅ Ready | Zero public exposure, Logic Apps integration |
| [Function App with Key Vault Private Endpoint](./src/function-app-private-endpoints-access-keyvault-scenario/) | Serverless functions accessing secrets securely via private network | ✅ Ready | Managed Identity, VNet integration, no internet traffic |
| [Private Container Apps Environment](./src/private-container-apps-environment-scenario/) | Microservices platform with complete network isolation | 🚧 Coming Soon | Internal load balancing, private ingress |
| [Public Container Apps Environment](./src/public-container-apps-environment-scenario/) | Container hosting with public accessibility | 🚧 Coming Soon | Auto-scaling, public endpoints |

### More scenarios coming soon! 
Want to see a specific scenario? [Open an issue](https://github.com/Ricky-G/azure-scenario-hub/issues) and let us know!

## 🚀 Get Started in 3 Steps

### 1. Clone this repo
```bash
git clone https://github.com/Ricky-G/azure-scenario-hub.git
cd azure-scenario-hub
```

### 2. Pick a scenario
Browse the `src/` directory and choose the architecture you need.

### 3. Deploy!
Each scenario has a simple README with copy-paste commands. Most deploy in under 5 minutes!

## 📋 What You'll Need

- **Azure Subscription** - [Get a free one here](https://azure.microsoft.com/free/)
- **Azure CLI** - [Install guide](https://docs.microsoft.com/cli/azure/install-azure-cli)
- **5 minutes** - Seriously, that's it!

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

Got a cool Azure scenario? We'd love to include it!

1. Fork this repository
2. Create your scenario following our structure
3. Make sure it deploys successfully
4. Submit a pull request

Check our [Contributing Guide](CONTRIBUTING.md) for details.

## 📞 Need Help?

- **Questions?** [Open an issue](https://github.com/Ricky-G/azure-scenario-hub/issues)
- **Found a bug?** Let us know!
- **Want to chat?** Start a [discussion](https://github.com/Ricky-G/azure-scenario-hub/discussions)

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