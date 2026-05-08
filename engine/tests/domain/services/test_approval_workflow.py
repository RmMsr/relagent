"""Workflow tests for the approval lifecycle.

These tests exercise the interaction between ChatService and ApprovalService
across multiple steps — user input, approval request, grant/reject, and continue.
"""

import pytest

from engine.adapters.test_adapters import MemoryEventStoreAdapter, StubAgentExecution
from engine.domain.models import (
    Approval,
    AssistantMessage,
    ChatRequest,
    Grant,
    SystemAction,
    UserMessage,
)
from engine.domain.ports.events import SessionMessagesAppendedEvent
from engine.domain.services import ApprovalService, ChatService
from engine.domain.types import ApprovalType, SensitivityLevel


def _approval(**kwargs) -> Approval:
    defaults = dict(
        type=ApprovalType.OutgoingData,
        component="web_search",
        purpose="Searching the web",
        sensitivity=SensitivityLevel.OpenInformation,
    )
    return Approval(**{**defaults, **kwargs})


def _grant_for(approval: Approval) -> Grant:
    """Create a grant that satisfies the given approval."""
    return Grant(
        approval_type=approval.type,
        component=approval.component,
        max_sensitivity=approval.sensitivity,
        allowed_parameters=approval.allowed_parameters,
    )


class TestApprovalGrantWorkflow:
    """User asks → agent requests approval → user grants → agent continues."""

    async def test_grant_then_continue_produces_assistant_response(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
        echo_agent_execution: StubAgentExecution,
    ):
        approval = _approval()

        # 1. Agent requests approval on first call, responds on second
        echo_agent_execution.prime_basic_query(SystemAction(approvals=[approval]))
        echo_agent_execution.prime_basic_query(
            AssistantMessage(content="Here are your search results")
        )

        # 2. User sends a message → agent returns SystemAction
        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Search for news")])
        )
        session_id = response.session_id
        assert isinstance(response.message, SystemAction)
        assert len(response.message.approvals) == 1

        # 3. User grants the approval
        approval_service.register_session_grant(session_id, _grant_for(approval))

        # 4. Continue → agent sees grant and proceeds
        response = await chat_service.continue_session(session_id)
        assert isinstance(response.message, AssistantMessage)
        assert response.message.content == "Here are your search results"
        history = chat_service.get_messages(session_id=session_id)
        assert len(history.messages) == 3
        assert history.messages[0].role == "user"
        assert history.messages[1].role == "system"
        assert len(history.messages[1].approvals) == 1
        assert history.messages[1].approvals[0].granted is True
        assert history.messages[2].role == "assistant"

    async def test_continue_updates_approval_granted_in_persisted_context(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
        echo_agent_execution: StubAgentExecution,
    ):
        """After continue, the persisted context must reflect granted=True."""
        approval = _approval()
        echo_agent_execution.prime_basic_query(SystemAction(approvals=[approval]))
        echo_agent_execution.prime_basic_query(AssistantMessage(content="Done"))

        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Do it")])
        )
        session_id = response.session_id
        approval_service.register_session_grant(session_id, _grant_for(approval))

        await chat_service.continue_session(session_id)

        # Re-load context from persistence to confirm the grant is persisted
        context = chat_service.ensure_context(session_id)
        system_actions = [m for m in context.messages if isinstance(m, SystemAction)]
        assert system_actions[0].approvals[0].granted is True

    async def test_continue_with_global_grant_resolves_approval(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
        echo_agent_execution: StubAgentExecution,
    ):
        """A global grant should also resolve pending approvals on continue."""
        approval = _approval()
        echo_agent_execution.prime_basic_query(SystemAction(approvals=[approval]))
        echo_agent_execution.prime_basic_query(AssistantMessage(content="Done"))

        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Search")])
        )
        session_id = response.session_id

        # Register a global grant (not session-specific)
        approval_service.register_global_grant(_grant_for(approval))

        await chat_service.continue_session(session_id)

        context = chat_service.ensure_context(session_id)
        system_actions = [m for m in context.messages if isinstance(m, SystemAction)]
        assert system_actions[0].approvals[0].granted is True

    async def test_continue_without_grant_leaves_approval_pending(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
        echo_agent_execution: StubAgentExecution,
    ):
        """If no grant matches, approval stays None after continue."""
        approval = _approval()
        echo_agent_execution.prime_basic_query(SystemAction(approvals=[approval]))
        echo_agent_execution.prime_basic_query(
            AssistantMessage(content="Still waiting")
        )

        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Search")])
        )
        session_id = response.session_id

        # No grant registered — continue anyway
        await chat_service.continue_session(session_id)

        context = chat_service.ensure_context(session_id)
        system_actions = [m for m in context.messages if isinstance(m, SystemAction)]
        assert system_actions[0].approvals[0].granted is None

    async def test_continue_resolves_multiple_approvals_selectively(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
        echo_agent_execution: StubAgentExecution,
    ):
        """Only approvals with matching grants are resolved; others stay pending."""
        approval_search = _approval(component="web_search")
        approval_email = _approval(component="email_send")
        echo_agent_execution.prime_basic_query(
            SystemAction(approvals=[approval_search, approval_email])
        )
        echo_agent_execution.prime_basic_query(AssistantMessage(content="Partial"))

        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Do both")])
        )
        session_id = response.session_id

        # Only grant web_search
        approval_service.register_session_grant(session_id, _grant_for(approval_search))

        await chat_service.continue_session(session_id)

        context = chat_service.ensure_context(session_id)
        system_actions = [m for m in context.messages if isinstance(m, SystemAction)]
        approvals_by_component = {a.component: a for a in system_actions[0].approvals}
        assert approvals_by_component["web_search"].granted is True
        assert approvals_by_component["email_send"].granted is None

    async def test_continue_does_not_overwrite_rejected_approval(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
        echo_agent_execution: StubAgentExecution,
    ):
        """A rejected approval should not be flipped to granted even if a grant exists."""
        approval = _approval()
        echo_agent_execution.prime_basic_query(SystemAction(approvals=[approval]))
        echo_agent_execution.prime_basic_query(AssistantMessage(content="Acknowledged"))

        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Search")])
        )
        session_id = response.session_id

        # Reject first, then register a grant
        approval_service.reject_session_approvals(session_id, approvals=[approval.id])
        approval_service.register_session_grant(session_id, _grant_for(approval))

        await chat_service.continue_session(session_id)

        context = chat_service.ensure_context(session_id)
        system_actions = [m for m in context.messages if isinstance(m, SystemAction)]
        # Rejection takes precedence — the user explicitly said no
        assert system_actions[0].approvals[0].granted is False


class TestApprovalRejectWorkflow:
    """User asks → agent requests approval → user rejects → agent backs off."""

    async def test_reject_then_continue_produces_assistant_response(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
        echo_agent_execution: StubAgentExecution,
    ):
        approval = _approval()

        # 1. Agent requests approval on first call, acknowledges rejection on second
        echo_agent_execution.prime_basic_query(SystemAction(approvals=[approval]))
        echo_agent_execution.prime_basic_query(
            AssistantMessage(content="Understood, I won't search the web")
        )

        # 2. User sends a message → agent returns SystemAction
        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Search for news")])
        )
        session_id = response.session_id
        assert isinstance(response.message, SystemAction)

        # 3. User rejects the approval
        approval_service.reject_session_approvals(session_id, approvals=[approval.id])

        # 4. Verify the approval is marked as rejected in context
        context = chat_service.ensure_context(session_id)
        system_actions = [m for m in context.messages if isinstance(m, SystemAction)]
        rejected = [
            a
            for action in system_actions
            for a in action.approvals
            if a.granted is False
        ]
        assert len(rejected) == 1
        assert rejected[0].id == approval.id

        # 5. Continue → agent responds acknowledging the rejection
        response = await chat_service.continue_session(session_id)
        assert isinstance(response.message, AssistantMessage)
        assert response.message.content == "Understood, I won't search the web"


class TestPartialRejectWorkflow:
    """User asks → agent requests 3 approvals → user rejects the middle one → continue."""

    async def test_reject_one_of_three_approvals(
        self,
        chat_service: ChatService,
        approval_service: ApprovalService,
        echo_agent_execution: StubAgentExecution,
    ):
        approval_search = _approval(component="web_search", purpose="Search the web")
        approval_email = _approval(component="email_send", purpose="Send an email")
        approval_calendar = _approval(
            component="calendar_read", purpose="Read calendar"
        )

        # 1. Agent requests all three, then acknowledges partial rejection
        echo_agent_execution.prime_basic_query(
            SystemAction(approvals=[approval_search, approval_email, approval_calendar])
        )
        echo_agent_execution.prime_basic_query(
            AssistantMessage(
                content="I'll skip the email but proceed with search and calendar"
            )
        )

        # 2. User sends a message → agent returns SystemAction with 3 approvals
        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Plan my day")])
        )
        session_id = response.session_id
        assert isinstance(response.message, SystemAction)
        assert len(response.message.approvals) == 3

        # 3. User rejects only the email approval
        approval_service.reject_session_approvals(
            session_id, approvals=[approval_email.id]
        )

        # 4. Verify only email is rejected, others remain pending
        context = chat_service.ensure_context(session_id)
        system_actions = [m for m in context.messages if isinstance(m, SystemAction)]
        approvals_in_context = {
            a.id: a for action in system_actions for a in action.approvals
        }
        assert approvals_in_context[approval_search.id].granted is None
        assert approvals_in_context[approval_email.id].granted is False
        assert approvals_in_context[approval_calendar.id].granted is None

        # 5. Continue → agent acknowledges partial rejection
        response = await chat_service.continue_session(session_id)
        assert isinstance(response.message, AssistantMessage)
        assert "skip the email" in response.message.content


class TestContinueSession:
    """Tests for ChatService.continue_session side effects."""

    async def test_continue_appends_response_to_context(
        self,
        chat_service: ChatService,
        echo_agent_execution: StubAgentExecution,
    ):
        """continue_session appends the agent response to persisted context."""
        echo_agent_execution.prime_basic_query(
            AssistantMessage(content="First response")
        )
        echo_agent_execution.prime_basic_query(
            AssistantMessage(content="Continued response")
        )

        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Hello")])
        )
        session_id = response.session_id

        await chat_service.continue_session(session_id)

        history = chat_service.get_messages(session_id=session_id)
        assert len(history.messages) == 3
        assert isinstance(history.messages[2], AssistantMessage)
        assert history.messages[2].content == "Continued response"

    async def test_continue_returns_message_with_id(
        self,
        chat_service: ChatService,
        echo_agent_execution: StubAgentExecution,
    ):
        """Messages from continue have a UUID message_id."""
        echo_agent_execution.prime_basic_query(AssistantMessage(content="First"))
        echo_agent_execution.prime_basic_query(AssistantMessage(content="Second"))

        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Hi")])
        )
        session_id = response.session_id

        cont_response = await chat_service.continue_session(session_id)
        assert cont_response.message.message_id is not None

    async def test_continue_publishes_messages_appended_event(
        self,
        chat_service: ChatService,
        echo_agent_execution: StubAgentExecution,
        event_store: MemoryEventStoreAdapter,
    ):
        """continue_session must publish a messages.appended event."""
        echo_agent_execution.prime_basic_query(AssistantMessage(content="First"))
        echo_agent_execution.prime_basic_query(AssistantMessage(content="Continued"))

        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Go")])
        )
        session_id = response.session_id

        # Clear events from perform_user_input
        event_store.events.clear()

        await chat_service.continue_session(session_id)

        appended_events = [
            e for e in event_store.events if isinstance(e, SessionMessagesAppendedEvent)
        ]
        assert len(appended_events) == 1
        assert appended_events[0].session_id == session_id

    async def test_continue_returns_current_sensitivity_level(
        self,
        chat_service: ChatService,
        echo_agent_execution: StubAgentExecution,
    ):
        """Response includes the context's sensitivity level."""
        echo_agent_execution.prime_basic_query(AssistantMessage(content="First"))
        echo_agent_execution.prime_basic_query(AssistantMessage(content="Continued"))

        response = await chat_service.perform_user_input(
            ChatRequest(messages=[UserMessage(content="Hi")])
        )
        session_id = response.session_id

        # Change sensitivity
        chat_service.set_sensitivity_level(session_id, SensitivityLevel.Confidential)

        cont_response = await chat_service.continue_session(session_id)
        assert cont_response.sensitivity_level == SensitivityLevel.Confidential

    async def test_continue_raises_on_unknown_session(
        self,
        chat_service: ChatService,
    ):
        """continue_session raises SessionNotFound for unknown session IDs."""
        from uuid import uuid4
        from engine.domain.exceptions import SessionNotFound

        with pytest.raises(SessionNotFound):
            await chat_service.continue_session(uuid4())
