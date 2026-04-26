from datetime import datetime, timezone
from uuid import UUID

from pydantic import BaseModel, Field

from engine.domain.types import SensitivityLevel


class Metadata(BaseModel):
    session_id: UUID
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    sensitivity_level: SensitivityLevel | None = None
