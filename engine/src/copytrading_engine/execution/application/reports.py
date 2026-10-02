"""Canonical typed execution reports built from durable journal records."""

from typing import Literal, Self

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, StrictInt, model_validator

from copytrading_engine.execution.domain.events import JournalEvent


class StoredReport(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", hide_input_in_errors=True)

    id: StrictInt = Field(gt=0)
    event: JournalEvent


class ExecutionReport(BaseModel):
    model_config = ConfigDict(
        frozen=True,
        extra="forbid",
        hide_input_in_errors=True,
        json_schema_serialization_defaults_required=True,
    )

    schema_version: Literal[2] = 2
    event_type: Literal["execution_report"] = "execution_report"
    id: StrictInt = Field(gt=0)
    timestamp: AwareDatetime
    event: JournalEvent

    @model_validator(mode="after")
    def timestamp_matches_event(self) -> Self:
        if self.timestamp != self.event.at:
            raise ValueError("Execution report timestamp must match the journal event time")
        return self
