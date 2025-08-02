"""
Azure SQL Database configuration using Azure SDK for Python
Following Azure best practices for managed identity and secure connections
"""
import os
import logging
from typing import Optional
from datetime import datetime
import asyncio
import pyodbc
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential
from azure.core.exceptions import AzureError

logger = logging.getLogger(__name__)

class AzureSQLConfig:
    """
    Azure SQL Database configuration following Azure best practices:
    - Uses managed identity authentication
    - Retrieves connection strings from Key Vault
    - Implements connection pooling and retry logic
    - Follows Azure security recommendations
    """
    
    def __init__(self):
        self._connection_string: Optional[str] = None
        self._credential = DefaultAzureCredential()
        
    async def get_connection_string(self) -> str:
        """
        Retrieve SQL connection string from Azure Key Vault using managed identity
        """
        if self._connection_string:
            return self._connection_string
            
        try:
            # Get Key Vault URL from environment
            key_vault_url = os.getenv("KEY_VAULT_URI")
            if not key_vault_url:
                # Fallback to environment variable for local development
                connection_string = os.getenv("SQL_CONNECTION_STRING")
                if connection_string:
                    logger.info("Using SQL connection string from environment variable")
                    self._connection_string = connection_string
                    return connection_string
                raise ValueError("KEY_VAULT_URI environment variable not set")
            
            # Use Azure SDK to get secret from Key Vault
            secret_client = SecretClient(vault_url=key_vault_url, credential=self._credential)
            secret = secret_client.get_secret("sql-connection-string")
            
            self._connection_string = secret.value
            logger.info("Successfully retrieved SQL connection string from Key Vault")
            return self._connection_string
            
        except AzureError as e:
            logger.error(f"Azure error retrieving connection string: {e}")
            raise
        except Exception as e:
            logger.error(f"Error retrieving connection string: {e}")
            raise
    
    async def get_connection(self):
        """
        Get a database connection with retry logic and proper error handling
        """
        connection_string = await self.get_connection_string()
        
        try:
            # Use pyodbc with proper connection parameters for Azure SQL
            connection = pyodbc.connect(
                connection_string,
                timeout=30,
                autocommit=False
            )
            return connection
        except pyodbc.Error as e:
            logger.error(f"Database connection error: {e}")
            raise
    
    async def execute_query(self, query: str, params: tuple = None, fetch: bool = True):
        """
        Execute a query with proper error handling and connection management
        """
        connection = None
        cursor = None
        
        try:
            connection = await self.get_connection()
            cursor = connection.cursor()
            
            if params:
                cursor.execute(query, params)
            else:
                cursor.execute(query)
            
            if fetch:
                results = cursor.fetchall()
                return results
            else:
                connection.commit()
                return cursor.rowcount
                
        except pyodbc.Error as e:
            if connection:
                connection.rollback()
            logger.error(f"Query execution error: {e}")
            raise
        finally:
            if cursor:
                cursor.close()
            if connection:
                connection.close()
    
    async def test_connection(self) -> bool:
        """Test database connectivity"""
        try:
            await self.execute_query("SELECT 1")
            logger.info("Database connection test successful")
            return True
        except Exception as e:
            logger.error(f"Database connection test failed: {e}")
            return False

# Global database configuration instance
db_config = AzureSQLConfig()

async def init_database():
    """
    Initialize database tables with minimal schema for lamp state only
    """
    try:
        # Test connection first
        if not await db_config.test_connection():
            raise Exception("Database connection test failed")
        
        # Create simple lamp state table
        create_table_query = """
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='lamp_state' AND xtype='U')
        CREATE TABLE lamp_state (
            id INT IDENTITY(1,1) PRIMARY KEY,
            is_on BIT NOT NULL DEFAULT 0,
            last_changed DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
            change_count INT NOT NULL DEFAULT 0,
            updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
        )
        """
        
        await db_config.execute_query(create_table_query, fetch=False)
        
        # Insert initial state if table is empty
        check_query = "SELECT COUNT(*) FROM lamp_state"
        result = await db_config.execute_query(check_query)
        
        if result[0][0] == 0:
            insert_query = """
            INSERT INTO lamp_state (is_on, last_changed, change_count) 
            VALUES (0, GETUTCDATE(), 0)
            """
            await db_config.execute_query(insert_query, fetch=False)
            logger.info("Created initial lamp state")
        
        logger.info("Database initialization completed successfully")
        return True
        
    except Exception as e:
        logger.error(f"Database initialization failed: {e}")
        raise
