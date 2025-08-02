"""
Local SQLite database configuration for development
"""
import sqlite3
import os
import logging
from typing import Optional, List, Dict, Any
from contextlib import contextmanager
from datetime import datetime, timedelta
import json

logger = logging.getLogger(__name__)

class LocalDatabaseConfig:
    """Simple SQLite database for local development"""
    
    def __init__(self):
        # Store database in the src directory
        self.db_path = os.path.join(os.path.dirname(__file__), "lamp_app.db")
        self._ensure_tables()
    
    def _ensure_tables(self):
        """Create tables if they don't exist"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                # Current lamp state table
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS current_lamp_state (
                        id INTEGER PRIMARY KEY CHECK (id = 1),
                        is_on BOOLEAN NOT NULL DEFAULT 0,
                        last_changed TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        change_count INTEGER NOT NULL DEFAULT 0,
                        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                
                # Lamp activities table
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS lamp_activities (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        action TEXT NOT NULL,
                        timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        session_id TEXT NOT NULL,
                        user_agent TEXT,
                        ip_address TEXT,
                        previous_state BOOLEAN
                    )
                """)
                
                # Daily statistics table  
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS lamp_statistics (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        date DATE NOT NULL UNIQUE,
                        total_toggles INTEGER NOT NULL DEFAULT 0,
                        on_count INTEGER NOT NULL DEFAULT 0,
                        off_count INTEGER NOT NULL DEFAULT 0,
                        unique_sessions INTEGER NOT NULL DEFAULT 0,
                        total_on_duration_minutes INTEGER NOT NULL DEFAULT 0,
                        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                
                # Insert initial state if doesn't exist
                cursor.execute("INSERT OR IGNORE INTO current_lamp_state (id, is_on, change_count) VALUES (1, 0, 0)")
                
                conn.commit()
                logger.info("SQLite database tables created/verified successfully")
                
        except Exception as e:
            logger.error(f"Failed to create SQLite tables: {e}")
            raise
    
    @contextmanager
    def get_connection(self):
        """Context manager for database connections"""
        conn = None
        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row  # Enable column access by name
            yield conn
        except Exception as e:
            if conn:
                conn.rollback()
            logger.error(f"Database error: {e}")
            raise
        finally:
            if conn:
                conn.close()
    
    def test_connection(self) -> bool:
        """Test database connectivity"""
        try:
            with self.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT 1")
                return True
        except Exception as e:
            logger.error(f"Database connection test failed: {e}")
            return False

# Global instance
local_db = LocalDatabaseConfig()

def init_database():
    """Initialize the local SQLite database"""
    try:
        if local_db.test_connection():
            logger.info("Local SQLite database initialized successfully")
            return True
        else:
            raise Exception("SQLite database connection test failed")
    except Exception as e:
        logger.error(f"Failed to initialize local database: {e}")
        raise
