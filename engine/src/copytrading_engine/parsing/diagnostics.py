"""Safe validation metadata: retain rules and schema paths, never provider payloads."""

from pydantic import BaseModel, ConfigDict, TypeAdapter, ValidationError

from copytrading_engine.shared.reading import PostReading


def _contract_names(schema: object) -> set[str]:
    """Every field name and tag in the reading contract: schema words, never post text."""
    names: set[str] = set()
    if isinstance(schema, dict):
        names.update(schema.get("properties", {}))
        names.update(schema.get("discriminator", {}).get("mapping", {}))
        if isinstance(schema.get("const"), str):
            names.add(schema["const"])
        for value in schema.values():
            names |= _contract_names(value)
    elif isinstance(schema, list):
        for value in schema:
            names |= _contract_names(value)
    return names


FIELDS = frozenset({"reading"} | _contract_names(TypeAdapter(PostReading).json_schema()))


class ValidationIssue(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")
    path: str
    code: str


def _from_reading(loc: tuple[int | str, ...]) -> tuple[int | str, ...]:
    """A path from the reading on: the reader's answer wraps it in its output's own envelope
    (the chat-or-reading choice, ADR-0012), which says nothing about what was wrong."""
    return loc[loc.index("reading") :] if "reading" in loc else loc


def validation_issues(error: Exception) -> tuple[ValidationIssue, ...]:
    """PydanticAI wraps validation failures; inspect causes without serializing exceptions. A
    reading check's failure (a GroundingError) carries its rule and path, so a post the reader
    could not read twice says which check it failed."""
    seen: set[int] = set()
    current: BaseException | None = error
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        issue = getattr(current, "issue", None)
        if isinstance(issue, ValidationIssue):
            return (issue,)
        if isinstance(current, ValidationError):
            return tuple(
                ValidationIssue(
                    path=".".join(
                        str(part) if isinstance(part, int) or part in FIELDS else "<extra>"
                        for part in _from_reading(item["loc"])
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
