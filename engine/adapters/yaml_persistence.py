import logging
import os
from datetime import datetime, timezone
from pathlib import Path
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
from engine.domain.models import (
    AssistantMessage,
    ChatContext,
    ChatMessage,
    Metadata,
    SessionInfo,
    UserMessage,
)
from engine.domain.ports import Persistence

logger = logging.getLogger(__name__)


class YamlPersistenceAdapter(Persistence):
    def __init__(self, data_dir: os.PathLike[str]) -> None:
        self.base_dir: Path = Path(data_dir)

    def save_context(self, session: SessionInfo, context: ChatContext) -> None:
        file_path = self._get_file_path(
            session_id=session.session_id, part_name="chat_messages"
        )
        logger.info("Saving chat messages to: %s", file_path)

        documents: list[BaseModel] = []

        # Create or update metadata

        metadata: Metadata | None = None

        if file_path.exists():
            metadata = self._get_document_metadata(file_path)
            if metadata.session_id != session.session_id:
                logger.error("Found session_id mismatch in file: %s", file_path)
                raise PersistenceError("Chat context inconsistent")
            metadata.updated_at = datetime.now(tz=timezone.utc)
        else:
            metadata = Metadata(session_id=session.session_id)

        documents.append(metadata)

        # Add all messages as separate documents

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
            try:
                match doc.get("role"):
                    case "user":
                        messages.append(UserMessage.model_validate(doc))
                    case "assistant":
                        messages.append(AssistantMessage.model_validate(doc))
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

    def load_session(self, session_id: UUID) -> SessionInfo:
        file_path = self._get_file_path(session_id=session_id, part_name="session_info")

        try:
            data = self._read_data_from_file(file_path=file_path)
            session: SessionInfo = SessionInfo.model_validate(data)
            logger.info("Loaded session (%s) from: %s", session.session_id, file_path)
        except (PersistenceError, ValidationError) as exc:
            raise SessionNotFound(session_id=session_id) from exc

        return session

    def _get_file_path(self, session_id: UUID, part_name: str) -> Path:
        return self.base_dir / "sessions" / str(session_id) / f"{part_name}.yaml"

    def _write_model_with_lock(self, file_path: Path, model: BaseModel) -> None:
        """
        Write model as a YAML document into a file using voluntary file locking
        """

        file_path.parent.mkdir(parents=True, exist_ok=True)
        with portalocker.Lock(filename=file_path, mode="w") as fh:  # type: ignore[reportUnknownMemberType]
            yaml.safe_dump(model.model_dump(mode="json"), fh)  # type: ignore[reportUnknownMemberType]
            fh.flush()
            os.fsync(fh.fileno())

    def _write_documents_with_lock(
        self, file_path: Path, documents: Iterable[BaseModel]
    ) -> None:
        """
        Write models as multiple YAML documents into a single file using voluntary file locking
        """

        data = [doc.model_dump(mode="json") for doc in documents]

        file_path.parent.mkdir(parents=True, exist_ok=True)
        with portalocker.Lock(filename=file_path, mode="w") as fh:  # type: ignore[reportUnknownMemberType]
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
        """
        Read only the first YAML document (metadata) from a file
        """

        with open(file_path, "r") as fh:
            for doc in yaml.safe_load_all(fh):
                if isinstance(doc, dict) and "session_id" in doc:
                    return Metadata.model_validate(doc)
        raise PersistenceError("No valid metadata found in file: %s" % file_path)
