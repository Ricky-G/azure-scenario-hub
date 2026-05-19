using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace MockBackend.Functions;

public class TimeFunction
{
    private static readonly string InstanceId =
        Environment.GetEnvironmentVariable("WEBSITE_INSTANCE_ID") ??
        Environment.MachineName;

    private readonly ILogger<TimeFunction> _logger;

    public TimeFunction(ILogger<TimeFunction> logger)
    {
        _logger = logger;
    }

    [Function("Time")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "time")]
        HttpRequestData req)
    {
        await Task.Delay(5);

        var payload = new
        {
            serverTime = DateTimeOffset.UtcNow,
            instanceId = InstanceId
        };

        _logger.LogInformation("TimeRequest instanceId={InstanceId}", InstanceId);

        var response = req.CreateResponse(HttpStatusCode.OK);
        response.Headers.Add("Content-Type", "application/json; charset=utf-8");
        await response.WriteStringAsync(JsonSerializer.Serialize(payload));
        return response;
    }
}
