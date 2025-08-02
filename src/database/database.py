"""
Database configuration and connection management for the Lamp Web App
"""
import os
import logging
import re
import psycopg2
import psycopg2.extras
from typing import Optional, Dict, Any, List
from contextlib import contextmanager
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential
import time

logger = logging.getLogger(__name__)

class DatabaseConfig:
    """Database configuration and connection management using psycopg2"""
    
    def __init__(self):
        self._connection_string = None
        
    def _get_connection_string(self) -> str:
        """
        Retrieve PostgreSQL connection string from environment variable or Azure Key Vault
        """
        if self._connection_string:
            return self._connection_string
            
        # Try to get from environment variable first
        connection_string = os.getenv("POSTGRES_CONNECTION_STRING")
        
        if connection_string:
            # Check if it's a Key Vault reference that wasn't resolved by Azure
            if connection_string.startswith("@Microsoft.KeyVault("):
                logger.warning("Found unresolved Key Vault reference in environment variable, attempting direct Key Vault access")
                # Extract the secret name from the Key Vault reference
                # Format: @Microsoft.KeyVault(SecretUri=https://vault.vault.azure.net/secrets/secret-name/)
                try:
                    # Parse the Key Vault URL to extract vault name and secret name
                    match = re.search(r'SecretUri=https://([^.]+)\.vault\.azure\.net/secrets/([^/]+)', connection_string)
                    if match:
                        vault_name = match.group(1)
                        secret_name = match.group(2)
                        vault_url = f"https://{vault_name}.vault.azure.net/"
                        
                        credential = DefaultAzureCredential()
                        client = SecretClient(vault_url=vault_url, credential=credential)
                        secret = client.get_secret(secret_name)
                        self._connection_string = secret.value
                        logger.info(f"Successfully retrieved PostgreSQL connection string from Key Vault using managed identity (vault: {vault_name}, secret: {secret_name})")
                        return self._connection_string
                    else:
                        logger.error(f"Could not parse Key Vault reference: {connection_string}")
                except Exception as e:
                    logger.error(f"Failed to resolve Key Vault reference directly: {e}")
                    # Fall through to try the KEY_VAULT_URI method
            else:
                logger.info("Using PostgreSQL connection string from environment variable")
                self._connection_string = connection_string
                return connection_string
            
        # Try to get from Azure Key Vault using KEY_VAULT_URI (fallback)
        try:
            key_vault_url = os.getenv("KEY_VAULT_URI")
            if not key_vault_url:
                logger.warning("KEY_VAULT_URI environment variable not set, cannot access Key Vault")
                raise ValueError("KEY_VAULT_URI environment variable not set")
                
            credential = DefaultAzureCredential()
            client = SecretClient(vault_url=key_vault_url, credential=credential)
            
            secret = client.get_secret("postgresql-connection-string")
            self._connection_string = secret.value
            logger.info("Successfully retrieved PostgreSQL connection string from Key Vault using KEY_VAULT_URI")
            return self._connection_string
            
        except Exception as e:
            logger.error(f"Failed to retrieve connection string from Key Vault: {e}")
            raise ValueError("Could not retrieve PostgreSQL connection string from Key Vault or environment")
    
    def get_connection(self):
        """Get a new database connection using psycopg2"""
        connection_string = self._get_connection_string()
        
        try:
            connection = psycopg2.connect(connection_string)
            connection.autocommit = False  # Explicitly set autocommit to False
            logger.debug("PostgreSQL connection established successfully")
            return connection
            
        except Exception as e:
            logger.error(f"Failed to connect to PostgreSQL database: {e}")
            raise
    
    def test_connection(self) -> bool:
        """Test database connectivity"""
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cursor:
                    cursor.execute("SELECT 1")
                    cursor.fetchone()
            logger.info("Database connection test successful")
            return True
        except Exception as e:
            logger.error(f"Database connection test failed: {e}")
            return False
    
    def execute_query(self, query: str, params: tuple = None) -> List[Dict[str, Any]]:
        """Execute a SELECT query and return results as list of dictionaries"""
        try:
            with self.get_connection() as conn:
                with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cursor:
                    if params:
                        cursor.execute(query, params)
                    else:
                        cursor.execute(query)
                    
                    # Fetch all rows and convert to list of dictionaries
                    rows = cursor.fetchall()
                    results = [dict(row) for row in rows]
                    
                    logger.debug(f"Query executed successfully, returned {len(results)} rows")
                    return results
                    
        except Exception as e:
            logger.error(f"Failed to execute query: {e}")
            raise
    
    def execute_command(self, command: str, params: tuple = None) -> int:
        """Execute an INSERT, UPDATE, or DELETE command and return rows affected"""
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cursor:
                    if params:
                        cursor.execute(command, params)
                    else:
                        cursor.execute(command)
                    
                    rows_affected = cursor.rowcount
                    conn.commit()
                    logger.debug(f"Command executed successfully, {rows_affected} rows affected")
                    return rows_affected
                    
        except Exception as e:
            logger.error(f"Failed to execute command: {e}")
            raise
    
    def create_tables(self):
        """Create the lamp_status table and related tables if they don't exist"""
        try:
            # Create main lamp status table
            create_lamp_status_sql = """
            CREATE TABLE IF NOT EXISTS lamp_status (
                id SERIAL PRIMARY KEY,
                is_on BOOLEAN NOT NULL DEFAULT FALSE,
                last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                client_info TEXT
            )
            """
            self.execute_command(create_lamp_status_sql)
            
            # Create activities table
            create_activities_sql = """
            CREATE TABLE IF NOT EXISTS lamp_activities (
                id SERIAL PRIMARY KEY,
                action VARCHAR(10) NOT NULL,
                timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                session_id VARCHAR(100),
                user_agent TEXT,
                ip_address VARCHAR(45),
                previous_state VARCHAR(10),
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            )
            """
            self.execute_command(create_activities_sql)
            
            # Create statistics table
            create_statistics_sql = """
            CREATE TABLE IF NOT EXISTS lamp_statistics (
                id SERIAL PRIMARY KEY,
                date DATE NOT NULL,
                total_toggles INTEGER DEFAULT 0,
                on_count INTEGER DEFAULT 0,
                off_count INTEGER DEFAULT 0,
                unique_sessions INTEGER DEFAULT 0,
                total_on_duration_minutes INTEGER DEFAULT 0,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            )
            """
            self.execute_command(create_statistics_sql)
            
            # Insert default record if lamp_status table is empty
            check_data_sql = "SELECT COUNT(*) as count FROM lamp_status"
            result = self.execute_query(check_data_sql)
            
            if result[0]['count'] == 0:
                insert_default_sql = "INSERT INTO lamp_status (is_on) VALUES (FALSE)"
                self.execute_command(insert_default_sql)
                logger.info("Inserted default lamp status record")
            
            logger.info("Database tables created/verified successfully")
            
        except Exception as e:
            logger.error(f"Failed to create database tables: {e}")
            raise

# Global database configuration instance
db_config = DatabaseConfig()

@contextmanager
def get_db():
    """
    Context manager to get database connection
    """
    connection = None
    try:
        connection = db_config.get_connection()
        yield connection
    except Exception as e:
        if connection:
            connection.rollback()
        logger.error(f"Database connection error: {e}")
        raise
    finally:
        if connection:
            connection.close()

def init_database():
    """Initialize database tables and verify connection"""
    max_retries = 3
    retry_delay = 5
    
    for attempt in range(max_retries):
        try:
            # Test connection first
            if not db_config.test_connection():
                raise Exception("Database connection test failed")
            
            # Create tables
            db_config.create_tables()
            logger.info("Database initialization completed successfully")
            return True
            
        except Exception as e:
            if attempt < max_retries - 1:
                logger.warning(f"Database initialization attempt {attempt + 1} failed: {e}. Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
                retry_delay *= 2  # Exponential backoff
            else:
                logger.error(f"Database initialization failed after {max_retries} attempts: {e}")
                raise e
    
    return False
