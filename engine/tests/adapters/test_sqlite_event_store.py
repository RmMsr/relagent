import asyncio
import sqlite3
import tempfile
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Generator

import pytest

from engine.adapters.sqlite_event_store import SqliteEventStoreAdapter
from engine.domain.ports.events import (
    SessionMessagesAppendedEvent,
    SessionUpdatedEvent,
)


@pytest.fixture
def event_store() -> Generator[SqliteEventStoreAdapter, None, None]:
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = Path(tmpdir) / "events.db"
        yield SqliteEventStoreAdapter(db_path=db_path)


@pytest.fixture
def sample_session_id() -> uuid.UUID:
    return uuid.UUID("151a0cfb-74bb-4978-8881-3d15e4017a5e")


class TestSqliteEventStore:
    def test_publish_session_updated(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        event = SessionUpdatedEvent(session_id=sample_session_id)
        event_store.publish(event)

        assert event.id == 1
        assert event.session_id == sample_session_id

    def test_publish_messages_appended(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        event = SessionMessagesAppendedEvent(
            session_id=sample_session_id,
            latest_sequence_id=123,
        )
        event_store.publish(event)

        assert event.id == 1
        assert event.latest_sequence_id == 123

    def test_publish_increments_id(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        event1 = SessionUpdatedEvent(session_id=sample_session_id)
        event2 = SessionUpdatedEvent(session_id=sample_session_id)
        event3 = SessionMessagesAppendedEvent(
            session_id=sample_session_id, latest_sequence_id=1
        )

        event_store.publish(event1)
        event_store.publish(event2)
        event_store.publish(event3)

        assert event1.id == 1
        assert event2.id == 2
        assert event3.id == 3

    def test_publish_stores_event_in_database(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        event = SessionUpdatedEvent(session_id=sample_session_id)

        event_store.publish(event)

        stored_events = event_store.get_events_after(last_id=0)
        assert len(stored_events) == 1
        assert stored_events[0].id == 1
        assert stored_events[0].session_id == sample_session_id
        assert stored_events[0].event_name.value == "session.updated"

    def test_publish_rejects_event_with_existing_id(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        event = SessionUpdatedEvent(session_id=sample_session_id)
        event.id = 42

        with pytest.raises(
            ValueError, match="Cannot publish event that already has id"
        ):
            event_store.publish(event)

    def test_get_events_after(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))
        event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))
        event_store.publish(
            SessionMessagesAppendedEvent(
                session_id=sample_session_id, latest_sequence_id=1
            )
        )

        events = event_store.get_events_after(last_id=1)

        assert len(events) == 2
        assert events[0].id == 2
        assert events[1].id == 3

    def test_get_events_after_respects_limit(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        for _ in range(10):
            event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))

        # Limit returns most recent N events (per spec: replay limit)
        events = event_store.get_events_after(last_id=0, limit=5)

        assert len(events) == 5
        assert events[0].id == 6  # Most recent 5 are IDs 6-10
        assert events[4].id == 10

    def test_get_events_after_empty(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))

        events = event_store.get_events_after(last_id=1)

        assert len(events) == 0

    def test_prune_old_events(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))
        event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))

        old_time = (datetime.now(timezone.utc) - timedelta(hours=100)).isoformat()
        with sqlite3.connect(event_store.db_path) as conn:
            conn.execute("UPDATE events SET created_at = ? WHERE id = 1", (old_time,))
            conn.commit()

        deleted = event_store.prune_old_events(max_age_hours=72)

        assert deleted == 1
        events = event_store.get_events_after(last_id=0)
        assert len(events) == 1
        assert events[0].id == 2


class TestGenerateServerSentEvents:
    async def test_replays_missed_events_on_connect(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        generator = event_store.generate_server_sent_events(last_event_id=0)

        event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))
        event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))
        event_store.publish(
            SessionMessagesAppendedEvent(
                session_id=sample_session_id, latest_sequence_id=1
            )
        )

        sse1 = await generator.__anext__()
        sse2 = await generator.__anext__()
        sse3 = await generator.__anext__()

        assert sse1.id == "1"
        assert sse2.id == "2"
        assert sse3.id == "3"
        assert sse1.event == "session.updated"
        assert sse3.event == "session.messages.appended"

    async def test_replays_only_events_after_last_id(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))
        event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))
        event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))

        generator = event_store.generate_server_sent_events(last_event_id=2)

        sse = await generator.__anext__()
        assert sse.id == "3"

    async def test_detects_new_events_after_polling(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        generator = event_store.generate_server_sent_events(last_event_id=0)

        async def publish_after_delay() -> None:
            await asyncio.sleep(0.1)
            event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))

        asyncio.create_task(publish_after_delay())

        sse = await asyncio.wait_for(generator.__anext__(), timeout=2.0)

        assert sse.id == "1"
        assert sse.event == "session.updated"

    async def test_streams_multiple_new_events_in_order(
        self, event_store: SqliteEventStoreAdapter, sample_session_id: uuid.UUID
    ) -> None:
        generator = event_store.generate_server_sent_events(last_event_id=0)

        async def publish_events() -> None:
            await asyncio.sleep(0.1)
            event_store.publish(SessionUpdatedEvent(session_id=sample_session_id))
            event_store.publish(
                SessionMessagesAppendedEvent(
                    session_id=sample_session_id, latest_sequence_id=42
                )
            )

        asyncio.create_task(publish_events())

        sse1 = await asyncio.wait_for(generator.__anext__(), timeout=2.0)
        sse2 = await asyncio.wait_for(generator.__anext__(), timeout=2.0)

        assert sse1.id == "1"
        assert sse2.id == "2"
        assert sse1.event == "session.updated"
        assert sse2.event == "session.messages.appended"
