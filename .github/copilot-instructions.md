# GitHub Copilot Instructions for Azure Scenario Hub

## 🎯 Repository Overview

This repository is a comprehensive library of Azure architecture scenarios designed for rapid deployment, testing, and learning. It provides infrastructure-as-code templates using primarily Bicep, with plans for Terraform support.

## 🏗️ Project Structure & Standards

### Directory Organization
```
src/
├── scenario-name/
│   ├── README.md              # Scenario documentation
│   ├── bicep/                 # Bicep templates
│   │   ├── main.bicep        # Primary deployment template
│   │   └── modules/          # Modular components
│   ├── terraform/            # Terraform (planned)
│   └── docs/                 # Additional documentation
```

### Naming Conventions
- **Scenarios**: Use kebab-case (e.g., `eventgrid-private-endpoints-scenario`)
- **Bicep Files**: Use kebab-case for files, camelCase for parameters
- **Resources**: Follow Azure naming conventions with consistent prefixes
- **Variables**: Use camelCase in Bicep, snake_case in Terraform

## 🛠️ Technology Stack

### Primary Technologies
- **Bicep**: Primary IaC tool for Azure deployments
- **Azure CLI**: For deployment automation
- **PowerShell**: Default shell environment (Windows)
- **Markdown**: Documentation standard

### Planned Technologies
- **Terraform**: Alternative IaC option
- **GitHub Actions**: CI/CD automation
- **Azure DevOps**: Enterprise deployment pipelines

## 📝 Code Generation Guidelines

### Bicep Templates
```bicep
// Always use descriptive parameter names and descriptions
@description('The location for all resources')
param location string = resourceGroup().location

@description('The name prefix for all resources')
param namePrefix string

// Use consistent resource naming
var storageAccountName = '${namePrefix}stor${uniqueString(resourceGroup().id)}'

// Include proper tags
var commonTags = {
  Environment: 'Development'
  Project: 'AzureScenarioHub'
  Scenario: scenarioName
}
```

### Documentation Standards
- Include clear prerequisites and deployment steps
- Provide parameter explanations and examples
- Add architecture diagrams where beneficial
- Include troubleshooting sections
- Reference Azure documentation links

## 🔒 Security Requirements

### Template Security
- Never hardcode secrets or credentials
- Use Key Vault references for sensitive data
- Implement least-privilege access principles
- Include network security configurations
- Enable diagnostic logging and monitoring

### Best Practices
- Use managed identities over service principals
- Implement private endpoints where appropriate
- Configure proper RBAC assignments
- Enable Azure Security Center recommendations

## 🎨 Scenario Development

### When Creating New Scenarios
1. **Research Phase**: Identify common Azure patterns needing simplification
2. **Architecture Design**: Create logical, well-documented infrastructure
3. **Implementation**: Build modular, reusable Bicep templates
4. **Documentation**: Write comprehensive README with deployment guide
5. **Testing**: Validate deployment in clean Azure subscription

### Scenario Categories
- **Networking & Security**: Private endpoints, VNet configurations, security patterns
- **Application Hosting**: App Services, Container Apps, Function Apps
- **Data & Analytics**: Storage, databases, analytics services
- **Integration**: Event Grid, Service Bus, Logic Apps
- **DevOps & Automation**: CI/CD patterns, monitoring, automation

## 🚀 Development Workflow

### File Creation Order
1. Create scenario directory structure
2. Develop main.bicep with core infrastructure
3. Build modular components in modules/ directory
4. Write comprehensive README.md
5. Add architecture diagrams (optional)
6. Include parameter examples and troubleshooting

### Testing Requirements
- Validate Bicep compilation: `bicep build main.bicep`
- Test deployment in isolated resource group
- Verify resource cleanup procedures
- Document any deployment prerequisites

## 📋 Template Requirements

### Every Scenario Must Include
- **README.md**: Complete deployment guide with prerequisites
- **main.bicep**: Primary infrastructure template
- **Parameter descriptions**: Clear explanations for all inputs
- **Resource tagging**: Consistent tagging strategy
- **Output values**: Useful information for post-deployment tasks

### Optional Enhancements
- **Architecture diagrams**: Visual representation of resources
- **PowerShell scripts**: Automation helpers
- **Sample applications**: Demo workloads for the infrastructure
- **Cost estimates**: Approximate Azure consumption costs

## 🔍 Code Review Guidelines

### Bicep Quality Checks
- Parameters have descriptions and appropriate types
- Resources use consistent naming conventions
- Outputs provide valuable post-deployment information
- Comments explain complex logic or configurations
- Modules are properly parameterized and reusable

### Documentation Quality
- Clear, step-by-step deployment instructions
- Prerequisites are explicitly listed
- Expected outcomes are described
- Troubleshooting guidance is provided
- Links to relevant Azure documentation

## 🎯 User Experience Focus

### Make It Easy
- Minimize required parameters where possible
- Provide sensible defaults for non-critical settings
- Include copy-paste deployment commands
- Explain the "why" behind architectural decisions
- Anticipate common configuration needs

### Support Learning
- Include educational comments in templates
- Explain Azure service interactions
- Reference official documentation
- Provide context for security configurations
- Show best practices in action

## 💡 Contribution Guidelines

### For New Contributors
- Follow established directory structure
- Use existing scenarios as templates
- Focus on common, reusable patterns
- Prioritize clarity over complexity
- Test thoroughly before submitting

### For Enhancements
- Maintain backward compatibility where possible
- Update documentation for any changes
- Consider impact on existing deployments
- Validate against current Azure service features

---

