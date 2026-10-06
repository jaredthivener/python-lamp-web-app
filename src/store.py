"""
The lamp's state and activity log.

Postgres in production; a local SQLite file when no connection string is configured.
"""

import logging
import os
import re
import tempfile
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import psycopg2  # type: ignore[import-untyped]
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from pydantic import BaseModel, computed_field
from sqlalchemy import Boolean, Column, DateTime, Integer, MetaData, String, Table, Text
from sqlalchemy import create_engine, func, insert, select, update
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


def _utc(value: datetime) -> datetime:
    """SQLite hands back naive datetimes; everything stored here is UTC."""
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def _postgres_dsn() -> Optional[str]:
    """Return the Postgres connection string from the environment or Azure Key Vault"""
    dsn = os.getenv("POSTGRES_CONNECTION_STRING", "")
    vault_url = os.getenv("KEY_VAULT_URI")
    secret_name = "postgresql-connection-string"

    # App Service leaves the literal reference in place when it fails to resolve it:
    # @Microsoft.KeyVault(SecretUri=https://vault.vault.azure.net/secrets/secret-name/)
    reference = re.match(
        r"@Microsoft\.KeyVault\(SecretUri=(https://[^/]+/)secrets/([^/)]+)", dsn
    )
    if reference:
        vault_url, secret_name = reference.groups()
    elif dsn and not dsn.startswith("@Microsoft.KeyVault("):
        return dsn

    if not vault_url:
        return None
    client = SecretClient(vault_url=vault_url, credential=DefaultAzureCredential())
    return client.get_secret(secret_name).value


def _create_engine() -> Engine:
    dsn = _postgres_dsn()
    if dsn:
        # psycopg2 takes the string verbatim, so URLs and "host=... dbname=..." both work.
        return create_engine(
            "postgresql+psycopg2://",
            creator=lambda: psycopg2.connect(dsn, connect_timeout=5),
            pool_pre_ping=True,
        )
    path = Path(tempfile.gettempdir()) / "lamp.db"
    logger.warning(
        "No POSTGRES_CONNECTION_STRING or KEY_VAULT_URI set; using SQLite at %s", path
    )
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
    ) -> Snapshot:
        """Flip the lamp and record who did it, atomically"""
        now = datetime.now(timezone.utc)
        with self.engine.begin() as conn:
            # One statement flips and reads back, so concurrent pulls can never both see "off".
            is_on = conn.execute(
                update(lamp_status)
                .where(lamp_status.c.id == 1)
                .values(
                    is_on=~lamp_status.c.is_on,
                    last_updated=now,
                    client_info=f"Session: {session_id or 'unknown'}, IP: {ip_address or 'unknown'}",
                )
                .returning(lamp_status.c.is_on)
            ).scalar_one()
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
