"""
Local repository implementation using SQLite for development
"""
import logging
from datetime import datetime, date, timedelta
from typing import List, Optional
from dataclasses import dataclass
from .local_db import local_db

logger = logging.getLogger(__name__)

@dataclass
class LampState:
    id: int
    is_on: bool
    last_changed: datetime
    change_count: int
    updated_at: datetime

@dataclass  
class LampActivity:
    id: int
    action: str
    timestamp: datetime
    session_id: str
    user_agent: str
    ip_address: str
    previous_state: bool

@dataclass
class DailyStats:
    id: int
    date: date
    total_toggles: int
    on_count: int
    off_count: int
    unique_sessions: int
    total_on_duration_minutes: int

class LocalLampRepository:
    """Local SQLite-based repository for lamp data"""
    
    def get_current_state(self) -> LampState:
        """Get the current lamp state"""
        try:
            with local_db.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT id, is_on, last_changed, change_count, updated_at 
                    FROM current_lamp_state WHERE id = 1
                """)
                row = cursor.fetchone()
                
                if row:
                    return LampState(
                        id=row['id'],
                        is_on=bool(row['is_on']),
                        last_changed=datetime.fromisoformat(row['last_changed']),
                        change_count=row['change_count'],
                        updated_at=datetime.fromisoformat(row['updated_at'])
                    )
                else:
                    # Create initial state
                    cursor.execute("""
                        INSERT INTO current_lamp_state (id, is_on, change_count) 
                        VALUES (1, 0, 0)
                    """)
                    conn.commit()
                    return self.get_current_state()
                    
        except Exception as e:
            logger.error(f"Error getting current state: {e}")
            raise
    
    def toggle_lamp(self, session_id: str, user_agent: str = None, ip_address: str = None) -> LampState:
        """Toggle the lamp state and record the activity"""
        try:
            with local_db.get_connection() as conn:
                cursor = conn.cursor()
                
                # Get current state
                current_state = self.get_current_state()
                new_state = not current_state.is_on
                action = "on" if new_state else "off"
                
                # Update current state
                cursor.execute("""
                    UPDATE current_lamp_state 
                    SET is_on = ?, last_changed = ?, change_count = change_count + 1, updated_at = ?
                    WHERE id = 1
                """, (new_state, datetime.now().isoformat(), datetime.now().isoformat()))
                
                # Record activity
                cursor.execute("""
                    INSERT INTO lamp_activities (action, session_id, user_agent, ip_address, previous_state)
                    VALUES (?, ?, ?, ?, ?)
                """, (action, session_id, user_agent or "Unknown", ip_address or "127.0.0.1", current_state.is_on))
                
                # Update daily statistics
                self._update_daily_stats(cursor, action, session_id)
                
                conn.commit()
                
                # Return new state
                return self.get_current_state()
                
        except Exception as e:
            logger.error(f"Error toggling lamp: {e}")
            raise
    
    def _update_daily_stats(self, cursor, action: str, session_id: str):
        """Update daily statistics"""
        today = date.today().isoformat()
        
        # Get or create today's stats
        cursor.execute("SELECT * FROM lamp_statistics WHERE date = ?", (today,))
        stats = cursor.fetchone()
        
        if stats:
            # Update existing stats
            new_toggles = stats['total_toggles'] + 1
            new_on_count = stats['on_count'] + (1 if action == "on" else 0)
            new_off_count = stats['off_count'] + (1 if action == "off" else 0)
            
            # Count unique sessions
            cursor.execute("""
                SELECT COUNT(DISTINCT session_id) 
                FROM lamp_activities 
                WHERE DATE(timestamp) = ?
            """, (today,))
            unique_sessions = cursor.fetchone()[0]
            
            cursor.execute("""
                UPDATE lamp_statistics 
                SET total_toggles = ?, on_count = ?, off_count = ?, unique_sessions = ?, updated_at = ?
                WHERE date = ?
            """, (new_toggles, new_on_count, new_off_count, unique_sessions, datetime.now().isoformat(), today))
        else:
            # Create new stats
            on_count = 1 if action == "on" else 0
            off_count = 1 if action == "off" else 0
            
            cursor.execute("""
                INSERT INTO lamp_statistics (date, total_toggles, on_count, off_count, unique_sessions)
                VALUES (?, 1, ?, ?, 1)
            """, (today, on_count, off_count))
    
    def get_recent_activities(self, limit: int = 10) -> List[LampActivity]:
        """Get recent lamp activities"""
        try:
            with local_db.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT id, action, timestamp, session_id, user_agent, ip_address, previous_state
                    FROM lamp_activities 
                    ORDER BY timestamp DESC 
                    LIMIT ?
                """, (limit,))
                
                activities = []
                for row in cursor.fetchall():
                    activities.append(LampActivity(
                        id=row['id'],
                        action=row['action'],
                        timestamp=datetime.fromisoformat(row['timestamp']),
                        session_id=row['session_id'],
                        user_agent=row['user_agent'],
                        ip_address=row['ip_address'],
                        previous_state=bool(row['previous_state']) if row['previous_state'] is not None else None
                    ))
                
                return activities
                
        except Exception as e:
            logger.error(f"Error getting recent activities: {e}")
            return []
    
    def get_daily_statistics(self, target_date: date = None) -> Optional[DailyStats]:
        """Get daily statistics for a specific date (defaults to today)"""
        if target_date is None:
            target_date = date.today()
            
        try:
            with local_db.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT id, date, total_toggles, on_count, off_count, unique_sessions, total_on_duration_minutes
                    FROM lamp_statistics 
                    WHERE date = ?
                """, (target_date.isoformat(),))
                
                row = cursor.fetchone()
                if row:
                    return DailyStats(
                        id=row['id'],
                        date=date.fromisoformat(row['date']),
                        total_toggles=row['total_toggles'],
                        on_count=row['on_count'],
                        off_count=row['off_count'],
                        unique_sessions=row['unique_sessions'],
                        total_on_duration_minutes=row['total_on_duration_minutes']
                    )
                return None
                
        except Exception as e:
            logger.error(f"Error getting daily statistics: {e}")
            return None
    
    def get_total_lifetime_toggles(self) -> int:
        """Get total lifetime toggles across all days"""
        try:
            with local_db.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT SUM(total_toggles) FROM lamp_statistics")
                result = cursor.fetchone()[0]
                return result or 0
        except Exception as e:
            logger.error(f"Error getting lifetime toggles: {e}")
            return 0
    
    def get_dashboard_data(self) -> dict:
        """Get comprehensive dashboard data"""
        try:
            current_state = self.get_current_state()
            today_stats = self.get_daily_statistics()
            recent_activities = self.get_recent_activities(5)
            lifetime_toggles = self.get_total_lifetime_toggles()
            
            return {
                "current_state": {
                    "is_on": current_state.is_on,
                    "last_changed": current_state.last_changed.isoformat(),
                    "change_count": current_state.change_count
                },
                "today_stats": {
                    "total_toggles": today_stats.total_toggles if today_stats else 0,
                    "on_count": today_stats.on_count if today_stats else 0,
                    "off_count": today_stats.off_count if today_stats else 0,
                    "unique_sessions": today_stats.unique_sessions if today_stats else 0
                } if today_stats else None,
                "total_lifetime_toggles": lifetime_toggles,
                "recent_activities": [
                    {
                        "id": activity.id,
                        "action": activity.action,
                        "timestamp": activity.timestamp.isoformat(),
                        "session_id": activity.session_id
                    } for activity in recent_activities
                ]
            }
            
        except Exception as e:
            logger.error(f"Error getting dashboard data: {e}")
            raise
