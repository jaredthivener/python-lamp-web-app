"""
Database initialization script for development and testing
"""
import os
import sys
import logging
from pathlib import Path

# Add src directory to Python path
src_path = Path(__file__).parent
sys.path.insert(0, str(src_path))

from database.database import init_database, db_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_sample_data():
    """Create some sample data for testing"""
    # Note: This function uses SQLAlchemy patterns but the project uses psycopg2
    # Skipping sample data creation for now
    logger.info("Sample data creation skipped - not implemented for psycopg2")
    return

    # The original SQLAlchemy code is commented out:
    # from datetime import datetime, timedelta
    # from sqlalchemy.orm import sessionmaker
    # from models import LampActivity, LampStatistics, CurrentLampState

    # The original SQLAlchemy code is commented out:
    # from datetime import datetime, timedelta
    # from sqlalchemy.orm import sessionmaker
    # from models import LampActivity, LampStatistics, CurrentLampState

    # try:
    #     engine = db_config.get_engine()
    #     Session = sessionmaker(bind=engine)
    #     session = Session()
    #     ... (rest of SQLAlchemy code)
    # except Exception as e:
    #     logger.error(f"Error creating sample data: {e}")
    #     raise

def main():
    """Main initialization function"""
    try:
        logger.info("Starting database initialization...")

        # Initialize database tables
        success = init_database()

        if success:
            logger.info("Database tables created successfully")

            # Create sample data for development
            if os.getenv("ENVIRONMENT", "dev") == "dev":
                logger.info("Creating sample data for development...")
                create_sample_data()

            logger.info("Database initialization completed successfully!")
            return True
        else:
            logger.error("Database initialization failed")
            return False

    except Exception as e:
        logger.error(f"Database initialization error: {e}")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
