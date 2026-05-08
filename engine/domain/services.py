import asyncio
import time
from datetime import datetime
from typing import Sequence
from uuid import UUID

from engine.domain.exceptions import (
    ChatContextNotFound,
    NoInFlightCycleToStop,
    SessionInFlightTimeout,
    SessionNotFound,
)
from engine.domain.models import (
    Approval,
    AssistantMessage,
    ChatContext,
    ChatMessage,
    ChatRequest,
    ChatResponse,
    Grant,
    MessagesResponse,
    PermissionKey,
    SessionInfo,
    SystemAction,
    UserMessage,
)
from engine.domain.ports.agent_execution import AgentExecution
from engine.domain.ports.events import (
    EventStore,
    SessionCreatedEvent,
    SessionDeletedEvent,
    SessionMessagesAppendedEvent,
    SessionUpdatedEvent,
)
from engine.domain.ports.persistence import Persistence
from engine.domain.types import SensitivityLevel
from engine.log_config import get_logger
from engine.settings import get_setting_int

DEFAULT_IN_FLIGHT_POLL_INTERVAL_MS = 250
DEFAULT_IN_FLIGHT_TIMEOUT_SECONDS = 30

logger = get_logger(__name__)


class ChatService:
    persistence_repository: Persistence
    agent_execution: AgentExecution
    event_store: EventStore | None
    approval_service: "ApprovalService | None"

    def __init__(
        self,
        persistence_repository: Persistence,
        agent_execution: AgentExecution,
        event_store: EventStore | None = None,
        approval_service: "ApprovalService | None" = None,
    ) -> None:
        self.persistence_repository = persistence_repository
        self.agent_execution = agent_execution
        self.event_store = event_store
        self.approval_service = approval_service

    async def perform_user_input(self, request: ChatRequest) -> ChatResponse:
        new_session: bool = False
        session: SessionInfo | None = None
        existing_context: ChatContext | None = None
        if request.session_id:
            existing_context = await self.wait_for_settled(
                session_id=request.session_id
            )
            session = self.persistence_repository.find_session(
                session_id=request.session_id
            )

            # Idempotent POST: if the user message already exists, return the prior response.
            if existing_context and request.messages:
                incoming_id = request.messages[-1].message_id
                for i, msg in enumerate(existing_context.messages):
                    if isinstance(msg, UserMessage) and msg.message_id == incoming_id:
                        response_msg = next(
                            (
                                m
                                for m in existing_context.messages[i + 1 :]
                                if isinstance(m, (AssistantMessage, SystemAction))
                            ),
                            None,
                        )
                        if response_msg is not None:
                            return ChatResponse(
                                session_id=request.session_id,
                                message=response_msg,
                                sensitivity_level=existing_context.sensitivity_level,
                            )
                        break

        if session is None:
            session = SessionInfo()
            new_session = True

        context: ChatContext = (
            existing_context if existing_context is not None else ChatContext()
        )

        # TODO: Use all request messages
        ai_response = await self.agent_execution.run_basic_query(
            context=context,
            query=request.messages[-1].content,
            session_id=session.session_id,
        )

        self._append_messages_to_context(context, request.messages)
        self._append_messages_to_context(context, [ai_response])
        if isinstance(ai_response, AssistantMessage):
            self._settle_cycle(context)

        await self.ensure_session_title(session=session, context=context)

        self.persistence_repository.save_session(session=session)

        if new_session:
            self._publish_session_created(session_id=session.session_id)
        else:
            self._publish_session_updated(session_id=session.session_id)

        self.persistence_repository.save_context(
            session_id=session.session_id, context=context
        )

        self._publish_messages_appended(session_id=session.session_id)

        return ChatResponse(
            session_id=session.session_id,
            message=ai_response,
            sensitivity_level=context.sensitivity_level,
        )

    async def continue_session(self, session_id: UUID) -> ChatResponse:
        """Resume agent after grants, sensitivity changes, or for error recovery."""
        session = self.persistence_repository.load_session(session_id=session_id)
        context = self.ensure_context(session_id=session.session_id)

        self._resolve_pending_approvals(context, session.session_id)

        ai_response = await self.agent_execution.run_basic_query(
            context=context,
            query=None,
            session_id=session.session_id,
        )

        if isinstance(ai_response, SystemAction):
            # Replace trailing SystemActions to avoid duplicates when
            # approvals are still unresolved after a sensitivity change.
            self._remove_trailing_system_actions(context)

        self._append_messages_to_context(context, [ai_response])
        if isinstance(ai_response, AssistantMessage):
            self._settle_cycle(context)

        self.persistence_repository.save_context(
            session_id=session.session_id, context=context
        )

        self._publish_messages_appended(session_id=session.session_id)

        return ChatResponse(
            session_id=session.session_id,
            message=ai_response,
            sensitivity_level=context.sensitivity_level,
        )

    def ensure_session(self, session_id: UUID | None = None) -> SessionInfo:
        if session_id is None:
            session = SessionInfo()
            logger.info(
                "No previous session given. Created new session: %s", session.session_id
            )
            return session
        try:
            return self.persistence_repository.load_session(session_id=session_id)
        except SessionNotFound:
            session = SessionInfo()
            logger.info(
                "Previous session (%s) not found. Created new session: %s",
                session_id,
                session.session_id,
            )
            return session

    def set_sensitivity_level(
        self, session_id: UUID, sensitivity_level: SensitivityLevel
    ) -> None:
        context = self.ensure_context(session_id=session_id)
        context.sensitivity_level = sensitivity_level

        # Downgrade pending approvals that exceed the new level
        for action in self._get_trailing_system_actions(context):
            for approval in action.approvals:
                if (
                    approval.granted is None
                    and approval.sensitivity.value > sensitivity_level.value
                ):
                    approval.sensitivity = sensitivity_level

        self.persistence_repository.save_context(session_id=session_id, context=context)

    def ensure_context(self, session_id: UUID) -> ChatContext:
        try:
            return self.persistence_repository.load_context(session_id=session_id)
        except ChatContextNotFound:
            return ChatContext()

    def get_messages(
        self, session_id: UUID, after: UUID | None = None
    ) -> MessagesResponse:
        logger.info(
            "Fetching messages for session %s after message_id: %s",
            str(session_id),
            after,
        )
        context: ChatContext = self.persistence_repository.load_context(
            session_id=session_id
        )
        messages = list(context.messages)
        if after is not None:
            idx = next(
                (i for i, m in enumerate(messages) if m.message_id == after), None
            )
            if idx is not None:
                messages = messages[idx + 1 :]
        return MessagesResponse(session_id=session_id, messages=messages)

    def get_session(self, session_id: UUID) -> SessionInfo:
        return self.persistence_repository.load_session(session_id=session_id)

    def list_recent_sessions(self, limit: int = 100) -> list[SessionInfo]:
        return self.persistence_repository.list_recent_sessions(limit=limit)

    def delete_session(self, session_id: UUID) -> None:
        self.persistence_repository.delete_session(session_id=session_id)
        self._publish_session_deleted(session_id=session_id)
        logger.info("Deleted session: %s", session_id)

    async def ensure_session_title(
        self, session: SessionInfo, context: ChatContext
    ) -> None:
        if session.title is None:
            first_user_message: UserMessage | None = next(
                (m for m in context.messages if isinstance(m, UserMessage)), None
            )
            if first_user_message is None:
                logger.debug(
                    "Context needs at least one user message to generate title"
                )
                return
            session.title = await self.agent_execution.generate_title(
                query=first_user_message.content
            )

    def _publish_session_created(self, session_id: UUID) -> None:
        if self.event_store is None:
            return
        self.event_store.publish(
            SessionCreatedEvent(
                session_id=session_id,
            )
        )

    def _publish_session_updated(self, session_id: UUID) -> None:
        if self.event_store is None:
            return
        self.event_store.publish(
            SessionUpdatedEvent(
                session_id=session_id,
            )
        )

    def _publish_session_deleted(self, session_id: UUID) -> None:
        if self.event_store is None:
            return
        self.event_store.publish(
            SessionDeletedEvent(
                session_id=session_id,
            )
        )

    def _publish_messages_appended(self, session_id: UUID) -> None:
        if self.event_store is None:
            return
        self.event_store.publish(
            SessionMessagesAppendedEvent(session_id=session_id)
        )

    def _resolve_pending_approvals(
        self, context: ChatContext, session_id: UUID
    ) -> None:
        """Set granted=True on trailing pending approvals that match active grants."""
        if self.approval_service is None:
            return

        trailing_actions = self._get_trailing_system_actions(context)
        if not trailing_actions:
            return

        pending_approvals = [
            approval
            for action in trailing_actions
            for approval in action.approvals
            if approval.granted is None
        ]

        if not pending_approvals:
            return

        satisfied, _ = self.approval_service.get_satisfied_and_missing_approvals(
            required_approvals=pending_approvals, session_id=session_id
        )

        satisfied_by_id = {a.id: grant for a, grant in satisfied}

        for action in trailing_actions:
            for approval in action.approvals:
                grant = satisfied_by_id.get(approval.id)
                if grant is not None:
                    approval.granted = True
                    approval.expires_at = grant.expires_at

    @staticmethod
    def _get_trailing_system_actions(context: ChatContext) -> list[SystemAction]:
        """Return SystemAction messages from the tail of the message list.

        Walks backwards from the end, collecting SystemActions until a
        non-SystemAction message is encountered.
        """
        trailing: list[SystemAction] = []
        for msg in reversed(context.messages):
            if isinstance(msg, SystemAction):
                trailing.append(msg)
            else:
                break
        return trailing

    @staticmethod
    def _settle_cycle(context: ChatContext) -> None:
        """Flip final=True on trailing in-flight chain through the cycle's UserMessage."""
        for msg in reversed(context.messages):
            if msg.final:
                continue
            msg.final = True
            if isinstance(msg, UserMessage):
                return

    async def wait_for_settled(
        self,
        session_id: UUID,
        *,
        poll_interval: float | None = None,
        timeout: float | None = None,
    ) -> ChatContext | None:
        """Block until trailing message has final=True. Returns the settled
        context (or None if no context exists) so callers can avoid a reload."""
        if poll_interval is None:
            poll_interval = (
                get_setting_int(
                    "engine",
                    "in_flight_poll_interval_ms",
                    default=DEFAULT_IN_FLIGHT_POLL_INTERVAL_MS,
                    write_log=False,
                )
                / 1000
            )
        if timeout is None:
            timeout = float(
                get_setting_int(
                    "engine",
                    "in_flight_timeout_seconds",
                    default=DEFAULT_IN_FLIGHT_TIMEOUT_SECONDS,
                    write_log=False,
                )
            )

        deadline = time.monotonic() + timeout
        while True:
            try:
                context = self.persistence_repository.load_context(
                    session_id=session_id
                )
            except ChatContextNotFound:
                return None
            if not context.messages or context.messages[-1].final:
                return context
            if time.monotonic() >= deadline:
                raise SessionInFlightTimeout(
                    session_id=session_id,
                    trailing_message_id=context.messages[-1].message_id,
                )
            await asyncio.sleep(poll_interval)

    def stop_cycle(self, session_id: UUID) -> ChatContext:
        """Settle the in-flight cycle: decline undecided approvals, mark all final."""
        context = self.persistence_repository.load_context(session_id=session_id)

        if not context.messages or context.messages[-1].final:
            raise NoInFlightCycleToStop(session_id=session_id)

        for msg in reversed(context.messages):
            if msg.final:
                break
            if isinstance(msg, SystemAction):
                for approval in msg.approvals:
                    if approval.granted is None:
                        approval.granted = False

        self._settle_cycle(context)
        self.persistence_repository.save_context(
            session_id=session_id, context=context
        )
        self._publish_messages_appended(session_id=session_id)
        return context

    @staticmethod
    def _remove_trailing_system_actions(context: ChatContext) -> None:
        """Remove SystemAction messages from the tail of the message list."""
        messages = list(context.messages)
        while messages and isinstance(messages[-1], SystemAction):
            messages.pop()
        context.messages = messages

    @staticmethod
    def _append_messages_to_context(
        context: ChatContext, messages: Sequence[ChatMessage]
    ) -> None:
        context.messages = list(context.messages) + list(messages)


class ApprovalService:
    persistence_repository: Persistence

    def __init__(self, persistence_repository: Persistence):
        self.persistence_repository = persistence_repository

    def register_global_grant(self, grant: Grant) -> None:
        """Registers or updates a global grant in the persistence layer."""
        self.persistence_repository.add_global_grant(grant)

    def register_session_grant(self, session_id: UUID, grant: Grant) -> None:
        """Registers or updates a session-specific grant in the persistence layer."""
        self.persistence_repository.add_session_grant(session_id, grant)

    def reject_session_approvals(self, session_id: UUID, approvals: list[UUID]) -> None:
        """Set granted=False on the specified approvals in the session context."""
        context = self.persistence_repository.load_context(session_id)

        approvals_by_id = {
            approval.id: approval
            for msg in context.messages
            if isinstance(msg, SystemAction)
            for approval in msg.approvals
        }

        unknown = set(approvals) - approvals_by_id.keys()
        if unknown:
            raise ValueError(f"Unknown approval IDs: {unknown}")

        for approval_id in approvals:
            approvals_by_id[approval_id].granted = False

        self.persistence_repository.save_context(session_id, context)

    def grant_session_approval(
        self,
        session_id: UUID,
        approval_id: UUID,
        expires_at: datetime | None = None,
    ) -> None:
        """Set granted=True on a specific approval in the session context."""
        context = self.persistence_repository.load_context(session_id)

        for msg in context.messages:
            if not isinstance(msg, SystemAction):
                continue
            for approval in msg.approvals:
                if approval.id == approval_id:
                    approval.granted = True
                    if expires_at is not None:
                        approval.expires_at = expires_at
                    self.persistence_repository.save_context(session_id, context)
                    return

        raise ValueError(f"Unknown approval ID: {approval_id}")

    def active_global_grants(self) -> list[Grant]:
        return self.persistence_repository.load_active_global_grants()

    def active_session_grants(self, session_id: UUID) -> list[Grant]:
        return self.persistence_repository.load_active_session_grants(session_id)

    def get_satisfied_and_missing_approvals(
        self, required_approvals: list[Approval], session_id: UUID | None = None
    ) -> tuple[list[tuple[Approval, Grant]], list[Approval]]:
        """Filters out all requested approvals that are satisfied by active grants.

        Returns (satisfied, missing) where satisfied pairs each approval with
        the grant that matched it. Expired grants are ignored.
        """

        active_grants = self.active_global_grants()
        if session_id is not None:
            active_grants.extend(self.active_session_grants(session_id))
        grants_by_key = {grant.permission_key: grant for grant in active_grants}

        satisfied_approvals: list[tuple[Approval, Grant]] = []
        missing_approvals: list[Approval] = []

        for approval in required_approvals:
            matching_permission_keys = self.generate_matching_permission_keys(
                approval.permission_key
            )

            matching_grant: Grant | None = None
            for key in matching_permission_keys:
                if key in grants_by_key:
                    matching_grant = grants_by_key[key]
                    break

            if matching_grant is not None:
                satisfied_approvals.append((approval, matching_grant))
            else:
                missing_approvals.append(approval)

        return satisfied_approvals, missing_approvals

    def generate_matching_permission_keys(
        self, requested_key: PermissionKey
    ) -> set[PermissionKey]:
        """Returns a set of permission keys that would satisfy the requested permission.

        In addition to the supplied key those wider permissions are added:
        - Higher sensitivity levels
        - One wildcard_parameter for every allowed_parameter
        """

        accepted_sensitivity_levels = [
            level
            for level in SensitivityLevel
            if level.value >= requested_key.sensitivity.value
        ]

        result_keys = set()

        for level in accepted_sensitivity_levels:
            # Add version for each sensitivity level
            result_keys.add(
                requested_key._replace(
                    sensitivity=level,
                )
            )

            if requested_key.wildcard_parameter is not None:
                # Only one parameter can be used as wildcard
                continue

            # Add wildcard version for each parameter
            for parameter_name, _ in requested_key.allowed_parameters:
                result_keys.add(
                    requested_key._replace(
                        allowed_parameters=tuple(
                            (k, v)
                            for k, v in requested_key.allowed_parameters
                            if k != parameter_name
                        ),
                        wildcard_parameter=parameter_name,
                        sensitivity=level,
                    )
                )

        return result_keys
