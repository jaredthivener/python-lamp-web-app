"""
High-availability caching service for lamp state management.
Provides fallback when Azure PostgreSQL is unavailable and maintains state consistency.
"""
import json
import logging
from datetime import datetime, date
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
import threading
import time

logger = logging.getLogger(__name__)

@dataclass
class CachedLampState:
    """Cached representation of lamp state"""
    is_on: bool
    last_updated: datetime
    session_id: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'is_on': self.is_on,
            'last_updated': self.last_updated.isoformat(),
            'session_id': self.session_id
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'CachedLampState':
        return cls(
            is_on=data['is_on'],
            last_updated=datetime.fromisoformat(data['last_updated']),
            session_id=data.get('session_id')
        )

@dataclass
class CachedActivity:
    """Cached representation of lamp activity"""
    id: str
    action: str
    timestamp: datetime
    session_id: str
    previous_state: bool
    user_agent: Optional[str] = None
    ip_address: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'id': self.id,
            'action': self.action,
            'timestamp': self.timestamp.isoformat(),
            'session_id': self.session_id,
            'previous_state': self.previous_state,
            'user_agent': self.user_agent,
            'ip_address': self.ip_address
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'CachedActivity':
        return cls(
            id=data['id'],
            action=data['action'],
            timestamp=datetime.fromisoformat(data['timestamp']),
            session_id=data['session_id'],
            previous_state=data['previous_state'],
            user_agent=data.get('user_agent'),
            ip_address=data.get('ip_address')
        )

@dataclass
class CachedDailyStats:
    """Cached representation of daily statistics"""
    date: date
    total_toggles: int
    on_count: int
    off_count: int
    unique_sessions: int
    total_on_duration_minutes: int
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'date': self.date.isoformat(),
            'total_toggles': self.total_toggles,
            'on_count': self.on_count,
            'off_count': self.off_count,
            'unique_sessions': self.unique_sessions,
            'total_on_duration_minutes': self.total_on_duration_minutes
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'CachedDailyStats':
        return cls(
            date=date.fromisoformat(data['date']),
            total_toggles=data['total_toggles'],
            on_count=data['on_count'],
            off_count=data['off_count'],
            unique_sessions=data['unique_sessions'],
            total_on_duration_minutes=data['total_on_duration_minutes']
        )

class LampCacheService:
    """
    High-availability caching service for lamp state management.
    Maintains state in memory and provides fallback when database is unavailable.
    """
    
    def __init__(self):
        self._lock = threading.RLock()
        self._current_state = CachedLampState(is_on=False, last_updated=datetime.now())
        self._activities: List[CachedActivity] = []
        self._daily_stats: Dict[str, CachedDailyStats] = {}
        self._sessions: set = set()
        self._lifetime_toggles = 0
        self._cache_dirty = False  # Track if cache has unsaved changes
        
        logger.info("LampCacheService initialized")
    
    def get_current_state(self) -> CachedLampState:
        """Get current lamp state from cache"""
        with self._lock:
            return CachedLampState(
                is_on=self._current_state.is_on,
                last_updated=self._current_state.last_updated,
                session_id=self._current_state.session_id
            )
    
    def toggle_lamp(self, session_id: str, user_agent: str = None, ip_address: str = None) -> CachedLampState:
        """Toggle lamp state and record activity in cache"""
        with self._lock:
            # Record previous state
            previous_state = self._current_state.is_on
            
            # Toggle the state
            new_state = not previous_state
            timestamp = datetime.now()
            
            # Update current state
            self._current_state = CachedLampState(
                is_on=new_state,
                last_updated=timestamp,
                session_id=session_id
            )
            
            # Create activity record
            activity_id = f"cache_{int(timestamp.timestamp() * 1000)}_{session_id[:8]}"
            activity = CachedActivity(
                id=activity_id,
                action="on" if new_state else "off",
                timestamp=timestamp,
                session_id=session_id,
                previous_state=previous_state,
                user_agent=user_agent,
                ip_address=ip_address
            )
            
            # Add to activities (keep last 100)
            self._activities.append(activity)
            if len(self._activities) > 100:
                self._activities = self._activities[-100:]
            
            # Update daily stats
            self._update_daily_stats(timestamp, session_id, new_state)
            
            # Update lifetime toggles
            self._lifetime_toggles += 1
            
            # Mark cache as dirty
            self._cache_dirty = True
            
            logger.info(f"Lamp toggled to {'ON' if new_state else 'OFF'} in cache by session {session_id}")
            
            return CachedLampState(
                is_on=new_state,
                last_updated=timestamp,
                session_id=session_id
            )
    
    def _update_daily_stats(self, timestamp: datetime, session_id: str, new_state: bool):
        """Update daily statistics in cache"""
        today = timestamp.date()
        today_key = today.isoformat()
        
        # Add session to tracking
        self._sessions.add(session_id)
        
        if today_key not in self._daily_stats:
            self._daily_stats[today_key] = CachedDailyStats(
                date=today,
                total_toggles=0,
                on_count=0,
                off_count=0,
                unique_sessions=0,
                total_on_duration_minutes=0
            )
        
        stats = self._daily_stats[today_key]
        stats.total_toggles += 1
        
        if new_state:
            stats.on_count += 1
        else:
            stats.off_count += 1
        
        # Count unique sessions for today (simplified - just use total unique sessions)
        stats.unique_sessions = len(self._sessions)
    
    def get_recent_activities(self, limit: int = 10) -> List[CachedActivity]:
        """Get recent activities from cache"""
        with self._lock:
            return list(reversed(self._activities[-limit:]))
    
    def get_daily_statistics(self, target_date: date = None) -> Optional[CachedDailyStats]:
        """Get daily statistics from cache"""
        if target_date is None:
            target_date = date.today()
        
        date_key = target_date.isoformat()
        
        with self._lock:
            return self._daily_stats.get(date_key)
    
    def get_dashboard_data(self) -> Dict[str, Any]:
        """Get comprehensive dashboard data from cache"""
        with self._lock:
            current_state = self.get_current_state()
            today_stats = self.get_daily_statistics()
            recent_activities = self.get_recent_activities(5)
            
            return {
                "current_state": current_state.to_dict(),
                "today_stats": today_stats.to_dict() if today_stats else {
                    "date": date.today().isoformat(),
                    "total_toggles": 0,
                    "on_count": 0,
                    "off_count": 0,
                    "unique_sessions": 0,
                    "total_on_duration_minutes": 0
                },
                "total_lifetime_toggles": self._lifetime_toggles,
                "recent_activities": [activity.to_dict() for activity in recent_activities],
                "source": "cache"  # Indicate this data is from cache
            }
    
    def is_cache_dirty(self) -> bool:
        """Check if cache has unsaved changes"""
        with self._lock:
            return self._cache_dirty
    
    def mark_cache_clean(self):
        """Mark cache as clean (synced with database)"""
        with self._lock:
            self._cache_dirty = False
            logger.info("Cache marked as clean")
    
    def update_from_database(self, db_data: Dict[str, Any]):
        """Update cache with data from database"""
        with self._lock:
            try:
                # Update current state if provided
                if 'current_state' in db_data:
                    state_data = db_data['current_state']
                    self._current_state = CachedLampState.from_dict(state_data)
                
                # Update lifetime toggles if provided
                if 'total_lifetime_toggles' in db_data:
                    self._lifetime_toggles = db_data['total_lifetime_toggles']
                
                # Update daily stats if provided
                if 'today_stats' in db_data and db_data['today_stats']:
                    stats_data = db_data['today_stats']
                    stats = CachedDailyStats.from_dict(stats_data)
                    self._daily_stats[stats.date.isoformat()] = stats
                
                # Update recent activities if provided
                if 'recent_activities' in db_data:
                    activities_data = db_data['recent_activities']
                    self._activities = [CachedActivity.from_dict(act) for act in activities_data]
                
                logger.info("Cache updated from database")
                
            except Exception as e:
                logger.error(f"Error updating cache from database: {e}")
    
    def get_cache_data_for_sync(self) -> Dict[str, Any]:
        """Get cache data that needs to be synced to database"""
        with self._lock:
            if not self._cache_dirty:
                return {}
            
            return {
                "current_state": self._current_state.to_dict(),
                "activities": [activity.to_dict() for activity in self._activities],
                "daily_stats": {k: v.to_dict() for k, v in self._daily_stats.items()},
                "lifetime_toggles": self._lifetime_toggles,
                "sessions": list(self._sessions)
            }
    
    def reset_cache(self):
        """Reset cache to initial state (for testing)"""
        with self._lock:
            self._current_state = CachedLampState(is_on=False, last_updated=datetime.now())
            self._activities.clear()
            self._daily_stats.clear()
            self._sessions.clear()
            self._lifetime_toggles = 0
            self._cache_dirty = False
            logger.info("Cache reset to initial state")

# Global cache instance
_cache_instance = None
_cache_lock = threading.Lock()

def get_cache_service() -> LampCacheService:
    """Get or create global cache service instance"""
    global _cache_instance
    
    if _cache_instance is None:
        with _cache_lock:
            if _cache_instance is None:
                _cache_instance = LampCacheService()
    
    return _cache_instance
