# Contributing to Azure Scenario Hub

Thank you for helping make Azure Scenario Hub more useful. Contributions should teach, measure, or prove one focused Azure cloud or Microsoft AI engineering concept with working code, tested commands, and honest limitations.

## Scope

Good contributions have a clear Azure or Microsoft AI connection and fit one of the scenario types below. Generic tutorials, untested snippets, marketing-only samples, production claims without evidence, and unrelated framework demonstrations are out of scope.

For new agent scenarios, use **Microsoft Agent Framework**. Semantic Kernel agent examples are accepted only when they address support, interoperability, or migration of an existing Semantic Kernel estate; see the official [Semantic Kernel migration guide](https://learn.microsoft.com/agent-framework/migration-guide/from-semantic-kernel/).

## Before You Start

1. Search [existing issues](https://github.com/Ricky-G/azure-scenario-hub/issues) and the current [scenario catalog](README.md#-available-scenarios).
2. For a substantial new scenario, open a [feature request](https://github.com/Ricky-G/azure-scenario-hub/issues/new/choose) or start a [discussion](https://github.com/Ricky-G/azure-scenario-hub/discussions) before investing heavily.
3. Choose one scenario type and keep the implementation centered on one problem.
4. Read [SECURITY.md](SECURITY.md) before adding infrastructure, authentication, dependencies, or AI data flows.

## Choose a Scenario Type

| Type | Required outcome |
|---|---|
| **Deployable** | Reproducible Azure infrastructure with deployment automation, parameters, cost guidance, validation, and cleanup |
| **Runnable Demo** | A focused application, SDK, notebook, or agent example with isolated dependencies and repeatable run commands |
| **Benchmark** | A documented workload, methodology, environment, thresholds, raw evidence, and summarized results |
| **Investigation** | A reproducible diagnostic or platform-behavior proof with captured evidence and bounded conclusions |

## Required Structure

Create `src/<scenario-name>/` using kebab-case. Keep each scenario self-contained; do not introduce a repository-wide dependency unless the scenario genuinely requires it.

```text
src/<scenario-name>/
├── README.md
├── bicep/ or terraform/       # When infrastructure is required
├── app/ or app.py             # When application code is required
├── tests/ or test-harness/    # Focused validation
├── deploy-*.ps1 / deploy-*.sh # When deployment automation is required
└── docs/ or report/           # Diagrams and evidence
```

Every scenario README must include:

1. A title and one-sentence description
2. An architecture or execution-flow diagram
3. Explicit prerequisites, permissions, and quotas
4. Copy-paste quick-start commands
5. A configuration or parameter table
6. What the scenario deploys, demonstrates, or proves
7. Validation steps, expected results, and known limitations
8. Estimated Azure cost or a clear statement that it runs offline
9. Cleanup instructions that cover all billable resources and generated data
10. Troubleshooting guidance
11. Links to relevant Microsoft Learn documentation

Use `.env.example` for local configuration placeholders. Do not commit populated `.env` files, credentials, subscription IDs, private certificates, or generated secrets.

## Engineering Standards

### Deployable Scenarios

- Use Bicep as the primary Azure IaC language unless the scenario specifically investigates Terraform.
- Compile Bicep with `az bicep build` and test deployment in a clean resource group or subscription scope.
- Prefer managed identity, least-privilege resource-scoped RBAC, private networking where appropriate, and diagnostic logging.
- Derive globally unique resource names; do not require users to invent full names unnecessarily.
- Provide PowerShell and Bash helpers where practical, plus a complete cleanup path.
- Direct production users to [Azure Verified Modules](https://aka.ms/avm).

### Runnable Demos

- Pin direct dependencies and install them in an isolated environment.
- Prefer Microsoft Entra ID or managed identity. If an access-key fallback is included, identify it clearly as a fallback.
- Add focused offline tests, contract checks, or deterministic fixtures whenever a live Azure call is not required.
- Document model/deployment requirements, regional availability, device permissions, and any billable API calls.

### Benchmarks and Investigations

- Record the Azure region, service tier, test location, runtime versions, workload shape, and date.
- Preserve raw evidence or generated reports needed to reproduce the conclusion.
- Separate measured facts from interpretation, and document methodology traps or confounding variables.
- Never generalize beyond the tested configuration without saying so.

## Catalog and Website Updates

Adding, removing, or renaming a scenario requires updates to both:

1. The category table and counts in [README.md](README.md)
2. The searchable card, counts, and status in [docs/index.html](docs/index.html)

Use the existing statuses consistently: **Ready**, **Runnable**, **Legacy**, or **Coming Soon**. Validate the static gallery at desktop and mobile widths when changing its markup or styles.

## Security

- Never commit credentials, tokens, connection strings, private keys, populated environment files, or sensitive evidence.
- Prefer managed identity or Microsoft Entra ID over access keys and service principals.
- Scope RBAC assignments to the narrowest practical resource.
- Review new dependencies and pin versions that contain required security fixes.
- Explain the production-hardening gap for infrastructure, applications, AI agents, and data flows.
- Report suspected vulnerabilities privately by following [SECURITY.md](SECURITY.md), not through an issue or discussion.

## Validate Your Scenario

Before opening a pull request:

1. Test in a clean environment or resource group.
2. Compile and lint the files you changed.
3. Install exact dependencies from the committed manifests.
4. Run focused tests, contract checks, or the documented evidence workflow.
5. Verify cleanup removes or documents every billable resource.
6. Check all local links and update both catalogs.
7. Run `git diff --check` and review the final diff for generated files or secrets.

If live Azure validation is not possible, say exactly what was and was not tested. Do not mark a scenario Ready based only on static review.

## Pull Requests

Keep pull requests focused. The description should include:

- The problem and scenario type
- What changed and why
- Commands and environments used for validation
- Expected evidence or screenshots where relevant
- Azure cost incurred during testing
- Known limitations and production-hardening work
- A checklist confirming the root README and gallery were updated

By contributing, you agree that your contribution is licensed under this repository's [MIT License](LICENSE). Only submit code, media, data, and documentation that you have the right to contribute.

## Community Expectations

Follow the [Community Code of Conduct](CODE_OF_CONDUCT.md). Be respectful, specific, and evidence-led. Assume good intent, critique technical choices rather than people, protect private information, and help keep discussions useful for learners and practitioners.