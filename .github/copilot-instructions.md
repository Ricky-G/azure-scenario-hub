# GitHub Copilot Instructions for Azure Scenario Hub

## 🎯 Repository Overview

Azure Scenario Hub is a community library of tested Azure cloud and Microsoft AI engineering scenarios. It includes deployable architectures, runnable demos, benchmarks, and evidence-backed investigations for experimentation and learning — **not** production use.

> Infrastructure scenarios should direct production users to [Azure Verified Modules](https://aka.ms/avm). Application and AI scenarios must identify the additional security, identity, reliability, and compliance work required before production use.

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
│       ├── README.md          # Quick-start deployment or run guide
│       ├── bicep/             # Bicep templates where applicable
│       │   ├── main.bicep     # Single-file deployment entry point
│       │   └── modules/       # Reusable Bicep modules
│       ├── terraform/         # Terraform alternative (where present)
│       ├── app/ or app.py     # Runnable implementation where applicable
│       ├── <lang>/            # Language sub-dirs for multi-language scenarios
│       │   └── README.md      #   e.g. dotnet/, python/
│       ├── tests/              # Validation, integration, or load tests
│       ├── deploy-infra.*      # Deployment helpers where applicable
│       └── docs/ or report/    # Architecture diagrams and evidence
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

## 📦 Scenario Types

- **Deployable** — reproducible Azure infrastructure, normally Bicep-first with deployment and cleanup scripts
- **Runnable Demo** — focused application or SDK example with isolated dependencies and tested run commands
- **Benchmark** — repeatable workload, methodology, raw evidence, and summarized results
- **Investigation** — reproducible diagnostic or platform-behavior proof with captured evidence

The root `README.md` and `docs/index.html` are the source of truth for the current scenario inventory. Update both whenever adding, removing, or renaming a scenario.

---

## 🛠️ Technology Stack

### In Use Today
- **Bicep** — primary IaC language for Azure deployments
- **Terraform** — alternative IaC, present in select scenarios (e.g., `azure-function-unzip-large-files`)
- **Azure CLI** — used in deployment scripts and GitHub Actions
- **PowerShell** — Windows deployment scripts (`.ps1`)
- **Bash** — Linux/macOS deployment scripts (`.sh`)
- **GitHub Actions** — CI validation workflows (`.github/workflows/`)
- **C# / .NET** — application code in integration scenarios
- **Python** — application code in AI and app service scenarios
- **Jupyter / Verso** — executable AI and governance walkthroughs
- **KQL / HTML** — diagnostics, benchmarks, and evidence reports

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

1. **Choose one scenario type** — deployable, runnable demo, benchmark, or investigation
2. **Create the directory** — `src/<scenario-name>/` using kebab-case
3. **Add the smallest complete implementation** — use Bicep for Azure infrastructure and the appropriate SDK/runtime for application behavior
4. **Add automation where applicable** — deployment, run, validation, and cleanup commands must be copy-paste ready
5. **Write `README.md`** — follow the README requirements below
6. **Test in a clean environment** — compile IaC, install exact dependencies, and run focused validation
7. **Update both catalogs** — add the scenario to root `README.md` and `docs/index.html`

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
4. **Quick Start** — copy-paste commands to deploy or run
5. **Configuration** — parameters or environment variables, with secrets clearly identified
6. **What It Deploys or Demonstrates** — explicit resources, behavior, and limits
7. **Post-Deployment or Run Steps** — anything required to exercise the scenario
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
- [ ] Deployment or run commands are copy-paste ready
- [ ] Cleanup section is present and tested
- [ ] Root `README.md` and `docs/index.html` are updated

### Runnable Demos
- [ ] Dependencies are pinned and install in a clean environment
- [ ] Secrets use environment variables or managed identity, never source code
- [ ] Focused offline tests or contract checks pass
- [ ] The README distinguishes demo code from production guidance

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

