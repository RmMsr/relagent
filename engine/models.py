import datetime
import logging
import os
import uuid
from uuid import UUID

import portalocker
from pydantic import BaseModel, Field, ValidationError
from pydantic_yaml import (
    parse_yaml_raw_as,
    to_yaml_str,  # type: ignore[reportUnknownVariableType]
)

from engine.constants import DATA_DIR
from engine.exceptions import SessionCorrupted, SessionNotFound

logger = logging.getLogger(__name__)


class SessionInfo(BaseModel):
    session_id: UUID = Field(
        description="Unique ID referencing the session",
        default_factory=uuid.uuid4,
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    title: str | None
    created_at: datetime.datetime = Field(default_factory=datetime.datetime.now)

    def save_as_yaml(self) -> None:
        """Save session info to YAML file."""
        if not self.session_id:
            raise ValueError("Session ID is required for saving")

        file_path = os.path.join(
            DATA_DIR, "sessions", str(self.session_id), "session_info.yaml"
        )
        logger.info("Saving session info to: %s", file_path)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with portalocker.open_atomic(filename=file_path, binary=False) as f:
            f.write(to_yaml_str(model=self))  # type: ignore[reportUnknownVariableType]
            f.flush()
            os.fsync(f.fileno())

    @classmethod
    def load_from_yaml(cls, session_id: UUID) -> "SessionInfo":
        file_path = os.path.join(
            DATA_DIR, "sessions", str(session_id), "session_info.yaml"
        )
        try:
            with open(file_path, mode="r") as f:
                return parse_yaml_raw_as(cls, f.read())
        except FileNotFoundError as exp:
            logger.error("Session not found: %s", exp)
            raise SessionNotFound(session_id=session_id) from exp
        except ValidationError as exp:
            logger.error("Session not valid: %s", exp)
            raise SessionCorrupted(session_id=session_id) from exp


class ChatRequest(BaseModel):
    session_id: UUID | None = Field(
        description="Unique ID referencing the session",
        default=None,
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    content: str = Field(
        description="Input from the app",
        examples=["Hi, how long until peaceful coexistence day?"],
    )


class ChatResponse(BaseModel):
    session_id: UUID = Field(
        description="Unique ID referencing the session",
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    content: str
