"""Extraction use case, independent of model provider and message transport."""

from collections.abc import Sequence
from decimal import Decimal
from typing import Literal

from copytrading_engine.parsing.contracts import RawMessage as _RawMessage
from copytrading_engine.parsing.extraction import (
    PROMPT_VERSION,
    DecodeError,
    Decoder,
    GroundingError,
    check_reading,
    normalize,
)
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared import reading as r
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
    reading: r.PostReading | None = None,
    suggested: Sequence[Instruction] = (),
) -> StockSignal:
    return StockSignal(
        reading=reading,
        suggested=tuple(suggested),
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
    reading = await decoder.decode(text, route)
    try:
        check_reading(reading, text, route)
    except GroundingError as exc:
        raise DecodeError(
            "evidence_validation_failed", retryable=False, issues=(exc.issue,)
        ) from None
    decision, reason, calls = _act_on(reading, route)
    return outcome(
        event,
        decision,
        reason,
        model=model,
        instructions=tuple(call for call, _ in calls),
        evidence=tuple(evidence for _, evidence in calls),
        guru_id=route.guru_id,
        profile_revision=route.profile_revision,
        reading=reading,
        suggested=suggested(reading, route) if decision == "review" else (),
    )


class _Wait(Exception):
    """A call the engine cannot place as written; the post waits for the owner."""

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(reason)


def _act_on(
    reading: r.PostReading, route: Route
) -> tuple[Literal["trade", "ignore", "review"], str, tuple[tuple[Instruction, Evidence], ...]]:
    """Act or ask (ADR-0007): a trade made or an instruction with every call placeable trades;
    conditionals, suggestions, and calls with no exact price or no named buy wait for the
    owner; commentary is ignored."""
    match reading:
        case r.Commentary():
            return "ignore", reading.summary, ()
        case r.Unclear():
            return "review", "unclear", ()
        case r.Conditional() | r.Suggestion():
            return "review", reading.kind, ()
        case r.TradeMade() | r.Instruction():
            try:
                calls = tuple(_placeable(call, route) for call in reading.calls)
            except _Wait as wait:
                return "review", wait.reason, ()
            return "trade", reading.summary, calls


def _placeable(call: r.Call, route: Route) -> tuple[Instruction, Evidence]:
    """The engine's call for a stated one, under the guru's rules, with the post's words behind
    each field. Raises _Wait when it cannot be placed without the owner."""
    instruction = _instruction(call, route, owner=False)
    if isinstance(call, r.Buy):
        fraction_words = call.size.words if isinstance(call.size, r.Fraction | r.Batch) else None
        entry_words = None
    else:
        fraction_words = call.share.words
        entry_words = (
            call.sell_from.words
            if instruction.entry_price is not None and isinstance(call.sell_from, r.Lot)
            else None
        )
    assert isinstance(call.price, r.Exact)  # _instruction waits on any other price
    evidence = Evidence(
        **instruction.model_dump(),
        action_evidence=call.action_words,
        symbol_evidence=call.stock.words,
        price_evidence=call.price.words,
        entry_evidence=entry_words,
        fraction_evidence=fraction_words,
    )
    return instruction, evidence


def suggested(reading: r.PostReading | None, route: Route) -> tuple[Instruction, ...]:
    """What Copy places for a post that waits for the owner (ADR-0007): each call the owner can
    copy as read, a range at its top and a batch the guru has no N for at the default share. A
    call with no price, or a sell that names no buy for a guru who names them, has nothing to
    copy; the owner enters it or sells the lot from Accounts."""
    if not isinstance(reading, r.TradeMade | r.Instruction | r.Conditional | r.Suggestion):
        return ()
    calls = []
    for call in reading.calls:
        try:
            calls.append(_instruction(call, route, owner=True))
        except _Wait:
            continue
    return tuple(calls)


def _instruction(call: r.Call, route: Route, *, owner: bool) -> Instruction:
    """One call as the engine places it. On its own (`owner=False`) the engine waits for the
    owner on a range or a batch the guru has no N for; when the owner copies, a range buys at its
    top and such a batch at the default share."""
    match call.price:
        case r.Exact(value=price):
            pass
        case r.Range(high=high) if owner:
            price = high
        case r.Range():
            raise _Wait("price_range")
        case r.AtMarket():
            raise _Wait("price_at_market")
        case _:
            raise _Wait("price_not_given")
    whole_position = route.sells_refer_to == "whole_position"
    if isinstance(call, r.Buy):
        match call.size:
            case r.Fraction(value=fraction):
                pass
            case r.Batch() if route.batches is not None:
                # Each batch is an equal share of the full position.
                fraction = Decimal(1) / route.batches
            case r.Batch() if not owner:
                raise _Wait("batch_size_unknown")
            case _:
                fraction = None
        return Instruction(
            action="buy",
            symbol=call.stock.ticker,
            price=price,
            fraction=fraction,
            whole_position=whole_position,
        )
    # A guru whose sells refer to the whole position holds one lot per stock, so a named buy
    # price only describes it.
    if not whole_position and not isinstance(call.sell_from, r.Lot):
        raise _Wait("sell_names_no_buy")
    share = Decimal(1) if isinstance(call.share, r.All) else call.share.value
    entry_price = None
    if not whole_position and isinstance(call.sell_from, r.Lot):
        entry_price = call.sell_from.buy_price
    return Instruction(
        action="close" if share == 1 else "reduce",
        symbol=call.stock.ticker,
        price=price,
        entry_price=entry_price,
        fraction=share,
        exit_basis=(
            ("original_position" if call.counts_from == "original" else "remaining_position")
            if call.counts_from
            else route.exit_basis
        ),
        whole_position=whole_position,
    )
