from uuid import UUID, uuid4

import pytest

from engine.domain.exceptions import SessionNotFound
from engine.domain.models import (
    Approval,
    AssistantMessage,
    ChatContext,
    ChatRequest,
    Grant,
    SessionInfo,
    SystemAction,
    UserMessage,
)
from engine.domain.ports.events import EventNames, EventStore
from engine.domain.ports.persistence import Persistence
from engine.domain.services import ApprovalService, ChatService
from engine.domain.types import ApprovalType, SensitivityLevel


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

        messages = context.all_messages()
        assert len(messages) == len(sample_context.messages)
        assert messages[0].content == sample_context.all_messages()[0].content

    def test_returns_empty_context_when_not_found(
        self,
        chat_service: ChatService,
        sample_session_id: UUID,
    ):
        context = chat_service.ensure_context(session_id=sample_session_id)

        assert isinstance(context, ChatContext)
        assert context.messages == []


class TestPerformUserInput:
    async def test_processes_message_with_existing_session(
        self,
        chat_service: ChatService,
        persistence: Persistence,
        event_store: EventStore,
        sample_session: SessionInfo,
    ):
        persistence.save_session(sample_session)

        request = ChatRequest(
            session_id=sample_session.session_id,
            messages=[UserMessage(content="Hello")],
        )

        response = await chat_service.perform_user_input(request)

        assert response.session_id == sample_session.session_id
        assert isinstance(response.message, AssistantMessage)
        assert response.message.content == "Echo: Hello"

        # Verify context was saved
        context = persistence.load_context(sample_session.session_id)
        assert len(context.messages) == 2

        # Verify events were created
        events = event_store.get_events_after()

        assert len(events) == 2
        assert events[0].event_name == EventNames.SESSION_UPDATED
        assert events[0].session_id == sample_session.session_id
        assert events[1].event_name == EventNames.SESSION_MESSAGES_APPENDED
        assert events[1].session_id == sample_session.session_id
        # Settlement publishes the cycle-start UserMessage id, not the AssistantMessage id
        user_msg = context.messages[-2]
        assert events[1].latest_sequence_id == user_msg.sequence_id

    async def test_processes_message_with_new_session(
        self,
        chat_service: ChatService,
        persistence: Persistence,
        event_store: EventStore,
    ):
        request = ChatRequest(
            messages=[UserMessage(content="Hello")],
        )

        response = await chat_service.perform_user_input(request)

        assert response.session_id is not None
        assert isinstance(response.message, AssistantMessage)
        assert response.message.content == "Echo: Hello"

        # Verify context was saved
        context = persistence.load_context(response.session_id)
        assert len(context.messages) == 2

        # Verify events were created
        events = event_store.get_events_after()

        assert len(events) == 2
        assert events[0].event_name == EventNames.SESSION_CREATED
        assert events[1].event_name == EventNames.SESSION_MESSAGES_APPENDED
        assert events[1].session_id == response.session_id
        user_msg = context.messages[-2]
        assert events[1].latest_sequence_id == user_msg.sequence_id

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

        assert session.title is not None
        assert session.title.startswith("Title: ")

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


class TestGetMessages:
    async def test_returns_all_messages(
        self,
        chat_service: ChatService,
        persistence: Persistence,
    ):
        request = ChatRequest(messages=[UserMessage(content="Hello")])
        response = await chat_service.perform_user_input(request)

        result = chat_service.get_messages(session_id=response.session_id)

        assert result.session_id == response.session_id
        assert len(result.messages) == 2

    async def test_from_id_filters_messages(
        self,
        chat_service: ChatService,
        persistence: Persistence,
    ):
        session = SessionInfo()
        persistence.save_session(session)
        context = ChatContext(
            messages=[
                UserMessage(content="First", sequence_id=0),
                AssistantMessage(content="Reply", sequence_id=1),
                UserMessage(content="Second", sequence_id=2),
                AssistantMessage(content="Reply 2", sequence_id=3),
            ]
        )
        persistence.save_context(session.session_id, context)

        result = chat_service.get_messages(session_id=session.session_id, from_id=2)

        assert len(result.messages) == 2
        assert all((m.sequence_id or 0) >= 2 for m in result.messages)

    async def test_from_id_zero_returns_all(
        self,
        chat_service: ChatService,
        persistence: Persistence,
    ):
        session = SessionInfo()
        persistence.save_session(session)
        context = ChatContext(
            messages=[
                UserMessage(content="A", sequence_id=0),
                AssistantMessage(content="B", sequence_id=1),
            ]
        )
        persistence.save_context(session.session_id, context)

        result = chat_service.get_messages(session_id=session.session_id, from_id=0)

        assert len(result.messages) == 2


class TestDeleteSession:
    async def test_deleted_session_is_not_loadable(
        self,
        chat_service: ChatService,
        persistence: Persistence,
    ):
        session = SessionInfo()
        persistence.save_session(session)

        chat_service.delete_session(session_id=session.session_id)

        with pytest.raises(SessionNotFound):
            persistence.load_session(session_id=session.session_id)

    async def test_delete_publishes_event(
        self,
        chat_service: ChatService,
        persistence: Persistence,
        event_store: EventStore,
    ):
        session = SessionInfo()
        persistence.save_session(session)

        chat_service.delete_session(session_id=session.session_id)

        events = event_store.get_events_after()
        assert any(e.event_name == EventNames.SESSION_DELETED for e in events)


class TestListRecentSessions:
    async def test_returns_saved_sessions(
        self,
        chat_service: ChatService,
        persistence: Persistence,
    ):
        s1 = SessionInfo(title="First")
        s2 = SessionInfo(title="Second")
        persistence.save_session(s1)
        persistence.save_session(s2)

        result = chat_service.list_recent_sessions()

        ids = [s.session_id for s in result]
        assert s1.session_id in ids
        assert s2.session_id in ids

    async def test_empty_when_no_sessions(self, chat_service: ChatService):
        assert chat_service.list_recent_sessions() == []

    async def test_limit_is_respected(
        self,
        chat_service: ChatService,
        persistence: Persistence,
    ):
        for i in range(5):
            persistence.save_session(SessionInfo(title=f"Session {i}"))

        result = chat_service.list_recent_sessions(limit=3)

        assert len(result) == 3


def _approval(**kwargs) -> Approval:
    defaults = dict(
        type=ApprovalType.OutgoingData,
        component="web_search",
        purpose="Searching the web",
        sensitivity=SensitivityLevel.OpenInformation,
    )
    return Approval(**{**defaults, **kwargs})


def _grant_for(approval: Approval) -> Grant:
    return Grant(
        approval_type=approval.type,
        component=approval.component,
        max_sensitivity=approval.sensitivity,
        allowed_parameters=approval.allowed_parameters,
    )


class TestResolvePendingApprovals:
    """Only trailing SystemAction messages (those at the end of the message list)
    should have their pending approvals resolved against active grants.
    """

    def test_resolves_single_trailing_approval(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
    ):
        session_id = uuid4()
        approval = _approval()

        context = ChatContext(
            messages=[
                UserMessage(content="Search"),
                SystemAction(approvals=[approval]),
            ]
        )
        approval_service.register_session_grant(session_id, _grant_for(approval))

        assert approval.granted is None

        chat_service._resolve_pending_approvals(context, session_id)

        assert approval.granted is True

    def test_resolves_multiple_trailing_system_actions(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
    ):
        session_id = uuid4()
        approval_a = _approval(component="web_search")
        approval_b = _approval(component="email_send")
        context = ChatContext(
            messages=[
                UserMessage(content="Do things"),
                SystemAction(approvals=[approval_a]),
                SystemAction(approvals=[approval_b]),
            ]
        )
        approval_service.register_session_grant(session_id, _grant_for(approval_a))
        approval_service.register_session_grant(session_id, _grant_for(approval_b))

        chat_service._resolve_pending_approvals(context, session_id)

        assert approval_a.granted is True
        assert approval_b.granted is True

    def test_does_not_resolve_non_trailing_system_action(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
    ):
        """An earlier SystemAction followed by an AssistantMessage is not trailing."""
        session_id = uuid4()
        old_approval = _approval(component="web_search")
        new_approval = _approval(component="email_send")
        context = ChatContext(
            messages=[
                UserMessage(content="First request"),
                SystemAction(approvals=[old_approval]),
                AssistantMessage(content="Done with search"),
                UserMessage(content="Second request"),
                SystemAction(approvals=[new_approval]),
            ]
        )
        # Grant both — but only the trailing one should be resolved
        approval_service.register_session_grant(session_id, _grant_for(old_approval))
        approval_service.register_session_grant(session_id, _grant_for(new_approval))

        chat_service._resolve_pending_approvals(context, session_id)

        assert old_approval.granted is None  # not trailing — untouched
        assert new_approval.granted is True

    def test_leaves_unmatched_approvals_as_none(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
    ):
        session_id = uuid4()
        approval = _approval(component="email_send")
        context = ChatContext(
            messages=[
                UserMessage(content="Send email"),
                SystemAction(approvals=[approval]),
            ]
        )
        # No grant registered for email_send

        chat_service._resolve_pending_approvals(context, session_id)

        assert approval.granted is None

    def test_does_not_overwrite_rejected_approvals(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
    ):
        """Rejected approvals (granted=False) must not be flipped to True."""
        session_id = uuid4()
        approval = _approval()
        approval.granted = False  # Already rejected by user
        context = ChatContext(
            messages=[
                UserMessage(content="Search"),
                SystemAction(approvals=[approval]),
            ]
        )
        approval_service.register_session_grant(session_id, _grant_for(approval))

        chat_service._resolve_pending_approvals(context, session_id)

        assert approval.granted is False

    def test_selective_resolution_in_trailing_action(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
    ):
        """Only approvals with matching grants are resolved within a trailing action."""
        session_id = uuid4()
        approval_search = _approval(component="web_search")
        approval_email = _approval(component="email_send")
        context = ChatContext(
            messages=[
                UserMessage(content="Do both"),
                SystemAction(approvals=[approval_search, approval_email]),
            ]
        )
        # Only grant web_search
        approval_service.register_session_grant(session_id, _grant_for(approval_search))

        chat_service._resolve_pending_approvals(context, session_id)

        assert approval_search.granted is True
        assert approval_email.granted is None

    def test_noop_when_no_trailing_system_actions(
        self,
        chat_service: ChatService,
    ):
        """No error when context ends with a non-SystemAction message."""
        session_id = uuid4()
        context = ChatContext(
            messages=[
                UserMessage(content="Hello"),
                AssistantMessage(content="Hi there"),
            ]
        )

        # Should not raise
        chat_service._resolve_pending_approvals(context, session_id)

    def test_noop_when_context_is_empty(
        self,
        chat_service: ChatService,
    ):
        session_id = uuid4()
        context = ChatContext(messages=[])

        chat_service._resolve_pending_approvals(context, session_id)

    def test_uses_global_grants(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
    ):
        session_id = uuid4()
        approval = _approval()
        context = ChatContext(
            messages=[
                UserMessage(content="Search"),
                SystemAction(approvals=[approval]),
            ]
        )
        approval_service.register_global_grant(_grant_for(approval))

        chat_service._resolve_pending_approvals(context, session_id)

        assert approval.granted is True

    def test_already_granted_approvals_stay_granted(
        self,
        chat_service: ChatService,
    ):
        """Approvals already marked granted=True are not touched."""
        session_id = uuid4()
        approval = _approval()
        approval.granted = True
        context = ChatContext(
            messages=[
                UserMessage(content="Search"),
                SystemAction(approvals=[approval]),
            ]
        )

        chat_service._resolve_pending_approvals(context, session_id)

        assert approval.granted is True
