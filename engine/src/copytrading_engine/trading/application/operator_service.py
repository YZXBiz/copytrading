"""Operator read models over live owners, retained ledgers, and source evidence."""

import asyncio
import datetime as dt
import logging
from pathlib import Path

from copytrading_engine.execution.application.manual_commands import (
    manual_command_page_from_snapshot,
)
from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandPage,
    ManualCommandPageRequest,
)
from copytrading_engine.execution.domain.market import EquityHistory, HistoryWindow
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverview,
    AccountOverviewPage,
    AccountUnavailable,
    DestinationView,
    UnavailableReason,
    destination_views,
)
from copytrading_engine.shared.route_keys import choose_route, route_key
from copytrading_engine.trading.application.account_access import (
    AccountAccess,
    OwnerUnavailable,
    bounded_owner_read,
)
from copytrading_engine.trading.presentation.operator_models import SourceActivityPage

log = logging.getLogger(__name__)


class OperatorQueryService:
    """Answer the native app's paged account, event, source, and command-history reads."""

    def __init__(self, access: AccountAccess) -> None:
        self._access = access

    async def account_overviews(
        self, before_account_id: str | None = None, limit: int = 50
    ) -> AccountOverviewPage:
        """Return a bounded descending keyset page; no cross-page snapshot is implied."""
        if type(limit) is not int or not 1 <= limit <= 100:
            raise ValueError("Invalid account overview page")
        if before_account_id is not None and (
            not isinstance(before_account_id, str) or not 1 <= len(before_account_id) <= 64
        ):
            raise ValueError("Invalid account overview page")
        configuration = self._access.configuration()
        configured = {item.id: item for item in configuration.accounts} if configuration else {}
        eligible_configured = {
            account_id
            for account_id in configured
            if before_account_id is None or account_id < before_account_id
        }
        paths = self._access.retained_page_paths(
            before_account_id, limit + 1 + len(eligible_configured)
        )

        async def read_one(
            account_id: str,
        ) -> tuple[AccountOverview | None, AccountUnavailable | None]:
            failure: UnavailableReason | None = None
            database = paths.get(account_id)
            supervisor = self._access.supervisors().get(account_id)
            if (
                supervisor is not None
                and supervisor.owner is not None
                and supervisor.state != "failed"
            ):
                live = await bounded_owner_read(supervisor.owner.operator_overview())
                if not isinstance(live, OwnerUnavailable):
                    return live, None
                failure = live.reason
            if database is not None:
                try:
                    overview, _, _ = await self._access.retained_account(database, timeout=2)
                except TimeoutError:
                    failure = "timeout"
                except Exception as exc:  # noqa: BLE001 - one unreadable ledger must not hide others
                    log.warning(
                        "retained_account_read_failed id=%s type=%s", account_id, type(exc).__name__
                    )
                    failure = "read_failed"
                else:
                    if account_id not in configured:
                        return overview, None
                    readiness = (
                        "processing_stopped"
                        if self._access.runtime_state() in {"paused", "pausing"}
                        else "account_unavailable"
                    )
                    return overview.model_copy(
                        update={"active_configuration": True, "readiness": readiness}
                    ), None
            unavailable = (
                AccountUnavailable(account_id=account_id, reason=failure) if failure else None
            )
            if account_id not in configured:
                return None, unavailable
            account = configured[account_id]
            return AccountOverview(
                account_id=account_id,
                environment=account.environment,
                active_configuration=True,
                broker_identity="unverified",
                entry_permission="unknown",
                recovery_preference="manual",
                readiness="account_unavailable",
                account_risk_status="unavailable",
                account_risk_reason="account_unavailable",
                account_activity_status="unavailable",
                account_activity_reason="account_unavailable",
                total_exposure_usd=None,
                app_cost_basis_usd=None,
                positions=(),
                unresolved_incidents=(),
                ownership_incidents=(),
                pending_orders=None,
                pending_reports=None,
                oldest_report_at=None,
                balance=None,
            ), unavailable

        candidates = sorted(set(paths) | eligible_configured, reverse=True)
        page_ids = candidates[: limit + 1]
        results = await asyncio.gather(*(read_one(account_id) for account_id in page_ids[:limit]))
        return AccountOverviewPage(
            items=tuple(item for item, _ in results if item is not None),
            next_before_account_id=page_ids[limit - 1] if len(page_ids) > limit else None,
            unavailable_accounts=tuple(gap for _, gap in results if gap is not None),
        )

    async def account_events(
        self, account_id: str, before_seq: int | None, limit: int
    ) -> AccountEventPage:
        if not 1 <= limit <= 100 or (before_seq is not None and before_seq < 1):
            raise ValueError("Invalid account event page")
        supervisor = self._access.supervisors().get(account_id)
        if supervisor is not None and supervisor.owner is not None and supervisor.state != "failed":
            live = await bounded_owner_read(supervisor.owner.event_page(before_seq, limit))
            if not isinstance(live, OwnerUnavailable):
                return live
        database = self._access.retained_paths().get(account_id)
        if database is None:
            raise KeyError(account_id)
        _, _, page = await self._access.retained_account(
            database, before_seq=before_seq, limit=limit, timeout=2
        )
        return page

    async def equity_history(self, account_id: str, window: HistoryWindow) -> EquityHistory | None:
        """The running account's broker curve; None while it has no live owner to ask."""
        configuration = self._access.configuration()
        if configuration is None or account_id not in {item.id for item in configuration.accounts}:
            raise KeyError(account_id)
        supervisor = self._access.supervisors().get(account_id)
        if supervisor is None or supervisor.owner is None or supervisor.state == "failed":
            return None
        history = await bounded_owner_read(
            supervisor.owner.equity_history(window, dt.datetime.now(dt.UTC))
        )
        return None if isinstance(history, OwnerUnavailable) else history

    async def source_activity(self, before_seq: int | None, limit: int) -> SourceActivityPage:
        page = await asyncio.wait_for(
            asyncio.to_thread(
                self._access.evidence.source_page,
                self._access.application_database,
                before_seq=before_seq,
                limit=limit,
                destinations={},
            ),
            timeout=2,
        )
        ids = {item.source_id for item in page.items}
        by_source: dict[str, list[DestinationView]] = {key: [] for key in ids}
        paths = self._access.retained_paths()

        async def read_destinations(
            account_id: str, database: Path
        ) -> dict[str, DestinationView] | AccountUnavailable:
            supervisor = self._access.supervisors().get(account_id)
            if (
                supervisor is not None
                and supervisor.owner is not None
                and supervisor.state != "failed"
            ):
                live = await bounded_owner_read(supervisor.owner.destination_views(ids))
                if not isinstance(live, OwnerUnavailable):
                    return live
            try:
                _, snapshot, _ = await self._access.retained_account(database, timeout=2)
            except TimeoutError:
                return AccountUnavailable(account_id=account_id, reason="timeout")
            except Exception as exc:  # noqa: BLE001 - one unreadable ledger must not hide others
                log.warning("destination_read_failed id=%s type=%s", account_id, type(exc).__name__)
                return AccountUnavailable(account_id=account_id, reason="read_failed")
            return destination_views(snapshot, ids)

        results = await asyncio.gather(
            *(
                read_destinations(account_id, database)
                for account_id, database in sorted(paths.items())
            )
        )
        unavailable = tuple(result for result in results if isinstance(result, AccountUnavailable))
        for views in results:
            if isinstance(views, AccountUnavailable):
                continue
            for source_id, view in views.items():
                by_source[source_id].append(view)
        configuration = self._access.configuration()
        if configuration is not None:
            accounts = {account.id: account for account in configuration.accounts}
            routes_by_key = {
                route_key(candidate.source, candidate.channel_id, candidate.author_id): candidate
                for candidate in configuration.routes
            }
            for item in page.items:
                if item.delivery_status != "pending":
                    continue
                parts = item.source_id.split(":", 2)
                route = None
                if len(parts) == 3:
                    route = choose_route(routes_by_key, "discord", parts[1], item.author_id).route
                if route is None:
                    continue
                present = {view.account_id for view in by_source[item.source_id]}
                for connection in route.connections:
                    if connection.account_id in present:
                        continue
                    by_source[item.source_id].append(
                        DestinationView(
                            account_id=connection.account_id,
                            environment=accounts[connection.account_id].environment,
                            status="pending_delivery",
                            instruction_outcomes=(),
                            limits_hit=(),
                            orders=(),
                        )
                    )
        return page.model_copy(
            update={
                "unavailable_accounts": unavailable,
                "items": tuple(
                    item.model_copy(
                        update={
                            "destinations": tuple(
                                sorted(
                                    by_source[item.source_id], key=lambda value: value.account_id
                                )
                            )
                        }
                    )
                    for item in page.items
                ),
            }
        )

    async def list_manual_commands(self, request: ManualCommandPageRequest) -> ManualCommandPage:
        request = ManualCommandPageRequest.model_validate(request.model_dump())
        supervisor = self._access.supervisors().get(request.account_id)
        if (
            supervisor is not None
            and supervisor.owner is not None
            and supervisor.state not in {"failed", "paused"}
        ):
            return await supervisor.owner.manual_command_page(
                request.source_id,
                before_command_id=request.before_command_id,
                limit=request.limit,
            )
        return await self._retained_manual_command_page(request)

    async def _retained_manual_command_page(
        self, request: ManualCommandPageRequest
    ) -> ManualCommandPage:
        try:
            database = self._access.manual_command_ledger_path(request.account_id)
            _, snapshot, _ = await self._access.retained_account(database, timeout=3)
            return manual_command_page_from_snapshot(
                snapshot,
                account_id=request.account_id,
                source_id=request.source_id,
                before_command_id=request.before_command_id,
                limit=request.limit,
            )
        except Exception as exc:
            log.warning(
                "retained_manual_command_read_failed account=%s type=%s",
                request.account_id,
                type(exc).__name__,
            )
            raise ValueError("Manual account history is unavailable") from exc
