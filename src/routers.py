"""
API router for lamp-related endpoints
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import os

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
    return LampStatusResponse(**lamp_state.to_dict())

@router.post("/lamp/toggle", response_model=LampActionResponse)
async def toggle_lamp():
    """Toggle the lamp on/off (deprecated - use specific endpoints)."""
    previous_status = "on" if lamp_state.is_on else "off"
    lamp_state.toggle()
    response_data = lamp_state.to_dict()
    response_data["message"] = f"Lamp toggled from {previous_status} to {response_data['status']}"
    response_data["previous_status"] = previous_status
    return LampActionResponse(**response_data)

@router.post("/lamp/toggle/on", response_model=LampActionResponse)
async def turn_lamp_on():
    """Turn the lamp on."""
    previous_status = "on" if lamp_state.is_on else "off"
    
    if lamp_state.is_on:
        response_data = lamp_state.to_dict()
        response_data["message"] = "Lamp is already on"
        response_data["previous_status"] = previous_status
        return LampActionResponse(**response_data)
    
    lamp_state.is_on = True
    response_data = lamp_state.to_dict()
    response_data["message"] = "Lamp turned on"
    response_data["previous_status"] = previous_status
    return LampActionResponse(**response_data)

@router.post("/lamp/toggle/off", response_model=LampActionResponse)
async def turn_lamp_off():
    """Turn the lamp off."""
    previous_status = "on" if lamp_state.is_on else "off"
    
    if not lamp_state.is_on:
        response_data = lamp_state.to_dict()
        response_data["message"] = "Lamp is already off"
        response_data["previous_status"] = previous_status
        return LampActionResponse(**response_data)
    
    lamp_state.is_on = False
    response_data = lamp_state.to_dict()
    response_data["message"] = "Lamp turned off"
    response_data["previous_status"] = previous_status
    return LampActionResponse(**response_data)
