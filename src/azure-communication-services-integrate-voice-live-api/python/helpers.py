"""
Helper utilities for Azure Communication Services integration.
Provides event parsing and data extraction functions.
"""
import json
from typing import Dict, Any, Optional
import logging

logger = logging.getLogger(__name__)


class ACSHelper:
    """Helper class for Azure Communication Services event processing."""
    
    @staticmethod
    def get_json_object(event_data: Any) -> Dict[str, Any]:
        """
        Extract JSON object from Event Grid event data.
        
        Args:
            event_data: Event data from Azure Event Grid
            
        Returns:
            Dictionary containing parsed JSON data
        """
        try:
            if isinstance(event_data, str):
                return json.loads(event_data)
            elif isinstance(event_data, dict):
                return event_data
            elif hasattr(event_data, 'to_json'):
                return json.loads(event_data.to_json())
            else:
                # Try to convert to string and parse
                return json.loads(str(event_data))
        except Exception as e:
            logger.error(f"Error parsing JSON object: {e}")
            return {}
    
    @staticmethod
    def get_caller_id(json_object: Dict[str, Any]) -> Optional[str]:
        """
        Extract caller ID from ACS event data.
        
        Args:
            json_object: Parsed JSON object from ACS event
            
        Returns:
            Caller ID string or None if not found
        """
        try:
            return json_object.get("from", {}).get("rawId")
        except Exception as e:
            logger.error(f"Error extracting caller ID: {e}")
            return None
    
    @staticmethod
    def get_incoming_call_context(json_object: Dict[str, Any]) -> Optional[str]:
        """
        Extract incoming call context from ACS event data.
        
        Args:
            json_object: Parsed JSON object from ACS event
            
        Returns:
            Incoming call context string or None if not found
        """
        try:
            return json_object.get("incomingCallContext")
        except Exception as e:
            logger.error(f"Error extracting incoming call context: {e}")
            return None
    
    @staticmethod
    def get_call_connection_id(json_object: Dict[str, Any]) -> Optional[str]:
        """
        Extract call connection ID from ACS event data.
        
        Args:
            json_object: Parsed JSON object from ACS event
            
        Returns:
            Call connection ID string or None if not found
        """
        try:
            return json_object.get("callConnectionId")
        except Exception as e:
            logger.error(f"Error extracting call connection ID: {e}")
            return None
    
    @staticmethod
    def validate_subscription_event(event_data: Dict[str, Any]) -> Optional[str]:
        """
        Validate Event Grid subscription and extract validation code.
        
        Args:
            event_data: Event data from Event Grid
            
        Returns:
            Validation code if this is a subscription validation event, None otherwise
        """
        try:
            event_type = event_data.get("eventType", "")
            if event_type == "Microsoft.EventGrid.SubscriptionValidationEvent":
                return event_data.get("data", {}).get("validationCode")
            return None
        except Exception as e:
            logger.error(f"Error validating subscription event: {e}")
            return None


class URLHelper:
    """Helper class for URL manipulation and formatting."""
    
    @staticmethod
    def create_callback_url(base_url: str, context_id: str, caller_id: str) -> str:
        """
        Create callback URL for ACS events.
        
        Args:
            base_url: Base application URL
            context_id: Unique context identifier
            caller_id: Caller identifier
            
        Returns:
            Formatted callback URL
        """
        base = base_url.rstrip('/')
        return f"{base}/api/callbacks/{context_id}?callerId={caller_id}"
    
    @staticmethod
    def create_websocket_url(base_url: str) -> str:
        """
        Create WebSocket URL from base URL.
        
        Args:
            base_url: Base application URL
            
        Returns:
            WebSocket URL with appropriate protocol
        """
        ws_url = base_url.replace("https://", "wss://").replace("http://", "ws://")
        return f"{ws_url.rstrip('/')}/ws"
    
    @staticmethod
    def ensure_https(url: str) -> str:
        """
        Ensure URL uses HTTPS protocol.
        
        Args:
            url: Original URL
            
        Returns:
            URL with HTTPS protocol
        """
        if url.startswith("http://"):
            return url.replace("http://", "https://")
        elif not url.startswith("https://"):
            return f"https://{url}"
        return url


class AudioHelper:
    """Helper class for audio data processing."""
    
    @staticmethod
    def is_silent_audio(audio_bytes: bytes, threshold: float = 0.01) -> bool:
        """
        Check if audio data represents silence.
        
        Args:
            audio_bytes: Audio data as bytes
            threshold: Silence threshold (0.0 to 1.0)
            
        Returns:
            True if audio is considered silent, False otherwise
        """
        if not audio_bytes:
            return True
        
        try:
            # Simple silence detection - check if all bytes are below threshold
            max_value = max(audio_bytes) if audio_bytes else 0
            return max_value < (threshold * 255)
        except Exception as e:
            logger.error(f"Error checking audio silence: {e}")
            return True
    
    @staticmethod
    def get_audio_format_info(sample_rate: int = 16000, channels: int = 1, bit_depth: int = 16) -> Dict[str, Any]:
        """
        Get audio format information for ACS media streaming.
        
        Args:
            sample_rate: Audio sample rate in Hz
            channels: Number of audio channels
            bit_depth: Audio bit depth
            
        Returns:
            Dictionary with audio format information
        """
        return {
            "sample_rate": sample_rate,
            "channels": channels,
            "bit_depth": bit_depth,
            "format": f"PCM{sample_rate//1000}K{'Mono' if channels == 1 else 'Stereo'}"
        }
