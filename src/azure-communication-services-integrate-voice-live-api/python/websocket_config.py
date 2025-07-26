"""
WebSocket configuration utilities for FastAPI application.
Provides CORS and WebSocket-specific configurations.
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

logger = logging.getLogger(__name__)


def configure_websockets(app: FastAPI) -> None:
    """
    Configure WebSocket settings for the FastAPI application.
    
    Args:
        app: FastAPI application instance
    """
    # Add CORS middleware for WebSocket connections
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # Configure appropriately for production
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    logger.info("WebSocket configuration applied")


class WebSocketManager:
    """
    Manager class for WebSocket connections.
    Handles connection lifecycle and message routing.
    """
    
    def __init__(self):
        """Initialize WebSocket manager."""
        self.active_connections = set()
    
    async def connect(self, websocket) -> None:
        """
        Accept and register a new WebSocket connection.
        
        Args:
            websocket: WebSocket connection to register
        """
        await websocket.accept()
        self.active_connections.add(websocket)
        logger.info(f"WebSocket connected. Total connections: {len(self.active_connections)}")
    
    def disconnect(self, websocket) -> None:
        """
        Unregister a WebSocket connection.
        
        Args:
            websocket: WebSocket connection to unregister
        """
        self.active_connections.discard(websocket)
        logger.info(f"WebSocket disconnected. Total connections: {len(self.active_connections)}")
    
    async def send_personal_message(self, message: str, websocket) -> None:
        """
        Send a message to a specific WebSocket connection.
        
        Args:
            message: Message to send
            websocket: Target WebSocket connection
        """
        try:
            await websocket.send_text(message)
        except Exception as e:
            logger.error(f"Error sending message to WebSocket: {e}")
            self.disconnect(websocket)
    
    async def broadcast(self, message: str) -> None:
        """
        Broadcast a message to all active WebSocket connections.
        
        Args:
            message: Message to broadcast
        """
        disconnected = set()
        
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except Exception as e:
                logger.error(f"Error broadcasting to WebSocket: {e}")
                disconnected.add(connection)
        
        # Remove disconnected connections
        for connection in disconnected:
            self.disconnect(connection)


# Global WebSocket manager instance
websocket_manager = WebSocketManager()
