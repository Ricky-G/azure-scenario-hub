## Summary

Describe the problem, the scenario type, and the smallest complete change that solves it.

## Scenario Type

- [ ] Deployable
- [ ] Runnable Demo
- [ ] Benchmark
- [ ] Investigation
- [ ] Legacy Support or migration
- [ ] Repository documentation, website, CI, or security

## Validation

List the exact commands, environments, Azure regions/service tiers, and results used to validate this change.

```text
# Commands and concise results
```

## Evidence and Cost

Link or attach relevant screenshots, reports, raw results, or deployment evidence. State the Azure cost incurred during testing, or explain why the change runs offline.

## Security and Production Readiness

Describe identity, RBAC, networking, secrets, dependency, data-flow, AI/agent, and production-hardening implications. Do not include sensitive values.

## Checklist

- [ ] I kept the change focused on one problem.
- [ ] I tested in a clean environment or resource group where applicable.
- [ ] I compiled or linted the files I changed.
- [ ] I ran focused tests, contract checks, or the documented evidence workflow.
- [ ] I pinned direct dependencies and reviewed relevant security advisories.
- [ ] I documented prerequisites, configuration, cost, limitations, and cleanup.
- [ ] I updated both `README.md` and `docs/index.html` when the scenario inventory changed.
- [ ] I checked local links and ran `git diff --check`.
- [ ] I removed generated files, credentials, tenant data, and sensitive evidence.
- [ ] I have the right to contribute all submitted code, media, data, and documentation under the MIT License.
