import uuid
from typing import Sequence

import pytest

from engine.domain.exceptions import ChatContextNotFound
from engine.domain.models import (
    AgentStats,
    Approval,
    AssistantMessage,
    ChatContext,
    ChatMessage,
    SessionInfo,
    SystemAction,
    UserMessage,
)
from engine.domain.ports.persistence import Persistence
from engine.domain.types import ApprovalType, SensitivityLevel


class TestContextPersistence:
    def test_save_and_load_context_round_trip(self, persistence: Persistence):
        session = SessionInfo()
        context = ChatContext(
            messages=[
                UserMessage(content="Hello"),
                AssistantMessage(content="Hi there!"),
                AssistantMessage(
                    content="Please remember todays appointmen at 12:00",
                    stats=AgentStats(
                        agent_name="test_agent",
                        answering_model_name="test_model",
                        duration_seconds=10.5,
                        input_tokens=100,
                        output_tokens=50,
                        requests_count=1,
                        tool_calls_count=0,
                    ),
                ),
            ]
        )

        persistence.save_context(session_id=session.session_id, context=context)
        loaded = persistence.load_context(session_id=session.session_id)

        assert len(loaded.messages) == 3
        assert isinstance(loaded.messages[0], UserMessage)
        assert loaded.messages[0].role == "user"
        assert loaded.messages[0].content == "Hello"
        assert isinstance(loaded.messages[1], AssistantMessage)
        assert loaded.messages[1].role == "assistant"
        assert loaded.messages[1].content == "Hi there!"
        assert loaded.messages[1].stats is None
        assert isinstance(loaded.messages[2], AssistantMessage)
        assert loaded.messages[2].stats == AgentStats(
            agent_name="test_agent",
            answering_model_name="test_model",
            duration_seconds=10.5,
            input_tokens=100,
            output_tokens=50,
            requests_count=1,
            tool_calls_count=0,
        )

    def test_load_context_not_found(self, persistence: Persistence):
        non_existent_id = uuid.uuid4()

        with pytest.raises(ChatContextNotFound) as exc_info:
            persistence.load_context(session_id=non_existent_id)

        assert exc_info.value.session_id == non_existent_id

    def test_system_action_round_trip(self, persistence: Persistence):
        session = SessionInfo()
        approval = Approval(
            type=ApprovalType.OutgoingData,
            component="web_search",
            purpose="Searching the web for 'test query'",
            allowed_parameters={"query": "test query"},
            internal_parameters={"tool_call_id": "call_1"},
        )
        context = ChatContext(
            messages=[
                UserMessage(content="Search for something"),
                SystemAction(
                    notification="Agent needs approval to continue",
                    approvals=[approval],
                ),
            ]
        )

        persistence.save_context(session_id=session.session_id, context=context)
        loaded = persistence.load_context(session_id=session.session_id)

        assert len(loaded.messages) == 2
        assert isinstance(loaded.messages[0], UserMessage)
        assert isinstance(loaded.messages[1], SystemAction)

        loaded_action = loaded.messages[1]
        assert loaded_action.notification == "Agent needs approval to continue"
        assert len(loaded_action.approvals) == 1

        loaded_approval = loaded_action.approvals[0]
        assert loaded_approval.component == "web_search"
        assert loaded_approval.allowed_parameters == {"query": "test query"}
        assert loaded_approval.internal_parameters == {"tool_call_id": "call_1"}
        assert loaded_approval.granted is None

    def test_sensitivity_level_round_trip(self, persistence: Persistence):
        session = SessionInfo()
        context = ChatContext(
            messages=[UserMessage(content="Hello")],
            sensitivity_level=SensitivityLevel.Personal,
        )
        persistence.save_context(session_id=session.session_id, context=context)
        loaded = persistence.load_context(session_id=session.session_id)
        assert loaded.sensitivity_level == SensitivityLevel.Personal

    def test_sensitivity_level_defaults_to_personal(self, persistence: Persistence):
        session = SessionInfo()
        context = ChatContext(messages=[UserMessage(content="Hello")])
        persistence.save_context(session_id=session.session_id, context=context)
        loaded = persistence.load_context(session_id=session.session_id)
        assert loaded.sensitivity_level == SensitivityLevel.Personal

    def test_sensitivity_level_updated_on_resave(self, persistence: Persistence):
        session = SessionInfo()
        context = ChatContext(
            messages=[UserMessage(content="Hello")],
            sensitivity_level=SensitivityLevel.OpenInformation,
        )
        persistence.save_context(session_id=session.session_id, context=context)
        context.sensitivity_level = SensitivityLevel.Confidential
        persistence.save_context(session_id=session.session_id, context=context)
        loaded = persistence.load_context(session_id=session.session_id)
        assert loaded.sensitivity_level == SensitivityLevel.Confidential

    def test_save_context_preserves_multiple_messages(self, persistence: Persistence):
        session = SessionInfo()
        messages: Sequence[ChatMessage] = [
            UserMessage(content=f"Message {i}") for i in range(5)
        ] + [AssistantMessage(content=f"Response {i}") for i in range(5)]
        context = ChatContext(messages=messages)

        persistence.save_context(session_id=session.session_id, context=context)
        loaded = persistence.load_context(session_id=session.session_id)

        assert len(loaded.messages) == 10
