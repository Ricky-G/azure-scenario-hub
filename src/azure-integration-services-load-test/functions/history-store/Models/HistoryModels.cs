namespace HistoryStore.Models;

public class HistoryMessage
{
    public required string Id { get; set; }
    public DateTime Timestamp { get; set; }
    public required string Source { get; set; }
    public required string EventType { get; set; }
    public required string EntityId { get; set; }
    public required string EntityType { get; set; }
    public required string Operation { get; set; }
    public required ChangeSet Changes { get; set; }
    public required MessageMetadata Metadata { get; set; }
}

public class ChangeSet
{
    public Dictionary<string, object>? Before { get; set; }
    public Dictionary<string, object>? After { get; set; }
}

public class MessageMetadata
{
    public required string RequestId { get; set; }
    public required string Method { get; set; }
    public required string Url { get; set; }
    public required Dictionary<string, string> Headers { get; set; }
}

public class HistoryRecord
{
    public required string Id { get; set; }
    public DateTime Timestamp { get; set; }
    public DateTime ReceivedAt { get; set; }
    public required string EventType { get; set; }
    public required EntityInfo Entity { get; set; }
    public required string Operation { get; set; }
    public ChangeSet? Changes { get; set; }
    public MessageMetadata? Metadata { get; set; }
    public required string ProcessedBy { get; set; }
    public required string FunctionInstance { get; set; }
}

public class EntityInfo
{
    public required string Id { get; set; }
    public required string Type { get; set; }
}