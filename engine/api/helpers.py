from engine.adapters.pydantic_ai_execution.pydantic_execution import (
    PydanticAgentAdapter,
)
from engine.adapters.sqlite_event_store.sqlite_backend import SqliteEventStoreAdapter
from engine.adapters.yaml_persistence.yaml_adapter import YamlPersistenceAdapter
from engine.constants import DATA_DIR, DEBUG_DUMPS
from engine.domain.ports.events import EventStore
from engine.domain.services import ChatService


def dependency_chat_service() -> ChatService:
    return ChatService(
        persistence_repository=YamlPersistenceAdapter(data_dir=DATA_DIR),
        agent_execution=PydanticAgentAdapter(debug_dumps=DEBUG_DUMPS),
        event_store=dependency_event_store(),
    )


def dependency_event_store() -> EventStore:
    """Creates and preserves a single EventStore instance."""
    if hasattr(dependency_event_store, "_instance") and isinstance(
        event_store := getattr(dependency_event_store, "_instance"), EventStore
    ):
        return event_store
    event_store = SqliteEventStoreAdapter(db_path=DATA_DIR / "events.db")
    setattr(dependency_event_store, "_instance", event_store)
    return event_store
