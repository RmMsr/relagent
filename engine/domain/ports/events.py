from abc import ABC, abstractmethod
from datetime import datetime, timezone
from enum import Enum
from typing import AsyncGenerator, Literal
from uuid import UUID

from pydantic import BaseModel, Field
from sse_starlette import ServerSentEvent


class EventNames(Enum):
    SESSION_CREATED = "session.created"
    SESSION_DELETED = "session.deleted"
    SESSION_UPDATED = "session.updated"
    SESSION_MESSAGES_APPENDED = "session.messages.appended"


class BaseEvent(BaseModel):
    """Base class for all events with common fields"""

    id: int | None = Field(
        default=None,
        description="Monotonic event ID. Can be empty until persisted.",
    )
    created_at: datetime = Field(default_factory=lambda: datetime.now(tz=timezone.utc))
    session_id: UUID = Field(description="Session this event relates to")


class SessionCreatedEvent(BaseEvent):
    event_name: Literal[EventNames.SESSION_CREATED] = EventNames.SESSION_CREATED


class SessionDeletedEvent(BaseEvent):
    event_name: Literal[EventNames.SESSION_DELETED] = EventNames.SESSION_DELETED


class SessionUpdatedEvent(BaseEvent):
    event_name: Literal[EventNames.SESSION_UPDATED] = EventNames.SESSION_UPDATED


class SessionMessagesAppendedEvent(BaseEvent):
    event_name: Literal[EventNames.SESSION_MESSAGES_APPENDED] = (
        EventNames.SESSION_MESSAGES_APPENDED
    )
    latest_sequence_id: int = Field(
        description="Sequence ID of the latest message in the session"
    )


Event = (
    SessionCreatedEvent
    | SessionDeletedEvent
    | SessionUpdatedEvent
    | SessionMessagesAppendedEvent
)


class EventStore(ABC):
    def close(self) -> None:
        """
        Release any resources held by the event store

        Implement in subclass if needed.
        """

    @abstractmethod
    def publish(self, event: Event) -> None:
        """Publish an event"""
        raise NotImplementedError

    @abstractmethod
    def get_events_after(self, last_id: int = 0, limit: int = 100) -> list[Event]:
        """
        Get events with ID > `last_id`

        Does not return more than `limit` events, skipping older events if needed
        """
        raise NotImplementedError

    @abstractmethod
    def prune_old_events(self, max_age_hours: int = 72) -> int:
        """Delete events older than max_age_hours, return count deleted"""
        raise NotImplementedError

    @abstractmethod
    def generate_server_sent_events(
        self, last_event_id: int
    ) -> AsyncGenerator[ServerSentEvent, None]:
        """Allows to iterate over new events for sending via Server Sent Events"""
        raise NotImplementedError
