"""
Lamp Web App: one lamp shared by everyone with the page open.

Pulling the cord is a POST; every open page hears about it over Server-Sent Events.
"""

import asyncio
import logging
import os
import time
from contextlib import asynccontextmanager, suppress
from pathlib import Path
from typing import Any, AsyncIterator, Optional

import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from fastapi.sse import EventSourceResponse
from fastapi.staticfiles import StaticFiles

from store import Snapshot, Store

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Two toggles a second at most: a shared full-screen light must never strobe (WCAG 2.3.1),
# and it caps how fast anyone can grow the activity log.
TOGGLE_COOLDOWN_SECONDS = 0.5
SNAPSHOT_TTL_SECONDS = 15
MAX_VIEWERS = 2000


class Hub:
    """
    Holds the latest lamp snapshot and wakes every open event stream when it changes.

    ponytail: lives in this process, which matches the single App Service worker in
    infra/. Scaling out needs a shared bus (Postgres LISTEN/NOTIFY) behind publish().
    """

    def __init__(self) -> None:
        self.snapshot: Optional[Snapshot] = None
        self.viewers = 0
        self.checked_at = float("-inf")
        self.toggled_at = float("-inf")
        self.refreshing = asyncio.Lock()
        self._changed = asyncio.Event()

    def publish(self, snapshot: Snapshot) -> None:
        self.snapshot = snapshot
        self._changed.set()
        self._changed = asyncio.Event()

    async def subscribe(self) -> AsyncIterator[Snapshot]:
        """Yield the lamp now, then again whenever it or the viewer count changes"""
        self.viewers += 1
        try:
            sent = None
            while True:
                snapshot = self.snapshot
                current = (snapshot, self.viewers)
                if snapshot is not None and current != sent:
                    sent = current
                    yield snapshot.model_copy(update={"viewers": self.viewers})
                    continue  # the lamp may have changed while that event was being written
                # Streams only hold the latest state, so a slow client skips ahead instead of
                # queueing. Timing out is expected: it is what picks up people arriving and leaving.
                with suppress(asyncio.TimeoutError):
                    await asyncio.wait_for(self._changed.wait(), timeout=2)
        finally:
            self.viewers -= 1


store = Store()
hub = Hub()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Connect to the database at startup so problems show up in the boot log"""
    try:
        await asyncio.to_thread(store.ping)
    except Exception as e:
        logger.warning(f"Database not reachable at startup, will retry on demand: {e}")
    yield


app = FastAPI(
    title="Lamp Web App",
    description="A lamp with a pull cord, shared live by everyone looking at it",
    version="2.0.0",
    lifespan=lifespan,
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Return a generic 500 response and log the real error server-side."""
    logger.exception("Unhandled exception on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


async def current_snapshot() -> Snapshot:
    """The lamp as last seen, re-read from the database once it is older than the TTL."""
    async with hub.refreshing:
        if time.monotonic() - hub.checked_at > SNAPSHOT_TTL_SECONDS:
            hub.checked_at = time.monotonic()
            try:
                hub.publish(await asyncio.to_thread(store.snapshot))
            except Exception as e:
                logger.warning(
                    f"Database unavailable, serving the last known lamp state: {e}"
                )
    if hub.snapshot is None:
        raise HTTPException(status_code=503, detail="The lamp is unreachable right now")
    return hub.snapshot.model_copy(update={"viewers": hub.viewers})


def room_has_space() -> None:
    if hub.viewers >= MAX_VIEWERS:
        raise HTTPException(status_code=503, detail="The room is full")


@app.get("/api/v1/lamp/status", response_model=Snapshot, tags=["lamp"])
async def get_lamp_status(snapshot: Snapshot = Depends(current_snapshot)) -> Snapshot:
    """Get the lamp state and its usage counters."""
    return snapshot


@app.post("/api/v1/lamp/toggle", response_model=Snapshot, tags=["lamp"])
async def toggle_lamp(request: Request) -> Snapshot:
    """Pull the cord, for everyone."""
    now = time.monotonic()
    if now - hub.toggled_at < TOGGLE_COOLDOWN_SECONDS:
        raise HTTPException(status_code=429, detail="Someone just pulled the cord")
    hub.toggled_at = now

    # Headers are untrusted: clip them to the column sizes before they reach the database.
    snapshot = await asyncio.to_thread(
        store.toggle,
        request.headers.get("X-Session-ID", "")[:100] or None,
        request.headers.get("User-Agent", "")[:500] or None,
        request.client.host if request.client else None,
    )
    hub.checked_at = now
    hub.publish(snapshot)
    return snapshot.model_copy(update={"viewers": hub.viewers})


@app.get(
    "/api/v1/lamp/events",
    response_class=EventSourceResponse,
    dependencies=[Depends(room_has_space), Depends(current_snapshot)],
    tags=["lamp"],
)
async def lamp_events() -> AsyncIterator[Snapshot]:
    """Stream the lamp: one event immediately, then one per change."""
    async for snapshot in hub.subscribe():
        yield snapshot


@app.get("/health", response_model=dict)
async def health_check() -> dict[str, str]:
    """Liveness for Docker and App Service. Stays 200 while the process is up; flags a lost database."""
    try:
        return {"status": "healthy", "database": await asyncio.to_thread(store.ping)}
    except Exception as e:
        logger.warning(f"Health check could not reach the database: {e}")
        return {"status": "degraded", "database": "unreachable"}


class Frontend(StaticFiles):
    """The page and its assets, revalidated on every load so a deploy never pairs old JS with new HTML."""

    def file_response(self, *args: Any, **kwargs: Any) -> Response:
        response = super().file_response(*args, **kwargs)
        response.headers["Cache-Control"] = "no-cache"
        response.headers["Content-Security-Policy"] = "default-src 'self'"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response


# Mounted last so the routes above win.
app.mount(
    "/", Frontend(directory=Path(__file__).parent / "static", html=True), name="static"
)

if __name__ == "__main__":
    # Open event streams never finish on their own; without the timeout a deploy would hang on them.
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        timeout_graceful_shutdown=3,
    )
