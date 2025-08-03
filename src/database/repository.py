"""
Repository pattern for database operations using psycopg2
"""
import logging
from datetime import datetime, date, timedelta
from typing import Optional, List
import psycopg2
from .models import LampActivity, LampStatistics, CurrentLampState
from .models import LampActivityResponse, LampStatisticsResponse, CurrentLampStateResponse, LampDashboardResponse
from .database import db_config

logger = logging.getLogger(__name__)

class LampRepository:
    """Repository for lamp-related database operations using psycopg2"""

    def __init__(self):
        pass

    def get_current_state(self) -> CurrentLampState:
        """Get or create the current lamp state"""
        try:
            query = "SELECT id, is_on, last_updated, client_info FROM lamp_status WHERE id = 1"
            result = db_config.execute_query(query)

            if not result:
                # Create initial state if it doesn't exist
                insert_query = """
                INSERT INTO lamp_status (is_on, last_updated)
                VALUES (FALSE, CURRENT_TIMESTAMP)
                RETURNING id, is_on, last_updated, client_info
                """
                insert_result = db_config.execute_query(insert_query)
                if insert_result:
                    row = insert_result[0]
                    state = CurrentLampState(
                        id=row['id'],
                        is_on=bool(row['is_on']),
                        last_changed=row['last_updated'],
                        last_session_id=row['client_info'],
                        change_count=0
                    )
                    logger.info("Created initial lamp state")
                    return state
                else:
                    raise Exception("Failed to create initial lamp state")
            else:
                row = result[0]
                state = CurrentLampState(
                    id=row['id'],
                    is_on=bool(row['is_on']),
                    last_changed=row['last_updated'],
                    last_session_id=row['client_info'],
                    change_count=0  # We'll calculate this separately if needed
                )
                return state

        except Exception as e:
            logger.error(f"Error getting current state: {e}")
            raise

    def toggle_lamp(self, session_id: Optional[str] = None, user_agent: Optional[str] = None,
                   ip_address: Optional[str] = None) -> CurrentLampState:
        """Toggle the lamp state and record the activity"""
        try:
            # Get current state
            current_state = self.get_current_state()
            previous_state = "on" if current_state.is_on else "off"
            new_state = not current_state.is_on
            new_action = "on" if new_state else "off"

            # Update current state
            client_info = f"Session: {session_id or 'unknown'}, IP: {ip_address or 'unknown'}"
            update_query = """
            UPDATE lamp_status
            SET is_on = %s, last_updated = CURRENT_TIMESTAMP, client_info = %s
            WHERE id = 1
            """
            db_config.execute_command(update_query, (new_state, client_info))

            # Record activity (tables are created by database.py create_tables method)
            try:
                # Insert activity record
                insert_activity = """
                INSERT INTO lamp_activities (action, session_id, user_agent, ip_address, previous_state)
                VALUES (%s, %s, %s, %s, %s)
                """
                db_config.execute_command(insert_activity, (new_action, session_id, user_agent, ip_address, previous_state))

            except Exception as activity_error:
                logger.warning(f"Failed to record activity (but toggle succeeded): {activity_error}")

            # Update daily statistics (separate from activity recording)
            try:
                self._update_daily_stats(new_action, session_id or "unknown")
            except Exception as stats_error:
                logger.error(f"Failed to update daily statistics: {stats_error}")

            # Get updated state
            updated_state = self.get_current_state()

            logger.info(f"Lamp toggled to {new_action} (session: {session_id})")
            return updated_state

        except Exception as e:
            logger.error(f"Error toggling lamp: {e}")
            raise

    def _update_daily_stats(self, action: str, session_id: str):
        """Update daily statistics for today"""
        try:
            today = date.today()
            logger.info(f"Updating daily statistics for {today}, action: {action}, session: {session_id}")

            # Get or create today's stats
            query = """
            SELECT id, total_toggles, on_count, off_count, unique_sessions
            FROM lamp_statistics
            WHERE date = %s
            """
            results = db_config.execute_query(query, (today,))
            logger.debug(f"Existing stats query result: {results}")

            if results:
                # Update existing stats
                stats = results[0]
                new_toggles = stats['total_toggles'] + 1
                new_on_count = stats['on_count'] + (1 if action == "on" else 0)
                new_off_count = stats['off_count'] + (1 if action == "off" else 0)

                # Count unique sessions for today
                unique_query = """
                SELECT COUNT(DISTINCT session_id) as session_count
                FROM lamp_activities
                WHERE DATE(timestamp) = %s
                """
                unique_results = db_config.execute_query(unique_query, (today,))
                unique_sessions = unique_results[0]['session_count'] if unique_results else 1

                logger.info(f"Updating existing stats: toggles={new_toggles}, on={new_on_count}, off={new_off_count}, sessions={unique_sessions}")

                update_query = """
                UPDATE lamp_statistics
                SET total_toggles = %s, on_count = %s, off_count = %s, unique_sessions = %s, updated_at = CURRENT_TIMESTAMP
                WHERE date = %s
                """
                db_config.execute_command(update_query, (new_toggles, new_on_count, new_off_count, unique_sessions, today))

            else:
                # Create new stats entry for today
                on_count = 1 if action == "on" else 0
                off_count = 1 if action == "off" else 0

                logger.info(f"Creating new stats entry: toggles=1, on={on_count}, off={off_count}, sessions=1")

                insert_query = """
                INSERT INTO lamp_statistics (date, total_toggles, on_count, off_count, unique_sessions, total_on_duration_minutes)
                VALUES (%s, 1, %s, %s, 1, 0)
                """
                db_config.execute_command(insert_query, (today, on_count, off_count))

            logger.info(f"Successfully updated daily statistics for {today}")

        except Exception as e:
            logger.error(f"Error updating daily statistics: {e}")
            # Don't raise - statistics update failure shouldn't break the toggle operation

    def get_recent_activities(self, limit: int = 10) -> List[LampActivity]:
        """Get recent lamp activities"""
        try:
            query = """
            SELECT id, action, timestamp, session_id, user_agent, ip_address, previous_state
            FROM lamp_activities
            ORDER BY timestamp DESC
            LIMIT %s
            """
            results = db_config.execute_query(query, (limit,))

            activities = []
            for row in results:
                activity = LampActivity(
                    id=row['id'],
                    action=row['action'],
                    timestamp=row['timestamp'],
                    session_id=row['session_id'],
                    user_agent=row['user_agent'],
                    ip_address=row['ip_address'],
                    previous_state=row['previous_state']
                )
                activities.append(activity)

            return activities

        except Exception as e:
            logger.error(f"Error getting recent activities: {e}")
            return []  # Return empty list on error instead of raising

    def get_daily_statistics(self, target_date: Optional[date] = None) -> Optional[LampStatistics]:
        """Get statistics for a specific date (default: today)"""
        try:
            if not target_date:
                target_date = date.today()

            # Tables are created by database.py create_tables method

            # Try to get existing stats for the date
            query = """
            SELECT id, date, total_toggles, on_count, off_count, unique_sessions, total_on_duration_minutes
            FROM lamp_statistics
            WHERE date = %s
            """
            results = db_config.execute_query(query, (target_date,))

            if results:
                row = results[0]
                return LampStatistics(
                    id=row['id'],
                    date=row['date'],
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
        """Get total number of lamp toggles across all time"""
        try:
            query = "SELECT COUNT(*) as total FROM lamp_activities"
            results = db_config.execute_query(query)
            if results:
                return results[0]['total']
            return 0
        except Exception as e:
            logger.error(f"Error getting lifetime toggles: {e}")
            return 0

    def get_dashboard_data(self) -> LampDashboardResponse:
        """Get comprehensive dashboard data"""
        try:
            current_state = self.get_current_state()
            today_stats = self.get_daily_statistics()
            recent_activities = self.get_recent_activities(5)
            lifetime_toggles = self.get_total_lifetime_toggles()

            # Convert to response models
            current_state_response = CurrentLampStateResponse(
                is_on=current_state.is_on,
                last_changed=current_state.last_changed or datetime.now(),
                change_count=current_state.change_count
            )

            today_stats_response = None
            if today_stats:
                today_stats_response = LampStatisticsResponse(
                    id=today_stats.id,
                    date=today_stats.date,
                    total_toggles=today_stats.total_toggles,
                    on_count=today_stats.on_count,
                    off_count=today_stats.off_count,
                    unique_sessions=today_stats.unique_sessions,
                    total_on_duration_minutes=today_stats.total_on_duration_minutes
                )

            recent_activities_response = [
                LampActivityResponse(
                    id=activity.id,
                    action=activity.action,
                    timestamp=activity.timestamp,
                    session_id=activity.session_id,
                    previous_state=activity.previous_state
                ) for activity in recent_activities
            ]

            return LampDashboardResponse(
                current_state=current_state_response,
                today_stats=today_stats_response,
                recent_activities=recent_activities_response,
                total_lifetime_toggles=lifetime_toggles
            )

        except Exception as e:
            logger.error(f"Error getting dashboard data: {e}")
            raise
