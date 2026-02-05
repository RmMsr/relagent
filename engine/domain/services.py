import logging
from uuid import UUID

from engine.domain.exceptions import ChatContextNotFound, SessionNotFound
from engine.domain.models import (
    ChatContext,
    ChatRequest,
    ChatResponse,
    SessionInfo,
)
from engine.domain.ports import AgentExecution, Persistence

logger = logging.getLogger(__name__)


class ChatService:
    persistence_repository: Persistence
    agent_execution: AgentExecution

    def __init__(
        self,
        persistence_repository: Persistence,
        agent_execution: AgentExecution,
    ) -> None:
        self.persistence_repository = persistence_repository
        self.agent_execution = agent_execution

    async def perform_user_input(self, request: ChatRequest) -> ChatResponse:
        session: SessionInfo = self.ensure_session(session_id=request.session_id)
        context: ChatContext = self.ensure_context(session_id=session.session_id)

        # Todo: Use all request messages
        ai_response = await self.agent_execution.run_basic_query(
            context, request.messages[-1].content
        )

        # Todo: dump raw messages for debugging

        context.messages.extend(request.messages)
        context.messages.append(ai_response)

        await self.ensure_session_title(session=session, context=context)

        self.persistence_repository.save_context(session=session, context=context)
        self.persistence_repository.save_session(session=session)
        return ChatResponse(session_id=session.session_id, content=ai_response.content)

    def ensure_session(self, session_id: UUID | None) -> SessionInfo:
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
