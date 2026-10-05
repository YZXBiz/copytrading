"""Explicit progress states for each validated signal instruction."""

from typing import Annotated, Literal

from pydantic import Field

from copytrading_engine.execution.domain.values import Identifier, Quantity, Value


class Exposure(Value):
    """A named comparison of current, proposed, and permitted exposure."""

    scope: Literal["symbol", "total"]
    current: Quantity
    proposed: Quantity
    limit: Quantity


class Pending(Value):
    kind: Literal["pending"] = "pending"


class OrderLinked(Value):
    kind: Literal["order_linked"] = "order_linked"
    client_id: Identifier


class Skipped(Value):
    kind: Literal["skipped"] = "skipped"
    reason: Annotated[str, Field(min_length=1)]
    # The limit a skipped buy would have passed, with its numbers, so Activity can say which.
    exposure: tuple[Exposure, ...] = ()


InstructionProgress = Annotated[
    Pending | OrderLinked | Skipped,
    Field(discriminator="kind"),
]
