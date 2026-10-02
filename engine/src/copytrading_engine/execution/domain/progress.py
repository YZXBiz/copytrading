"""Explicit progress states for each validated signal instruction."""

from typing import Annotated, Literal

from pydantic import Field

from copytrading_engine.execution.domain.values import Identifier, Value


class Pending(Value):
    kind: Literal["pending"] = "pending"


class OrderLinked(Value):
    kind: Literal["order_linked"] = "order_linked"
    client_id: Identifier


class Skipped(Value):
    kind: Literal["skipped"] = "skipped"
    reason: Annotated[str, Field(min_length=1)]


InstructionProgress = Annotated[
    Pending | OrderLinked | Skipped,
    Field(discriminator="kind"),
]
