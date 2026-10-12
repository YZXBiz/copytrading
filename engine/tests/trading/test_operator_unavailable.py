"""Operator pages name accounts they could not read instead of showing them as empty."""

import asyncio
from types import SimpleNamespace

from pydantic import SecretStr

from copytrading_engine.execution.domain.market import EquityHistory, HistoryWindow
from copytrading_engine.execution.presentation.operator_views import AccountUnavailable
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.adapters.operator_queries import SQLiteOperatorEvidence
from copytrading_engine.trading.application import account_access
from copytrading_engine.trading.application.account_access import (
    AccountAccess,
    OwnerUnavailable,
    bounded_owner_read,
)
from copytrading_engine.trading.application.operator_service import OperatorQueryService
from copytrading_engine.trading.application.paused_reader import PausedAccountReader, ReadKeys


def _service(data_dir) -> OperatorQueryService:
    return OperatorQueryService(
        AccountAccess(
            data_dir,
            lambda: {},
            configuration=lambda: None,
            runtime_state=lambda: "paused",
            evidence=SQLiteOperatorEvidence(),
        )
    )


def _corrupt_ledger(data_dir, account_id: str) -> None:
    database = data_dir / "accounts" / account_id / "execution.sqlite3"
    database.parent.mkdir(parents=True)
    database.write_bytes(b"not a SQLite database")


async def test_unreadable_retained_account_is_reported_on_the_overview_page(tmp_path):
    _corrupt_ledger(tmp_path, "archive")

    page = await _service(tmp_path).account_overviews()

    assert page.items == ()
    assert page.unavailable_accounts == (
        AccountUnavailable(account_id="archive", reason="read_failed"),
    )


async def test_unreadable_account_is_reported_on_the_source_activity_page(tmp_path):
    for opener in (SQLiteSourceStore.open, SQLiteExtractionStore.open):
        store = await opener(tmp_path / "application.db")
        await store.close()
    _corrupt_ledger(tmp_path, "archive")

    page = await _service(tmp_path).source_activity(None, 10)

    assert page.unavailable_accounts == (
        AccountUnavailable(account_id="archive", reason="read_failed"),
    )


async def test_stalled_owner_read_is_a_timeout_not_an_empty_result(monkeypatch):
    monkeypatch.setattr(account_access, "_OWNER_READ_TIMEOUT_SECONDS", 0.01)
    release = asyncio.Event()

    async def stalled() -> str:
        await release.wait()
        return "late"

    result = await bounded_owner_read(stalled())
    release.set()

    assert result == OwnerUnavailable("timeout")


async def test_failed_owner_read_is_reported_as_read_failed():
    async def failing() -> str:
        raise OSError("worker lost")

    assert await bounded_owner_read(failing()) == OwnerUnavailable("read_failed")


async def test_chart_is_read_from_the_broker_when_the_stopped_owner_cannot_answer(tmp_path):
    window = HistoryWindow(range="day")
    curve = EquityHistory(window=window, base_value=None, points=())

    class Broker:
        def equity_history(self, asked: HistoryWindow) -> EquityHistory:
            return curve

        def close(self) -> None:
            pass

    class Owner:
        async def equity_history(self, asked, now):
            raise OSError("owner closed")

    supervisor = SimpleNamespace(owner=Owner(), state="stopped", error_code=None)
    reader = PausedAccountReader(lambda _: Broker())
    reader.attach(
        (
            ReadKeys(
                account_id="primary", environment="paper", key=SecretStr("k"), secret=SecretStr("s")
            ),
        )
    )
    service = OperatorQueryService(
        AccountAccess(
            tmp_path,
            lambda: {"primary": supervisor},
            configuration=lambda: None,
            runtime_state=lambda: "paused",
            evidence=SQLiteOperatorEvidence(),
        ),
        reader,
    )

    assert await service.equity_history("primary", window) == curve
