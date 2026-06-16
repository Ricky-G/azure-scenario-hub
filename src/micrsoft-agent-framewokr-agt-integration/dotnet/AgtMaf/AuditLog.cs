using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace AgtMaf;

/// <summary>A single governed event in the audit trail.</summary>
public sealed class AuditRecord
{
    public required string EventType { get; init; }   // prompt_evaluation | tool_evaluation | agent_run
    public required string Layer { get; init; }       // prompt | tool | run
    public required string Target { get; init; }      // prompt summary or tool name
    public required string Action { get; init; }      // allow | deny | escalate | audit
    public required bool Allowed { get; init; }
    public string? Rule { get; init; }
    // Settable so the Act 6 demo can simulate an attacker editing a stored record.
    public required string Reason { get; set; }
    public required string AgentId { get; init; }
    public string Timestamp { get; init; } = DateTime.UtcNow.ToString("O");
    public string PrevHash { get; set; } = "";
    public string ThisHash { get; set; } = "";

    /// <summary>SHA-256 over the record (excluding its own hash) plus the previous hash.</summary>
    public string ComputeHash()
    {
        var payload = JsonSerializer.Serialize(new
        {
            EventType, Layer, Target, Action, Allowed, Rule, Reason, AgentId, Timestamp, PrevHash,
        });
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(payload))).ToLowerInvariant();
    }
}

/// <summary>
/// A tiny tamper-evident audit log (hash-chained). The Agent Governance Toolkit
/// ships a Merkle-chained audit log in its full stack; for a self-contained demo
/// we implement the same idea: every record is hashed together with the previous
/// record's hash, so any later edit to an earlier record breaks the chain.
/// </summary>
public sealed class AuditLog
{
    private readonly List<AuditRecord> _records = [];

    public IReadOnlyList<AuditRecord> Records => _records;
    public int Count => _records.Count;

    public AuditRecord Record(
        string eventType, string layer, string target, string action,
        bool allowed, string? rule, string reason, string agentId)
    {
        var rec = new AuditRecord
        {
            EventType = eventType,
            Layer = layer,
            Target = target,
            Action = action,
            Allowed = allowed,
            Rule = rule,
            Reason = reason,
            AgentId = agentId,
            PrevHash = _records.Count > 0 ? _records[^1].ThisHash : "GENESIS",
        };
        rec.ThisHash = rec.ComputeHash();
        _records.Add(rec);
        return rec;
    }

    /// <summary>Walk the chain and confirm no record was altered or reordered.</summary>
    public (bool Ok, string? Error) VerifyIntegrity()
    {
        var prev = "GENESIS";
        for (var i = 0; i < _records.Count; i++)
        {
            if (_records[i].PrevHash != prev)
            {
                return (false, $"record #{i} prev_hash mismatch");
            }
            if (_records[i].ComputeHash() != _records[i].ThisHash)
            {
                return (false, $"record #{i} content hash mismatch (tampered)");
            }
            prev = _records[i].ThisHash;
        }
        return (true, null);
    }
}
