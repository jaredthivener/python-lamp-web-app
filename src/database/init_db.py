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

from database import init_database, db_config
from models import Base

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_sample_data():
    """Create some sample data for testing"""
    from datetime import datetime, timedelta
    from sqlalchemy.orm import sessionmaker
    from models import LampActivity, LampStatistics, CurrentLampState
    
    try:
        engine = db_config.get_engine()
        Session = sessionmaker(bind=engine)
        session = Session()
        
        # Create initial lamp state if it doesn't exist
        existing_state = session.query(CurrentLampState).filter(CurrentLampState.id == 1).first()
        if not existing_state:
            initial_state = CurrentLampState(
                id=1,
                is_on=False,
                last_changed=datetime.utcnow(),
                change_count=0
            )
            session.add(initial_state)
            session.commit()
            logger.info("Created initial lamp state")
        
        # Create some sample activities for testing
        sample_activities = [
            LampActivity(
                action="on",
                timestamp=datetime.utcnow() - timedelta(minutes=30),
                session_id="sample_session_1",
                user_agent="Mozilla/5.0 (Test Browser)",
                ip_address="127.0.0.1",
                previous_state="off"
            ),
            LampActivity(
                action="off",
                timestamp=datetime.utcnow() - timedelta(minutes=15),
                session_id="sample_session_1",
                user_agent="Mozilla/5.0 (Test Browser)",
                ip_address="127.0.0.1",
                previous_state="on"
            ),
            LampActivity(
                action="on",
                timestamp=datetime.utcnow() - timedelta(minutes=5),
                session_id="sample_session_2",
                user_agent="Mozilla/5.0 (Test Browser)",
                ip_address="127.0.0.1",
                previous_state="off"
            )
        ]
        
        # Check if sample data already exists
        existing_activities = session.query(LampActivity).count()
        if existing_activities == 0:
            session.add_all(sample_activities)
            session.commit()
            logger.info(f"Created {len(sample_activities)} sample activities")
        
        session.close()
        
    except Exception as e:
        logger.error(f"Error creating sample data: {e}")
        if 'session' in locals():
            session.rollback()
            session.close()
        raise

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
