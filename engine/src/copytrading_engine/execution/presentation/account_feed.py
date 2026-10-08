"""One account's feed: what happened to its money, a row per outcome, newest first."""

from decimal import Decimal
from typing import Literal

from pydantic import AwareDatetime

from copytrading_engine.execution.domain.events import (
    AccountControlChanged,
    JournalEvent,
    LimitChange,
    LimitsChanged,
    ManualSaleRecorded,
    OrderUpdate,
    OwnershipResolved,
)
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.values import Value

FeedKind = Literal[
    "bought",
    "sold",
    "cancelled",
    "expired",
    "rejected",
    "paused",
    "resumed",
    "settled",
    "limits_changed",
]
# Who made it happen: a guru's post, or the owner (a sale in the app or at the broker, a reviewed
# post, a pause, a settled holdings review).
FeedSource = Literal["guru", "you"]
_ENDED: dict[str, FeedKind] = {"canceled": "cancelled", "expired": "expired"}

_OWNER_ORDERS = ("lotsale-", "manual-")


class AccountFeedItem(Value):
    sequence: int
    at: AwareDatetime
    kind: FeedKind
    source: FeedSource
    # Which way an order went; a cancelled, expired, or rejected row needs it to say what ended.
    side: Literal["buy", "sell"] | None = None
    symbol: str | None = None
    shares: Decimal | None = None
    price: Decimal | None = None
    amount: Decimal | None = None
    guru_id: str | None = None
    message_id: str | None = None
    order_id: str | None = None
    # The limits the owner changed, for a limits_changed row.
    changes: tuple[LimitChange, ...] = ()


class AccountFeedPage(Value):
    account_id: str
    items: tuple[AccountFeedItem, ...]
    next_before_seq: int | None = None


def account_feed(
    account_id: str,
    snapshot: LedgerSnapshot,
    rows: tuple[tuple[int, JournalEvent], ...],
    limit: int,
) -> AccountFeedPage:
    items = tuple(item for seq, event in rows if (item := _item(seq, event, snapshot)) is not None)
    return AccountFeedPage(
        account_id=account_id,
        items=items,
        next_before_seq=rows[-1][0] if len(rows) == limit else None,
    )


def _item(seq: int, event: JournalEvent, snapshot: LedgerSnapshot) -> AccountFeedItem | None:
    payload = event.payload
    match payload:
        case OrderUpdate():
            return _order_item(seq, event, payload, snapshot)
        case ManualSaleRecorded(sale=sale):
            order = sale.order
            price = order.filled_avg_price
            return AccountFeedItem(
                sequence=seq,
                at=sale.filled_at,
                kind="sold",
                source="you",
                side="sell",
                symbol=order.symbol,
                shares=order.filled_qty,
                price=price,
                amount=None if price is None else order.filled_qty * price,
                order_id=order.client_order_id,
            )
        case OwnershipResolved(resolution=resolution):
            return AccountFeedItem(
                sequence=seq,
                at=event.at,
                kind="settled",
                source="you",
                symbol=resolution.request.symbol,
                shares=resolution.external_qty,
            )
        case LimitsChanged(changes=changes):
            return AccountFeedItem(
                sequence=seq, at=event.at, kind="limits_changed", source="you", changes=changes
            )
        case AccountControlChanged(result=result) if result.command.action in ("pause", "resume"):
            return AccountFeedItem(
                sequence=seq,
                at=event.at,
                kind="paused" if result.command.action == "pause" else "resumed",
                source="you",
            )
    return None


def _order_item(
    seq: int, event: JournalEvent, update: OrderUpdate, snapshot: LedgerSnapshot
) -> AccountFeedItem | None:
    order = snapshot.orders.get(update.client_id)
    if order is None:
        return None
    message = snapshot.messages.get(order.message_id)
    owner = update.client_id.startswith(_OWNER_ORDERS)
    filled = update.filled_qty
    # A partly filled order that then ended reads as what it bought or sold.
    if filled > 0 and update.filled_avg_price is not None:
        kind: FeedKind = "bought" if order.side == "buy" else "sold"
        shares, price = filled, update.filled_avg_price
        amount: Decimal | None = filled * price
    else:
        kind = _ENDED.get(update.status, "rejected")
        shares, price, amount = order.qty, order.limit_price, None
    return AccountFeedItem(
        sequence=seq,
        at=event.at,
        kind=kind,
        source="you" if owner else "guru",
        side=order.side,
        symbol=order.symbol,
        shares=shares,
        price=price,
        amount=amount,
        guru_id=None if owner or message is None else message.guru_id,
        message_id=order.message_id,
        order_id=update.client_id,
    )
