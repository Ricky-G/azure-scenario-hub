using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;

namespace AgtMaf;

/// <summary>
/// AGT governance wired into the Microsoft Agent Framework (.NET) middleware pipeline.
/// Three composable layers turn an ordinary MAF agent into a governed one. All three
/// evaluate real Agent Governance Toolkit policies and write to a tamper-evident audit
/// log; none of them change how the agent or its tools are written.
///
/// They are attached with the framework's builder:
///   .AsBuilder()
///   .Use(runFunc: audit.RunAsync,  runStreamingFunc: null)   // outermost
///   .Use(runFunc: prompt.RunAsync, runStreamingFunc: null)   // governs the PROMPT
///   .Use(tool.InvokeFunctionAsync)                           // governs each TOOL CALL
///   .Build();
/// </summary>
public static class GovernanceTrace
{
    public static void EmitOutcome(GovernanceDecision d)
    {
        var detail = d.Rule is not null ? $"matched '{d.Rule}' - {d.Reason}" : d.Reason;
        if (d.Escalated)
        {
            Display.Escalate(detail);
        }
        else if (d.Allowed)
        {
            Display.Allowed(detail);
        }
        else
        {
            Display.Denied(detail);
        }
    }
}

/// <summary>Govern the outbound prompt with AGT before the model is invoked (run middleware).</summary>
public sealed class PromptGovernanceMiddleware(
    StaticPromptAnalyzer analyzer, AuditLog auditLog, string agentId, bool trace = true)
{
    public async Task<AgentResponse> RunAsync(
        IEnumerable<ChatMessage> messages, AgentSession? session, AgentRunOptions? options,
        AIAgent innerAgent, CancellationToken cancellationToken)
    {
        var materialized = messages as IReadOnlyList<ChatMessage> ?? messages.ToList();
        var prompt = materialized.LastOrDefault(m => m.Role == ChatRole.User)?.Text ?? string.Empty;

        var (decision, features) = analyzer.Analyze(prompt);

        auditLog.Record("prompt_evaluation", "prompt", decision.Target, decision.Action,
            decision.Allowed, decision.Rule, decision.Reason, agentId);

        if (trace)
        {
            Display.Intercept("prompt -> model", decision.Target);
            Display.Info("static analysis",
                $"pii={features.ContainsPii} secret={features.ContainsSecret} " +
                $"injection_markers={(features.InjectionMarkers.Count == 0 ? "[]" : string.Join(",", features.InjectionMarkers))}");
            GovernanceTrace.EmitOutcome(decision);
        }

        if (!decision.Allowed)
        {
            return new AgentResponse(new ChatMessage(
                ChatRole.Assistant, $"Request blocked by AGT prompt policy: {decision.Reason}"));
        }

        return await innerAgent.RunAsync(materialized, session, options, cancellationToken).ConfigureAwait(false);
    }
}

/// <summary>Govern every outbound tool call with an AGT capability + argument policy (function middleware).</summary>
public sealed class ToolGovernanceMiddleware(
    ToolCallAnalyzer analyzer, AuditLog auditLog, string agentId, bool trace = true)
{
    public async ValueTask<object?> InvokeFunctionAsync(
        AIAgent agent, FunctionInvocationContext context,
        Func<FunctionInvocationContext, CancellationToken, ValueTask<object?>> next,
        CancellationToken cancellationToken)
    {
        var toolName = context.Function.Name;

        var args = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        foreach (var kv in context.Arguments)
        {
            args[kv.Key] = kv.Value;
        }

        var decision = analyzer.Analyze(toolName, args);

        auditLog.Record("tool_evaluation", "tool", toolName, decision.Action,
            decision.Allowed, decision.Rule, decision.Reason, agentId);

        if (trace)
        {
            Display.Intercept("tool call", toolName);
            Display.Info("arguments", args.Count == 0 ? "{}" : string.Join(", ", args.Select(a => $"{a.Key}={a.Value}")));
            GovernanceTrace.EmitOutcome(decision);
        }

        if (decision.Allowed)
        {
            var result = await next(context, cancellationToken).ConfigureAwait(false);
            if (trace)
            {
                Display.Note($"tool result -> {Shorten(result)}");
            }
            return result;
        }

        // Denied or escalated: do NOT call next() so the tool never executes. Returning the
        // governance message as the function result lets the agent produce a graceful answer.
        var marker = decision.Escalated ? "ESCALATED" : "DENIED";
        return $"{marker} by AGT capability policy: {decision.Reason}";
    }

    private static string Shorten(object? result, int limit = 90)
    {
        var text = result?.ToString()?.Replace("\n", " ") ?? "";
        return text.Length > limit ? text[..limit] + "..." : text;
    }
}

/// <summary>Anchor each governed run as a record in the hash-chained audit log (run middleware).</summary>
public sealed class AuditTrailMiddleware(AuditLog auditLog, string agentId)
{
    public async Task<AgentResponse> RunAsync(
        IEnumerable<ChatMessage> messages, AgentSession? session, AgentRunOptions? options,
        AIAgent innerAgent, CancellationToken cancellationToken)
    {
        var materialized = messages as IReadOnlyList<ChatMessage> ?? messages.ToList();
        var prompt = materialized.LastOrDefault(m => m.Role == ChatRole.User)?.Text ?? string.Empty;
        var summary = prompt.Length > 58 ? prompt[..57] + "..." : prompt;

        auditLog.Record("agent_run", "run", summary, "audit", true, null, "Governed agent run started.", agentId);

        return await innerAgent.RunAsync(materialized, session, options, cancellationToken).ConfigureAwait(false);
    }
}
