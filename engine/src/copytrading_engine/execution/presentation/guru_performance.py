"""What one guru's copied calls made in one account, read from the ledger and its journal.

A closed trade is one filled sell order (the owner's own sale of a copied lot included). The
ledger keeps only what each lot holds now, not how each sell was split across its buys, so the
journal's fills are replayed through `OwnedLot.reduced`, the same call the ledger made, to learn
which buys each sell took from. A lot is trusted only when the replay ends exactly where the
ledger's lot is; otherwise its sells are counted as unmatched, never guessed.
"""

import datetime as dt
from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal

from pydantic import AwareDatetime

from copytrading_engine.execution.domain.events import (
    JournalEvent,
    LateOrderIncidentOpened,
    LateOrderIncidentReopened,
    ManualSaleRecorded,
    OrderUpdate,
)
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.orders import OwnedLot
from copytrading_engine.execution.domain.sessions import trade_date
from copytrading_engine.execution.domain.values import Money, Value
from copytrading_engine.execution.presentation.operator_views import excerpt

CENT = Decimal("0.01")
ZERO = Decimal(0)

# The journal events that carry an order's cumulative fill, which is what the ledger applied.
FILL_KINDS = ("order_update", "late_order_incident_opened", "late_order_incident_reopened")
REPLAY_KINDS = (*FILL_KINDS, "manual_sale_recorded")


class ClosedTrade(Value):
    """One sale of copied shares, with the guru's post that bought them."""

    symbol: str
    profit_usd: Money
    closed_on: dt.date
    source_id: str | None
    excerpt: str | None
    posted_at: AwareDatetime | None


class PerformancePoint(Value):
    day: dt.date
    cumulative_usd: Money


class GuruPerformance(Value):
    guru_id: str
    account_id: str
    realized_usd: Money
    #: The open copied lots against the broker's price now; None when any of them has no price.
    unrealized_usd: Money | None
    closed_trades: int
    winning_trades: int
    #: Sales whose lots the replay could not tell apart; they are in no figure here.
    unmatched_sells: int
    best: ClosedTrade | None
    worst: ClosedTrade | None
    #: The realized total at the end of each day that closed a trade, oldest first.
    series: tuple[PerformancePoint, ...]


@dataclass(slots=True)
class _Sale:
    """The shares one sell order took from a lot, and what they cost and brought in."""

    lot_key: str
    symbol: str
    qty: Decimal = ZERO
    cost: Decimal = ZERO
    proceeds: Decimal = ZERO
    last_at: dt.datetime | None = None
    priced: bool = True


def _lot_as_replayed(final: OwnedLot, held: dict[str, Decimal]) -> OwnedLot:
    entries = {entry: held.get(entry, ZERO) for entry in final.entry_remaining}
    total = sum(entries.values(), ZERO)
    return final.model_copy(
        update={
            "entry_remaining": entries,
            "remaining_qty": total,
            "original_qty": max(final.original_qty, total),
        }
    )


def _take(
    sale: _Sale,
    snapshot: LedgerSnapshot,
    final: OwnedLot,
    held: dict[str, Decimal],
    qty: Decimal,
    entries: tuple[str, ...] | None,
    price: Decimal | None,
    at: dt.datetime,
) -> bool:
    """Reduce the replayed lot as the ledger did, and book what was taken. False when the lot
    cannot supply it, which makes the lot unmatched."""
    before = _lot_as_replayed(final, held)
    try:
        after = before.reduced(qty, entries)
    except ValueError:
        return False
    for entry, left in after.entry_remaining.items():
        taken = before.entry_remaining[entry] - left
        held[entry] = left
        buy = snapshot.orders.get(entry)
        if taken and (buy is None or buy.filled_avg_price is None):
            sale.priced = False
        elif taken:
            assert buy is not None
            assert buy.filled_avg_price is not None
            sale.cost += taken * buy.filled_avg_price
    if price is None:
        sale.priced = False
    else:
        sale.proceeds += qty * price
    sale.qty += qty
    sale.last_at = at
    return True


def guru_performance(
    snapshot: LedgerSnapshot,
    events: tuple[JournalEvent, ...],
    *,
    guru_id: str,
    account_id: str,
    unrealized_usd: Decimal | None,
) -> GuruPerformance:
    """`events` are the journal's fills and manual sales, oldest first."""
    lots = {
        key: lot
        for key, lot in snapshot.lots.items()
        if (order := snapshot.orders.get(key)) is not None
        and (message := snapshot.messages.get(order.message_id)) is not None
        and message.guru == guru_id
    }
    lot_of = {entry: key for key, lot in lots.items() for entry in lot.entries(key)}
    held: dict[str, dict[str, Decimal]] = {key: {} for key in lots}
    sales: dict[str, _Sale] = {}
    broken: set[str] = set()
    filled: dict[str, Decimal] = defaultdict(lambda: ZERO)

    for event in events:
        payload = event.payload
        if isinstance(payload, OrderUpdate | LateOrderIncidentOpened | LateOrderIncidentReopened):
            order = snapshot.orders.get(payload.client_id)
            delta = payload.filled_qty - filled[payload.client_id]
            filled[payload.client_id] = payload.filled_qty
            if order is None or delta <= 0:
                continue
            if order.side == "buy":
                key = lot_of.get(order.client_id)
                if key is not None:
                    held[key][order.client_id] = held[key].get(order.client_id, ZERO) + delta
                continue
            key = order.lot_id if order.lot_id in lots else None
            if key is None:
                continue
            final = lots[key]
            before = _lot_as_replayed(final, held[key])
            # As the ledger applies a fill: no more than the buys the sell named hold.
            available = (
                before.remaining_of(order.from_entries)
                if order.from_entries
                else before.remaining_qty
            )
            applied = min(delta, available)
            sale = sales.setdefault(order.client_id, _Sale(lot_key=key, symbol=order.symbol))
            if applied < delta or not _take(
                sale,
                snapshot,
                final,
                held[key],
                applied,
                order.from_entries or None,
                order.filled_avg_price,
                event.at,
            ):
                broken.add(key)
        elif isinstance(payload, ManualSaleRecorded):
            sold = payload.sale
            if sold.lot_id not in lots:
                continue
            key = sold.lot_id
            sale = sales.setdefault(
                sold.order.client_order_id, _Sale(lot_key=key, symbol=sold.order.symbol)
            )
            if not _take(
                sale,
                snapshot,
                lots[key],
                held[key],
                sold.order.filled_qty,
                None,
                sold.order.filled_avg_price,
                event.at,
            ):
                broken.add(key)

    # A lot is trusted only if the replay ends where the ledger's lot is.
    for key, lot in lots.items():
        if {e: held[key].get(e, ZERO) for e in lot.entry_remaining} != lot.entry_remaining:
            broken.add(key)

    trades: list[ClosedTrade] = []
    unmatched = 0
    for sale in sales.values():
        if sale.lot_key in broken or not sale.priced or sale.last_at is None:
            unmatched += 1
            continue
        opening = snapshot.orders[sale.lot_key]
        message = snapshot.messages[opening.message_id]
        trades.append(
            ClosedTrade(
                symbol=sale.symbol,
                profit_usd=(sale.proceeds - sale.cost).quantize(CENT),
                closed_on=trade_date(sale.last_at),
                source_id=message.key,
                excerpt=excerpt(message.text),
                posted_at=message.timestamp,
            )
        )
    trades.sort(key=lambda trade: trade.closed_on)
    by_day: dict[dt.date, Decimal] = defaultdict(lambda: ZERO)
    for trade in trades:
        by_day[trade.closed_on] += trade.profit_usd
    running = ZERO
    series: list[PerformancePoint] = []
    for day in sorted(by_day):
        running += by_day[day]
        series.append(PerformancePoint(day=day, cumulative_usd=running))
    return GuruPerformance(
        guru_id=guru_id,
        account_id=account_id,
        realized_usd=running,
        unrealized_usd=unrealized_usd,
        closed_trades=len(trades),
        winning_trades=sum(1 for trade in trades if trade.profit_usd > 0),
        unmatched_sells=unmatched,
        best=max(trades, key=lambda trade: trade.profit_usd) if trades else None,
        worst=min(trades, key=lambda trade: trade.profit_usd) if trades else None,
        series=tuple(series),
    )
