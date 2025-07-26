using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Net.Http;
using System.Text.Json;
using System.Diagnostics;
using AvailabilityChecker.Services;
using AvailabilityChecker.Models;

namespace AvailabilityChecker.Functions;

public class AvailabilityChecker
{
    private readonly ILogger<AvailabilityChecker> _logger;
    private readonly HttpClient _httpClient;
    private readonly ITelemetryService _telemetryService;
    private readonly List<EndpointConfig> _endpoints;

    public AvailabilityChecker(ILogger<AvailabilityChecker> logger, IHttpClientFactory httpClientFactory, ITelemetryService telemetryService)
    {
        _logger = logger;
        _httpClient = httpClientFactory.CreateClient();
        _httpClient.Timeout = TimeSpan.FromSeconds(30);
        _telemetryService = telemetryService;
        
        // Configure endpoints from environment variables
        _endpoints = new List<EndpointConfig>
        {
            new EndpointConfig 
            { 
                Name = "auditsadaptor", 
                Url = Environment.GetEnvironmentVariable("AUDITSADAPTOR_URL"), 
                HealthPath = "/api/health" 
            },
            new EndpointConfig 
            { 
                Name = "auditstore", 
                Url = Environment.GetEnvironmentVariable("AUDITSTORE_URL"), 
                HealthPath = "/api/health" 
            },
            new EndpointConfig 
            { 
                Name = "historyadaptor", 
                Url = Environment.GetEnvironmentVariable("HISTORYADAPTOR_URL"), 
                HealthPath = "/api/health" 
            },
            new EndpointConfig 
            { 
                Name = "historystore", 
                Url = Environment.GetEnvironmentVariable("HISTORYSTORE_URL"), 
                HealthPath = "/api/health" 
            }
        };
    }

    [Function("AvailabilityChecker")]
    public async Task Run([TimerTrigger("0 */5 * * * *")] TimerInfo timerInfo, FunctionContext context)
    {
        var stopwatch = Stopwatch.StartNew();
        _telemetryService.TrackFunctionStart("AvailabilityChecker", context);
        
        var executionTimestamp = DateTime.UtcNow;
        
        if (timerInfo.IsPastDue)
        {
            _logger.LogWarning("Availability checker timer trigger is running late!");
        }
        
        _logger.LogInformation($"Availability checker timer trigger function ran at: {executionTimestamp}");

        var results = new List<HealthCheckResult>();

        // Check each endpoint
        foreach (var endpoint in _endpoints)
        {
            var result = await CheckEndpointHealth(endpoint);
            results.Add(result);
            
            // Log to Application Insights
            LogAvailabilityResult(result);
        }

        // Summary
        var healthyCount = results.Count(r => r.IsHealthy);
        var totalCount = results.Count;
        
        _logger.LogInformation($"Availability check complete: {healthyCount}/{totalCount} endpoints healthy");
        
        // Log summary to Application Insights
        _telemetryService.TrackCustomEvent("AvailabilityCheckCompleted",
            new Dictionary<string, string>
            {
                ["TotalEndpoints"] = totalCount.ToString(),
                ["HealthyEndpoints"] = healthyCount.ToString(),
                ["UnhealthyEndpoints"] = (totalCount - healthyCount).ToString(),
                ["CheckTimestamp"] = executionTimestamp.ToString("O")
            },
            new Dictionary<string, double>
            {
                ["EndpointsHealthy"] = healthyCount,
                ["EndpointsTotal"] = totalCount,
                ["HealthPercentage"] = totalCount > 0 ? (double)healthyCount / totalCount * 100 : 0
            });
        
        _telemetryService.TrackFunctionEnd("AvailabilityChecker", context, stopwatch, true);
    }

    private async Task<HealthCheckResult> CheckEndpointHealth(EndpointConfig endpoint)
    {
        var startTime = DateTime.UtcNow;
        var result = new HealthCheckResult
        {
            Name = endpoint.Name,
            Url = endpoint.Url,
            Timestamp = DateTime.UtcNow,
            IsHealthy = false,
            ResponseTime = 0,
            StatusCode = null,
            Error = null
        };

        if (string.IsNullOrEmpty(endpoint.Url))
        {
            result.Error = "URL not configured";
            _logger.LogWarning($"{endpoint.Name}: URL not configured");
            return result;
        }

        try
        {
            var fullUrl = $"{endpoint.Url}{endpoint.HealthPath}";
            var response = await _httpClient.GetAsync(fullUrl);
            
            result.ResponseTime = (int)(DateTime.UtcNow - startTime).TotalMilliseconds;
            result.StatusCode = (int)response.StatusCode;
            result.IsHealthy = response.IsSuccessStatusCode;
            
            if (!result.IsHealthy)
            {
                result.Error = $"Unhealthy status code: {response.StatusCode}";
            }
            
            _logger.LogInformation("{Endpoint}: {Status} ({ResponseTime}ms)", 
                endpoint.Name, result.IsHealthy ? "Healthy" : "Unhealthy", result.ResponseTime);
        }
        catch (Exception ex)
        {
            result.ResponseTime = (int)(DateTime.UtcNow - startTime).TotalMilliseconds;
            result.Error = ex.Message;
            _logger.LogError(ex, "{Endpoint}: Error - {ErrorMessage}", endpoint.Name, ex.Message);
        }

        return result;
    }

    private void LogAvailabilityResult(HealthCheckResult result)
    {
        // Log custom event to Application Insights
        var properties = new Dictionary<string, object>
        {
            ["Endpoint"] = result.Name,
            ["Url"] = result.Url ?? "unknown",
            ["IsHealthy"] = result.IsHealthy,
            ["ResponseTime"] = result.ResponseTime,
            ["StatusCode"] = result.StatusCode ?? 0,
            ["Error"] = result.Error ?? "none",
            ["Timestamp"] = result.Timestamp
        };

        _logger.LogInformation("Availability test: {Endpoint} - {Status}", 
            result.Name, result.IsHealthy ? "Success" : "Failed");
        
        // Track availability metrics
        using (_logger.BeginScope(properties))
        {
            // Track response time
            _logger.LogMetric($"{result.Name}_ResponseTime", result.ResponseTime);
            
            // Track availability (1 for healthy, 0 for unhealthy)
            _logger.LogMetric($"{result.Name}_Availability", result.IsHealthy ? 1 : 0);
        }
    }
}