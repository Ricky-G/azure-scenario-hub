"""
Azure OpenAI Voice Live API service implementation.
Handles We            logger.info("Voice Live WebSocket connected")
            
            # Start message receiving task
            asyncio.create_task(self._receive_messages())
            
            # Agent mode: Send session update but skip system prompt - instructions are pre-configured in the agent
            await self._update_session()
            await asyncio.sleep(0.2)
            self.running = True
                
            return Trueto Azure OpenAI Voice Live API for real-time audio processing.
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
        Establish WebSocket connection to Azure Voice Live API using managed identity authentication.
        Includes automatic retry on 401 authentication failures.
        
        Returns:
            True if connection successful, False otherwise
        """
        try:
            # Ensure any existing connection is closed first
            if self.websocket and not self.websocket.closed:
                await self.websocket.close()
                
            # Reset connection state for new call
            self.connection_ready.clear()
            self.running = False
            self.client_request_id = str(uuid.uuid4())  # Generate new request ID for each call
            
            # Small delay to prevent rapid reconnection issues
            await asyncio.sleep(0.1)
                
            # Try connecting with current tokens
            return await self._connect_with_retry()
            
        except Exception as e:
            logger.error(f"Failed to connect to Voice Live API: {e}")
            logger.exception("Full connection error details:")
            return False
    
    async def _connect_with_retry(self) -> bool:
        """
        Connect to Voice Live API with automatic 401 retry.
        
        Implements single-retry pattern for token refresh on authentication failures.
        This is essential for production environments where tokens may expire.
        """
        try:
            voice_live_url = settings.get_voice_live_websocket_url()
            headers = settings.get_websocket_headers(self.client_request_id)
            
            logger.info(f"Connecting to Voice Live API using Azure Managed Identity... (Request ID: {self.client_request_id})")
            
            self.websocket = await asyncio.wait_for(
                websockets.connect(
                    voice_live_url,
                    extra_headers=headers,
                    ping_interval=30,
                    ping_timeout=10,
                    close_timeout=10
                ),
                timeout=15  # 15 second connection timeout
            )
            
            logger.info(f"Voice Live WebSocket connected successfully (Request ID: {self.client_request_id})")
            
            # Start message receiving task
            asyncio.create_task(self._receive_messages())
            
            # Agent mode: Send session update but skip system prompt - instructions are pre-configured in the agent
            await self._update_session()
            await asyncio.sleep(0.2)
            self.running = True
                
            return True
            
        except websockets.InvalidStatusCode as e:
            if e.status_code == 401:
                # Authentication failed - refresh tokens and retry once
                logger.warning(f"Voice Live authentication failed (401), refreshing tokens and retrying... (Request ID: {self.client_request_id})")
                
                settings.force_refresh_tokens()
                voice_live_url = settings.get_voice_live_websocket_url()
                headers = settings.get_websocket_headers(self.client_request_id)
                
                self.websocket = await asyncio.wait_for(
                    websockets.connect(
                        voice_live_url,
                        extra_headers=headers,
                        ping_interval=30,
                        ping_timeout=10,
                        close_timeout=10
                    ),
                    timeout=15  # 15 second connection timeout
                )
                
                logger.info(f"Voice Live WebSocket connected after token refresh (Request ID: {self.client_request_id})")
                
                # Start message handling and session setup
                asyncio.create_task(self._receive_messages())
                await self._update_session()
                await asyncio.sleep(0.2)
                self.running = True
                
                return True
            else:
                # Other HTTP errors, don't retry
                logger.error(f"Voice Live connection failed with status {e.status_code}: {e}")
                raise
        except asyncio.TimeoutError:
            logger.error(f"Voice Live connection timed out after 15 seconds (Request ID: {self.client_request_id})")
            raise
        except Exception as e:
            logger.error(f"Unexpected error during Voice Live connection: {e}")
            logger.exception("Full Voice Live connection error:")
            raise
    
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
        """Update Voice Live session configuration for agent mode."""
        try:
            session_update = SessionUpdate.create_default()
            await self.websocket.send(session_update)
            logger.info(f"Session update sent (Request ID: {self.client_request_id})")
        except Exception as e:
            logger.error(f"Error updating session (Request ID: {self.client_request_id}): {e}")
    
    async def _create_conversation(self) -> None:
        """Not needed in agent mode - instructions are pre-configured."""
        return
    
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
                # In agent mode, session.created is enough to proceed
                logger.info(f"Session created - starting AI response (Request ID: {self.client_request_id})")
                await self._start_response()
                
            elif message_type == "session.updated":
                # Set connection ready for agent mode
                logger.info(f"Session updated - connection ready (Request ID: {self.client_request_id})")
                self.connection_ready.set()
                
            elif message_type == "response.audio.delta":
                # Forward audio response to ACS
                logger.info("🎵 Received audio delta from AI - forwarding to caller")
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
                # Log unhandled message types for troubleshooting
                expected_informational = [
                    "response.audio.done", 
                    "response.audio_transcript.done",
                    "response.content_part.done",
                    "response.output_item.done",
                    "response.output_item.added",
                    "response.content_part.added",
                    "response.audio_transcript.delta",
                    "conversation.item.created",
                    "conversation.item.input_audio_transcription.completed",
                    "input_audio_buffer.speech_stopped",
                    "input_audio_buffer.committed"
                ]
                
                if message_type in expected_informational:
                    # These are normal informational messages, log at debug level
                    pass  # Suppress to reduce log noise
                else:
                    logger.info("⚠️  Unhandled message type: %s", message_type)
                
        except Exception as e:
            logger.error(f"Error processing Voice Live message: {e}")
    
    async def _handle_audio_delta(self, data: dict) -> None:
        """
        Handle audio delta from Voice Live API and forward to ACS.
        
        Resamples audio from 24kHz (Voice Live API) to 16kHz (ACS requirement).
        Sends complete audio chunks immediately to avoid timing issues.
        
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
                
                # Send entire resampled audio buffer immediately to avoid timing issues
                if len(resampled_audio) > 0:
                    outbound_message = OutboundAudioData.create(resampled_audio, "VoiceLiveAI")
                    
                    # Send to ACS - check WebSocket availability during graceful shutdown
                    if self.media_handler and hasattr(self.media_handler, 'websocket') and self.media_handler.websocket:
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
