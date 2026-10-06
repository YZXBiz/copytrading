"""Confine the execution engine, broker, and synchronous store to one worker."""

import asyncio
import concurrent.futures
import datetime as dt
import logging
import threading
from collections.abc import Callable
from pathlib import Path
from typing import TypeVar, cast

from copytrading_engine.execution.adapters.alpaca.broker import (
    AlpacaBroker,
    AlpacaCredentials,
    Environment,
)
from copytrading_engine.execution.adapters.alpaca.order_stream import (
    OrderStream,
    alpaca_order_stream,
)
from copytrading_engine.execution.adapters.resources import (
    ExecutionResources,
    build_resources,
    default_account_lock_root,
)
from copytrading_engine.execution.application.ports import (
    AccountRuntimeView,
    Broker,
    ExecutionObservation,
    ExecutionObserver,
    NoOpObserver,
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
from copytrading_engine.execution.domain.market import EquityHistory, HistoryWindow
from copytrading_engine.execution.domain.ownership import (
    OwnershipInspection,
    OwnershipResolution,
    OwnershipResolutionRequest,
)
from copytrading_engine.execution.domain.recovery import (
    IncidentClearanceEvidence,
    ManualSale,
    ReleaseEvidence,
)
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.domain.sizing import DestinationSignal
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverview,
    DestinationView,
)

log = logging.getLogger(__name__)
_ResultT = TypeVar("_ResultT")


class ExecutionOwner:
    """Serialize async callers over a single worker-confined execution resource set."""

    def __init__(self) -> None:
        self._executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=1, thread_name_prefix="execution-owner"
        )
        self._gate = asyncio.Lock()
        self._stop_event = threading.Event()
        self._resource: ExecutionResources | None = None
        self._closer: Callable[[ExecutionResources], None] | None = None
        self._data_dir = Path(".")
        self._closing = False
        self._closed = False
        self._unusable = False
        self._close_task: asyncio.Task[None] | None = None
        self._order_stream: OrderStream | None = None

    @classmethod
    async def open(
        cls,
        data_dir: Path,
        credentials: AlpacaCredentials,
        config: CopyConfig,
        *,
        environment: Environment,
        broker_factory: Callable[[AlpacaCredentials, Environment], Broker] | None = None,
        account_lock_root: Path | None = None,
        observer: ExecutionObserver | None = None,
    ) -> ExecutionOwner:
        data_dir.mkdir(parents=True, exist_ok=True)
        if environment not in {"paper", "live"}:
            raise ValueError("Choose Alpaca paper or live explicitly")
        lock_root = account_lock_root or default_account_lock_root()
        if not lock_root.is_absolute():
            raise ValueError("Account lock root must be an absolute path")
        factory = broker_factory or (lambda keys, mode: AlpacaBroker(keys, mode))
        return await cls._from_resource_factory(
            lambda: build_resources(
                data_dir,
                credentials,
                config,
                environment,
                factory,
                lock_root,
                observer if observer is not None else NoOpObserver(),
            ),
            lambda resource: resource.close(),
            data_dir=data_dir,
            # Only a real Alpaca account has a live stream; test brokers never open one.
            order_stream=(
                alpaca_order_stream(credentials, environment) if broker_factory is None else None
            ),
        )

    async def watch_orders(
        self, on_update: Callable[[], None], on_live: Callable[[bool], None], stop: asyncio.Event
    ) -> None:
        """Call `on_update` whenever Alpaca reports a change to one of this account's orders, and
        `on_live` as the stream connects and drops."""
        if self._order_stream is not None:
            await self._order_stream(on_update, on_live, stop)

    @classmethod
    async def _from_resource_factory(
        cls,
        factory: Callable[[], ExecutionResources],
        closer: Callable[[ExecutionResources], None],
        *,
        data_dir: Path = Path("."),
        order_stream: OrderStream | None = None,
    ) -> ExecutionOwner:
        """Shared worker bootstrap used by production and the thread-confinement probe."""
        owner = cls()
        owner._data_dir = data_dir
        owner._order_stream = order_stream
        owner._closer = closer
        future = owner._executor.submit(factory)
        result, cancelled, failure = await owner._drain(future)
        if cancelled:
            if failure is None:
                owner._resource = result
                cleanup = owner._executor.submit(owner._close_resource)
                _, _, cleanup_failure = await owner._drain(cleanup)
                if cleanup_failure is not None:
                    log.warning("startup_cleanup_failed error=%s", type(cleanup_failure).__name__)
            owner._closed = True
            owner._executor.shutdown(wait=True)
            raise asyncio.CancelledError
        if failure is not None:
            owner._closed = True
            owner._executor.shutdown(wait=True)
            raise failure
        owner._resource = result
        return owner

    async def _drain(
        self, future: concurrent.futures.Future[_ResultT]
    ) -> tuple[_ResultT | None, bool, BaseException | None]:
        """Shield one worker call until completion, retaining caller cancellation."""
        cancelled = False
        wrapped = asyncio.wrap_future(future)
        while True:
            try:
                await asyncio.shield(wrapped)
                break
            except asyncio.CancelledError:
                cancelled = True
                if future.done():
                    break
            except BaseException:  # noqa: BLE001 - keep draining until the worker settles
                break
        try:
            return future.result(), cancelled, None
        except BaseException as exc:  # noqa: BLE001 - keep draining until the worker settles
            return None, cancelled, exc

    def _close_resource(self) -> None:
        if self._resource is not None and self._closer is not None:
            self._closer(self._resource)

    async def _submit(
        self,
        operation: Callable[[ExecutionResources], _ResultT],
    ) -> _ResultT:
        async with self._gate:
            if self._closing or self._closed or self._unusable or self._resource is None:
                raise RuntimeError("Execution owner is closed or unusable")
            future = self._executor.submit(operation, self._resource)
            result, cancelled, failure = await self._drain(future)
            if cancelled:
                if not self._resource.store.usable:
                    self._unusable = True
                if failure is not None:
                    log.warning("execution_worker_failed error=%s", type(failure).__name__)
                raise asyncio.CancelledError
            if failure is not None:
                if not self._resource.store.usable:
                    self._unusable = True
                raise failure
            return cast(_ResultT, result)

    def request_stop(self) -> None:
        """Make pre-submit stop checks visible without queueing behind broker work."""
        self._stop_event.set()

    async def receive(self, delivery: DestinationSignal, now: dt.datetime) -> None:
        await self._submit(lambda resource: resource.receive(delivery, now))

    async def record_rejection(self, payload_hash: str, reason: str, now: dt.datetime) -> None:
        await self._submit(lambda resource: resource.record_rejection(payload_hash, reason, now))

    async def cycle(self, now: dt.datetime, *, halted: bool) -> ExecutionObservation:
        return await self._submit(
            lambda resource: resource.cycle(now, halted=halted, stopping=self._stop_event)
        )

    async def observation(self) -> ExecutionObservation:
        return await self._submit(lambda resource: resource.observation())

    async def pending_notifications(self) -> tuple[tuple[int, str, str, dict[str, object]], ...]:
        return await self._submit(lambda resource: resource.pending_notifications())

    async def confirm_notification(self, notification_id: int) -> None:
        await self._submit(lambda resource: resource.confirm_notification(notification_id))

    async def release_uncertain_intent(
        self,
        client_id: str,
        *,
        actor: str,
        reason: str,
        order_history_ref: str,
        fill_history_ref: str,
        account_id: str,
    ) -> ReleaseEvidence:
        return await self._submit(
            lambda resource: resource.release_uncertain_intent(
                client_id,
                actor=actor,
                reason=reason,
                order_history_ref=order_history_ref,
                fill_history_ref=fill_history_ref,
                account_id=account_id,
            )
        )

    async def record_manual_sale(self, sale: ManualSale, *, account_id: str) -> None:
        await self._submit(
            lambda resource: resource.record_manual_sale(sale, account_id=account_id)
        )

    async def record_manual_correction(
        self, correction: ManualCorrectionRecord
    ) -> ManualCorrectionRecord:
        return await self._submit(
            lambda resource: resource.record_manual_correction(
                correction, stopping=self._stop_event.is_set
            )
        )

    async def preview_lot_sale(
        self, request: LotSalePreviewRequest, now: dt.datetime
    ) -> LotSalePreview:
        return await self._submit(
            lambda resource: resource.preview_lot_sale(
                request, now, stopping=self._stop_event.is_set
            )
        )

    async def confirm_lot_sale(
        self, request: LotSaleConfirmation, now: dt.datetime
    ) -> LotSaleResult:
        return await self._submit(
            lambda resource: resource.confirm_lot_sale(
                request, now, stopping=self._stop_event.is_set
            )
        )

    async def preview_manual_order(
        self, request: ManualPreviewRequest, now: dt.datetime
    ) -> ManualOrderPreview:
        return await self._submit(
            lambda resource: resource.preview_manual_order(
                request, now, stopping=self._stop_event.is_set
            )
        )

    async def confirm_manual_order(
        self, request: ManualConfirmationRequest, now: dt.datetime
    ) -> ManualCommandResult:
        return await self._submit(
            lambda resource: resource.confirm_manual_order(
                request, now, stopping=self._stop_event.is_set
            )
        )

    async def manual_command_result(self, command_id: str) -> ManualCommandResult:
        return await self._submit(
            lambda resource: resource.manual_command_result(
                command_id, stopping=self._stop_event.is_set
            )
        )

    async def manual_command_page(
        self,
        source_id: str,
        *,
        before_command_id: str | None = None,
        limit: int = 50,
    ) -> ManualCommandPage:
        return await self._submit(
            lambda resource: resource.manual_command_page(
                source_id,
                before_command_id=before_command_id,
                limit=limit,
                stopping=self._stop_event.is_set,
            )
        )

    async def inventory_account(self, now: dt.datetime) -> OwnershipInspection:
        return await self._submit(lambda resource: resource.inventory_account(now))

    async def inspect_ownership(self) -> OwnershipInspection:
        return await self._submit(lambda resource: resource.inspect_ownership())

    async def resolve_ownership(self, request: OwnershipResolutionRequest) -> OwnershipResolution:
        return await self._submit(lambda resource: resource.resolve_ownership(request))

    async def recover_account(self, now: dt.datetime) -> OwnershipInspection:
        return await self._submit(lambda resource: resource.recover_account(now))

    async def control_account(
        self, command: AccountControlCommand, now: dt.datetime
    ) -> AccountControlResult:
        return await self._submit(lambda resource: resource.control_account(command, now))

    async def account_status(self) -> AccountRuntimeView:
        return await self._submit(lambda resource: resource.account_status())

    async def operator_overview(self) -> AccountOverview:
        return await self._submit(lambda resource: resource.operator_overview())

    async def destination_views(self, source_ids: set[str]) -> dict[str, DestinationView]:
        return await self._submit(lambda resource: resource.destination_views(source_ids))

    async def event_page(self, before_seq: int | None, limit: int) -> AccountEventPage:
        return await self._submit(lambda resource: resource.event_page(before_seq, limit))

    async def equity_history(self, window: HistoryWindow, now: dt.datetime) -> EquityHistory:
        return await self._submit(lambda resource: resource.equity_history(window, now))

    async def clear_late_order_incident(
        self,
        client_id: str,
        *,
        actor: str,
        reason: str,
        matched_audit_ref: str,
        account_id: str,
    ) -> IncidentClearanceEvidence:
        return await self._submit(
            lambda resource: resource.clear_late_order_incident(
                client_id,
                actor=actor,
                reason=reason,
                matched_audit_ref=matched_audit_ref,
                account_id=account_id,
            )
        )

    async def _close_resources(self) -> None:
        failure: BaseException | None = None
        async with self._gate:
            if self._closed:
                return
            future = self._executor.submit(self._close_resource)
            _, cancelled, failure = await self._drain(future)
            self._closed = True
            self._unusable = True
            self._executor.shutdown(wait=True)
        if failure is not None:
            raise failure
        if cancelled:
            raise asyncio.CancelledError

    async def close(self) -> None:
        if self._close_task is None:
            if self._closed:
                return
            self._closing = True
            self.request_stop()
            self._close_task = asyncio.create_task(self._close_resources())

        cleanup = self._close_task
        cancelled = False
        while True:
            try:
                await asyncio.shield(cleanup)
                break
            except asyncio.CancelledError:
                cancelled = True
                if cleanup.done():
                    break
            except BaseException:  # noqa: BLE001 - keep draining until the worker settles
                break
        cleanup.result()
        if cancelled:
            raise asyncio.CancelledError
