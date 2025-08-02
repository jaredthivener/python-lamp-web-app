"""
Database models for the Lamp Web App using pyodbc
"""
from datetime import datetime
from typing import Optional
from dataclasses import dataclass
from pydantic import BaseModel

@dataclass
class LampActivity:
    """
    Data class for lamp toggle activities
    """
    id: int
    action: str  # 'on' or 'off'
    timestamp: datetime
    session_id: Optional[str] = None
    user_agent: Optional[str] = None
    ip_address: Optional[str] = None
    previous_state: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

@dataclass
class LampStatistics:
    """
    Data class for aggregated lamp usage statistics
    """
    id: int
    date: datetime
    total_toggles: int = 0
    on_count: int = 0
    off_count: int = 0
    unique_sessions: int = 0
    total_on_duration_minutes: int = 0
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

@dataclass
class CurrentLampState:
    """
    Data class for the current state of the lamp
    """
    id: int = 1  # Always 1 - single row table
    is_on: bool = False
    last_changed: Optional[datetime] = None
    last_session_id: Optional[str] = None
    change_count: int = 0
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

# Pydantic models for API responses
class LampActivityResponse(BaseModel):
    """Response model for lamp activity records"""
    id: int
    action: str
    timestamp: datetime
    session_id: Optional[str]
    previous_state: Optional[str]
    
    class Config:
        from_attributes = True

class LampStatisticsResponse(BaseModel):
    """Response model for lamp statistics"""
    id: int
    date: datetime
    total_toggles: int
    on_count: int
    off_count: int
    unique_sessions: int
    total_on_duration_minutes: int
    
    class Config:
        from_attributes = True

class CurrentLampStateResponse(BaseModel):
    """Response model for current lamp state"""
    is_on: bool
    last_changed: datetime
    change_count: int
    
    class Config:
        from_attributes = True

class LampDashboardResponse(BaseModel):
    """Response model for lamp dashboard with comprehensive stats"""
    current_state: CurrentLampStateResponse
    today_stats: Optional[LampStatisticsResponse]
    recent_activities: list[LampActivityResponse]
    total_lifetime_toggles: int
    
    class Config:
        from_attributes = True
