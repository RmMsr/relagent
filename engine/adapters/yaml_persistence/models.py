from datetime import datetime, timezone
from uuid import UUID

from pydantic import BaseModel, Field


class Metadata(BaseModel):
    session_id: UUID
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
