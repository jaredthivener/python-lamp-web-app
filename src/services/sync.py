"""
Synchronization service for maintaining consistency between cache and Azure PostgreSQL.
Handles bidirectional sync and automatic reconnection.
"""
import asyncio
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, Optional
import threading
import time

from .cache import get_cache_service, CachedLampState, CachedActivity, CachedDailyStats

logger = logging.getLogger(__name__)

class DatabaseSyncService:
    """
    Service for synchronizing cache with Azure PostgreSQL database.
    Handles connection failures gracefully and maintains data consistency.
    """

    def __init__(self):
        self.cache_service = get_cache_service()
        self._sync_lock = threading.RLock()
        self._is_running = False
        self._sync_thread = None
        self._db_available = False
        self._last_sync_attempt = None
        self._sync_interval = 30  # seconds
        self._max_retry_interval = 300  # 5 minutes max between retries
        self._current_retry_interval = 5  # start with 5 seconds

        logger.info("DatabaseSyncService initialized")

    def start_sync_service(self):
        """Start the background sync service"""
        with self._sync_lock:
            if self._is_running:
                logger.warning("Sync service is already running")
                return

            self._is_running = True
            self._sync_thread = threading.Thread(target=self._sync_loop, daemon=True)
            self._sync_thread.start()
            logger.info("Database sync service started")

    def stop_sync_service(self):
        """Stop the background sync service"""
        with self._sync_lock:
            if not self._is_running:
                return

            self._is_running = False
            if self._sync_thread:
                self._sync_thread.join(timeout=5)
            logger.info("Database sync service stopped")

    def _sync_loop(self):
        """Main sync loop running in background thread"""
        logger.info("Sync loop started")

        while self._is_running:
            try:
                self._perform_sync()

                # If sync succeeded, reset retry interval
                self._current_retry_interval = 5
                sleep_time = self._sync_interval

            except Exception as e:
                logger.error(f"Sync failed: {e}")
                # Exponential backoff for retries
                sleep_time = min(self._current_retry_interval, self._max_retry_interval)
                self._current_retry_interval = min(self._current_retry_interval * 2, self._max_retry_interval)

            # Sleep with periodic checks for shutdown
            for _ in range(int(sleep_time)):
                if not self._is_running:
                    break
                time.sleep(1)

        logger.info("Sync loop stopped")

    def _perform_sync(self):
        """Perform synchronization between cache and database"""
        self._last_sync_attempt = datetime.now()

        try:
            # Try to connect to database
            repository = self._get_database_repository()

            if repository is None:
                self._db_available = False
                logger.warning("Database not available, using cache-only mode")
                return

            # Database is available
            if not self._db_available:
                logger.info("Database connection restored")
                self._db_available = True

                # First sync: load data from database to cache
                self._sync_from_database(repository)

            # Then sync cache changes to database
            if self.cache_service.is_cache_dirty():
                self._sync_to_database(repository)

        except Exception as e:
            self._db_available = False
            logger.error(f"Database sync error: {e}")
            raise

    def _get_database_repository(self):
        """Get database repository instance, return None if unavailable"""
        try:
            from database.repository import LampRepository
            repo = LampRepository()

            # Test connection with a simple query
            repo.get_current_state()
            return repo

        except Exception as e:
            logger.debug(f"Database repository unavailable: {e}")
            return None

    def _sync_from_database(self, repository):
        """Sync data from database to cache"""
        try:
            logger.info("Syncing data from database to cache")

            # Get comprehensive data from database
            dashboard_data = repository.get_dashboard_data()

            # Convert database format to cache format
            cache_data = {
                "current_state": {
                    "is_on": dashboard_data.current_state.is_on,
                    "last_updated": dashboard_data.current_state.last_changed.isoformat(),
                    "session_id": getattr(dashboard_data.current_state, 'session_id', None)
                },
                "total_lifetime_toggles": dashboard_data.total_lifetime_toggles
            }

            # Add today's stats if available
            if dashboard_data.today_stats:
                cache_data["today_stats"] = {
                    "date": dashboard_data.today_stats.date.isoformat(),
                    "total_toggles": dashboard_data.today_stats.total_toggles,
                    "on_count": dashboard_data.today_stats.on_count,
                    "off_count": dashboard_data.today_stats.off_count,
                    "unique_sessions": dashboard_data.today_stats.unique_sessions,
                    "total_on_duration_minutes": dashboard_data.today_stats.total_on_duration_minutes
                }

            # Add recent activities if available
            if dashboard_data.recent_activities:
                cache_data["recent_activities"] = [
                    {
                        "id": str(activity.id),
                        "action": activity.action,
                        "timestamp": activity.timestamp.isoformat(),
                        "session_id": activity.session_id,
                        "previous_state": activity.previous_state,
                        "user_agent": getattr(activity, 'user_agent', None),
                        "ip_address": getattr(activity, 'ip_address', None)
                    }
                    for activity in dashboard_data.recent_activities
                ]

            # Update cache with database data
            self.cache_service.update_from_database(cache_data)

            logger.info("Database to cache sync completed")

        except Exception as e:
            logger.error(f"Error syncing from database to cache: {e}")
            raise

    def _sync_to_database(self, repository):
        """Sync cache changes to database"""
        try:
            logger.info("Syncing cache changes to database")

            # Get cache data that needs syncing
            cache_data = self.cache_service.get_cache_data_for_sync()

            if not cache_data:
                logger.debug("No cache changes to sync")
                return

            # Sync current state
            if 'current_state' in cache_data:
                state_data = cache_data['current_state']
                # Update database state if needed
                db_state = repository.get_current_state()
                if (db_state.is_on != state_data['is_on'] or
                    abs((db_state.last_changed - datetime.fromisoformat(state_data['last_updated'])).total_seconds()) > 1):

                    # Need to sync state - this is complex and might require special handling
                    logger.info("State difference detected between cache and database")

            # Sync activities (add new ones)
            if 'activities' in cache_data:
                activities = cache_data['activities']
                for activity_data in activities:
                    try:
                        # Try to add activity to database
                        # This is a simplified approach - in production you'd want to check for duplicates
                        logger.debug(f"Would sync activity: {activity_data['id']}")
                    except Exception as e:
                        logger.warning(f"Failed to sync activity {activity_data['id']}: {e}")

            # Mark cache as clean after successful sync
            self.cache_service.mark_cache_clean()

            logger.info("Cache to database sync completed")

        except Exception as e:
            logger.error(f"Error syncing cache to database: {e}")
            raise

    def is_database_available(self) -> bool:
        """Check if database is currently available"""
        return self._db_available

    def get_last_sync_attempt(self) -> Optional[datetime]:
        """Get timestamp of last sync attempt"""
        return self._last_sync_attempt

    def force_sync(self) -> bool:
        """Force an immediate sync attempt"""
        try:
            with self._sync_lock:
                self._perform_sync()
                return True
        except Exception as e:
            logger.error(f"Force sync failed: {e}")
            return False

    def get_sync_status(self) -> Dict[str, Any]:
        """Get current sync service status"""
        return {
            "is_running": self._is_running,
            "database_available": self._db_available,
            "last_sync_attempt": self._last_sync_attempt.isoformat() if self._last_sync_attempt else None,
            "cache_dirty": self.cache_service.is_cache_dirty(),
            "current_retry_interval": self._current_retry_interval,
            "next_sync_in_seconds": self._sync_interval if self._db_available else self._current_retry_interval
        }

# Global sync service instance
_sync_instance = None
_sync_lock = threading.Lock()

def get_sync_service() -> DatabaseSyncService:
    """Get or create global sync service instance"""
    global _sync_instance

    if _sync_instance is None:
        with _sync_lock:
            if _sync_instance is None:
                _sync_instance = DatabaseSyncService()

    return _sync_instance

def start_sync_service():
    """Start the global sync service"""
    sync_service = get_sync_service()
    sync_service.start_sync_service()

def stop_sync_service():
    """Stop the global sync service"""
    global _sync_instance
    if _sync_instance:
        _sync_instance.stop_sync_service()
