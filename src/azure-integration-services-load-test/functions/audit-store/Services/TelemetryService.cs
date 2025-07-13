using Microsoft.ApplicationInsights;
using Microsoft.ApplicationInsights.DataContracts;
using Microsoft.Azure.Functions.Worker;
using System.Diagnostics;

namespace AuditStore.Services;

public interface ITelemetryService
{
    void TrackFunctionStart(string functionName, FunctionContext context);
    void TrackFunctionEnd(string functionName, FunctionContext context, Stopwatch stopwatch, bool success = true, string? error = null);
    void TrackCustomEvent(string eventName, IDictionary<string, string>? properties = null, IDictionary<string, double>? metrics = null);
    void TrackException(Exception exception, IDictionary<string, string>? properties = null);
}

public class TelemetryService : ITelemetryService
{
    private readonly TelemetryClient _telemetryClient;

    public TelemetryService(TelemetryClient telemetryClient)
    {
        _telemetryClient = telemetryClient;
    }

    public void TrackFunctionStart(string functionName, FunctionContext context)
    {
        var properties = new Dictionary<string, string>
        {
            ["FunctionName"] = functionName,
            ["InvocationId"] = context.InvocationId,
            ["EventType"] = "FunctionStart",
            ["StartTime"] = DateTime.UtcNow.ToString("O")
        };

        // Add trigger metadata if available
        if (context.FunctionDefinition.InputBindings.Any())
        {
            var triggerType = context.FunctionDefinition.InputBindings.First().Value.Type;
            properties["TriggerType"] = triggerType;
        }

        _telemetryClient.TrackEvent($"{functionName}.Started", properties);
    }

    public void TrackFunctionEnd(string functionName, FunctionContext context, Stopwatch stopwatch, bool success = true, string? error = null)
    {
        var properties = new Dictionary<string, string>
        {
            ["FunctionName"] = functionName,
            ["InvocationId"] = context.InvocationId,
            ["EventType"] = "FunctionEnd",
            ["EndTime"] = DateTime.UtcNow.ToString("O"),
            ["Success"] = success.ToString(),
            ["Duration"] = stopwatch.ElapsedMilliseconds.ToString()
        };

        if (!string.IsNullOrEmpty(error))
        {
            properties["Error"] = error;
        }

        var metrics = new Dictionary<string, double>
        {
            ["DurationMs"] = stopwatch.ElapsedMilliseconds
        };

        _telemetryClient.TrackEvent($"{functionName}.Completed", properties, metrics);

        // Also track as a dependency for better visualization in Application Map
        var dependency = new DependencyTelemetry
        {
            Name = functionName,
            Type = "Azure Function",
            Duration = stopwatch.Elapsed,
            Success = success,
            Data = context.InvocationId
        };

        _telemetryClient.TrackDependency(dependency);
    }

    public void TrackCustomEvent(string eventName, IDictionary<string, string>? properties = null, IDictionary<string, double>? metrics = null)
    {
        _telemetryClient.TrackEvent(eventName, properties, metrics);
    }

    public void TrackException(Exception exception, IDictionary<string, string>? properties = null)
    {
        _telemetryClient.TrackException(exception, properties);
    }
}