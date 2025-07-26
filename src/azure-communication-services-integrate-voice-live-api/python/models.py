"""
Data models for Azure Communication Services media streaming.
Handles audio data processing and WebSocket message formatting.
"""
from pydantic import BaseModel
from typing import Optional, Dict, Any, Union, List
import json
import base64
from datetime import datetime


class StreamingDataBase(BaseModel):
    """Base class for all streaming data types."""
    kind: str


class AudioData(StreamingDataBase):
    """Audio data from Azure Communication Services media streaming."""
    kind: str = "AudioData"
    data: str  # Base64 encoded audio data
    timestamp: Union[int, str]  # Can be either int or ISO 8601 string
    participant_raw_id: str = ""
    is_silent: bool = False
    
    def get_timestamp_ms(self) -> int:
        """
        Get timestamp as milliseconds since epoch.
        
        Handles both integer timestamps and ISO 8601 string formats 
        from different ACS message sources.
        """
        if isinstance(self.timestamp, int):
            return self.timestamp
        elif isinstance(self.timestamp, str):
            try:
                # Parse ISO 8601 format: '2025-07-23T10:35:30.363Z'
                from datetime import datetime
                dt = datetime.fromisoformat(self.timestamp.replace('Z', '+00:00'))
                return int(dt.timestamp() * 1000)  # Convert to milliseconds
            except Exception:
                return 0
        return 0
    
    def to_bytes(self) -> bytes:
        """Convert base64 audio data to bytes."""
        if not self.data:
            return b""
        try:
            # Handle potential padding issues in base64
            data = self.data
            if len(data) % 4 != 0:
                data += '=' * (4 - len(data) % 4)
            return base64.b64decode(data)
        except Exception as e:
            # Log the error once per instance to avoid spam
            if not hasattr(self, '_decode_error_logged'):
                import logging
                logger = logging.getLogger(__name__)
                logger.error(f"Base64 decode error: {e}, data sample: {self.data[:50]}...")
                self._decode_error_logged = True
            return b""


class AudioMetadata(StreamingDataBase):
    """Audio metadata from Azure Communication Services media streaming."""
    kind: str = "AudioMetadata"
    subscription_id: str = ""
    encoding: str = ""
    sample_rate: int = 0
    channels: int = 0
    length: int = 0


class UnknownStreamingData(StreamingDataBase):
    """Unknown streaming data type."""
    kind: str = "Unknown"
    properties: Dict[str, Any] = {}


class OutboundAudioData(BaseModel):
    """Outbound audio data packet for ACS."""
    kind: str = "AudioData"
    audio_data: Dict[str, Any]
    
    @classmethod
    def create(cls, audio_bytes: bytes, participant_id: str = "VoiceLiveAI") -> str:
        """Create JSON string for outbound audio data in the exact format ACS expects."""
        timestamp = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'
        
        data = {
            "kind": "AudioData",
            "audioData": {
                "data": base64.b64encode(audio_bytes).decode('utf-8'),
                "timestamp": timestamp,
                "participantRawID": participant_id,
                "silent": len(audio_bytes) == 0 or all(b == 0 for b in audio_bytes)
            }
        }
        return json.dumps(data)


class StopAudioData(BaseModel):
    """Stop audio packet for ACS (barge-in scenarios)."""
    
    @classmethod
    def create(cls) -> str:
        """Create JSON string to stop audio playback."""
        timestamp = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'
        
        data = {
            "kind": "StopAudio",
            "stopAudio": {
                "timestamp": timestamp
            }
        }
        return json.dumps(data)


class StreamingDataParser:
    """Parser for incoming streaming data from ACS."""
    
    @staticmethod
    def parse(json_data: Union[str, dict]) -> Union[AudioData, AudioMetadata, UnknownStreamingData]:
        """Parse JSON string or dict into appropriate streaming data object."""
        try:
            # Handle both string and dict input
            if isinstance(json_data, str):
                data = json.loads(json_data)
            elif isinstance(json_data, dict):
                data = json_data
            else:
                raise ValueError(f"Unsupported data type: {type(json_data)}")
                
            kind = data.get("kind", "Unknown")
            
            if kind == "AudioData":
                # Handle the actual ACS format: {"kind":"AudioData","audioData":{...}}
                audio_data = data.get("audioData", data)  # Fallback to direct structure
                
                # Handle timestamp - can be int, string, or ISO format
                timestamp_raw = audio_data.get("timestamp", 0)
                if isinstance(timestamp_raw, str):
                    # Keep as string for proper parsing in AudioData
                    timestamp = timestamp_raw
                else:
                    # Already an integer
                    timestamp = int(timestamp_raw) if timestamp_raw else 0
                
                return AudioData(
                    data=audio_data.get("data", ""),
                    timestamp=timestamp,
                    participant_raw_id=audio_data.get("participantRawID", ""),
                    is_silent=audio_data.get("silent", False)  # Note: "silent" not "isSilent"
                )
            elif kind == "AudioMetadata":
                # Handle the ACS AudioMetadata format: {"kind":"AudioMetadata","audioMetadata":{...}}
                audio_metadata = data.get("audioMetadata", data)  # Fallback to direct structure
                
                return AudioMetadata(
                    subscription_id=audio_metadata.get("subscriptionId", ""),
                    encoding=audio_metadata.get("encoding", ""),
                    sample_rate=int(audio_metadata.get("sampleRate", 0)),
                    channels=int(audio_metadata.get("channels", 0)),
                    length=int(audio_metadata.get("length", 0))
                )
            else:
                return UnknownStreamingData(properties=data)
                
        except Exception as e:
            import logging
            logger = logging.getLogger(__name__)
            
            # Handle timestamp parsing errors gracefully
            if "invalid literal for int()" in str(e) and "timestamp" in str(json_data):
                logger.warning(f"Timestamp parsing error, using string format: {e}")
                try:
                    if isinstance(json_data, dict):
                        audio_data = json_data.get("audioData", json_data)
                        return AudioData(
                            data=audio_data.get("data", ""),
                            timestamp=str(audio_data.get("timestamp", "0")),
                            participant_raw_id=audio_data.get("participantRawID", ""),
                            is_silent=audio_data.get("silent", False)
                        )
                except Exception:
                    pass  # Fall through to generic error handling
            
            logger.error(f"Error parsing streaming data: {e}")
            return UnknownStreamingData(properties={"error": str(e), "received_data_type": str(type(json_data))})


class VoiceLiveMessage(BaseModel):
    """Azure OpenAI Voice Live API message structure."""
    type: str
    event_id: Optional[str] = None
    
    
class SessionUpdate(VoiceLiveMessage):
    """Session update message for Voice Live API."""
    type: str = "session.update"
    session: Dict[str, Any]
    
    @classmethod
    def create_default(cls) -> str:
        """Create default session update configuration for agent mode."""
        session_config = {
            "type": "session.update",
            "session": {
                "turn_detection": {
                    "type": "azure_semantic_vad",
                    "threshold": 0.3,
                    "prefix_padding_ms": 300,  # Slightly more padding for phone quality
                    "silence_duration_ms": 500,  # Longer silence before ending turn
                    "remove_filler_words": False
                },
                "input_audio_sampling_rate": 24000,
                "input_audio_noise_reduction": {"type": "azure_deep_noise_suppression"},
                "input_audio_echo_cancellation": {"type": "server_echo_cancellation"},
                "voice": {
                    "name": "en-US-Aria:DragonHDLatestNeural",
                    "type": "azure-standard",
                    "temperature": 0.7
                },
                "max_response_output_tokens": 200,
                "modalities": ["text", "audio"]
            }
        }
        
        return json.dumps(session_config)


class ResponseCreate(VoiceLiveMessage):
    """Response creation message for Voice Live API."""
    type: str = "response.create"
    
    @classmethod
    def create(cls) -> str:
        """Create response creation message."""
        return json.dumps({"type": "response.create"})


class InputAudioBuffer(VoiceLiveMessage):
    """Input audio buffer message for Voice Live API."""
    type: str = "input_audio_buffer.append"
    audio: str
    
    @classmethod
    def create(cls, audio_bytes: bytes) -> str:
        """Create input audio buffer message."""
        return json.dumps({
            "type": "input_audio_buffer.append",
            "audio": base64.b64encode(audio_bytes).decode('utf-8')
        })
