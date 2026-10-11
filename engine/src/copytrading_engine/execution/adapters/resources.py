"""The engine, broker, store, and locks of one account, used only on its owner's worker thread."""

import datetime as dt
import fcntl
import hashlib
import logging
import os
import pwd
import threading
from collections.abc import Callable
from contextlib import ExitStack
from copy import deepcopy
from dataclasses import dataclass, field
from pathlib import Path

from copytrading_engine.execution.adapters.alpaca.broker import (
    AlpacaCredentials,
    Environment,
)
from copytrading_engine.execution.adapters.sqlite_ledger import Store
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.lot_sales import LotSaleApplication
from copytrading_engine.execution.application.manual_commands import ManualTradingApplication
from copytrading_engine.execution.application.ports import (
    AccountOpenRefused,
    AccountRuntimeView,
    Broker,
    BrokerError,
    EquityHistoryBroker,
    ExecutionObservation,
    ExecutionObserver,
)
from copytrading_engine.execution.application.recovery import RecoveryApplication
from copytrading_engine.execution.domain.events import (
    JournalEvent,
    LimitChange,
    LimitsChanged,
    SignalRejected,
)
from copytrading_engine.execution.domain.lifecycle import (
    AccountControlCommand,
    AccountControlResult,
)
from copytrading_engine.execution.domain.lot_sales import (
    LotSaleConfirmation,
    LotSalePreview,
    LotSalePreviewRequest,
    LotSaleResult,
)
from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandPage,
    ManualCommandResult,
    ManualConfirmationRequest,
    ManualCorrectionRecord,
    ManualOrderPreview,
    ManualPreviewRequest,
)
from copytrading_engine.execution.domain.market import Account, EquityHistory, HistoryWindow
from copytrading_engine.execution.domain.ownership import (
    OwnershipInspection,
    OwnershipResolution,
    OwnershipResolutionRequest,
)
from copytrading_engine.execution.domain.positions import PositionAudit
from copytrading_engine.execution.domain.recovery import (
    IncidentClearanceEvidence,
    ManualSale,
    ReleaseEvidence,
)
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.domain.sizing import DestinationSignal
from copytrading_engine.execution.domain.values import BrokerAccountNumber
from copytrading_engine.execution.presentation.account_feed import AccountFeedPage, account_feed
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverview,
    DestinationView,
    account_balance,
    account_overview,
    destination_views,
    event_page,
)
from copytrading_engine.shared.owner_facing import OwnerFacingError

# A ledger not yet bound to a broker account matches no broker account, so manual orders and
# lot sales refuse until the account has connected.
_UNBOUND_LEDGER = BrokerAccountNumber("unbound")

log = logging.getLogger(__name__)


_identity_guard = threading.Lock()


_active_identities: set[tuple[Environment, str]] = set()


_EQUITY_HISTORY_REUSE = dt.timedelta(seconds=60)


def default_account_lock_root() -> Path:
    """Stable per-user host lock directory, independent of an installation's state root.

    This file lock coordinates processes of the same OS user on one host. It is
    not a distributed lease across users or machines.
    """
    # HOME may be overridden independently in two processes owned by this user.
    user_home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    return user_home / ".copytrading" / "account-locks"


def _reserve_identity(environment: Environment, account_id: str) -> Callable[[], None]:
    identity = (environment, account_id)
    with _identity_guard:
        if identity in _active_identities:
            raise AccountOpenRefused("account_in_use")
        _active_identities.add(identity)

    def release() -> None:
        with _identity_guard:
            _active_identities.remove(identity)

    return release


# Entries the owner turned off or paused skip a buy at once. A restart's recovery only holds it:
# each cycle tries again, and the signal-age check decides when a post is too old.
_DELIBERATE_BLOCKS = frozenset({"account_paused", "account_disabled"})


@dataclass
class ExecutionResources:
    stack: ExitStack
    store: Store
    broker: Broker
    engine: CopyEngine
    account: Account
    data_dir: Path
    account_observed_at: dt.datetime
    position_audit: PositionAudit | None = None
    _recovery_ready: bool = False
    last_inspection: OwnershipInspection | None = None
    _equity_histories: dict[HistoryWindow, tuple[dt.datetime, EquityHistory]] = field(
        default_factory=dict
    )

    @property
    def runtime_entries_ready(self) -> bool:
        """Derive buy readiness from current-session recovery and durable permission."""
        control = self.engine.ledger.snapshot().control
        return self._recovery_ready and control.entry_permission == "enabled"

    def account_status(self) -> AccountRuntimeView:
        control = self.engine.ledger.snapshot().control
        inspection = self.last_inspection
        if control.entry_permission == "paused":
            readiness = "paused"
        elif control.entry_permission == "disabled":
            readiness = "disabled"
        elif not self.runtime_entries_ready:
            readiness = (
                "manual_resume_required"
                if control.recovery_preference == "manual"
                else "recovery_pending"
            )
        elif inspection is None or not self._inspection_ready(inspection):
            readiness = "reconciliation_unavailable"
        else:
            try:
                readiness = (
                    "enabled_waiting_for_session"
                    if self.engine.market_session(dt.datetime.now(dt.UTC)).value == "closed"
                    else "enabled"
                )
            except Exception:  # noqa: BLE001 - readiness degrades instead of failing status
                readiness = "session_unavailable"
        return AccountRuntimeView(
            entry_permission=control.entry_permission,
            recovery_preference=control.recovery_preference,
            readiness=readiness,
            account_risk_status=inspection.account_risk_status if inspection else "unavailable",
            account_risk_reason=inspection.account_risk_reason if inspection else "not_checked",
            account_activity_status=inspection.account_activity_status
            if inspection
            else "unavailable",
            account_activity_reason=inspection.account_activity_reason
            if inspection
            else "not_checked",
        )

    def operator_overview(self) -> AccountOverview:
        return account_overview(
            self.engine.ledger.snapshot(),
            self.last_inspection,
            local_account_id=self.data_dir.name,
            active_configuration=True,
            readiness=self.account_status().readiness,
            balance=account_balance(self.account, self.account_observed_at),
        )

    def destination_views(self, source_ids: set[str]) -> dict[str, DestinationView]:
        return destination_views(
            self.engine.ledger.snapshot(), source_ids, self.store.message_events(source_ids)
        )

    def equity_history(self, window: HistoryWindow, now: dt.datetime) -> EquityHistory:
        """The broker's curve, fetched at most once a minute so charts never crowd out trading."""
        if not isinstance(self.broker, EquityHistoryBroker):
            raise RuntimeError("This broker does not report equity history")
        cached = self._equity_histories.get(window)
        if cached is not None and now - cached[0] < _EQUITY_HISTORY_REUSE:
            return cached[1]
        history = self.broker.equity_history(window)
        self._equity_histories[window] = (now, history)
        return history

    def event_page(self, before_seq: int | None, limit: int) -> AccountEventPage:
        return event_page(self.data_dir.name, self.store.event_page(before_seq, limit), limit)

    def feed_page(self, before_seq: int | None, limit: int) -> AccountFeedPage:
        return account_feed(
            self.data_dir.name,
            self.engine.ledger.snapshot(),
            self.store.feed_events(before_seq, limit),
            limit,
        )

    def entry_block_reason(self) -> str | None:
        control = self.engine.ledger.snapshot().control
        if control.entry_permission == "paused":
            return "account_paused"
        if control.entry_permission == "disabled":
            return "account_disabled"
        if not self.runtime_entries_ready:
            # Manual recovery waits for the owner's Resume; automatic waits for the checks.
            return (
                "manual_resume_required"
                if control.recovery_preference == "manual"
                else "recovery_pending"
            )
        return None

    def recover_account(self, now: dt.datetime) -> OwnershipInspection:
        self.engine.reconcile(now)
        inspection = self.inspect_ownership()
        self.last_inspection = inspection
        self.account = self.broker.account()
        self.account_observed_at = now
        control = self.engine.ledger.snapshot().control
        self._recovery_ready = (
            control.entry_permission in {"enabled", "paused"}
            and control.recovery_preference == "automatic"
            and self._inspection_ready(inspection)
        )
        # A deliberate pause or entries left off skip queued buys; recovery only holds them, and
        # each cycle's signal-age check decides when one is too old.
        reason = self.entry_block_reason()
        if reason in _DELIBERATE_BLOCKS:
            self.engine.ledger.skip_unpermitted_buys(now, reason)
        return inspection

    def _inspection_ready(self, inspection: OwnershipInspection) -> bool:
        return (
            inspection.account_id == self.account.id
            and self.account.active
            and inspection.account_risk_status == "ready"
            and inspection.account_activity_status == "ready"
            and not self.engine.ledger.snapshot().buy_halted
        )

    def _resume_refusal(self, inspection: OwnershipInspection) -> str:
        """Why new buys can't resume yet, as a code the app words in the owner's language."""
        if inspection.account_activity_reason == "unresolved_account_order":
            return "resume_blocked_outside_order"
        if not self.account.active:
            return "resume_blocked_account_inactive"
        if self.engine.ledger.snapshot().buy_halted:
            return "resume_blocked_order_unclear"
        return "resume_blocked_unreadable"

    def control_account(
        self, command: AccountControlCommand, now: dt.datetime
    ) -> AccountControlResult:
        previous = self.engine.ledger.snapshot().control.commands.get(command.command_id)
        if previous is not None:
            return self.engine.ledger.account_control(
                command, now, local_account_id=self.data_dir.name
            )
        if command.action == "resume":
            self.engine.reconcile(now)
            inspection = self.inspect_ownership()
            self.last_inspection = inspection
            self.account = self.broker.account()
            self.account_observed_at = now
            if not self._inspection_ready(inspection):
                raise OwnerFacingError(self._resume_refusal(inspection))
        result = self.engine.ledger.account_control(
            command, now, local_account_id=self.data_dir.name
        )
        if command.action == "pause":
            self.engine.ledger.skip_unpermitted_buys(now, "account_paused")
        elif command.action == "resume":
            self._recovery_ready = True
        return result

    def update_config(self, config: CopyConfig, now: dt.datetime) -> tuple[LimitChange, ...]:
        """Copy with new limits from the next cycle on, and journal what changed."""
        before, after = _flat_limits(self.engine.config), _flat_limits(config)
        changes = tuple(
            LimitChange(setting=name, before=_text(before[name]), after=_text(value))
            for name, value in after.items()
            if before[name] != value
        )
        if config.sources != self.engine.config.sources:
            raise ValueError("A limits update cannot change the account's sources")
        if not changes:
            return ()
        self.engine.ledger.record(JournalEvent(at=now, payload=LimitsChanged(changes=changes)))
        self.engine.config = config
        return changes

    def observation(self) -> ExecutionObservation:
        return ExecutionObservation(
            account=deepcopy(self.account),
            ledger=deepcopy(self.engine.ledger.snapshot()),
            total_cost_exposure_usd=self.engine.ledger.exposure(),
            position_audit=deepcopy(self.position_audit),
        )

    def cycle(
        self,
        now: dt.datetime,
        *,
        halted: bool,
        stopping: threading.Event,
    ) -> ExecutionObservation:
        self.engine.reconcile(now)
        self.engine.process(
            now,
            halted=halted,
            now_clock=lambda: dt.datetime.now(dt.UTC),
            halted_now=lambda: (self.data_dir / "HALT").exists(),
            entry_block_reason=self.entry_block_reason,
            stopping=stopping.is_set,
        )
        # Orders this cycle placed can fill before it ends: book those fills before the broker is
        # read, so a buy shows as copied and a sale as gone in the same cycle, never as shares at
        # the broker nobody copied or shares sold that still count. With nothing pending this
        # costs no broker call.
        self.engine.reconcile(now)
        self.position_audit = self.engine.audit_positions()
        self.account = self.broker.account()
        self.account_observed_at = now
        self.last_inspection = self.inspect_ownership()
        return self.observation()

    def receive(self, delivery: DestinationSignal, now: dt.datetime) -> None:
        self.engine.receive(delivery, now)
        if (reason := self.entry_block_reason()) in _DELIBERATE_BLOCKS:
            self.engine.ledger.skip_unpermitted_buys(now, reason)

    def record_rejection(self, payload_hash: str, reason: str, now: dt.datetime) -> None:
        self.engine.ledger.record(
            JournalEvent(
                at=now,
                payload=SignalRejected(payload_hash=payload_hash, reason=reason),
            )
        )

    def pending_notifications(self) -> tuple[tuple[int, str, str, dict[str, object]], ...]:
        return deepcopy(self.store.pending_notifications())

    def confirm_notification(self, notification_id: int) -> None:
        self.store.confirm_notification(notification_id)

    def release_uncertain_intent(
        self,
        client_id: str,
        *,
        actor: str,
        reason: str,
        order_history_ref: str,
        fill_history_ref: str,
        account_id: str,
    ) -> ReleaseEvidence:
        return RecoveryApplication(self.engine.ledger, self.broker).release_uncertain_intent(
            client_id,
            actor=actor,
            reason=reason,
            order_history_ref=order_history_ref,
            fill_history_ref=fill_history_ref,
            account_id=account_id,
        )

    def record_manual_sale(self, sale: ManualSale, *, account_id: str) -> None:
        RecoveryApplication(self.engine.ledger, self.broker).record_manual_sale(
            sale, account_id=account_id
        )

    def _owner_orders_ready(self) -> bool:
        """Owner-placed orders need finished recovery, a ready inspection, and an account that
        is not disabled."""
        inspection_ready = self.last_inspection is not None and self._inspection_ready(
            self.last_inspection
        )
        return (
            self._recovery_ready
            and inspection_ready
            and self.engine.ledger.snapshot().control.entry_permission in {"enabled", "paused"}
        )

    def _manual_application(self, stopping: Callable[[], bool]) -> ManualTradingApplication:
        snapshot = self.engine.ledger.snapshot()
        manual_orders_ready = self._owner_orders_ready()
        return ManualTradingApplication(
            self.engine,
            local_account_id=self.data_dir.name,
            broker_account_id=snapshot.account_id or _UNBOUND_LEDGER,
            environment=snapshot.environment or "paper",
            halted=lambda: (
                (self.data_dir / "HALT").exists() or self.engine.ledger.snapshot().buy_halted
            ),
            entry_block_reason=self.entry_block_reason,
            recovery_ready=lambda: manual_orders_ready,
            stopping=stopping,
        )

    def _lot_sale_application(self, stopping: Callable[[], bool]) -> LotSaleApplication:
        snapshot = self.engine.ledger.snapshot()
        orders_ready = self._owner_orders_ready()
        return LotSaleApplication(
            self.engine,
            local_account_id=self.data_dir.name,
            broker_account_id=snapshot.account_id or _UNBOUND_LEDGER,
            environment=snapshot.environment or "paper",
            halted=lambda: (
                (self.data_dir / "HALT").exists() or self.engine.ledger.snapshot().buy_halted
            ),
            entry_block_reason=self.entry_block_reason,
            recovery_ready=lambda: orders_ready,
            stopping=stopping,
        )

    def preview_lot_sale(
        self, request: LotSalePreviewRequest, now: dt.datetime, *, stopping: Callable[[], bool]
    ) -> LotSalePreview:
        return self._lot_sale_application(stopping).preview(request, now)

    def confirm_lot_sale(
        self, request: LotSaleConfirmation, now: dt.datetime, *, stopping: Callable[[], bool]
    ) -> LotSaleResult:
        return self._lot_sale_application(stopping).confirm(request, now)

    def record_manual_correction(
        self, correction: ManualCorrectionRecord, *, stopping: Callable[[], bool]
    ) -> ManualCorrectionRecord:
        return self._manual_application(stopping).record_correction(correction)

    def preview_manual_order(
        self, request: ManualPreviewRequest, now: dt.datetime, *, stopping: Callable[[], bool]
    ) -> ManualOrderPreview:
        return self._manual_application(stopping).preview(request, now)

    def confirm_manual_order(
        self,
        request: ManualConfirmationRequest,
        now: dt.datetime,
        *,
        stopping: Callable[[], bool],
    ) -> ManualCommandResult:
        return self._manual_application(stopping).confirm(request, now)

    def manual_command_result(
        self, command_id: str, *, stopping: Callable[[], bool]
    ) -> ManualCommandResult:
        return self._manual_application(stopping).result(command_id)

    def manual_command_page(
        self,
        source_id: str,
        *,
        before_command_id: str | None,
        limit: int,
        stopping: Callable[[], bool],
    ) -> ManualCommandPage:
        return self._manual_application(stopping).command_page(
            source_id, before_command_id=before_command_id, limit=limit
        )

    def inventory_account(self, now: dt.datetime) -> OwnershipInspection:
        self.account = self.engine.bind(
            now, environment=self.engine.ledger.snapshot().environment or "paper"
        )
        self.account_observed_at = now
        return RecoveryApplication(self.engine.ledger, self.broker).inspect_ownership()

    def inspect_ownership(self) -> OwnershipInspection:
        return RecoveryApplication(self.engine.ledger, self.broker).inspect_ownership()

    def resolve_ownership(self, request: OwnershipResolutionRequest) -> OwnershipResolution:
        result = RecoveryApplication(self.engine.ledger, self.broker).resolve_ownership(request)
        self.last_inspection = self.inspect_ownership()
        return result

    def clear_late_order_incident(
        self,
        client_id: str,
        *,
        actor: str,
        reason: str,
        matched_audit_ref: str,
        account_id: str,
    ) -> IncidentClearanceEvidence:
        return RecoveryApplication(self.engine.ledger, self.broker).clear_late_order_incident(
            client_id,
            actor=actor,
            reason=reason,
            matched_audit_ref=matched_audit_ref,
            account_id=account_id,
        )

    def close(self) -> None:
        try:
            if not self.store.usable:
                return
            now = dt.datetime.now(dt.UTC)
            for order in self.engine.pending():
                try:
                    self.engine.cancel(order, now, "copying_stopped")
                except BrokerError as exc:
                    log.warning("shutdown_cancel_unconfirmed error=%s", type(exc).__name__)
            try:
                self.engine.reconcile(dt.datetime.now(dt.UTC))
            except BrokerError as exc:
                log.warning("shutdown_reconcile_unavailable error=%s", type(exc).__name__)
        finally:
            self.stack.close()


def build_resources(
    data_dir: Path,
    credentials: AlpacaCredentials,
    config: CopyConfig,
    environment: Environment,
    broker_factory: Callable[[AlpacaCredentials, Environment], Broker],
    account_lock_root: Path,
    observer: ExecutionObserver,
) -> ExecutionResources:
    """Acquire the entire synchronous core on the owner thread with rollback cleanup."""
    stack = ExitStack()
    try:
        ownership = stack.enter_context((data_dir / "executor.lock").open("w"))
        try:
            fcntl.flock(ownership.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise RuntimeError("Another executor owns this state directory") from None
        broker = broker_factory(credentials, environment)
        close_broker = getattr(broker, "close", None)
        if close_broker is not None:
            stack.callback(close_broker)
        account = broker.account()
        stack.callback(_reserve_identity(environment, account.id))
        account_key = hashlib.sha256(f"{environment}:{account.id}".encode()).hexdigest()
        account_lock_root.mkdir(parents=True, exist_ok=True, mode=0o700)
        identity_lock = stack.enter_context(
            (account_lock_root / f".execution-account-{account_key}.lock").open("w")
        )
        try:
            fcntl.flock(identity_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise AccountOpenRefused("account_in_use") from None
        store = Store(data_dir / "execution.sqlite3")
        stack.callback(store.close)
        store.bind_identity(account.id, environment)
        engine = CopyEngine(store, broker, config, observer=observer)
        engine.bind(dt.datetime.now(dt.UTC), account=account, environment=environment)
        return ExecutionResources(
            stack.pop_all(), store, broker, engine, account, data_dir, dt.datetime.now(dt.UTC)
        )
    except BaseException:
        stack.close()
        raise


def _flat_limits(config: CopyConfig) -> dict[str, object]:
    """Every limit by its account policy name, the entry pricing ones included."""
    return (
        config.model_dump(exclude={"sources", "entry_pricing"}) | config.entry_pricing.model_dump()
    )


def _text(value: object) -> str:
    return str(value).lower() if isinstance(value, bool) else str(value)
