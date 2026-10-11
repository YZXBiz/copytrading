"""The guru's recent calls, as the reader sees them beside a new post (ADR-0010).

A guru's book is replayed from the calls the engine copied, each owner correction in place of
the reading it corrects: every buy stays open until a sell closes it (by its price, or every buy
of the stock when the sell names none). The reader is shown every open buy, however old, and the
last few closed calls, by reference (c1, c2, …), stock, price, and size only: never the posts'
text, which is the guru's and untrusted.
"""

import datetime as dt
from collections.abc import Iterable
from dataclasses import dataclass
from decimal import Decimal
from typing import Literal

from copytrading_engine.shared.signals import Instruction

CLOSED_SHOWN = 10


@dataclass(frozen=True, slots=True)
class PastCall:
    """One call the engine copied, or the owner corrected, for this guru."""

    source_key: str
    index: int
    at: dt.datetime
    instruction: Instruction


@dataclass(frozen=True, slots=True)
class RecentCall:
    """A call as the reader is shown it, by a reference it can name in `repeats`."""

    ref: str
    source_key: str
    index: int
    at: dt.datetime
    action: Literal["buy", "reduce", "close"]
    symbol: str
    # None for a sell at the market (ADR-0007).
    price: Decimal | None
    fraction: Decimal | None
    entry_price: Decimal | None
    open: bool


def recent_calls(past: Iterable[PastCall]) -> tuple[RecentCall, ...]:
    """Every open buy and the last few closed calls, oldest first, numbered c1, c2, …"""
    ordered = sorted(past, key=lambda call: (call.at, call.source_key, call.index))
    open_buys: dict[tuple[str, int], PastCall] = {}
    closed: list[PastCall] = []
    for call in ordered:
        instruction = call.instruction
        if instruction.action == "buy":
            open_buys[(call.source_key, call.index)] = call
            continue
        closed.append(call)
        if instruction.action != "close":
            continue
        for key, buy in list(open_buys.items()):
            same_stock = buy.instruction.symbol == instruction.symbol
            named = (
                instruction.entry_price is None or buy.instruction.price == instruction.entry_price
            )
            if same_stock and named:
                closed.append(open_buys.pop(key))
    shown = sorted(
        [*open_buys.values(), *sorted(closed, key=lambda c: c.at)[-CLOSED_SHOWN:]],
        key=lambda call: (call.at, call.source_key, call.index),
    )
    still_open = set(open_buys)
    return tuple(
        RecentCall(
            ref=f"c{number}",
            source_key=call.source_key,
            index=call.index,
            at=call.at,
            action=call.instruction.action,
            symbol=call.instruction.symbol,
            price=call.instruction.price,
            fraction=call.instruction.fraction,
            entry_price=call.instruction.entry_price,
            open=(call.source_key, call.index) in still_open,
        )
        for number, call in enumerate(shown, start=1)
    )


def describe(calls: tuple[RecentCall, ...], now: dt.datetime) -> str:
    """The calls as the reader's instructions list them: fields only, one per line."""
    lines = []
    for call in calls:
        minutes = max(0, int((now - call.at).total_seconds() // 60))
        parts = [
            call.ref,
            call.action,
            call.symbol,
            f"at {call.price}" if call.price is not None else "at market",
        ]
        if call.fraction is not None:
            parts.append(f"share {call.fraction.normalize()}")
        if call.entry_price is not None:
            parts.append(f"from the buy at {call.entry_price}")
        parts.append("open" if call.open else "closed")
        parts.append(f"{minutes} min ago")
        lines.append(" · ".join(parts))
    return "\n".join(lines)
