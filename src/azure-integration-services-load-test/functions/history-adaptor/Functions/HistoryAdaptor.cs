using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using System.Net;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using System.Diagnostics;
using HistoryAdaptor.Services;
using HistoryAdaptor.Models;

namespace HistoryAdaptor.Functions;

public class HistoryAdaptor
{
    private readonly ILogger<HistoryAdaptor> _logger;
    private readonly ServiceBusClient _serviceBusClient;
    private readonly ITelemetryService _telemetryService;
    private readonly string _topicName;

    public HistoryAdaptor(ILogger<HistoryAdaptor> logger, ServiceBusClient serviceBusClient, ITelemetryService telemetryService)
    {
        _logger = logger;
        _serviceBusClient = serviceBusClient;
        _telemetryService = telemetryService;
        _topicName = Environment.GetEnvironmentVariable("SERVICEBUS_TOPIC_HISTORY") ?? "history";
    }

    [Function("HistoryAdaptor")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", Route = "history")] HttpRequestData req,
        FunctionContext executionContext)
    {
        var stopwatch = Stopwatch.StartNew();
        _telemetryService.TrackFunctionStart("HistoryAdaptor", executionContext);
        _logger.LogInformation("HistoryAdaptor HTTP trigger function processed a request.");

        try
        {
            // Parse request body
            var requestBody = await req.ReadAsStringAsync();
            HistoryRequest? historyRequest = null;
            
            if (!string.IsNullOrEmpty(requestBody))
            {
                historyRequest = JsonSerializer.Deserialize<HistoryRequest>(requestBody, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
            }

            // Create history message
            var historyMessage = new HistoryMessage
            {
                Id = GenerateId(),
                Timestamp = DateTime.UtcNow,
                Source = "historyadaptor",
                EventType = historyRequest?.EventType ?? "history-event",
                EntityId = historyRequest?.EntityId ?? GenerateEntityId(),
                EntityType = historyRequest?.EntityType ?? "test-entity",
                Operation = historyRequest?.Operation ?? "create",
                Changes = historyRequest?.Changes ?? new ChangeSet
                {
                    Before = null,
                    After = new Dictionary<string, object>
                    {
                        ["status"] = "active",
                        ["createdAt"] = DateTime.UtcNow
                    }
                },
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
            
            var serviceBusMessage = new ServiceBusMessage(JsonSerializer.Serialize(historyMessage))
            {
                ContentType = "application/json",
                Subject = historyMessage.EventType
            };
            
            // Add application properties
            serviceBusMessage.ApplicationProperties.Add("entityType", historyMessage.EntityType);
            serviceBusMessage.ApplicationProperties.Add("operation", historyMessage.Operation);
            
            await sender.SendMessageAsync(serviceBusMessage);

            _logger.LogInformation($"History message sent successfully: {historyMessage.Id}");

            // Track custom event for message sent
            _telemetryService.TrackCustomEvent("HistoryMessageSent", 
                new Dictionary<string, string> 
                { 
                    ["MessageId"] = historyMessage.Id,
                    ["EventType"] = historyMessage.EventType,
                    ["EntityId"] = historyMessage.EntityId,
                    ["EntityType"] = historyMessage.EntityType,
                    ["Operation"] = historyMessage.Operation,
                    ["Topic"] = _topicName
                });

            // Return success response
            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new
            {
                success = true,
                messageId = historyMessage.Id,
                message = "History message sent to Service Bus topic",
                topic = _topicName,
                timestamp = historyMessage.Timestamp,
                entityId = historyMessage.EntityId
            });

            _telemetryService.TrackFunctionEnd("HistoryAdaptor", executionContext, stopwatch, true);
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending history message");
            _telemetryService.TrackException(ex, new Dictionary<string, string> { ["Function"] = "HistoryAdaptor" });
            
            var errorResponse = req.CreateResponse(HttpStatusCode.InternalServerError);
            await errorResponse.WriteAsJsonAsync(new
            {
                error = "Failed to send history message",
                message = ex.Message,
                timestamp = DateTime.UtcNow
            });
            
            _telemetryService.TrackFunctionEnd("HistoryAdaptor", executionContext, stopwatch, false, ex.Message);
            return errorResponse;
        }
    }

    private static string GenerateId()
    {
        return $"hist-{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}-{Guid.NewGuid().ToString("N").Substring(0, 9)}";
    }

    private static string GenerateEntityId()
    {
        return $"entity-{Guid.NewGuid().ToString("N").Substring(0, 11)}";
    }
}