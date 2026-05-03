"""Tests for YAML-specific persistence behaviour.

These tests cover concerns that only apply to the YAML adapter: file layout,
serialisation edge cases, and side effects that MemoryPersistence does not share.
"""

import textwrap
import uuid
from pathlib import Path

import pytest

from engine.adapters.yaml_persistence import YamlPersistenceAdapter
from engine.domain.exceptions import ChatContextNotFound, SessionNotFound
from engine.domain.models import (
    AssistantMessage,
    ChatContext,
    SessionInfo,
    SystemAction,
    UserMessage,
)


@pytest.fixture
def yaml_adapter(tmp_path: Path) -> YamlPersistenceAdapter:
    return YamlPersistenceAdapter(data_dir=tmp_path)


class TestYamlSessionBehaviour:
    def test_save_session_updates_timestamp(self, yaml_adapter: YamlPersistenceAdapter):
        session = SessionInfo(title="Test")
        original_updated_at = session.updated_at

        yaml_adapter.save_session(session)

        assert session.updated_at >= original_updated_at


class TestYamlFileLayout:
    def test_save_context_creates_directory_structure(
        self, yaml_adapter: YamlPersistenceAdapter, tmp_path: Path
    ):
        session = SessionInfo()
        context = ChatContext(messages=[UserMessage(content="Test")])

        yaml_adapter.save_context(session_id=session.session_id, context=context)

        expected_dir = tmp_path / "sessions" / str(session.session_id)
        assert expected_dir.exists()
        assert (expected_dir / "chat_messages.yaml").exists()


class TestYamlErrorHandling:
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


class TestFinalFieldReadTimeDefault:
    def test_old_record_without_final_loads_as_true(
        self, yaml_adapter: YamlPersistenceAdapter, tmp_path: Path
    ):
        session_id = uuid.uuid4()
        file_path = tmp_path / "sessions" / str(session_id) / "chat_messages.yaml"
        file_path.parent.mkdir(parents=True)
        file_path.write_text(
            textwrap.dedent(
                f"""\
                session_id: {session_id}
                created_at: '2025-01-01T00:00:00+00:00'
                updated_at: '2025-01-01T00:00:00+00:00'
                sensitivity_level: 2
                ---
                role: user
                content: pre-cutover user message
                timestamp: '2025-01-01T00:00:01+00:00'
                ---
                role: system
                approvals: []
                notification: pre-cutover system note
                timestamp: '2025-01-01T00:00:02+00:00'
                ---
                role: assistant
                content: pre-cutover assistant response
                timestamp: '2025-01-01T00:00:03+00:00'
                """
            )
        )

        loaded = yaml_adapter.load_context(session_id=session_id)

        assert len(loaded.messages) == 3
        assert isinstance(loaded.messages[0], UserMessage)
        assert loaded.messages[0].final is True
        assert isinstance(loaded.messages[1], SystemAction)
        assert loaded.messages[1].final is True
        assert isinstance(loaded.messages[2], AssistantMessage)
        assert loaded.messages[2].final is True

    def test_new_record_with_explicit_final_false_preserved(
        self, yaml_adapter: YamlPersistenceAdapter
    ):
        session = SessionInfo()
        context = ChatContext(
            messages=[
                UserMessage(content="in flight", final=False),
                SystemAction(notification="awaiting approval", final=False),
            ]
        )

        yaml_adapter.save_context(session_id=session.session_id, context=context)
        loaded = yaml_adapter.load_context(session_id=session.session_id)

        assert loaded.messages[0].final is False
        assert loaded.messages[1].final is False

    def test_round_trip_preserves_final_true(self, yaml_adapter: YamlPersistenceAdapter):
        session = SessionInfo()
        context = ChatContext(
            messages=[
                UserMessage(content="settled", final=True),
                AssistantMessage(content="response"),
            ]
        )

        yaml_adapter.save_context(session_id=session.session_id, context=context)
        loaded = yaml_adapter.load_context(session_id=session.session_id)

        assert loaded.messages[0].final is True
        assert loaded.messages[1].final is True
