# Contributing to Azure Scenario Hub

Azure Scenario Hub accepts focused, reproducible Azure cloud and Microsoft AI engineering scenarios. Contributions should teach or prove one useful thing with working code and tested commands.

## Choose a Scenario Type

- **Deployable**: Azure infrastructure with Bicep or Terraform, deployment automation, and cleanup instructions.
- **Runnable Demo**: A focused application or SDK example with isolated dependencies and a repeatable run path.
- **Benchmark**: A documented workload, methodology, raw evidence, and summarized results.
- **Investigation**: A reproducible diagnostic or platform-behavior proof with captured evidence.

Generic samples without an Azure or Microsoft AI engineering connection are out of scope. Keep each scenario centered on one problem.

## Required Structure

Create `src/<scenario-name>/` using kebab-case. Every scenario must include a `README.md` with:

1. A title and one-sentence description
2. An architecture or execution-flow diagram
3. Explicit prerequisites, permissions, and quotas
4. Copy-paste quick-start commands
5. A configuration or parameter table
6. What the scenario deploys, demonstrates, or proves
7. Estimated Azure cost or a clear statement that it runs offline
8. Cleanup instructions
9. Troubleshooting guidance
10. Links to relevant Microsoft Learn documentation

Infrastructure scenarios should include both PowerShell and Bash deployment helpers where practical. Runnable demos should pin dependencies and provide focused offline tests or contract checks.

## Security

- Never commit credentials, tokens, connection strings, certificates, or populated `.env` files.
- Prefer managed identity or Microsoft Entra ID over access keys.
- Scope RBAC assignments to the narrowest practical resource.
- Use `.env.example` files with obvious placeholder values when local configuration is required.
- Identify every place where a learning-oriented example requires additional production hardening.

## Validate Your Scenario

Before opening a pull request:

1. Test in a clean environment or resource group.
2. Compile Bicep with `az bicep build --file main.bicep` when applicable.
3. Install dependencies from the committed manifest and run focused tests.
4. Confirm cleanup removes or documents every billable resource.
5. Add the scenario to both `README.md` and `docs/index.html`.
6. Run `git diff --check` and review the final diff for generated files or secrets.

## Pull Requests

Explain the problem, what the scenario proves, how it was validated, and any Azure cost incurred during testing. Include screenshots or generated reports when they are part of the evidence, but do not commit transient build output.