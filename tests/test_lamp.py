"""
Checks for the lamp: toggles are atomic, the API reports them, streams fan them out,
and a lost database degrades the app instead of taking it down.
"""

import asyncio
import os
import sqlite3
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select, update

import main
import store as storage

TOGGLE = "/api/v1/lamp/toggle"
STATUS = "/api/v1/lamp/status"


@pytest.fixture
def store(tmp_path):
    # CI sets TEST_DATABASE_URL to repeat every check against a real Postgres.
    engine = create_engine(
        os.getenv("TEST_DATABASE_URL", f"sqlite:///{tmp_path / 'lamp.db'}")
    )
    storage.metadata.drop_all(engine)
    yield storage.Store(engine)
    engine.dispose()


@pytest.fixture
def client(store, monkeypatch):
    monkeypatch.setattr(main, "store", store)
    monkeypatch.setattr(main, "hub", main.Hub())
    monkeypatch.setattr(main, "TOGGLE_COOLDOWN_SECONDS", 0)
    with TestClient(main.app) as client:
        yield client


def test_toggle_flips_the_lamp_and_counts_it(client):
    assert client.get(STATUS).json()["is_on"] is False

    on = client.post(TOGGLE, headers={"X-Session-ID": "visitor-1"}).json()
    assert (
        on["is_on"],
        on["status"],
        on["today"],
        on["lifetime"],
        on["visitors_today"],
    ) == (True, "on", 1, 1, 1)
    assert on["recent"][0]["action"] == "on"

    off = client.post(TOGGLE, headers={"X-Session-ID": "visitor-1"}).json()
    assert (off["is_on"], off["lifetime"], off["visitors_today"]) == (False, 2, 1)
    assert client.get(STATUS).json()["is_on"] is False


def test_rapid_toggles_are_refused(client, monkeypatch):
    assert client.post(TOGGLE).status_code == 200
    monkeypatch.setattr(main, "TOGGLE_COOLDOWN_SECONDS", 60)
    assert client.post(TOGGLE).status_code == 429
    assert client.get(STATUS).json()["lifetime"] == 1


def test_the_cooldown_is_for_the_lamp_not_for_each_replica(client, store, monkeypatch):
    store.toggle()  # a pull taken by another replica, which this one has not heard about
    monkeypatch.setattr(main, "TOGGLE_COOLDOWN_SECONDS", 60)
    assert client.post(TOGGLE).status_code == 429
    assert store.snapshot().lifetime == 1


def test_oversized_headers_are_clipped_to_the_column(client, store):
    assert client.post(TOGGLE, headers={"X-Session-ID": "x" * 5000}).status_code == 200
    with store.engine.connect() as conn:
        assert (
            len(conn.execute(select(storage.lamp_activities.c.session_id)).scalar_one())
            == 100
        )


def test_concurrent_pulls_never_lose_a_flip(store):
    with ThreadPoolExecutor(8) as pool:
        list(pool.map(lambda _: store.toggle(), range(40)))

    snapshot = store.snapshot()
    assert (snapshot.lifetime, snapshot.is_on) == (40, False)
    # Each pull saw the state the one before it left behind.
    with store.engine.connect() as conn:
        actions = (
            conn.execute(
                select(storage.lamp_activities.c.action).order_by(
                    storage.lamp_activities.c.id
                )
            )
            .scalars()
            .all()
        )
    assert actions == ["on", "off"] * 20


def test_runs_on_the_tables_the_previous_version_created(tmp_path):
    path = tmp_path / "deployed.db"
    with closing(sqlite3.connect(path)) as db:
        db.executescript("""
            CREATE TABLE lamp_status (
                id INTEGER PRIMARY KEY, is_on BOOLEAN NOT NULL DEFAULT FALSE,
                last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP, client_info TEXT);
            CREATE TABLE lamp_activities (
                id INTEGER PRIMARY KEY, action VARCHAR(10) NOT NULL,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP, session_id VARCHAR(100),
                user_agent TEXT, ip_address VARCHAR(45), previous_state VARCHAR(10),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
            INSERT INTO lamp_status (is_on, client_info) VALUES (TRUE, 'Session: s, IP: 10.0.0.1');
            INSERT INTO lamp_activities (action, session_id, previous_state) VALUES ('on', 's', 'off');
        """)

    deployed = storage.Store(create_engine(f"sqlite:///{path}"))
    before = deployed.snapshot()
    assert (before.is_on, before.lifetime, before.today) == (True, 1, 1)
    assert deployed.toggle().is_on is False
    deployed.engine.dispose()


def test_every_open_stream_hears_a_toggle(store):
    async def scenario():
        hub = main.Hub()
        hub.publish(store.snapshot())
        first, second = hub.subscribe(), hub.subscribe()
        assert (await anext(first)).is_on is False
        assert (await anext(second)).viewers == 2

        hub.publish(store.toggle())
        assert (await anext(first)).is_on is True
        assert (await anext(second)).is_on is True

        await first.aclose()
        await second.aclose()
        assert hub.viewers == 0

    asyncio.run(scenario())


def test_replicas_agree_on_the_lamp_and_who_is_watching(store, monkeypatch):
    monkeypatch.setattr(main, "store", store)
    monkeypatch.setattr(main, "hub", main.Hub())

    async def scenario():
        main.hub.publish(store.snapshot())
        stream = main.hub.subscribe()
        assert (await anext(stream)).viewers == 1

        # Another replica has three people watching, and one of them pulls the cord.
        store.pulse("another-replica", 3)
        store.toggle()
        await main.catch_up()
        heard = await anext(stream)
        assert (heard.is_on, heard.viewers) == (True, 4)

        # That replica dies without saying goodbye: its viewers lapse.
        with store.engine.begin() as conn:
            conn.execute(
                update(storage.lamp_viewers)
                .where(storage.lamp_viewers.c.replica == "another-replica")
                .values(seen_at=datetime.now(timezone.utc) - timedelta(minutes=1))
            )
        await main.catch_up()
        assert main.hub.room == 1

        await stream.aclose()
        await main.catch_up()  # with nobody left here, this replica takes its count back
        assert store.pulse("a-third-replica", 0)[1] == 0

    asyncio.run(scenario())


def test_a_replica_reporting_twice_at_once_is_counted_once(store):
    # A replica that has just started does this: its background loop and its first
    # request both report, at the same moment.
    with ThreadPoolExecutor(8) as pool:
        # Open eight connections first, so that the reports after them start together
        list(pool.map(lambda n: store.pulse(f"warm-up-{n}", 0), range(8)))
        list(pool.map(lambda _: store.pulse("this-replica", 1), range(40)))
    assert store.pulse("another-replica", 0)[1] == 1


def test_a_request_during_the_first_sync_is_not_turned_away(store, monkeypatch):
    # The background loop has asked the database and is still waiting for the lamp's state
    asking, answer = threading.Event(), store.snapshot

    def slow_snapshot():
        asking.set()
        time.sleep(0.2)
        return answer()

    monkeypatch.setattr(store, "snapshot", slow_snapshot)
    monkeypatch.setattr(main, "store", store)
    monkeypatch.setattr(main, "hub", main.Hub())
    with TestClient(main.app) as client:
        assert asking.wait(5)
        assert client.get(STATUS).status_code == 200


def test_a_replica_with_no_viewers_still_reports_the_whole_room(client, store):
    store.pulse("another-replica", 2)
    assert client.post(TOGGLE).json()["viewers"] == 2
    assert client.get(STATUS).json()["viewers"] == 2


def test_azure_postgres_is_signed_in_to_without_a_password(monkeypatch):
    token = SimpleNamespace(
        get_token=lambda scope: SimpleNamespace(token=f"for {scope}")
    )
    monkeypatch.setattr(storage, "_azure_identity", lambda: token)
    monkeypatch.setattr(storage.psycopg2, "connect", lambda **params: params)
    azure = "lamp.postgres.database.azure.com"

    passwordless = storage._connect(
        f"host={azure} dbname=lamp user=lamp-app sslmode=require"
    )
    assert passwordless["password"] == f"for {storage.ENTRA_POSTGRES_SCOPE}"
    assert (passwordless["user"], passwordless["connect_timeout"]) == ("lamp-app", 5)

    assert (
        storage._connect(f"postgresql://me:secret@{azure}/lamp")["password"] == "secret"
    )
    assert "password" not in storage._connect("host=localhost dbname=lamp user=me")


def test_page_and_health(client):
    assert client.get("/health").json()["status"] == "healthy"
    page = client.get("/")
    assert page.status_code == 200
    assert page.headers["content-security-policy"] == "default-src 'self'"


def test_a_lost_database_degrades_instead_of_crashing(client, monkeypatch):
    assert client.get(STATUS).status_code == 200  # the lamp has been seen once

    monkeypatch.setattr(
        main, "store", storage.Store(create_engine("sqlite:////nonexistent/lamp.db"))
    )
    assert client.get("/health").json()["status"] == "degraded"
    assert client.get("/livez").status_code == 200  # a probe must not get it restarted
    assert client.get(STATUS).status_code == 200  # last known state

    # A replica that starts during the outage has nothing to fall back on
    monkeypatch.setattr(main, "hub", main.Hub())
    assert client.get(STATUS).status_code == 503
