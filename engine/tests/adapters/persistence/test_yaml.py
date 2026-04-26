"""Tests for YAML-specific persistence behaviour.

These tests cover concerns that only apply to the YAML adapter: file layout,
serialisation edge cases, and side effects that MemoryPersistence does not share.
"""

import uuid
from pathlib import Path

import pytest

from engine.adapters.yaml_persistence import YamlPersistenceAdapter
from engine.domain.exceptions import ChatContextNotFound, SessionNotFound
from engine.domain.models import ChatContext, SessionInfo, UserMessage


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
