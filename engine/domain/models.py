from datetime import datetime, timezone
from typing import Literal, NamedTuple, Sequence
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field, model_validator

from engine.domain.types import ApprovalType, SensitivityLevel


class SessionInfo(BaseModel):
    """Metadata of a scoped conversation"""

    session_id: UUID = Field(
        description="Unique ID referencing the session",
        default_factory=uuid4,
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    title: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class AgentStats(BaseModel):
    """Statistics about an agent's actions"""

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


class PermissionKey(NamedTuple):
    """Identifier for matching Approvals and Grant objects"""

    approval_type: ApprovalType
    component: str | None
    allowed_parameters: tuple[tuple[str, str | int | bool], ...]
    wildcard_parameter: str | None
    sensitivity: SensitivityLevel


class Approval(BaseModel):
    """Describes the required permissions for a specific action"""

    id: UUID = Field(description="Unique ID for the approval", default_factory=uuid4)
    type: ApprovalType = Field(description="Type of approval required")
    component: str | None = Field(
        description="Component that requires the approval. Like the tools internal name",
        default=None,
        examples=["web_search"],
    )
    purpose: str = Field(
        description="Explanation of why this approval is needed",
        examples=["Searching the web for recent updates"],
    )
    allowed_parameters: dict[str, str | int | bool] = Field(
        default={},
        description="If supplied the grant is limited to these parameters",
        examples=[{"provider": "sample_provider"}],
    )
    internal_parameters: dict[str, str | int | bool] = Field(
        default={},
        description="Transparent parameters for implementation layer only",
        examples=[{"tool_call_id": "call_123"}],
    )
    sensitivity: SensitivityLevel = Field(
        description="The highest level of sensitivity needed",
        default=SensitivityLevel.OpenInformation,
    )
    granted: bool | None = Field(
        description="Contains the result of a processed approval", default=None
    )
    expires_at: datetime | None = Field(
        description="Optional time limit for the approval", default=None
    )

    @property
    def permission_key(self) -> PermissionKey:
        return PermissionKey(
            approval_type=self.type,
            component=self.component,
            allowed_parameters=tuple(sorted(self.allowed_parameters.items())),
            wildcard_parameter=None,
            sensitivity=self.sensitivity,
        )


class Grant(BaseModel, frozen=True):
    """Allows execution of the specified action"""

    approval_type: ApprovalType = Field(
        description="For which approvals this grant applies"
    )
    component: str | None = Field(
        description="Component that requires the approval. Like the tools internal name",
        default=None,
        examples=["web_search"],
    )
    allowed_parameters: dict[str, str | int | bool] = Field(
        default={},
        description="If supplied the grant is limited to these parameters",
        examples=[{"provider": "sample_provider"}],
    )
    wildcard_parameter: str | None = Field(
        default=None,
        description="""
            Allows the named allowed_parameter key to have any value.
            If a key is named here it must not be included in allowed_parameters
            """,
        examples=["query", "document_location"],
    )
    max_sensitivity: SensitivityLevel = Field(
        description="The grant can not be used above this sensitivity level",
        default=SensitivityLevel.OpenInformation,
    )
    expires_at: datetime | None = Field(
        description="Optional time limit for the grant", default=None
    )

    @model_validator(mode="after")
    def wildcard_not_in_allowed_parameters(self) -> "Grant":
        if (
            self.wildcard_parameter is not None
            and self.wildcard_parameter in self.allowed_parameters
        ):
            raise ValueError(
                f"wildcard_parameter '{self.wildcard_parameter}' must not also appear in allowed_parameters"
            )
        return self

    @property
    def permission_key(self) -> PermissionKey:
        return PermissionKey(
            approval_type=self.approval_type,
            component=self.component,
            allowed_parameters=tuple(sorted(self.allowed_parameters.items())),
            wildcard_parameter=self.wildcard_parameter,
            sensitivity=self.max_sensitivity,
        )


class UserMessage(BaseModel):
    """An element of the history containing a message from the User"""

    model_config = ConfigDict(use_enum_values=True)

    message_id: UUID = Field(default_factory=uuid4, description="Unique message identity")
    role: Literal["user"] = "user"
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    content: str
    final: bool = Field(
        default=False,
        description="True once the cycle this message opened has settled",
    )


class AssistantMessage(BaseModel):
    """An element of the history containing a message from the Agent"""

    model_config = ConfigDict(use_enum_values=True)

    message_id: UUID = Field(default_factory=uuid4, description="Unique message identity")
    role: Literal["assistant"] = "assistant"
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    content: str
    stats: AgentStats | None = None
    final: bool = Field(
        default=True,
        description="Always True for AssistantMessage; the field exists for uniform handling.",
    )


class SystemAction(BaseModel):
    """An element of the history where the system adds a change

    Example cases:
    - Requesting approval
    - Notifying the user
    """

    model_config = ConfigDict(use_enum_values=True)

    message_id: UUID = Field(default_factory=uuid4, description="Unique message identity")
    role: Literal["system"] = "system"
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    approvals: list[Approval] = Field(
        description="Missing approvals that block further execution",
        default_factory=list,
    )
    notification: str | None = Field(
        description="Informative message to the user from the system", default=None
    )
    stats: AgentStats | None = None
    final: bool = Field(
        default=False,
        description="True once the surrounding cycle has settled",
    )


ChatMessage = UserMessage | AssistantMessage | SystemAction


class ChatContext(BaseModel):
    """The state of an conversation"""

    messages: Sequence[ChatMessage] = Field(default_factory=list)
    sensitivity_level: SensitivityLevel = Field(
        default=SensitivityLevel.Personal,
        description="The highest sensitivity present in this context",
    )

    def all_messages(self) -> list[UserMessage | AssistantMessage]:
        return [
            msg
            for msg in self.messages
            if isinstance(msg, (UserMessage, AssistantMessage))
        ]


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
            [UserMessage(content="Hi, how long until peaceful coexistence day?")]
        ],
    )


class ChatResponse(BaseModel):
    session_id: UUID = Field(
        description="Unique ID referencing the session",
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    message: AssistantMessage | SystemAction
    sensitivity_level: SensitivityLevel = Field(
        description="The sensitivity level of the context after this exchange",
    )


class MessagesResponse(BaseModel):
    session_id: UUID = Field(
        description="Unique ID referencing the session",
        examples=["151a0cfb-74bb-4978-8881-3d15e4017a5e"],
    )
    messages: Sequence[ChatMessage] = Field(
        description="All messages in the session",
        default_factory=list,
    )
