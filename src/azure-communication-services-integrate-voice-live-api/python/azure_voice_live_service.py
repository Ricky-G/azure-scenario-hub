"""
Azure OpenAI Voice Live API service implementation.
Handles WebSocket connection to Azure OpenAI Voice Live API for real-time audio processing.
"""
import asyncio
import websockets
import json
import logging
from typing import Optional, Callable, Any
import uuid
from datetime import datetime

from config import settings
from models import SessionUpdate, ResponseCreate, InputAudioBuffer
from helpers import AudioHelper

logger = logging.getLogger(__name__)


class AzureVoiceLiveService:
    """
    Service class for Azure OpenAI Voice Live API integration.
    Manages WebSocket connection and real-time audio processing.
    """
    
    def __init__(self, media_handler: Any):
        """
        Initialize Voice Live service.
        
        Args:
            media_handler: Reference to ACS media streaming handler
        """
        self.media_handler = media_handler
        self.websocket: Optional[websockets.WebSocketServerProtocol] = None
        self.connection_ready = asyncio.Event()
        self.running = False
        self.client_request_id = str(uuid.uuid4())
        
        # Audio processing configuration
        self.audio_format = AudioHelper.get_audio_format_info(16000, 1, 16)
        
        logger.info(f"Voice Live service initialized with client ID: {self.client_request_id}")
    
    async def connect(self) -> bool:
        """
        Establish WebSocket connection to Azure Voice Live API using API key authentication - matching .NET implementation.
        
        Returns:
            True if connection successful, False otherwise
        """
        try:
            voice_live_url = settings.get_voice_live_websocket_url(self.client_request_id)
            logger.info(f"Connecting to Voice Live API: {voice_live_url}")
            
            logger.info("Connecting to Voice Live model endpoint with API key in URL (matching .NET implementation)...")
            
            # Connect to Voice Live WebSocket - API key is in URL, no additional headers needed
            self.websocket = await websockets.connect(
                voice_live_url,
                ping_interval=30,
                ping_timeout=10,
                close_timeout=10
            )
            
            logger.info("Voice Live WebSocket connected successfully!")
            
            # Start message receiving task
            asyncio.create_task(self._receive_messages())
            
            # Configure session
            await self._update_session()
            
            # Wait a moment for session to be ready
            await asyncio.sleep(0.5)
            
            # Create conversation with system prompt (matching .NET implementation)
            await self._create_conversation()
            
            # Immediately start AI response to greet caller
            await self._start_response()
            
            # Note: connection_ready will be set when we receive session.updated event
            self.running = True
            
            logger.info("Voice Live WebSocket connected, waiting for session to be ready...")
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect to Voice Live API: {e}")
            return False
    
    async def wait_for_connection(self) -> None:
        """Wait for Voice Live connection to be established."""
        await self.connection_ready.wait()
    
    async def send_audio(self, audio_bytes: bytes) -> None:
        """
        Send audio data to Voice Live API.
        
        Args:
            audio_bytes: PCM audio data
        """
        if not self.websocket or not self.running:
            logger.warning("Voice Live connection not ready")
            return
        
        try:
            if not AudioHelper.is_silent_audio(audio_bytes):
                logger.debug(f"Sending audio data: {len(audio_bytes)} bytes")
                message = InputAudioBuffer.create(audio_bytes)
                await self.websocket.send(message)
            else:
                logger.debug("Skipping silent audio frame")
                
        except Exception as e:
            logger.error(f"Error sending audio to Voice Live: {e}")
    
    async def close(self) -> None:
        """Close Voice Live WebSocket connection."""
        self.running = False
        if self.websocket:
            try:
                await self.websocket.close()
                logger.info("Voice Live connection closed")
            except Exception as e:
                logger.error(f"Error closing Voice Live connection: {e}")
    
    async def _update_session(self) -> None:
        """Update Voice Live session configuration."""
        try:
            session_update = SessionUpdate.create_default()
            await self.websocket.send(session_update)
            logger.debug("Session configuration sent")
        except Exception as e:
            logger.error(f"Error updating session: {e}")
    
    async def _create_conversation(self) -> None:
        """Create initial conversation with system prompt."""
        try:
            conversation_message = {
                "type": "conversation.item.create",
                "item": {
                    "type": "message",
                    "role": "system",
                    "content": [
                        {
                            "type": "input_text",
                            "text": settings.system_prompt
                        }
                    ]
                }
            }
            await self.websocket.send(json.dumps(conversation_message))
            logger.debug("System prompt sent")
        except Exception as e:
            logger.error(f"Error creating conversation: {e}")
    
    async def _start_response(self) -> None:
        """Start AI response generation."""
        try:
            response_message = ResponseCreate.create()
            await self.websocket.send(response_message)
            logger.debug("Response creation triggered")
        except Exception as e:
            logger.error(f"Error starting response: {e}")
    
    async def _receive_messages(self) -> None:
        """
        Receive and process messages from Voice Live API.
        Handles audio deltas and control messages.
        """
        try:
            async for message in self.websocket:
                await self._process_voice_live_message(message)
        except websockets.exceptions.ConnectionClosed:
            logger.info("Voice Live connection closed")
        except Exception as e:
            logger.error(f"Error receiving Voice Live messages: {e}")
        finally:
            self.running = False
    
    async def _process_voice_live_message(self, message: str) -> None:
        """
        Process incoming message from Voice Live API.
        
        Args:
            message: JSON message from Voice Live API
        """
        try:
            data = json.loads(message)
            message_type = data.get("type", "")
            
            logger.debug(f"Received Voice Live message: {message_type}")
            
            if message_type == "session.created":
                logger.info("Voice Live session created")
                
            elif message_type == "session.updated":
                logger.info("Voice Live session updated")
                # Signal that connection is ready for audio processing
                self.connection_ready.set()
                logger.info("Voice Live service ready for audio processing")
                
            elif message_type == "response.audio.delta":
                # Forward audio response to ACS
                if datetime.now().second % 5 == 0:  # Log only every 5 seconds like .NET
                    logger.info(f"Audio streaming active - {len(data.get('delta', ''))} base64 chars")
                await self._handle_audio_delta(data)
                
            elif message_type == "input_audio_buffer.speech_started":
                # Handle barge-in (voice activity detection)
                logger.info("Voice activity detected - triggering barge-in")
                await self._handle_speech_started()
                
            elif message_type == "response.created":
                logger.info("AI response created")
                
            elif message_type == "response.done":
                logger.info("AI response completed")
                
            elif message_type == "error":
                error_info = data.get("error", {})
                logger.error(f"Voice Live API error: {error_info}")
                
            else:
                logger.debug(f"Unhandled message type: {message_type}")
                
        except Exception as e:
            logger.error(f"Error processing Voice Live message: {e}")
    
    async def _handle_audio_delta(self, data: dict) -> None:
        """
        Handle audio delta from Voice Live API and forward to ACS.
        
        Args:
            data: Audio delta message data
        """
        try:
            import base64
            from models import OutboundAudioData
            from audio_resampler import AudioResampler
            
            audio_delta = data.get("delta", "")
            if audio_delta:
                logger.debug(f"Processing audio delta: {len(audio_delta)} base64 chars")
                
                # Decode base64 audio data from Voice Live (24kHz)
                audio_bytes = base64.b64decode(audio_delta)
                logger.debug(f"Decoded audio: {len(audio_bytes)} bytes")
                
                # Resample from 24kHz (Voice Live) to 16kHz (ACS)
                resampled_audio = AudioResampler.resample_24k_to_16k(audio_bytes)
                logger.debug(f"Resampled audio: {len(resampled_audio)} bytes (24kHz->16kHz)")
                
                # Send entire resampled audio buffer immediately (like .NET implementation)
                # Do NOT chunk with delays - this causes timing issues with ACS
                if len(resampled_audio) > 0:
                    outbound_message = OutboundAudioData.create(resampled_audio, "VoiceLiveAI")
                    
                    # Send to ACS media handler immediately - but only if still running
                    if self.media_handler and hasattr(self.media_handler, 'running') and self.media_handler.running:
                        # Await the send operation to ensure proper sequencing and error handling
                        try:
                            await self.media_handler.send_message(outbound_message)
                            
                            # Log occasionally to reduce log spam (like .NET implementation)
                            if datetime.now().second % 3 == 0:
                                logger.info(f"Audio sent to ACS successfully ({len(resampled_audio)} bytes)")
                        except Exception as e:
                            logger.error(f"Failed to send audio to ACS: {e}")
                    elif self.media_handler:
                        logger.warning("Media handler not running - skipping audio send")
                    else:
                        logger.warning("No media handler available to send audio")
                else:
                    logger.warning("Resampled audio is empty")
            else:
                logger.warning("Received empty audio delta")
                    
        except Exception as e:
            logger.error(f"Error handling audio delta: {e}")
            logger.exception("Full audio delta error:")
    
    async def _handle_speech_started(self) -> None:
        """Handle speech started event (barge-in scenario)."""
        try:
            from models import StopAudioData
            
            # Send stop audio message to ACS
            stop_message = StopAudioData.create()
            if self.media_handler:
                await self.media_handler.send_message(stop_message)
                
        except Exception as e:
            logger.error(f"Error handling speech started: {e}")
    
    async def send_message(self, message: str) -> None:
        """
        Send raw message to Voice Live API.
        
        Args:
            message: JSON message string
        """
        if self.websocket and self.running:
            try:
                await self.websocket.send(message)
            except Exception as e:
                logger.error(f"Error sending message to Voice Live: {e}")
        else:
            logger.warning("Cannot send message - Voice Live not connected")
