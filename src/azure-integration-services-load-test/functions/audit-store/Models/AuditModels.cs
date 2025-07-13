namespace AuditStore.Models;

public class AuditMessage
{
    public required string Id { get; set; }
    public DateTime Timestamp { get; set; }
    public required string Source { get; set; }
    public required string Action { get; set; }
    public required string User { get; set; }
    public required string Details { get; set; }
    public required MessageMetadata Metadata { get; set; }
}

public class MessageMetadata
{
    public required string RequestId { get; set; }
    public required string Method { get; set; }
    public required string Url { get; set; }
    public required Dictionary<string, string> Headers { get; set; }
}

public class AuditRecord
{
    public required string Id { get; set; }
    public DateTime Timestamp { get; set; }
    public DateTime ReceivedAt { get; set; }
    public required string Action { get; set; }
    public required string User { get; set; }
    public required string Details { get; set; }
    public MessageMetadata? Metadata { get; set; }
    public required string ProcessedBy { get; set; }
    public required string FunctionInstance { get; set; }
}