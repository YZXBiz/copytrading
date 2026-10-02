"""Extraction use case, independent of model provider and message transport."""

from collections.abc import Sequence
from typing import Literal

from copytrading_engine.parsing.contracts import RawMessage as _RawMessage
from copytrading_engine.parsing.extraction import (
    PROMPT_VERSION,
    DecodeError,
    Decoder,
    GroundingError,
    normalize,
    validate_grounding,
)
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.signals import Evidence, Instruction, StockSignal


def outcome(
    event: _RawMessage,
    decision: Literal["trade", "ignore", "review"],
    reason: str,
    *,
    model: str,
    instructions: Sequence[Instruction] = (),
    evidence: Sequence[Evidence] = (),
    guru_id: str | None = None,
    profile_revision: str | None = None,
) -> StockSignal:
    return StockSignal(
        source=event.source,
        channel_id=event.channel_id,
        author_id=event.author_id,
        id=event.id,
        timestamp=event.timestamp,
        text=event.text,
        parser_profile=PROMPT_VERSION,
        model=model,
        guru_id=guru_id,
        profile_revision=profile_revision,
        decision=decision,
        reason=reason,
        instructions=tuple(instructions),
        evidence=tuple(evidence),
    )


def without_model(event: _RawMessage, route: Route, model: str) -> StockSignal | None:
    """Resolve source filtering before reserving a paid provider attempt."""
    text = normalize(event.text)
    prefix = normalize(route.prefix)
    if not text.startswith(prefix):
        return outcome(
            event,
            "ignore",
            "source_prefix_mismatch",
            model=model,
            guru_id=route.guru_id,
            profile_revision=route.profile_revision,
        )
    text = text[len(prefix) :].strip()
    if not text:
        return outcome(
            event,
            "review",
            "no_text_to_decode",
            model=model,
            guru_id=route.guru_id,
            profile_revision=route.profile_revision,
        )
    return None


async def transform(event: _RawMessage, route: Route, decoder: Decoder, model: str) -> StockSignal:
    local = without_model(event, route, model)
    if local is not None:
        return local
    text = normalize(event.text)[len(normalize(route.prefix)) :].strip()
    result = await decoder.decode(text, route)
    try:
        validate_grounding(result, text, route)
    except GroundingError as exc:
        raise DecodeError(
            "evidence_validation_failed", retryable=False, issues=(exc.issue,)
        ) from None
    instructions = tuple(
        Instruction(
            action=item.action,
            symbol=item.symbol,
            price=item.price,
            entry_price=item.entry_price,
            fraction=item.fraction,
            exit_basis=(
                route.exit_basis
                if item.action != "buy" and item.exit_basis is None
                else item.exit_basis
            ),
        )
        for item in result.instructions
    )
    evidence = tuple(
        Evidence(
            **{
                **{key: getattr(instruction, key) for key in Instruction.model_fields},
                **{
                    key: getattr(item, key)
                    for key in Evidence.model_fields
                    if key not in Instruction.model_fields
                },
            }
        )
        for instruction, item in zip(instructions, result.instructions, strict=True)
    )
    return outcome(
        event,
        result.decision,
        result.reason,
        model=model,
        instructions=instructions,
        evidence=evidence,
        guru_id=route.guru_id,
        profile_revision=route.profile_revision,
    )
