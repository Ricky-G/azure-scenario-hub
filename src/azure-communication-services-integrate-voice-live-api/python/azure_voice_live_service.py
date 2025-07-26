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
    
    async def connect(self) -> bool:
        """
        Establish WebSocket connection to Azure Voice Live API using API key authentication - matching .NET implementation.
        
        Returns:
            True if connection successful, False otherwise
        """
        try:
            # Ensure any existing connection is closed first
            if self.websocket and not self.websocket.closed:
                await self.websocket.close()
                
            voice_live_url = settings.get_voice_live_websocket_url(self.client_request_id)
            
            if settings.use_managed_identity:
                logger.info("Connecting to Voice Live API using Azure Managed Identity...")
                # Get WebSocket headers with Authorization token
                headers = settings.get_websocket_headers(self.client_request_id)
                
                # Connect to Voice Live WebSocket with authentication headers
                # Use extra_headers parameter instead of additional_headers
                self.websocket = await websockets.connect(
                    voice_live_url,
                    extra_headers=headers,
                    ping_interval=30,
                    ping_timeout=10,
                    close_timeout=10
                )
            else:
                logger.info("Connecting to Voice Live API using API key...")
                # Connect to Voice Live WebSocket - API key is in URL, no additional headers needed
                self.websocket = await websockets.connect(
                    voice_live_url,
                    ping_interval=30,
                    ping_timeout=10,
                    close_timeout=10
                )
            
            logger.info("Voice Live WebSocket connected")
            
            # Start message receiving task
            asyncio.create_task(self._receive_messages())
            
            if settings.use_managed_identity:
                # Agent mode: Send session update but skip system prompt - instructions are pre-configured in the agent
                await self._update_session()
                await asyncio.sleep(0.2)
                self.running = True
            else:
                # API key mode: Configure session and system prompt
                await self._update_session()
                await asyncio.sleep(0.2)
                await self._create_conversation()
                await self._start_response()
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
            return
        
        try:
            if not AudioHelper.is_silent_audio(audio_bytes):
                message = InputAudioBuffer.create(audio_bytes)
                await self.websocket.send(message)
                
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
        """Update Voice Live session configuration - required for both API key and agent modes."""
        try:
            # In agent mode, exclude instructions (they're read-only and pre-configured)
            # In API key mode, include instructions
            include_instructions = not settings.use_managed_identity
            session_update = SessionUpdate.create_default(include_instructions=include_instructions)
            await self.websocket.send(session_update)
        except Exception as e:
            logger.error(f"Error updating session: {e}")
    
    async def _create_conversation(self) -> None:
        """Create initial conversation with system prompt - only for API key mode."""
        if settings.use_managed_identity:
            return
            
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
        except Exception as e:
            logger.error(f"Error creating conversation: {e}")
    
    async def _start_response(self) -> None:
        """Start AI response generation."""
        try:
            if not self.websocket or self.websocket.closed:
                logger.warning("Cannot start response - WebSocket not connected")
                return
                
            response_message = ResponseCreate.create()
            await self.websocket.send(response_message)
        except websockets.exceptions.ConnectionClosed as e:
            logger.warning(f"WebSocket connection closed while starting response: {e}")
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
            
            if message_type == "session.created":
                if settings.use_managed_identity:
                    # In agent mode, session.created is enough to proceed
                    await self._start_response()
                
            elif message_type == "session.updated":
                # Set connection ready for both API key and agent modes
                self.connection_ready.set()
                
            elif message_type == "response.audio.delta":
                # Forward audio response to ACS
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
                # Decode base64 audio data from Voice Live (24kHz)
                audio_bytes = base64.b64decode(audio_delta)
                
                # Resample from 24kHz (Voice Live) to 16kHz (ACS)
                resampled_audio = AudioResampler.resample_24k_to_16k(audio_bytes)
                
                # Send entire resampled audio buffer immediately (like .NET implementation)
                # Do NOT chunk with delays - this causes timing issues with ACS
                if len(resampled_audio) > 0:
                    outbound_message = OutboundAudioData.create(resampled_audio, "VoiceLiveAI")
                    
                    # Send to ACS media handler - allow sending even during graceful shutdown
                    if self.media_handler and hasattr(self.media_handler, 'websocket') and self.media_handler.websocket:
                        # Check if WebSocket is still available rather than just the running flag
                        try:
                            await self.media_handler.send_message(outbound_message)
                        except Exception as e:
                            # Only log errors that aren't due to normal connection closure
                            if "1000" not in str(e) and "closed" not in str(e).lower():
                                logger.error(f"Failed to send audio to ACS: {e}")
                    elif self.media_handler:
                        logger.warning("Media handler WebSocket not available - skipping audio send")
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
