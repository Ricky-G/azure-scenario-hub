using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Diagnostics;
using AuditsAdaptor.Services;

namespace AuditsAdaptor.Functions;

public class Health
{
    private readonly ILogger<Health> _logger;
    private readonly ITelemetryService _telemetryService;
    private static readonly DateTime _startTime = DateTime.UtcNow;

    public Health(ILogger<Health> logger, ITelemetryService telemetryService)
    {
        _logger = logger;
        _telemetryService = telemetryService;
    }

    [Function("Health")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "health")] HttpRequestData req,
        FunctionContext executionContext)
    {
        var stopwatch = Stopwatch.StartNew();
        _telemetryService.TrackFunctionStart("Health", executionContext);
        _logger.LogInformation("Health check endpoint called");

        var uptime = DateTime.UtcNow - _startTime;
        var functionAppName = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME") ?? "audits-adaptor";
        var instanceId = Environment.GetEnvironmentVariable("WEBSITE_INSTANCE_ID") ?? "unknown";
        
        var healthStatus = new
        {
            status = "healthy",
            timestamp = DateTime.UtcNow,
            function = functionAppName,
            instanceId = instanceId,
            version = GetAssemblyVersion(),
            uptime = new
            {
                days = uptime.Days,
                hours = uptime.Hours,
                minutes = uptime.Minutes,
                seconds = uptime.Seconds,
                totalSeconds = uptime.TotalSeconds
            },
            environment = new
            {
                dotnet = RuntimeInformation.FrameworkDescription,
                os = RuntimeInformation.OSDescription,
                arch = RuntimeInformation.OSArchitecture.ToString(),
                processArch = RuntimeInformation.ProcessArchitecture.ToString()
            },
            azure = new
            {
                region = Environment.GetEnvironmentVariable("REGION_NAME") ?? "unknown",
                resourceGroup = Environment.GetEnvironmentVariable("RESOURCE_GROUP") ?? "unknown",
                subscriptionId = Environment.GetEnvironmentVariable("SUBSCRIPTION_ID") ?? "unknown",
                functionsVersion = Environment.GetEnvironmentVariable("FUNCTIONS_EXTENSION_VERSION") ?? "unknown",
                workerRuntime = Environment.GetEnvironmentVariable("FUNCTIONS_WORKER_RUNTIME") ?? "unknown"
            }
        };

        // Track health check event
        _telemetryService.TrackCustomEvent("HealthCheckPerformed",
            new Dictionary<string, string>
            {
                ["FunctionApp"] = functionAppName,
                ["InstanceId"] = instanceId,
                ["Status"] = "healthy",
                ["Version"] = GetAssemblyVersion(),
                ["Runtime"] = Environment.GetEnvironmentVariable("FUNCTIONS_WORKER_RUNTIME") ?? "unknown"
            },
            new Dictionary<string, double>
            {
                ["UptimeSeconds"] = uptime.TotalSeconds
            });

        var response = req.CreateResponse(HttpStatusCode.OK);
        await response.WriteAsJsonAsync(healthStatus);
        
        _telemetryService.TrackFunctionEnd("Health", executionContext, stopwatch, true);
        return response;
    }

    private static string GetAssemblyVersion()
    {
        try
        {
            var assembly = Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version;
            return version?.ToString() ?? "1.0.0";
        }
        catch
        {
            return "1.0.0";
        }
    }
}