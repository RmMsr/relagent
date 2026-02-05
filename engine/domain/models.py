import uuid
from datetime import datetime, timezone
from uuid import UUID

from pydantic import BaseModel, Field


class Metadata(BaseModel):
    session_id: UUID
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class SessionInfo(BaseModel):
    session_id: UUID = Field(
        description="Unique ID referencing the session",
        default_factory=uuid.uuid4,
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    title: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatContext(BaseModel):
    messages: list[ChatMessage] = Field(default_factory=list)


class ChatRequest(BaseModel):
    session_id: UUID | None = Field(
        description="Unique ID referencing the session",
        default=None,
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    messages: list[ChatMessage] = Field(
        description="Input from the app",
        default_factory=list,
        examples=[
            [
                ChatMessage(
                    role="user", content="Hi, how long until peaceful coexistence day?"
                )
            ]
        ],
    )


class ChatResponse(BaseModel):
    session_id: UUID = Field(
        description="Unique ID referencing the session",
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    content: str
