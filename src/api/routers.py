"""
API router for lamp-related endpoints with database persistence
"""
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
from typing import Optional, List
import logging
import uuid

# Database imports
from database.ha_repository import HALampRepository
from database.models import (
    LampActivityResponse, 
    LampStatisticsResponse, 
    CurrentLampStateResponse, 
    LampDashboardResponse
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1", tags=["lamp"])

# Response models for backward compatibility
class LampStatusResponse(BaseModel):
    status: str
    is_on: bool

class LampActionResponse(BaseModel):
    status: str
    is_on: bool
    message: str
    previous_status: str

def get_client_info(request: Request) -> tuple:
    """Extract client information from request"""
    session_id = request.headers.get("X-Session-ID") or str(uuid.uuid4())
    user_agent = request.headers.get("User-Agent", "Unknown")
    ip_address = request.client.host if request.client else "Unknown"
    return session_id, user_agent, ip_address

@router.get("/lamp/status", response_model=LampStatusResponse)
async def get_lamp_status():
    """Get the current lamp status from HA repository."""
    try:
        repo = HALampRepository()
        current_state = repo.get_current_state()
        
        return LampStatusResponse(
            status="on" if current_state.is_on else "off",
            is_on=current_state.is_on
        )
    except Exception as e:
        logger.error(f"Error getting lamp status: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.post("/lamp/toggle", response_model=LampActionResponse)
async def toggle_lamp(request: Request):
    """Toggle the lamp state using HA repository."""
    try:
        repo = HALampRepository()
        session_id, user_agent, ip_address = get_client_info(request)
        
        # Get current state before toggle
        current_state = repo.get_current_state()
        previous_status = "on" if current_state.is_on else "off"
        
        # Toggle the lamp
        new_state = repo.toggle_lamp(session_id, user_agent, ip_address)
        new_status = "on" if new_state.is_on else "off"
        
        message = f"Lamp turned {new_status} successfully!"
        
        return LampActionResponse(
            status=new_status,
            is_on=new_state.is_on,
            message=message,
            previous_status=previous_status
        )
    except Exception as e:
        logger.error(f"Error toggling lamp: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.get("/lamp/dashboard", response_model=LampDashboardResponse)
async def get_lamp_dashboard():
    """Get comprehensive lamp dashboard data using HA repository."""
    try:
        repo = HALampRepository()
        dashboard_data = repo.get_dashboard_data()
        return dashboard_data
    except Exception as e:
        logger.error(f"Error getting dashboard data: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.get("/lamp/activities", response_model=List[LampActivityResponse])
async def get_recent_activities(limit: int = 10):
    """Get recent lamp activities using HA repository."""
    try:
        if limit > 100:  # Prevent excessive data retrieval
            limit = 100
            
        repo = HALampRepository()
        activities = repo.get_recent_activities(limit)
        
        return [
            LampActivityResponse(
                id=activity.id,
                action=activity.action,
                timestamp=activity.timestamp,
                session_id=activity.session_id,
                previous_state=activity.previous_state
            ) for activity in activities
        ]
    except Exception as e:
        logger.error(f"Error getting recent activities: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.get("/lamp/statistics/today", response_model=Optional[LampStatisticsResponse])
async def get_today_statistics():
    """Get today's lamp usage statistics using HA repository."""
    try:
        repo = HALampRepository()
        stats = repo.get_daily_statistics()
        
        if not stats:
            return None
            
        return LampStatisticsResponse(
            id=stats.id,
            date=stats.date,
            total_toggles=stats.total_toggles,
            on_count=stats.on_count,
            off_count=stats.off_count,
            unique_sessions=stats.unique_sessions,
            total_on_duration_minutes=stats.total_on_duration_minutes
        )
    except Exception as e:
        logger.error(f"Error getting today's statistics: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.get("/lamp/sync-status")
async def get_sync_status():
    """Get current sync status between cache and database."""
    try:
        repo = HALampRepository()
        sync_status = repo.get_sync_status()
        return sync_status
    except Exception as e:
        logger.error(f"Error getting sync status: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")
