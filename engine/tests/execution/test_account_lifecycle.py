"""Real account SQLite and one controlled broker exercise durable entry permission."""

import datetime as dt
from decimal import Decimal

import pytest
from pydantic import SecretStr

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials
from copytrading_engine.execution.adapters.owner import ExecutionOwner
from copytrading_engine.execution.domain.lifecycle import (
    AccountControlCommand,
    AccountControlConflict,
)
from copytrading_engine.execution.domain.market import EquityHistory, HistoryWindow
from copytrading_engine.execution.domain.progress import OrderLinked, Pending
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.shared.signals import StockSignal
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

from .builders import destination_signal, event
from .fakes import FakeBroker

NOW = dt.datetime.now(dt.UTC)


async def _open(tmp_path, broker, account_id="paper"):
    return await ExecutionOwner.open(
        tmp_path / "accounts" / account_id,
        AlpacaCredentials(key=SecretStr("test"), secret=SecretStr("test")),
        CopyConfig(sources=("discord:demo",)),
        environment="paper",
        broker_factory=lambda _credentials, _environment: broker,
        account_lock_root=tmp_path / "locks",
    )


def _command(identity, action, preference=None):
    return AccountControlCommand(
        command_id=identity,
        account_id="paper",
        action=action,
        recovery_preference=preference,
    )


async def test_disabled_and_paused_buys_are_durable_skips_but_owned_exit_continues(
    tmp_path, monkeypatch
):
    datetime_type = dt.datetime

    class FixedDateTime(datetime_type):
        @classmethod
        def now(cls, tz=None):
            fixed = cls(2026, 1, 5, 15, 0, tzinfo=dt.UTC)
            return fixed if tz is None else fixed.astimezone(tz)

    monkeypatch.setattr(dt, "datetime", FixedDateTime)
    now = FixedDateTime(2026, 1, 5, 15, 0, tzinfo=dt.UTC)
    broker = FakeBroker()
    owner = await _open(tmp_path, broker)
    try:
        await owner.recover_account(now)
        assert (await owner.account_status()).entry_permission == "disabled"
        first = StockSignal.model_validate(event("disabled", timestamp=now))
        await owner.receive(destination_signal(first, account_id="paper"), now)
        await owner.cycle(now, halted=False)
        assert broker.calls == 0
        assert (await owner.observation()).ledger.messages["discord:demo:disabled"].parts[
            0
        ].reason == "account_disabled"

        enabled = await owner.control_account(_command("enable-1", "resume"), now)
        assert enabled.entry_permission == "enabled"
        buy = StockSignal.model_validate(event("owned", price="25.10", timestamp=now))
        await owner.receive(destination_signal(buy, account_id="paper"), now)
        await owner.cycle(now, halted=False)
        assert broker.calls == 1
        enabled_buy = (await owner.observation()).ledger.messages["discord:demo:owned"]
        assert isinstance(enabled_buy.parts[0], OrderLinked)

        await owner.control_account(_command("pause-1", "pause"), now)
        paused = StockSignal.model_validate(event("paused", price="25.20", timestamp=now))
        await owner.receive(destination_signal(paused, account_id="paper"), now)
        await owner.cycle(now, halted=False)
        assert broker.calls == 1
        assert (await owner.observation()).ledger.messages["discord:demo:paused"].parts[
            0
        ].reason == "account_paused"

        exit_signal = StockSignal.model_validate(
            event("exit", "close", "25", "25.10", timestamp=now)
        )
        await owner.receive(destination_signal(exit_signal, account_id="paper"), now)
        await owner.cycle(now, halted=False)
        assert broker.calls == 2

        await owner.control_account(_command("enable-2", "resume"), now)
        await owner.cycle(now, halted=False)
        assert broker.calls == 2
    finally:
        await owner.close()


async def test_control_replay_conflict_and_recovery_preferences_survive_restart(tmp_path):
    broker = FakeBroker()
    owner = await _open(tmp_path, broker)
    try:
        await owner.recover_account(NOW)
        automatic = _command("preference-1", "set_recovery", "automatic")
        assert (await owner.control_account(automatic, NOW)).recovery_preference == "automatic"
        assert await owner.control_account(
            automatic, NOW + dt.timedelta(seconds=1)
        ) == await owner.control_account(automatic, NOW)
        with pytest.raises(AccountControlConflict):
            await owner.control_account(_command("preference-1", "pause"), NOW)
        await owner.control_account(_command("enable-1", "resume"), NOW)
    finally:
        await owner.close()

    owner = await _open(tmp_path, broker)
    try:
        await owner.recover_account(NOW + dt.timedelta(minutes=1))
        assert (await owner.account_status()).readiness in {
            "enabled",
            "enabled_waiting_for_session",
        }
        await owner.control_account(_command("pause-1", "pause"), NOW)
    finally:
        await owner.close()

    owner = await _open(tmp_path, broker)
    try:
        await owner.recover_account(NOW + dt.timedelta(minutes=2))
        assert (await owner.account_status()).readiness == "paused"
        await owner.control_account(_command("preference-2", "set_recovery", "manual"), NOW)
        await owner.control_account(_command("enable-2", "resume"), NOW)
    finally:
        await owner.close()

    owner = await _open(tmp_path, broker)
    try:
        await owner.recover_account(NOW + dt.timedelta(minutes=3))
        assert (await owner.account_status()).readiness == "manual_resume_required"
        assert (await owner.account_status()).entry_permission == "enabled"
        page = await owner.event_page(None, 2)
        assert len(page.items) == 2
        assert page.next_before_seq is not None
        following = await owner.event_page(page.next_before_seq, 2)
        assert set(item.sequence for item in page.items).isdisjoint(
            item.sequence for item in following.items
        )
    finally:
        await owner.close()


async def test_retained_account_and_source_page_show_real_evidence_without_broker_open(tmp_path):
    broker = FakeBroker()
    owner = await _open(tmp_path, broker)
    signal = StockSignal.model_validate(event("evidence", timestamp=NOW))
    broker.account_data |= {"equity": "5120.50", "last_equity": "5000", "cash": "4100"}
    try:
        await owner.recover_account(NOW)
        await owner.receive(destination_signal(signal, account_id="paper"), NOW)
        overview = await owner.operator_overview()
        assert overview.account_id == "paper"
        assert overview.broker_identity == "paper-demo"
        assert overview.entry_permission == "disabled"
        assert overview.total_exposure_usd == 0
        assert overview.balance is not None
        assert overview.balance.equity == Decimal("5120.50")
        assert overview.balance.day_change_usd == Decimal("120.50")
        assert overview.balance.cash == Decimal("4100")
        assert overview.balance.observed_at == NOW
    finally:
        await owner.close()

    raw = RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="demo",
        id="evidence",
        timestamp=NOW,
        text="original source text",
    )
    database = tmp_path / "application.db"
    source = await SQLiteSourceStore.open(database)
    parser = await SQLiteExtractionStore.open(database)
    try:
        await source.add(raw)
        await parser.add(raw)
        await parser.finish(raw.identity, signal)
        assert (await source.pending_snapshot()).oldest_at is not None
        assert (await parser.pending_snapshot()).count == 1
    finally:
        await source.close()
        await parser.close()

    runtime = TradingRuntime(tmp_path)
    accounts = (await runtime.operator.account_overviews()).items
    assert len(accounts) == 1
    assert accounts[0].active_configuration is False
    assert accounts[0].readiness == "inactive_evidence"
    assert accounts[0].total_exposure_usd is None
    page = await runtime.operator.source_activity(None, 1)
    assert page.items[0].text == "original source text"
    assert page.items[0].source_revision == 1
    assert page.items[0].source_at == NOW
    assert page.items[0].decision == "trade"
    assert page.items[0].interpreted_by == "fixture"
    assert [(item.action, item.symbol, item.price) for item in page.items[0].instructions] == [
        ("buy", "ABC", Decimal("25"))
    ]
    assert page.items[0].destinations[0].account_id == "paper"
    assert page.items[0].destinations[0].instruction_outcomes == ("account_disabled",)
    assert page.next_before_seq == page.items[0].sequence
    assert not (await runtime.operator.source_activity(page.next_before_seq, 1)).items
    events = await runtime.operator.account_events("paper", None, 2)
    assert events.account_id == "paper"
    assert len(events.items) == 2
    feed = await runtime.operator.account_feed("paper", None, 50)
    assert feed.account_id == "paper"
    assert feed.next_before_seq is None


async def test_retained_account_overviews_use_stable_bounded_keyset_pages(tmp_path):
    preexisting = ("zeta", "gamma", "epsilon", "delta", "alpha")
    for account_id in preexisting:
        owner = await _open(tmp_path, FakeBroker(), account_id)
        try:
            await owner.recover_account(NOW)
        finally:
            await owner.close()

    runtime = TradingRuntime(tmp_path)
    first = await runtime.operator.account_overviews(limit=2)

    assert [item.account_id for item in first.items] == ["zeta", "gamma"]
    assert first.next_before_account_id == "gamma"

    # A key inserted below the cursor can shift later page boundaries, but it
    # cannot duplicate or omit preexisting keys. A key above the cursor belongs
    # to the already-traversed region and does not appear on a later page.
    owner = await _open(tmp_path, FakeBroker(), "eta")
    try:
        await owner.recover_account(NOW)
    finally:
        await owner.close()
    owner = await _open(tmp_path, FakeBroker(), "zulu")
    try:
        await owner.recover_account(NOW)
    finally:
        await owner.close()

    second = await runtime.operator.account_overviews(
        before_account_id=first.next_before_account_id, limit=2
    )
    assert [item.account_id for item in second.items] == ["eta", "epsilon"]
    assert second.next_before_account_id == "epsilon"
    third = await runtime.operator.account_overviews(
        before_account_id=second.next_before_account_id, limit=2
    )
    assert [item.account_id for item in third.items] == ["delta", "alpha"]
    assert third.next_before_account_id is None
    traversed = [item.account_id for page in (first, second, third) for item in page.items]
    assert "zulu" not in traversed
    assert traversed.count("eta") == 1
    assert all(traversed.count(account_id) == 1 for account_id in preexisting)

    with pytest.raises(ValueError, match="account overview page"):
        await runtime.operator.account_overviews(limit=101)
    with pytest.raises(ValueError, match="account overview page"):
        await runtime.operator.account_overviews(limit=True)
    with pytest.raises(ValueError, match="account overview page"):
        await runtime.operator.account_overviews(before_account_id="", limit=2)


async def test_equity_history_is_asked_of_the_broker_at_most_once_a_minute(tmp_path):
    broker = FakeBroker()
    calls = []

    def equity_history(window):
        calls.append(window)
        return EquityHistory(window=window, base_value=Decimal(5000), points=())

    today = HistoryWindow(range="day")
    friday = HistoryWindow(range="day", day=dt.date(2026, 9, 25))
    month = HistoryWindow(range="month")
    broker.equity_history = equity_history
    owner = await _open(tmp_path, broker)
    try:
        first = await owner.equity_history(today, NOW)
        assert await owner.equity_history(today, NOW + dt.timedelta(seconds=59)) == first
        await owner.equity_history(month, NOW)
        await owner.equity_history(friday, NOW)
        await owner.equity_history(today, NOW + dt.timedelta(seconds=60))
    finally:
        await owner.close()
    assert calls == [today, month, friday, today]


def test_account_history_says_which_control_the_owner_changed():
    from copytrading_engine.execution.domain.events import AccountControlChanged, JournalEvent
    from copytrading_engine.execution.domain.lifecycle import (
        AccountControlCommand,
        AccountControlResult,
    )
    from copytrading_engine.execution.presentation.operator_views import event_page

    def changed(action: str, recovery: str | None = None) -> JournalEvent:
        command = AccountControlCommand(
            command_id=f"cmd-{action}",
            account_id="paper",
            action=action,
            recovery_preference=recovery,
        )
        return JournalEvent(
            at=NOW,
            payload=AccountControlChanged(
                result=AccountControlResult(
                    command=command,
                    applied_at=NOW,
                    entry_permission="enabled",
                    recovery_preference=recovery or "manual",
                )
            ),
        )

    page = event_page(
        "paper", ((2, changed("set_recovery", "automatic")), (1, changed("resume"))), 50
    )
    assert [(item.kind, item.reason, item.status) for item in page.items] == [
        ("account_control_changed", "set_recovery", "automatic"),
        ("account_control_changed", "resume", None),
    ]


async def _restarted_with_entries_on(tmp_path, broker, preference, monkeypatch):
    """An account whose entries were on, opened again as after a restart, during regular hours."""
    datetime_type = dt.datetime
    clock = {"at": datetime_type(2026, 1, 5, 15, 0, tzinfo=dt.UTC)}

    class MovableDateTime(datetime_type):
        @classmethod
        def now(cls, tz=None):
            at = clock["at"]
            return at if tz is None else at.astimezone(tz)

    monkeypatch.setattr(dt, "datetime", MovableDateTime)
    now = clock["at"]
    owner = await _open(tmp_path, broker)
    try:
        await owner.recover_account(now)
        await owner.control_account(_command("pref", "set_recovery", preference), now)
        await owner.control_account(_command("enable", "resume"), now)
    finally:
        await owner.close()
    return await _open(tmp_path, broker), now, clock


async def test_a_buy_during_manual_recovery_waits_for_resume_instead_of_being_dropped(
    tmp_path, monkeypatch
):
    broker = FakeBroker()
    owner, now, clock = await _restarted_with_entries_on(tmp_path, broker, "manual", monkeypatch)
    try:
        await owner.recover_account(now)
        assert (await owner.account_status()).readiness == "manual_resume_required"
        buy = StockSignal.model_validate(event("after-restart", price="25.10", timestamp=now))
        await owner.receive(destination_signal(buy, account_id="paper"), now)
        await owner.cycle(now, halted=False)
        assert broker.calls == 0
        part = (await owner.observation()).ledger.messages["discord:demo:after-restart"].parts[0]
        assert isinstance(part, Pending), part

        # The owner resumes within the signal's age: the buy goes through the normal rules.
        later = now + dt.timedelta(seconds=30)
        clock["at"] = later
        await owner.control_account(_command("resume-after-restart", "resume"), later)
        await owner.cycle(later, halted=False)
        assert broker.calls == 1
        bought = (await owner.observation()).ledger.messages["discord:demo:after-restart"]
        assert isinstance(bought.parts[0], OrderLinked)
    finally:
        await owner.close()


async def test_a_buy_that_ages_out_waiting_for_resume_says_it_waited_for_the_owner(
    tmp_path, monkeypatch
):
    broker = FakeBroker()
    owner, now, clock = await _restarted_with_entries_on(tmp_path, broker, "manual", monkeypatch)
    try:
        await owner.recover_account(now)
        buy = StockSignal.model_validate(event("too-late", price="25.10", timestamp=now))
        await owner.receive(destination_signal(buy, account_id="paper"), now)
        await owner.cycle(now, halted=False)
        clock["at"] = now + dt.timedelta(minutes=5)
        await owner.cycle(clock["at"], halted=False)
        assert broker.calls == 0
        part = (await owner.observation()).ledger.messages["discord:demo:too-late"].parts[0]
        assert part.reason == "stale_waiting_for_resume"
    finally:
        await owner.close()


async def test_a_buy_during_automatic_recovery_trades_once_the_checks_pass(tmp_path, monkeypatch):
    broker = FakeBroker()
    owner, now, clock = await _restarted_with_entries_on(tmp_path, broker, "automatic", monkeypatch)
    try:
        # The post lands before this session's recovery checks ran.
        buy = StockSignal.model_validate(event("early", price="25.10", timestamp=now))
        await owner.receive(destination_signal(buy, account_id="paper"), now)
        await owner.cycle(now, halted=False)
        assert broker.calls == 0
        part = (await owner.observation()).ledger.messages["discord:demo:early"].parts[0]
        assert isinstance(part, Pending), part

        clock["at"] = now + dt.timedelta(seconds=5)
        await owner.recover_account(clock["at"])
        await owner.cycle(clock["at"], halted=False)
        assert broker.calls == 1
    finally:
        await owner.close()
