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
            logger.info(f"Received AudioMetadata - Sample Rate: {metadata.sample_rate}, "
                       f"Encoding: {metadata.encoding}, "
                       f"Channels: {metadata.channels}, Length: {metadata.length}")
            
            # Log audio format information for debugging
            if metadata.sample_rate:
                sample_rate = metadata.sample_rate
                logger.info(f"ACS audio stream configuration: {sample_rate}Hz sample rate, "
                          f"{metadata.channels} channel(s), {metadata.encoding} encoding")
                
                # Validate that we're receiving expected format
                if sample_rate not in [16000, 24000]:
                    logger.warning(f"Unexpected sample rate: {sample_rate}")
            
            # Send immediate audio response to prevent Teams timeout
            # For Teams calls, we need to handle the external number security prompt
            await self._send_immediate_audio_response(metadata.sample_rate)
            
            # Also send a Teams external call confirmation
            await self._send_teams_external_call_response(metadata.sample_rate)
                
        except Exception as e:
            logger.error(f"Error handling metadata: {e}")
    
    async def _send_immediate_audio_response(self, sample_rate: int = 16000) -> None:
        """
        Send immediate audio to prevent Teams from timing out while Voice Live connects.
        Teams requires actual audible content for proper audio path establishment.
        
        Args:
            sample_rate: The sample rate to use for audio generation (from AudioMetadata)
        """
        try:
            import base64
            from models import OutboundAudioData
            
            # Generate 1 second of clear audio content that Teams can recognize
            # This is critical for Teams interoperability - Teams needs to hear actual content
            duration_seconds = 1
            total_samples = sample_rate * duration_seconds
            
            # Generate a brief "Hello" audio pattern that sounds natural to Teams
            # Use multiple tones to create a recognizable audio pattern
            audio_samples = []
            for i in range(total_samples):
                # Create a gentle multi-tone audio pattern that sounds like the beginning of speech
                time_ratio = i / sample_rate
                
                if time_ratio < 0.1:  # First 100ms: rising tone (like beginning of "Hello")
                    frequency = 300 + (time_ratio * 2000)  # 300Hz to 500Hz
                    amplitude = int(1000 * time_ratio * 10)  # Fade in
                    sample = int(amplitude * math.sin(2 * math.pi * frequency * time_ratio))
                elif time_ratio < 0.3:  # Next 200ms: sustained tone
                    frequency = 400
                    amplitude = 800
                    sample = int(amplitude * math.sin(2 * math.pi * frequency * time_ratio))
                elif time_ratio < 0.5:  # Next 200ms: different tone (like "lo")
                    frequency = 350
                    amplitude = int(800 * (1 - (time_ratio - 0.3) * 2))  # Fade out
                    sample = int(amplitude * math.sin(2 * math.pi * frequency * time_ratio))
                else:  # Remaining time: silence
                    sample = 0
                
                # Convert to 16-bit signed integer
                audio_samples.append(sample.to_bytes(2, byteorder='little', signed=True))
            
            # Combine all samples
            audio_bytes = b''.join(audio_samples)
            
            # Create audio message using the proper ACS format
            audio_message = OutboundAudioData.create(audio_bytes, "TeamsAudioPath")
            
            # Send the audio message
            await self.send_message(audio_message)
            logger.info(f"Sent Teams-compatible audio response ({sample_rate}Hz, {len(audio_bytes)} bytes) to establish audio path")
            
        except Exception as e:
            logger.warning(f"Could not send immediate audio response: {e}")
            # Continue anyway - this is just to prevent timeout
    
    async def _send_teams_external_call_response(self, sample_rate: int = 16000) -> None:
        """
        Send "OK" response for Teams external call security prompt.
        Teams prompts: "You're calling an external number. Say 'OK' or press 1 to join."
        
        Args:
            sample_rate: The sample rate to use for audio generation
        """
        try:
            import base64
            from models import OutboundAudioData
            
            # Generate clear "OK" audio response for Teams
            # This needs to be loud and clear enough for Teams to recognize
            duration_seconds = 0.5  # Short and quick response
            total_samples = sample_rate * duration_seconds
            
            # Generate "OK" audio pattern (O-sound followed by K-sound)
            audio_samples = []
            for i in range(total_samples):
                time_ratio = i / sample_rate
                
                if time_ratio < 0.25:  # First quarter: "O" sound (low frequency vowel)
                    frequency = 200  # Deep "O" sound
                    amplitude = 2000  # Loud enough for Teams to detect
                    sample = int(amplitude * math.sin(2 * math.pi * frequency * time_ratio))
                else:  # Second quarter: "K" sound (higher frequency stop)
                    frequency = 1000  # Sharp "K" sound
                    amplitude = int(2000 * (1 - (time_ratio - 0.25) * 4))  # Quick fade
                    sample = int(amplitude * math.sin(2 * math.pi * frequency * time_ratio))
                
                # Convert to 16-bit signed integer
                audio_samples.append(sample.to_bytes(2, byteorder='little', signed=True))
            
            # Combine all samples
            audio_bytes = b''.join(audio_samples)
            
            # Create audio message
            audio_message = OutboundAudioData.create(audio_bytes, "TeamsOKResponse")
            
            # Send with a slight delay to ensure it comes after the prompt
            await asyncio.sleep(0.5)  # Wait for Teams prompt to finish
            await self.send_message(audio_message)
            logger.info(f"Sent Teams 'OK' response ({sample_rate}Hz, {len(audio_bytes)} bytes) for external call prompt")
            
            # Also try sending DTMF "1" as backup (Teams accepts either OK or pressing 1)
            await self._send_dtmf_response()
            
        except Exception as e:
            logger.warning(f"Could not send Teams OK response: {e}")
            # Continue anyway - this is just for Teams external call handling
    
    async def _send_dtmf_response(self) -> None:
        """Send DTMF '1' tone as alternative to saying 'OK' for Teams external call prompt."""
        try:
            # DTMF '1' tone: 697 Hz + 1209 Hz combined
            sample_rate = 16000
            duration_seconds = 0.3  # Short DTMF burst
            total_samples = sample_rate * duration_seconds
            
            audio_samples = []
            for i in range(total_samples):
                time_ratio = i / sample_rate
                
                # DTMF '1' = 697 Hz (row) + 1209 Hz (column)
                sample1 = math.sin(2 * math.pi * 697 * time_ratio)
                sample2 = math.sin(2 * math.pi * 1209 * time_ratio)
                combined_sample = int(1500 * (sample1 + sample2) / 2)  # Combine and amplify
                
                audio_samples.append(combined_sample.to_bytes(2, byteorder='little', signed=True))
            
            audio_bytes = b''.join(audio_samples)
            
            from models import OutboundAudioData
            dtmf_message = OutboundAudioData.create(audio_bytes, "TeamsDTMF1")
            
            await asyncio.sleep(0.2)  # Small gap between OK and DTMF
            await self.send_message(dtmf_message)
            logger.info(f"Sent Teams DTMF '1' tone ({len(audio_bytes)} bytes) as backup response")
            
        except Exception as e:
            logger.warning(f"Could not send DTMF response: {e}")
    
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
