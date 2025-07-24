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
    
    # TODO: Azure Managed Identity / Token Credential authentication (future enhancement)
    # use_managed_identity: bool = False  # Flag to switch between API key and managed identity
    # agent_id: Optional[str] = None  # For agent-based authentication
    # agent_project_name: Optional[str] = None  # For agent project authentication
    
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
        
        base_url = self.azure_voice_live_endpoint.replace("https://", "wss://").rstrip("/")
        
        # TODO: Add Azure Managed Identity token-based authentication support (future enhancement)
        # This is the centralized place to implement Azure token credential flow
        # When implementing managed identity authentication:
        # 1. Check self.use_managed_identity flag
        # 2. If managed identity: 
        #    - Initialize: self.azure_async_token_credential = DefaultAzureCredential()
        #    - Get tokens: cognitive_services_token = self.azure_async_token_credential.get_token("https://cognitiveservices.azure.com/.default")
        #    - Get AI token: azure_ai_token = self.azure_async_token_credential.get_token("https://ai.azure.com/.default")
        # 3. Build URL with tokens instead of api-key:
        #    - For agent-based: add agent_id and agent_access_token parameters
        #    - For standard: use Authorization header with bearer token
        # 4. Handle token refresh logic and caching
        
        # Current implementation: API key authentication
        # Use voice-agent endpoint matching .NET implementation exactly
        return (f"{base_url}/voice-agent/realtime"
                f"?api-version=2025-05-01-preview"
                f"&x-ms-client-request-id={client_request_id}"
                f"&model={self.voice_live_model}"
                f"&api-key={self.azure_voice_live_api_key}")
    
    # TODO: Add Azure Managed Identity token management methods (future enhancement)
    # async def get_azure_tokens(self) -> tuple[str, str]:
    #     """Fetch Azure Cognitive Services and AI tokens using DefaultAzureCredential."""
    #     # from azure.identity.aio import DefaultAzureCredential
    #     # self.azure_async_token_credential = DefaultAzureCredential()
    #     # cognitive_services_token = await self.azure_async_token_credential.get_token("https://cognitiveservices.azure.com/.default")
    #     # azure_ai_token = await self.azure_async_token_credential.get_token("https://ai.azure.com/.default")
    #     # return cognitive_services_token.token, azure_ai_token.token
    #     pass
    #
    # async def refresh_tokens_if_needed(self) -> tuple[str, str]:
    #     """Check token expiry and refresh if needed."""
    #     # Implement token refresh logic for both cognitive services and AI tokens
    #     pass
    
    def get_auth_headers(self) -> dict:
        """Get authentication headers for HTTP requests to Azure services."""
        # TODO: Extend for Azure Managed Identity token-based authentication (future enhancement)
        # When implementing managed identity, check self.use_managed_identity flag and return appropriate headers:
        # if self.use_managed_identity:
        #     cognitive_token, ai_token = await self.get_azure_tokens()
        #     return {
        #         "Authorization": f"Bearer {cognitive_token}",
        #         "Content-Type": "application/json"
        #     }
        # else:
        #     return current API key headers
        
        # Current implementation: API key authentication
        return {
            "api-key": self.azure_voice_live_api_key,
            "Content-Type": "application/json"
        }


# Global settings instance
settings = AppSettings()
