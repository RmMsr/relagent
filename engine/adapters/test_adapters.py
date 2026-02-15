from datetime import datetime, timedelta, timezone
from typing import AsyncGenerator
from uuid import UUID

from sse_starlette import ServerSentEvent

from engine.api.events import BaseEventConverter
from engine.domain.exceptions import ChatContextNotFound, SessionNotFound
from engine.domain.models import AssistantMessage, ChatContext, SessionInfo
from engine.domain.ports.agent_execution import AgentExecution
from engine.domain.ports.events import Event, EventStore
from engine.domain.ports.persistence import Persistence


class MemoryPersistence(Persistence):
    """In-memory persistence adapter for testing."""

    def __init__(self) -> None:
        self._sessions: dict[UUID, SessionInfo] = {}
        self._contexts: dict[UUID, ChatContext] = {}
        self._timestamps: dict[UUID, datetime] = {}

    def save_session(self, session: SessionInfo) -> None:
        self._sessions[session.session_id] = session.model_copy(deep=True)
        self._timestamps[session.session_id] = datetime.now(timezone.utc)

    def load_session(self, session_id: UUID) -> SessionInfo:
        session = self._sessions.get(session_id)
        if session is None:
            raise SessionNotFound(session_id=session_id)
        # Update timestamp on access
        self._timestamps[session_id] = datetime.now(timezone.utc)
        return session

    def save_context(self, session_id: UUID, context: ChatContext) -> None:
        self._contexts[session_id] = context.model_copy(deep=True)
        self._timestamps[session_id] = datetime.now(timezone.utc)

    def load_context(self, session_id: UUID) -> ChatContext:
        context = self._contexts.get(session_id)
        if context is None:
            raise ChatContextNotFound(session_id=session_id)
        # Update timestamp on access
        self._timestamps[session_id] = datetime.now(timezone.utc)
        return context

    def list_recent_sessions(self, limit: int = 100) -> list[SessionInfo]:
        sessions_with_time = [
            (
                session,
                self._timestamps.get(
                    session_id, datetime.min.replace(tzinfo=timezone.utc)
                ),
            )
            for session_id, session in self._sessions.items()
        ]
        sessions_with_time.sort(key=lambda x: x[1], reverse=True)
        return [session for session, _ in sessions_with_time[:limit]]

    def delete_session(self, session_id: UUID) -> None:
        self._sessions.pop(session_id, None)
        self._contexts.pop(session_id, None)
        self._timestamps.pop(session_id, None)


class MemoryEventStoreAdapter(EventStore):
    """In-memory event store adapter for testing."""

    def __init__(self) -> None:
        super().__init__()
        self.events: list[Event] = []

    def publish(self, event: Event) -> None:
        event = event.model_copy(update={"id": len(self.events) + 1})
        self.events.append(event)

    def get_events_after(self, last_id: int = 0, limit: int = 100) -> list[Event]:
        filtered = [
            event
            for event in self.events
            if event.id is not None and event.id > last_id
        ]
        return filtered[-limit:]

    def prune_old_events(self, max_age_hours: int = 72) -> int:
        old_len = len(self.events)
        self.events = [
            event
            for event in self.events
            if event.created_at
            > datetime.now(tz=timezone.utc) - timedelta(hours=max_age_hours)
        ]
        return old_len - len(self.events)

    async def generate_server_sent_events(
        self, last_event_id: int
    ) -> AsyncGenerator[ServerSentEvent, None]:
        """Yields existing events then returns (no polling loop for testing)."""
        converter = BaseEventConverter()
        for event in self.get_events_after(last_id=last_event_id, limit=100):
            yield converter.convert_to_sse(event)


class EchoAgentExecution(AgentExecution):
    """Echo agent execution for testing."""

    async def run_basic_query(
        self, context: ChatContext, query: str
    ) -> AssistantMessage:
        return AssistantMessage(content="Echo: " + query)

    async def generate_title(self, query: str) -> str:
        return "Title: " + query
