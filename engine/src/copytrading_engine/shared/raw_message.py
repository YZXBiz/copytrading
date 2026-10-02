"""Validated values shared by capture and persistence, independent of Discord and SQL."""

from typing import Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, StrictInt


class RawMessage(BaseModel):
    """Producer validation for the published raw-message v1 contract."""

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)
    schema_version: StrictInt = Field(ge=1, le=1)
    event_type: Literal["raw_message"]
    source: str = Field(pattern=r"^[a-z][a-z0-9_-]*$")
    channel_id: str = Field(pattern=r"^[a-zA-Z0-9_-]+$")
    author_id: str | None = Field(default=None, pattern=r"^[0-9]{1,32}$")
    id: str = Field(pattern=r"^[a-zA-Z0-9_-]+$")
    timestamp: AwareDatetime
    text: str = Field(max_length=10_000)
    image_count: StrictInt = Field(default=0, ge=0)

    @property
    def identity(self) -> str:
        return f"{self.source}:{self.channel_id}:{self.id}"
