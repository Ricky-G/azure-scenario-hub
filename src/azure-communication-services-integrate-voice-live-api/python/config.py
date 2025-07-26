"""
Configuration settings for Azure Communication Services with Voice Live API
Uses Azure Managed Identity for authentication
"""
from pydantic_settings import BaseSettings
from typing import Optional
import logging
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)


class AppSettings(BaseSettings):
    """Application configuration settings with Azure service credentials."""
    
    # Server configuration
    host: str = "0.0.0.0"
    port: int = 49412
    base_url: Optional[str] = None
    
    # Azure Communication Services configuration
    acs_connection_string: str
    
    # Azure OpenAI Voice Live API configuration
    azure_voice_live_endpoint: str
    voice_live_model: str = "gpt-4o-realtime-preview"
    
    # Azure Managed Identity configuration
    agent_id: str
    agent_project_name: str
    
    # Azure Token Scopes configuration
    azure_cognitive_services_scope: str = "https://cognitiveservices.azure.com/.default"
    azure_ai_scope: str = "https://ai.azure.com/.default"
    
    # Token storage (populated at runtime)
    _cognitive_services_token: Optional[str] = None
    _azure_ai_token: Optional[str] = None
    _azure_credential: Optional[DefaultAzureCredential] = None
    _token_expires_at: Optional[float] = None  # Timestamp when tokens expire
    
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
    
    def get_azure_tokens(self) -> tuple[str, str]:
        """
        Fetch Azure Cognitive Services and AI tokens using DefaultAzureCredential with caching.
        
        Uses lock-free caching with expiration timestamps for high-concurrency scenarios.
        Token caching is safe since tokens are service-level, not user-specific.
        """
        import time
        
        # Check if we have valid cached tokens (with 5-minute safety buffer)
        current_time = time.time()
        if (self._cognitive_services_token and self._azure_ai_token and 
            self._token_expires_at and current_time < self._token_expires_at):
            return self._cognitive_services_token, self._azure_ai_token
        
        # Cache miss or expired - fetch fresh tokens
        logger.info("Fetching fresh Azure tokens")
        
        if not self._azure_credential:
            self._azure_credential = DefaultAzureCredential()
        
        # Get both tokens for agent authentication
        cognitive_services_token = self._azure_credential.get_token(self.azure_cognitive_services_scope)
        azure_ai_token = self._azure_credential.get_token(self.azure_ai_scope)
        
        # Cache tokens with 5-minute safety buffer (tokens usually expire in 60 minutes)
        safety_buffer_seconds = 5 * 60  # 5 minutes
        expires_in = min(cognitive_services_token.expires_on, azure_ai_token.expires_on)
        
        self._cognitive_services_token = cognitive_services_token.token
        self._azure_ai_token = azure_ai_token.token
        self._token_expires_at = expires_in - safety_buffer_seconds
        
        logger.info("Tokens cached, expires at: %s", time.ctime(self._token_expires_at))
        return self._cognitive_services_token, self._azure_ai_token
    
    def force_refresh_tokens(self) -> tuple[str, str]:
        """Force refresh of tokens, bypassing cache. Used for 401 retry scenarios."""
        logger.warning("Forcing token refresh due to authentication failure")
        
        # Clear cache to force fresh fetch
        self._cognitive_services_token = None
        self._azure_ai_token = None
        self._token_expires_at = None
        
        # Fetch fresh tokens
        return self.get_azure_tokens()
    
    def get_voice_live_websocket_url(self) -> str:
        """Generate Azure Voice Live WebSocket URL with agent-based authentication."""
        base_url = self.azure_voice_live_endpoint.replace("https://", "wss://").rstrip("/")
        
        # Always use Azure Managed Identity token-based authentication with agent
        _, ai_token = self.get_azure_tokens()
        
        return (f"{base_url}/voice-agent/realtime"
                f"?api-version=2025-05-01-preview"
                f"&agent_id={self.agent_id}"
                f"&agent-project-name={self.agent_project_name}"
                f"&agent_access_token={ai_token}")
    
    def get_websocket_headers(self, client_request_id: str) -> dict:
        """Get WebSocket connection headers with authentication."""
        # Use cognitive services token for Authorization header
        cognitive_token, _ = self.get_azure_tokens()
        return {
            "Authorization": f"Bearer {cognitive_token}",
            "x-ms-client-request-id": client_request_id
        }
    
    def get_auth_headers(self) -> dict:
        """Get authentication headers for HTTP requests to Azure services."""
        # Use cognitive services token for HTTP requests
        cognitive_token, _ = self.get_azure_tokens()
        return {
            "Authorization": f"Bearer {cognitive_token}",
            "Content-Type": "application/json"
        }


# Global settings instance
settings = AppSettings()
