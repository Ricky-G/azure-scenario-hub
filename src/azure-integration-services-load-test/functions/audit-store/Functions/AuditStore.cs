using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using System.Diagnostics;
using AuditStore.Services;
using AuditStore.Models;

namespace AuditStore.Functions;

public class AuditStore
{
    private readonly ILogger<AuditStore> _logger;
    private readonly ITelemetryService _telemetryService;

    public AuditStore(ILogger<AuditStore> logger, ITelemetryService telemetryService)
    {
        _logger = logger;
        _telemetryService = telemetryService;
    }

    [Function("AuditStore")]
    public async Task Run(
        [ServiceBusTrigger("%SERVICEBUS_TOPIC_AUDITS%", "%SERVICEBUS_SUBSCRIPTION_AUDITS%", Connection = "SERVICEBUS_CONNECTION_STRING")] 
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        FunctionContext executionContext)
    {
        var stopwatch = Stopwatch.StartNew();
        _telemetryService.TrackFunctionStart("AuditStore", executionContext);
        _logger.LogInformation("AuditStore Service Bus topic trigger function processing message");

        try
        {
            // Parse the message body
            var messageBody = message.Body.ToString();
            _logger.LogInformation($"Received audit message: {messageBody}");

            var auditMessage = JsonSerializer.Deserialize<AuditMessage>(messageBody, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (auditMessage == null)
            {
                _logger.LogError("Failed to deserialize audit message");
                await messageActions.DeadLetterMessageAsync(message, "InvalidMessage", "Failed to deserialize message body");
                return;
            }

            // Extract message details
            var messageId = auditMessage.Id ?? "unknown";
            var timestamp = auditMessage.Timestamp;
            var action = auditMessage.Action ?? "unknown";
            var user = auditMessage.User ?? "unknown";
            var details = auditMessage.Details ?? "";

            // Log to Application Insights with custom properties
            _logger.LogInformation("Audit stored - ID: {MessageId}, Action: {Action}, User: {User}", 
                messageId, action, user);

            // Track custom event in Application Insights
            _telemetryService.TrackCustomEvent("AuditMessageReceived",
                new Dictionary<string, string>
                {
                    ["MessageId"] = messageId,
                    ["Action"] = action,
                    ["User"] = user,
                    ["Source"] = auditMessage.Source ?? "unknown",
                    ["MessageSize"] = message.Body.ToArray().Length.ToString()
                },
                new Dictionary<string, double>
                {
                    ["MessageCount"] = 1,
                    ["MessageSizeBytes"] = message.Body.ToArray().Length
                });

            // Simulate audit storage (in a real scenario, this would write to a database)
            var auditRecord = new AuditRecord
            {
                Id = messageId,
                Timestamp = timestamp,
                ReceivedAt = DateTime.UtcNow,
                Action = action,
                User = user,
                Details = details,
                Metadata = auditMessage.Metadata,
                ProcessedBy = "auditstore",
                FunctionInstance = executionContext.InvocationId
            };

            // Log successful processing
            _logger.LogInformation($"Audit record processed successfully: {JsonSerializer.Serialize(auditRecord)}");

            // In a real implementation, you would:
            // 1. Store in database (Cosmos DB, SQL, etc.)
            // 2. Send to long-term storage (Blob Storage)
            // 3. Trigger any downstream processes

            // Complete the message
            await messageActions.CompleteMessageAsync(message);

            _telemetryService.TrackFunctionEnd("AuditStore", executionContext, stopwatch, true);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing audit message");
            _telemetryService.TrackException(ex, new Dictionary<string, string> 
            { 
                ["Function"] = "AuditStore",
                ["MessageId"] = message.MessageId,
                ["DeliveryCount"] = message.DeliveryCount.ToString()
            });
            
            // Dead letter the message after retries
            if (message.DeliveryCount >= 5)
            {
                await messageActions.DeadLetterMessageAsync(message, "ProcessingError", ex.Message);
                _telemetryService.TrackCustomEvent("AuditMessageDeadLettered",
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
            
            _telemetryService.TrackFunctionEnd("AuditStore", executionContext, stopwatch, false, ex.Message);
            throw;
        }
    }
}