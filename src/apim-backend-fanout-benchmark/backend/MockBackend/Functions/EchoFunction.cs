using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace MockBackend.Functions;

public class EchoFunction
{
    private static readonly string InstanceId =
        Environment.GetEnvironmentVariable("WEBSITE_INSTANCE_ID") ??
        Environment.MachineName;

    private static readonly string[] EchoedHeaderNames =
    [
        "User-Agent",
        "X-Forwarded-For",
        "X-Correlation-Id",
        "traceparent",
        "tracestate",
        "Ocp-Apim-Subscription-Key"
    ];

    private readonly ILogger<EchoFunction> _logger;

    public EchoFunction(ILogger<EchoFunction> logger)
    {
        _logger = logger;
    }

    [Function("Echo")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "echo/{*path}")]
        HttpRequestData req,
        string? path)
    {
        // Stable 5ms baseline so APIM overhead is measurable above noise.
        await Task.Delay(5);

        var echoedHeaders = new Dictionary<string, string>();
        foreach (var name in EchoedHeaderNames)
        {
            if (req.Headers.TryGetValues(name, out var values))
            {
                echoedHeaders[name] = string.Join(",", values);
            }
        }

        var payload = new
        {
            serverTime = DateTimeOffset.UtcNow,
            instanceId = InstanceId,
            method = req.Method,
            path = path ?? string.Empty,
            query = req.Url.Query,
            headers = echoedHeaders
        };

        // Custom dimension so the benchmark can confirm both APIMs hit the same instances.
        _logger.LogInformation("EchoRequest path={Path} instanceId={InstanceId}", path, InstanceId);

        var response = req.CreateResponse(HttpStatusCode.OK);
        response.Headers.Add("Content-Type", "application/json; charset=utf-8");
        await response.WriteStringAsync(JsonSerializer.Serialize(payload));
        return response;
    }
}
