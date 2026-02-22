from typing import Literal
from pydantic import BaseModel, Field


class StatusResponse(BaseModel):
    service_name: str = Field(description="Service name", examples=["relagent-engine"])
    version: str = Field(description="Service version", examples=["0.0.1"])
    status: Literal["ok"]
