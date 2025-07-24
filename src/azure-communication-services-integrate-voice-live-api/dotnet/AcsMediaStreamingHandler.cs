using System.Net.WebSockets;
using Azure.Communication.CallAutomation;
using System.Text;
using CallAutomation.AzureAI.VoiceLive;

public class AcsMediaStreamingHandler
{
    private WebSocket m_webSocket;
    private CancellationTokenSource m_cts;
    private MemoryStream m_buffer;
    private AzureVoiceLiveService m_aiServiceHandler;
    private IConfiguration m_configuration;

    // Constructor to inject AzureAIFoundryClient
    public AcsMediaStreamingHandler(WebSocket webSocket, IConfiguration configuration)
    {
        m_webSocket = webSocket;
        m_configuration = configuration;
        m_buffer = new MemoryStream();
        m_cts = new CancellationTokenSource();
    }
      
    // Method to receive messages from WebSocket
    public async Task ProcessWebSocketAsync()
    {    
        if (m_webSocket == null || m_webSocket.State != WebSocketState.Open)
        {
            Console.WriteLine($"WebSocket is not in Open state. Current state: {m_webSocket?.State}");
            return;
        }
        
        Console.WriteLine("ACS WebSocket connected successfully. Initializing Voice Live connection...");
        
        // start forwarder to AI model
        m_aiServiceHandler = new AzureVoiceLiveService(this, m_configuration);
        
        try
        {
            // Wait for Voice Live to be ready before processing audio
            await m_aiServiceHandler.WaitForConnectionAsync();
            Console.WriteLine("Voice Live connection established. Starting audio processing...");
            
            await StartReceivingFromAcsMediaWebSocket();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error in ProcessWebSocketAsync: {ex.Message}");
            Console.WriteLine($"Stack trace: {ex.StackTrace}");
        }
        finally
        {
            await m_aiServiceHandler.Close();
            this.Close();
        }
    }

    public async Task SendMessageAsync(string message)
    {
        try
        {
            if (m_webSocket?.State == WebSocketState.Open)
            {
                byte[] jsonBytes = Encoding.UTF8.GetBytes(message);

                // Send the message over WebSocket
                await m_webSocket.SendAsync(new ArraySegment<byte>(jsonBytes), WebSocketMessageType.Text, endOfMessage: true, CancellationToken.None);
            }
            else
            {
                Console.WriteLine($"Cannot send message - WebSocket state: {m_webSocket?.State}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error sending message to ACS: {ex.Message}");
        }
    }

    public async Task CloseWebSocketAsync(WebSocketReceiveResult result)
    {
        await m_webSocket.CloseAsync(result.CloseStatus.Value, result.CloseStatusDescription, CancellationToken.None);
    }

    public async Task CloseNormalWebSocketAsync()
    {
        await m_webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Stream completed", CancellationToken.None);
    }

    public void Close()
    {
        m_cts.Cancel();
        m_cts.Dispose();
        m_buffer.Dispose();
    }

    private async Task WriteToAzureFoundryAIServiceInputStream(string data)
    {
        try
        {
            var input = StreamingData.Parse(data);
            if (input is AudioData audioData)
            {
                // Only log first few audio packets to confirm flow
                if (DateTime.UtcNow.Second % 10 == 0)
                {
                    Console.WriteLine($"Received audio from caller - Size: {audioData.Data.Length} bytes, ParticipantId: {audioData.ParticipantId}");
                }
                
                if (!audioData.IsSilent && audioData.Data.Length > 0)
                {
                    await m_aiServiceHandler.SendAudioToExternalAI(audioData.Data.ToArray());
                }
            }
            else if (input is TranscriptionData transcriptionData)
            {
                Console.WriteLine($"Received transcription: {transcriptionData.Text}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error processing streaming data: {ex.Message}");
        }
    }

    // receive messages from WebSocket
    private async Task StartReceivingFromAcsMediaWebSocket()
    {
        if (m_webSocket == null)
        {
            return;
        }
        
        try
        {
            var buffer = new ArraySegment<byte>(new byte[4096]);
            
            while (m_webSocket.State == WebSocketState.Open && !m_cts.Token.IsCancellationRequested)
            {
                WebSocketReceiveResult receiveResult = await m_webSocket.ReceiveAsync(buffer, m_cts.Token);

                if (receiveResult.MessageType == WebSocketMessageType.Close)
                {
                    Console.WriteLine($"WebSocket close message received: {receiveResult.CloseStatus} - {receiveResult.CloseStatusDescription}");
                    break;
                }
                
                if (receiveResult.MessageType == WebSocketMessageType.Text)
                {
                    string data = Encoding.UTF8.GetString(buffer.Array, 0, receiveResult.Count);
                    await WriteToAzureFoundryAIServiceInputStream(data);               
                }
                else if (receiveResult.MessageType == WebSocketMessageType.Binary)
                {
                    Console.WriteLine($"Received unexpected binary message of {receiveResult.Count} bytes");
                }
            }
            
            Console.WriteLine($"Exiting receive loop. WebSocket state: {m_webSocket.State}");
        }
        catch (OperationCanceledException)
        {
            Console.WriteLine("Receive operation was cancelled");
        }
        catch (WebSocketException wsEx)
        {
            Console.WriteLine($"WebSocket exception: {wsEx.Message}, Error code: {wsEx.WebSocketErrorCode}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Unexpected exception in StartReceivingFromAcsMediaWebSocket: {ex.Message}");
        }
    }
}