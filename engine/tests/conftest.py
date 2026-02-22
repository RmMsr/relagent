import configparser
import uuid
from datetime import datetime, timezone
from uuid import UUID

import pytest

from engine.adapters.test_adapters import (
    EchoAgentExecution,
    MemoryEventStoreAdapter,
    MemoryPersistence,
)
from engine.domain.models import (
    AgentStats,
    AssistantMessage,
    ChatContext,
    SessionInfo,
    UserMessage,
)
from engine.domain.ports.events import EventStore
from engine.domain.ports.persistence import Persistence
from engine.domain.services import ChatService

# Inject an empty config parser before any engine module reads settings.ini.
# This must happen before importing modules that transitively import
# engine.constants (which calls get_setting at import time).
from engine.settings import override_config_parser

override_config_parser(configparser.ConfigParser())


@pytest.fixture
def sample_session_id() -> UUID:
    return uuid.UUID("151a0cfb-74bb-4978-8881-3d15e4017a5e")


@pytest.fixture
def sample_session(sample_session_id: UUID) -> SessionInfo:
    return SessionInfo(
        session_id=sample_session_id,
        title="Test Session",
        created_at=datetime(2024, 1, 1, 12, 0, 0, tzinfo=timezone.utc),
        updated_at=datetime(2024, 1, 1, 12, 0, 0, tzinfo=timezone.utc),
    )


@pytest.fixture
def persisted_session_with_context(
    sample_session: SessionInfo, sample_context: ChatContext, persistence: Persistence
):
    persistence.save_session(sample_session)
    persistence.save_context(sample_session.session_id, sample_context)
    return sample_session


@pytest.fixture
def sample_user_message() -> UserMessage:
    return UserMessage(
        content="Hello, how are you?",
        timestamp=datetime(2024, 1, 1, 12, 0, 0, tzinfo=timezone.utc),
    )


@pytest.fixture
def sample_assistant_message() -> AssistantMessage:
    return AssistantMessage(
        content="I'm doing well, thank you!",
        timestamp=datetime(2024, 1, 1, 12, 0, 1, tzinfo=timezone.utc),
        stats=AgentStats(
            agent_name="discussion",
            input_tokens=150,
            output_tokens=75,
        ),
    )


@pytest.fixture
def sample_context(
    sample_user_message: UserMessage, sample_assistant_message: AssistantMessage
) -> ChatContext:
    return ChatContext(messages=[sample_user_message, sample_assistant_message])


@pytest.fixture
def persistence() -> Persistence:
    """In-memory persistence adapter for testing."""
    return MemoryPersistence()


@pytest.fixture
def event_store() -> EventStore:
    """In-memory event store adapter for testing."""
    return MemoryEventStoreAdapter()


@pytest.fixture
def echo_agent_execution() -> EchoAgentExecution:
    """Echo agent execution for testing."""
    return EchoAgentExecution()


@pytest.fixture
def chat_service(
    persistence: Persistence,
    echo_agent_execution: EchoAgentExecution,
    event_store: EventStore,
) -> ChatService:
    """Chat service with real in-memory adapters."""
    return ChatService(
        persistence_repository=persistence,
        agent_execution=echo_agent_execution,
        event_store=event_store,
    )
