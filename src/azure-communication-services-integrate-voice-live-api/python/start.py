#!/usr/bin/env python3
"""
Startup script for Azure Communication Services with Voice Live API service.
Handles environment setup and service initialization.
"""
import os
import sys
import logging
import subprocess
from pathlib import Path

# Add the current directory to Python path
current_dir = Path(__file__).parent
sys.path.insert(0, str(current_dir))

from config import settings

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def check_environment():
    """Check if environment variables are properly configured."""
    required_vars = [
        'ACS_CONNECTION_STRING',
        'AZURE_VOICE_LIVE_API_KEY',
        'AZURE_VOICE_LIVE_ENDPOINT'
    ]
    
    missing_vars = []
    for var in required_vars:
        if not getattr(settings, var.lower(), None):
            missing_vars.append(var)
    
    if missing_vars:
        logger.error(f"Missing required environment variables: {', '.join(missing_vars)}")
        logger.error("Please check your .env file or environment configuration")
        return False
    
    return True


def install_dependencies():
    """Install required Python dependencies."""
    try:
        logger.info("Installing dependencies...")
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', '-r', 'requirements.txt'])
        logger.info("Dependencies installed successfully")
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to install dependencies: {e}")
        return False


def main():
    """Main startup function."""
    logger.info("Starting Azure Communication Services Voice Live API service...")
    
    # Check environment configuration
    if not check_environment():
        sys.exit(1)
    
    # Install dependencies if needed
    if '--install-deps' in sys.argv:
        if not install_dependencies():
            sys.exit(1)
    
    # Import and start the main application
    try:
        from main import app
        import uvicorn
        
        logger.info(f"Starting server on {settings.host}:{settings.port}")
        logger.info(f"Base URL: {settings.base_url}")
        logger.info(f"Voice Live endpoint: {settings.azure_voice_live_endpoint}")
        
        uvicorn.run(
            app,
            host=settings.host,
            port=settings.port,
            log_level=settings.log_level.lower(),
            access_log=True
        )
        
    except Exception as e:
        logger.error(f"Failed to start service: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
