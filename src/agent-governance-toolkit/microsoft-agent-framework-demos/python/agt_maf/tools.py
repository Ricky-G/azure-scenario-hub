"""Contoso FinOps tools for the governed agent.

These are ordinary Microsoft Agent Framework tools. Nothing about them is
"governed" — governance is applied entirely by the AGT tool middleware that sits
in front of them (see :mod:`agt_maf.governance`). That separation is the whole
point: the tools stay simple, and the capability sandbox is declared as data in
``policies/tool-governance.yaml``.

Tool risk tiers (enforced by the policy, not by the code below):
    read / safe   : get_cost_summary, list_resources, forecast_spend   -> allow
    sensitive     : transfer_budget  -> escalate when amount > $50,000, deny to "external"
                    scale_resource   -> deny when replicas > 20 (numeric ceiling)
                    provision_vm     -> deny outside allowed regions (data residency)
                    send_report_email
    destructive   : delete_resource, rotate_secret, deprovision_environment -> deny

The sensitive tools above are the heart of this scenario: their *arguments* are
governed by one agent-level policy, with no governance code inside the tools.
"""

from __future__ import annotations

from typing import Annotated

from agent_framework import tool
from pydantic import Field

# NOTE: approval_mode="never_require" keeps the demo non-interactive. Governance
# is enforced by AGT middleware, not by the framework's own approval prompt.


@tool(approval_mode="never_require")
def get_cost_summary(
    scope: Annotated[str, Field(description="Cost scope, e.g. 'subscription' or a resource group name.")],
) -> str:
    """Return a month-to-date cost summary for the given scope."""
    return f"[{scope}] month-to-date spend is $4,210; forecast $6,800; top driver: AKS (38%)."


@tool(approval_mode="never_require")
def list_resources(
    resource_group: Annotated[str, Field(description="The resource group to list resources for.")],
) -> str:
    """List the resources in a resource group."""
    return f"[{resource_group}] 3 resources: aks-prod (running), sql-prod (running), stor-logs (idle)."


@tool(approval_mode="never_require")
def forecast_spend(
    months: Annotated[int, Field(description="How many months ahead to forecast.")],
) -> str:
    """Forecast cloud spend for the next N months."""
    base = 6_800
    return f"Forecast for next {months} month(s): ~${base * max(1, months):,} at the current run-rate."


@tool(approval_mode="never_require")
def transfer_budget(
    amount: Annotated[int, Field(description="Amount in USD to move between budgets.")],
    to: Annotated[str, Field(description="Destination budget / team name.")],
) -> str:
    """Move budget between teams. Large transfers are escalated by policy."""
    return f"Transferred ${amount:,} to '{to}'."


@tool(approval_mode="never_require")
def scale_resource(
    resource_id: Annotated[str, Field(description="The resource to scale.")],
    replicas: Annotated[int, Field(description="Desired replica count.")],
) -> str:
    """Scale a resource to N replicas. The policy caps the replica count."""
    return f"Scaled {resource_id} to {replicas} replicas."


@tool(approval_mode="never_require")
def provision_vm(
    region: Annotated[str, Field(description="Azure region to deploy into.")],
    size: Annotated[str, Field(description="VM size, e.g. 'Standard_D2s_v5'.")],
) -> str:
    """Provision a VM. The policy enforces an allowed-region (data-residency) boundary."""
    return f"Provisioned a {size} VM in {region}."


@tool(approval_mode="never_require")
def send_report_email(
    to: Annotated[str, Field(description="Recipient email address.")],
    subject: Annotated[str, Field(description="Email subject line.")],
) -> str:
    """Email a FinOps report."""
    return f"Report emailed to {to} (subject: {subject!r})."


@tool(approval_mode="never_require")
def delete_resource(
    resource_id: Annotated[str, Field(description="The id of the resource to delete.")],
) -> str:
    """Delete a cloud resource. (Destructive — denied by the capability policy.)"""
    return f"DELETED {resource_id}."  # Should never run while governed.


@tool(approval_mode="never_require")
def rotate_secret(
    name: Annotated[str, Field(description="The name of the secret to rotate.")],
) -> str:
    """Rotate a secret in Key Vault. (Privileged — denied by the capability policy.)"""
    return f"Rotated secret {name}."  # Should never run while governed.


@tool(approval_mode="never_require")
def deprovision_environment(
    environment: Annotated[str, Field(description="The environment to tear down, e.g. 'prod'.")],
) -> str:
    """Tear down an entire environment. (Destructive — denied by the capability policy.)"""
    return f"Deprovisioned {environment}."  # Should never run while governed.


@tool(approval_mode="never_require")
def export_billing_data(
    destination: Annotated[str, Field(description="Where to export raw billing data to.")],
) -> str:
    """Export raw billing data to an external destination.

    This tool is intentionally **not** listed in ``policies/tool-governance.yaml`` —
    it represents a freshly added capability that nobody has classified yet. The
    default-deny policy blocks it automatically, which is the whole point of a
    zero-trust capability sandbox.
    """
    return f"Exported billing data to {destination}."  # Should never run while governed.


#: Every tool the demo agent is *built* with. The AGT capability sandbox decides
#: which of these may actually run.
ALL_TOOLS = [
    get_cost_summary,
    list_resources,
    forecast_spend,
    transfer_budget,
    scale_resource,
    provision_vm,
    send_report_email,
    delete_resource,
    rotate_secret,
    deprovision_environment,
    export_billing_data,
]
