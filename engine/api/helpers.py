from fastapi import Depends, HTTPException
from fastapi.security import APIKeyHeader
from engine.adapters.pydantic_ai_execution.pydantic_execution import (
    PydanticAgentAdapter,
)
from engine.adapters.sqlite_event_store.sqlite_backend import SqliteEventStoreAdapter
from engine.adapters.yaml_persistence.yaml_adapter import YamlPersistenceAdapter
from engine.constants import DATA_DIR, DEBUG_DUMPS, SECRET_ACCESS_KEY
from engine.domain.ports.events import EventStore
from engine.domain.services import ChatService
from engine.logging import get_logger

logger = get_logger(__name__)


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


header_scheme = APIKeyHeader(name="X-API-Key", auto_error=False)


def validate_api_key(key_to_check: str | None) -> bool:
    if SECRET_ACCESS_KEY == "":
        return True
    elif key_to_check is not None and key_to_check == SECRET_ACCESS_KEY:
        return True
    return False


async def require_api_key(
    api_key: str | None = Depends(header_scheme),
) -> None:
    if not validate_api_key(key_to_check=api_key):
        raise HTTPException(
            status_code=401, detail="Invalid API key. Use X-API-Key header."
        )


def check_secret_key():
    if not SECRET_ACCESS_KEY:
        logger.warning(
            "!!! Empty server.secret_access_key (env SERVER_SECRET_ACCESS_KEY) detected. Please secure the API endpoints."
        )
