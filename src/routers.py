"""
API router for lamp-related endpoints
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import os
import re

router = APIRouter(prefix="/api/v1", tags=["lamp"])

# Lamp state (in production, you'd use a database)
class LampState:
    def __init__(self):
        self.is_on = False
    
    def toggle(self):
        self.is_on = not self.is_on
        return self
    
    def to_dict(self):
        return {
            "status": "on" if self.is_on else "off",
            "is_on": self.is_on
        }

# Global lamp state
lamp_state = LampState()

# Response models
class LampStatusResponse(BaseModel):
    status: str
    is_on: bool

class LampActionResponse(BaseModel):
    status: str
    is_on: bool
    message: str
    previous_status: str

@router.get("/lamp/status", response_model=LampStatusResponse)
async def get_lamp_status():
    """Get the current lamp status."""
    try:
        if lamp_state is None:
            raise HTTPException(status_code=404, detail="Lamp not found or not initialized")
        
        return LampStatusResponse(**lamp_state.to_dict())
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.post("/lamp/toggle", response_model=LampActionResponse)
async def toggle_lamp():
    """Toggle the lamp on/off (deprecated - use specific endpoints)."""
    try:
        if lamp_state is None:
            raise HTTPException(status_code=404, detail="Lamp not found or not initialized")
        
        previous_status = "on" if lamp_state.is_on else "off"
        lamp_state.toggle()
        response_data = lamp_state.to_dict()
        response_data["message"] = f"Lamp toggled from {previous_status} to {response_data['status']}"
        response_data["previous_status"] = previous_status
        return LampActionResponse(**response_data)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.post("/lamp/toggle/on", response_model=LampActionResponse)
async def turn_lamp_on():
    """Turn the lamp on."""
    try:
        if lamp_state is None:
            raise HTTPException(status_code=404, detail="Lamp not found or not initialized")
        
        previous_status = "on" if lamp_state.is_on else "off"
        
        # Check if lamp is already in the requested state (could be 409 Conflict)
        if lamp_state.is_on:
            raise HTTPException(
                status_code=409, 
                detail="Lamp is already on. No action needed."
            )
        
        lamp_state.is_on = True
        response_data = lamp_state.to_dict()
        response_data["message"] = "Lamp turned on successfully"
        response_data["previous_status"] = previous_status
        return LampActionResponse(**response_data)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.post("/lamp/toggle/off", response_model=LampActionResponse)
async def turn_lamp_off():
    """Turn the lamp off."""
    try:
        if lamp_state is None:
            raise HTTPException(status_code=404, detail="Lamp not found or not initialized")
        
        previous_status = "on" if lamp_state.is_on else "off"
        
        # Check if lamp is already in the requested state (could be 409 Conflict)
        if not lamp_state.is_on:
            raise HTTPException(
                status_code=409, 
                detail="Lamp is already off. No action needed."
            )
        
        lamp_state.is_on = False
        response_data = lamp_state.to_dict()
        response_data["message"] = "Lamp turned off successfully"
        response_data["previous_status"] = previous_status
        return LampActionResponse(**response_data)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

# Additional error handling endpoints
@router.post("/lamp/validate/{action}")
async def validate_lamp_action(action: str):
    """Validate lamp actions with proper error responses."""
    valid_actions = ["on", "off", "toggle", "status"]
    
    if action not in valid_actions:
        raise HTTPException(
            status_code=400, 
            detail=f"Invalid action '{action}'. Valid actions are: {', '.join(valid_actions)}"
        )
    
    if action == "status":
        raise HTTPException(
            status_code=422, 
            detail="Status is not an action. Use GET /lamp/status instead."
        )
    
    return {"message": f"Action '{action}' is valid", "valid_actions": valid_actions}

# Additional endpoints demonstrating various HTTP status codes
@router.post("/lamp/brightness/{level}")
async def set_lamp_brightness(level: int):
    """Set lamp brightness (demonstrates validation and range checking)."""
    # 400 Bad Request for invalid input
    if level < 0 or level > 100:
        raise HTTPException(
            status_code=400, 
            detail="Brightness level must be between 0 and 100"
        )
    
    # 403 Forbidden if lamp is off
    if not lamp_state.is_on:
        raise HTTPException(
            status_code=403, 
            detail="Cannot set brightness: lamp is currently off"
        )
    
    # 422 Unprocessable Entity for semantic validation
    if level == 0:
        raise HTTPException(
            status_code=422, 
            detail="Setting brightness to 0 is not allowed. Use /lamp/toggle/off instead."
        )
    
    # 201 Created for successful creation of new state
    return {"message": f"Lamp brightness set to {level}%", "brightness": level}, 201

@router.delete("/lamp/reset")
async def reset_lamp():
    """Reset lamp to default state (demonstrates DELETE with different responses)."""
    if lamp_state is None:
        raise HTTPException(status_code=404, detail="Lamp not found")
    
    # 204 No Content for successful deletion/reset with no response body
    lamp_state.is_on = False
    return None, 204

@router.put("/lamp/config")
async def update_lamp_config(config: dict):
    """Update lamp configuration (demonstrates PUT method)."""
    if not config:
        raise HTTPException(status_code=400, detail="Configuration cannot be empty")
    
    # 405 Method Not Allowed for unsupported operations
    if "factory_reset" in config:
        raise HTTPException(
            status_code=405, 
            detail="Factory reset not allowed via this endpoint"
        )
    
    # 202 Accepted for async processing
    return {"message": "Configuration update accepted", "config": config}, 202

@router.get("/lamp/history")
async def get_lamp_history():
    """Get lamp usage history (demonstrates different success scenarios)."""
    # Simulate no history available
    history = []
    
    if not history:
        # 204 No Content when no data is available
        return None, 204
    
    # 200 OK with data (default)
    return {"history": history}

@router.post("/lamp/schedule")
async def schedule_lamp_action(schedule_time: str, action: str):
    """Schedule a lamp action (demonstrates various validation scenarios)."""
    
    # 400 Bad Request for malformed input
    if not re.match(r'^\d{2}:\d{2}$', schedule_time):
        raise HTTPException(
            status_code=400, 
            detail="Time must be in HH:MM format"
        )
    
    valid_actions = ["on", "off", "toggle"]
    if action not in valid_actions:
        raise HTTPException(
            status_code=400, 
            detail=f"Invalid action. Must be one of: {valid_actions}"
        )
    
    # 409 Conflict if schedule already exists
    # (In real app, you'd check against a database)
    existing_schedule = False  # Simulate check
    if existing_schedule:
        raise HTTPException(
            status_code=409, 
            detail=f"Schedule already exists for {schedule_time}"
        )
    
    # Remove the unreachable validation for now
    # schedule_count = 0  # Simulate count
    # if schedule_count >= 10:
    #     raise HTTPException(
    #         status_code=429, 
    #         detail="Maximum number of schedules (10) exceeded. Please remove some schedules first."
    #     )
    
    # 201 Created for successful schedule creation
    return {
        "message": f"Lamp scheduled to {action} at {schedule_time}",
        "schedule_time": schedule_time,
        "action": action
    }, 201
