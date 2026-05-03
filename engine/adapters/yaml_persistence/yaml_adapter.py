import os
from datetime import datetime, timezone
from pathlib import Path
import shutil
from typing import Any, Iterable, Sequence
from uuid import UUID

import portalocker
import yaml
from pydantic import BaseModel, ValidationError

from engine.domain.exceptions import (
    ChatContextNotFound,
    PersistenceError,
    SessionNotFound,
)
from engine.domain.immutability import check_final_immutability
from engine.domain.models import (
    AssistantMessage,
    ChatContext,
    ChatMessage,
    Grant,
    SessionInfo,
    SystemAction,
    UserMessage,
)
from engine.domain.ports.persistence import Persistence
from engine.log_config import get_logger

from .models import Metadata

logger = get_logger(__name__)


class YamlPersistenceAdapter(Persistence):
    def __init__(self, data_dir: os.PathLike[str]) -> None:
        self.base_dir: Path = Path(data_dir)

    def save_context(self, session_id: UUID, context: ChatContext) -> None:
        file_path = self._get_file_path(
            session_id=session_id, part_name="chat_messages"
        )
        logger.info("Saving chat messages to: %s", file_path)

        documents: list[BaseModel] = []
        metadata: Metadata | None = None
        prior_messages: list[ChatMessage] = []

        if file_path.exists():
            metadata = self._get_document_metadata(file_path)
            if metadata.session_id != session_id:
                logger.error("Found session_id mismatch in file: %s", file_path)
                raise PersistenceError("Chat context inconsistent")
            metadata.updated_at = datetime.now(tz=timezone.utc)
            try:
                prior_messages = list(self.load_context(session_id).messages)
            except ChatContextNotFound:
                prior_messages = []
        else:
            metadata = Metadata(session_id=session_id)

        check_final_immutability(prior_messages, context.messages)

        metadata.sensitivity_level = context.sensitivity_level
        documents.append(metadata)

        for msg in context.messages:
            documents.append(msg)

        self._write_documents_with_lock(file_path=file_path, documents=documents)

    def load_context(self, session_id: UUID) -> ChatContext:
        file_path = self._get_file_path(
            session_id=session_id, part_name="chat_messages"
        )

        try:
            docs = self._read_documents_from_file(file_path=file_path)
        except PersistenceError as exc:
            raise ChatContextNotFound(session_id=session_id) from exc

        if not docs:
            logger.warning("Empty YAML file: %s", file_path)
            raise ChatContextNotFound(session_id=session_id)

        # First document is metadata - validate session_id
        metadata_dict = docs[0]
        metadata: Metadata | None = None
        if metadata_dict:
            metadata = Metadata.model_validate(metadata_dict)
            if metadata.session_id != session_id:
                logger.error("Found session_id mismatch in file: %s", file_path)
                raise ChatContextNotFound(session_id=session_id)

        # Remaining documents are chat messages
        messages: list[ChatMessage] = []
        for num, doc in enumerate(docs[1:], start=1):
            # Pre-cutover records: treat as settled.
            if isinstance(doc, dict) and "final" not in doc:
                doc["final"] = True
            try:
                match doc.get("role"):
                    case "user":
                        messages.append(UserMessage.model_validate(doc))
                    case "assistant":
                        messages.append(AssistantMessage.model_validate(doc))
                    case "system":
                        messages.append(SystemAction.model_validate(doc))
                    case _:
                        logger.error(
                            "Failed to load chat message (#%d). See file: %s",
                            num,
                            file_path,
                        )
                        raise ChatContextNotFound(session_id=session_id)
            except ValidationError as exc:
                logger.error(
                    "Failed to load chat message (#%d). See file: %s", num, file_path
                )
                raise ChatContextNotFound(session_id=session_id) from exc

        sensitivity_level = metadata.sensitivity_level if metadata else None
        if sensitivity_level is not None:
            return ChatContext(messages=messages, sensitivity_level=sensitivity_level)
        return ChatContext(messages=messages)

    def save_session(self, session: SessionInfo) -> None:
        if not session.session_id:
            raise ValueError("Session ID is required for saving")

        file_path: Path = self._get_file_path(
            session_id=session.session_id, part_name="session_info"
        )
        logger.info("Saving session info to: %s", file_path)

        session.updated_at = datetime.now(tz=timezone.utc)

        self._write_model_with_lock(file_path=file_path, model=session)
        self._update_folder_timestamp(
            folder_path=self._get_session_folder(session.session_id),
            timestamp=session.updated_at,
        )

    def load_session(self, session_id: UUID) -> SessionInfo:
        file_path = self._get_file_path(session_id=session_id, part_name="session_info")

        try:
            data = self._read_data_from_file(file_path=file_path)
            session: SessionInfo = SessionInfo.model_validate(data)
        except (PersistenceError, ValidationError) as exc:
            raise SessionNotFound(session_id=session_id) from exc

        return session

    def list_recent_sessions(self, limit: int = 100) -> list[SessionInfo]:
        sessions_dir = self.base_dir / "sessions"
        if not sessions_dir.exists():
            return []

        # Collect folders with mtime (cheap filesystem metadata only)
        folders_with_time: list[tuple[Path, float]] = []
        for session_folder in sessions_dir.iterdir():
            if not session_folder.is_dir():
                continue
            try:
                UUID(session_folder.name)
            except ValueError:
                continue
            folders_with_time.append((session_folder, session_folder.stat().st_mtime))

        # Sort by mtime first, then only parse YAML for the top candidates
        folders_with_time.sort(key=lambda x: x[1], reverse=True)

        sessions: list[SessionInfo] = []
        for session_folder, _ in folders_with_time:
            if len(sessions) >= limit:
                break
            try:
                session = self.load_session(UUID(session_folder.name))
                sessions.append(session)
            except SessionNotFound:
                continue

        return sessions

    def delete_session(self, session_id: UUID) -> None:
        session_folder = self._get_session_folder(session_id)
        if session_folder.exists():
            shutil.rmtree(session_folder)
            logger.info("Deleted session folder: %s", session_folder)
        else:
            logger.warning("Session folder not found for deletion: %s", session_folder)

    def add_global_grant(self, grant: Grant) -> None:
        file_path = self.base_dir / "grants.yaml"
        file_path.parent.mkdir(parents=True, exist_ok=True)
        existing_grants = self.load_active_global_grants()
        existing_grants = [
            g for g in existing_grants if g.permission_key != grant.permission_key
        ]
        existing_grants.append(grant)
        with portalocker.Lock(file_path, mode="w", timeout=5) as f:
            yaml.safe_dump([g.model_dump(mode="json") for g in existing_grants], f)

    def add_session_grant(self, session_id: UUID, grant: Grant) -> None:
        file_path = self._get_session_folder(session_id) / "grants.yaml"
        file_path.parent.mkdir(parents=True, exist_ok=True)
        existing_grants = self.load_active_session_grants(session_id)
        existing_grants = [
            g for g in existing_grants if g.permission_key != grant.permission_key
        ]
        existing_grants.append(grant)
        with portalocker.Lock(file_path, mode="w", timeout=5) as f:
            yaml.safe_dump([g.model_dump(mode="json") for g in existing_grants], f)

    def load_active_global_grants(self) -> list[Grant]:
        file_path = self.base_dir / "grants.yaml"
        if not file_path.exists():
            return []
        with open(file_path, "r") as f:
            data = yaml.safe_load(f)

        all_grants = [Grant.model_validate(item) for item in data]
        now = datetime.now(timezone.utc)
        return [
            grant
            for grant in all_grants
            if grant.expires_at is None or grant.expires_at > now
        ]

    def load_active_session_grants(self, session_id: UUID) -> list[Grant]:
        file_path = self._get_session_folder(session_id) / "grants.yaml"
        if not file_path.exists():
            return []
        with open(file_path, "r") as f:
            data = yaml.safe_load(f)

        all_grants = [Grant.model_validate(item) for item in data]
        now = datetime.now(timezone.utc)
        return [
            grant
            for grant in all_grants
            if grant.expires_at is None or grant.expires_at > now
        ]

    def _get_session_folder(self, session_id: UUID) -> Path:
        return self.base_dir / "sessions" / str(session_id)

    def _get_file_path(self, session_id: UUID, part_name: str) -> Path:
        return self._get_session_folder(session_id) / f"{part_name}.yaml"

    def _write_model_with_lock(self, file_path: Path, model: BaseModel) -> None:
        """Write model as a YAML document into a file using voluntary file locking"""

        file_path.parent.mkdir(parents=True, exist_ok=True)
        with portalocker.Lock(filename=file_path, mode="w", timeout=5) as fh:  # type: ignore[reportUnknownMemberType]
            yaml.safe_dump(model.model_dump(mode="json"), fh)  # type: ignore[reportUnknownMemberType]
            fh.flush()
            os.fsync(fh.fileno())

    def _write_documents_with_lock(
        self, file_path: Path, documents: Iterable[BaseModel]
    ) -> None:
        """Write models as multiple YAML documents into a single file using voluntary file locking"""

        data = [doc.model_dump(mode="json") for doc in documents]

        file_path.parent.mkdir(parents=True, exist_ok=True)
        with portalocker.Lock(filename=file_path, mode="w", timeout=5) as fh:  # type: ignore[reportUnknownMemberType]
            yaml.safe_dump_all(data, fh)  # type: ignore[reportUnknownMemberType]
            fh.flush()
            os.fsync(fh.fileno())

    def _read_data_from_file(self, file_path: Path) -> Any:
        try:
            with open(file_path, "r") as fh:
                data = yaml.safe_load(stream=fh)
        except FileNotFoundError as exc:
            raise PersistenceError("File not found: %s" % file_path) from exc
        except (yaml.YAMLError, ValueError) as exc:
            raise PersistenceError(
                "Failed to parse YAML from file: %s" % file_path
            ) from exc

        return data

    def _read_documents_from_file(self, file_path: Path) -> Sequence[Any]:
        try:
            with open(file_path, "r") as fh:
                documents = list(yaml.safe_load_all(stream=fh))
        except FileNotFoundError as exc:
            raise PersistenceError("File not found: %s" % file_path) from exc
        except (yaml.YAMLError, ValueError) as exc:
            raise PersistenceError(
                "Failed to parse YAML from file: %s" % file_path
            ) from exc

        return documents

    def _get_document_metadata(self, file_path: Path) -> Metadata:
        """Read only the first YAML document (metadata) from a file"""

        with open(file_path, "r") as fh:
            for doc in yaml.safe_load_all(fh):
                if isinstance(doc, dict) and "session_id" in doc:
                    return Metadata.model_validate(doc)
        raise PersistenceError("No valid metadata found in file: %s" % file_path)

    @staticmethod
    def _update_folder_timestamp(folder_path: Path, timestamp: datetime) -> None:
        """Update the modification time of a folder to the given timestamp."""
        try:
            os.utime(folder_path, (timestamp.timestamp(), timestamp.timestamp()))
        except OSError as e:
            logger.warning(
                "Failed to update folder timestamp for %s: %s", folder_path, e
            )
