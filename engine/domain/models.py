import uuid
from datetime import datetime, timezone
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, PrivateAttr


class SessionInfo(BaseModel):
    session_id: UUID = Field(
        description="Unique ID referencing the session",
        default_factory=uuid.uuid4,
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    title: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class AgentStats(BaseModel):
    agent_name: str | None = Field(default=None, description="Internal agent name")
    answering_model_name: str | None = Field(
        default=None, description="Name of the initial model answering the request"
    )
    duration_seconds: float | None = Field(
        default=None, description="Total duration the agent spent"
    )
    input_tokens: int | None = Field(
        default=None, description="Input tokens for this request"
    )
    output_tokens: int | None = Field(
        default=None, description="Output tokens for this request"
    )
    requests_count: int | None = Field(
        default=None, description="Number of requests to a model"
    )
    tool_calls_count: int | None = Field(
        default=None, description="Number of tool calls made"
    )


class UserMessage(BaseModel):
    sequence_id: int | None = Field(
        default=None, description="Message ID within session"
    )
    role: Literal["user"] = "user"
    content: str
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class AssistantMessage(BaseModel):
    sequence_id: int | None = Field(
        default=None, description="Message ID within session"
    )
    role: Literal["assistant"] = "assistant"
    content: str
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    stats: AgentStats | None = None


ChatMessage = UserMessage | AssistantMessage


class ChatContext(BaseModel):
    messages: list[ChatMessage] = Field(default_factory=list)
    _next_sequence_id: int = PrivateAttr(default=0)


class ChatRequest(BaseModel):
    session_id: UUID | None = Field(
        description="Unique ID referencing the session",
        default=None,
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    messages: list[UserMessage] = Field(
        description="Input from the app",
        default_factory=list,
        examples=[
            [
                UserMessage(
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
    message: AssistantMessage


class MessagesResponse(BaseModel):
    session_id: UUID = Field(
        description="Unique ID referencing the session",
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    messages: list[ChatMessage] = Field(
        description="All messages in the session",
        default_factory=list,
    )
