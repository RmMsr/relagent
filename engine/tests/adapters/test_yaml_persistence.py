import uuid
from pathlib import Path

import pytest

from engine.adapters.yaml_persistence import YamlPersistenceAdapter
from engine.domain.exceptions import ChatContextNotFound, SessionNotFound
from engine.domain.models import (
    AssistantMessage,
    ChatContext,
    SessionInfo,
    UserMessage,
)


@pytest.fixture
def yaml_adapter(tmp_path: Path) -> YamlPersistenceAdapter:
    return YamlPersistenceAdapter(data_dir=tmp_path)


class TestSessionPersistence:
    def test_save_and_load_session_round_trip(self, yaml_adapter: YamlPersistenceAdapter):
        session = SessionInfo(title="Test Session")

        yaml_adapter.save_session(session)
        loaded = yaml_adapter.load_session(session_id=session.session_id)

        assert loaded.session_id == session.session_id
        assert loaded.title == session.title

    def test_load_session_not_found(self, yaml_adapter: YamlPersistenceAdapter):
        non_existent_id = uuid.uuid4()

        with pytest.raises(SessionNotFound) as exc_info:
            yaml_adapter.load_session(session_id=non_existent_id)

        assert exc_info.value.session_id == non_existent_id

    def test_save_session_updates_timestamp(self, yaml_adapter: YamlPersistenceAdapter):
        session = SessionInfo(title="Test")
        original_updated_at = session.updated_at

        yaml_adapter.save_session(session)

        assert session.updated_at >= original_updated_at


class TestContextPersistence:
    def test_save_and_load_context_round_trip(
        self, yaml_adapter: YamlPersistenceAdapter
    ):
        session = SessionInfo()
        context = ChatContext(
            messages=[
                UserMessage(content="Hello"),
                AssistantMessage(content="Hi there!"),
            ]
        )

        yaml_adapter.save_context(session=session, context=context)
        loaded = yaml_adapter.load_context(session_id=session.session_id)

        assert len(loaded.messages) == 2
        assert loaded.messages[0].role == "user"
        assert loaded.messages[0].content == "Hello"
        assert loaded.messages[1].role == "assistant"
        assert loaded.messages[1].content == "Hi there!"

    def test_load_context_not_found(self, yaml_adapter: YamlPersistenceAdapter):
        non_existent_id = uuid.uuid4()

        with pytest.raises(ChatContextNotFound) as exc_info:
            yaml_adapter.load_context(session_id=non_existent_id)

        assert exc_info.value.session_id == non_existent_id

    def test_save_context_creates_directory_structure(
        self, yaml_adapter: YamlPersistenceAdapter, tmp_path: Path
    ):
        session = SessionInfo()
        context = ChatContext(messages=[UserMessage(content="Test")])

        yaml_adapter.save_context(session=session, context=context)

        expected_dir = tmp_path / "sessions" / str(session.session_id)
        assert expected_dir.exists()
        assert (expected_dir / "chat_messages.yaml").exists()

    def test_save_context_preserves_multiple_messages(
        self, yaml_adapter: YamlPersistenceAdapter
    ):
        session = SessionInfo()
        messages = [
            UserMessage(content=f"Message {i}") for i in range(5)
        ] + [
            AssistantMessage(content=f"Response {i}") for i in range(5)
        ]
        context = ChatContext(messages=messages)

        yaml_adapter.save_context(session=session, context=context)
        loaded = yaml_adapter.load_context(session_id=session.session_id)

        assert len(loaded.messages) == 10


class TestErrorHandling:
    def test_load_context_with_empty_file(
        self, yaml_adapter: YamlPersistenceAdapter, tmp_path: Path
    ):
        session_id = uuid.uuid4()
        file_path = tmp_path / "sessions" / str(session_id) / "chat_messages.yaml"
        file_path.parent.mkdir(parents=True)
        file_path.write_text("")

        with pytest.raises(ChatContextNotFound):
            yaml_adapter.load_context(session_id=session_id)

    def test_load_session_with_invalid_yaml(
        self, yaml_adapter: YamlPersistenceAdapter, tmp_path: Path
    ):
        session_id = uuid.uuid4()
        file_path = tmp_path / "sessions" / str(session_id) / "session_info.yaml"
        file_path.parent.mkdir(parents=True)
        file_path.write_text("invalid: yaml: content: [")

        with pytest.raises(SessionNotFound):
            yaml_adapter.load_session(session_id=session_id)
