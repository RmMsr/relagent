import uuid
from datetime import datetime, timezone

import pytest

from engine.domain.models import (
    AgentStats,
    Approval,
    AssistantMessage,
    ChatContext,
    ChatRequest,
    Grant,
    PermissionKey,
    SessionInfo,
    SystemAction,
    UserMessage,
)
from engine.domain.types import ApprovalType, SensitivityLevel


class TestSessionInfo:
    def test_default_session_id_is_valid_uuid(self):
        session = SessionInfo()
        assert isinstance(session.session_id, uuid.UUID)

    def test_default_timestamps_are_set(self):
        before = datetime.now(timezone.utc)
        session = SessionInfo()
        after = datetime.now(timezone.utc)

        assert before <= session.created_at <= after
        assert before <= session.updated_at <= after

    def test_custom_values_preserved(self):
        session_id = uuid.uuid4()
        created = datetime(2024, 1, 1, tzinfo=timezone.utc)
        session = SessionInfo(
            session_id=session_id, title="My Session", created_at=created
        )

        assert session.session_id == session_id
        assert session.title == "My Session"
        assert session.created_at == created


class TestUserMessage:
    def test_role_is_user(self):
        msg = UserMessage(content="Hello")
        assert msg.role == "user"

    def test_default_timestamp_is_set(self):
        before = datetime.now(timezone.utc)
        msg = UserMessage(content="Hello")
        after = datetime.now(timezone.utc)

        assert before <= msg.timestamp <= after

    def test_invalid_role_raises_value_error(self):
        with pytest.raises(ValueError):
            UserMessage(content="Hello", role="assistant")  # type: ignore[arg-type]

    def test_default_final_is_false(self):
        msg = UserMessage(content="Hello")
        assert msg.final is False

    def test_explicit_final_preserved(self):
        msg = UserMessage(content="Hello", final=True)
        assert msg.final is True


class TestAgentStats:
    def test_default_values_are_none(self):
        stats = AgentStats()
        assert stats.agent_name is None
        assert stats.input_tokens is None

    def test_custom_values_preserved(self):
        stats = AgentStats(agent_name="test", duration_seconds=10.5, input_tokens=100)
        assert stats.agent_name == "test"
        assert stats.duration_seconds == 10.5


class TestAssistantMessage:
    def test_role_is_assistant(self):
        msg = AssistantMessage(content="Hi there")
        assert msg.role == "assistant"

    def test_invalid_role_raises_value_error(self):
        with pytest.raises(ValueError):
            AssistantMessage(content="Hello", role="user")  # type: ignore[arg-type]

    def test_has_default_stats(self):
        msg = AssistantMessage(content="Response")
        assert msg.stats is None

    def test_custom_stats_preserved(self):
        stats = AgentStats(agent_name="test", input_tokens=200)
        msg = AssistantMessage(content="Response", stats=stats)
        assert msg.stats is not None
        assert msg.stats.agent_name == "test"

    def test_default_final_is_true(self):
        msg = AssistantMessage(content="Response")
        assert msg.final is True


class TestChatContext:
    def test_default_messages_is_empty_list(self):
        ctx = ChatContext()
        assert ctx.messages == []

    def test_messages_preserved(
        self,
        sample_user_message: UserMessage,
        sample_assistant_message: AssistantMessage,
    ):
        ctx = ChatContext(messages=[sample_user_message, sample_assistant_message])
        assert len(ctx.messages) == 2
        assert ctx.messages[0].role == "user"
        assert ctx.messages[1].role == "assistant"


class TestChatRequest:
    def test_default_session_id_is_none(self):
        request = ChatRequest()
        assert request.session_id is None

    def test_default_messages_is_empty_list(self):
        request = ChatRequest()
        assert request.messages == []


class TestMessageSerialization:
    def test_user_message_round_trip(self):
        msg = UserMessage(content="Test")
        data = msg.model_dump(mode="json")
        restored = UserMessage.model_validate(data)

        assert restored.content == msg.content
        assert restored.role == "user"

    def test_assistant_message_round_trip(self):
        msg = AssistantMessage(content="Response")
        data = msg.model_dump(mode="json")
        restored = AssistantMessage.model_validate(data)

        assert restored.content == msg.content
        assert restored.role == "assistant"

    def test_assistant_message_stats_round_trip(self):
        stats = AgentStats(
            agent_name="test-agent",
            answering_model_name="test-model",
            duration_seconds=10.5,
            input_tokens=500,
            output_tokens=250,
            requests_count=2,
            tool_calls_count=1,
        )
        msg = AssistantMessage(content="Response", stats=stats)
        restored = AssistantMessage.model_validate(msg.model_dump(mode="json"))

        assert restored.stats is not None
        assert restored.stats.agent_name == "test-agent"
        assert restored.stats.answering_model_name == "test-model"
        assert restored.stats.duration_seconds == 10.5
        assert restored.stats.input_tokens == 500
        assert restored.stats.output_tokens == 250
        assert restored.stats.requests_count == 2
        assert restored.stats.tool_calls_count == 1

    def test_messages_distinguished_by_role(self):
        user_data = {"role": "user", "content": "Hello"}
        assistant_data = {"role": "assistant", "content": "Hi"}

        user_msg = UserMessage.model_validate(user_data)
        assistant_msg = AssistantMessage.model_validate(assistant_data)

        assert user_msg.role == "user"
        assert assistant_msg.role == "assistant"

    def test_user_message_final_round_trip(self):
        msg = UserMessage(content="Test", final=True)
        restored = UserMessage.model_validate(msg.model_dump(mode="json"))
        assert restored.final is True

    def test_assistant_message_final_round_trip(self):
        msg = AssistantMessage(content="Response")
        restored = AssistantMessage.model_validate(msg.model_dump(mode="json"))
        assert restored.final is True

    def test_system_action_final_round_trip(self):
        action = SystemAction(final=True)
        restored = SystemAction.model_validate(action.model_dump(mode="json"))
        assert restored.final is True

    def test_user_message_serializes_final_field(self):
        msg = UserMessage(content="Test")
        data = msg.model_dump(mode="json")
        assert "final" in data
        assert data["final"] is False


class TestApproval:
    def test_defaults(self):
        approval = Approval(type=ApprovalType.OutgoingData, purpose="test")
        assert approval.type == ApprovalType.OutgoingData
        assert approval.component is None
        assert approval.allowed_parameters == {}
        assert approval.internal_parameters == {}
        assert approval.sensitivity == SensitivityLevel.OpenInformation
        assert approval.granted is None
        assert approval.expires_at is None

    def test_permission_key_uses_type_component_parameters_sensitivity(self):
        approval = Approval(
            type=ApprovalType.OutgoingData,
            component="web_search",
            allowed_parameters={"provider": "ddg"},
            sensitivity=SensitivityLevel.Personal,
            purpose="test",
        )
        key = approval.permission_key
        assert key.approval_type == ApprovalType.OutgoingData
        assert key.component == "web_search"
        assert key.sensitivity == SensitivityLevel.Personal
        assert key.allowed_parameters == (("provider", "ddg"),)

    def test_permission_key_excludes_internal_parameters(self):
        approval = Approval(
            type=ApprovalType.OutgoingData,
            purpose="test",
            internal_parameters={"tool_call_id": "call_123"},
        )
        key = approval.permission_key
        assert not hasattr(key, "internal_parameters")
        assert key.allowed_parameters == ()

    def test_permission_key_sorts_allowed_parameters(self):
        approval = Approval(
            type=ApprovalType.OutgoingData,
            purpose="test",
            allowed_parameters={"z_key": "last", "a_key": "first"},
        )
        key = approval.permission_key
        assert key.allowed_parameters == (("a_key", "first"), ("z_key", "last"))


class TestGrant:
    def test_defaults(self):
        grant = Grant(approval_type=ApprovalType.NoneRequired)
        assert grant.approval_type == ApprovalType.NoneRequired
        assert grant.component is None
        assert grant.allowed_parameters == {}
        assert grant.max_sensitivity == SensitivityLevel.OpenInformation
        assert grant.expires_at is None

    def test_is_immutable(self):
        grant = Grant(approval_type=ApprovalType.NoneRequired)
        with pytest.raises(Exception):
            grant.component = "web_search"  # type: ignore[misc]

    def test_permission_key_structure(self):
        grant = Grant(
            approval_type=ApprovalType.OutgoingData,
            component="web_search",
            allowed_parameters={"provider": "ddg"},
            max_sensitivity=SensitivityLevel.Confidential,
        )
        key = grant.permission_key
        assert key.approval_type == ApprovalType.OutgoingData
        assert key.component == "web_search"
        assert key.sensitivity == SensitivityLevel.Confidential
        assert key.allowed_parameters == (("provider", "ddg"),)

    def test_permission_key_sorts_allowed_parameters(self):
        grant = Grant(
            approval_type=ApprovalType.OutgoingData,
            allowed_parameters={"z_key": "last", "a_key": "first"},
        )
        key = grant.permission_key
        assert key.allowed_parameters == (("a_key", "first"), ("z_key", "last"))

    def test_wildcard_parameter_not_in_allowed_parameters(self):
        with pytest.raises(ValueError, match="wildcard_parameter"):
            Grant(
                approval_type=ApprovalType.OutgoingData,
                allowed_parameters={"query": "python"},
                wildcard_parameter="query",
            )

    def test_wildcard_parameter_absent_from_allowed_parameters_is_valid(self):
        grant = Grant(
            approval_type=ApprovalType.OutgoingData,
            allowed_parameters={"provider": "ddg"},
            wildcard_parameter="query",
        )
        assert grant.wildcard_parameter == "query"
        assert "query" not in grant.allowed_parameters

    def test_wildcard_parameter_none_with_allowed_parameters_is_valid(self):
        grant = Grant(
            approval_type=ApprovalType.OutgoingData,
            allowed_parameters={"query": "python"},
        )
        assert grant.wildcard_parameter is None
        assert grant.allowed_parameters == {"query": "python"}


class TestPermissionKeyConsistency:
    def test_matching_approval_and_grant_produce_equal_keys(self):
        approval = Approval(
            type=ApprovalType.OutgoingData,
            component="web_search",
            allowed_parameters={"provider": "ddg"},
            sensitivity=SensitivityLevel.Personal,
            purpose="test",
        )
        grant = Grant(
            approval_type=ApprovalType.OutgoingData,
            component="web_search",
            allowed_parameters={"provider": "ddg"},
            max_sensitivity=SensitivityLevel.Personal,
        )
        assert approval.permission_key == grant.permission_key

    def test_different_component_produces_different_keys(self):
        approval = Approval(
            type=ApprovalType.OutgoingData,
            component="web_search",
            purpose="test",
        )
        grant = Grant(
            approval_type=ApprovalType.OutgoingData,
            component="email_send",
        )
        assert approval.permission_key != grant.permission_key

    def test_permission_key_is_hashable(self):
        grant = Grant(
            approval_type=ApprovalType.OutgoingData,
            component="web_search",
        )
        key = grant.permission_key
        assert isinstance(key, PermissionKey)
        d = {key: grant}
        assert d[key] == grant


class TestSystemAction:
    def test_role_is_system(self):
        action = SystemAction()
        assert action.role == "system"

    def test_default_approvals_is_empty(self):
        action = SystemAction()
        assert action.approvals == []

    def test_approvals_preserved(self):
        approval = Approval(type=ApprovalType.OutgoingData, purpose="test")
        action = SystemAction(approvals=[approval])
        assert len(action.approvals) == 1
        assert action.approvals[0].purpose == "test"

    def test_default_final_is_false(self):
        action = SystemAction()
        assert action.final is False

    def test_explicit_final_preserved(self):
        action = SystemAction(final=True)
        assert action.final is True
