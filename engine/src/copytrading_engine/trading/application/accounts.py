"""Independent account reconciliation and durable signal intake supervisors."""

import asyncio
import datetime as dt
import logging
from collections.abc import Callable
from contextlib import AbstractContextManager, nullcontext
from typing import Protocol, runtime_checkable

from copytrading_engine.execution.application.ports import AccountRuntimeView, ExecutionObservation
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
from copytrading_engine.execution.domain.market import EquityHistory, HistoryWindow
from copytrading_engine.execution.domain.ownership import (
    OwnershipInspection,
    OwnershipResolution,
    OwnershipResolutionRequest,
)
from copytrading_engine.execution.domain.sizing import DestinationSignal, DestinationTerms
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverview,
    DestinationView,
)
from copytrading_engine.parsing.contracts import (
    DestinationIdentity,
    DestinationRegistration,
    PendingSignal,
)
from copytrading_engine.shared.correlation import WorkflowAttempt, bind_workflow_attempt
from copytrading_engine.shared.route_keys import choose_route
from copytrading_engine.shared.signals import StockSignal
from copytrading_engine.trading.domain.status import AccountRunState, AccountStatus

log = logging.getLogger(__name__)


class AccountUnavailable(Exception):
    """The account has stopped accepting work; its delivery must remain pending."""


class AccountOwner(Protocol):
    async def receive(self, delivery: DestinationSignal, now: dt.datetime) -> None: ...

    async def cycle(self, now: dt.datetime, *, halted: bool) -> ExecutionObservation: ...

    async def recover_account(self, now: dt.datetime) -> OwnershipInspection: ...

    async def control_account(
        self, command: AccountControlCommand, now: dt.datetime
    ) -> AccountControlResult: ...

    async def resolve_ownership(
        self, request: OwnershipResolutionRequest
    ) -> OwnershipResolution: ...

    async def record_manual_correction(
        self, correction: ManualCorrectionRecord
    ) -> ManualCorrectionRecord: ...

    async def preview_lot_sale(
        self, request: LotSalePreviewRequest, now: dt.datetime
    ) -> LotSalePreview: ...

    async def confirm_lot_sale(
        self, request: LotSaleConfirmation, now: dt.datetime
    ) -> LotSaleResult: ...

    async def preview_manual_order(
        self, request: ManualPreviewRequest, now: dt.datetime
    ) -> ManualOrderPreview: ...

    async def confirm_manual_order(
        self, request: ManualConfirmationRequest, now: dt.datetime
    ) -> ManualCommandResult: ...

    async def manual_command_result(self, command_id: str) -> ManualCommandResult: ...

    async def manual_command_page(
        self, source_id: str, *, before_command_id: str | None = None, limit: int = 50
    ) -> ManualCommandPage: ...

    async def observation(self) -> ExecutionObservation: ...

    async def account_status(self) -> AccountRuntimeView: ...

    async def operator_overview(self) -> AccountOverview: ...

    async def destination_views(self, source_ids: set[str]) -> dict[str, DestinationView]: ...

    async def event_page(self, before_seq: int | None, limit: int) -> AccountEventPage: ...

    async def equity_history(self, window: HistoryWindow, now: dt.datetime) -> EquityHistory: ...

    async def pending_notifications(
        self,
    ) -> tuple[tuple[int, str, str, dict[str, object]], ...]: ...

    async def confirm_notification(self, notification_id: int) -> None: ...

    def request_stop(self) -> None: ...

    async def close(self) -> None: ...


@runtime_checkable
class WatchesOrders(Protocol):
    """An owner that can say the moment one of its broker orders changes."""

    async def watch_orders(
        self, on_update: Callable[[], None], on_live: Callable[[bool], None], stop: asyncio.Event
    ) -> None: ...


# While the order stream is live and nothing waits on a clock, fills arrive the moment they
# happen, so the periodic check is only a safety net for balances and reconciliation; it stays
# well inside Alpaca's per-account request limits with many accounts.
STREAM_SAFETY_SECONDS = 30.0


class AccountSupervisor:
    def __init__(
        self,
        account_id: str,
        owner: AccountOwner | None,
        poll_seconds: float,
        stop: asyncio.Event,
        on_change: Callable[[], None],
    ) -> None:
        self.id = account_id
        self.owner = owner
        self.poll_seconds = poll_seconds
        self.stop = stop
        self.on_change = on_change
        self.state: AccountRunState = "ready" if owner is not None else "failed"
        self.error_code: str | None = None if owner is not None else "account_unavailable"
        self._account_status = AccountStatus(self.id, self.state, self.error_code)
        self._task: asyncio.Task[None] | None = None
        # Set by an order update or a newly received call: the next cycle starts at once.
        self._wake = asyncio.Event()
        self._order_watch: asyncio.Task[None] | None = None
        self._stream_live = False
        self._outstanding_work = True

    @property
    def status(self) -> AccountStatus:
        return self._account_status

    async def refresh(self) -> None:
        if self.owner is None:
            return
        current = await self.owner.account_status()
        self._account_status = AccountStatus(
            self.id,
            self.state,
            self.error_code,
            current.entry_permission,
            current.recovery_preference,
            current.readiness,
            current.account_risk_status,
            current.account_risk_reason,
            current.account_activity_status,
            current.account_activity_reason,
        )
        self.on_change()

    def start(self) -> None:
        if self.owner is None:
            return
        self.state = "running"
        self._account_status = AccountStatus(
            self.id,
            self.state,
            self.error_code,
            self._account_status.entry_permission,
            self._account_status.recovery_preference,
            self._account_status.readiness,
            self._account_status.account_risk_status,
            self._account_status.account_risk_reason,
            self._account_status.account_activity_status,
            self._account_status.account_activity_reason,
        )
        self._task = asyncio.create_task(self._reconcile())
        if isinstance(self.owner, WatchesOrders):
            self._order_watch = asyncio.create_task(
                self.owner.watch_orders(self._wake.set, self._stream_changed, self.stop)
            )
        self.on_change()

    async def receive(self, delivery: DestinationSignal, now: dt.datetime) -> None:
        if delivery.terms.connection.account_id != self.id:
            raise ValueError("Destination account identity mismatch")
        if self.stop.is_set():
            raise AccountUnavailable
        if self.state != "running" or self.owner is None:
            raise AccountUnavailable
        try:
            await self.owner.receive(delivery, now)
        except Exception as exc:  # noqa: BLE001 - the supervisor records the account failure
            self._fail(exc)
            raise AccountUnavailable from None
        # A new call is acted on now, not at the next periodic check.
        self._wake.set()

    async def _reconcile(self) -> None:
        assert self.owner is not None
        while not self.stop.is_set() and self.state == "running":
            # Cleared before the cycle: a wake during it starts the next cycle at once.
            self._wake.clear()
            try:
                observation = await self.owner.cycle(dt.datetime.now(dt.UTC), halted=False)
                self._outstanding_work = observation.ledger.has_outstanding_work
                await self.refresh()
            except Exception as exc:  # noqa: BLE001 - the supervisor records the account failure
                self._fail(exc)
                return
            await self._idle()

    @property
    def check_seconds(self) -> float:
        """How long until the next periodic check: a slow safety net while the order stream is
        live and nothing waits on a clock, otherwise the account's own short interval."""
        if self._stream_live and not self._outstanding_work:
            return max(self.poll_seconds, STREAM_SAFETY_SECONDS)
        return self.poll_seconds

    def _stream_changed(self, live: bool) -> None:
        self._stream_live = live
        if not live:
            # Updates may have been missed while it was down: reconcile now, then check often.
            self._wake.set()

    async def _idle(self) -> None:
        """Wait for the periodic check, ended early by an order update, a new call, or Stop."""
        waits = {
            asyncio.ensure_future(self.stop.wait()),
            asyncio.ensure_future(self._wake.wait()),
        }
        try:
            await asyncio.wait(
                waits, timeout=self.check_seconds, return_when=asyncio.FIRST_COMPLETED
            )
        finally:
            for wait in waits:
                wait.cancel()

    def _fail(self, exc: Exception) -> None:
        if self.state == "failed":
            return
        if self._order_watch is not None:
            self._order_watch.cancel()
        self.state = "failed"
        self.error_code = "account_unavailable"
        self._account_status = AccountStatus(self.id, self.state, self.error_code)
        if self.owner is not None:
            self.owner.request_stop()
        log.error("trading_account_failed id=%s type=%s", self.id, type(exc).__name__)
        self.on_change()

    async def close(self) -> None:
        if self.owner is not None:
            self.owner.request_stop()
        if self._task is not None:
            await self._task
        if self.owner is not None:
            await self.owner.close()


class SignalInbox(Protocol):
    async def claim_pending_signals(
        self, limit: int = 100, after_seq: int = 0
    ) -> tuple[PendingSignal, ...]: ...

    async def confirm_signal(self, key: str) -> None: ...

    async def prepare_destinations(
        self,
        key: str,
        registrations: tuple[DestinationRegistration, ...],
    ) -> tuple[DestinationIdentity, ...]: ...

    async def reserve_destination_attempt(
        self, key: str, account_id: str
    ) -> DestinationIdentity: ...


class SignalFanout:
    """Confirm parser delivery only after every configured account commits receipt."""

    def __init__(
        self,
        parser: SignalInbox,
        routes: dict[str, tuple[DestinationTerms, ...]],
        accounts: dict[str, AccountSupervisor],
        stop: asyncio.Event,
        *,
        observe_workflow: Callable[[WorkflowAttempt], AbstractContextManager] = lambda _: (
            nullcontext()
        ),
        observe_destination: Callable[
            [str, WorkflowAttempt], AbstractContextManager
        ] = lambda _message, _attempt: nullcontext(),
    ) -> None:
        self.parser = parser
        self.routes = routes
        self.accounts = accounts
        self.stop = stop
        self.observe_workflow = observe_workflow
        self.observe_destination = observe_destination
        self._cursor = 0

    async def _receive(
        self,
        key: str,
        signal: StockSignal,
        terms: DestinationTerms,
        identity: DestinationIdentity,
    ) -> None:
        attempt = WorkflowAttempt(
            identity.workflow_id, identity.trace_id, identity.destination_id, identity.attempt
        )
        with bind_workflow_attempt(attempt), self.observe_destination(key, attempt):
            await self.accounts[terms.connection.account_id].receive(
                DestinationSignal(signal=signal, terms=terms), dt.datetime.now(dt.UTC)
            )

    async def deliver(self) -> int:
        confirmed = 0
        for _ in range(2):
            deliveries = await self.parser.claim_pending_signals(after_seq=self._cursor)
            if not deliveries:
                self._cursor = 0
                break
            for delivery in deliveries:
                if self.stop.is_set():
                    return confirmed
                self._cursor = delivery.seq
                waiting = False
                route = (
                    choose_route(
                        self.routes,
                        delivery.signal.source,
                        delivery.signal.channel_id,
                        delivery.signal.author_id,
                    ).route
                    or ()
                )
                registrations = tuple(
                    DestinationRegistration(
                        terms.connection.account_id, terms.configuration_revision
                    )
                    for terms in route
                )
                destinations = await self.parser.prepare_destinations(delivery.key, registrations)
                if destinations:
                    first = destinations[0]
                    workflow = WorkflowAttempt(first.workflow_id, first.trace_id, None, 0)
                    with bind_workflow_attempt(workflow):
                        with self.observe_workflow(workflow):
                            reserved = []
                            for terms in route:
                                if self.stop.is_set():
                                    return confirmed
                                identity = await self.parser.reserve_destination_attempt(
                                    delivery.key, terms.connection.account_id
                                )
                                reserved.append((terms, identity))
                            # Each account serializes its own work, so different accounts take
                            # the same post side by side. Every account runs to the end, even if
                            # another fails: cancelling one mid-order could orphan a submission.
                            # The work is built only here, so a stop above never strands a
                            # coroutine that nothing will await.
                            outcomes = await asyncio.gather(
                                *(
                                    self._receive(delivery.key, delivery.signal, terms, identity)
                                    for terms, identity in reserved
                                ),
                                return_exceptions=True,
                            )
                            for outcome in outcomes:
                                if isinstance(outcome, AccountUnavailable):
                                    waiting = True
                                elif isinstance(outcome, BaseException):
                                    raise outcome
                if not waiting:
                    await self.parser.confirm_signal(delivery.key)
                    confirmed += 1
            if len(deliveries) < 100:
                self._cursor = 0
                break
        return confirmed
