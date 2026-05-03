from typing import Literal
from pydantic import BaseModel, Field

from engine.domain.models import Grant
from engine.domain.types import SensitivityLevel


class StatusResponse(BaseModel):
    service_name: str = Field(description="Service name", examples=["relagent-engine"])
    version: str = Field(description="Service version", examples=["0.0.1"])
    status: Literal["ok"]


class SetSensitivityRequest(BaseModel):
    sensitivity_level: SensitivityLevel


class GrantApprovalRequest(BaseModel):
    """Per-approval grant: optionally registers a session-scoped Grant for
    matching future approvals, then marks this approval granted=True."""

    grant: Grant | None = Field(
        default=None,
        description=(
            "If provided, registers as a session grant so future approvals "
            "matching the same permission key are auto-satisfied."
        ),
    )
