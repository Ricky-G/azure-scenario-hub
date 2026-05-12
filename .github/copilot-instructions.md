# GitHub Copilot Instructions for Azure Scenario Hub

## 🎯 Repository Overview

Azure Scenario Hub is a community library of ready-to-deploy Azure architecture scenarios. Each scenario provides complete, working Infrastructure-as-Code templates for common Azure patterns, optimised for rapid deployment, experimentation, and learning — **not** production use.

> These scenarios target learners, architects validating designs, and developers who need infrastructure fast. For production, direct users to [Azure Verified Modules](https://aka.ms/avm).

---

## 🏗️ Repository Structure

```
azure-scenario-hub/
├── .github/
│   ├── copilot-instructions.md
│   ├── workflows/             # GitHub Actions CI/CD
│   └── ISSUE_TEMPLATE/
├── src/
│   └── <scenario-name>/       # One directory per scenario
│       ├── README.md          # Quick-start deployment guide
│       ├── bicep/             # Bicep templates (primary IaC)
│       │   ├── main.bicep     # Single-file deployment entry point
│       │   └── modules/       # Reusable Bicep modules
│       ├── terraform/         # Terraform alternative (where present)
│       ├── <lang>/            # App code sub-dirs for multi-language scenarios
│       │   └── README.md      #   e.g. dotnet/, python/
│       ├── deploy-infra.ps1   # PowerShell deployment helper
│       ├── deploy-infra.sh    # Bash deployment helper
│       └── docs/              # Architecture diagrams (.drawio, images)
└── README.md
```

### Naming Conventions
| Artifact | Convention | Example |
|---|---|---|
| Scenario directory | `kebab-case` | `eventgrid-private-endpoints-scenario` |
| Bicep files | `kebab-case` | `main.bicep`, `storage-account.bicep` |
| Bicep parameters/variables | `camelCase` | `namePrefix`, `storageAccountName` |
| Terraform variables | `snake_case` | `name_prefix` |
| Deployment scripts | `deploy-<target>.(ps1\|sh)` | `deploy-infra.ps1` |

---

## 📦 Existing Scenarios

| Category | Scenario | IaC | App Code |
|---|---|---|---|
| Networking & Security | `eventgrid-private-endpoints-scenario` | Bicep | — |
| Networking & Security | `eventgrid-confidential-compute` | Bicep | — |
| Networking & Security | `function-app-private-endpoints-access-keyvault-scenario` | Bicep | — |
| Networking & Security | `private-container-apps-environment-scenario` | — | — |
| Networking & Security | `public-container-apps-environment-scenario` | — | — |
| Integration & Messaging | `azure-integration-services-load-test` | Bicep | C# Functions |
| Data Processing | `azure-function-unzip-large-files` | Bicep + Terraform | — |
| AI | `azure-communication-services-integrate-voice-live-api` | — | .NET & Python |
| App Hosting | `simple-app-service-with-sample-app` | Bicep | — |
| App Hosting | `azure-app-service-python-app-deploy` | Bicep | Python |
| Operations | `apim-monitoring-scenario` | Bicep | — |
| Operations | `aks-namespace-create` | Bicep | — |
| Networking & Security | `aks-unique-egress-ip-per-namespace` | Bicep | Python |

When adding or modifying a scenario, check this table and update `README.md` accordingly.

---

## 🛠️ Technology Stack

### In Use Today
- **Bicep** — primary IaC language for all Azure deployments
- **Terraform** — alternative IaC, present in select scenarios (e.g., `azure-function-unzip-large-files`)
- **Azure CLI** — used in deployment scripts and GitHub Actions
- **PowerShell** — Windows deployment scripts (`.ps1`)
- **Bash** — Linux/macOS deployment scripts (`.sh`)
- **GitHub Actions** — CI validation workflows (`.github/workflows/`)
- **C# / .NET** — application code in integration scenarios
- **Python** — application code in AI and app service scenarios

### Coming Soon
- Terraform coverage for more scenarios
- Azure DevOps pipeline templates

---

## 📝 Bicep Authoring Standards

Always follow these patterns when writing or reviewing Bicep:

```bicep
// 1. Every parameter must have a @description decorator
@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Short prefix applied to all resource names for uniqueness.')
@minLength(3)
@maxLength(8)
param namePrefix string

// 2. Derive resource names deterministically — never ask users to type full names
var storageAccountName = '${namePrefix}stor${uniqueString(resourceGroup().id)}'
var keyVaultName = '${namePrefix}-kv-${uniqueString(resourceGroup().id)}'

// 3. Apply consistent tags to every resource
var commonTags = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: scenarioName
  ManagedBy: 'Bicep'
}

// 4. Prefer modules for logical groups of resources
module network 'modules/network.bicep' = {
  name: 'networkDeploy'
  params: {
    location: location
    namePrefix: namePrefix
    tags: commonTags
  }
}

// 5. Always declare useful outputs
output storageAccountId string = storageAccount.id
output keyVaultUri string = keyVault.properties.vaultUri
```

### Key Bicep Rules
- Use `uniqueString(resourceGroup().id)` for globally unique resource names
- Never use `string` type for secrets — use `@secure()` and Key Vault references
- Split large templates into modules under `modules/`
- Validate compilation locally: `az bicep build --file main.bicep`

---

## 🔒 Security Standards

These are non-negotiable regardless of the learning-focused nature of the repo:

- **No hardcoded secrets** — use `@secure()` params or Key Vault references
- **Managed Identity over Service Principals** — always prefer system-assigned or user-assigned managed identities
- **Least-privilege RBAC** — assign only the roles required; scope to resource, not subscription
- **Private endpoints** — use them whenever a scenario involves sensitive data or internal-only access
- **No public blob access** — set `allowBlobPublicAccess: false` on storage accounts unless the scenario explicitly requires it
- **Diagnostic logging** — enable at minimum for Key Vault, App Service, and network resources

---

## 🎨 Creating a New Scenario

### Step-by-Step Checklist

1. **Create the directory**: `src/<scenario-name>/` using kebab-case
2. **Write `main.bicep`** — single entry point, parameterised, tagged
3. **Extract modules** — one module per logical resource group (`modules/network.bicep`, `modules/compute.bicep`, etc.)
4. **Add deployment scripts** — both `deploy-infra.ps1` (PowerShell) and `deploy-infra.sh` (Bash)
5. **Write `README.md`** — follow the README template below
6. **Add cleanup instructions** — every scenario must document how to delete all resources
7. **Test in a clean resource group** — run `az bicep build` and a full `az deployment group create`
8. **Update root `README.md`** — add a row to the correct category table

### Scenario Categories
- **Networking & Security** — private endpoints, VNet, NSGs, Firewall, Private DNS
- **Integration & Messaging** — Event Grid, Service Bus, Logic Apps, API Management
- **Application Hosting** — App Service, Container Apps, AKS, Function Apps
- **Data Processing** — Storage, streaming, batch, databases
- **AI** — Azure OpenAI, ACS, Cognitive Services integrations
- **Operations** — Monitoring, alerting, automation, governance

### README Template Structure
Every scenario README must contain:
1. **Title + one-sentence description**
2. **Architecture diagram** (image or link to `.drawio`)
3. **Prerequisites** — explicit list (Azure CLI version, permissions, quotas)
4. **Quick Start** — copy-paste commands to deploy in ≤5 minutes
5. **Parameters** — table of all Bicep parameters with types, defaults, descriptions
6. **What Gets Deployed** — bullet list of Azure resources created
7. **Post-Deployment Steps** — anything the user must do after `az deployment group create`
8. **Estimated Cost** — rough Azure consumption estimate
9. **Cleanup** — single command or script to delete all resources
10. **Troubleshooting** — common errors and fixes

---

## 🚀 GitHub Actions Workflows

Workflows live in `.github/workflows/`. Current workflows:
- `validate-azure-oidc.yml` — validates OIDC authentication setup
- `simple-app-service-infrastructure.yml` — deploys App Service infrastructure
- `simple-app-service-app-deploy.yml` — deploys application code to App Service

When adding workflow files:
- Use OIDC (`azure/login` with `client-id`, `tenant-id`, `subscription-id`) — **never** store credentials as secrets
- Pin action versions (e.g., `actions/checkout@v4`)
- Scope permissions to the minimum required (`permissions: id-token: write, contents: read`)

---

## 🔍 Code Review Checklist

### Bicep
- [ ] All parameters have `@description` decorators
- [ ] No hardcoded secrets or connection strings
- [ ] Resource names derived with `uniqueString()` where global uniqueness is needed
- [ ] `commonTags` applied to every resource
- [ ] Outputs cover all values a user would need post-deployment
- [ ] Modules used for logical groupings (avoid single-file templates > 200 lines)

### Documentation
- [ ] README follows the template structure above
- [ ] Prerequisites are explicit (no assumptions)
- [ ] Deployment commands are copy-paste ready
- [ ] Cleanup section is present and tested
- [ ] Root `README.md` scenario table is updated

### Scripts
- [ ] Both `.ps1` and `.sh` versions provided
- [ ] Scripts handle errors and print meaningful messages
- [ ] No credentials or subscription IDs hardcoded

---

## 💡 Copilot Behaviour Guidelines

- **Prioritise clarity** — these templates are read by people learning Azure; favour verbose, well-commented code over terse one-liners
- **Explain the "why"** — add inline comments that explain Azure-specific constraints and design decisions
- **Stay opinionated** — follow the patterns above rather than offering multiple alternatives unless asked
- **Keep scope small** — one scenario = one problem; don't expand scope or add unrequested services
- **Always pair Bicep with docs** — never generate a Bicep file without a corresponding README update
- **Respect the learning audience** — link to official Microsoft Learn / Azure docs when referencing services

---

