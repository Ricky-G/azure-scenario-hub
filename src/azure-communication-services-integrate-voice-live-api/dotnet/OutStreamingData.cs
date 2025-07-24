using System.Text.Json;

namespace Azure.Communication.CallAutomation
{
    public static class OutStreamingData
    {
        /// <summary>
        /// Creates a JSON string for sending audio data to ACS
        /// </summary>
        public static string GetAudioDataForOutbound(byte[] audioData)
        {
            var audioJson = new
            {
                kind = "AudioData",
                audioData = new
                {
                    data = Convert.ToBase64String(audioData),
                    timestamp = DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"),
                    participantRawId = "VoiceLiveAI",
                    silent = false
                }
            };

            return JsonSerializer.Serialize(audioJson);
        }

        /// <summary>
        /// Creates a JSON string for stopping audio playback (used for barge-in)
        /// </summary>
        public static string GetStopAudioForOutbound()
        {
            var stopAudioJson = new
            {
                kind = "StopAudio"
            };

            return JsonSerializer.Serialize(stopAudioJson);
        }

        /// <summary>
        /// Creates a JSON string for sending transcription data to ACS
        /// </summary>
        public static string GetTranscriptionDataForOutbound(string text, double confidence = 1.0)
        {
            var transcriptionJson = new
            {
                kind = "TranscriptionData",
                transcriptionData = new
                {
                    text = text,
                    format = "display",
                    confidence = confidence,
                    timestamp = DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"),
                    participantRawId = "VoiceLiveAI",
                    resultStatus = "Final"
                }
            };

            return JsonSerializer.Serialize(transcriptionJson);
        }
    }
}