"""
Lamp Web App: one lamp shared by everyone with the page open.

Pulling the cord is a POST; every open page hears about it over Server-Sent Events.
"""

import asyncio
import logging
import os
import socket
import time
from contextlib import asynccontextmanager, suppress
from datetime import timedelta
from pathlib import Path
from typing import Any, AsyncIterator, Optional

import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from fastapi.sse import EventSourceResponse
from fastapi.staticfiles import StaticFiles

from store import Snapshot, Store, TooSoon

# Configure logging
logging.basicConfig(level=logging.INFO)
logging.getLogger("azure").setLevel(
    logging.WARNING
)  # it logs every token request at INFO
logger = logging.getLogger(__name__)

# Two toggles a second at most: a shared full-screen light must never strobe (WCAG 2.3.1),
# and it caps how fast anyone can grow the activity log. The database enforces it, so
# the limit is for the lamp, not for each replica.
TOGGLE_COOLDOWN_SECONDS = 0.5
SNAPSHOT_TTL_SECONDS = 15
MAX_VIEWERS = 2000
# How often a replica with viewers checks the database for pulls made on other replicas.
SYNC_SECONDS = 1.0
REPLICA = f"{socket.gethostname()}-{os.getpid()}"[-64:]  # the pod name, on Kubernetes


class Hub:
    """
    Holds the latest lamp snapshot and wakes every open event stream when it changes.

    Every replica has its own hub. catch_up() below is what keeps them in agreement.
    """

    def __init__(self) -> None:
        self.snapshot: Optional[Snapshot] = None
        self.viewers = 0  # streams open on this replica
        self.elsewhere = 0  # streams open on the others, as of the last catch-up
        self.reported = 0  # what this replica last told the database it had
        self.checked_at = float("-inf")
        self.toggled_at = float("-inf")
        self.refreshing = asyncio.Lock()
        self._changed = asyncio.Event()

    @property
    def room(self) -> int:
        """Everyone watching the lamp, whichever replica they landed on"""
        return self.viewers + self.elsewhere

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
                current = (snapshot, self.room)
                if snapshot is not None and current != sent:
                    sent = current
                    yield snapshot.model_copy(update={"viewers": self.room})
                    continue  # the lamp may have changed while that event was being written
                # Streams only hold the latest state, so a slow client skips ahead instead of
                # queueing. Timing out is expected: it is what picks up people arriving and leaving.
                with suppress(asyncio.TimeoutError):
                    await asyncio.wait_for(self._changed.wait(), timeout=2)
        finally:
            self.viewers -= 1


store = Store()
hub = Hub()


async def catch_up(idle_too: bool = False) -> bool:
    """
    Bring this replica level with the others. They share nothing but the database, so
    each one asks it: has the lamp changed, and how many are watching elsewhere?
    Returns False when there was no need to ask.
    """
    viewers = hub.viewers
    if not (idle_too or viewers or hub.reported):
        return False  # nobody here to tell, and no count of ours left to take back
    changed_at, room = await asyncio.to_thread(store.pulse, REPLICA, viewers)
    hub.reported = viewers
    hub.elsewhere = max(0, room - viewers)
    if hub.snapshot is None or (changed_at and changed_at != hub.snapshot.changed_at):
        hub.publish(await asyncio.to_thread(store.snapshot))  # a pull made elsewhere
    # Not before the lamp's state is in: until then a request has to ask for itself,
    # or it finds no state and a recent check, and reports the lamp unreachable.
    hub.checked_at = time.monotonic()
    return True


async def keep_in_step() -> None:
    """
    Runs for the life of the process, so that no request ever waits on the database:
    once a second while this replica has viewers, and once per TTL while it has none.
    """
    # ponytail: polling, one small transaction per replica per second while it has
    # viewers. Postgres LISTEN/NOTIFY would make it instant once that load matters.
    reachable = True
    while True:
        idle_check_due = time.monotonic() - hub.checked_at > SNAPSHOT_TTL_SECONDS
        try:
            if await catch_up(idle_too=idle_check_due) and not reachable:
                logger.info("Database is reachable again")
                reachable = True
        except Exception as e:
            if reachable:
                logger.warning(
                    f"Database unavailable, serving the last known lamp state: {e}"
                )
            reachable = False
        await asyncio.sleep(SYNC_SECONDS)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    in_step = asyncio.create_task(keep_in_step())
    yield
    in_step.cancel()
    with suppress(Exception):
        await asyncio.to_thread(store.leave, REPLICA)


app = FastAPI(
    title="Lamp Web App",
    description="A lamp with a pull cord, shared live by everyone looking at it",
    version="2.0.0",
    lifespan=lifespan,
    # OpenTelemetry is on by default and exports only where FASTAPI_OTEL_AUTO_CONFIGURE and
    # OTEL_EXPORTER_OTLP_* point it. Health probes would be most of the traffic, and say nothing.
    telemetry={"exclude": lambda scope: scope["path"] == "/livez"},
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Return a generic 500 response and log the real error server-side."""
    logger.exception("Unhandled exception on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


async def current_snapshot() -> Snapshot:
    """The lamp as this replica last saw it. keep_in_step() is what keeps that fresh."""
    if hub.snapshot is None:
        # Nothing seen yet: a replica that has just started, or one that has never
        # reached the database. One request at a time gets to try; the rest are told no.
        async with hub.refreshing:
            if (
                hub.snapshot is None
                and time.monotonic() - hub.checked_at > SYNC_SECONDS
            ):
                hub.checked_at = time.monotonic()
                with suppress(Exception):
                    await catch_up(idle_too=True)
    if hub.snapshot is None:
        raise HTTPException(status_code=503, detail="The lamp is unreachable right now")
    return hub.snapshot.model_copy(update={"viewers": hub.room})


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
    too_soon = HTTPException(status_code=429, detail="Someone just pulled the cord")
    now = time.monotonic()
    if now - hub.toggled_at < TOGGLE_COOLDOWN_SECONDS:
        raise too_soon  # this replica already knows, without asking the database
    hub.toggled_at = now

    # Headers are untrusted: clip them to the column sizes before they reach the database.
    try:
        snapshot = await asyncio.to_thread(
            store.toggle,
            request.headers.get("X-Session-ID", "")[:100] or None,
            request.headers.get("User-Agent", "")[:500] or None,
            request.client.host if request.client else None,
            timedelta(seconds=TOGGLE_COOLDOWN_SECONDS),
        )
    except TooSoon:
        raise too_soon from None  # another replica took a pull a moment ago
    hub.publish(snapshot)
    with suppress(Exception):
        await catch_up(
            idle_too=True
        )  # this replica may have no viewers of its own to count
    return (hub.snapshot or snapshot).model_copy(update={"viewers": hub.room})


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


@app.get("/livez", include_in_schema=False)
async def alive() -> dict[str, str]:
    """
    For health probes: answers whenever the process can, whatever the database is doing.
    A probe that waits on the database gets a healthy app restarted when the database is slow.
    """
    return {"status": "alive"}


@app.get("/health", response_model=dict)
async def health_check() -> dict[str, str]:
    """For people and dashboards: stays 200 while the process is up, and says whether the database answers."""
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
