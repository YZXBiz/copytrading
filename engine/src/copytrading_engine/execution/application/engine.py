"""Copy use cases: coordinate typed broker operations and durable ledger transitions."""

import datetime as dt
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from decimal import ROUND_DOWN, Decimal
from typing import Literal

from copytrading_engine.execution.application.ledger import LATE_SKIPS, TradingLedger
from copytrading_engine.execution.application.ports import (
    AccountOpenRefused,
    Broker,
    BrokerError,
    ExecutionObserver,
    LedgerRepository,
    NoOpObserver,
    QuoteBroker,
)
from copytrading_engine.execution.domain.events import (
    BrokerAcknowledged,
    Exposure,
    JournalEvent,
    QuoteUnavailable,
    ReadBackSummary,
    SubmissionQuote,
)
from copytrading_engine.execution.domain.ledger_state import MessageRecord
from copytrading_engine.execution.domain.market import Account, BrokerOrder, CalendarDay, Position
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus, is_cancelable
from copytrading_engine.execution.domain.orders import (
    CancelReason,
    OrderPlan,
    OrderRecord,
    OrderRequest,
    OwnedLot,
)
from copytrading_engine.execution.domain.ownership import account_activity_reason, still_open
from copytrading_engine.execution.domain.positions import (
    PositionAudit,
    compare_positions,
    fee_allowance,
)
from copytrading_engine.execution.domain.pricing import (
    SELL_FLOOR_QUOTE_MAX_AGE_SECONDS,
    price_tick,
    quote_problem,
)
from copytrading_engine.execution.domain.progress import OrderLinked, Pending, Skipped
from copytrading_engine.execution.domain.risk import (
    MINIMUM_CRYPTO_BUY_USD,
    MINIMUM_ORDER_USD,
    EntryFacts,
    ExposureBreach,
    account_exposure,
    entry_budget,
)
from copytrading_engine.execution.domain.sessions import Session, SessionSchedule, trade_date
from copytrading_engine.execution.domain.signals import CopyConfig, SignalSourceNotAllowed
from copytrading_engine.execution.domain.sizing import DestinationSignal
from copytrading_engine.shared.signals import Instruction
from copytrading_engine.shared.symbols import is_crypto

ZERO = Decimal(0)
STEP = Decimal("0.000001")
# Independent broker reads for one decision go out together instead of one after another:
# each is a network round trip, and waiting for them in turn was most of a decision's time.
_BROKER_READS = ThreadPoolExecutor(max_workers=8, thread_name_prefix="broker-read")


@dataclass(frozen=True, slots=True)
class TradeDecision:
    plan: OrderPlan | None
    reason: str
    breaches: tuple[ExposureBreach, ...] = ()
    # For a sell skipped as `bought_after_sell`: when the first buy it would have sold was posted.
    bought_at: dt.datetime | None = None


@dataclass(frozen=True, slots=True)
class _ProcessControls:
    now: Callable[[], dt.datetime]
    monotonic: Callable[[], float]
    halted: Callable[[], bool]
    entry_block_reason: Callable[[], str | None]
    stopping: Callable[[], bool]


@dataclass(frozen=True, slots=True)
class _SubmissionGuard:
    signal_at: dt.datetime
    buy: bool
    started_at: dt.datetime
    started_monotonic: float
    max_age_seconds: int
    controls: _ProcessControls
    market_session: Callable[[dt.datetime, str], Session]

    @classmethod
    def begin(
        cls,
        signal_at: dt.datetime,
        *,
        buy: bool,
        max_age_seconds: int,
        controls: _ProcessControls,
        market_session: Callable[[dt.datetime, str], Session],
    ) -> _SubmissionGuard:
        started_at = controls.now()
        started_monotonic = controls.monotonic()
        return cls(
            signal_at,
            buy,
            started_at,
            started_monotonic,
            max_age_seconds,
            controls,
            market_session,
        )

    def check(self, plan: OrderPlan | None = None) -> tuple[str | None, dt.datetime]:
        current = self.controls.now()
        age = max(
            (current - self.signal_at).total_seconds(),
            (self.started_at - self.signal_at).total_seconds()
            + self.controls.monotonic()
            - self.started_monotonic,
        )
        # Only a buy can be too old: a late sell is still right, since the guru is out.
        if self.buy and (age > self.max_age_seconds or age < -5):
            return "stale", current
        if self.controls.stopping():
            return "stopping", current
        if self.buy and (reason := self.controls.entry_block_reason()) is not None:
            return reason, current
        if self.buy and self.controls.halted():
            return "halted", current
        if plan is not None and (
            trade_date(current) != trade_date(self.started_at)
            or self.market_session(current, plan.symbol) != plan.session
        ):
            return "session_changed", current
        return None, current


# Buys blocked only while an account recovers after a restart wait for it instead of being
# skipped: the next cycle tries again, and the signal age still decides when a post is too old.
RECOVERY_WAITS = frozenset({"recovery_pending", "manual_resume_required"})
# Why a sell waits and tries again instead of being skipped: a sell is never too old and never
# lost (ADR-0010), so anything that can clear by itself or by the owner's hand holds it. No
# fresh bid yet (a thin market's quotes can be minutes apart), the market closed, an open-order
# page Alpaca couldn't give whole, an order or holdings question on its stock, an order outside
# CopyTrading on its stock, overnight trading halted, the session changing, or a stop.
SELL_WAITS = frozenset(
    {
        "quote_stale",
        "quote_unavailable",
        "outside_session",
        "incomplete_account_orders",
        "unresolved_account_order",
        "unresolved_order_incident",
        "external_open_order",
        "position_mismatch",
        "ownership_incident",
        "overnight_halted",
        "session_changed",
        "stopping",
    }
)
# A waiting sell is planned again at most this often: each plan is five Alpaca requests, and the
# app polls every 2 seconds, which for one sell would be most of Alpaca's 200 requests a minute.
SELL_RETRY_SECONDS = 30
# Posts read back after CopyTrading was off are told to the owner once, in one summary, when none
# has come in for this long.
READ_BACK_QUIET_SECONDS = 60
# What a held buy that aged out says instead of a bare "stale".
_AGED_OUT_WAITING = {
    "recovery_pending": "stale_during_recovery",
    "manual_resume_required": "stale_waiting_for_resume",
}


class CopyEngine:
    def __init__(
        self,
        store: LedgerRepository,
        broker: Broker,
        config: CopyConfig,
        *,
        observer: ExecutionObserver | None = None,
    ) -> None:
        self.broker, self.config = broker, config
        self.observer = observer if observer is not None else NoOpObserver()
        self.ledger = TradingLedger(store, self.observer)
        self._calendar: dict[str, tuple[CalendarDay, ...]] = {}
        self._environment: str | None = None
        # When each waiting sell (post, part) may be planned again.
        self._sell_retry_at: dict[tuple[str, int], dt.datetime] = {}
        # Posts read back since the last summary, and when the latest came in.
        self._read_back: dict[str, None] = {}
        self._read_back_at: dt.datetime | None = None

    def bind(
        self,
        now: dt.datetime,
        account: Account | None = None,
        environment: Literal["paper", "live"] = "paper",
    ) -> Account:
        account = account if account is not None else self.broker.account()
        if not account.active:
            raise AccountOpenRefused("broker_account_inactive")
        if self.ledger.account_id is not None and self.ledger.account_id != account.id:
            # Records are placed by the Alpaca account their keys open before any account opens
            # (account_records), so this record is never another account's.
            raise RuntimeError("Broker account identity changed")
        if not self.ledger.account_id and self.broker.open_orders():
            # The first connection records what the account already holds; an order placed
            # outside CopyTrading could fill during that count, so the owner settles it first.
            raise AccountOpenRefused("outside_open_orders")
        positions = self.broker.positions()
        self.ledger.bind(account.id, now, environment, positions)
        self._environment = environment
        return account

    def receive(self, delivery: DestinationSignal, now: dt.datetime) -> None:
        signal = delivery.signal
        if self._environment is None:
            raise RuntimeError("Bind the broker account before receiving a destination")
        if delivery.terms.environment != self._environment:
            raise ValueError("Destination environment does not match account owner")
        if f"{signal.source}:{signal.channel_id}" not in self.config.sources:
            raise SignalSourceNotAllowed("Signal source is not configured for this account")
        key = f"{signal.source}:{signal.channel_id}:{signal.id}"
        new = key not in self.ledger.state.messages
        self.ledger.receive(delivery, now, self.config.max_signal_age_seconds)
        message = self.ledger.message(key)
        late = message.status in LATE_SKIPS or any(
            isinstance(part, Skipped) and part.reason in LATE_SKIPS for part in message.parts
        )
        if new and late:
            # Read back after CopyTrading was off: the owner hears of it in one summary.
            self._read_back[key] = None
            self._read_back_at = now

    def pending(self, symbol: str | None = None) -> tuple[OrderRecord, ...]:
        return self.ledger.pending(symbol)

    def audit_positions(self, positions: tuple[Position, ...] | None = None) -> PositionAudit:
        """The ledger's holdings against the broker's, read now unless `positions` were."""
        return compare_positions(
            self.ledger.lots(),
            self.pending(),
            self.broker.positions() if positions is None else positions,
            tuple(self.ledger.state.external_positions.values()),
            unsettled_fees=fee_allowance(self.ledger.orders()),
        )

    def reconcile(
        self, now: dt.datetime, *, settle_before: dt.datetime | None = None
    ) -> tuple[Position, ...]:
        """Book what the broker reports for every order still open, then audit holdings, and
        return the broker positions that audit read, after every fill it booked. A holdings
        question settles only once its count has held still for a later sync: with
        `settle_before`, only questions opened before then are settled."""
        pending = self.pending()
        pending_ids = {order.client_id for order in pending}
        for order in pending:
            update = self.broker.lookup(order.client_id)
            if update is None:
                # A lookup can be temporarily absent. Preserve the last broker
                # evidence for known and quarantined orders.
                if order.status in {OrderStatus.PREPARED, OrderStatus.UNCERTAIN}:
                    self.ledger.uncertain(order.client_id, now)
                continue
            self.ledger.apply_order(order.client_id, update, now)
            current = self.ledger.order(order.client_id)
            # Only a buy is cancelled for waiting: a sell keeps working at its floor until it fills,
            # its shares are gone, or copying stops (ADR-0010). A buy's timeout runs from when
            # Alpaca put it on the market, since Alpaca can hold an order for seconds first. A buy
            # Alpaca still hasn't put out a whole timeout after it was sent is cancelled too: the
            # call would be stale by the time it went out.
            live_since = current.accepted_at or current.created_at
            if (
                current.side == "buy"
                and current.pending
                and is_cancelable(current.status)
                and (now - live_since).total_seconds() >= self.config.order_timeout_seconds
            ):
                self.cancel(current, now, "timeout")

        # Operator-released IDs leave the ordinary pending set, but remain
        # under broker observation for their full audit history.
        snapshot = self.ledger.state
        for client_id in snapshot.release_evidence:
            if client_id in pending_ids:
                continue
            update = self.broker.lookup(client_id)
            if update is not None:
                self.ledger.apply_order(client_id, update, now)
        positions = self.broker.positions()
        self._count_crypto_fees(positions, now)
        self.ledger.open_ownership_incidents(
            self.audit_positions(positions),
            now,
            self._outside_orders(),
            settle_before=settle_before,
        )
        return positions

    def _count_crypto_fees(self, positions: tuple[Position, ...], now: dt.datetime) -> None:
        """Count Alpaca's fee on each coin's latest buys from the holding just read. Alpaca keeps
        the fee out of the coin bought and reports it only at the day's end, so the holding is the
        one place it shows (ADR-0014). The holding counts only when no order of the coin filled
        while it was read: each open order is looked up again, and one that moved waits for the
        next sync."""
        for symbol in sorted(
            {order.symbol for order in self.ledger.orders() if order.unsettled_fee_qty}
        ):
            still = all(
                (update := self.broker.lookup(order.client_id)) is not None
                and update.filled_qty == order.filled_qty
                for order in self.pending(symbol)
            )
            if not still:
                continue
            held = sum((p.qty for p in positions if p.symbol == symbol), ZERO)
            self.ledger.count_crypto_fee(symbol, self.ledger.expected_position(symbol) - held, now)

    def _outside_orders(self) -> frozenset[str]:
        """Stocks with an open broker order the app didn't place. Read only while a holdings
        question is open, since only settling one needs it."""
        if not any(
            not incident.resolved for incident in self.ledger.state.ownership_incidents.values()
        ):
            return frozenset()
        known = {order.client_id for order in self.pending()}
        return frozenset(
            order.symbol
            for order in self.broker.open_orders()
            if order.client_order_id not in known
        )

    def cancel(self, order: OrderRecord, now: dt.datetime, reason: CancelReason) -> None:
        if not order.broker_id or not is_cancelable(order.status):
            return
        try:
            self.broker.cancel(order.broker_id)
            self.ledger.cancel_requested(order.client_id, reason, now)
        except BrokerError as exc:
            if exc.status not in {404, 422}:
                raise
        # A later lookup must confirm cancellation before releasing the reservation.

    def _market_bid(self, symbol: str, now: dt.datetime) -> tuple[Decimal | None, str]:
        """The live bid for a sell at the market, or why there is none to sell against."""
        if not isinstance(self.broker, QuoteBroker):
            return None, "quote_unavailable"
        try:
            quote = self.broker.quote(symbol)
        except BrokerError:
            return None, "quote_unavailable"
        problem = quote_problem(quote, quote.bid, now, SELL_FLOOR_QUOTE_MAX_AGE_SECONDS)
        if problem is not None:
            return None, problem
        return quote.bid, "ready"

    def _posted_at(self, entry: str) -> dt.datetime:
        """When the post that made a buy was posted: its message's time, or the order's own for a
        buy with no post."""
        order = self.ledger.order(entry)
        message = self.ledger.state.messages.get(order.message_id)
        return message.timestamp if message is not None else order.created_at

    def _posted_before(self, entry: str, message_id: str) -> bool:
        """The buy came from a post no later than this one, or from earlier in the same post."""
        order = self.ledger.order(entry)
        sell = self.ledger.state.messages.get(message_id)
        if sell is None or order.message_id == message_id:
            return True
        return self._posted_at(entry) <= sell.timestamp

    def _sell_replaces(self, order: OrderRecord, sell: Instruction, message_id: str) -> bool:
        """An open buy this sell would have sold: at the buy price it names (any, when it names
        none), posted no later than it. A buy at another price, or posted after it, is a separate
        call and stays open."""
        if order.side != "buy" or order.message_id == message_id:
            return False
        if sell.entry_price is not None and order.entry_price != sell.entry_price:
            return False
        posted = self.ledger.state.messages.get(message_id)
        bought = self.ledger.state.messages.get(order.message_id)
        return posted is None or bought is None or bought.timestamp <= posted.timestamp

    def _crosses(self, symbol: str, side: Literal["buy", "sell"], limit_price: Decimal) -> bool:
        """An open order of the stock on the other side this one would trade with: a sell at or
        under this buy's limit, or a buy at or over this sell's."""
        return any(
            order.side != side
            and (
                order.limit_price is None
                or (
                    order.limit_price <= limit_price
                    if side == "buy"
                    else order.limit_price >= limit_price
                )
            )
            for order in self.pending(symbol)
        )

    def _selling(self, symbol: str) -> Decimal:
        """The shares of the stock the open sells have yet to sell."""
        return sum(
            (
                order.qty - order.filled_qty
                for order in self.pending(symbol)
                if order.side == "sell"
            ),
            ZERO,
        )

    def _unsold(
        self, lot_id: str, lot: OwnedLot, from_entries: tuple[str, ...]
    ) -> tuple[Decimal, Decimal | None]:
        """What the buys a sell takes from hold less what the open sells of any of them have yet
        to sell, and the most it can sell without taking shares an open sell of other buys in the
        lot still needs (None when no open sell shares a buy with it).

        The lot splits a fill across the buys a sell names in proportion to what each holds, so a
        sell is safe only while every open sell that shares a buy with it, this one included,
        fits in that sell's own buys."""
        chosen = set(from_entries or lot.entries(lot_id))
        working = [
            (order.qty - order.filled_qty, set(order.from_entries or lot.entries(lot_id)))
            for order in self.pending(lot.symbol)
            if order.side == "sell" and order.lot_id == lot_id
        ]
        held = lot.remaining_of(from_entries) if from_entries else lot.remaining_qty
        sharing = [(left, entries) for left, entries in working if entries & chosen]
        unsold = held - sum((left for left, _ in sharing), ZERO)
        if not sharing:
            return unsold, None
        room = unsold
        for _, entries in sharing:
            others = sum((left for left, other in working if other & entries), ZERO)
            room = min(room, lot.remaining_of(tuple(entries)) - others)
        return unsold, room

    def _activity_reason(
        self, open_orders: tuple[BrokerOrder, ...], instruction: Instruction
    ) -> str | None:
        """Why the account's open orders hold this decision, if they do. A buy spends the account's
        cash, so every order and every order incident holds it; a sell answers only to its own
        stock's, which an order elsewhere can't change (ADR-0010)."""
        if instruction.action == "buy":
            return account_activity_reason(
                open_orders,
                self.pending(),
                unresolved_order_incidents=self.ledger.state.entry_halted,
            )
        return account_activity_reason(
            open_orders,
            self.pending(),
            unresolved_order_incidents=any(
                incident.unresolved and incident.symbol == instruction.symbol
                for incident in self.ledger.state.late_order_incidents.values()
            ),
            symbol=instruction.symbol,
        )

    def market_session(self, now: dt.datetime, symbol: str | None = None) -> Session:
        """The session an order of `symbol` would trade in now: a coin's is always open, a
        stock's comes from the broker's calendar and the account's hours."""
        if symbol is not None and is_crypto(symbol):
            return Session.AROUND_THE_CLOCK
        date = trade_date(now).isoformat()
        if date not in self._calendar:
            self._calendar = {date: self.broker.calendar(date)}
        days = self._calendar[date]
        if not days:
            return Session.CLOSED
        if len(days) != 1 or days[0].date.isoformat() != date:
            raise RuntimeError("Broker calendar identity mismatch")
        day = days[0]
        schedule = SessionSchedule(
            regular_open=day.open,
            regular_close=day.close,
            extended_open=day.session_open,
            extended_close=day.session_close or day.close,
        )
        return schedule.at(
            now, extended=self.config.extended_hours, overnight=self.config.overnight
        )

    def decide(
        self,
        instruction: Instruction,
        message_id: str,
        source_key: str,
        now: dt.datetime,
        *,
        halted: bool,
        manual: bool = False,
        chosen_lot: str | None = None,
        chosen_qty: Decimal | None = None,
    ) -> TradeDecision:
        """Plan one instruction. An exit with `chosen_lot` sells that lot, up to `chosen_qty`
        shares, as the owner chose it, even when exits are not copied."""
        s, c = instruction, self.config
        crypto = is_crypto(s.symbol)
        if crypto and self._environment != "paper":
            # Crypto is copied on paper accounts only: a live account never sends a coin's order,
            # whoever asks for it (ADR-0014).
            return TradeDecision(None, "crypto_paper_only")
        if self.ledger.unresolved_ownership(s.symbol):
            return TradeDecision(None, "ownership_incident")
        if s.action == "buy" and (halted or self.ledger.state.buy_halted):
            return TradeDecision(None, "halted")
        if s.action != "buy" and not c.copy_exits and chosen_lot is None:
            return TradeDecision(None, "exits_disabled")
        active = self.pending(s.symbol)
        # An order the owner places by hand waits for every open order on the stock.
        if active and manual:
            return TradeDecision(None, "wait_pending_order")
        # A buy waits for an earlier open buy of the stock; it never waits for an open sell unless
        # the two would cross, which is checked once its price is known (ADR-0010).
        if s.action == "buy" and any(order.side == "buy" for order in active):
            return TradeDecision(None, "wait_pending_order")
        if s.action != "buy":
            # A sell cancels an open buy it would have sold (the guru got out before the copy got
            # in) and waits until that buy has ended, so it also sells what the buy filled.
            replaced = tuple(order for order in active if self._sell_replaces(order, s, message_id))
            for order in replaced:
                if is_cancelable(order.status):
                    self.cancel(order, now, "replaced_by_sell")
            if replaced:
                return TradeDecision(None, "wait_pending_order")
        session = self.market_session(now, s.symbol)
        if session == Session.CLOSED:
            return TradeDecision(None, "outside_session")
        asset_read = _BROKER_READS.submit(self.broker.asset, s.symbol)
        account_read = _BROKER_READS.submit(self.broker.account)
        positions_read = _BROKER_READS.submit(self.broker.positions)
        open_orders_read = _BROKER_READS.submit(self.broker.open_orders)
        try:
            asset = asset_read.result()
        except BrokerError as exc:
            if exc.status != 404:
                raise
            # Alpaca lists no such stock: a typo, a delisted name, or a listing it does not carry.
            return TradeDecision(None, "unsupported_asset")
        if asset.symbol != s.symbol:
            raise RuntimeError("Broker asset identity mismatch")
        if (
            not asset.tradable
            or asset.asset_class != ("crypto" if crypto else "us_equity")
            or asset.status != "active"
        ):
            return TradeDecision(None, "unsupported_asset")
        # A coin trades in its own steps (Alpaca's asset); a stock's are cents and millionths.
        price_increment = asset.price_increment if crypto else None
        qty_step = asset.min_trade_increment if crypto and asset.min_trade_increment else STEP
        if session == Session.OVERNIGHT:
            if not (asset.overnight_tradable or "overnight_tradable" in asset.attributes):
                return TradeDecision(None, "overnight_not_supported")
            if asset.overnight_halted or "overnight_halted" in asset.attributes:
                return TradeDecision(None, "overnight_halted")
        source_price = s.price
        if source_price is None:
            # A sell at the market (ADR-0007): the live bid stands in for the guru's price, so
            # the limit under it still bounds how low the copy can fill.
            source_price, problem = self._market_bid(s.symbol, now)
            if source_price is None:
                return TradeDecision(None, problem)
        tick = price_tick(source_price, price_increment)
        if s.action == "buy" and source_price != source_price.quantize(tick):
            return TradeDecision(None, "invalid_price_tick")
        lot_id = None
        limit_price = None
        room: Decimal | None = None
        account = account_read.result()
        if account.id != self.ledger.account_id:
            raise RuntimeError("Broker account identity changed")
        positions = positions_read.result()
        activity_reason = self._activity_reason(
            still_open(open_orders_read.result(), self.ledger.orders()), s
        )
        if activity_reason is not None:
            return TradeDecision(None, activity_reason)
        joins_lot = None
        from_entries: tuple[str, ...] = ()
        requested_usd = None
        budget_usd = None
        limited_by = None
        if s.action == "buy":
            # Only a buy is checked against the whole account: a sell needs only its own stock's
            # shares and price, and no cap or valuation elsewhere in the account ever holds it.
            try:
                exposure = account_exposure(
                    positions,
                    self.ledger.lots(),
                    self.pending(),
                    account_currency=account.currency,
                )
            except ValueError:
                return TradeDecision(None, "account_risk_unavailable")
            limit_price = c.pricing.buy_ceiling(source_price, price_increment)
            if self._crosses(s.symbol, "buy", limit_price):
                # Alpaca refuses a buy at or above an open sell of the stock as a possible wash
                # trade: it waits for the sell, and the buy's age limit still ends the wait.
                return TradeDecision(None, "wait_pending_order")
            # Every buy of a stock joins the guru's open lot of it (ADR-0010).
            open_lots = self.ledger.position_lots(source_key, s.symbol)
            joins_lot = open_lots[0][0] if open_lots else None
            anchor = None
            if not manual:
                anchor = self.ledger.anchor_cash(
                    message_id, account.id, account.cash, account.buying_power, now
                )
            # Filled cost remains spent. Pending/unknown submission reserves its
            # full limit notional; terminal unfilled shares release their reserve.
            committed_in_message = sum(
                (
                    (order.qty if order.pending else order.filled_qty) * order.limit_price
                    for order in self.ledger.orders()
                    if order.message_id == message_id
                    and order.side == "buy"
                    and order.limit_price is not None
                ),
                ZERO,
            )
            facts = EntryFacts(
                symbol_exposure=exposure.symbol(s.symbol),
                total_exposure=exposure.total,
                cash=max(
                    ZERO,
                    min(
                        account.cash,
                        (anchor.cash if anchor is not None else account.cash)
                        - committed_in_message,
                    ),
                ),
                buying_power=max(
                    ZERO,
                    min(
                        account.buying_power,
                        (anchor.buying_power if anchor is not None else account.buying_power)
                        - committed_in_message,
                    ),
                ),
                equity=account.equity,
                last_equity=account.last_equity,
                entries_today=sum(
                    o.side == "buy"
                    and o.day == trade_date(now)
                    and o.status != "aborted_before_submit"
                    for o in self.ledger.orders()
                ),
                account_active=account.active,
            )
            connection = self.ledger.message(message_id).destination.connection
            minimum_usd = MINIMUM_CRYPTO_BUY_USD if crypto else MINIMUM_ORDER_USD
            decision = entry_budget(
                c, facts, connection, s.fraction, s.usd_amount, minimum_usd=minimum_usd
            )
            if decision.budget is None:
                return TradeDecision(None, decision.reason, decision.breaches)
            requested_usd = decision.requested
            budget_usd = decision.budget
            limited_by = decision.limited_by
            qty = (decision.budget / limit_price).quantize(qty_step, rounding=ROUND_DOWN)
            if crypto and (
                qty * limit_price < minimum_usd
                or (asset.min_order_size is not None and qty < asset.min_order_size)
            ):
                # Rounded down to the coin's step, the buy no longer costs Alpaca's $10 minimum.
                return TradeDecision(None, "below_minimum_budget")
            entry_price = source_price
        else:
            if chosen_lot is not None:
                lot = self.ledger.state.lots.get(chosen_lot)
                if lot is None or lot.symbol != s.symbol or lot.remaining_qty <= 0:
                    return TradeDecision(None, "lot_unavailable")
                lot_id = chosen_lot
            else:
                lots = self.ledger.position_lots(source_key, s.symbol)
                if not lots:
                    return TradeDecision(None, "lot_unavailable")
                if len(lots) != 1:
                    return TradeDecision(None, "missing_or_ambiguous_lot")
                lot_id, lot = lots[0]
            entry_price = lot.entry_price
            # The buys an "of the original" share counts, sold-out ones included.
            basis = lot.entries(lot_id)
            if chosen_lot is None:
                # A sell that names a buy price takes from the buys at exactly that price; one
                # that names none takes from every buy (ADR-0010).
                named = s.entry_price is not None
                if named:
                    basis = tuple(e for e in basis if lot.entry_prices[e] == s.entry_price)
                buys = tuple(e for e in basis if lot.entry_remaining.get(e, ZERO) > 0)
                if named and not buys:
                    return TradeDecision(None, "named_buy_not_held")
                if named:
                    # The order sells those buys, so it carries their price, as the post named it.
                    entry_price = s.entry_price
                # A sell read late can be processed after a buy the guru posted after it: it only
                # takes from, and counts, buys posted before it, never a later one (ADR-0010).
                basis = tuple(e for e in basis if self._posted_before(e, message_id))
                earlier = tuple(e for e in buys if e in basis)
                if not earlier:
                    later = min(self._posted_at(entry) for entry in buys)
                    return TradeDecision(None, "bought_after_sell", bought_at=later)
                if named or len(earlier) != len(buys):
                    from_entries = earlier
            # A sell plans against the shares no open sell has already taken: "half of the rest"
            # is half of what is left once the sells still working have sold (ADR-0010).
            held, room = self._unsold(lot_id, lot, from_entries)
            if held <= 0:
                return TradeDecision(None, "already_selling")
            qty = held if chosen_qty is None else min(held, chosen_qty)
            if s.action == "reduce":
                assert s.fraction is not None
                # "Sell half" is half of what is left, unless the post or playbook says the
                # original buy.
                if s.exit_basis == "original_position":
                    bought = sum((self.ledger.order(entry).received_qty for entry in basis), ZERO)
                    qty = min(qty, bought * s.fraction)
                else:
                    qty = min(qty, held * s.fraction)
            qty = qty.quantize(qty_step, rounding=ROUND_DOWN)
            # An exit is a limit order too: its floor is the guru's sell price less the allowance,
            # so it sells whenever the market is at or above that floor (ADR-0010).
            limit_price = c.pricing.sell_floor(source_price, price_increment)
            if self._crosses(s.symbol, "sell", limit_price):
                # A sell at or under an open buy of the stock would trade with it: it waits.
                return TradeDecision(None, "wait_pending_order")
        if not asset.fractionable:
            qty = qty.quantize(Decimal(1), rounding=ROUND_DOWN)
        if qty <= 0:
            return TradeDecision(None, "below_minimum_quantity")
        if room is not None and qty > room:
            # An open sell of other buys in the lot still needs these shares: the lot splits a fill
            # across the buys a sell names, so this one waits for it rather than take them.
            return TradeDecision(None, "wait_pending_order")
        owned = self.ledger.owned(s.symbol)
        # The last-moment re-check reads both again, together, right before the order.
        final_positions_read = _BROKER_READS.submit(self.broker.positions)
        final_open_read = _BROKER_READS.submit(self.broker.open_orders)
        positions = final_positions_read.result()
        actual = sum((p.qty for p in positions if p.symbol == s.symbol), ZERO)
        if actual != self.ledger.expected_position(s.symbol):
            [count] = (p for p in self.audit_positions(positions).positions if p.symbol == s.symbol)
            if count.mismatched:
                return TradeDecision(None, "position_mismatch")
            # An open order of the stock filled since it was last booked: the next sync books it.
            return TradeDecision(None, "wait_pending_order")
        final_open = still_open(final_open_read.result(), self.ledger.orders())
        activity_reason = self._activity_reason(final_open, s)
        if activity_reason is not None:
            return TradeDecision(None, activity_reason)
        known = {order.client_id for order in active}
        if any(o.symbol == s.symbol and o.client_order_id not in known for o in final_open):
            return TradeDecision(None, "external_open_order")
        if s.action != "buy" and qty > owned - self._selling(s.symbol):
            return TradeDecision(None, "insufficient_owned_shares")
        if c.approve_orders and not manual:
            # Every check passed, so this is an order the account would have sent: hold it for the
            # owner, who approves it by hand (a manual copy plans afresh and is not held again).
            return TradeDecision(None, "approval_required")
        return TradeDecision(
            OrderPlan(
                symbol=s.symbol,
                side="buy" if s.action == "buy" else "sell",
                position_intent="buy_to_open" if s.action == "buy" else "sell_to_close",
                qty=qty,
                type="limit",
                limit_price=limit_price,
                source_price=source_price,
                entry_tolerance_pct=c.pricing.max_above_signal_pct
                if s.action == "buy"
                else c.pricing.max_below_signal_pct,
                lot_id=lot_id,
                entry_price=entry_price,
                session=session,
                joins_lot=joins_lot,
                from_entries=from_entries,
                requested_usd=requested_usd,
                budget_usd=budget_usd,
                limited_by=limited_by,
            ),
            "ready",
        )

    def process(
        self,
        now: dt.datetime,
        *,
        halted: bool = False,
        now_clock: Callable[[], dt.datetime] | None = None,
        monotonic_clock: Callable[[], float] = time.monotonic,
        halted_now: Callable[[], bool] | None = None,
        entry_block_reason: Callable[[], str | None] | None = None,
        stopping: Callable[[], bool] | None = None,
    ) -> None:
        if now_clock is None:
            cycle_started = monotonic_clock()

            def default_now_clock() -> dt.datetime:
                return now + dt.timedelta(seconds=max(0, monotonic_clock() - cycle_started))

            now_clock = default_now_clock
        operator_halted = halted_now or (lambda: halted)
        controls = _ProcessControls(
            now=now_clock,
            monotonic=monotonic_clock,
            halted=lambda: operator_halted() or self.ledger.state.buy_halted,
            entry_block_reason=entry_block_reason or (lambda: None),
            stopping=stopping or (lambda: False),
        )
        for message in self.ledger.queued():
            for index, instruction in enumerate(message.instructions):
                if not isinstance(self.ledger.message(message.key).parts[index], Pending):
                    continue
                self._process_instruction(message, index, instruction, controls)
            if all(
                not isinstance(part, Pending) for part in self.ledger.message(message.key).parts
            ):
                self.ledger.complete(message.key, controls.now())
        self._summarize_read_back(controls.now())

    def _summarize_read_back(self, now: dt.datetime) -> None:
        """Once posts stop coming back, tell the owner what came of them in one message."""
        if self._read_back_at is None or (
            (now - self._read_back_at).total_seconds() < READ_BACK_QUIET_SECONDS
        ):
            return
        messages = [self.ledger.message(key) for key in self._read_back]
        sells = sum(
            isinstance(part, OrderLinked) and instruction.action != "buy"
            for message in messages
            for part, instruction in zip(message.parts, message.instructions, strict=True)
        )
        too_old = sum(
            instruction.action == "buy"
            and (
                message.status in LATE_SKIPS
                or (isinstance(part, Skipped) and part.reason in LATE_SKIPS)
            )
            for message in messages
            for part, instruction in zip(message.parts, message.instructions, strict=True)
        )
        self.ledger.record(
            JournalEvent(
                at=now,
                payload=ReadBackSummary(
                    posts=len(messages), sells_copied=sells, buys_too_old=too_old
                ),
            )
        )
        self._read_back, self._read_back_at = {}, None

    def _process_instruction(
        self,
        message: MessageRecord,
        index: int,
        instruction: Instruction,
        controls: _ProcessControls,
    ) -> None:
        retry = (message.key, index)
        if instruction.action != "buy" and controls.now() < self._sell_retry_at.get(
            retry, dt.datetime.min.replace(tzinfo=dt.UTC)
        ):
            return
        guard = _SubmissionGuard.begin(
            message.timestamp,
            buy=instruction.action == "buy",
            max_age_seconds=self.config.max_signal_age_seconds,
            controls=controls,
            market_session=self.market_session,
        )
        blocked, current = guard.check()
        if self._held(instruction, blocked):
            return
        if blocked is not None:
            self.ledger.skip(
                message.key, index, self._skip_reason(instruction, blocked, controls), current
            )
            return
        with self.observer.span("risk_checks", message.key):
            decision = self.decide(
                instruction, message.key, message.source_key, current, halted=controls.halted()
            )
        if decision.reason == "wait_pending_order":
            return
        if decision.plan is None and instruction.action != "buy" and decision.reason in SELL_WAITS:
            self._sell_retry_at[retry] = current + dt.timedelta(seconds=SELL_RETRY_SECONDS)
            if decision.reason in {"quote_stale", "quote_unavailable"}:
                self.ledger.sell_waiting(message.key, index, decision.reason, current)
            return
        self._sell_retry_at.pop(retry, None)
        if decision.plan is None:
            details = tuple(
                Exposure(
                    scope=breach.scope,
                    current=breach.current,
                    proposed=breach.proposed,
                    limit=breach.limit,
                )
                for breach in decision.breaches
            )
            self.ledger.skip(
                message.key,
                index,
                decision.reason,
                controls.now(),
                exposure=details or None,
                bought_at=decision.bought_at,
            )
            return
        blocked, current = guard.check(decision.plan)
        if self._held(instruction, blocked):
            return
        if blocked is not None:
            self.ledger.skip(
                message.key, index, self._skip_reason(instruction, blocked, controls), current
            )
            return
        order = self.ledger.prepare(decision.plan, message.key, index, current)
        self._submit_prepared_order(message.key, order, guard)

    @staticmethod
    def _held(instruction: Instruction, blocked: str | None) -> bool:
        """A buy that only waits for the account's restart recovery stays pending, and so does a
        sell held by anything that can clear (`SELL_WAITS`): a sell is never lost."""
        if instruction.action == "buy":
            return blocked in RECOVERY_WAITS
        return blocked in SELL_WAITS

    @staticmethod
    def _skip_reason(instruction: Instruction, blocked: str, controls: _ProcessControls) -> str:
        """A buy that aged out while its account recovered says why it waited, not just that it
        is old."""
        if instruction.action == "buy" and blocked == "stale":
            waiting = controls.entry_block_reason()
            if waiting in _AGED_OUT_WAITING:
                return _AGED_OUT_WAITING[waiting]
        return blocked

    def _submit_prepared_order(
        self,
        message_key: str,
        order: OrderRecord,
        guard: _SubmissionGuard,
    ) -> None:
        request = OrderRequest.for_plan(
            order,
            order.client_id,
            # Marked for extended hours only outside the regular session: Alpaca routes such an
            # order differently even at 9:30, and a regular-session order needs no flag. A coin's
            # order carries no hours at all.
            extended_hours=order.type == "limit" and order.session != Session.REGULAR,
        )
        try:
            with self.observer.span("order_submission", message_key):
                blocked, current = guard.check(order)
                if blocked is not None:
                    self.ledger.abort_before_submit(order.client_id, blocked, current)
                    return
                self.ledger.submitting(order.client_id, current)
                blocked, current = guard.check(order)
                if blocked is not None:
                    self.ledger.abort_before_submit(order.client_id, blocked, current)
                    return
                self.ledger.apply_order(
                    order.client_id, self.broker.submit(request), guard.controls.now()
                )
                self.ledger.record(
                    JournalEvent(
                        at=guard.controls.now(),
                        payload=BrokerAcknowledged(
                            client_id=order.client_id,
                            message_id=order.message_id,
                        ),
                    )
                )
            if isinstance(self.broker, QuoteBroker):
                try:
                    with self.observer.span("quote_snapshot", message_key):
                        quote = self.broker.quote(order.symbol)
                    self.ledger.record(
                        JournalEvent(
                            at=guard.controls.now(),
                            payload=SubmissionQuote(
                                client_id=order.client_id,
                                message_id=order.message_id,
                                quote=quote,
                            ),
                        )
                    )
                except BrokerError:
                    self.ledger.record(
                        JournalEvent(
                            at=guard.controls.now(),
                            payload=QuoteUnavailable(
                                client_id=order.client_id,
                                message_id=order.message_id,
                            ),
                        )
                    )
        except BrokerError as exc:
            self.ledger.submission_failed(order.client_id, exc.status, guard.controls.now())

    def submit_manual_prepared(
        self,
        order: OrderRecord,
        now: dt.datetime,
        *,
        halted: Callable[[], bool],
        entry_block_reason: Callable[[], str | None],
        stopping: Callable[[], bool],
    ) -> OrderRecord:
        """Submit an already durable operator-confirmed intent through the normal path."""
        started = time.monotonic()

        def current_time() -> dt.datetime:
            return now + dt.timedelta(seconds=max(0, time.monotonic() - started))

        controls = _ProcessControls(
            now=current_time,
            monotonic=time.monotonic,
            halted=halted,
            entry_block_reason=entry_block_reason,
            stopping=stopping,
        )
        guard = _SubmissionGuard.begin(
            now,
            buy=order.side == "buy",
            max_age_seconds=self.config.max_signal_age_seconds,
            controls=controls,
            market_session=self.market_session,
        )
        self._submit_prepared_order(order.message_id, order, guard)
        return self.ledger.order(order.client_id)
