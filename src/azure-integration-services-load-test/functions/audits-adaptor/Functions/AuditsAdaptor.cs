using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using System.Net;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using System.Diagnostics;
using AuditsAdaptor.Services;
using AuditsAdaptor.Models;

namespace AuditsAdaptor.Functions;

public class AuditsAdaptor
{
    private readonly ILogger<AuditsAdaptor> _logger;
    private readonly ServiceBusClient _serviceBusClient;
    private readonly ITelemetryService _telemetryService;
    private readonly string _topicName;

    public AuditsAdaptor(ILogger<AuditsAdaptor> logger, ServiceBusClient serviceBusClient, ITelemetryService telemetryService)
    {
        _logger = logger;
        _serviceBusClient = serviceBusClient;
        _telemetryService = telemetryService;
        _topicName = Environment.GetEnvironmentVariable("SERVICEBUS_TOPIC_AUDITS") ?? "audits";
    }

    [Function("AuditsAdaptor")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", Route = "audits")] HttpRequestData req,
        FunctionContext executionContext)
    {
        var stopwatch = Stopwatch.StartNew();
        _telemetryService.TrackFunctionStart("AuditsAdaptor", executionContext);
        _logger.LogInformation("AuditsAdaptor HTTP trigger function processed a request.");

        try
        {
            // Parse request body
            var requestBody = await req.ReadAsStringAsync();
            AuditRequest? auditRequest = null;
            
            if (!string.IsNullOrEmpty(requestBody))
            {
                auditRequest = JsonSerializer.Deserialize<AuditRequest>(requestBody, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
            }

            // Create audit message
            var auditMessage = new AuditMessage
            {
                Id = GenerateId(),
                Timestamp = DateTime.UtcNow,
                Source = "auditsadaptor",
                Action = auditRequest?.Action ?? "audit-test",
                User = auditRequest?.User ?? "system",
                Details = auditRequest?.Details ?? "Test audit message from HTTP trigger",
                Metadata = new MessageMetadata
                {
                    RequestId = executionContext.InvocationId,
                    Method = req.Method,
                    Url = req.Url.ToString(),
                    Headers = req.Headers.ToDictionary(h => h.Key, h => string.Join(", ", h.Value))
                }
            };

            // Send message to Service Bus
            await using var sender = _serviceBusClient.CreateSender(_topicName);
            
            var serviceBusMessage = new ServiceBusMessage(JsonSerializer.Serialize(auditMessage))
            {
                ContentType = "application/json",
                Subject = auditMessage.Action
            };
            
            await sender.SendMessageAsync(serviceBusMessage);

            _logger.LogInformation($"Audit message sent successfully: {auditMessage.Id}");

            // Track custom event for message sent
            _telemetryService.TrackCustomEvent("AuditMessageSent", 
                new Dictionary<string, string> 
                { 
                    ["MessageId"] = auditMessage.Id,
                    ["Action"] = auditMessage.Action,
                    ["User"] = auditMessage.User,
                    ["Topic"] = _topicName
                });

            // Return success response
            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new
            {
                success = true,
                messageId = auditMessage.Id,
                message = "Audit message sent to Service Bus topic",
                topic = _topicName,
                timestamp = auditMessage.Timestamp
            });

            _telemetryService.TrackFunctionEnd("AuditsAdaptor", executionContext, stopwatch, true);
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending audit message");
            _telemetryService.TrackException(ex, new Dictionary<string, string> { ["Function"] = "AuditsAdaptor" });
            
            var errorResponse = req.CreateResponse(HttpStatusCode.InternalServerError);
            await errorResponse.WriteAsJsonAsync(new
            {
                error = "Failed to send audit message",
                message = ex.Message,
                timestamp = DateTime.UtcNow
            });
            
            _telemetryService.TrackFunctionEnd("AuditsAdaptor", executionContext, stopwatch, false, ex.Message);
            return errorResponse;
        }
    }

    private static string GenerateId()
    {
        return $"audit-{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}-{Guid.NewGuid().ToString("N").Substring(0, 9)}";
    }
}