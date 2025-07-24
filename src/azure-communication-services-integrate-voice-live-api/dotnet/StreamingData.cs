using System.Text.Json;
using System.Text.Json.Nodes;

namespace Azure.Communication.CallAutomation
{
    public abstract class StreamingData
    {
        public static StreamingData Parse(string json)
        {
            try
            {
                var parsedJson = JsonNode.Parse(json);
                var kind = parsedJson?["kind"]?.GetValue<string>();
                
                switch (kind)
                {
                    case "AudioData":
                        return new AudioData(parsedJson);
                    case "TranscriptionData":
                        return new TranscriptionData(parsedJson);
                    default:
                        return new UnknownStreamingData(parsedJson);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error parsing streaming data: {ex.Message}");
                return new UnknownStreamingData(null);
            }
        }
    }

    public class AudioData : StreamingData
    {
        public AudioDataProperties AudioDataProperties { get; set; }
        public ReadOnlyMemory<byte> Data { get; set; }
        public DateTime Timestamp { get; set; }
        public string ParticipantId { get; set; }
        public bool IsSilent { get; set; }

        public AudioData(JsonNode parsedJson)
        {
            if (parsedJson == null) return;
            
            var audioData = parsedJson["audioData"];
            if (audioData != null)
            {
                // Parse audio properties
                Timestamp = audioData["timestamp"] != null ? DateTime.Parse(audioData["timestamp"].GetValue<string>()) : DateTime.UtcNow;
                ParticipantId = audioData["participantRawId"]?.GetValue<string>() ?? "";
                IsSilent = audioData["silent"]?.GetValue<bool>() ?? false;
                
                // Parse audio data
                var dataString = audioData["data"]?.GetValue<string>();
                if (!string.IsNullOrEmpty(dataString))
                {
                    Data = Convert.FromBase64String(dataString);
                }
                else
                {
                    Data = ReadOnlyMemory<byte>.Empty;
                }
            }
        }
    }

    public class AudioDataProperties
    {
        public string Encoding { get; set; } = "PCM";
        public int SampleRate { get; set; } = 16000;
        public int Channels { get; set; } = 1;
        public int BitRate { get; set; } = 16;
    }

    public class TranscriptionData : StreamingData
    {
        public string Text { get; set; }
        public string Format { get; set; }
        public double Confidence { get; set; }
        public string ParticipantId { get; set; }
        public DateTime Timestamp { get; set; }

        public TranscriptionData(JsonNode parsedJson)
        {
            if (parsedJson == null) return;
            
            var transcriptionData = parsedJson["transcriptionData"];
            if (transcriptionData != null)
            {
                Text = transcriptionData["text"]?.GetValue<string>() ?? "";
                Format = transcriptionData["format"]?.GetValue<string>() ?? "";
                Confidence = transcriptionData["confidence"]?.GetValue<double>() ?? 0.0;
                ParticipantId = transcriptionData["participantRawId"]?.GetValue<string>() ?? "";
                Timestamp = transcriptionData["timestamp"] != null ? DateTime.Parse(transcriptionData["timestamp"].GetValue<string>()) : DateTime.UtcNow;
            }
        }
    }

    public class UnknownStreamingData : StreamingData
    {
        public JsonNode RawData { get; set; }

        public UnknownStreamingData(JsonNode parsedJson)
        {
            RawData = parsedJson;
        }
    }
}