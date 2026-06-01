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
from engine.api.models import (
    GrantApprovalRequest,
    SetSensitivityRequest,
    StatusResponse,
)
from engine.constants import SERVICE_NAME, VERSION
from engine.domain.exceptions import (
    ChatContextNotFound,
    NoInFlightCycleToStop,
    ProviderUnavailable,
    SessionInFlightTimeout,
    SessionNotFound,
)
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


def _provider_unavailable_error(exc: ProviderUnavailable) -> HTTPException:
    """503 with a structured, retryable body — mirrors the 409 in-flight contract.

    Clients SHOULD surface a retryable message; the inference provider is either
    unreachable or still warming up (e.g. bundled llama.cpp loading weights)."""
    return HTTPException(
        status_code=503,
        detail={"error": "provider_unavailable", "reason": exc.reason},
        headers={"Retry-After": "5"},
    )


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
    """Send a user message. Returns 409 (`session_in_flight`) if the target
    session has an unsettled cycle. Clients SHOULD queue locally and retry
    after the cycle settles (see also POST `/sessions/{id}/stop`)."""
    plain_body = not isinstance(body, ChatRequest)

    request: ChatRequest = (
        ChatRequest(messages=[UserMessage(content=body)]) if plain_body else body
    )

    try:
        response: ChatResponse = await service.perform_user_input(request=request)
    except SessionInFlightTimeout as exc:
        raise HTTPException(
            status_code=409,
            detail={
                "error": "session_in_flight",
                "session_id": str(exc.session_id),
                "trailing_message_id": str(exc.trailing_message_id),
            },
        )
    except ProviderUnavailable as exc:
        raise _provider_unavailable_error(exc)

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
    session_id: UUID, service: ChatServiceDepends, after: str | None = None
) -> MessagesResponse:
    try:
        return service.get_messages(
            session_id=session_id, after=UUID(after) if after else None
        )
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
    """Drive the agent's next iteration on the session's in-flight cycle.

    Called by clients after every approval in the trailing in-flight
    `SystemAction` is decided (granted or declined). The engine does NOT
    auto-continue on its own. Returns 404 if the session does not exist."""
    try:
        return await service.continue_session(session_id=session_id)
    except SessionNotFound:
        raise HTTPException(status_code=404, detail="Session not found")
    except ProviderUnavailable as exc:
        raise _provider_unavailable_error(exc)


@api_router.get("/sessions/{session_id}/grants")
def get_session_grants(
    session_id: UUID, approval_service: ApprovalServiceDepends
) -> list[Grant]:
    """Get available grants for a specific session."""
    return approval_service.active_session_grants(session_id=session_id)


@api_router.post("/sessions/{session_id}/approvals/{approval_id}/grant")
def grant_session_approval(
    session_id: UUID,
    approval_id: UUID,
    body: GrantApprovalRequest,
    approval_service: ApprovalServiceDepends,
) -> dict[str, str]:
    """Record a per-approval grant decision on the in-flight `SystemAction`.

    The engine mutates the trailing `SystemAction(final=false)` in place;
    no new record is appended. Granting does NOT trigger the agent — the
    client follows up with POST `/sessions/{id}/continue` once every
    approval in the group is decided. Returns 404 if the session or
    approval does not exist. Replaces the removed POST
    `/sessions/{id}/grants` (which is now only the global GET/POST `/grants`)."""
    if body.grant is not None:
        approval_service.register_session_grant(
            session_id=session_id, grant=body.grant
        )
    try:
        approval_service.grant_session_approval(
            session_id=session_id,
            approval_id=approval_id,
            expires_at=body.grant.expires_at if body.grant is not None else None,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except ChatContextNotFound:
        raise HTTPException(status_code=404, detail="Session not found")
    return {"status": "granted"}


@api_router.post("/sessions/{session_id}/approvals/{approval_id}/decline")
def decline_session_approval(
    session_id: UUID,
    approval_id: UUID,
    approval_service: ApprovalServiceDepends,
) -> dict[str, str]:
    """Record a per-approval decline decision on the in-flight `SystemAction`.

    Same semantics as `/grant` — mutates in place, does not invoke the
    agent. Returns 404 if the session or approval does not exist.
    Replaces the removed POST `/sessions/{id}/reject_approvals`, which
    decided every undecided approval in one call; clients now decide
    each approval individually."""
    try:
        approval_service.reject_session_approvals(
            session_id=session_id, approvals=[approval_id]
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except ChatContextNotFound:
        raise HTTPException(status_code=404, detail="Session not found")
    return {"status": "declined"}


@api_router.post("/sessions/{session_id}/stop")
def stop_session(
    session_id: UUID, service: ChatServiceDepends
) -> MessagesResponse:
    """Settle the in-flight cycle by declining undecided approvals.

    Sets every undecided approval to `granted=false`, flips the trailing
    `SystemAction(s)` and the cycle's `UserMessage` to `final=true`, and
    appends no new record. The agent is NOT invoked. Returns the
    settled message list so the client can update its view without a
    follow-up read. Returns 409 (`no_in_flight_cycle`) if the trailing
    message is already `final=true`, or 404 if the session does not
    exist."""
    try:
        context = service.stop_cycle(session_id=session_id)
    except NoInFlightCycleToStop as exc:
        raise HTTPException(
            status_code=409,
            detail={
                "error": "no_in_flight_cycle",
                "session_id": str(exc.session_id),
            },
        )
    except ChatContextNotFound:
        raise HTTPException(status_code=404, detail="Session not found")
    return MessagesResponse(session_id=session_id, messages=context.messages)


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
                        '"created_at": "2024-01-15T10:30:01Z"}\n\n'
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
