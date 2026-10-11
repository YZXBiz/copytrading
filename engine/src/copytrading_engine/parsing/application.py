"""Extraction use case, independent of model provider and message transport."""

import datetime as dt
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
from copytrading_engine.parsing.history import RecentCall
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
    """Settle an empty post before reserving a paid provider attempt."""
    text = normalize(event.text).strip()
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


async def transform(
    event: _RawMessage,
    route: Route,
    decoder: Decoder,
    model: str,
    recent: tuple[RecentCall, ...] = (),
) -> StockSignal:
    local = without_model(event, route, model)
    if local is not None:
        return local
    text = normalize(event.text).strip()
    reading = await decoder.decode(text, route, recent)
    try:
        check_reading(reading, text, route)
    except GroundingError as exc:
        raise DecodeError(
            "evidence_validation_failed", retryable=False, issues=(exc.issue,)
        ) from None
    acted, repeat = _without_repeats(reading, route, recent, event.timestamp)
    if repeat is not None:
        decision, reason, calls = (
            repeat,
            ("repeats_a_recent_call" if repeat == "ignore" else "repeats_an_earlier_call"),
            (),
        )
    else:
        decision, reason, calls = _act_on(acted)
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
        suggested=suggested(reading) if decision == "review" else (),
    )


def _without_repeats(
    reading: r.PostReading,
    route: Route,
    recent: tuple[RecentCall, ...],
    at: dt.datetime,
) -> tuple[r.PostReading, Literal["ignore", "review"] | None]:
    """A call the reader says restates one of the guru's recent calls is not a new call while
    the guru's repeat window is on (ADR-0010): within the window it is dropped, and a post that
    only restates is ignored; a restatement after the window waits for the owner, who can tell a
    reminder from a second buy. With the window off, every call is a new call."""
    window = route.repeat_window_minutes
    if window is None or not isinstance(reading, r.TradeMade | r.Instruction):
        return reading, None
    by_ref = {call.ref: call for call in recent}
    kept = []
    for call in reading.calls:
        earlier = by_ref.get(call.repeats) if call.repeats is not None else None
        if earlier is None:
            kept.append(call)
        elif (at - earlier.at).total_seconds() > window * 60:
            return reading, "review"
    if not kept:
        return reading, "ignore"
    return reading.model_copy(update={"calls": tuple(kept)}), None


class _Wait(Exception):
    """A call the engine cannot place as written; the post waits for the owner."""

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(reason)


def _act_on(
    reading: r.PostReading,
) -> tuple[Literal["trade", "ignore", "review"], str, tuple[tuple[Instruction, Evidence], ...]]:
    """Act or ask (ADR-0007): a trade made or an instruction with every call placeable trades;
    conditionals, suggestions, a range, a buy with no exact price, and a vague trim wait for the
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
                calls = tuple(_placeable(call) for call in reading.calls)
            except _Wait as wait:
                return "review", wait.reason, ()
            return "trade", reading.summary, calls


def _placeable(call: r.Call) -> tuple[Instruction, Evidence]:
    """The engine's call for a stated one, with the post's words behind each field. Raises
    _Wait when it cannot be placed without the owner."""
    instruction = _instruction(call, owner=False)
    if isinstance(call, r.Buy):
        fraction_words = call.size.words if isinstance(call.size, r.Fraction) else None
        entry_words = None
    else:
        assert not isinstance(call.share, r.NotGiven)  # _instruction waits on it
        fraction_words = call.share.words
        entry_words = (
            call.sell_from.words
            if instruction.entry_price is not None and isinstance(call.sell_from, r.Lot)
            else None
        )
    evidence = Evidence(
        **instruction.model_dump(),
        action_evidence=call.action_words,
        symbol_evidence=call.stock.words,
        # A sell at the market has no price to cite (_instruction waits on any other price).
        price_evidence=call.price.words if isinstance(call.price, r.Exact) else None,
        entry_evidence=entry_words,
        fraction_evidence=fraction_words,
    )
    return instruction, evidence


def suggested(reading: r.PostReading | None) -> tuple[Instruction, ...]:
    """What Copy places for a post that waits for the owner (ADR-0007, ADR-0010): each call the
    owner can copy as read, a range at its top and a batch at the full position, trimmed by the
    account's limits. A buy with no price, or a sell that states no share, has nothing to copy;
    the owner enters it or sells the lot from Accounts."""
    if not isinstance(reading, r.TradeMade | r.Instruction | r.Conditional | r.Suggestion):
        return ()
    calls = []
    for call in reading.calls:
        try:
            calls.append(_instruction(call, owner=True))
        except _Wait:
            continue
    return tuple(calls)


def _instruction(call: r.Call, *, owner: bool) -> Instruction:
    """One call as the engine places it (ADR-0007, ADR-0010). On its own (`owner=False`) the
    engine waits for the owner on a range and on a sell that states no share; when the owner
    copies, a range buys at its top. A sell with no price, or one at the market, sells at the
    market when placed ("sell wmt half"): the guru is getting out now, and the limit under the
    live bid bounds it. A buy needs the guru's price, which bounds what the copy pays. A buy with
    no size asks for the full position, and one whose size is a batch the playbook gives no share
    waits; a sell that names a buy price sells from the buys at that price, and one that names
    none from every buy; a share counts from what is left unless the post says the original
    buy."""
    price: Decimal | None
    match call.price:
        case r.Exact(value=price):
            pass
        case r.Range(high=high) if owner:
            price = high
        case r.Range():
            raise _Wait("price_range")
        case r.AtMarket() | r.NotGiven() if isinstance(call, r.Sell):
            price = None
        case r.AtMarket():
            raise _Wait("price_at_market")
        case _:
            raise _Wait("price_not_given")
    if isinstance(call, r.Buy):
        # A batch the playbook gives no size waits like a vague trim: "the second batch" is a
        # share of a position, not the whole of one. The owner copying it chooses the size.
        if isinstance(call.size, r.Batch) and not owner:
            raise _Wait("batch_size_not_given")
        fraction = call.size.value if isinstance(call.size, r.Fraction) else None
        return Instruction(action="buy", symbol=call.stock.ticker, price=price, fraction=fraction)
    if isinstance(call.share, r.NotGiven):
        raise _Wait("sell_share_not_given")
    share = Decimal(1) if isinstance(call.share, r.All) else call.share.value
    return Instruction(
        action="close" if share == 1 else "reduce",
        symbol=call.stock.ticker,
        price=price,
        entry_price=call.sell_from.buy_price if isinstance(call.sell_from, r.Lot) else None,
        fraction=share,
        exit_basis="original_position" if call.counts_from == "original" else "remaining_position",
    )
