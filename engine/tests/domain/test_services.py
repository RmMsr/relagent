from uuid import UUID

from engine.domain.models import (
    AssistantMessage,
    ChatContext,
    ChatRequest,
    SessionInfo,
    UserMessage,
)
from engine.domain.ports.events import EventNames, EventStore
from engine.domain.ports.persistence import Persistence
from engine.domain.services import ChatService


class TestEnsureSession:
    def test_creates_new_session_when_none_provided(self, chat_service: ChatService):
        session = chat_service.ensure_session(session_id=None)

        assert isinstance(session, SessionInfo)
        assert session.session_id is not None

    def test_loads_existing_session(
        self,
        chat_service: ChatService,
        persistence: Persistence,
        sample_session: SessionInfo,
    ):
        persistence.save_session(sample_session)

        session = chat_service.ensure_session(session_id=sample_session.session_id)

        assert session.session_id == sample_session.session_id
        assert session.title == sample_session.title

    def test_creates_new_session_when_not_found(
        self,
        chat_service: ChatService,
        sample_session_id: UUID,
    ):
        session = chat_service.ensure_session(session_id=sample_session_id)

        assert isinstance(session, SessionInfo)
        assert session.session_id != sample_session_id


class TestEnsureContext:
    def test_loads_existing_context(
        self,
        chat_service: ChatService,
        persistence: Persistence,
        sample_session_id: UUID,
        sample_context: ChatContext,
    ):
        persistence.save_context(sample_session_id, sample_context)

        context = chat_service.ensure_context(session_id=sample_session_id)

        assert len(context.messages) == len(sample_context.messages)
        assert context.messages[0].content == sample_context.messages[0].content

    def test_returns_empty_context_when_not_found(
        self,
        chat_service: ChatService,
        sample_session_id: UUID,
    ):
        context = chat_service.ensure_context(session_id=sample_session_id)

        assert isinstance(context, ChatContext)
        assert context.messages == []


class TestPerformUserInput:
    async def test_processes_message_and_saves(
        self,
        chat_service: ChatService,
        persistence: Persistence,
        event_store: EventStore,
    ):
        session = chat_service.ensure_session()
        persistence.save_session(session)

        request = ChatRequest(
            session_id=session.session_id,
            messages=[UserMessage(content="Hello")],
        )

        response = await chat_service.perform_user_input(request)

        assert response.session_id == session.session_id
        assert isinstance(response.message, AssistantMessage)
        assert response.message.content == "Echo: Hello"

        # Verify context was saved
        context = persistence.load_context(session.session_id)
        assert len(context.messages) == 2

        # Verify events were created
        events = event_store.get_events_after()

        assert len(events) == 2
        assert events[0].event_name == EventNames.SESSION_UPDATED
        assert events[1].event_name == EventNames.SESSION_MESSAGES_APPENDED
        assert events[1].session_id == session.session_id
        assert events[1].latest_sequence_id == response.message.sequence_id

    async def test_perform_user_input_increases_message_sequence_per_session(
        self,
        chat_service: ChatService,
        persistence: Persistence,
    ):
        session_1 = chat_service.ensure_session()
        persistence.save_session(session=session_1)

        session_2 = chat_service.ensure_session()
        persistence.save_session(session=session_2)

        # Perform 3 requests on 2 sessions with 1, 1 and 2 messages

        await chat_service.perform_user_input(
            ChatRequest(
                session_id=session_1.session_id,
                messages=[UserMessage(content="Hello 1")],
            )
        )

        await chat_service.perform_user_input(
            ChatRequest(
                session_id=session_2.session_id,
                messages=[UserMessage(content="Hello 2")],
            )
        )

        await chat_service.perform_user_input(
            ChatRequest(
                session_id=session_1.session_id,
                messages=[
                    UserMessage(content="Some question"),
                    UserMessage(content="Some clarification"),
                ],
            )
        )

        # Session 1: Expect 5 messages (3 User + 2 Assistant)

        messages_response = chat_service.get_messages(session_id=session_1.session_id)
        messages = messages_response.messages

        assert len(messages) == 5
        assert isinstance(messages[0], UserMessage)
        assert messages[0].sequence_id == 0
        assert isinstance(messages[1], AssistantMessage)
        assert messages[1].sequence_id == 1
        assert isinstance(messages[2], UserMessage)
        assert messages[2].sequence_id == 2
        assert isinstance(messages[3], UserMessage)
        assert messages[3].sequence_id == 3
        assert isinstance(messages[4], AssistantMessage)
        assert messages[4].sequence_id == 4

        # Session 2: Expect 2 messages (1 User + 1 Assistant)

        messages_response = chat_service.get_messages(session_id=session_2.session_id)
        messages = messages_response.messages

        assert len(messages) == 2
        assert isinstance(messages[0], UserMessage)
        assert messages[0].sequence_id == 0
        assert isinstance(messages[1], AssistantMessage)
        assert messages[1].sequence_id == 1


class TestEnsureSessionTitle:
    async def test_generates_title_when_missing(
        self,
        chat_service: ChatService,
        event_store: EventStore,
        sample_context: ChatContext,
    ):
        session = SessionInfo(title=None)

        await chat_service.ensure_session_title(session=session, context=sample_context)

        # EchoAgentExecution returns "Title: " + query
        assert session.title is not None
        assert session.title.startswith("Title: ")
        events = event_store.get_events_after()
        assert len(events) == 1
        assert events[0].event_name == EventNames.SESSION_UPDATED
        assert events[0].session_id == session.session_id

    async def test_skips_generation_when_title_exists(
        self,
        chat_service: ChatService,
        sample_context: ChatContext,
    ):
        session = SessionInfo(title="Existing Title")

        await chat_service.ensure_session_title(session=session, context=sample_context)

        assert session.title == "Existing Title"

    async def test_skips_generation_when_no_messages(
        self,
        chat_service: ChatService,
    ):
        session = SessionInfo(title=None)
        empty_context = ChatContext()

        await chat_service.ensure_session_title(session=session, context=empty_context)

        assert session.title is None
