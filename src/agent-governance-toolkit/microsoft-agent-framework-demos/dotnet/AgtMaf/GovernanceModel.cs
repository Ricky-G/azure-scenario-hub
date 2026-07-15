namespace AgtMaf;

/// <summary>
/// A normalized governance decision produced by an AGT policy evaluation. Wraps the
/// toolkit's decision types into a small, display-friendly shape that is consistent
/// across the prompt layer and the tool layer.
/// </summary>
public sealed class GovernanceDecision
{
    /// <summary>
    /// The exact phrase the Agent Governance Toolkit uses to signal "allowed only
    /// with human approval". Following AGT's policy-as-code convention, an escalation
    /// is a denied decision whose rule message contains this marker.
    /// </summary>
    public const string EscalationMarker = "requires human approval";

    public required string Layer { get; init; }   // "prompt" or "tool"
    public required string Target { get; init; }   // prompt summary, or tool name
    public required bool Allowed { get; init; }
    public required string Action { get; init; }   // allow | deny | escalate | audit
    public string? Rule { get; init; }
    public required string Reason { get; init; }

    public bool Escalated => Action == "escalate";

    /// <summary>
    /// Build a decision from the primitives both AGT result types expose. AGT has no
    /// first-class "approval" action, so — following AGT's own policy-as-code tutorials —
    /// an escalation is a denied decision whose rule message contains
    /// <see cref="EscalationMarker"/>. Because the .NET PolicyDecision surfaces the matched
    /// rule name (not its custom message), the caller passes the looked-up
    /// <paramref name="ruleMessage"/> so we can detect the marker; we also fall back to the
    /// rule-name convention <c>escalate-*</c>.
    /// </summary>
    public static GovernanceDecision Create(
        bool allowed, string? rule, string? ruleMessage, string genericReason, string layer, string target)
    {
        var message = ruleMessage ?? genericReason ?? "";
        var isEscalation =
            message.Contains(EscalationMarker, StringComparison.OrdinalIgnoreCase) ||
            (rule?.StartsWith("escalate", StringComparison.OrdinalIgnoreCase) ?? false);

        var action = allowed ? "allow" : (isEscalation ? "escalate" : "deny");

        return new GovernanceDecision
        {
            Layer = layer,
            Target = target,
            Allowed = allowed,
            Action = action,
            Rule = rule,
            Reason = !string.IsNullOrWhiteSpace(ruleMessage)
                ? ruleMessage!
                : (!string.IsNullOrWhiteSpace(genericReason) ? genericReason : "No rule matched; default action applied."),
        };
    }
}
