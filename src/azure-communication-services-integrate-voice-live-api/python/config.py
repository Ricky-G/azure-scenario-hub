"""
Configuration settings for Azure Communication Services with Voice Live API
Uses Pydantic Settings for type-safe configuration management
"""
from pydantic_settings import BaseSettings
from typing import Optional
import os


class AppSettings(BaseSettings):
    """Application configuration settings with Azure service credentials."""
    
    # Server configuration
    host: str = "0.0.0.0"
    port: int = 49412  # Same port as .NET implementation
    base_url: Optional[str] = None
    
    # Azure Communication Services configuration
    acs_connection_string: str
    
    # Azure OpenAI Voice Live API configuration
    azure_voice_live_api_key: str
    azure_voice_live_endpoint: str
    voice_live_model: str = "gpt-4o-realtime-preview"
    system_prompt: str = "You are a helpful assistant"
    
    # Logging configuration
    log_level: str = "INFO"
    
    class Config:
        """Pydantic configuration for environment variable loading."""
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False
    def get_websocket_url(self) -> str:
        """Generate WebSocket URL based on base_url configuration."""
        if self.base_url:
            return self.base_url.replace("https://", "wss://").replace("http://", "ws://") + "/ws"
        else:
            return f"ws://{self.host}:{self.port}/ws"
    
    def get_voice_live_websocket_url(self, client_request_id: str) -> str:
        """Generate Azure Voice Live WebSocket URL using API key authentication - matching .NET implementation."""
        
        # Use exact same approach as .NET implementation
        base_url = self.azure_voice_live_endpoint.replace("https://", "wss://").rstrip("/")
        
        # Use voice-agent endpoint matching .NET implementation exactly
        return (f"{base_url}/voice-agent/realtime"
                f"?api-version=2025-05-01-preview"
                f"&x-ms-client-request-id={client_request_id}"
                f"&model={self.voice_live_model}"
                f"&api-key={self.azure_voice_live_api_key}")
    
    def get_auth_headers(self) -> dict:
        """Get authentication headers for HTTP requests to Azure services."""
        return {
            "api-key": self.azure_voice_live_api_key,
            "Content-Type": "application/json"
        }


# Global settings instance
settings = AppSettings()
