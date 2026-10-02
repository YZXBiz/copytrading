"""Safe validation metadata: retain rules and schema paths, never provider payloads."""

from pydantic import BaseModel, ConfigDict, ValidationError

FIELDS = frozenset(
    {
        "decision",
        "reason",
        "instructions",
        "action",
        "symbol",
        "price",
        "entry_price",
        "fraction",
        "action_evidence",
        "symbol_evidence",
        "price_evidence",
        "entry_evidence",
        "fraction_evidence",
    }
)


class ValidationIssue(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")
    path: str
    code: str


def validation_issues(error: Exception) -> tuple[ValidationIssue, ...]:
    """PydanticAI wraps validation failures; inspect causes without serializing exceptions."""
    seen: set[int] = set()
    current: BaseException | None = error
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        if isinstance(current, ValidationError):
            return tuple(
                ValidationIssue(
                    path=".".join(
                        str(part) if isinstance(part, int) or part in FIELDS else "<extra>"
                        for part in item["loc"]
                    )
                    or "<root>",
                    code=item["type"],
                )
                for item in current.errors(
                    include_input=False, include_context=False, include_url=False
                )[:10]
            )
        current = current.__cause__ or current.__context__
    return ()
