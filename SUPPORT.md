# Support

Azure Scenario Hub is a community-maintained learning and experimentation repository. Support covers the documented deployment, run, validation, and cleanup paths for scenarios in this repository.

> [!IMPORTANT]
> Support is provided on a best-effort basis with no service-level agreement. This repository is not an official Microsoft support channel and its scenarios are not production support commitments.

## Getting Help

### Before You Ask

1. Read the scenario README, including prerequisites, permissions, regional availability, cost, and cleanup.
2. Search [existing issues](https://github.com/Ricky-G/azure-scenario-hub/issues) and [discussions](https://github.com/Ricky-G/azure-scenario-hub/discussions).
3. Reproduce the problem from a clean environment using the documented commands.
4. Confirm your Azure subscription, tenant, selected region, quotas, and active CLI context.
5. Check [Azure Status](https://azure.status.microsoft/) and your subscription's Resource Health or Service Health blade.
6. Remove secrets, tokens, tenant data, subscription IDs, certificates, and personal information from all logs and screenshots.

### Choose the Right Channel

| Need | Channel |
|---|---|
| Reproducible scenario bug | [Bug report](https://github.com/Ricky-G/azure-scenario-hub/issues/new/choose) |
| New scenario or enhancement | [Feature request](https://github.com/Ricky-G/azure-scenario-hub/issues/new/choose) |
| Design question or community discussion | [GitHub Discussions](https://github.com/Ricky-G/azure-scenario-hub/discussions) |
| Security vulnerability | Follow [SECURITY.md](SECURITY.md) and report privately |
| Azure platform, billing, quota, or account incident | [Azure Support](https://azure.microsoft.com/support/create-ticket/) |

Do not use a public issue or discussion for security vulnerabilities or exposed credentials.

## What to Include

Every support request should include:

- Scenario name and link
- Scenario type: Deployable, Runnable Demo, Benchmark, Investigation, or Legacy Support
- Expected behavior and actual behavior
- Exact reproduction commands, with secrets redacted
- Complete error text and relevant logs
- Operating system and runtime/tool versions
- Azure region, service tier, deployment type, and authentication method when applicable
- Whether the failure occurs in a clean environment
- Validation or troubleshooting already attempted

### Deployable Scenarios

Also include the Azure CLI, Bicep, Terraform, PowerShell, or Bash version; deployment scope; resource provider registration state; quota information; and the failing deployment operation ID when available.

### Runnable AI and Agent Demos

Also include the Python or .NET version, dependency installation command, Azure endpoint type, model/deployment name without credentials, authentication method, and relevant device permissions. Confirm that your account has the documented Azure RBAC role.

For new agent development, use [Microsoft Agent Framework](https://learn.microsoft.com/agent-framework/overview/). The Semantic Kernel scenario is retained only for legacy support and migration reference.

### Benchmarks and Investigations

Also include the test location, timestamp, service tier, workload parameters, raw result path, and any deviation from the documented methodology. Performance results are not comparable when the environment or workload differs materially.

## Common Troubleshooting

### Authentication and Authorization

- Run `az account show` and confirm the tenant and subscription.
- Prefer Microsoft Entra ID or managed identity over access keys.
- Verify the documented RBAC role at the documented scope.
- With `DefaultAzureCredential`, remove conflicting environment credentials and run `az login` again.
- Never paste a credential into an issue. Revoke exposed credentials immediately.

### Deployment Failures

- Confirm required resource providers and preview features are registered.
- Check regional service/model availability and subscription quota.
- Inspect the Azure deployment operation details, not only the top-level error.
- Remove partially deployed lab resources before retrying when the README requires a clean deployment.
- Compile Bicep locally with `az bicep build` before deployment.

### Python and .NET Demos

- Create the scenario's own virtual environment and install its pinned manifest.
- Do not assume the repository-level environment contains every scenario dependency.
- Run the scenario's offline tests or contract checks before making a live Azure call.
- For audio demos, check microphone or speaker permission and the operating system's selected device.

### Cost and Cleanup

- Review the scenario's estimate before deployment.
- Run cleanup as soon as testing is complete, especially for APIM Premium, AKS, Application Gateway, and other continuously billed resources.
- Verify the resource group or individually scoped resources were actually deleted.
- Billing disputes and subscription charges must go through [Azure Support](https://azure.microsoft.com/support/create-ticket/).

## Support Boundaries

Maintainers can help with repository code and documented scenario behavior. They cannot provide production architecture approval, operate your Azure environment, access your tenant, guarantee response times, resolve Azure service incidents, or accept liability for costs incurred while running a scenario.

For production architecture, review the [Azure Well-Architected Framework](https://learn.microsoft.com/azure/well-architected/) and use [Azure Verified Modules](https://aka.ms/avm) for infrastructure building blocks.

## Useful Resources

- [Azure documentation](https://learn.microsoft.com/azure/)
- [Azure Architecture Center](https://learn.microsoft.com/azure/architecture/)
- [Bicep documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure CLI reference](https://learn.microsoft.com/cli/azure/)
- [Microsoft Foundry documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [Microsoft Agent Framework](https://learn.microsoft.com/agent-framework/overview/)

## Contributing Back

If you resolve a repository issue, consider documenting the fix, improving a troubleshooting section, or contributing a focused regression test. See [CONTRIBUTING.md](CONTRIBUTING.md).