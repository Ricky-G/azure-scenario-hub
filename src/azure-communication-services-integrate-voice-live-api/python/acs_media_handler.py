"""
Azure Communication Services Media Streaming Handler.
Manages WebSocket connection from ACS and forwards audio to Voice Live API.
"""
import asyncio
import json
import logging
import math
from typing import Optional
import websockets
from websockets.exceptions import ConnectionClosed, WebSocketException

from models import StreamingDataParser, AudioData, AudioMetadata
from azure_voice_live_service import AzureVoiceLiveService
from audio_resampler import AudioResampler

logger = logging.getLogger(__name__)


class ACSMediaStreamingHandler:
    """
    Handler for Azure Communication Services media streaming WebSocket.
    Processes incoming audio data and forwards to Azure Voice Live API.
    """
    
    def __init__(self, websocket: websockets.WebSocketServerProtocol):
        """
        Initialize ACS media streaming handler.
        
        Args:
            websocket: WebSocket connection from ACS
        """
        self.websocket = websocket
        self.voice_live_service: Optional[AzureVoiceLiveService] = None
        self.running = False
        self.audio_buffer = bytearray()
        self.cleanup_started = False
        self.last_heartbeat = asyncio.get_event_loop().time()
        self.heartbeat_task = None
        
        logger.info("ACS Media Streaming Handler initialized")
    
    async def process_websocket(self) -> None:
        """
        Main processing loop for ACS WebSocket connection.
        Initializes Voice Live service and processes audio data.
        """
        if not self.websocket:
            logger.error("WebSocket connection is None")
            return
        
        try:
            logger.info("ACS WebSocket connected successfully. Initializing Voice Live connection...")
            
            # Initialize Voice Live service
            self.voice_live_service = AzureVoiceLiveService(self)
            
            # Start heartbeat monitoring early to maintain connection
            self.heartbeat_task = asyncio.create_task(self._heartbeat_monitor())
            
            # Start processing ACS media stream immediately to receive metadata and establish flow
            receive_task = asyncio.create_task(self._start_receiving_from_acs())
            
            # Connect to Voice Live API in parallel
            connect_task = asyncio.create_task(self._initialize_voice_live())
            
            # Wait for both tasks to complete or either to fail
            done, pending = await asyncio.wait(
                [receive_task, connect_task],
                return_when=asyncio.FIRST_EXCEPTION
            )
            
            # Cancel any remaining tasks
            for task in pending:
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
            
            # Check if any task raised an exception
            for task in done:
                if task.exception():
                    raise task.exception()
            
        except Exception as e:
            logger.error(f"Error in process_websocket: {e}")
            logger.exception("Full exception details:")
        finally:
            await self._cleanup()
    
    async def _initialize_voice_live(self) -> None:
        """Initialize Voice Live connection."""
        try:
            # Connect to Voice Live API
            if not await self.voice_live_service.connect():
                logger.error("Failed to connect to Voice Live API")
                return
            
            # Wait for Voice Live to be ready
            await self.voice_live_service.wait_for_connection()
            logger.info("Voice Live connection established. Stopping holding message and starting AI processing...")
            
            # Send stop audio command to interrupt any playing holding message
            try:
                from models import StopAudioData
                stop_message = StopAudioData.create()
                await self.send_message(stop_message)
                logger.info("Sent stop command to interrupt holding message")
            except Exception as stop_error:
                logger.warning(f"Could not send stop command: {stop_error}")
            
        except Exception as e:
            logger.error(f"Error initializing Voice Live: {e}")
            raise
    
    async def send_message(self, message: str) -> None:
        """
        Send message back to ACS WebSocket.
        
        Args:
            message: JSON message to send to ACS
        """
        # Allow sending as long as WebSocket exists and cleanup hasn't started
        # Don't require 'running' flag to be True since AI responses may come during graceful shutdown
        if self.websocket and not self.cleanup_started:
            try:
                await self.websocket.send_text(message)
                logger.debug(f"Message sent to ACS successfully ({len(message)} chars)")
            except ConnectionClosed as e:
                logger.warning(f"WebSocket connection closed during send: {e}")
                # Don't immediately stop - let the receive loop handle the disconnection
            except WebSocketException as e:
                logger.error(f"WebSocket error during send: {e}")
                # For WebSocket-specific errors, we might want to stop
                if "1006" in str(e) or "1001" in str(e):
                    self.running = False
            except Exception as e:
                if not self.cleanup_started:
                    logger.error(f"Error sending message to ACS: {e}")
                    # Only stop for severe errors, not transient ones
                    if "broken pipe" in str(e).lower() or "connection reset" in str(e).lower():
                        self.running = False
        else:
            if self.cleanup_started:
                logger.debug("Cannot send message - cleanup in progress")
            else:
                logger.warning("Cannot send message - ACS WebSocket not available")
    
    async def close(self) -> None:
        """Close all connections and cleanup resources."""
        if not self.cleanup_started:
            logger.info("Closing ACS Media Streaming Handler")
            await self._cleanup()
        else:
            logger.debug("Close called but cleanup already in progress")
    
    async def _start_receiving_from_acs(self) -> None:
        """
        Start receiving messages from ACS WebSocket.
        Processes audio data and metadata messages.
        """
        self.running = True
        
        try:
            while self.running:
                try:
                    # Receive message from FastAPI WebSocket
                    message = await self.websocket.receive()
                    # Update heartbeat timestamp on any received message
                    self.last_heartbeat = asyncio.get_event_loop().time()
                    await self._process_acs_message(message)
                    
                    # Check if we should stop after processing the message
                    if not self.running:
                        logger.info("Stopping receive loop - running flag set to False")
                        break
                        
                except ConnectionClosed:
                    logger.info("ACS WebSocket connection closed normally")
                    break
                except RuntimeError as e:
                    if "Cannot call" in str(e) and "disconnect message" in str(e):
                        logger.info("ACS WebSocket disconnected - cannot receive further messages")
                        break
                    else:
                        logger.error(f"Runtime error in WebSocket receive: {e}")
                        break
                except Exception as e:
                    logger.error(f"Error receiving WebSocket message: {e}")
                    break
                    
        except Exception as e:
            logger.error(f"Error receiving from ACS: {e}")
            logger.exception("Full exception details:")
        finally:
            self.running = False
            logger.info("ACS WebSocket receive loop terminated")
    
    async def _process_acs_message(self, message: dict) -> None:
        """
        Process incoming message from ACS media streaming.
        
        Args:
            message: FastAPI WebSocket message containing audio data or metadata
        """
        try:
            # Extract the actual message content from FastAPI WebSocket message
            if isinstance(message, dict):
                if "text" in message:
                    # Text message - parse JSON
                    message_content = json.loads(message["text"])
                    logger.debug(f"Received text message: {json.dumps(message_content, indent=2)}")
                elif "bytes" in message:
                    # Binary message - handle raw audio data
                    message_content = message["bytes"]
                    logger.debug(f"Received bytes message: {len(message_content)} bytes")
                elif "type" in message and "code" in message:
                    # WebSocket disconnect/close message - this is normal termination
                    message_type = message.get("type")
                    if message_type == "websocket.disconnect":
                        logger.info(f"WebSocket disconnect message received: {message}")
                        # Set running to False to gracefully terminate the receive loop
                        self.running = False
                        return
                    else:
                        logger.warning(f"Unknown WebSocket control message: {message}")
                        return
                else:
                    logger.warning(f"Unknown WebSocket message format: {list(message.keys())}")
                    return
            else:
                message_content = message
                logger.debug(f"Received direct message: {type(message_content)}")
            
            # Parse the streaming data
            streaming_data = StreamingDataParser.parse(message_content)
            logger.debug(f"Parsed streaming data type: {type(streaming_data)}")
            
            if isinstance(streaming_data, AudioData):
                await self._handle_audio_data(streaming_data)
            elif isinstance(streaming_data, AudioMetadata):
                logger.info("Processing AudioMetadata - will send immediate audio response")
                await self._handle_metadata(streaming_data)
            else:
                logger.debug(f"Received unknown streaming data type: {type(streaming_data)}")
                
        except Exception as e:
            logger.error(f"Error processing ACS message: {e}")
            logger.debug("Full exception details:", exc_info=True)
    
    async def _handle_audio_data(self, audio_data: AudioData) -> None:
        """
        Handle audio data from ACS and forward to Voice Live API.
        
        Args:
            audio_data: Parsed audio data from ACS
        """
        try:
            if not audio_data.is_silent:
                audio_bytes = audio_data.to_bytes()
                if audio_bytes:
                    # Only log periodically to avoid spam
                    if hasattr(self, '_audio_count'):
                        self._audio_count += 1
                    else:
                        self._audio_count = 1
                        
                    if self._audio_count % 100 == 0:  # Log every 100th audio packet
                        logger.info(f"Processing audio packets: {self._audio_count} total, current: {len(audio_bytes)} bytes, timestamp: {audio_data.get_timestamp_ms()}")
                    
                    # Forward audio to Voice Live API with proper resampling
                    if self.voice_live_service:
                        # Resample from 16kHz (ACS) to 24kHz (Voice Live API)
                        resampled_audio = AudioResampler.resample_16k_to_24k(audio_bytes)
                        await self.voice_live_service.send_audio(resampled_audio)
                else:
                    # Only warn periodically about conversion issues
                    if not hasattr(self, '_conversion_warning_shown'):
                        logger.warning("Audio data conversion failed - empty bytes (further warnings suppressed)")
                        self._conversion_warning_shown = True
            # Remove silent audio logging to reduce noise
                
        except Exception as e:
            logger.error(f"Error handling audio data: {e}")
    
    async def _handle_metadata(self, metadata: AudioMetadata) -> None:
        """
        Handle AudioMetadata from ACS media streaming.
        
        Args:
            metadata: Parsed AudioMetadata from ACS
        """
        try:
            # Log basic metadata information
            logger.info(f"AudioMetadata received - Sample Rate: {metadata.sample_rate}Hz, "
                       f"Channels: {metadata.channels}, Encoding: {metadata.encoding}")
                
        except Exception as e:
            logger.error(f"Error handling metadata: {e}")
    
    
    async def _cleanup(self) -> None:
        """Cleanup resources and close connections."""
        if self.cleanup_started:
            logger.debug("Cleanup already in progress, skipping duplicate cleanup")
            return
            
        self.cleanup_started = True
        self.running = False
        
        try:
            # Cancel heartbeat task
            if self.heartbeat_task:
                self.heartbeat_task.cancel()
                try:
                    await self.heartbeat_task
                except asyncio.CancelledError:
                    pass
            
            # Close Voice Live service
            if self.voice_live_service:
                await self.voice_live_service.close()
                self.voice_live_service = None
            
            # Close ACS WebSocket if still open (FastAPI WebSocket doesn't have closed attribute)
            if self.websocket:
                try:
                    await self.websocket.close()
                except Exception as close_error:
                    logger.debug(f"WebSocket already closed or error closing: {close_error}")
                
        except Exception as e:
            logger.error(f"Error during cleanup: {e}")
        
        logger.info("ACS Media Streaming Handler cleanup completed")
    
    async def _heartbeat_monitor(self) -> None:
        """Monitor connection health and send periodic heartbeats."""
        try:
            heartbeat_count = 0
            while self.running and not self.cleanup_started:
                # Send periodic keep-alive messages every 5 seconds
                try:
                    heartbeat_count += 1
                    keep_alive_message = {
                        "kind": "connectivityCheck",
                        "sequenceNumber": heartbeat_count,
                        "timestamp": int(asyncio.get_event_loop().time() * 1000)
                    }
                    await self.websocket.send_text(json.dumps(keep_alive_message))
                    logger.debug(f"Sent WebSocket keep-alive #{heartbeat_count}")
                    self.last_heartbeat = asyncio.get_event_loop().time()
                except Exception as e:
                    logger.warning(f"Failed to send keep-alive: {e}")
                    # Don't immediately fail - the receive loop will handle disconnections
                
                # Sleep for 5 seconds before next heartbeat
                await asyncio.sleep(5)
                
        except asyncio.CancelledError:
            logger.debug("Heartbeat monitor cancelled")
        except Exception as e:
            logger.error(f"Error in heartbeat monitor: {e}")
    
    def __del__(self):
        """Destructor to ensure cleanup on object deletion."""
        if self.running:
            logger.warning("ACSMediaStreamingHandler deleted without proper cleanup")
            # Note: Cannot call async cleanup from __del__, logging warning only
