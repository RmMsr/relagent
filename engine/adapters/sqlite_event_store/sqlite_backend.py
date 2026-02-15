import asyncio
import json
import logging
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import AsyncGenerator

from pydantic import ValidationError
from sse_starlette import ServerSentEvent

from engine.api.events import BaseEventConverter
from engine.domain.ports.events import (
    Event,
    EventNames,
    EventStore,
    SessionCreatedEvent,
    SessionDeletedEvent,
    SessionMessagesAppendedEvent,
    SessionUpdatedEvent,
)

logger = logging.getLogger(__name__)

POLL_INTERVAL = 0.1  # 100ms; values down to 20ms tested with negligible CPU impact


class SqliteEventStoreAdapter(EventStore):
    """
    Low effort implmenetation of EventStore using SQLite.

    Should work well with low concurrency and moderate event volume. Could be
    replaced by Redis streams if needed.
    """

    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self._ensure_schema()

    def publish(self, event: Event) -> None:
        if event.id is not None:
            raise ValueError(f"Cannot publish event that already has id={event.id}")

        data = event.model_dump_json()
        with self._get_connection() as conn:
            cursor = conn.execute(
                "INSERT INTO events (event_name, created_at, data) VALUES (?, ?, ?)",
                (
                    event.event_name.value,
                    event.created_at.isoformat(),
                    data,
                ),
            )
            conn.commit()
            event_id = cursor.lastrowid
            if event_id is None:
                raise RuntimeError("Failed to get lastrowid after insert")

        event.id = event_id
        logger.info("Published event (#%d): %s", event_id, event.event_name.value)

    def get_events_after(self, last_id: int = 0, limit: int = 100) -> list[Event]:
        with self._get_connection() as conn:
            cursor = conn.execute(
                """
                SELECT * FROM (
                    SELECT id, event_name, created_at, data
                    FROM events WHERE id > ? ORDER BY id DESC LIMIT ?
                ) AS sub
                ORDER BY id ASC
                """,
                (last_id, limit),
            )
            rows = cursor.fetchall()

        events = list[Event]()
        for current in rows:
            event = self._build_event_from_row(dict(current))
            if event:
                events.append(event)

        return events

    def prune_old_events(self, max_age_hours: int = 72) -> int:
        cutoff = datetime.now(timezone.utc) - timedelta(hours=max_age_hours)

        with self._get_connection() as conn:
            cursor = conn.execute(
                "DELETE FROM events WHERE created_at < ?",
                (cutoff.isoformat(),),
            )
            conn.commit()
            deleted = cursor.rowcount

        if deleted > 0:
            logger.info("Pruned %d events older than %d hours", deleted, max_age_hours)
        return deleted

    async def generate_server_sent_events(
        self, last_event_id: int
    ) -> AsyncGenerator[ServerSentEvent, None]:
        logger.info(
            "Generating server-sent events starting from event ID: %d", last_event_id
        )

        current_id = last_event_id
        converter = BaseEventConverter()

        # Replay missed events
        missed_events = self.get_events_after(last_id=current_id, limit=100)
        for event in missed_events:
            yield converter.convert_to_sse(event)
            if event.id is not None:
                current_id = event.id

        # Stream new events (EventSourceResponse handles keepalive ping automatically)
        while True:
            new_events = self.get_events_after(last_id=current_id, limit=100)
            for event in new_events:
                yield converter.convert_to_sse(event)
                if event.id is not None:
                    current_id = event.id

            await asyncio.sleep(POLL_INTERVAL)

    def _get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30.0)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        with self._get_connection() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_name TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    data TEXT NULL
                )
            """)
            conn.commit()

    def _build_event_from_row(self, row: dict[str, str | int]) -> Event | None:
        try:
            if isinstance(row["data"], str):
                data = json.loads(row["data"])
            else:
                data = {}

            event_name = EventNames(data["event_name"])

            data["id"] = row["id"]
            data["event_name"] = event_name
            data["created_at"] = row["created_at"]

            match event_name:
                case EventNames.SESSION_CREATED:
                    return SessionCreatedEvent.model_validate(data)
                case EventNames.SESSION_DELETED:
                    return SessionDeletedEvent.model_validate(data)
                case EventNames.SESSION_UPDATED:
                    return SessionUpdatedEvent.model_validate(data)
                case EventNames.SESSION_MESSAGES_APPENDED:
                    return SessionMessagesAppendedEvent.model_validate(data)
        except ValidationError as exc:
            logger.warning(
                "Validation error for'%s' while loading event from store: %s",
                exc.title,
                [e for e in exc.errors()],
            )
            return None
        except (KeyError, ValueError) as exc:
            logger.warning(
                "Error loading event from store: %s raw data: %s",
                str(exc),
                json.dumps(row),
            )
            return None
