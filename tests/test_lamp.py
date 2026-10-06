"""
Checks for the lamp: toggles are atomic, the API reports them, streams fan them out,
and a lost database degrades the app instead of taking it down.
"""
import asyncio
import os
import sqlite3
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select

import main
from store import Store, lamp_activities, metadata

TOGGLE = "/api/v1/lamp/toggle"
STATUS = "/api/v1/lamp/status"


@pytest.fixture
def store(tmp_path):
    # CI sets TEST_DATABASE_URL to repeat every check against a real Postgres.
    engine = create_engine(os.getenv("TEST_DATABASE_URL", f"sqlite:///{tmp_path / 'lamp.db'}"))
    metadata.drop_all(engine)
    return Store(engine)


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
    assert (on["is_on"], on["status"], on["today"], on["lifetime"], on["visitors_today"]) == (True, "on", 1, 1, 1)
    assert on["recent"][0]["action"] == "on"

    off = client.post(TOGGLE, headers={"X-Session-ID": "visitor-1"}).json()
    assert (off["is_on"], off["lifetime"], off["visitors_today"]) == (False, 2, 1)
    assert client.get(STATUS).json()["is_on"] is False


def test_rapid_toggles_are_refused(client, monkeypatch):
    monkeypatch.setattr(main, "TOGGLE_COOLDOWN_SECONDS", 60)
    assert client.post(TOGGLE).status_code == 200
    assert client.post(TOGGLE).status_code == 429
    assert client.get(STATUS).json()["lifetime"] == 1


def test_oversized_headers_are_clipped_to_the_column(client, store):
    assert client.post(TOGGLE, headers={"X-Session-ID": "x" * 5000}).status_code == 200
    with store.engine.connect() as conn:
        assert len(conn.execute(select(lamp_activities.c.session_id)).scalar_one()) == 100


def test_concurrent_pulls_never_lose_a_flip(store):
    with ThreadPoolExecutor(8) as pool:
        list(pool.map(lambda _: store.toggle(), range(40)))

    snapshot = store.snapshot()
    assert (snapshot.lifetime, snapshot.is_on) == (40, False)
    # Each pull saw the state the one before it left behind.
    with store.engine.connect() as conn:
        actions = conn.execute(select(lamp_activities.c.action).order_by(lamp_activities.c.id)).scalars().all()
    assert actions == ["on", "off"] * 20


def test_runs_on_the_tables_the_previous_version_created(tmp_path):
    path = tmp_path / "deployed.db"
    with sqlite3.connect(path) as db:
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

    store = Store(create_engine(f"sqlite:///{path}"))
    before = store.snapshot()
    assert (before.is_on, before.lifetime, before.today) == (True, 1, 1)
    assert store.toggle().is_on is False


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


def test_page_and_health(client):
    assert client.get("/health").json()["status"] == "healthy"
    page = client.get("/")
    assert page.status_code == 200
    assert page.headers["content-security-policy"] == "default-src 'self'"


def test_a_lost_database_degrades_instead_of_crashing(client, monkeypatch):
    assert client.get(STATUS).status_code == 200  # the lamp has been seen once

    monkeypatch.setattr(main, "store", Store(create_engine("sqlite:////nonexistent/lamp.db")))
    main.hub.checked_at = float("-inf")
    assert client.get("/health").json()["status"] == "degraded"
    assert client.get(STATUS).status_code == 200  # last known state

    monkeypatch.setattr(main, "hub", main.Hub())  # a fresh process has nothing to fall back on
    assert client.get(STATUS).status_code == 503
