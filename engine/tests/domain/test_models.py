import uuid
from datetime import datetime, timezone

import pytest

from engine.domain.models import (
    AssistantMessage,
    ChatContext,
    ChatRequest,
    SessionInfo,
    UserMessage,
)


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


class TestAssistantMessage:
    def test_role_is_assistant(self):
        msg = AssistantMessage(content="Hi there")
        assert msg.role == "assistant"

    def test_invalid_role_raises_value_error(self):
        with pytest.raises(ValueError):
            AssistantMessage(content="Hello", role="user")  # type: ignore[arg-type]


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

    def test_messages_distinguished_by_role(self):
        user_data = {"role": "user", "content": "Hello"}
        assistant_data = {"role": "assistant", "content": "Hi"}

        user_msg = UserMessage.model_validate(user_data)
        assistant_msg = AssistantMessage.model_validate(assistant_data)

        assert user_msg.role == "user"
        assert assistant_msg.role == "assistant"
