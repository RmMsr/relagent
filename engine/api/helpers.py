from functools import cache
from typing import AsyncGenerator

from fastapi import Depends, FastAPI, HTTPException
from fastapi.concurrency import asynccontextmanager
from fastapi.security import APIKeyHeader

from engine.adapters.pydantic_ai_execution.queries import (
    PydanticAgentAdapter,
)
from engine.adapters.sqlite_event_store.sqlite_backend import SqliteEventStoreAdapter
from engine.adapters.yaml_persistence.yaml_adapter import YamlPersistenceAdapter
from engine.constants import DATA_DIR, DEBUG_DUMPS, SECRET_ACCESS_KEY, WEB_DIR
from engine.domain.ports.events import EventStore
from engine.domain.ports.persistence import Persistence
from engine.domain.services import AgentExecution, ApprovalService, ChatService
from engine.log_config import get_logger

logger = get_logger(__name__)


@cache
def dependency_persistence() -> Persistence:
    return YamlPersistenceAdapter(data_dir=DATA_DIR)


@cache
def dependency_event_store() -> EventStore:
    """Creates and preserves a single EventStore instance."""
    return SqliteEventStoreAdapter(db_path=DATA_DIR / "events.db")


@cache
def dependency_approval_service() -> ApprovalService:
    return ApprovalService(persistence_repository=dependency_persistence())


def dependency_agent_execution() -> AgentExecution:
    return PydanticAgentAdapter(
        approval_service=dependency_approval_service(),
        debug_dumps=DEBUG_DUMPS,
    )


def dependency_chat_service(
    agent_execution: AgentExecution = Depends(dependency_agent_execution),
) -> ChatService:
    return ChatService(
        persistence_repository=dependency_persistence(),
        agent_execution=agent_execution,
        event_store=dependency_event_store(),
        approval_service=dependency_approval_service(),
    )


def validate_api_key(key_to_check: str | None) -> bool:
    if SECRET_ACCESS_KEY == "":
        return True
    elif key_to_check is not None and key_to_check == SECRET_ACCESS_KEY:
        return True
    return False


header_scheme = APIKeyHeader(name="X-API-Key", auto_error=False)


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


@cache
def is_web_available() -> bool:
    if WEB_DIR.is_dir() and (WEB_DIR / "index.html").exists():
        logger.info("Serving web app from %s at /app/", WEB_DIR)
        return True
    return False


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    yield
    event_store = dependency_event_store()
    if event_store:
        event_store.close()
        logger.info("Closed event store")
