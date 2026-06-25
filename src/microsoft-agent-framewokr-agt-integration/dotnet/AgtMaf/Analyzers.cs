using System.Text.RegularExpressions;
using AgentGovernance;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

namespace AgtMaf;

/// <summary>
/// Loads an AGT policy file into a <see cref="GovernanceKernel"/> and also parses it
/// for each rule's custom <c>message</c>. The .NET PolicyDecision surfaces the matched
/// rule NAME but not its message, so we read the messages ourselves to show friendly
/// reasons (and to detect the "requires human approval" escalation marker).
/// </summary>
public sealed class PolicyBundle
{
    public GovernanceKernel Kernel { get; }
    public IReadOnlyDictionary<string, string> RuleMessages { get; }

    private PolicyBundle(GovernanceKernel kernel, IReadOnlyDictionary<string, string> messages)
    {
        Kernel = kernel;
        RuleMessages = messages;
    }

    public string? MessageFor(string? ruleName) =>
        ruleName is not null && RuleMessages.TryGetValue(ruleName, out var m) ? m : null;

    public static PolicyBundle FromFile(string path)
    {
        var yaml = File.ReadAllText(path);

        var kernel = new GovernanceKernel();
        kernel.LoadPolicyFromYaml(yaml);

        var messages = new Dictionary<string, string>(StringComparer.Ordinal);
        try
        {
            var deserializer = new DeserializerBuilder()
                .WithNamingConvention(CamelCaseNamingConvention.Instance)
                .IgnoreUnmatchedProperties()
                .Build();
            var doc = deserializer.Deserialize<PolicyFileModel>(yaml);
            foreach (var rule in doc?.Rules ?? [])
            {
                if (!string.IsNullOrWhiteSpace(rule.Name) && !string.IsNullOrWhiteSpace(rule.Message))
                {
                    messages[rule.Name!] = rule.Message!;
                }
            }
        }
        catch
        {
            // Friendly messages are best-effort; the kernel decision is the source of truth.
        }

        return new PolicyBundle(kernel, messages);
    }

    private sealed class PolicyFileModel
    {
        public List<RuleModel>? Rules { get; set; }
    }

    private sealed class RuleModel
    {
        public string? Name { get; set; }
        public string? Message { get; set; }
    }
}

/// <summary>Deterministic signals extracted from a prompt by static analysis.</summary>
public sealed record PromptFeatures(
    bool ContainsPii,
    bool ContainsSecret,
    bool ContainsInjection,
    IReadOnlyList<string> InjectionMarkers);

/// <summary>
/// Govern an outbound prompt with deterministic C# static analysis plus a real AGT
/// policy. The regex / keyword detection runs here (the .NET policy engine has no regex
/// operator); the resulting boolean signals are fed into the policy, which decides.
/// </summary>
public sealed class StaticPromptAnalyzer
{
    private static readonly Regex SsnRe = new(@"\b\d{3}-\d{2}-\d{4}\b", RegexOptions.Compiled);
    private static readonly Regex CreditCardRe = new(@"\b(?:\d[ -]?){15,16}\b", RegexOptions.Compiled);

    private static readonly Regex SecretRe = new(
        @"\b(AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex SecretKeywordRe = new(
        @"\b(password|passwd|api[_ -]?key|secret[_ -]?key|connection[_ -]?string|bearer\s+token)\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex[] InjectionPatterns =
    [
        new(@"ignore (all |any |the )?(previous|prior|above) instructions", RegexOptions.Compiled | RegexOptions.IgnoreCase),
        new(@"disregard (the|all|your) (above|previous|prior|system)", RegexOptions.Compiled | RegexOptions.IgnoreCase),
        new(@"reveal (your|the) (system|developer) prompt", RegexOptions.Compiled | RegexOptions.IgnoreCase),
        new(@"you are now (in )?(developer|dan|jailbreak) mode", RegexOptions.Compiled | RegexOptions.IgnoreCase),
        new(@"\bjailbreak\b", RegexOptions.Compiled | RegexOptions.IgnoreCase),
        new(@"exfiltrate|leak (the )?(data|secrets|credentials)", RegexOptions.Compiled | RegexOptions.IgnoreCase),
        new(@"pretend (to be|you are)|act as (an?|the) (unrestricted|uncensored)", RegexOptions.Compiled | RegexOptions.IgnoreCase),
    ];

    private readonly PolicyBundle _policy;
    private readonly string _agentId;

    public StaticPromptAnalyzer(string policyPath, string agentId)
    {
        _policy = PolicyBundle.FromFile(policyPath);
        _agentId = agentId;
    }

    public static PromptFeatures ExtractFeatures(string prompt)
    {
        var markers = new List<string>();
        foreach (var pat in InjectionPatterns)
        {
            var m = pat.Match(prompt);
            if (m.Success)
            {
                markers.Add(m.Value);
            }
        }
        var pii = SsnRe.IsMatch(prompt) || CreditCardRe.IsMatch(prompt);
        var secret = SecretRe.IsMatch(prompt) || SecretKeywordRe.IsMatch(prompt);
        return new PromptFeatures(pii, secret, markers.Count > 0, markers);
    }

    public (GovernanceDecision Decision, PromptFeatures Features) Analyze(string prompt)
    {
        var features = ExtractFeatures(prompt);

        // The deterministic signals are the evaluation context the policy decides on.
        var context = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase)
        {
            ["contains_pii"] = features.ContainsPii,
            ["contains_secret"] = features.ContainsSecret,
            ["contains_injection"] = features.ContainsInjection,
            ["injection_markers"] = features.InjectionMarkers.Count,
        };

        var decision = _policy.Kernel.PolicyEngine.Evaluate(_agentId, context);

        var summary = prompt.Length > 58 ? prompt[..57] + "..." : prompt;
        var gov = GovernanceDecision.Create(
            decision.Allowed,
            decision.MatchedRule,
            _policy.MessageFor(decision.MatchedRule),
            decision.Reason,
            layer: "prompt",
            target: summary);
        return (gov, features);
    }
}

/// <summary>
/// Govern an outbound tool call with a real AGT capability + argument-boundary policy.
/// This is the heart of the scenario: the same agent-level policy decides allow / deny /
/// escalate purely from the tool name AND its argument values.
/// </summary>
public sealed class ToolCallAnalyzer
{
    private readonly PolicyBundle _policy;
    private readonly string _agentId;

    public ToolCallAnalyzer(string policyPath, string agentId)
    {
        _policy = PolicyBundle.FromFile(policyPath);
        _agentId = agentId;
    }

    public GovernanceDecision Analyze(string toolName, IReadOnlyDictionary<string, object?> arguments)
    {
        // The kernel merges these args into the evaluation context, so policy conditions
        // can reference argument values directly (e.g. `amount > 50000`).
        var args = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
        foreach (var (key, value) in arguments)
        {
            if (value is not null)
            {
                args[key] = value;
            }
        }

        var result = _policy.Kernel.EvaluateToolCall(_agentId, toolName, args);
        return GovernanceDecision.Create(
            result.Allowed,
            result.PolicyDecision?.MatchedRule,
            _policy.MessageFor(result.PolicyDecision?.MatchedRule),
            result.Reason,
            layer: "tool",
            target: toolName);
    }
}
