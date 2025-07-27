using Azure.Communication.CallAutomation;
using Azure.Messaging;
using Azure.Messaging.EventGrid;
using Azure.Messaging.EventGrid.SystemEvents;
using Microsoft.AspNetCore.Mvc;
using Newtonsoft.Json;
using System.ComponentModel.DataAnnotations;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseUrls("http://localhost:49412");

// Configure WebSocket settings
builder.ConfigureWebSockets();

//Get ACS Connection String from appsettings.json
var acsConnectionString = builder.Configuration.GetValue<string>("AcsConnectionString");
ArgumentNullException.ThrowIfNullOrEmpty(acsConnectionString);

//Call Automation Client
var client = new CallAutomationClient(acsConnectionString);
var app = builder.Build();
var appBaseUrl = builder.Configuration.GetValue<string>("BaseUrl")?.TrimEnd('/') ?? Environment.GetEnvironmentVariable("VS_TUNNEL_URL")?.TrimEnd('/');

// Log all available URLs
Console.WriteLine($"Configured BaseUrl: {builder.Configuration.GetValue<string>("BaseUrl")}");
Console.WriteLine($"VS_TUNNEL_URL: {Environment.GetEnvironmentVariable("VS_TUNNEL_URL")}");
Console.WriteLine($"Final appBaseUrl: {appBaseUrl}");

if (string.IsNullOrEmpty(appBaseUrl))
{
    appBaseUrl = $"https://{Environment.GetEnvironmentVariable("WEBSITE_HOSTNAME")}";
    Console.WriteLine($"App base URL: {appBaseUrl}");
}

app.MapGet("/", () => "Hello ACS CallAutomation!");

// Health check endpoint for debugging
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

// WebSocket test endpoint
app.MapGet("/test-ws", async (HttpContext context) =>
{
    if (context.WebSockets.IsWebSocketRequest)
    {
        using var webSocket = await context.WebSockets.AcceptWebSocketAsync();
        var buffer = new byte[1024];
        
        // Send test message
        var testMessage = Encoding.UTF8.GetBytes("WebSocket connection successful!");
        await webSocket.SendAsync(new ArraySegment<byte>(testMessage), WebSocketMessageType.Text, true, CancellationToken.None);
        
        // Echo messages back
        while (webSocket.State == WebSocketState.Open)
        {
            var result = await webSocket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);
            if (result.MessageType == WebSocketMessageType.Text)
            {
                await webSocket.SendAsync(new ArraySegment<byte>(buffer, 0, result.Count), WebSocketMessageType.Text, true, CancellationToken.None);
            }
            else if (result.MessageType == WebSocketMessageType.Close)
            {
                await webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", CancellationToken.None);
            }
        }
    }
    else
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsync("WebSocket connections only");
    }
});

app.MapPost("/api/incomingCall", async (
    [FromBody] EventGridEvent[] eventGridEvents,
    ILogger<Program> logger) =>
{
    foreach (var eventGridEvent in eventGridEvents)
    {
        Console.WriteLine($"Incoming Call event received.");

        // Handle system events
        if (eventGridEvent.TryGetSystemEventData(out object eventData))
        {
            // Handle the subscription validation event.
            if (eventData is SubscriptionValidationEventData subscriptionValidationEventData)
            {
                var responseData = new SubscriptionValidationResponse
                {
                    ValidationResponse = subscriptionValidationEventData.ValidationCode
                };
                return Results.Ok(responseData);
            }
        }

        var jsonObject = Helper.GetJsonObject(eventGridEvent.Data);
        var callerId = Helper.GetCallerId(jsonObject);
        var incomingCallContext = Helper.GetIncomingCallContext(jsonObject);
        logger.LogInformation($"appBaseUrl: {appBaseUrl}");
        var callbackUri = new Uri(new Uri(appBaseUrl), $"/api/callbacks/{Guid.NewGuid()}?callerId={callerId}");
        logger.LogInformation($"Callback Url: {callbackUri}");
        // Ensure WebSocket URL is properly formatted
        var websocketUri = appBaseUrl.Replace("https://", "wss://").Replace("http://", "ws://") + "/ws";
        logger.LogInformation($"WebSocket Url: {websocketUri}");

        var mediaStreamingOptions = new MediaStreamingOptions(MediaStreamingAudioChannel.Mixed)
        {
            TransportUri = new Uri(websocketUri),
            MediaStreamingContent = MediaStreamingContent.Audio,
            StartMediaStreaming = true,  // Let ACS start streaming automatically
            EnableBidirectional = true,
            AudioFormat = AudioFormat.Pcm16KMono
        };
        
        logger.LogInformation($"Media streaming options configured - Audio format: {mediaStreamingOptions.AudioFormat}");
     
        var options = new AnswerCallOptions(incomingCallContext, callbackUri)
        {
            MediaStreamingOptions = mediaStreamingOptions,
        };

        AnswerCallResult answerCallResult = await client.AnswerCallAsync(options);
        logger.LogInformation($"Answered call for connection id: {answerCallResult.CallConnection.CallConnectionId}");
    }
    return Results.Ok();
});

// api to handle call back events
app.MapPost("/api/callbacks/{contextId}", async (
    [FromBody] CloudEvent[] cloudEvents,
    [FromRoute] string contextId,
    [Required] string callerId,
    ILogger<Program> logger) =>
{
    foreach (var cloudEvent in cloudEvents)
    {
        CallAutomationEventBase @event = CallAutomationEventParser.Parse(cloudEvent);
        logger.LogInformation($"Event received: {JsonConvert.SerializeObject(@event, Formatting.Indented)}");
    }

    return Results.Ok();
});

// Use WebSocket configuration with CORS
app.UseWebSocketConfiguration();

app.Use(async (context, next) =>
{
    if (context.Request.Path == "/ws" || context.Request.Path.StartsWithSegments("/ws"))
    {
        if (context.WebSockets.IsWebSocketRequest)
        {
            try
            {
                Console.WriteLine($"WebSocket connection request from: {context.Connection.RemoteIpAddress}");
                Console.WriteLine($"WebSocket path: {context.Request.Path}");
                
                // Accept WebSocket connection
                var webSocket = await context.WebSockets.AcceptWebSocketAsync();
                Console.WriteLine($"WebSocket accepted. State: {webSocket.State}");
                
                var mediaService = new AcsMediaStreamingHandler(webSocket, builder.Configuration);

                // Process WebSocket messages
                await mediaService.ProcessWebSocketAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"WebSocket error: {ex.Message}");
                Console.WriteLine($"Stack trace: {ex.StackTrace}");
            }
        }
        else
        {
            Console.WriteLine($"Not a WebSocket request");
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
        }
    }
    else
    {
        await next(context);
    }
});

app.Run();