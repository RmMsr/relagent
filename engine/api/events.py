import json
from typing import Protocol

from sse_starlette import ServerSentEvent

from engine.domain.ports.events import Event


class EventConverter(Protocol):
    """Protocol for converting events to ServerSentEvent"""

    def convert_to_sse(self, event: Event) -> ServerSentEvent: ...


class BaseEventConverter:
    def convert_to_sse(self, event: Event) -> ServerSentEvent:
        return ServerSentEvent(
            event=event.event_name.value,
            id=str(event.id),
            data=json.dumps(self._extract_event_data(event)),
        )

    def _extract_event_data(self, event: Event) -> dict[str, str]:
        return {
            "session_id": str(event.session_id),
            "created_at": event.created_at.isoformat(),
        }
