"""
Database package - Contains high-availability database functionality
"""
import logging
import os

logger = logging.getLogger(__name__)

# Always use high-availability repository as the main interface
from .ha_repository import HALampRepository

# Try to import the regular Azure repository if available
try:
    # Check if we're in an Azure environment or have required environment variables
    if (os.getenv("KEY_VAULT_URI") or 
        os.getenv("POSTGRES_CONNECTION_STRING") or 
        os.getenv("AZURE_CLIENT_ID")):
        # Try Azure setup
        from .database import get_db, db_config
        from .repository import LampRepository as _PostgresRepository
        logger.info("Azure PostgreSQL available for HA repository")
        __all__ = ["HALampRepository", "get_db", "db_config"]
    else:
        logger.info("No Azure environment variables found, HA repository will use cache-only mode")
        raise ImportError("Azure environment variables not found")
        
except (ImportError, Exception) as e:
    # No database available, HA repository will use cache-only mode
    logger.info(f"Azure database unavailable ({e}), HA repository will use cache-only mode")
    
    # Create compatibility aliases
    db_config = None
    get_db = None
    
    __all__ = ["HALampRepository"]

# Provide compatibility alias for the main repository
LampRepository = HALampRepository
