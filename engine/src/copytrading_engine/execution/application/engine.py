"""Copy use cases: coordinate typed broker operations and durable ledger transitions."""

import datetime as dt
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from decimal import ROUND_DOWN, Decimal
from typing import Literal

from copytrading_engine.execution.application.ledger import TradingLedger
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
    CancelReason,
    CancelRequested,
    Exposure,
    JournalEvent,
    QuoteUnavailable,
    SubmissionQuote,
)
from copytrading_engine.execution.domain.ledger_state import MessageRecord
from copytrading_engine.execution.domain.market import Account, CalendarDay
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus, is_cancelable
from copytrading_engine.execution.domain.orders import OrderPlan, OrderRecord, OrderRequest
from copytrading_engine.execution.domain.ownership import account_activity_reason
from copytrading_engine.execution.domain.positions import PositionAudit, compare_positions
from copytrading_engine.execution.domain.progress import Pending
from copytrading_engine.execution.domain.risk import (
    EntryFacts,
    ExposureBreach,
    account_exposure,
    entry_budget,
)
from copytrading_engine.execution.domain.sessions import Session, SessionSchedule, trade_date
from copytrading_engine.execution.domain.signals import CopyConfig, SignalSourceNotAllowed
from copytrading_engine.execution.domain.sizing import DestinationSignal
from copytrading_engine.shared.signals import Instruction

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
    market_session: Callable[[dt.datetime], Session]

    @classmethod
    def begin(
        cls,
        signal_at: dt.datetime,
        *,
        buy: bool,
        max_age_seconds: int,
        controls: _ProcessControls,
        market_session: Callable[[dt.datetime], Session],
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
        if age > self.max_age_seconds or age < -5:
            return "stale", current
        if self.controls.stopping():
            return "stopping", current
        if self.buy and (reason := self.controls.entry_block_reason()) is not None:
            return reason, current
        if self.buy and self.controls.halted():
            return "halted", current
        if plan is not None and (
            trade_date(current) != trade_date(self.started_at)
            or self.market_session(current) != plan.session
        ):
            return "session_changed", current
        return None, current


# Buys blocked only while an account recovers after a restart wait for it instead of being
# skipped: the next cycle tries again, and the signal age still decides when a post is too old.
RECOVERY_WAITS = frozenset({"recovery_pending", "manual_resume_required"})
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
        self.ledger.receive(delivery, now, self.config.max_signal_age_seconds)

    def pending(self, symbol: str | None = None) -> tuple[OrderRecord, ...]:
        return self.ledger.pending(symbol)

    def audit_positions(self) -> PositionAudit:
        return compare_positions(
            self.ledger.lots(),
            self.pending(),
            self.broker.positions(),
            tuple(self.ledger.snapshot().external_positions.values()),
        )

    def reconcile(self, now: dt.datetime) -> None:
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
            if (
                current.pending
                and is_cancelable(current.status)
                and (now - current.created_at).total_seconds() >= self.config.order_timeout_seconds
            ):
                self.cancel(current, now, "timeout")

        # Operator-released IDs leave the ordinary pending set, but remain
        # under broker observation for their full audit history.
        snapshot = self.ledger.snapshot()
        for client_id in snapshot.release_evidence:
            if client_id in pending_ids:
                continue
            update = self.broker.lookup(client_id)
            if update is not None:
                self.ledger.apply_order(client_id, update, now)
        self.ledger.open_ownership_incidents(self.audit_positions(), now)

    def cancel(self, order: OrderRecord, now: dt.datetime, reason: CancelReason) -> None:
        if not order.broker_id or not is_cancelable(order.status):
            return
        try:
            self.broker.cancel(order.broker_id)
            self.ledger.record(
                JournalEvent(
                    at=now,
                    payload=CancelRequested(
                        client_id=order.client_id,
                        message_id=order.message_id,
                        reason=reason,
                    ),
                )
            )
        except BrokerError as exc:
            if exc.status not in {404, 422}:
                raise
        # A later lookup must confirm cancellation before releasing the reservation.

    def market_session(self, now: dt.datetime) -> Session:
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
        if self.ledger.unresolved_ownership(s.symbol):
            return TradeDecision(None, "ownership_incident")
        if s.action == "buy" and (halted or self.ledger.snapshot().buy_halted):
            return TradeDecision(None, "halted")
        if s.action != "buy" and not c.copy_exits and chosen_lot is None:
            return TradeDecision(None, "exits_disabled")
        active = self.pending(s.symbol)
        if active:
            if s.action != "buy" and not manual:
                for order in active:
                    if order.message_id != message_id and is_cancelable(order.status):
                        self.cancel(order, now, "replaced_by_sell")
            return TradeDecision(None, "wait_pending_order")
        session = self.market_session(now)
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
        if not asset.tradable or asset.asset_class != "us_equity" or asset.status != "active":
            return TradeDecision(None, "unsupported_asset")
        if session == Session.OVERNIGHT:
            if not (asset.overnight_tradable or "overnight_tradable" in asset.attributes):
                return TradeDecision(None, "overnight_not_supported")
            if asset.overnight_halted or "overnight_halted" in asset.attributes:
                return TradeDecision(None, "overnight_halted")
        tick = Decimal("0.01") if s.price >= 1 else Decimal("0.0001")
        if s.action == "buy" and s.price != s.price.quantize(tick):
            return TradeDecision(None, "invalid_price_tick")
        lot_id = None
        limit_price = None
        account = account_read.result()
        if account.id != self.ledger.account_id:
            raise RuntimeError("Broker account identity changed")
        positions = positions_read.result()
        broker_open = open_orders_read.result()
        activity_reason = account_activity_reason(
            broker_open,
            self.pending(),
            unresolved_order_incidents=self.ledger.snapshot().entry_halted,
        )
        if activity_reason is not None:
            return TradeDecision(None, activity_reason)
        try:
            exposure = account_exposure(
                positions,
                self.ledger.lots(),
                self.pending(),
                account_currency=account.currency,
            )
        except ValueError:
            return TradeDecision(None, "account_risk_unavailable")
        joins_lot = None
        from_entries: tuple[str, ...] = ()
        requested_usd = None
        budget_usd = None
        if s.action == "buy":
            limit_price = c.entry_pricing.limit_price(s.price)
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
            decision = entry_budget(c, facts, connection, s.fraction)
            if decision.budget is None:
                return TradeDecision(None, decision.reason, decision.breaches)
            requested_usd = decision.requested
            budget_usd = decision.budget
            qty = (decision.budget / limit_price).quantize(STEP, rounding=ROUND_DOWN)
            entry_price = s.price
        else:
            if chosen_lot is not None:
                lot = self.ledger.snapshot().lots.get(chosen_lot)
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
            # A sell that names a buy price takes from the buys at exactly that price; one that
            # names none takes from every buy (ADR-0010).
            if s.entry_price is not None and chosen_lot is None:
                from_entries = lot.entries_at(s.entry_price)
                if not from_entries:
                    return TradeDecision(None, "named_buy_not_held")
                # The order sells those buys, so it carries their price, as the post named it.
                entry_price = s.entry_price
            held = lot.remaining_of(from_entries) if from_entries else lot.remaining_qty
            qty = held if chosen_qty is None else min(held, chosen_qty)
            if s.action == "reduce":
                assert s.fraction is not None
                # "Sell half" is half of what is left, unless the post or playbook says the
                # original buy.
                if s.exit_basis == "original_position":
                    bought = sum(
                        (
                            self.ledger.order(entry).filled_qty
                            for entry in (from_entries or lot.entries(lot_id))
                        ),
                        ZERO,
                    )
                    qty = min(qty, bought * s.fraction)
                else:
                    qty = min(qty, held * s.fraction)
            qty = qty.quantize(STEP, rounding=ROUND_DOWN)
            # An exit is a limit order too, no lower than the allowance under the guru's price.
            limit_price = c.entry_pricing.exit_limit_price(s.price)
        if not asset.fractionable:
            qty = qty.quantize(Decimal(1), rounding=ROUND_DOWN)
        if qty <= 0:
            return TradeDecision(None, "below_minimum_quantity")
        owned = self.ledger.owned(s.symbol)
        # The last-moment re-check reads both again, together, right before the order.
        final_positions_read = _BROKER_READS.submit(self.broker.positions)
        final_open_read = _BROKER_READS.submit(self.broker.open_orders)
        positions = final_positions_read.result()
        actual = sum((p.qty for p in positions if p.symbol == s.symbol), ZERO)
        if actual != self.ledger.expected_position(s.symbol):
            return TradeDecision(None, "position_mismatch")
        final_open = final_open_read.result()
        activity_reason = account_activity_reason(
            final_open,
            self.pending(),
            unresolved_order_incidents=self.ledger.snapshot().entry_halted,
        )
        if activity_reason is not None:
            return TradeDecision(None, activity_reason)
        if any(o.symbol == s.symbol for o in final_open):
            return TradeDecision(None, "external_open_order")
        if s.action != "buy" and qty > owned:
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
                source_price=s.price,
                entry_tolerance_pct=c.entry_pricing.max_above_signal_pct
                if s.action == "buy"
                else c.entry_pricing.max_below_signal_pct,
                lot_id=lot_id,
                entry_price=entry_price,
                session=session,
                joins_lot=joins_lot,
                from_entries=from_entries,
                requested_usd=requested_usd,
                budget_usd=budget_usd,
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
            halted=lambda: operator_halted() or self.ledger.snapshot().buy_halted,
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

    def _process_instruction(
        self,
        message: MessageRecord,
        index: int,
        instruction: Instruction,
        controls: _ProcessControls,
    ) -> None:
        guard = _SubmissionGuard.begin(
            message.timestamp,
            buy=instruction.action == "buy",
            max_age_seconds=self.config.max_signal_age_seconds,
            controls=controls,
            market_session=self.market_session,
        )
        blocked, current = guard.check()
        if self._held_for_recovery(instruction, blocked):
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
            )
            return
        blocked, current = guard.check(decision.plan)
        if self._held_for_recovery(instruction, blocked):
            return
        if blocked is not None:
            self.ledger.skip(
                message.key, index, self._skip_reason(instruction, blocked, controls), current
            )
            return
        order = self.ledger.prepare(decision.plan, message.key, index, current)
        self._submit_prepared_order(message.key, order, guard)

    @staticmethod
    def _held_for_recovery(instruction: Instruction, blocked: str | None) -> bool:
        """A buy that only waits for the account's restart recovery stays pending."""
        return instruction.action == "buy" and blocked in RECOVERY_WAITS

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
        request = OrderRequest(
            symbol=order.symbol,
            side=order.side,
            position_intent=order.position_intent,
            qty=order.qty,
            type=order.type,
            limit_price=order.limit_price,
            client_order_id=order.client_id,
            extended_hours=self.config.extended_hours if order.type == "limit" else False,
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
