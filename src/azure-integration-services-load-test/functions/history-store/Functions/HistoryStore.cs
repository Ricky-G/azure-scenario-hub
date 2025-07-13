using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using System.Diagnostics;
using HistoryStore.Services;
using HistoryStore.Models;

namespace HistoryStore.Functions;

public class HistoryStore
{
    private readonly ILogger<HistoryStore> _logger;
    private readonly ITelemetryService _telemetryService;

    public HistoryStore(ILogger<HistoryStore> logger, ITelemetryService telemetryService)
    {
        _logger = logger;
        _telemetryService = telemetryService;
    }

    [Function("HistoryStore")]
    public async Task Run(
        [ServiceBusTrigger("%SERVICEBUS_TOPIC_HISTORY%", "%SERVICEBUS_SUBSCRIPTION_HISTORY%", Connection = "SERVICEBUS_CONNECTION_STRING")] 
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        FunctionContext executionContext)
    {
        var stopwatch = Stopwatch.StartNew();
        _telemetryService.TrackFunctionStart("HistoryStore", executionContext);
        _logger.LogInformation("HistoryStore Service Bus topic trigger function processing message");

        try
        {
            // Parse the message body
            var messageBody = message.Body.ToString();
            _logger.LogInformation($"Received history message: {messageBody}");

            var historyMessage = JsonSerializer.Deserialize<HistoryMessage>(messageBody, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (historyMessage == null)
            {
                _logger.LogError("Failed to deserialize history message");
                await messageActions.DeadLetterMessageAsync(message, "InvalidMessage", "Failed to deserialize message body");
                return;
            }

            // Extract message details
            var messageId = historyMessage.Id ?? "unknown";
            var timestamp = historyMessage.Timestamp;
            var eventType = historyMessage.EventType ?? "unknown";
            var entityId = historyMessage.EntityId ?? "unknown";
            var entityType = historyMessage.EntityType ?? "unknown";
            var operation = historyMessage.Operation ?? "unknown";
            var changes = historyMessage.Changes;

            // Log to Application Insights with custom properties
            _logger.LogInformation("History stored - ID: {MessageId}, Entity: {EntityType}/{EntityId}, Operation: {Operation}", 
                messageId, entityType, entityId, operation);

            // Track custom event in Application Insights
            _telemetryService.TrackCustomEvent("HistoryMessageReceived",
                new Dictionary<string, string>
                {
                    ["MessageId"] = messageId,
                    ["EventType"] = eventType,
                    ["EntityId"] = entityId,
                    ["EntityType"] = entityType,
                    ["Operation"] = operation,
                    ["Source"] = historyMessage.Source ?? "unknown",
                    ["MessageSize"] = message.Body.ToArray().Length.ToString()
                },
                new Dictionary<string, double>
                {
                    ["MessageCount"] = 1,
                    ["MessageSizeBytes"] = message.Body.ToArray().Length
                });

            // Simulate history storage (in a real scenario, this would write to a time-series database)
            var historyRecord = new HistoryRecord
            {
                Id = messageId,
                Timestamp = timestamp,
                ReceivedAt = DateTime.UtcNow,
                EventType = eventType,
                Entity = new EntityInfo
                {
                    Id = entityId,
                    Type = entityType
                },
                Operation = operation,
                Changes = changes,
                Metadata = historyMessage.Metadata,
                ProcessedBy = "historystore",
                FunctionInstance = executionContext.InvocationId
            };

            // Validate changes object
            if (changes?.Before != null || changes?.After != null)
            {
                _logger.LogInformation("Change details: Before={Before}, After={After}", 
                    changes.Before != null ? JsonSerializer.Serialize(changes.Before) : "N/A",
                    changes.After != null ? JsonSerializer.Serialize(changes.After) : "N/A");
            }

            // Log successful processing
            _logger.LogInformation($"History record processed successfully: {JsonSerializer.Serialize(historyRecord)}");

            // In a real implementation, you would:
            // 1. Store in time-series database (Cosmos DB with Time Series API, TimescaleDB, etc.)
            // 2. Update entity current state if needed
            // 3. Trigger any history-based analytics or reports
            // 4. Archive old history records

            // Complete the message
            await messageActions.CompleteMessageAsync(message);

            _telemetryService.TrackFunctionEnd("HistoryStore", executionContext, stopwatch, true);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing history message");
            _telemetryService.TrackException(ex, new Dictionary<string, string> 
            { 
                ["Function"] = "HistoryStore",
                ["MessageId"] = message.MessageId,
                ["DeliveryCount"] = message.DeliveryCount.ToString()
            });
            
            // Dead letter the message after retries
            if (message.DeliveryCount >= 5)
            {
                await messageActions.DeadLetterMessageAsync(message, "ProcessingError", ex.Message);
                _telemetryService.TrackCustomEvent("HistoryMessageDeadLettered",
                    new Dictionary<string, string>
                    {
                        ["MessageId"] = message.MessageId,
                        ["Reason"] = "ProcessingError",
                        ["Error"] = ex.Message
                    });
            }
            else
            {
                // Let it retry
                await messageActions.AbandonMessageAsync(message);
            }
            
            _telemetryService.TrackFunctionEnd("HistoryStore", executionContext, stopwatch, false, ex.Message);
            throw;
        }
    }
}