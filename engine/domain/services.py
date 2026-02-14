import logging
from typing import Sequence
from uuid import UUID

from engine.domain.exceptions import ChatContextNotFound, SessionNotFound
from engine.domain.models import (
    ChatContext,
    ChatMessage,
    ChatRequest,
    ChatResponse,
    MessagesResponse,
    SessionInfo,
)
from engine.domain.ports.agent_execution import AgentExecution
from engine.domain.ports.events import (
    EventStore,
    SessionMessagesAppendedEvent,
    SessionUpdatedEvent,
)
from engine.domain.ports.persistence import Persistence

logger = logging.getLogger(__name__)


class ChatService:
    persistence_repository: Persistence
    agent_execution: AgentExecution
    event_store: EventStore | None

    def __init__(
        self,
        persistence_repository: Persistence,
        agent_execution: AgentExecution,
        event_store: EventStore | None = None,
    ) -> None:
        self.persistence_repository = persistence_repository
        self.agent_execution = agent_execution
        self.event_store = event_store

    async def perform_user_input(self, request: ChatRequest) -> ChatResponse:
        session: SessionInfo = self.ensure_session(session_id=request.session_id)
        context: ChatContext = self.ensure_context(session_id=session.session_id)

        # Todo: Use all request messages
        ai_response = await self.agent_execution.run_basic_query(
            context, request.messages[-1].content
        )

        self._add_messages_to_context_with_sequence_ids(context, request.messages)
        self._add_messages_to_context_with_sequence_ids(context, [ai_response])

        await self.ensure_session_title(session=session, context=context)

        self.persistence_repository.save_context(
            session_id=session.session_id, context=context
        )
        self.persistence_repository.save_session(session=session)

        # Publish message append event with latest message ID
        self._publish_messages_appended(
            session_id=session.session_id,
            latest_message_id=ai_response.sequence_id,
        )

        return ChatResponse(session_id=session.session_id, message=ai_response)

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

    def ensure_context(self, session_id: UUID) -> ChatContext:
        try:
            return self.persistence_repository.load_context(session_id=session_id)
        except ChatContextNotFound:
            return ChatContext()

    def get_messages(
        self, session_id: UUID, from_id: int | None = None
    ) -> MessagesResponse:
        logger.info(
            "Fetching messages for session %s from sequence ID: %s",
            str(session_id),
            from_id,
        )
        context: ChatContext = self.persistence_repository.load_context(
            session_id=session_id
        )
        messages = context.messages
        if from_id is not None:
            messages = [
                m
                for m in messages
                if m.sequence_id is not None and m.sequence_id >= from_id
            ]
        return MessagesResponse(session_id=session_id, messages=messages)

    def get_session(self, session_id: UUID) -> SessionInfo:
        return self.persistence_repository.load_session(session_id=session_id)

    async def ensure_session_title(
        self, session: SessionInfo, context: ChatContext
    ) -> None:
        if session.title is None:
            if not context.messages:
                logger.debug("Context needs at least one message to generate title")
                return
            session.title = await self.agent_execution.generate_title(
                query=context.messages[0].content
            )
            self._publish_session_updated(session_id=session.session_id)

    def _publish_session_updated(self, session_id: UUID) -> None:
        if self.event_store is None:
            return
        self.event_store.publish(
            SessionUpdatedEvent(
                session_id=session_id,
            )
        )

    def _publish_messages_appended(
        self, session_id: UUID, latest_message_id: int | None
    ) -> None:
        if self.event_store is None:
            return
        if latest_message_id is None:
            logger.warning("Cannot publish messages.appended without message ID")
            return
        self.event_store.publish(
            SessionMessagesAppendedEvent(
                session_id=session_id,
                latest_sequence_id=latest_message_id,
            )
        )

    def _add_messages_to_context_with_sequence_ids(
        self, context: ChatContext, messages: Sequence[ChatMessage]
    ) -> None:
        next_sequence_id: int = 0
        if context.messages:
            last_message = context.messages[-1]
            if last_message.sequence_id is not None:
                next_sequence_id = last_message.sequence_id + 1
        for m in messages:
            m.sequence_id = next_sequence_id
            next_sequence_id += 1
            context.messages.append(m)
