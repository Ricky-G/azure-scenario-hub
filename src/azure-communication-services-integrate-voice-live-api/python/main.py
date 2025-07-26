"""
Main FastAPI application for Azure Communication Services with Voice Live API integration.
Equivalent to the .NET Program.cs implementation.
"""
import asyncio
import json
import logging
import uuid
from datetime import datetime
from typing import List, Dict, Any, Optional

import uvicorn
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect, HTTPException, Query
from fastapi.responses import JSONResponse
from websockets.exceptions import ConnectionClosed
from azure.eventgrid import EventGridEvent, SystemEventNames
from azure.communication.callautomation import (
    CallAutomationClient,
    MediaStreamingOptions,
    MediaStreamingAudioChannelType,
    MediaStreamingContentType,
    StreamingTransportType,
    AudioFormat
)
from azure.identity import DefaultAzureCredential

from config import settings
from helpers import ACSHelper, URLHelper
from acs_media_handler import ACSMediaStreamingHandler
from models import StreamingDataParser

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.log_level.upper()),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Reduce Azure SDK logging verbosity
logging.getLogger('azure.core.pipeline.policies.http_logging_policy').setLevel(logging.WARNING)
logging.getLogger('azure.identity').setLevel(logging.WARNING)
logging.getLogger('azure.identity._credentials').setLevel(logging.WARNING)
logging.getLogger('azure.identity._internal').setLevel(logging.WARNING)
logging.getLogger('azure.identity._credentials.chained').setLevel(logging.WARNING)
logging.getLogger('azure.identity._credentials.managed_identity').setLevel(logging.WARNING)
logging.getLogger('azure.identity._credentials.environment').setLevel(logging.WARNING)
logging.getLogger('azure.identity._credentials.default').setLevel(logging.WARNING)

# Only show important Azure authentication events
logging.getLogger('azure.identity._credentials.chained').setLevel(logging.INFO)  # Token acquisition only

# FastAPI application instance
app = FastAPI(
    title="Azure Communication Services with Voice Live API",
    description="Python implementation of ACS Call Automation with Azure OpenAI Voice Live API",
    version="1.0.0"
)

# Initialize ACS Call Automation client
try:
    call_automation_client = CallAutomationClient.from_connection_string(
        settings.acs_connection_string
    )
    logger.info("Azure Communication Services client initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize ACS client: {e}")
    raise


@app.on_event("startup")
async def startup_event():
    """Application startup event handler."""
    logger.info("Azure Communication Services Voice Live API service started")


@app.on_event("shutdown")
async def shutdown_event():
    """Application shutdown event handler."""
    logger.info("Azure Communication Services Voice Live API service shutting down")


@app.get("/")
async def root():
    """Root endpoint for health check."""
    return {"message": "Hello ACS CallAutomation with Voice Live API!"}


@app.get("/health")
async def health_check():
    """Health check endpoint for debugging and monitoring."""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "ACS Voice Live API",
        "version": "1.0.0"
    }


@app.get("/test-ws")
async def websocket_test(websocket: WebSocket):
    """WebSocket test endpoint for debugging connections."""
    await websocket.accept()
    
    try:
        # Send test message
        await websocket.send_text("WebSocket connection successful!")
        
        # Echo messages back
        while True:
            message = await websocket.receive_text()
            await websocket.send_text(f"Echo: {message}")
            
    except WebSocketDisconnect:
        logger.info("WebSocket test connection closed")
    except Exception as e:
        logger.error(f"WebSocket test error: {e}")


@app.post("/api/incomingCall")
async def handle_incoming_call(request: Request):
    """
    Handle incoming call events from Azure Event Grid.
    Processes Event Grid events and initiates call automation.
    
    Args:
        request: HTTP request containing Event Grid events
        
    Returns:
        JSON response for Event Grid
    """
    try:
        # Parse Event Grid events
        body = await request.body()
        events = []
        
        try:
            import json
            event_data = json.loads(body.decode('utf-8'))
            
            # Handle both single event and array of events
            if isinstance(event_data, list):
                events = event_data
            else:
                events = [event_data]
                
        except Exception as e:
            logger.error(f"Error parsing Event Grid events: {e}")
            raise HTTPException(status_code=400, detail="Invalid Event Grid event format")
        
        logger.info("Incoming call event received")
        
        for event in events:
            # Handle Event Grid subscription validation
            validation_code = ACSHelper.validate_subscription_event(event)
            if validation_code:
                logger.info("Event Grid subscription validation event received")
                return {"validationResponse": validation_code}
            
            # Process incoming call event
            await _process_incoming_call_event(event)
        
        return {"status": "success"}
        
    except Exception as e:
        logger.error(f"Error handling incoming call: {e}")
        logger.exception("Full exception details:")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/callbacks/{context_id}")
async def handle_callback_events(
    context_id: str,
    request: Request,
    callerId: str = Query(...)
):
    """
    Handle callback events from Azure Communication Services.
    
    Args:
        context_id: Unique context identifier
        request: HTTP request containing call automation events
        callerId: Caller identifier from query parameters
        
    Returns:
        JSON response confirming event processing
    """
    try:
        body = await request.body()
        events = json.loads(body.decode('utf-8'))
        
        logger.info(f"Callback event received for context: {context_id}, caller: {callerId}")
        
        # Process each event
        for event in events:
            # Handle specific event types if needed
            event_type = event.get('type', '')
            if event_type:
                logger.info(f"Processing event type: {event_type}")
        
        return {"status": "success"}
        
    except Exception as e:
        logger.error(f"Error handling callback events: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket endpoint for Azure Communication Services media streaming.
    Accepts WebSocket connections from ACS and processes audio data.
    
    Args:
        websocket: WebSocket connection from ACS
    """
    # Accept the WebSocket connection with custom keep-alive settings
    await websocket.accept()
    
    media_handler = None
    
    try:
        logger.info("ACS WebSocket connection accepted")
        
        # Create media streaming handler
        media_handler = ACSMediaStreamingHandler(websocket)
        
        # Process WebSocket messages
        await media_handler.process_websocket()
        
    except WebSocketDisconnect as e:
        logger.info(f"ACS WebSocket connection closed by client: {e}")
    except ConnectionClosed as e:
        logger.info(f"ACS WebSocket connection closed: {e}")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        logger.exception("Full exception details:")
    finally:
        # Ensure cleanup happens even if media_handler wasn't created
        if media_handler:
            try:
                await media_handler.close()
            except Exception as cleanup_error:
                logger.error(f"Error during handler cleanup: {cleanup_error}")
        logger.info("WebSocket connection cleanup completed")


async def _process_incoming_call_event(event: Dict[str, Any]) -> None:
    """
    Process incoming call event and initiate call automation.
    
    Args:
        event: Event Grid event data
    """
    try:
        # Extract call information
        event_data = event.get('data', {})
        json_object = ACSHelper.get_json_object(event_data)
        
        caller_id = ACSHelper.get_caller_id(json_object)
        incoming_call_context = ACSHelper.get_incoming_call_context(json_object)
        
        if not caller_id or not incoming_call_context:
            logger.error("Missing required call information")
            return
        
        logger.info(f"Processing call from: {caller_id}")
        
        # Generate callback URL
        context_id = str(uuid.uuid4())
        base_url = settings.base_url or f"https://{settings.host}:{settings.port}"
        callback_url = URLHelper.create_callback_url(base_url, context_id, caller_id)
        websocket_url = URLHelper.create_websocket_url(base_url)
        
        # Configure media streaming options
        media_streaming_options = MediaStreamingOptions(
            transport_url=websocket_url,
            transport_type=StreamingTransportType.WEBSOCKET,
            content_type=MediaStreamingContentType.AUDIO,
            audio_channel_type=MediaStreamingAudioChannelType.MIXED,
            start_media_streaming=True,
            enable_bidirectional=True,
            audio_format=AudioFormat.PCM16_K_MONO
        )
        
        # Answer the call immediately with a holding message while Voice Live connects
        answer_result = call_automation_client.answer_call(
            incoming_call_context=incoming_call_context,
            callback_url=callback_url,
            media_streaming=media_streaming_options
        )
        logger.info(f"Call answered successfully - Connection ID: {answer_result.call_connection_id}")
        logger.info("Call answered - Voice Live will connect shortly and begin AI conversation")
        
    except Exception as e:
        logger.error(f"Error processing incoming call event: {e}")
        logger.exception("Full exception details:")


if __name__ == "__main__":
    """
    Main entry point for running the application.
    Starts the FastAPI server with uvicorn.
    """
    logger.info("Starting Azure Communication Services Voice Live API service")
    
    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        log_level=settings.log_level.lower(),
        reload=False,  # Set to True for development
        access_log=True
    )
