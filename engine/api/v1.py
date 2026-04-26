from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException
from sse_starlette import EventSourceResponse

from engine.api.helpers import (
    dependency_agent_execution,
    dependency_approval_service,
    dependency_chat_service,
    dependency_event_store,
    require_api_key,
)
from engine.api.models import SetSensitivityRequest, StatusResponse
from engine.constants import SERVICE_NAME, VERSION
from engine.domain.exceptions import ChatContextNotFound, SessionNotFound
from engine.domain.models import (
    AssistantMessage,
    ChatRequest,
    ChatResponse,
    Grant,
    MessagesResponse,
    SessionInfo,
    SystemAction,
    UserMessage,
)
from engine.domain.ports.events import (
    EventStore,
    SessionCreatedEvent,
    SessionDeletedEvent,
    SessionMessagesAppendedEvent,
    SessionUpdatedEvent,
)
from engine.domain.services import AgentExecution, ApprovalService, ChatService
from engine.log_config import get_logger
from engine.self_test import SelfTestResult, run_all_tests

logger = get_logger(__name__)

api_router = APIRouter(tags=["api"], dependencies=[Depends(require_api_key)])


ChatServiceDepends = Annotated[ChatService, Depends(dependency_chat_service)]
ApprovalServiceDepends = Annotated[
    ApprovalService, Depends(dependency_approval_service)
]
EventStoreDepends = Annotated[EventStore, Depends(dependency_event_store)]
AgentExecutionDepends = Annotated[AgentExecution, Depends(dependency_agent_execution)]


@api_router.get("/status")
async def status() -> StatusResponse:
    return StatusResponse(
        service_name=SERVICE_NAME,
        version=VERSION,
        status="ok",
    )


@api_router.get("/self-test")
async def self_test(execution: AgentExecutionDepends) -> list[SelfTestResult]:
    return await run_all_tests(execution)


@api_router.post("/messages")
async def messages(
    body: ChatRequest | str, service: ChatServiceDepends
) -> ChatResponse | str:
    plain_body = not isinstance(body, ChatRequest)

    request: ChatRequest = (
        ChatRequest(messages=[UserMessage(content=body)]) if plain_body else body
    )

    response: ChatResponse = await service.perform_user_input(request=request)

    if plain_body:
        if isinstance(response.message, AssistantMessage):
            return response.message.content
        elif (
            isinstance(response.message, SystemAction) and response.message.notification
        ):
            return response.message.notification
        else:
            return "(no output)"
    else:
        return response


@api_router.get("/messages/{session_id}")
def get_messages(
    session_id: UUID, service: ChatServiceDepends, from_id: int | None = None
) -> MessagesResponse:
    try:
        return service.get_messages(session_id=session_id, from_id=from_id)
    except ChatContextNotFound:
        raise HTTPException(status_code=404, detail="Session not found")


@api_router.get("/sessions")
def list_sessions(
    service: ChatServiceDepends,
    limit: int = 100,
) -> list[SessionInfo]:
    """List recent sessions sorted by last modified time."""
    # Validate and cap limit parameter
    if limit < 1:
        limit = 1
    elif limit > 1000:
        limit = 1000
    return service.list_recent_sessions(limit=limit)


@api_router.get("/sessions/{session_id}")
def get_session(session_id: UUID, service: ChatServiceDepends) -> SessionInfo:
    try:
        return service.get_session(session_id=session_id)
    except SessionNotFound:
        raise HTTPException(status_code=404, detail="Session not found")


@api_router.put("/sessions/{session_id}/sensitivity")
def set_session_sensitivity(
    session_id: UUID, body: SetSensitivityRequest, service: ChatServiceDepends
) -> dict[str, str]:
    """Set the sensitivity level for a session context."""
    service.set_sensitivity_level(
        session_id=session_id, sensitivity_level=body.sensitivity_level
    )
    return {"status": "updated"}


@api_router.post("/sessions/{session_id}/continue")
async def continue_session(
    session_id: UUID,
    service: ChatServiceDepends,
) -> ChatResponse:
    """Continue a session — re-run the agent with current state."""
    try:
        return await service.continue_session(session_id=session_id)
    except SessionNotFound:
        raise HTTPException(status_code=404, detail="Session not found")


@api_router.post("/sessions/{session_id}/grants")
def create_session_grant(
    session_id: UUID, approval_service: ApprovalServiceDepends, grant: Grant
) -> dict[str, str]:
    """Create a grant for a specific session."""
    approval_service.register_session_grant(session_id=session_id, grant=grant)
    return {"status": "created"}


@api_router.get("/sessions/{session_id}/grants")
def get_session_grants(
    session_id: UUID, approval_service: ApprovalServiceDepends
) -> list[Grant]:
    """Get available grants for a specific session."""
    return approval_service.active_session_grants(session_id=session_id)


@api_router.post("/sessions/{session_id}/reject_approvals")
def reject_session_approvals(
    session_id: UUID, approvals: list[UUID], approval_service: ApprovalServiceDepends
):
    approval_service.reject_session_approvals(
        session_id=session_id, approvals=approvals
    )
    return {"status": "rejected"}


@api_router.delete("/sessions/{session_id}")
def delete_session(
    session_id: UUID,
    service: ChatServiceDepends,
) -> dict[str, str]:
    """Delete a session and all its associated data."""
    try:
        service.delete_session(session_id=session_id)
        return {"status": "deleted", "session_id": str(session_id)}
    except SessionNotFound:
        raise HTTPException(status_code=404, detail="Session not found")


@api_router.post("/grants")
def create_grant(approval: ApprovalServiceDepends, grant: Grant) -> dict[str, str]:
    """Create a new grant for a specific resource."""
    approval.register_global_grant(grant=grant)
    return {"status": "created"}


@api_router.get("/grants")
def get_global_grants(approval: ApprovalServiceDepends) -> list[Grant]:
    """Get available grants for the current user."""
    return approval.active_global_grants()


@api_router.get(
    "/events",
    response_class=EventSourceResponse,
    responses={
        200: {
            "description": "Server-Sent Events stream for real-time notifications",
            "model": (
                SessionCreatedEvent
                | SessionDeletedEvent
                | SessionUpdatedEvent
                | SessionMessagesAppendedEvent
            ),
            "content": {
                "text/event-stream": {
                    "schema": {
                        "type": "array",
                        "items": {
                            "anyOf": [
                                {
                                    "type": "object",
                                    "$ref": "#/components/schemas/SessionCreatedEvent",
                                },
                                {
                                    "type": "object",
                                    "$ref": "#/components/schemas/SessionDeletedEvent",
                                },
                                {
                                    "type": "object",
                                    "$ref": "#/components/schemas/SessionUpdatedEvent",
                                },
                                {
                                    "type": "object",
                                    "$ref": "#/components/schemas/SessionMessagesAppendedEvent",
                                },
                            ]
                        },
                    },
                    "example": (
                        "event: session.created\n"
                        "id: 41\n"
                        'data: {"session_id": "151a0cfb-74bb-4978-8881-3d15e4017a5e", '
                        '"created_at": "2024-01-15T10:29:00Z"}\n\n'
                        "event: session.deleted\n"
                        "id: 42\n"
                        'data: {"session_id": "151a0cfb-74bb-4978-8881-3d15e4017a5e", '
                        '"created_at": "2024-01-15T10:30:00Z"}\n\n'
                        "event: session.updated\n"
                        "id: 43\n"
                        'data: {"session_id": "151a0cfb-74bb-4978-8881-3d15e4017a5e", '
                        '"created_at": "2024-01-15T10:30:00Z"}\n\n'
                        "event: session.messages.appended\n"
                        "id: 44\n"
                        'data: {"session_id": "151a0cfb-74bb-4978-8881-3d15e4017a5e", '
                        '"latest_sequence_id": 5, "created_at": "2024-01-15T10:30:01Z"}\n\n'
                        ": ping - 2024-01-15T10:30:15Z"
                    ),
                }
            },
        }
    },
    summary="Subscribe to real-time events",
    description="""
Subscribe to Server-Sent Events (SSE) for real-time notifications. See the
[HTML5 specification](https://html.spec.whatwg.org/multipage/server-sent-events.html#server-sent-events) for more details
.

## Event Types

- **session.created**: A new session was created
- **session.deleted**: A session was deleted
- **session.updated**: Session metadata changed (e.g., title generated)
- **session.messages.appended**: New message(s) added to a session

The connection sends a ping every 15 seconds to keep it alive.

## Reconnection

Include `Last-Event-ID` header with the last received event ID to replay missed events.

## Retention

Maximum 100 events are replayed. Events before that or older than 72 hours are not re-sent.
""",
)
async def events(
    event_store: EventStoreDepends,
    last_event_id: Annotated[
        int | None,
        Header(
            alias="Last-Event-ID",
            description="Last received event ID for reconnection replay",
        ),
    ] = None,
) -> EventSourceResponse:
    event_id = 0
    if last_event_id is not None:
        event_id = last_event_id

    return EventSourceResponse(event_store.generate_server_sent_events(event_id))
