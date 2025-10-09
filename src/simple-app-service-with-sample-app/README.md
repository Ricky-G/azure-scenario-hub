# Simple App Service with Python Sample App

A straightforward Azure scenario demonstrating how to deploy a Python Flask application to Azure App Service using Bicep infrastructure-as-code.

## 📋 Overview

This scenario provides:
- **Bicep templates** for deploying Azure App Service infrastructure
- **Python Flask application** with a Hello World example
- **Deployment automation** scripts for easy setup

Perfect for learning Azure App Service basics or as a starting point for your own Python web applications.

## 🏗️ Architecture

This scenario deploys:

1. **App Service Plan** (Linux-based)
   - Configurable SKU (Free, Basic, Standard, Premium)
   - Linux OS for Python runtime

2. **App Service** (Web App)
   - Python runtime (3.8 - 3.12 supported)
   - HTTPS enforced
   - Built-in deployment support

## 📁 Project Structure

```
simple-app-service-with-sample-app/
├── bicep/
│   ├── main.bicep              # Main infrastructure template
│   ├── main.parameters.json    # Parameter configuration
│   └── deploy.ps1              # Deployment script
├── sample-app/
│   ├── app.py                  # Flask application
│   ├── requirements.txt        # Python dependencies
│   ├── .gitignore             # Python gitignore
│   └── README.md              # App-specific documentation
└── README.md                   # This file
```

## 🚀 Quick Start

### Prerequisites

- **Azure Subscription**: [Free account available](https://azure.microsoft.com/free/)
- **Azure CLI**: [Installation guide](https://docs.microsoft.com/cli/azure/install-azure-cli)
- **Python 3.11+**: For local testing (optional)

### Step 1: Deploy Infrastructure

1. **Clone the repository:**
   ```powershell
   git clone https://github.com/Ricky-G/azure-scenario-hub.git
   cd azure-scenario-hub/src/simple-app-service-with-sample-app
   ```

2. **Login to Azure:**
   ```powershell
   az login
   ```

3. **Deploy using the PowerShell script:**
   ```powershell
   cd bicep
   .\deploy.ps1 -ResourceGroupName "rg-simpleapp-dev" -Location "eastus"
   ```

   Or deploy manually with Azure CLI:
   ```powershell
   # Create resource group
   az group create --name rg-simpleapp-dev --location eastus

   # Deploy template
   az deployment group create `
     --name simpleapp-deployment `
     --resource-group rg-simpleapp-dev `
     --template-file main.bicep `
     --parameters main.parameters.json
   ```

### Step 2: Deploy the Application

After infrastructure is deployed, deploy your Python app:

```powershell
cd ..\sample-app

# Get the App Service name from deployment outputs
az webapp deployment source config-zip `
  --resource-group rg-simpleapp-dev `
  --name <your-app-service-name> `
  --src sample-app.zip

# Or use 'az webapp up' for automatic deployment
az webapp up `
  --name <your-app-service-name> `
  --resource-group rg-simpleapp-dev `
  --runtime "PYTHON:3.11"
```

### Step 3: Verify Deployment

Visit your App Service URL (displayed in deployment outputs):
```
https://<your-app-service-name>.azurewebsites.net
```

You should see the Hello World page with application information.

## 🎛️ Configuration

### Bicep Parameters

Edit `bicep/main.parameters.json` to customize your deployment:

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `location` | Azure region | `eastus` | Any Azure region |
| `namePrefix` | Resource name prefix | `simpleapp` | Any string |
| `environment` | Environment name | `dev` | dev, test, prod, etc. |
| `appServicePlanSkuName` | Service plan tier | `B1` | F1, B1, B2, B3, S1, S2, S3, P1v2, P2v2, P3v2 |
| `pythonVersion` | Python runtime version | `3.11` | 3.8, 3.9, 3.10, 3.11, 3.12 |

### SKU Selection Guide

- **F1 (Free)**: Good for development, limited resources, no custom domains
- **B1 (Basic)**: Small production workloads, custom domains, SSL
- **S1 (Standard)**: Auto-scaling, deployment slots, more resources
- **P1v2 (Premium)**: High performance, advanced scaling, VNet integration

## 🧪 Local Testing

Test the Python application locally before deploying:

```powershell
cd sample-app

# Create virtual environment
python -m venv venv
.\venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt

# Run the app
python app.py
```

Visit `http://localhost:5000` to see your app running locally.

## 📊 Deployment Outputs

After successful deployment, you'll receive:

- **App Service Plan Name**: The name of your App Service Plan
- **App Service Name**: The name of your Web App
- **App Service URL**: The public URL of your application
- **Resource Group Name**: The resource group containing all resources

## 🔒 Security Considerations

This template implements several security best practices:

- ✅ HTTPS Only enabled
- ✅ TLS 1.2 minimum version
- ✅ FTPS disabled
- ✅ Managed identity support (for future enhancements)

## 💰 Cost Estimation

Approximate monthly costs (varies by region):

- **F1 (Free)**: $0 (limited features)
- **B1 (Basic)**: ~$13-15 USD
- **S1 (Standard)**: ~$70-75 USD
- **P1v2 (Premium)**: ~$150-160 USD

[Use Azure Pricing Calculator for detailed estimates](https://azure.microsoft.com/pricing/calculator/)

## 🔧 Troubleshooting

### Deployment Issues

**Problem**: Deployment fails with "App Service Plan SKU not available"
- **Solution**: Check SKU availability in your region using:
  ```powershell
  az appservice list-locations --sku B1
  ```

**Problem**: Python app doesn't start
- **Solution**: Check Application Logs in Azure Portal or use:
  ```powershell
  az webapp log tail --name <app-name> --resource-group <rg-name>
  ```

### Application Issues

**Problem**: 404 or default page shows instead of app
- **Solution**: Verify deployment and check startup command:
  ```powershell
  az webapp config show --name <app-name> --resource-group <rg-name>
  ```

## 🎯 Next Steps

- **Add CI/CD**: Set up GitHub Actions for automated deployments
- **Custom Domain**: Configure a custom domain name
- **Application Insights**: Add monitoring and telemetry
- **Database**: Connect to Azure SQL or Cosmos DB
- **Scaling**: Configure auto-scaling rules

## 📚 Additional Resources

- [Azure App Service Documentation](https://docs.microsoft.com/azure/app-service/)
- [Python on Azure App Service](https://docs.microsoft.com/azure/app-service/quickstart-python)
- [Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
- [Flask Documentation](https://flask.palletsprojects.com/)

## 🤝 Contributing

This scenario is part of the Azure Scenario Hub. Contributions and improvements are welcome!

## 📄 License

This project is part of the Azure Scenario Hub repository. See the main repository for license information.

---

**Questions or Issues?** Open an issue in the [Azure Scenario Hub repository](https://github.com/Ricky-G/azure-scenario-hub/issues).
