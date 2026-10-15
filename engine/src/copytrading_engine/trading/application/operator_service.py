"""Operator read models over live owners, retained ledgers, and source evidence."""

import asyncio
import datetime as dt
import logging
from dataclasses import dataclass, field
from pathlib import Path

from copytrading_engine.execution.application.manual_commands import (
    manual_command_page_from_snapshot,
)
from copytrading_engine.execution.application.ports import ACCOUNT_OPEN_REFUSALS
from copytrading_engine.execution.domain.ledger_state import HELD_FOR_OWNER, EarlierLedgerVersion
from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandPage,
    ManualCommandPageRequest,
)
from copytrading_engine.execution.domain.market import EquityHistory, HistoryWindow, Quote
from copytrading_engine.execution.domain.sessions import ET, trade_date
from copytrading_engine.execution.presentation.account_feed import AccountFeedPage
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverview,
    AccountOverviewPage,
    AccountUnavailable,
    DestinationView,
    UnavailableReason,
    destination_views,
    with_live_facts,
)
from copytrading_engine.shared.route_keys import choose_route, route_key
from copytrading_engine.trading.application.account_access import (
    AccountAccess,
    OwnerUnavailable,
    bounded_owner_read,
)
from copytrading_engine.trading.application.paused_reader import (
    PausedAccountReader,
    ReadKeys,
    ReadOnlyBroker,
)
from copytrading_engine.trading.presentation.operator_models import (
    GuruDayStats,
    GuruDayStatsPage,
    SourceActivityPage,
)

log = logging.getLogger(__name__)

# Orders the owner placed by hand for a post; a call they entered themselves no longer waits.
_OWNER_ENTRY = "manual-"


@dataclass
class _GuruTally:
    posts: int = 0
    traded: int = 0
    reads: list[float] = field(default_factory=list)
    waiting: list[str] = field(default_factory=list)


def _traded(view: DestinationView) -> bool:
    """The account bought or sold on the post: an order of it filled, in whole or in part."""
    return any(order.status == "filled" or order.filled_quantity > 0 for order in view.orders)


def _waits(views: list[DestinationView]) -> bool:
    """A call of the post waits for the owner (ADR-0007): an account holds it for them, and they
    have not entered the trade by hand."""
    held = any(
        view.status == "review_required"
        or any(outcome in HELD_FOR_OWNER for outcome in view.instruction_outcomes)
        for view in views
    )
    entered = any(
        order.client_id.startswith(_OWNER_ENTRY) for view in views for order in view.orders
    )
    return held and not entered


def _no_broker(keys: ReadKeys) -> ReadOnlyBroker:
    raise RuntimeError("This engine reads no broker while copying is paused")


class OperatorQueryService:
    """Answer the native app's paged account, event, source, and command-history reads."""

    def __init__(self, access: AccountAccess, reader: PausedAccountReader | None = None) -> None:
        self._access = access
        # With no reader given, paused accounts are read from their ledgers alone.
        self._reader = reader if reader is not None else PausedAccountReader(_no_broker)

    def attach_readers(self, keys: tuple[ReadKeys, ...]) -> None:
        """Read paused accounts live with these keys until `detach_readers`."""
        self._reader.attach(keys)

    def detach_readers(self) -> None:
        self._reader.detach()

    async def _live(self, account_id: str, overview: AccountOverview) -> AccountOverview:
        """A retained overview with the broker's balance and valuations, when they can be read."""
        facts = await self._reader.facts(account_id)
        if facts is None:
            return overview
        return with_live_facts(overview, facts.account, facts.positions, facts.observed_at)

    def _unavailable_readiness(self, account_id: str) -> str:
        """Why an account is not running, when its owner can act on it; else just unavailable."""
        supervisor = self._access.supervisors().get(account_id)
        code = (
            supervisor.error_code
            if supervisor is not None
            else self._access.account_error(account_id)
        )
        return code if code in ACCOUNT_OPEN_REFUSALS else "account_unavailable"

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
                except EarlierLedgerVersion:
                    failure = "earlier_version"
                except Exception as exc:  # noqa: BLE001 - one unreadable ledger must not hide others
                    log.warning(
                        "retained_account_read_failed id=%s type=%s error=%s",
                        account_id,
                        type(exc).__name__,
                        exc,
                    )
                    failure = "read_failed"
                else:
                    overview = await self._live(account_id, overview)
                    if account_id not in configured:
                        return overview, None
                    readiness = (
                        "processing_stopped"
                        if self._access.runtime_state() in {"paused", "pausing"}
                        else self._unavailable_readiness(account_id)
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
                readiness=self._unavailable_readiness(account_id),
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

    async def account_feed(
        self, account_id: str, before_seq: int | None, limit: int
    ) -> AccountFeedPage:
        """The account's feed: from its running owner, or else from its retained ledger."""
        if not 1 <= limit <= 100 or (before_seq is not None and before_seq < 1):
            raise ValueError("Invalid account feed page")
        supervisor = self._access.supervisors().get(account_id)
        if supervisor is not None and supervisor.owner is not None and supervisor.state != "failed":
            live = await bounded_owner_read(supervisor.owner.feed_page(before_seq, limit))
            if not isinstance(live, OwnerUnavailable):
                return live
        database = self._access.retained_paths().get(account_id)
        if database is None:
            raise KeyError(account_id)
        return await self._access.retained_feed(
            database, before_seq=before_seq, limit=limit, timeout=2
        )

    async def equity_history(self, account_id: str, window: HistoryWindow) -> EquityHistory | None:
        """The account's broker curve: from its running owner, else (paused, or an owner that
        cannot answer) from the read keys the app attached; None when neither can ask."""
        configuration = self._access.configuration()
        configured = configuration is not None and account_id in {
            item.id for item in configuration.accounts
        }
        if not configured and not self._reader.holds(account_id):
            raise KeyError(account_id)
        supervisor = self._access.supervisors().get(account_id)
        if supervisor is not None and supervisor.owner is not None and supervisor.state != "failed":
            history = await bounded_owner_read(
                supervisor.owner.equity_history(window, dt.datetime.now(dt.UTC))
            )
            if not isinstance(history, OwnerUnavailable):
                return history
        return await self._reader.equity_history(account_id, window)

    async def quote(self, account_id: str, symbol: str) -> Quote | None:
        """A stock's latest quote through the account's read keys, for the trade sheet."""
        if not self._reader.holds(account_id):
            raise KeyError(account_id)
        return await self._reader.quote(account_id, symbol)

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
        by_source, unavailable = await self._destinations({item.source_id for item in page.items})
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

    async def _destinations(
        self, ids: set[str]
    ) -> tuple[dict[str, list[DestinationView]], tuple[AccountUnavailable, ...]]:
        """What each account did with each of these posts, from its owner or its ledger."""
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
            except EarlierLedgerVersion:
                return AccountUnavailable(account_id=account_id, reason="earlier_version")
            except Exception as exc:  # noqa: BLE001 - one unreadable ledger must not hide others
                log.warning("destination_read_failed id=%s type=%s", account_id, type(exc).__name__)
                return AccountUnavailable(account_id=account_id, reason="read_failed")
            try:
                events = await asyncio.wait_for(
                    asyncio.to_thread(self._access.evidence.retained_message_events, database, ids),
                    timeout=2,
                )
            except Exception as exc:  # noqa: BLE001 - the timeline is extra; the outcome stands
                log.warning("timeline_read_failed id=%s type=%s", account_id, type(exc).__name__)
                events = ()
            return destination_views(snapshot, ids, events)

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
                if source_id in by_source:
                    by_source[source_id].append(view)
        return by_source, unavailable

    async def guru_day_stats(
        self, day_start: dt.datetime, day_end: dt.datetime, now: dt.datetime | None = None
    ) -> GuruDayStatsPage:
        """Each guru's posts, trades and read time from `day_start` up to `day_end`, and the
        posts of the current trading day still waiting for the owner, counted from every post
        the engine holds."""
        now = now or dt.datetime.now(dt.UTC)
        trading_day = trade_date(now)
        # The trading day began at 20:00 New York time the evening before.
        trading_start = dt.datetime.combine(
            trading_day - dt.timedelta(days=1), dt.time(20), tzinfo=ET
        )
        posts = await asyncio.wait_for(
            asyncio.to_thread(
                self._access.evidence.guru_posts,
                self._access.application_database,
                since=min(day_start, trading_start),
            ),
            timeout=2,
        )
        by_source, unavailable = await self._destinations({post.source_id for post in posts})
        tallies: dict[str, _GuruTally] = {}
        for post in posts:
            tally = tallies.setdefault(post.guru_id, _GuruTally())
            views = by_source.get(post.source_id, [])
            if day_start <= post.source_at < day_end:
                tally.posts += 1
                if any(_traded(view) for view in views):
                    tally.traded += 1
                if post.read_started_at is not None and post.read_at is not None:
                    tally.reads.append(
                        max(0.0, (post.read_at - post.read_started_at).total_seconds())
                    )
            if trade_date(post.source_at) == trading_day and _waits(views):
                tally.waiting.append(post.source_id)
        return GuruDayStatsPage(
            day_start=day_start,
            day_end=day_end,
            gurus=tuple(
                GuruDayStats(
                    guru_id=guru_id,
                    posts=tally.posts,
                    traded=tally.traded,
                    read_seconds=sum(tally.reads) / len(tally.reads) if tally.reads else None,
                    waiting_source_ids=tuple(tally.waiting),
                )
                for guru_id, tally in sorted(tallies.items())
            ),
            unavailable_accounts=unavailable,
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
