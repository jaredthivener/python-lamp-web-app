"""
High-availability repository that uses cache as fallback when database is unavailable.
"""
import logging
from datetime import datetime, date
from typing import Optional, List
from services import get_cache_service, get_sync_service
from .models import LampActivity, LampStatistics, CurrentLampState
from .models import LampActivityResponse, LampStatisticsResponse, CurrentLampStateResponse, LampDashboardResponse

logger = logging.getLogger(__name__)

class HALampRepository:
    """
    High-availability repository that provides seamless fallback to cache
    when Azure PostgreSQL is unavailable.
    """
    
    def __init__(self):
        self.cache_service = get_cache_service()
        self.sync_service = get_sync_service()
        self._db_repository = None
    
    def _get_db_repository(self):
        """Get database repository if available, None otherwise"""
        if self._db_repository is None:
            try:
                from .repository import LampRepository
                self._db_repository = LampRepository()
                # Test connection
                self._db_repository.get_current_state()
                return self._db_repository
            except Exception as e:
                logger.debug(f"Database repository unavailable: {e}")
                return None
        
        try:
            # Test if existing repository still works
            self._db_repository.get_current_state()
            return self._db_repository
        except Exception as e:
            logger.warning(f"Database repository became unavailable: {e}")
            self._db_repository = None
            return None
    
    def get_current_state(self) -> CurrentLampState:
        """Get current lamp state with database fallback to cache"""
        db_repo = self._get_db_repository()
        
        if db_repo:
            try:
                # Try database first
                db_state = db_repo.get_current_state()
                
                # Sync cache with database state if needed
                cache_state = self.cache_service.get_current_state()
                if cache_state.is_on != db_state.is_on:
                    logger.info("Syncing cache state with database")
                    cache_data = {
                        "current_state": {
                            "is_on": db_state.is_on,
                            "last_updated": db_state.last_changed.isoformat(),
                            "session_id": db_state.last_session_id
                        }
                    }
                    self.cache_service.update_from_database(cache_data)
                
                return db_state
                
            except Exception as e:
                logger.warning(f"Database failed, falling back to cache: {e}")
        
        # Fallback to cache
        cache_state = self.cache_service.get_current_state()
        cache_data = self.cache_service.get_dashboard_data()
        
        return CurrentLampState(
            id=1,
            is_on=cache_state.is_on,
            last_changed=cache_state.last_updated,
            last_session_id=cache_state.session_id,
            change_count=cache_data["total_lifetime_toggles"]
        )
    
    def toggle_lamp(self, session_id: Optional[str] = None, user_agent: Optional[str] = None, 
                   ip_address: Optional[str] = None) -> CurrentLampState:
        """Toggle lamp state with high availability"""
        db_repo = self._get_db_repository()
        
        if db_repo:
            try:
                # Try database first
                db_state = db_repo.toggle_lamp(session_id, user_agent, ip_address)
                
                # Also update cache to keep in sync
                cache_data = {
                    "current_state": {
                        "is_on": db_state.is_on,
                        "last_updated": db_state.last_changed.isoformat(),
                        "session_id": session_id
                    }
                }
                self.cache_service.update_from_database(cache_data)
                
                logger.info(f"Lamp toggled in database and cache synced")
                return db_state
                
            except Exception as e:
                logger.warning(f"Database toggle failed, using cache: {e}")
        
        # Fallback to cache
        cache_state = self.cache_service.toggle_lamp(
            session_id or "unknown",
            user_agent,
            ip_address
        )
        
        cache_data = self.cache_service.get_dashboard_data()
        
        logger.info(f"Lamp toggled in cache (database unavailable)")
        
        return CurrentLampState(
            id=1,
            is_on=cache_state.is_on,
            last_changed=cache_state.last_updated,
            last_session_id=cache_state.session_id,
            change_count=cache_data["total_lifetime_toggles"]
        )
    
    def get_recent_activities(self, limit: int = 10) -> List[LampActivity]:
        """Get recent activities with fallback"""
        db_repo = self._get_db_repository()
        
        if db_repo:
            try:
                return db_repo.get_recent_activities(limit)
            except Exception as e:
                logger.warning(f"Database activities failed, using cache: {e}")
        
        # Fallback to cache
        cache_activities = self.cache_service.get_recent_activities(limit)
        
        activities = []
        for cache_activity in cache_activities:
            activity = LampActivity(
                id=int(cache_activity.id.split('_')[1]) if '_' in cache_activity.id else hash(cache_activity.id),
                action=cache_activity.action,
                timestamp=cache_activity.timestamp,
                session_id=cache_activity.session_id,
                user_agent=cache_activity.user_agent,
                ip_address=cache_activity.ip_address,
                previous_state="on" if cache_activity.previous_state else "off"  # Convert bool to string
            )
            activities.append(activity)
        
        return activities
    
    def get_daily_statistics(self, target_date: date = None) -> Optional[LampStatistics]:
        """Get daily statistics with fallback"""
        if target_date is None:
            target_date = date.today()
        
        db_repo = self._get_db_repository()
        
        if db_repo:
            try:
                return db_repo.get_daily_statistics(target_date)
            except Exception as e:
                logger.warning(f"Database statistics failed, using cache: {e}")
        
        # Fallback to cache
        cache_stats = self.cache_service.get_daily_statistics(target_date)
        
        if not cache_stats:
            return None
        
        return LampStatistics(
            id=1,
            date=cache_stats.date,
            total_toggles=cache_stats.total_toggles,
            on_count=cache_stats.on_count,
            off_count=cache_stats.off_count,
            unique_sessions=cache_stats.unique_sessions,
            total_on_duration_minutes=cache_stats.total_on_duration_minutes
        )
    
    def get_dashboard_data(self) -> LampDashboardResponse:
        """Get comprehensive dashboard data with fallback"""
        db_repo = self._get_db_repository()
        
        if db_repo:
            try:
                return db_repo.get_dashboard_data()
            except Exception as e:
                logger.warning(f"Database dashboard failed, using cache: {e}")
        
        # Fallback to cache
        cache_data = self.cache_service.get_dashboard_data()
        
        # Convert cache data to expected format
        current_state_data = cache_data["current_state"]
        current_state = CurrentLampStateResponse(
            id=1,
            is_on=current_state_data["is_on"],
            last_updated=datetime.fromisoformat(current_state_data["last_updated"]),
            last_changed=datetime.fromisoformat(current_state_data["last_updated"]),  # Use same timestamp
            change_count=cache_data["total_lifetime_toggles"]  # Use lifetime toggles as change count
        )
        
        today_stats = None
        if cache_data["today_stats"] and cache_data["today_stats"]["total_toggles"] > 0:
            stats_data = cache_data["today_stats"]
            today_stats = LampStatisticsResponse(
                id=1,
                date=date.fromisoformat(stats_data["date"]),
                total_toggles=stats_data["total_toggles"],
                on_count=stats_data["on_count"],
                off_count=stats_data["off_count"],
                unique_sessions=stats_data["unique_sessions"],
                total_on_duration_minutes=stats_data["total_on_duration_minutes"]
            )
        
        recent_activities = []
        for activity_data in cache_data["recent_activities"]:
            activity = LampActivityResponse(
                id=int(activity_data["id"].split('_')[1]) if '_' in activity_data["id"] else hash(activity_data["id"]),
                action=activity_data["action"],
                timestamp=datetime.fromisoformat(activity_data["timestamp"]),
                session_id=activity_data["session_id"],
                previous_state="on" if activity_data["previous_state"] else "off"  # Convert bool to string
            )
            recent_activities.append(activity)
        
        return LampDashboardResponse(
            current_state=current_state,
            today_stats=today_stats,
            total_lifetime_toggles=cache_data["total_lifetime_toggles"],
            recent_activities=recent_activities
        )
    
    def get_sync_status(self) -> dict:
        """Get status of cache and sync service"""
        return {
            "database_available": self._get_db_repository() is not None,
            "cache_dirty": self.cache_service.is_cache_dirty(),
            "sync_status": self.sync_service.get_sync_status()
        }
