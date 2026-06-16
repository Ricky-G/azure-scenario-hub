using System.ComponentModel;
using Microsoft.Extensions.AI;

namespace AgtMaf;

/// <summary>
/// Contoso FinOps tools. These are ordinary Microsoft Agent Framework tools — nothing
/// about them is "governed". Governance is applied entirely by the AGT tool middleware
/// that sits in front of them, with the boundaries declared as data in
/// <c>policies/tool-governance.yaml</c>. That separation is the whole point: the tools
/// stay simple, and the capability + argument sandbox lives in policy.
///
/// Tool risk tiers (enforced by the policy, not by the code below):
///   read / safe : get_cost_summary, list_resources, forecast_spend       -> allow
///   sensitive   : transfer_budget (escalate amount > 50000, deny to "external"),
///                 scale_resource (deny replicas > 20),
///                 provision_vm (deny outside approved regions), send_report_email
///   destructive : delete_resource, rotate_secret, deprovision_environment -> deny
/// </summary>
public static class Tools
{
    public static string GetCostSummary(
        [Description("Cost scope, e.g. 'subscription' or a resource group name.")] string scope)
        => $"[{scope}] month-to-date spend is $4,210; forecast $6,800; top driver: AKS (38%).";

    public static string ListResources(
        [Description("The resource group to list resources for.")] string resourceGroup)
        => $"[{resourceGroup}] 3 resources: aks-prod (running), sql-prod (running), stor-logs (idle).";

    public static string ForecastSpend(
        [Description("How many months ahead to forecast.")] int months)
        => $"Forecast for next {months} month(s): ~${6_800 * Math.Max(1, months):N0} at the current run-rate.";

    public static string TransferBudget(
        [Description("Amount in USD to move between budgets.")] int amount,
        [Description("Destination budget / team name.")] string to)
        => $"Transferred ${amount:N0} to '{to}'.";

    public static string ScaleResource(
        [Description("The resource to scale.")] string resourceId,
        [Description("Desired replica count.")] int replicas)
        => $"Scaled {resourceId} to {replicas} replicas.";

    public static string ProvisionVm(
        [Description("Azure region to deploy into.")] string region,
        [Description("VM size, e.g. 'Standard_D2s_v5'.")] string size)
        => $"Provisioned a {size} VM in {region}.";

    public static string SendReportEmail(
        [Description("Recipient email address.")] string to,
        [Description("Email subject line.")] string subject)
        => $"Report emailed to {to} (subject: '{subject}').";

    public static string DeleteResource(
        [Description("The id of the resource to delete.")] string resourceId)
        => $"DELETED {resourceId}.";   // Should never run while governed.

    public static string RotateSecret(
        [Description("The name of the secret to rotate.")] string name)
        => $"Rotated secret {name}.";  // Should never run while governed.

    public static string DeprovisionEnvironment(
        [Description("The environment to tear down, e.g. 'prod'.")] string environment)
        => $"Deprovisioned {environment}.";  // Should never run while governed.

    public static string ExportBillingData(
        [Description("Where to export raw billing data to.")] string destination)
        => $"Exported billing data to {destination}.";  // Not in policy -> default-deny.

    /// <summary>Every tool the demo agent is *built* with. The AGT capability sandbox decides which may run.</summary>
    public static IList<AITool> All() =>
    [
        AIFunctionFactory.Create(GetCostSummary, name: "get_cost_summary"),
        AIFunctionFactory.Create(ListResources, name: "list_resources"),
        AIFunctionFactory.Create(ForecastSpend, name: "forecast_spend"),
        AIFunctionFactory.Create(TransferBudget, name: "transfer_budget"),
        AIFunctionFactory.Create(ScaleResource, name: "scale_resource"),
        AIFunctionFactory.Create(ProvisionVm, name: "provision_vm"),
        AIFunctionFactory.Create(SendReportEmail, name: "send_report_email"),
        AIFunctionFactory.Create(DeleteResource, name: "delete_resource"),
        AIFunctionFactory.Create(RotateSecret, name: "rotate_secret"),
        AIFunctionFactory.Create(DeprovisionEnvironment, name: "deprovision_environment"),
        AIFunctionFactory.Create(ExportBillingData, name: "export_billing_data"),
    ];
}
