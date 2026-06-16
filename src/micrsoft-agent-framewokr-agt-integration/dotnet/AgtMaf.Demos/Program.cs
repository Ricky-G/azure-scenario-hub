// AGT x MAF governance demo (.NET) — console entry point.
//
//   dotnet run -- <command>
//
// Commands:
//   args      (default-ish hero)  govern tool-call ARGUMENTS at the agent level  [START HERE]
//   prompt    Act 1  outbound prompt governance
//   tool      Act 2  tool-call capability sandbox
//   workflow  Act 4  governed multi-agent workflow
//   hardening Act 5  prompt-hardening note (a documented .NET gap)
//   audit     Act 6  tamper-evident audit trail
//   all       the complete showcase
//   verify    offline self-check (asserts every governance behaviour)
using AgtMaf;
using AgtMaf.Demos;

var command = (args.Length > 0 ? args[0] : "all").ToLowerInvariant();

switch (command)
{
    case "args" or "tool-args" or "arguments" or "explain":
        await RunArgumentBoundariesAsync();
        break;
    case "prompt":
        Display.Banner("AGT x MAF (.NET) - Outbound Prompt Governance",
            "Every prompt is statically analysed and governed by AGT before the model runs");
        await Scenarios.RunPromptGovernanceAsync(new GovernanceRuntime());
        break;
    case "tool" or "tools":
        Display.Banner("AGT x MAF (.NET) - Outbound Tool-Call Governance",
            "Every tool call is intercepted and checked against an AGT capability policy");
        await Scenarios.RunToolGovernanceAsync(new GovernanceRuntime());
        break;
    case "workflow":
        Display.Banner("AGT x MAF (.NET) - Governed Multi-Agent Workflow",
            "Governance and one shared audit chain span every agent in the workflow");
        {
            var rt = new GovernanceRuntime();
            await Scenarios.RunWorkflowGovernanceAsync(rt);
            Scenarios.ShowAuditTrail(rt.AuditLog, demonstrateTamper: false);
        }
        break;
    case "hardening" or "gap":
        Display.Banner("AGT x MAF (.NET) - Prompt Hardening (documented gap)",
            "The 12-vector PromptDefense auditor is Python-only; the .NET alternative is runtime detection");
        Scenarios.RunPromptHardeningNote();
        break;
    case "audit":
        Display.Banner("AGT x MAF (.NET) - Tamper-Evident Audit Trail",
            "Every governed decision is recorded in a hash-chained, verifiable audit log");
        {
            var rt = new GovernanceRuntime();
            await Scenarios.RunToolGovernanceAsync(rt);
            await Scenarios.RunArgumentInspectionAsync(rt);
            Scenarios.ShowAuditTrail(rt.AuditLog, demonstrateTamper: true);
        }
        break;
    case "all":
        await RunAllAsync();
        break;
    case "verify":
        return await Verify.RunAsync();
    default:
        Console.WriteLine("Unknown command. Use: args | prompt | tool | workflow | hardening | audit | all | verify");
        return 1;
}

return 0;

static async Task RunArgumentBoundariesAsync()
{
    Display.Banner("AGT x MAF (.NET) - Govern tool-call ARGUMENTS at the agent level",
        "One agent-attached policy checks every tool call's argument values - no per-tool code");
    Scenarios.ExplainToolArgumentGovernance();
    var runtime = new GovernanceRuntime();
    await Scenarios.RunArgumentInspectionAsync(runtime);
    Console.WriteLine();
    Display.Section("What just happened");
    Display.Note(
        "Every call above went through ONE tool-governance middleware attached to the agent. " +
        "Allowed / escalated / denied was decided purely from the argument VALUES, by the rules " +
        "in policies/tool-governance.yaml - not by any code inside the tools.");
    Console.WriteLine();
}

static async Task RunAllAsync()
{
    Display.Banner("Microsoft Agent Framework (.NET) x Agent Governance Toolkit",
        "A governed Contoso FinOps assistant - prompts and tool calls intercepted by AGT");
    var runtime = new GovernanceRuntime();

    await Scenarios.RunPromptGovernanceAsync(runtime);
    await Scenarios.RunToolGovernanceAsync(runtime);
    Scenarios.ExplainToolArgumentGovernance();
    await Scenarios.RunArgumentInspectionAsync(runtime);
    await Scenarios.RunWorkflowGovernanceAsync(runtime);
    Scenarios.RunPromptHardeningNote();
    Scenarios.ShowAuditTrail(runtime.AuditLog, demonstrateTamper: true);

    Console.WriteLine();
    Display.Section("Summary");
    Display.Note(
        "Every prompt and every tool call above was evaluated by a real AGT policy inside the real " +
        "MAF middleware pipeline. Swap ScriptedChatClient for a live model and the governance layer " +
        "does not change.");
    Console.WriteLine();
}
