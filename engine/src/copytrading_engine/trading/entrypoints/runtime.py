"""Explicit trading lifecycle and replay-safe local pipeline composition."""

import asyncio
import datetime as dt
import logging
import os
from collections.abc import AsyncIterator, Collection, Mapping
from contextlib import asynccontextmanager, nullcontext
from dataclasses import replace
from functools import partial
from pathlib import Path
from uuid import uuid4

from copytrading_engine.backup.restore.gate import restore_manual_disabled
from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials
from copytrading_engine.execution.domain.pricing import EntryPricingPolicy
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.domain.sizing import DestinationTerms
from copytrading_engine.parsing.providers.registry import ManagedDecoder
from copytrading_engine.parsing.readiness import probe_model
from copytrading_engine.parsing.relay import deliver_notifications
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.parsing.worker import ParseWorker
from copytrading_engine.shared.notification_models import NotificationPayload
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.route_keys import route_key
from copytrading_engine.sources.application import Delivery, ForwardBatch
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.adapters.activation import (
    TradingActivationJournal,
    TradingActivationStatus,
)
from copytrading_engine.trading.adapters.capabilities import (
    CapabilityCheck,
    TradingCapabilityReport,
    TradingCapabilityService,
)
from copytrading_engine.trading.adapters.channel_history import DiscordChannelHistory
from copytrading_engine.trading.adapters.operator_queries import SQLiteOperatorEvidence
from copytrading_engine.trading.adapters.routing import (
    AccountOwnershipPending,
    RoutingChangePending,
    RoutingRevision,
)
from copytrading_engine.trading.adapters.telemetry import TradingTelemetry
from copytrading_engine.trading.application.account_access import AccountAccess
from copytrading_engine.trading.application.accounts import (
    AccountOwner,
    AccountSupervisor,
    SignalFanout,
)
from copytrading_engine.trading.application.manual_intervention import ManualInterventionService
from copytrading_engine.trading.application.operator_service import OperatorQueryService
from copytrading_engine.trading.application.profile_review import ProfileReviewService
from copytrading_engine.trading.domain.config import (
    ConnectionCheck,
    TradingConfiguration,
    TradingSecrets,
)
from copytrading_engine.trading.domain.status import AccountStatus, TradingStatus
from copytrading_engine.trading.entrypoints.factories import (
    NotificationSender,
    SourceSession,
    TradingFactories,
    create_decoder,
    open_owner,
)

log = logging.getLogger(__name__)


class _ParserPublisher:
    def __init__(self, parser: SQLiteExtractionStore, stop: asyncio.Event) -> None:
        self._parser = parser
        self._stop = stop

    async def publish(self, delivery: Delivery) -> None:
        if self._stop.is_set():
            raise _PausedBeforeReceipt
        if delivery.mode != "live":
            raise RuntimeError("Historical capture reached the live parser")
        event = RawMessage.model_validate_json(delivery.payload)
        if event.identity != delivery.key:
            raise ValueError("Source delivery identity changed")
        await self._parser.add(event)


class _PausedBeforeReceipt(Exception):
    """Leave the durable delivery pending when Pause interrupts fanout."""


class TradingRuntime:
    """Own real network resources only between explicit Start and Pause commands."""

    def __init__(
        self,
        data_dir: Path,
        *,
        factories: TradingFactories | None = None,
        telemetry: TradingTelemetry | None = None,
        owner_open_timeout_seconds: float = 10,
        capability_service: TradingCapabilityService | None = None,
        restore_gate_path: Path | None = None,
    ) -> None:
        self._data_dir = data_dir
        self._restore_gate_path = restore_gate_path or data_dir / ".restore-manual-disabled"
        self._activation_journal = TradingActivationJournal(data_dir / "trading-activation.json")
        self._activation_id: str | None = None
        self._telemetry = telemetry
        if owner_open_timeout_seconds <= 0:
            raise ValueError("Owner open timeout must be positive")
        self._owner_open_timeout_seconds = owner_open_timeout_seconds
        self._capability_service = capability_service or TradingCapabilityService()
        self._factories = factories or TradingFactories(
            owner=partial(open_owner, telemetry=telemetry),
            decoder=partial(
                create_decoder,
                diagnostics=telemetry.diagnostic_sink if telemetry is not None else None,
            ),
        )
        self._status = TradingStatus()
        self._configuration: TradingConfiguration | None = None
        self._stop = asyncio.Event()
        self._source_stop = asyncio.Event()
        self._work_arrived = asyncio.Event()
        self._source_failed = False
        self._task: asyncio.Task[None] | None = None
        self._accounts: dict[str, AccountSupervisor] = {}
        self._late_owner_opens: set[asyncio.Future[AccountOwner]] = set()
        self._late_owner_closes: set[asyncio.Task[None]] = set()
        self._failure_code: str | None = None
        evidence = SQLiteOperatorEvidence()
        access = AccountAccess(
            data_dir,
            lambda: self._accounts,
            configuration=lambda: self._configuration,
            runtime_state=lambda: self._status.state,
            evidence=evidence,
        )
        self.operator = OperatorQueryService(access)
        self.manual = ManualInterventionService(access)
        self.profiles = ProfileReviewService(
            data_dir,
            self._factories.decoder,
            self._register_secrets,
            evidence,
            DiscordChannelHistory(),
        )
        self._maintenance_lock = asyncio.Lock()
        self._maintenance_active = False

    def status(self) -> TradingStatus:
        return self._status

    def _register_secrets(self, values: Collection[str]) -> None:
        if self._telemetry is not None:
            self._telemetry.register_secrets(values)

    def register_restore_secrets(self, values: tuple[str, ...]) -> None:
        """Protect one restore preflight's credentials before broker I/O begins."""
        self._register_secrets(values)

    def _register_trading_secrets(self, secrets: TradingSecrets) -> None:
        values = [
            secrets.discord_token.get_secret_value(),
            secrets.provider_api_key.get_secret_value(),
        ]
        for broker in secrets.brokers:
            values.extend((broker.key.get_secret_value(), broker.secret.get_secret_value()))
        if secrets.notification_token is not None:
            values.append(secrets.notification_token.get_secret_value())
        self._register_secrets(values)

    def activation_status(self, activation_id: str) -> TradingActivationStatus:
        return self._activation_journal.status(activation_id, self._status.state)

    async def start(
        self,
        configuration: TradingConfiguration,
        secrets: TradingSecrets,
        activation_id: str | None = None,
    ) -> TradingStatus:
        if restore_manual_disabled(self._restore_gate_path):
            raise ValueError("Trading is unavailable until restore reconciliation completes")
        if self._maintenance_active:
            raise ValueError("Trading is unavailable during maintenance")
        self._register_trading_secrets(secrets)
        if self._task is not None and not self._task.done():
            raise ValueError("Trading is already active")
        if (
            not secrets.discord_token.get_secret_value()
            or not secrets.provider_api_key.get_secret_value()
        ):
            raise ValueError("Source and provider credentials are required")
        credential_ids = {broker.account_id for broker in secrets.brokers}
        if credential_ids != {account.id for account in configuration.accounts}:
            raise ValueError("Every configured account needs its own broker credentials")
        if configuration.notification is not None and (
            secrets.notification_token is None or not secrets.notification_token.get_secret_value()
        ):
            raise ValueError("Configured notifications require a bot token")
        activation_id = activation_id or str(uuid4())
        self._activation_journal.begin(activation_id, configuration.revision())
        self._activation_id = activation_id
        self._configuration = configuration
        self._stop = asyncio.Event()
        self._source_stop = asyncio.Event()
        self._work_arrived = asyncio.Event()
        self._source_failed = False
        self._failure_code = None
        self._status = TradingStatus(
            state="starting", configured_accounts=len(configuration.accounts)
        )
        self._task = asyncio.create_task(self._run(configuration, secrets))
        return self._status

    async def check_connection(self, connection: ConnectionCheck) -> CapabilityCheck:
        """Check one service with the keys typed for it; nothing is saved or started."""
        self._register_secrets(connection.secret_values())
        return await self._capability_service.check(connection)

    async def validate(
        self, configuration: TradingConfiguration, secrets: TradingSecrets
    ) -> TradingCapabilityReport:
        """Check actual connections and pending revision ownership without activation."""
        self._register_trading_secrets(secrets)
        report = await self._capability_service.validate(configuration, secrets)
        failures = list(report.checks)
        if self._task is not None and not self._task.done():
            failures.append(
                CapabilityCheck(
                    name="configuration",
                    state="failed",
                    adapter="trading_runtime",
                    reason_code="pause_before_configuration_change",
                )
            )
        elif report.activatable:
            source = None
            parser = None
            routing = None
            try:
                database = self._data_dir / "application.db"
                source = await SQLiteSourceStore.open(database)
                parser = await SQLiteExtractionStore.open(database)
                routing = await RoutingRevision.open(database)
                await routing.validate(configuration)
            except RoutingChangePending:
                failures.append(
                    CapabilityCheck(
                        name="configuration",
                        state="failed",
                        adapter="routing_revision",
                        reason_code="routing_change_pending",
                    )
                )
            except AccountOwnershipPending:
                failures.append(
                    CapabilityCheck(
                        name="configuration",
                        state="failed",
                        adapter="routing_revision",
                        reason_code="account_ownership_pending",
                    )
                )
            except Exception:  # noqa: BLE001 - configuration errors become a failed capability check
                failures.append(
                    CapabilityCheck(
                        name="configuration",
                        state="failed",
                        adapter="routing_revision",
                        reason_code="configuration_preflight_unavailable",
                    )
                )
            finally:
                if routing is not None:
                    await routing.close()
                if parser is not None:
                    await parser.close()
                if source is not None:
                    await source.close()
        return report.model_copy(
            update={
                "activatable": report.activatable
                and all(
                    check.state in {"ready", "not_configured", "unsupported"} for check in failures
                )
                and not any(check.name == "configuration" for check in failures),
                "checks": tuple(failures),
            }
        )

    async def pause(self) -> TradingStatus:
        if self._task is None or self._task.done():
            self._status = TradingStatus(
                configured_accounts=len(self._configuration.accounts) if self._configuration else 0
            )
            return self._status
        self._stop.set()
        self._source_stop.set()
        for account in self._accounts.values():
            if account.owner is not None:
                account.owner.request_stop()
        self._status = replace(self._status, state="pausing")
        return self._status

    async def shutdown(self) -> None:
        await self.pause()
        task = self._task
        if task is not None:
            await task
        # An owner that finished opening hands itself to _close_late_owner a moment later, so
        # wait until every late open has been handed off and every close it started is done.
        # gather does not yield when everything is already done, and the hand-off runs as a
        # callback, so give the loop a turn before checking again.
        while self._late_owner_opens or self._late_owner_closes:
            await asyncio.gather(
                *self._late_owner_opens, *self._late_owner_closes, return_exceptions=True
            )
            await asyncio.sleep(0)

    def _watch_late_owner(self, opening: asyncio.Future[AccountOwner]) -> None:
        """Close an owner that is still opening after Start gave up on it, once it opens."""
        self._late_owner_opens.add(opening)
        opening.add_done_callback(self._close_late_owner)

    def _close_late_owner(self, opened: asyncio.Future[AccountOwner]) -> None:
        """Close an owner that finished opening after Start gave up on it."""
        self._late_owner_opens.discard(opened)
        if opened.cancelled() or opened.exception() is not None:
            return
        closing = asyncio.create_task(opened.result().close())
        self._late_owner_closes.add(closing)
        closing.add_done_callback(self._late_owner_closed)

    def _late_owner_closed(self, closing: asyncio.Task[None]) -> None:
        self._late_owner_closes.discard(closing)
        if not closing.cancelled() and (error := closing.exception()) is not None:
            log.error("late_account_owner_close_failed type=%s", type(error).__name__)

    @asynccontextmanager
    async def maintenance_fence(self) -> AsyncIterator[None]:
        """Stop and drain every trading-owned store before a consistent snapshot."""
        async with self._maintenance_lock:
            self._maintenance_active = True
            try:
                await self.shutdown()
                yield
            finally:
                self._maintenance_active = False

    async def _run(self, configuration: TradingConfiguration, secrets: TradingSecrets) -> None:
        source: SQLiteSourceStore | None = None
        parser: SQLiteExtractionStore | None = None
        routing: RoutingRevision | None = None
        decoder: ManagedDecoder | None = None
        session: SourceSession | None = None
        stage = "storage_unavailable"
        try:
            database = self._data_dir / "application.db"
            source = await SQLiteSourceStore.open(
                database,
                diagnostics=(
                    self._telemetry.diagnostic_sink if self._telemetry is not None else None
                ),
                on_captured=self._wake,
            )
            parser = await SQLiteExtractionStore.open(database)
            routing = await RoutingRevision.open(database)
            stage = "routing_state_unavailable"
            await routing.accept(configuration)
            stage = "provider_unavailable"
            decoder = await self._factories.decoder(
                configuration.provider.name,
                configuration.provider.reader(secrets.provider_api_key, timeout=20),
            )
            profile_by_revision = {
                profile.profile_revision: profile for profile in configuration.profiles
            }
            routes = {}
            for route_binding in configuration.routes:
                profile = profile_by_revision[route_binding.profile_revision]
                key = route_key(
                    route_binding.source, route_binding.channel_id, route_binding.author_id
                )
                routes[key] = profile.route()
            worker = ParseWorker(
                parser,
                decoder,
                routes,
                configuration.provider.model,
                max_age=max(
                    account.policy.max_signal_age_seconds for account in configuration.accounts
                ),
                observe=self._telemetry.model_span if self._telemetry else lambda _: nullcontext(),
                observe_workflow=(
                    self._telemetry.workflow_span if self._telemetry else lambda _: nullcontext()
                ),
            )
            stage = "broker_unavailable"
            account_root = self._data_dir / "accounts"
            account_root.mkdir(parents=True, exist_ok=True, mode=0o700)
            os.chmod(account_root, 0o700)
            broker_secrets = {broker.account_id: broker for broker in secrets.brokers}
            opening: dict[str, asyncio.Future[AccountOwner]] = {}
            for account in configuration.accounts:
                account_dir = account_root / account.id
                account_dir.mkdir(mode=0o700, exist_ok=True)
                os.chmod(account_dir, 0o700)
                broker = broker_secrets[account.id]
                policy = _copy_policy(configuration, account.id)
                opening[account.id] = asyncio.ensure_future(
                    self._factories.owner(
                        account_dir,
                        AlpacaCredentials(broker.key, broker.secret),
                        policy,
                        account.environment,
                    )
                )
            done, _ = await asyncio.wait(opening.values(), timeout=self._owner_open_timeout_seconds)
            for account in configuration.accounts:
                task = opening[account.id]
                owner: AccountOwner | None = None
                if task in done:
                    try:
                        owner = task.result()
                    except Exception as exc:  # noqa: BLE001 - one account's failure is reported per account
                        log.error(
                            "trading_account_open_failed id=%s type=%s",
                            account.id,
                            type(exc).__name__,
                        )
                else:
                    log.error("trading_account_open_timed_out id=%s", account.id)

                    self._watch_late_owner(task)
                self._accounts[account.id] = AccountSupervisor(
                    account.id,
                    owner,
                    account.policy.poll_seconds,
                    self._stop,
                    self._account_changed,
                )
            self._account_changed()
            if not any(account.owner is not None for account in self._accounts.values()):
                raise RuntimeError("No configured account could open")
            stage = "source_unavailable"
            session = self._factories.session(
                source,
                {int(channel) for channel in configuration.source.channel_ids},
                {int(author) for author in configuration.source.author_ids}
                if configuration.source.author_ids
                else None,
                self._source_stop,
                self._report_source_failure,
            )
            notifier = (
                self._factories.notifier(
                    configuration.notification, secrets.notification_token.get_secret_value()
                )
                if configuration.notification is not None and secrets.notification_token is not None
                else None
            )
            for account in self._accounts.values():
                if account.owner is not None:
                    await account.refresh()
                account.start()
            try:
                session.start(secrets.discord_token.get_secret_value())
            except Exception as exc:  # noqa: BLE001 - the source failure is recorded and retried
                self._mark_source_failure(exc)
            self._status = replace(self._status, state="degraded")
            stage = "provider_unavailable"
            await probe_model(decoder, worker.model_health)
            stage = "processing_unavailable"
            await self._work_loop(configuration, source, parser, worker, session, notifier)
        except RoutingChangePending:
            self._failure_code = "routing_change_pending"
        except AccountOwnershipPending:
            self._failure_code = "account_ownership_pending"
        except _PausedBeforeReceipt:
            pass
        except Exception as exc:  # noqa: BLE001 - the runtime records the failed stage and stops
            self._failure_code = self._failure_code or stage
            log.error("trading_runtime_failed stage=%s type=%s", stage, type(exc).__name__)
        finally:
            self._stop.set()
            self._source_stop.set()
            for account in self._accounts.values():
                if account.owner is not None:
                    account.owner.request_stop()
            if session is not None:
                try:
                    await session.close()
                except Exception as exc:  # noqa: BLE001 - cleanup must not mask the primary outcome
                    log.error("source_close_failed type=%s", type(exc).__name__)
            for account in self._accounts.values():
                try:
                    await account.close()
                except Exception as exc:  # noqa: BLE001 - cleanup must not mask the primary outcome
                    log.error("execution_close_failed type=%s", type(exc).__name__)
            final_accounts = tuple(
                AccountStatus(
                    id=account.id,
                    state="failed" if account.state == "failed" else "paused",
                    error_code=account.error_code,
                )
                for account in self._accounts.values()
            )
            self._accounts.clear()
            if decoder is not None:
                try:
                    await decoder.close()
                except Exception as exc:  # noqa: BLE001 - cleanup must not mask the primary outcome
                    log.error("provider_close_failed type=%s", type(exc).__name__)
            if parser is not None:
                await parser.close()
            if source is not None:
                await source.close()
            if routing is not None:
                await routing.close()
            if self._failure_code is not None:
                self._status = replace(
                    self._status,
                    state="failed",
                    active_accounts=0,
                    source_connected=False,
                    model_ready=False,
                    error_code=self._failure_code,
                    accounts=final_accounts,
                )
            else:
                self._status = TradingStatus(
                    configured_accounts=len(configuration.accounts), accounts=final_accounts
                )
            activation = self._activation_journal.record
            activation_id = self._activation_id
            if (
                activation is not None
                and activation_id is not None
                and activation.activation_id == activation_id
            ):
                if activation.phase == "starting":
                    if self._failure_code is not None:
                        self._activation_journal.mark_failed(activation_id, self._failure_code)
                    else:
                        self._activation_journal.mark_stopped(activation_id)

    async def _work_loop(
        self,
        configuration: TradingConfiguration,
        source: SQLiteSourceStore,
        parser: SQLiteExtractionStore,
        worker: ParseWorker,
        session: SourceSession,
        notifier: NotificationSender | None,
    ) -> None:
        forwarder = ForwardBatch(
            source,
            _ParserPublisher(parser, self._stop),
            observe=self._telemetry.source_span if self._telemetry else nullcontext,
        )
        fanout = SignalFanout(
            parser,
            {
                route_key(route.source, route.channel_id, route.author_id): tuple(
                    DestinationTerms(
                        connection=connection,
                        environment=next(
                            account.environment
                            for account in configuration.accounts
                            if account.id == connection.account_id
                        ),
                        configuration_revision=configuration.revision(),
                        guru_id=route.guru_id,
                        profile_revision=route.profile_revision,
                    )
                    for connection in route.connections
                )
                for route in configuration.routes
            },
            self._accounts,
            self._stop,
            observe_workflow=(
                self._telemetry.workflow_span if self._telemetry else lambda _: nullcontext()
            ),
            observe_destination=(
                self._telemetry.destination_span
                if self._telemetry
                else lambda _message, _attempt: nullcontext()
            ),
        )
        processed = 0
        notification_failed = False

        while not self._stop.is_set():
            # Cleared before the pass: a post captured during it wakes the next pass at once.
            self._work_arrived.clear()
            if not self._source_failed:
                try:
                    await session.ensure_running()
                except Exception as exc:  # noqa: BLE001 - the source failure is recorded and retried
                    self._mark_source_failure(exc)
                else:
                    if (
                        self._activation_id is not None
                        and session.ready
                        and worker.model_ready
                        and not self._source_failed
                        and all(account.state == "running" for account in self._accounts.values())
                        and self._activation_journal.record is not None
                        and self._activation_journal.record.phase == "starting"
                    ):
                        self._activation_journal.mark_ready(self._activation_id)
                    # Forwarding writes the shared source/parser database. An
                    # uncertain commit must fail the whole runtime.
                    await session.forward_if_ready(forwarder)
            for _ in range(100):
                if self._stop.is_set() or not await worker.process_next(dt.datetime.now(dt.UTC)):
                    break
            if self._stop.is_set():
                break
            processed += await fanout.deliver()
            if self._stop.is_set():
                break
            if notifier is not None:
                try:
                    await deliver_notifications(parser, lambda item: notifier.send(item.payload))
                    for account in self._accounts.values():
                        if account.state != "running" or account.owner is None:
                            continue
                        for (
                            notification_id,
                            _,
                            _,
                            value,
                        ) in await account.owner.pending_notifications():
                            await notifier.send(_execution_notification_payload(value))
                            await account.owner.confirm_notification(notification_id)
                    notification_failed = False
                except Exception as exc:  # noqa: BLE001 - delivery failure is retried later
                    notification_failed = True
                    log.warning("notification_delivery_failed type=%s", type(exc).__name__)
            self._status = replace(
                self._status,
                state="running"
                if session.ready
                and not self._source_failed
                and worker.model_ready
                and not notification_failed
                and all(account.state == "running" for account in self._accounts.values())
                else "degraded",
                source_connected=session.ready and not self._source_failed,
                model_ready=worker.model_ready,
                pending_source=(source_backlog := await source.pending_snapshot()).count,
                oldest_pending_source_at=source_backlog.oldest_at,
                pending_signals=(signal_backlog := await parser.pending_snapshot()).count,
                oldest_pending_signal_at=signal_backlog.oldest_at,
                processed_signals=processed,
                error_code=(
                    "account_unavailable"
                    if any(account.state == "failed" for account in self._accounts.values())
                    else "source_unavailable"
                    if self._source_failed
                    else "notification_unavailable"
                    if notification_failed
                    else None
                ),
                accounts=tuple(account.status for account in self._accounts.values()),
                active_accounts=sum(
                    account.state == "running" for account in self._accounts.values()
                ),
            )
            await self._idle(0.5)

    def _wake(self) -> None:
        self._work_arrived.set()

    async def _idle(self, seconds: float) -> None:
        """Wait for the next pass: a captured post or Stop ends the wait early."""
        waits = {
            asyncio.ensure_future(self._stop.wait()),
            asyncio.ensure_future(self._work_arrived.wait()),
        }
        try:
            await asyncio.wait(waits, timeout=seconds, return_when=asyncio.FIRST_COMPLETED)
        finally:
            for wait in waits:
                wait.cancel()

    def _report_source_failure(self, event: str, error: BaseException | None) -> None:
        del event
        self._mark_source_failure(error)

    def _mark_source_failure(self, error: BaseException | None) -> None:
        self._source_failed = True
        self._source_stop.set()
        self._fail_startup_if_pending("source_unavailable")
        self._status = replace(
            self._status,
            state="degraded",
            source_connected=False,
            error_code="source_unavailable",
        )
        log.error(
            "trading_source_failed type=%s",
            type(error).__name__ if error is not None else "unknown",
        )

    def _account_changed(self) -> None:
        statuses = tuple(account.status for account in self._accounts.values())
        if any(account.state == "failed" for account in self._accounts.values()):
            self._fail_startup_if_pending("account_unavailable")
        self._status = replace(
            self._status,
            accounts=statuses,
            active_accounts=sum(account.state == "running" for account in self._accounts.values()),
            state="degraded"
            if any(account.state == "failed" for account in self._accounts.values())
            and self._status.state in {"running", "degraded"}
            else self._status.state,
            error_code="account_unavailable"
            if any(account.state == "failed" for account in self._accounts.values())
            else self._status.error_code,
        )

    def _fail_startup_if_pending(self, error_code: str) -> None:
        record = self._activation_journal.record
        if record is None or record.phase != "starting":
            return
        try:
            self._activation_journal.mark_failed(self._activation_id or "", error_code)
        except Exception:  # noqa: BLE001 - an undurable failure stops the runtime
            # If the failure cannot be made durable, stop before any caller can
            # treat an uncertain activation as committed.
            self._failure_code = "activation_journal_unavailable"
            self._source_stop.set()
            self._stop.set()
            for account in self._accounts.values():
                if account.owner is not None:
                    account.owner.request_stop()


def _copy_policy(configuration: TradingConfiguration, account_id: str) -> CopyConfig:
    account = next(account for account in configuration.accounts if account.id == account_id)
    pricing = {"max_above_signal_pct", "max_price_move_pct", "max_price_move_extended_pct"}
    return CopyConfig(
        sources=tuple(f"discord:{channel}" for channel in configuration.source.channel_ids),
        entry_pricing=EntryPricingPolicy(**account.policy.model_dump(include=pricing)),
        **account.policy.model_dump(exclude=pricing),
    )


def _execution_notification_payload(value: Mapping[str, object]) -> NotificationPayload:
    labels = value.get("labels")
    annotations = value.get("annotations")
    starts_at = value.get("starts_at")
    if not isinstance(labels, dict) or not isinstance(annotations, dict):
        raise ValueError("Saved execution notification is invalid")
    if not isinstance(starts_at, str):
        raise ValueError("Saved execution notification timestamp is invalid")
    if not all(isinstance(k, str) and isinstance(v, str) for k, v in labels.items()):
        raise ValueError("Saved execution notification labels are invalid")
    if not all(isinstance(k, str) and isinstance(v, str) for k, v in annotations.items()):
        raise ValueError("Saved execution notification annotations are invalid")
    return NotificationPayload(labels, annotations, dt.datetime.fromisoformat(starts_at))
