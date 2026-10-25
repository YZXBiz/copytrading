"""A guru's day is counted from every post the engine holds, not from the page the app loaded."""

import datetime as dt
import sqlite3
from contextlib import closing
from decimal import Decimal
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from copytrading_engine.execution.presentation.operator_views import DestinationView, OrderView
from copytrading_engine.parsing.application import outcome
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.route_keys import guru_for_channel
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.adapters.operator_queries import SQLiteOperatorEvidence
from copytrading_engine.trading.application.account_access import AccountAccess
from copytrading_engine.trading.application.operator_service import OperatorQueryService

LOS_ANGELES = ZoneInfo("America/Los_Angeles")
# 11:00 in New York on Wednesday 14 October: the owner's day in Los Angeles began at 07:00 UTC.
NOW = dt.datetime(2026, 10, 14, 15, tzinfo=dt.UTC)
DAY_START = dt.datetime(2026, 10, 14, tzinfo=LOS_ANGELES)
DAY_END = dt.datetime(2026, 10, 15, tzinfo=LOS_ANGELES)


def _order(client_id: str, status: str, filled: str) -> OrderView:
    return OrderView(
        client_id=client_id,
        symbol="PM",
        side="buy",
        status=status,
        quantity=Decimal("1"),
        filled_quantity=Decimal(filled),
        limit_price=Decimal("201"),
        average_fill_price=Decimal("201") if filled != "0" else None,
        broker_id=None,
        created_at=NOW,
        instruction_index=0,
        requested_usd=None,
        budget_usd=None,
    )


def _view(
    status: str = "done", outcomes: tuple[str, ...] = (), orders: tuple[OrderView, ...] = ()
) -> DestinationView:
    return DestinationView(
        account_id="primary",
        environment="paper",
        status=status,
        instruction_outcomes=outcomes,
        limits_hit=(),
        orders=orders,
    )


class _Owner:
    """The running account's answer: what it did with each post it was asked about."""

    def __init__(self, views: dict[str, DestinationView]) -> None:
        self.views = views

    async def destination_views(self, source_ids: set[str]) -> dict[str, DestinationView]:
        return {key: view for key, view in self.views.items() if key in source_ids}


# Each guru posts in their own channel, which names them (route_keys.guru_for_channel).
CHANNELS = {"lee": "1", "zhao": "2"}
LEE = guru_for_channel("discord", "1")
ZHAO = guru_for_channel("discord", "2")


async def _post(
    source: SQLiteSourceStore,
    parser: SQLiteExtractionStore,
    message_id: str,
    at: dt.datetime,
    guru: str | None,
) -> str:
    raw = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id=CHANNELS.get(guru or "", "1"),
        id=message_id,
        timestamp=at,
        text=f"post {message_id}",
    )
    await source.add(raw)
    await parser.add(raw)
    await parser.finish(
        raw.identity,
        outcome(
            raw,
            "ignore",
            "chatter",
            model="fixture",
            guru_id=guru,
            profile_revision="a" * 64 if guru else None,
        ),
    )
    return raw.identity


def _read(database, source_id: str, started: dt.datetime, seconds: float) -> None:
    with closing(sqlite3.connect(database)) as db, db:
        db.execute(
            "UPDATE parser_inbox SET enqueued_at=?,completed_at=? WHERE id=?",
            (
                started.isoformat(),
                (started + dt.timedelta(seconds=seconds)).isoformat(),
                source_id,
            ),
        )


async def test_a_busy_day_counts_every_post_of_each_guru_within_the_owners_day(tmp_path):
    database = tmp_path / "application.db"
    source = await SQLiteSourceStore.open(database)
    parser = await SQLiteExtractionStore.open(database)
    morning = dt.datetime(2026, 10, 14, 13, tzinfo=dt.UTC)
    lee = [
        await _post(source, parser, f"lee-{n}", morning + dt.timedelta(minutes=n), "lee")
        for n in range(30)
    ]
    zhao = [
        await _post(
            source, parser, f"zhao-{n}", morning + dt.timedelta(minutes=n, seconds=30), "zhao"
        )
        for n in range(20)
    ]
    # 23:00 in Los Angeles the evening before: yesterday for the owner, but the same New York
    # trading day, so a call in it still waits.
    late_evening = await _post(
        source, parser, "lee-late", dt.datetime(2026, 10, 14, 6, tzinfo=dt.UTC), "lee"
    )
    # Yesterday's trading day: a call held then has expired.
    yesterday = await _post(
        source, parser, "lee-old", dt.datetime(2026, 10, 13, 15, tzinfo=dt.UTC), "lee"
    )
    unattributed = await _post(source, parser, "nobody", morning, None)
    await parser.close()
    await source.close()
    # Half of Lee's posts took the reader 2 seconds and half 4; the evening before is not today.
    for n, source_id in enumerate(lee):
        _read(database, source_id, morning, 2 if n % 2 else 4)
    _read(database, late_evening, morning, 100)

    owner = _Owner(
        {
            lee[0]: _view(orders=(_order("copy-1", "filled", "1"),)),
            # Part filled before the rest was cancelled: still bought.
            lee[1]: _view(orders=(_order("copy-2", "canceled", "0.4"),)),
            # Nothing filled: not traded.
            lee[2]: _view(orders=(_order("copy-3", "canceled", "0"),)),
            lee[3]: _view(outcomes=("approval_required",)),
            # Held for approval, but the owner entered the trade by hand.
            lee[4]: _view(
                outcomes=("approval_required",), orders=(_order("manual-1", "filled", "1"),)
            ),
            late_evening: _view(outcomes=("named_buy_not_held",)),
            yesterday: _view(outcomes=("approval_required",)),
            zhao[0]: _view(status="review_required", outcomes=("review_required",)),
            zhao[1]: _view(orders=(_order("copy-4", "filled", "1"),)),
            unattributed: _view(orders=(_order("copy-5", "filled", "1"),)),
        }
    )
    account = tmp_path / "accounts" / "primary" / "execution.sqlite3"
    account.parent.mkdir(parents=True)
    account.touch()
    supervisor = SimpleNamespace(owner=owner, state="running", error_code=None)
    service = OperatorQueryService(
        AccountAccess(
            tmp_path,
            lambda: {"primary": supervisor},
            configuration=lambda: None,
            runtime_state=lambda: "running",
            evidence=SQLiteOperatorEvidence(),
        )
    )

    page = await service.guru_day_stats(DAY_START, DAY_END, NOW)

    by_guru = {stats.guru_id: stats for stats in page.gurus}
    assert set(by_guru) == {LEE, ZHAO}
    # 50 posts between them, twice the newest page the app reads.
    assert by_guru[LEE].posts == 30
    assert by_guru[ZHAO].posts == 20
    assert by_guru[LEE].traded == 3
    assert by_guru[ZHAO].traded == 1
    assert by_guru[LEE].read_seconds == 3.0
    assert by_guru[ZHAO].read_seconds is not None
    # Whole posts, newest first, though neither is among the newest page the app reads: the app
    # lists them from here, so its count and its Waiting tab are one set.
    assert [item.source_id for item in by_guru[LEE].waiting] == [late_evening, lee[3]]
    assert [item.source_id for item in by_guru[ZHAO].waiting] == [zhao[0]]
    assert by_guru[LEE].waiting[1].text == "post lee-3"
    assert by_guru[LEE].waiting[1].guru_id == LEE
    assert [view.instruction_outcomes for view in by_guru[LEE].waiting[1].destinations] == [
        ("approval_required",)
    ]
    assert page.unavailable_accounts == ()


async def test_a_day_with_no_posts_has_no_gurus(tmp_path):
    service = OperatorQueryService(
        AccountAccess(
            tmp_path,
            lambda: {},
            configuration=lambda: None,
            runtime_state=lambda: "paused",
            evidence=SQLiteOperatorEvidence(),
        )
    )

    page = await service.guru_day_stats(DAY_START, DAY_END, NOW)

    assert page.gurus == ()


async def test_a_gurus_page_lists_their_posts_however_many_others_posted_since(tmp_path):
    database = tmp_path / "application.db"
    source = await SQLiteSourceStore.open(database)
    parser = await SQLiteExtractionStore.open(database)
    morning = dt.datetime(2026, 10, 14, 13, tzinfo=dt.UTC)
    # Read under the setup's earlier random ID ("zhao"), before IDs came from the channel.
    zhao = [
        await _post(source, parser, f"zhao-{n}", morning + dt.timedelta(minutes=n), "zhao")
        for n in range(3)
    ]
    unattributed = await _post(source, parser, "zhao-chatter", morning, None)
    # Thirty newer posts in another channel: more than the newest page the app reads.
    for n in range(30):
        await _post(source, parser, f"lee-{n}", morning + dt.timedelta(hours=1, minutes=n), "lee")
    await parser.close()
    await source.close()
    route = SimpleNamespace(source="discord", channel_id="2", author_id=None, connections=())
    service = OperatorQueryService(
        AccountAccess(
            tmp_path,
            lambda: {},
            configuration=lambda: SimpleNamespace(routes=(route,), accounts=()),
            runtime_state=lambda: "running",
            evidence=SQLiteOperatorEvidence(),
        )
    )

    first = await service.guru_activity(ZHAO, None, 2)
    older = await service.guru_activity(ZHAO, first.next_before_seq, 2)

    assert [item.source_id for item in first.items] == [zhao[2], zhao[1]]
    assert {item.guru_id for item in first.items} == {ZHAO}
    assert first.rejected_items == ()
    assert [item.source_id for item in older.items] == [zhao[0]]
    assert unattributed not in {item.source_id for item in first.items + older.items}
    assert older.next_before_seq is None
    # A guru the setup no longer has has no page.
    assert (await service.guru_activity(LEE, None, 25)).items == ()
