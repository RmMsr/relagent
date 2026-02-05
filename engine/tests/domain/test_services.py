import uuid
from unittest.mock import MagicMock

import pytest

from engine.domain.exceptions import ChatContextNotFound, SessionNotFound
from engine.domain.models import (
    AssistantMessage,
    ChatContext,
    ChatRequest,
    SessionInfo,
    UserMessage,
)
from engine.domain.services import ChatService


@pytest.fixture
def chat_service(mock_persistence: MagicMock, mock_agent_execution: MagicMock) -> ChatService:
    return ChatService(
        persistence_repository=mock_persistence,
        agent_execution=mock_agent_execution,
    )


class TestEnsureSession:
    def test_creates_new_session_when_none_provided(self, chat_service: ChatService):
        session = chat_service.ensure_session(session_id=None)

        assert isinstance(session, SessionInfo)
        assert session.session_id is not None

    def test_loads_existing_session(
        self,
        chat_service: ChatService,
        mock_persistence: MagicMock,
        sample_session: SessionInfo,
    ):
        mock_persistence.load_session.return_value = sample_session

        session = chat_service.ensure_session(session_id=sample_session.session_id)

        assert session == sample_session
        mock_persistence.load_session.assert_called_once_with(
            session_id=sample_session.session_id
        )

    def test_creates_new_session_when_not_found(
        self,
        chat_service: ChatService,
        mock_persistence: MagicMock,
        sample_session_id: uuid.UUID,
    ):
        mock_persistence.load_session.side_effect = SessionNotFound(
            session_id=sample_session_id
        )

        session = chat_service.ensure_session(session_id=sample_session_id)

        assert isinstance(session, SessionInfo)
        assert session.session_id != sample_session_id


class TestEnsureContext:
    def test_loads_existing_context(
        self,
        chat_service: ChatService,
        mock_persistence: MagicMock,
        sample_session_id: uuid.UUID,
        sample_context: ChatContext,
    ):
        mock_persistence.load_context.return_value = sample_context

        context = chat_service.ensure_context(session_id=sample_session_id)

        assert context == sample_context
        mock_persistence.load_context.assert_called_once_with(
            session_id=sample_session_id
        )

    def test_returns_empty_context_when_not_found(
        self,
        chat_service: ChatService,
        mock_persistence: MagicMock,
        sample_session_id: uuid.UUID,
    ):
        mock_persistence.load_context.side_effect = ChatContextNotFound(
            session_id=sample_session_id
        )

        context = chat_service.ensure_context(session_id=sample_session_id)

        assert isinstance(context, ChatContext)
        assert context.messages == []


class TestPerformUserInput:
    async def test_processes_message_and_saves(
        self,
        chat_service: ChatService,
        mock_persistence: MagicMock,
        mock_agent_execution: MagicMock,
        sample_session: SessionInfo,
    ):
        mock_persistence.load_session.return_value = sample_session
        mock_persistence.load_context.side_effect = ChatContextNotFound(
            session_id=sample_session.session_id
        )

        request = ChatRequest(
            session_id=sample_session.session_id,
            messages=[UserMessage(content="Hello")],
        )

        response = await chat_service.perform_user_input(request)

        assert response.session_id == sample_session.session_id
        assert isinstance(response.message, AssistantMessage)
        mock_agent_execution.run_basic_query.assert_called_once()
        mock_persistence.save_context.assert_called_once()
        mock_persistence.save_session.assert_called_once()


class TestEnsureSessionTitle:
    async def test_generates_title_when_missing(
        self,
        chat_service: ChatService,
        mock_agent_execution: MagicMock,
        sample_context: ChatContext,
    ):
        session = SessionInfo(title=None)

        await chat_service.ensure_session_title(session=session, context=sample_context)

        assert session.title == "Generated Title"
        mock_agent_execution.generate_title.assert_called_once()

    async def test_skips_generation_when_title_exists(
        self,
        chat_service: ChatService,
        mock_agent_execution: MagicMock,
        sample_context: ChatContext,
    ):
        session = SessionInfo(title="Existing Title")

        await chat_service.ensure_session_title(session=session, context=sample_context)

        assert session.title == "Existing Title"
        mock_agent_execution.generate_title.assert_not_called()

    async def test_skips_generation_when_no_messages(
        self,
        chat_service: ChatService,
        mock_agent_execution: MagicMock,
    ):
        session = SessionInfo(title=None)
        empty_context = ChatContext()

        await chat_service.ensure_session_title(session=session, context=empty_context)

        assert session.title is None
        mock_agent_execution.generate_title.assert_not_called()
