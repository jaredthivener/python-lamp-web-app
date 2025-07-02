from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
import uvicorn
import os
import logging

# Import routers
from routers import router as lamp_router

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
    description="An interactive lamp toggle with beautiful animations",
    version="1.0.0"
)

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

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    try:
        return HealthResponse(status="healthy", message="Lamp app is running!")
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail="Health check failed")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=settings.port, reload=settings.debug)
