from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
import uvicorn
import os
import logging

# Import routers
from api import router as lamp_router

# Import database initialization
from database import init_database
from database.repository import LampRepository

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Response models
class HealthResponse(BaseModel):
    status: str
    message: str

# Configuration
class Settings(BaseModel):
    app_name: str = "Lamp Web App"
    debug: bool = False
    port: int = 8000

settings = Settings()

app = FastAPI(
    title=settings.app_name,
    description="An interactive lamp toggle with beautiful animations and persistent state",
    version="1.0.0"
)

@app.on_event("startup")
async def startup_event():
    """Initialize database on application startup"""
    try:
        logger.info("Initializing database...")
        init_database()
        logger.info("Database initialization completed")
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        # Don't prevent app startup, but log the error
        # In production, you might want to fail fast here

# Get the directory of the current file (src)
current_dir = os.path.dirname(os.path.abspath(__file__))

app.mount("/static", StaticFiles(directory=os.path.join(current_dir, "static")), name="static")
templates = Jinja2Templates(directory=os.path.join(current_dir, "templates"))

# Include routers
app.include_router(lamp_router)

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    """Render the main lamp interface."""
    try:
        return templates.TemplateResponse("index.html", {"request": request})
    except Exception as e:
        logger.error(f"Error rendering template: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/health")
async def health_check():
    """Comprehensive health check endpoint with database connectivity."""
    health_status = {
        "status": "healthy",
        "message": "Lamp app is running!",
        "services": {
            "api": "operational",
            "database": "unknown",
            "lamp_state": None
        }
    }
    
    try:
        # Test database connectivity
        repo = LampRepository()
        current_state = repo.get_current_state()
        
        health_status["services"]["database"] = "connected"
        health_status["services"]["lamp_state"] = "on" if current_state.is_on else "off"
        
        return health_status
        
    except Exception as e:
        logger.warning(f"Database health check failed: {e}")
        health_status["status"] = "degraded"
        health_status["message"] = "App running but database unavailable"
        health_status["services"]["database"] = "disconnected"
        
        # Return 200 for degraded state (app still works without DB for basic functionality)
        return health_status

@app.get("/dashboard")
async def dashboard():
    """Get comprehensive lamp dashboard data."""
    try:
        repo = LampRepository()
        dashboard_data = repo.get_dashboard_data()
        return dashboard_data
    except Exception as e:
        logger.error(f"Error getting dashboard data: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=settings.port, reload=settings.debug)
