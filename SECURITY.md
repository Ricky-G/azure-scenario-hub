# Security Policy

Azure Scenario Hub contains learning-oriented infrastructure, applications, scripts, notebooks, policies, benchmarks, and captured evidence. Security reports affecting any of these artifacts are welcome.

## Supported Versions

| Version | Security support |
|---|---|
| Default branch (`main`) and latest release | Reviewed and updated on a best-effort basis |
| Older tags, branches, forks, or copied deployments | Not actively patched; reproduce against `main` before reporting |

This repository is not a hosted service and does not provide a production security SLA.

## Report a Vulnerability Privately

**Do not open a public issue or discussion for a suspected vulnerability.** Private vulnerability reporting is enabled for this repository.

Use GitHub's **[Report a vulnerability](https://github.com/Ricky-G/azure-scenario-hub/security/advisories/new)** form. This creates a private advisory visible only to the reporter and repository maintainers while the issue is assessed.

If a credential or secret has been exposed, revoke or rotate it immediately. Do not wait for maintainer acknowledgement and do not include the live value in the report.

### What to Include

Provide enough information to reproduce and assess the issue safely:

- Affected scenario, file, branch, and commit
- Vulnerability description and realistic impact
- Required Azure configuration, permissions, and deployment scope
- Minimal reproduction steps or proof of concept
- Whether exploitation requires a secret, privileged identity, network position, or deployed resource
- Suggested mitigation or fix, if known
- Any disclosure deadline or existing public disclosure

Redact tenant data, subscription IDs, access tokens, private certificates, customer content, and personal information. Maintainers do not need access to your Azure environment.

## In Scope

- Insecure defaults or privilege escalation in Bicep or Terraform
- Authentication, authorization, certificate, or managed-identity bypasses
- Public exposure of resources that the scenario claims are private
- Secret leakage through source, logs, reports, notebooks, workflows, or generated artifacts
- Injection, unsafe deserialization, path traversal, request forgery, or code execution in runnable demos
- Material dependency vulnerabilities in directly used code paths
- Agent tool-call, argument, data-boundary, or audit-control bypasses where the scenario claims enforcement
- Documentation that directs users to expose credentials or deploy an unsafe configuration

General hardening suggestions, unsupported production adaptations, Azure platform incidents, quota problems, and ordinary deployment errors are not vulnerabilities in this repository. Use [SUPPORT.md](SUPPORT.md) or [Azure Support](https://azure.microsoft.com/support/create-ticket/) instead.

## Handling and Disclosure

Reports are handled on a best-effort basis. Maintainers will validate the issue against the default branch, assess impact, and coordinate a fix and disclosure when appropriate. Complex Azure or third-party behavior may require additional validation.

Please allow maintainers a reasonable opportunity to investigate before public disclosure. Do not access data, identities, subscriptions, or resources that you do not own or have explicit permission to test.

## Security Baseline for Contributions

All contributions must follow these minimum expectations:

- No hardcoded credentials, tokens, connection strings, private keys, subscription IDs, or populated `.env` files
- Microsoft Entra ID or managed identity preferred over keys and service principals
- Least-privilege RBAC scoped to the narrowest practical resource
- Public network access disabled when the scenario claims private isolation
- Encryption in transit and at rest using supported Azure controls
- Dependency versions reviewed and patched when a known vulnerability affects the scenario
- Diagnostic output and captured evidence scrubbed of sensitive data
- AI inputs, outputs, tool arguments, and third-party data flows documented and bounded
- Production-hardening gaps stated explicitly

See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete engineering and validation requirements.

## Responsibilities for Users

These scenarios are designed for experimentation, learning, and lab environments. Before adapting one for production:

- Review every template, script, policy, dependency, and application code path.
- Replace learning-oriented defaults with your organization's approved identity, network, logging, backup, availability, data-retention, and compliance controls.
- Use [Azure Verified Modules](https://aka.ms/avm) for production infrastructure building blocks.
- Run threat modeling, security testing, dependency scanning, and policy validation in your own environment.
- For AI and agent scenarios, evaluate prompt injection, unsafe tool use, content safety, data residency, human oversight, auditability, and third-party model/tool boundaries.
- Monitor costs and remove test resources promptly.

Microsoft Agent Framework is the recommended framework for new agent development. The Semantic Kernel example is retained only for legacy support and migration reference.

## Pre-Deployment Security Checklist

- [ ] Review the full implementation and its transitive dependencies
- [ ] Replace access keys with managed identity where supported
- [ ] Validate least-privilege RBAC and Conditional Access requirements
- [ ] Restrict network access and verify private DNS behavior
- [ ] Enable Microsoft Defender for Cloud recommendations, diagnostics, alerts, and audit retention
- [ ] Define backup, recovery, availability, and incident-response requirements
- [ ] Validate data classification, residency, retention, and compliance obligations
- [ ] Test cleanup, credential rotation, and resource ownership boundaries
- [ ] Document accepted risks and obtain the required production approvals

## Additional Resources

- [Azure security documentation](https://learn.microsoft.com/azure/security/)
- [Azure Well-Architected Framework: Security](https://learn.microsoft.com/azure/well-architected/security/)
- [Microsoft Defender for Cloud](https://learn.microsoft.com/azure/defender-for-cloud/)
- [Azure Verified Modules](https://aka.ms/avm)
- [Microsoft Agent Framework transparency FAQ](https://github.com/microsoft/agent-framework/blob/main/TRANSPARENCY_FAQS.md)
- [Microsoft Security Response Center](https://www.microsoft.com/msrc)