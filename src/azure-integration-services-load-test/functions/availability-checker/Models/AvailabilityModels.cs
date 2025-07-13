namespace AvailabilityChecker.Models;

public class EndpointConfig
{
    public required string Name { get; set; }
    public string? Url { get; set; }
    public required string HealthPath { get; set; }
}

public class HealthCheckResult
{
    public required string Name { get; set; }
    public string? Url { get; set; }
    public DateTime Timestamp { get; set; }
    public bool IsHealthy { get; set; }
    public int ResponseTime { get; set; }
    public int? StatusCode { get; set; }
    public string? Error { get; set; }
}