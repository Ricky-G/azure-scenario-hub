# APIM Federated Workspaces Customer Demo

- **Length:** 20-25 minutes
- **Audience:** API platform owners, enterprise architects, and API delivery teams
- **Message:** One APIM platform can enforce common guardrails while separate teams own and operate their API lifecycle independently.

## Before the Meeting

1. Deploy at least three hours before the meeting.
2. Generate fresh demo traffic and validate the deployment:

   ```powershell
   cd src/apim-federated-workspaces
   ./test-workspaces.ps1
   ```

   Or on Linux/macOS:

   ```bash
   cd src/apim-federated-workspaces
   ./test-workspaces.sh
   ```

3. Allow several minutes for gateway logs to reach Log Analytics.
4. Open these browser tabs:
   - API Management service overview
   - **APIs > Workspaces**
   - Data Science workspace overview
   - Website Experience workspace overview
   - Scenario resource group filtered to `Microsoft.ApiManagement/gateways`
   - Log Analytics workspace **Logs**

No live API calls are required during the presentation after this preparation. The generated gateway logs use 30-day retention.

## 1. Frame the Problem - 2 Minutes

**Say:**

> "The tension is not whether governance or team autonomy wins. The platform team should own the service, global guardrails, runtime architecture, and observability. API teams should own the resources that change at their delivery speed. APIM workspaces give us that federated operating model inside one API management platform."

Show the architecture in [README.md](README.md#scenario).

Emphasize three boundaries:

- **Control plane:** Azure RBAC is scoped per workspace.
- **API lifecycle:** each team owns its APIs, products, policies, named values, and subscriptions.
- **Runtime:** dedicated gateways isolate capacity and give each team a distinct hostname; shared gateways are available when cost matters more than isolation.

## 2. Show the Platform View - 3 Minutes

In the Azure portal, open the APIM service and select **APIs > Workspaces**.

Show:

- **Data Science Team**
- **Website Experience Team**

**Say:**

> "This is still one centrally managed Premium service, but these are not just folders. Each workspace is an ARM scope with its own RBAC boundary and its own API management resources. The central team no longer has to be in the critical path for every API change."

Open the APIM service's global policy and point to `platform-governance` when using the disposable demo.

**Say:**

> "The platform baseline executes first. Every workspace policy uses `<base />`, so governance is inherited rather than copied into each team. In an existing customer APIM, we would merge this into the enterprise global policy instead of replacing it."

## 3. Become the Data Science Team - 5 Minutes

Open **Workspaces > Data Science Team**.

Move through these blades:

1. **APIs > Fraud Risk Inference API > score-risk**
2. **Products > Data Science Model APIs**
3. **Named values > ds-team-name**
4. **Policy fragments > ds-team-standards**
5. **Policies** at workspace and operation scope

**Say:**

> "The Data Science team can publish model APIs, productize them, manage team configuration, and reuse its own policy fragments. Its operation policy allows five calls per minute because inference capacity is expensive. None of these resources are visible as editable assets in the Website team's workspace."

**Impact line:**

> "The policy hierarchy shows three ownership layers: platform, workspace, and API team. The team is autonomous without becoming a silo. We will prove the resulting runtime behavior from centralized logs rather than making live calls during the demo."

## 4. Prove Team-Specific Guardrails - 3 Minutes

Open the Log Analytics workspace and run:

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == 'GatewayLogs'
| where workspaceId_s == 'data-science'
| where responseCode_d == 429
| summarize ThrottledRequests=count(), First429=min(TimeGenerated), Last429=max(TimeGenerated)
```

Expected result: one row with a nonzero `ThrottledRequests` count.

**Say:**

> "The platform provides the boundary; the Data Science team chooses the policy appropriate for its workload. A website endpoint can have a different limit without a platform-wide exception."

Clarify that rate limiting protects capacity but is not an exact billing or accounting mechanism; distributed counters can allow a small number of extra requests.

## 5. Switch to the Website Team - 3 Minutes

Open **Workspaces > Website Experience Team** and show the corresponding API, product, named value, and `web-team-standards` fragment.

For `Shared` topology, call out that both workspace connections use the same gateway capacity and default hostname, with distinct API paths. Open the shared gateway's **Configuration connections** to show both workspaces.

> "These teams still have separate RBAC and API lifecycle ownership, but they share one gateway's capacity and network configuration. This is the cost-balanced starting point. A mission-critical team can move to its own gateway without moving to another APIM service."

For `Dedicated` topology, show the two gateway resources and their distinct hostnames.

> "The teams share the platform but not the runtime resource. A bad deployment, traffic spike, or scaling decision in one gateway does not consume the other team's gateway capacity. This is the strongest isolation model."

Then contrast the other topology:

> "`GatewayTopology Dedicated` gives each team its own hostname and capacity. `Shared` reduces gateway cost, but the teams share runtime failure impact. It is an architecture decision, not a workspace limitation."

## 6. Show Delegated Access - 3 Minutes

Open **Access control (IAM)** on the APIM service and then on each workspace.

Explain the two-role model:

- Service scope: **API Management Service Workspace API Developer**
- Team workspace scope: **API Management Workspace Contributor**

**Say:**

> "A workspace collaborator receives a narrow service role so workspace resources can reference allowed service-level assets, plus a contributor role only on their workspace. We assign these roles to Entra groups, not individuals. The Website group receives no role on the Data Science workspace, and vice versa."

If group IDs were not supplied during deployment, show the role definitions and explain that the Bicep has optional principal parameters rather than manufacturing demo identities in the tenant.

## 7. Show Federated Observability - 3 Minutes

Open the Log Analytics workspace. Run each query in a separate query tab.

### Team Traffic Summary

This is the opening observability view: independent workspace ownership with centralized platform visibility.

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == 'GatewayLogs'
| where workspaceId_s in ('data-science', 'website-experience')
| where url_s has_any ('ai-insights', 'digital-experience')
| extend Team = case(
   workspaceId_s == 'data-science', 'Data Science',
   workspaceId_s == 'website-experience', 'Website Experience',
   'Other')
| extend StatusCode = toint(responseCode_d)
| summarize
   Requests=count(),
   Successful=countif(StatusCode >= 200 and StatusCode < 300),
   Throttled=countif(StatusCode == 429)
   by Team
| order by Team asc
```

### Throttling Proof

This shows the Data Science team's policy protecting inference capacity without affecting the Website team.

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == 'GatewayLogs'
| where workspaceId_s == 'data-science'
| where url_s has 'ai-insights'
| summarize Requests=count() by StatusCode=toint(responseCode_d)
| order by StatusCode asc
```

### Traffic Timeline

Select **Line chart** after running this query.

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == 'GatewayLogs'
| where workspaceId_s in ('data-science', 'website-experience')
| where url_s has_any ('ai-insights', 'digital-experience')
| extend Team = case(
   workspaceId_s == 'data-science', 'Data Science',
   workspaceId_s == 'website-experience', 'Website Experience',
   'Other')
| summarize Requests=count() by bin(TimeGenerated, 5m), Team
| render timechart
```

### Request Detail And Latency

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == 'GatewayLogs'
| where workspaceId_s in ('data-science', 'website-experience')
| where url_s has_any ('ai-insights', 'digital-experience')
| project
   TimeGenerated,
   Workspace=workspaceId_s,
   Method=method_s,
   Url=url_s,
   StatusCode=toint(responseCode_d),
   DurationMs=toint(DurationMs),
   CorrelationId
| order by TimeGenerated desc
| take 100
```

Then open **Data Science workspace > Monitoring > Logs**.

**Say:**

> "The platform team has a federated view across the service, while a workspace team can investigate its own gateway logs from its workspace. Diagnostics are configured at both service and workspace scope because both are required for workspace gateway log collection."

Mention that request metrics remain aggregated at APIM service scope; use resource logs for workspace-aware analysis.

## 8. Close with the Decision - 2 Minutes

**Say:**

> "For your existing Premium service, the first decision is the team boundary: which APIs, products, policies, and operational ownership belong together? The second is runtime topology: dedicated gateways for critical or differently networked teams, shared gateways for compatible lower-risk teams. The platform team keeps governance and observability in both models."

Ask these discovery questions:

1. Which Entra groups map to the initial workspace teams?
2. Which teams need dedicated capacity or distinct network reachability?
3. Which service-level policies must every workspace inherit?
4. Which resources must stay service-level for shared discovery and governance?
5. What log retention and workspace-level access model is required?

## Recovery Notes

- If queries are empty, confirm the test script passed, wait several minutes for ingestion, and widen the KQL time filter.
- The deployed diagnostic settings write APIM gateway records to `AzureDiagnostics`; use the queries in this script.
- If the portal is slow, show the workspace resources first and return to the already-ingested KQL results.
- Do not run cleanup until the customer session and any follow-up rehearsal are complete.
