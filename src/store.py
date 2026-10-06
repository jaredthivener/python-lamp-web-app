"""
The lamp's state and activity log.

Postgres in production; a local SQLite file when no connection string is configured.
Everything replicas need to agree on lives here, so any number of them can run.
"""

import logging
import os
import tempfile
import threading
from datetime import datetime, timedelta, timezone
from functools import cache
from pathlib import Path
from typing import Any, Optional

import psycopg2  # type: ignore[import-untyped]
from azure.identity import DefaultAzureCredential
from psycopg2.extensions import parse_dsn  # type: ignore[import-untyped]
from pydantic import BaseModel, computed_field
from sqlalchemy import Boolean, Column, DateTime, Integer, MetaData, String, Table, Text
from sqlalchemy import create_engine, delete, func, insert, select, true, update
from sqlalchemy.engine import Engine

logger = logging.getLogger(__name__)

# Table and column names match the schema already deployed, so no migration is needed.
metadata = MetaData()
lamp_status = Table(
    "lamp_status",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("is_on", Boolean, nullable=False, default=False),
    Column("last_updated", DateTime(timezone=True)),
    Column("client_info", Text),
)
lamp_activities = Table(
    "lamp_activities",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("action", String(10), nullable=False),
    Column("timestamp", DateTime(timezone=True)),
    Column("session_id", String(100)),
    Column("user_agent", Text),
    Column("ip_address", String(45)),
    Column("previous_state", String(10)),
)
# One row per running replica: how many event streams it has open, and when it last said so.
lamp_viewers = Table(
    "lamp_viewers",
    metadata,
    Column("replica", String(64), primary_key=True),
    Column("viewers", Integer, nullable=False),
    Column("seen_at", DateTime(timezone=True), nullable=False),
)

# A replica that has not reported for this long is gone, and its viewers with it.
REPLICA_SILENCE = timedelta(seconds=5)
ENTRA_POSTGRES_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"


class Activity(BaseModel):
    """One pull of the cord"""

    action: str  # 'on' or 'off'
    at: datetime


class Snapshot(BaseModel):
    """Everything the page shows about the lamp"""

    is_on: bool
    changed_at: datetime
    today: int
    lifetime: int
    visitors_today: int
    recent: list[Activity]
    viewers: int = 0

    @computed_field  # type: ignore[prop-decorator]
    @property
    def status(self) -> str:
        return "on" if self.is_on else "off"


class TooSoon(Exception):
    """The lamp was switched less than the cooldown ago, by anyone, on any replica"""


def _utc(value: datetime) -> datetime:
    """SQLite hands back naive datetimes; everything stored here is UTC."""
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


@cache
def _azure_identity() -> DefaultAzureCredential:
    return DefaultAzureCredential()  # one instance, so the tokens it fetches are cached


def _connect(dsn: str) -> Any:
    """Open a Postgres connection. psycopg2 takes URLs and "host=... dbname=..." alike."""
    params = parse_dsn(dsn)
    azure = params.get("host", "").endswith(".postgres.database.azure.com")
    if azure and "password" not in params:
        # Passwordless: this process's Azure identity (the pod's workload identity on AKS)
        # signs in with a short-lived token. Only new connections need one.
        params["password"] = _azure_identity().get_token(ENTRA_POSTGRES_SCOPE).token
    return psycopg2.connect(**{"connect_timeout": 5, **params})


def _create_engine() -> Engine:
    dsn = os.getenv("POSTGRES_CONNECTION_STRING")
    if dsn:
        return create_engine(
            "postgresql+psycopg2://", creator=lambda: _connect(dsn), pool_pre_ping=True
        )
    path = Path(tempfile.gettempdir()) / "lamp.db"
    logger.warning("No POSTGRES_CONNECTION_STRING set; using SQLite at %s", path)
    return create_engine(f"sqlite:///{path}")


class Store:
    """Reads and flips the lamp. Connects on first use, so the app boots even if the database is down."""

    def __init__(self, engine: Optional[Engine] = None) -> None:
        self._engine = engine
        self._ready = False
        self._lock = threading.Lock()

    @property
    def engine(self) -> Engine:
        with self._lock:
            engine = self._engine or _create_engine()
            if not self._ready:
                metadata.create_all(engine)
                with engine.begin() as conn:
                    if (
                        conn.execute(
                            select(lamp_status.c.id).where(lamp_status.c.id == 1)
                        ).first()
                        is None
                    ):
                        conn.execute(
                            insert(lamp_status).values(
                                id=1,
                                is_on=False,
                                last_updated=datetime.now(timezone.utc),
                            )
                        )
                self._engine, self._ready = engine, True
                logger.info("Lamp storage ready (%s)", engine.dialect.name)
            return engine

    def ping(self) -> str:
        """Check the database answers; returns its dialect name"""
        with self.engine.connect() as conn:
            conn.execute(select(1))
        return self.engine.dialect.name

    def toggle(
        self,
        session_id: Optional[str] = None,
        user_agent: Optional[str] = None,
        ip_address: Optional[str] = None,
        cooldown: timedelta = timedelta(0),
    ) -> Snapshot:
        """
        Flip the lamp and record who did it, atomically. Raises TooSoon if it was last
        switched within the cooldown: the check is part of the same statement, so it
        holds however many replicas are taking pulls.
        """
        now = datetime.now(timezone.utc)
        rested = lamp_status.c.last_updated <= now - cooldown if cooldown else true()
        with self.engine.begin() as conn:
            # One statement flips and reads back, so concurrent pulls can never both see "off".
            is_on = conn.execute(
                update(lamp_status)
                .where(lamp_status.c.id == 1, rested)
                .values(
                    is_on=~lamp_status.c.is_on,
                    last_updated=now,
                    client_info=f"Session: {session_id or 'unknown'}, IP: {ip_address or 'unknown'}",
                )
                .returning(lamp_status.c.is_on)
            ).scalar_one_or_none()
            if is_on is None:
                raise TooSoon
            conn.execute(
                insert(lamp_activities).values(
                    action="on" if is_on else "off",
                    timestamp=now,
                    session_id=session_id,
                    user_agent=user_agent,
                    ip_address=ip_address,
                    previous_state="off" if is_on else "on",
                )
            )
        return self.snapshot()

    def pulse(self, replica: str, viewers: int) -> tuple[Optional[datetime], int]:
        """
        Report how many streams this replica has open. Returns when the lamp last changed
        and how many streams are open across every replica still reporting.
        """
        now = datetime.now(timezone.utc)
        mine = {"viewers": viewers, "seen_at": now}
        own_row = lamp_viewers.c.replica == replica
        with self.engine.begin() as conn:
            if not conn.execute(
                update(lamp_viewers).where(own_row).values(mine)
            ).rowcount:
                conn.execute(insert(lamp_viewers).values(replica=replica, **mine))
            changed_at = conn.execute(
                select(lamp_status.c.last_updated).where(lamp_status.c.id == 1)
            ).scalar_one()
            room = conn.execute(
                select(func.coalesce(func.sum(lamp_viewers.c.viewers), 0)).where(
                    lamp_viewers.c.seen_at > now - REPLICA_SILENCE
                )
            ).scalar_one()
        return changed_at and _utc(changed_at), int(room)

    def leave(self, replica: str) -> None:
        """This replica is shutting down: stop counting its viewers now, not after the silence"""
        long_gone = lamp_viewers.c.seen_at < datetime.now(timezone.utc) - timedelta(
            days=1
        )
        with self.engine.begin() as conn:
            # Replicas that died without leaving are swept up by the next one that does.
            conn.execute(
                delete(lamp_viewers).where(
                    (lamp_viewers.c.replica == replica) | long_gone
                )
            )

    def snapshot(self) -> Snapshot:
        """Read the lamp plus the counters shown beside it"""
        midnight = datetime.now(timezone.utc).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        today = lamp_activities.c.timestamp >= midnight
        with self.engine.connect() as conn:
            is_on, changed_at = conn.execute(
                select(lamp_status.c.is_on, lamp_status.c.last_updated).where(
                    lamp_status.c.id == 1
                )
            ).one()
            # ponytail: counts scan lamp_activities on every toggle; index `timestamp` or
            # keep running counters once the table is large enough for that to show up.
            lifetime, today_count, visitors = conn.execute(
                select(
                    func.count(),
                    func.count().filter(today),
                    func.count(lamp_activities.c.session_id.distinct()).filter(today),
                ).select_from(lamp_activities)
            ).one()
            recent = conn.execute(
                select(lamp_activities.c.action, lamp_activities.c.timestamp)
                .order_by(lamp_activities.c.id.desc())
                .limit(5)
            ).all()
        return Snapshot(
            is_on=is_on,
            changed_at=_utc(changed_at or midnight),
            today=today_count,
            lifetime=lifetime,
            visitors_today=visitors,
            recent=[Activity(action=action, at=_utc(at)) for action, at in recent],
        )
