using System.Net.WebSockets;
using Azure.Communication.CallAutomation;
using System.Text;
using System.Text.Json;

namespace CallAutomation.AzureAI.VoiceLive
{
    public class AzureVoiceLiveService
    {
        private CancellationTokenSource m_cts;
        private AcsMediaStreamingHandler m_mediaStreaming;
        private string m_answerPromptSystemTemplate = "You are an AI assistant that helps people find information.";
        private ClientWebSocket m_azureVoiceLiveWebsocket;
        private TaskCompletionSource<bool> m_connectionReady;
        private string m_systemPrompt;

        public AzureVoiceLiveService(AcsMediaStreamingHandler mediaStreaming, IConfiguration configuration)
        {            
            m_mediaStreaming = mediaStreaming;
            m_cts = new CancellationTokenSource();
            m_connectionReady = new TaskCompletionSource<bool>();
            
            // Start connection asynchronously
            _ = Task.Run(async () => await CreateAISessionAsync(configuration));
        }
        
        public async Task WaitForConnectionAsync()
        {
            await m_connectionReady.Task;
        }

        private async Task CreateAISessionAsync(IConfiguration configuration)
        {
            var azureVoiceLiveApiKey = configuration.GetValue<string>("AzureVoiceLiveApiKey");
            ArgumentNullException.ThrowIfNullOrEmpty(azureVoiceLiveApiKey);

            var azureVoiceLiveEndpoint = configuration.GetValue<string>("AzureVoiceLiveEndpoint");
            ArgumentNullException.ThrowIfNullOrEmpty(azureVoiceLiveEndpoint);

            var voiceLiveModel = configuration.GetValue<string>("VoiceLiveModel");
            ArgumentNullException.ThrowIfNullOrEmpty(voiceLiveModel);

            m_systemPrompt = configuration.GetValue<string>("SystemPrompt") ?? m_answerPromptSystemTemplate;
            ArgumentNullException.ThrowIfNullOrEmpty(m_systemPrompt);

            // The URL to connect to - ensure no double slashes
            var baseUrl = azureVoiceLiveEndpoint.Replace("https://", "wss://").TrimEnd('/');
            var azureVoiceLiveWebsocketUrl = new Uri($"{baseUrl}/voice-live/realtime?api-version=2025-05-01-preview&x-ms-client-request-id={Guid.NewGuid()}&model={voiceLiveModel}&api-key={azureVoiceLiveApiKey}");

            // Create a new WebSocket client
            m_azureVoiceLiveWebsocket = new ClientWebSocket();

            Console.WriteLine($"Connecting to {azureVoiceLiveWebsocketUrl}...");

            try
            {
                // Connect to the WebSocket server
                await m_azureVoiceLiveWebsocket.ConnectAsync(azureVoiceLiveWebsocketUrl, CancellationToken.None);
                Console.WriteLine("Voice Live WebSocket connected successfully!");

                // Listen to messages over websocket
                StartConversation();

                // Update the session
                await UpdateSessionAsync();
                
                // Create initial conversation with system prompt
                await CreateConversationAsync();

                //Start Response from AI
                await StartResponseAsync();
                
                // Signal that connection is ready
                m_connectionReady.SetResult(true);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Failed to connect to Voice Live API: {ex.Message}");
                m_connectionReady.SetException(ex);
                throw;
            }
        }

        private async Task UpdateSessionAsync()
        {
            var jsonObject = new
            {
                type = "session.update",
                session = new
                {
                    turn_detection = new
                    {
                        type = "azure_semantic_vad",
                        threshold = 0.3,
                        prefix_padding_ms = 200,
                        silence_duration_ms = 200,
                        remove_filler_words = false
                    },
                    input_audio_sampling_rate = 24000,
                    input_audio_noise_reduction = new { type = "azure_deep_noise_suppression" },
                    input_audio_echo_cancellation = new { type = "server_echo_cancellation" },
                    voice = new
                    {
                        name = "en-US-Aria:DragonHDLatestNeural",
                        type = "azure-standard",
                        temperature = 0.8
                    }
                }
            };

            // Convert object to JSON string with indentation
            string sessionUpdate = JsonSerializer.Serialize(jsonObject, new JsonSerializerOptions { WriteIndented = false });
            Console.WriteLine($"Sending session update to Voice Live API");
            Console.WriteLine($"SessionUpdate: {sessionUpdate}");
            await SendMessageAsync(sessionUpdate, CancellationToken.None);
        }

        private async Task CreateConversationAsync()
        {
            // Create conversation item with system prompt
            var conversationItem = new
            {
                type = "conversation.item.create",
                item = new
                {
                    type = "message",
                    role = "system",
                    content = new[]
                    {
                        new
                        {
                            type = "input_text",
                            text = m_systemPrompt
                        }
                    }
                }
            };
            
            var message = JsonSerializer.Serialize(conversationItem, new JsonSerializerOptions { WriteIndented = false });
            Console.WriteLine($"Creating conversation with system prompt");
            await SendMessageAsync(message, CancellationToken.None);
        }

        private async Task StartResponseAsync()
        {
            var jsonObject = new
            {
                type = "response.create"
            };
            var message = JsonSerializer.Serialize(jsonObject, new JsonSerializerOptions { WriteIndented = false });
            await SendMessageAsync(message, CancellationToken.None);
        }

        // Method to send messages to the WebSocket server
        async Task SendMessageAsync(string message, CancellationToken cancellationToken)
        {
            //Console.WriteLine($"Sending Message: {message}");

            if (m_azureVoiceLiveWebsocket != null)
            {
                if (m_azureVoiceLiveWebsocket.State != WebSocketState.Open)
                    return;

                byte[] messageBytes = Encoding.UTF8.GetBytes(message);
                await m_azureVoiceLiveWebsocket.SendAsync(
                    new ArraySegment<byte>(messageBytes),
                    WebSocketMessageType.Text,
                    true,
                    cancellationToken);

                //Console.WriteLine($"Sent: {message}");
            }
        }

        // Method to receive messages from the WebSocket server
        async Task ReceiveMessagesAsync(CancellationToken cancellationToken)
        {
            byte[] buffer = new byte[1024 * 8]; // 8KB buffer

            try
            {
                while (m_azureVoiceLiveWebsocket.State == WebSocketState.Open && !cancellationToken.IsCancellationRequested)
                {
                    var receiveBuffer = new ArraySegment<byte>(buffer);
                    StringBuilder messageBuilder = new StringBuilder();

                    WebSocketReceiveResult result = null;

                    do
                    {
                        result = await m_azureVoiceLiveWebsocket.ReceiveAsync(receiveBuffer, cancellationToken);
                        messageBuilder.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));

                        if (result.MessageType == WebSocketMessageType.Close)
                        {
                            await m_azureVoiceLiveWebsocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", CancellationToken.None);
                            return;
                        }

                    } while (!result.EndOfMessage); // Ensure full message is received

                    string receivedMessage = messageBuilder.ToString();
                    // Only log non-audio delta messages to reduce clutter
                    if (!receivedMessage.Contains("response.audio.delta"))
                    {
                        Console.WriteLine($"Received: {receivedMessage}");
                    }

                    var data = JsonSerializer.Deserialize<Dictionary<string, object>>(receivedMessage);

                    if (data != null)
                    {
                        var eventType = data["type"]?.ToString();
                        
                        // Only log important events, skip audio deltas
                        if (eventType != "response.audio.delta")
                        {
                            Console.WriteLine($"Voice Live event: {eventType}");
                        }
                        
                        if (eventType == "session.created")
                        {
                            Console.WriteLine("Voice Live session created successfully");
                        }
                        else if (eventType == "session.updated")
                        {
                            Console.WriteLine("Voice Live session updated successfully");
                        }
                        else if (eventType == "error")
                        {
                            var error = data["error"];
                            Console.WriteLine($"Voice Live error: {error}");
                        }
                        else if (eventType == "response.audio.delta")
                        {
                            var deltaData = data["delta"]?.ToString();
                            if (!string.IsNullOrEmpty(deltaData))
                            {
                                var audioBytes = Convert.FromBase64String(deltaData);
                                
                                // Resample audio from 24KHz (Voice Live) to 16KHz (ACS)
                                var resampledAudio = AudioResampler.Resample24kTo16k(audioBytes);
                                
                                // Log only occasionally to reduce noise
                                if (DateTime.UtcNow.Second % 5 == 0) // Log every 5 seconds
                                {
                                    Console.WriteLine($"Audio streaming active - {resampledAudio.Length} bytes sent to ACS");
                                }
                                
                                var jsonString = OutStreamingData.GetAudioDataForOutbound(resampledAudio);
                                await m_mediaStreaming.SendMessageAsync(jsonString);
                            }
                        }
                        else if (data["type"].ToString() == "input_audio_buffer.speech_started")
                        {
                            Console.WriteLine($"  -- Voice activity detection started");
                            // Barge-in, send stop audio
                            var jsonString = OutStreamingData.GetStopAudioForOutbound();
                            await m_mediaStreaming.SendMessageAsync(jsonString);
                        }
                    }
                    else
                    {
                        Console.WriteLine($"Received message is null or empty.");
                    }
                }
            }
            catch (OperationCanceledException)
            {
                // Operation was canceled, which is fine
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error while receiving: {ex.Message}");
            }
        }

        public void StartConversation()
        {
            _ = Task.Run(async () => await ReceiveMessagesAsync(m_cts.Token));
        }

        public async Task SendAudioToExternalAI(byte[] data)
        {
            try
            {
                if (m_azureVoiceLiveWebsocket?.State != WebSocketState.Open)
                {
                    Console.WriteLine($"Cannot send audio - WebSocket is not open. State: {m_azureVoiceLiveWebsocket?.State}");
                    return;
                }
                
                // Resample audio from 16KHz to 24KHz before sending to Voice Live
                var resampledData = AudioResampler.Resample16kTo24k(data);
                
                var audioBytes = Convert.ToBase64String(resampledData);
                var jsonObject = new
                {
                    type = "input_audio_buffer.append",
                    audio = audioBytes
                };

                var message = JsonSerializer.Serialize(jsonObject, new JsonSerializerOptions { WriteIndented = false });
                await SendMessageAsync(message, CancellationToken.None);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error sending audio to Voice Live: {ex.Message}");
            }
        }
        

        public async Task Close()
        {
            m_cts.Cancel();
            m_cts.Dispose();
            if (m_azureVoiceLiveWebsocket != null)
            {
                try
                {
                    // Only attempt to close if the WebSocket is still open
                    if (m_azureVoiceLiveWebsocket.State == WebSocketState.Open)
                    {
                        await m_azureVoiceLiveWebsocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Normal", CancellationToken.None);
                    }
                    else
                    {
                        Console.WriteLine($"WebSocket already closed or in closing state: {m_azureVoiceLiveWebsocket.State}");
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error during WebSocket cleanup: {ex.Message}");
                }
                finally
                {
                    m_azureVoiceLiveWebsocket?.Dispose();
                }
            }
        }
    }
}