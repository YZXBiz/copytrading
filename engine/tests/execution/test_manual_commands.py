"""Manual previews never touch the broker; confirmations are durable before they submit."""

import datetime as dt
import json
import shutil
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

import pytest
from pydantic import SecretStr

from copytrading_engine.execution.adapters.alpaca.broker import AlpacaCredentials
from copytrading_engine.execution.adapters.owner import ExecutionOwner
from copytrading_engine.execution.adapters.sqlite_ledger import Store
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.manual_commands import ManualTradingApplication
from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.execution.domain.manual_commands import (
    ManualConfirmationRequest,
    ManualCorrectionRecord,
    ManualPreviewRequest,
)
from copytrading_engine.execution.domain.market import Quote
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.host.installation import Installation
from copytrading_engine.host.pipe.server import PipeServer
from copytrading_engine.host.pipe.services import TradingServices
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore
from copytrading_engine.host.status import EngineQueries
from copytrading_engine.shared.signals import Instruction, StockSignal
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

from .builders import NOW, destination_signal, event
from .fakes import FakeBroker, MemoryRepository


class QuotedBroker(FakeBroker):
    def __init__(self):
        super().__init__()
        self.quote_time = NOW
        self.bid = Decimal("24.99")
        self.ask = Decimal("25.00")
        self.cancel_calls = 0
        self.timeout_after_accept = False
        self.hide_lookup = False
        self.before_submit = None

    def quote(self, symbol: str) -> Quote:
        return Quote(feed="iex", bid=self.bid, ask=self.ask, timestamp=self.quote_time)

    def lookup(self, client_id):
        if self.hide_lookup:
            return None
        return super().lookup(client_id)

    def submit(self, order):
        if self.before_submit is not None:
            self.before_submit(order)
        return super().submit(order)

    def cancel(self, order_id):
        self.cancel_calls += 1
        super().cancel(order_id)


def reviewed_signal(identity: str = "review-1", timestamp: dt.datetime = NOW) -> StockSignal:
    return StockSignal(
        source="discord",
        channel_id="demo",
        id=identity,
        timestamp=timestamp,
        text="Please review the ambiguous trade details.",
        parser_profile="fixture",
        model="fixture",
        decision="review",
        reason="ambiguous_trade_details",
        evidence=(),
        instructions=(),
    )


def correction_for(
    signal: StockSignal,
    instruction: Instruction,
    *,
    correction_id: str = "correction-1",
    additional_instructions: tuple[Instruction, ...] = (),
) -> ManualCorrectionRecord:
    return ManualCorrectionRecord(
        correction_id=correction_id,
        source_id=f"{signal.source}:{signal.channel_id}:{signal.id}",
        selected_account_ids=("paper-demo",),
        revision=1,
        actor="operator",
        reason="Corrected the reviewed instruction",
        instructions=(instruction, *additional_instructions),
        source_revision=7,
        source_at=signal.timestamp,
        source_text=signal.text,
        accepted_interpretation=signal,
        recorded_at=NOW,
    )


def setup_manual(
    tmp_path: Path,
    *,
    sqlite: bool = False,
    broker: QuotedBroker | None = None,
    signal: StockSignal | None = None,
    instruction: Instruction | None = None,
    additional_instructions: tuple[Instruction, ...] = (),
):
    broker = broker or QuotedBroker()
    store = Store(tmp_path / "execution.sqlite3") if sqlite else MemoryRepository()
    if sqlite:
        store.bind_identity("paper-demo", "paper")
    engine = CopyEngine(store, broker, CopyConfig(sources=("discord:demo",)))
    engine.bind(NOW)
    signal = signal or reviewed_signal()
    engine.receive(destination_signal(signal, account_id="paper-demo"), NOW)
    instruction = instruction or Instruction(
        action="buy", symbol="ABC", price=Decimal("25"), fraction=Decimal("0.25")
    )
    correction = correction_for(
        signal, instruction, additional_instructions=additional_instructions
    )
    engine.ledger.record_manual_correction(correction)
    app = ManualTradingApplication(
        engine,
        local_account_id="paper-demo",
        broker_account_id="paper-demo",
        environment="paper",
        halted=lambda: False,
        entry_block_reason=lambda: None,
        recovery_ready=lambda: True,
        stopping=lambda: False,
    )
    return engine, broker, store, app, correction


def preview_request(correction: ManualCorrectionRecord, preview_id="preview-1"):
    return ManualPreviewRequest(
        preview_id=preview_id,
        account_id="paper-demo",
        correction_id=correction.correction_id,
        instruction_index=0,
    )


def confirmation_request(preview_id="preview-1", command_id="command-1"):
    return ManualConfirmationRequest(
        command_id=command_id,
        preview_id=preview_id,
        account_id="paper-demo",
        actor="operator",
    )


async def open_manual_owner(tmp_path: Path, broker: QuotedBroker) -> ExecutionOwner:
    return await ExecutionOwner.open(
        tmp_path / "accounts" / "paper-demo",
        AlpacaCredentials(key=SecretStr("test"), secret=SecretStr("test")),
        CopyConfig(sources=("discord:demo",)),
        environment="paper",
        broker_factory=lambda _credentials, _environment: broker,
        account_lock_root=tmp_path / "locks",
    )


def test_preview_maps_known_broker_failure_to_safe_market_facts_reason(tmp_path):
    _engine, broker, store, app, correction = setup_manual(tmp_path)

    def fail_asset(_symbol):
        raise BrokerError(503)

    broker.asset = fail_asset
    preview = app.preview(preview_request(correction), NOW)

    assert preview.plan is None
    assert "market_facts_unavailable" in preview.reasons
    assert "Alpaca HTTP" not in " ".join(preview.reasons)
    assert broker.calls == 0
    assert store.load().orders == {}
    assert store.load().manual_commands == {}


def test_unexpected_preview_failure_is_diagnostic_and_never_submits(tmp_path, caplog):
    engine, broker, store, app, correction = setup_manual(tmp_path)
    secret_text = "private response token=do-not-log"

    def fail_decision(*_args, **_kwargs):
        raise RuntimeError(secret_text)

    engine.decide = fail_decision
    preview = app.preview(preview_request(correction), NOW)

    assert preview.plan is None
    assert preview.reasons == ("preview_unavailable",)
    assert secret_text not in str(preview.model_dump(mode="json"))
    assert secret_text not in caplog.text
    assert "Unexpected manual preview failure" in caplog.text
    assert broker.calls == 0
    snapshot = store.load()
    assert snapshot.orders == {}
    assert snapshot.manual_commands == {}


def test_unexpected_quote_failure_is_diagnostic_and_never_submits(tmp_path, caplog):
    _engine, broker, store, app, correction = setup_manual(tmp_path)
    secret_text = "private quote response token=do-not-log"

    def fail_quote(_symbol):
        raise RuntimeError(secret_text)

    broker.quote = fail_quote
    preview = app.preview(preview_request(correction), NOW)

    assert preview.plan is None
    assert "preview_unavailable" in preview.reasons
    assert secret_text not in str(preview.model_dump(mode="json"))
    assert secret_text not in caplog.text
    assert "Unexpected manual preview failure" in caplog.text
    assert broker.calls == 0
    snapshot = store.load()
    assert snapshot.orders == {}
    assert snapshot.manual_commands == {}


def test_known_quote_broker_failure_remains_a_quote_unavailable_outcome(tmp_path):
    _engine, broker, store, app, correction = setup_manual(tmp_path)

    def fail_quote(_symbol):
        raise BrokerError(503)

    broker.quote = fail_quote
    preview = app.preview(preview_request(correction), NOW)

    assert preview.plan is None
    assert "quote_unavailable" in preview.reasons
    assert "preview_unavailable" not in preview.reasons
    assert broker.calls == 0
    assert store.load().orders == {}


async def test_manual_preference_requires_current_resume_and_keeps_exit_ready_after_pause(
    tmp_path,
):
    broker = QuotedBroker()
    now = NOW
    owner = await open_manual_owner(tmp_path, broker)
    try:
        await owner.recover_account(now)
        signal = reviewed_signal("resume-buy", now)
        await owner.receive(destination_signal(signal, account_id="paper-demo"), now)
        correction = correction_for(
            signal,
            Instruction(action="buy", symbol="ABC", price=Decimal("25"), fraction=Decimal("1")),
        )
        await owner.record_manual_correction(correction)

        before_resume = await owner.preview_manual_order(
            preview_request(correction, "before-resume"), now
        )
        assert before_resume.plan is None
        assert "recovery_pending" in before_resume.reasons
        assert broker.calls == 0

        resumed = await owner.control_account(
            AccountControlCommand(
                command_id="manual-resume",
                account_id="paper-demo",
                action="resume",
            ),
            now,
        )
        assert resumed.entry_permission == "enabled"
        assert resumed.recovery_preference == "manual"
        ready = await owner.preview_manual_order(preview_request(correction, "after-resume"), now)
        assert ready.plan is not None
        assert ready.reasons == ()
        result = await owner.confirm_manual_order(
            confirmation_request("after-resume", "manual-buy"),
            now + dt.timedelta(seconds=1),
        )
        assert result.status == "filled"
        assert broker.calls == 1
    finally:
        await owner.close()

    owner = await open_manual_owner(tmp_path, broker)
    try:
        restarted_at = now + dt.timedelta(seconds=2)
        await owner.recover_account(restarted_at)
        exit_signal = reviewed_signal("pause-exit", restarted_at)
        await owner.receive(destination_signal(exit_signal, account_id="paper-demo"), restarted_at)
        exit_instruction = Instruction(
            action="close",
            symbol="ABC",
            price=Decimal("24.99"),
            entry_price=Decimal("25"),
            fraction=Decimal("1"),
        )
        exit_correction = correction_for(
            exit_signal, exit_instruction, correction_id="pause-exit-correction"
        )
        await owner.record_manual_correction(exit_correction)
        before_resume = await owner.preview_manual_order(
            preview_request(exit_correction, "before-restart-resume"), restarted_at
        )
        assert before_resume.plan is None
        assert "recovery_pending" in before_resume.reasons
        assert broker.calls == 1

        resumed = await owner.control_account(
            AccountControlCommand(
                command_id="manual-resume-after-restart",
                account_id="paper-demo",
                action="resume",
            ),
            restarted_at + dt.timedelta(seconds=1),
        )
        assert resumed.recovery_preference == "manual"
        await owner.control_account(
            AccountControlCommand(
                command_id="manual-pause",
                account_id="paper-demo",
                action="pause",
            ),
            restarted_at + dt.timedelta(seconds=2),
        )
        exit_preview = await owner.preview_manual_order(
            preview_request(exit_correction, "pause-exit-preview"),
            restarted_at + dt.timedelta(seconds=3),
        )
        assert exit_preview.plan is not None
        assert exit_preview.plan.side == "sell"
        assert exit_preview.reasons == ()
        exit_result = await owner.confirm_manual_order(
            confirmation_request("pause-exit-preview", "pause-exit-command"),
            restarted_at + dt.timedelta(seconds=4),
        )
        assert exit_result.status == "filled"
        assert broker.calls == 2
    finally:
        await owner.close()


async def test_automatic_recovery_keeps_manual_preview_ready_after_clean_restart(tmp_path):
    broker = QuotedBroker()
    now = NOW
    owner = await open_manual_owner(tmp_path, broker)
    try:
        await owner.recover_account(now)
        await owner.control_account(
            AccountControlCommand(
                command_id="automatic-preference",
                account_id="paper-demo",
                action="set_recovery",
                recovery_preference="automatic",
            ),
            now,
        )
        await owner.control_account(
            AccountControlCommand(
                command_id="automatic-resume",
                account_id="paper-demo",
                action="resume",
            ),
            now,
        )
    finally:
        await owner.close()

    owner = await open_manual_owner(tmp_path, broker)
    try:
        restarted_at = now + dt.timedelta(seconds=1)
        await owner.recover_account(restarted_at)
        signal = reviewed_signal("automatic-manual-buy", restarted_at)
        await owner.receive(destination_signal(signal, account_id="paper-demo"), restarted_at)
        correction = correction_for(
            signal,
            Instruction(action="buy", symbol="ABC", price=Decimal("25"), fraction=Decimal("1")),
            correction_id="automatic-manual-correction",
        )
        await owner.record_manual_correction(correction)

        preview = await owner.preview_manual_order(
            preview_request(correction, "automatic-manual-preview"), restarted_at
        )
        assert preview.plan is not None
        assert preview.reasons == ()
        result = await owner.confirm_manual_order(
            confirmation_request("automatic-manual-preview", "automatic-manual-command"),
            restarted_at + dt.timedelta(seconds=1),
        )
        assert result.status == "filled"
        assert broker.calls == 1
    finally:
        await owner.close()


async def test_symbol_incident_blocks_only_affected_symbol_after_manual_resume(tmp_path):
    broker = QuotedBroker()
    owner = await open_manual_owner(tmp_path, broker)
    try:
        await owner.recover_account(NOW)
        await owner.control_account(
            AccountControlCommand(
                command_id="symbol-incident-resume",
                account_id="paper-demo",
                action="resume",
            ),
            NOW,
        )

        # Open a durable AAPL incident, then restore broker positions so the
        # current account-wide ownership comparison is clean.
        broker.holdings["AAPL"] = Decimal("1")
        await owner.cycle(NOW + dt.timedelta(seconds=1), halted=False)
        broker.holdings.pop("AAPL")
        observation = await owner.cycle(NOW + dt.timedelta(seconds=2), halted=False)
        incidents = tuple(observation.ledger.ownership_incidents.values())
        assert any(incident.symbol == "AAPL" and not incident.resolved for incident in incidents)
        assert observation.position_audit is not None
        assert observation.position_audit.matched

        async def correction_for_symbol(symbol: str, identity: str) -> ManualCorrectionRecord:
            at = NOW + dt.timedelta(seconds=3)
            signal = reviewed_signal(identity, at)
            await owner.receive(destination_signal(signal, account_id="paper-demo"), at)
            correction = correction_for(
                signal,
                Instruction(
                    action="buy",
                    symbol=symbol,
                    price=Decimal("25"),
                    fraction=Decimal("0.25"),
                ),
                correction_id=f"{identity}-correction",
            )
            await owner.record_manual_correction(correction)
            return correction

        clean_correction = await correction_for_symbol("MSFT", "clean-symbol")
        affected_correction = await correction_for_symbol("AAPL", "affected-symbol")
        clean_preview = await owner.preview_manual_order(
            preview_request(clean_correction, "clean-symbol-preview"),
            NOW + dt.timedelta(seconds=4),
        )
        affected_preview = await owner.preview_manual_order(
            preview_request(affected_correction, "affected-symbol-preview"),
            NOW + dt.timedelta(seconds=4),
        )

        assert clean_preview.plan is not None
        assert clean_preview.reasons == ()
        assert affected_preview.plan is None
        assert "ownership_incident" in affected_preview.reasons
        assert broker.calls == 0
    finally:
        await owner.close()


def test_manual_preview_has_no_broker_mutation_and_confirm_is_durable_before_submit(tmp_path):
    engine, broker, store, app, correction = setup_manual(tmp_path, sqlite=True)
    message_before = engine.ledger.message(correction.source_id)
    broker.before_submit = lambda _: _assert_durable_intent(store, "command-1")

    preview = app.preview(preview_request(correction), NOW)
    assert preview.plan is not None
    assert preview.reasons == ()
    assert broker.calls == 0
    assert broker.cancel_calls == 0
    assert engine.ledger.message(correction.source_id).cash_anchor is None

    result = app.confirm(confirmation_request(), NOW + dt.timedelta(seconds=1))
    assert result.status == "filled"
    assert broker.calls == 1
    assert store.load().manual_commands["command-1"].state == "prepared"
    message_after = engine.ledger.message(correction.source_id)
    assert message_after == message_before

    store.close()
    reopened = Store(tmp_path / "execution.sqlite3")
    reopened.bind_identity("paper-demo", "paper")
    restored = CopyEngine(reopened, broker, CopyConfig(sources=("discord:demo",)))
    restored.bind(NOW + dt.timedelta(seconds=2))
    restored_app = ManualTradingApplication(
        restored,
        local_account_id="paper-demo",
        broker_account_id="paper-demo",
        environment="paper",
        halted=lambda: False,
        entry_block_reason=lambda: None,
        recovery_ready=lambda: True,
        stopping=lambda: False,
    )
    duplicate = restored_app.confirm(confirmation_request(), NOW + dt.timedelta(seconds=3))
    assert duplicate.status == "filled"
    assert broker.calls == 1
    reopened.close()


def _assert_durable_intent(store, command_id):
    snapshot = store.load()
    command = snapshot.manual_commands[command_id]
    assert command.client_id in snapshot.orders
    assert snapshot.orders[command.client_id].submit_started_at is not None


def test_confirmation_rejects_price_change_and_stable_id_conflict(tmp_path):
    _engine, broker, _, app, correction = setup_manual(tmp_path)
    app.preview(preview_request(correction), NOW)
    broker.ask = Decimal("25.01")

    result = app.confirm(confirmation_request(), NOW + dt.timedelta(seconds=1))
    assert result.status == "rejected"
    assert result.reason == "account_facts_changed"
    assert broker.calls == 0


def test_changed_quote_requires_fresh_preview_and_new_confirmation_identity(tmp_path):
    _engine, broker, _, app, correction = setup_manual(tmp_path)
    old_preview = app.preview(preview_request(correction, "preview-old"), NOW)
    broker.ask = Decimal("24.99")
    broker.quote_time = NOW + dt.timedelta(seconds=2)

    stale = app.confirm(
        confirmation_request("preview-old", "command-old"), NOW + dt.timedelta(seconds=3)
    )
    assert stale.status == "rejected"
    assert stale.reason == "account_facts_changed"
    assert broker.calls == 0

    refreshed = app.preview(
        preview_request(correction, "preview-new"), NOW + dt.timedelta(seconds=4)
    )
    assert refreshed.plan == old_preview.plan
    assert refreshed.quote is not None
    assert refreshed.quote.timestamp == broker.quote_time
    assert refreshed.fresh_price == broker.ask
    accepted = app.confirm(
        confirmation_request("preview-new", "command-new"), NOW + dt.timedelta(seconds=5)
    )
    assert accepted.status == "filled"
    assert accepted.command.request.command_id == "command-new"
    assert broker.calls == 1


@pytest.mark.parametrize(
    ("gate", "expected_reason"),
    [("paused", "account_entries_paused"), ("halted", "halted")],
)
def test_manual_entry_cannot_override_pause_or_safety_halt(tmp_path, gate, expected_reason):
    _engine, broker, _, app, correction = setup_manual(tmp_path)
    if gate == "paused":
        app.entry_block_reason = lambda: "account_entries_paused"
    else:
        app.halted = lambda: True

    preview = app.preview(preview_request(correction), NOW)
    assert preview.plan is None
    assert expected_reason in preview.reasons
    result = app.confirm(confirmation_request(), NOW + dt.timedelta(seconds=1))
    assert result.status == "rejected"
    assert result.reason == expected_reason
    assert broker.calls == 0
    duplicate = app.confirm(confirmation_request(), NOW + dt.timedelta(seconds=2))
    assert duplicate == result
    with pytest.raises(ValueError, match="identity conflicts"):
        app.confirm(
            confirmation_request(command_id="command-1").model_copy(update={"actor": "other"}),
            NOW + dt.timedelta(seconds=3),
        )
    assert broker.calls == 0


def test_compound_same_account_confirmation_rejects_second_stale_preview(tmp_path):
    broker = QuotedBroker()
    broker.auto_fill = False
    second = Instruction(action="buy", symbol="XYZ", price=Decimal("25"), fraction=Decimal("0.25"))
    _engine, broker, _, app, correction = setup_manual(
        tmp_path, broker=broker, additional_instructions=(second,)
    )
    first_preview = app.preview(preview_request(correction, "preview-first"), NOW)
    second_preview = app.preview(
        preview_request(correction, "preview-second").model_copy(update={"instruction_index": 1}),
        NOW,
    )
    assert first_preview.plan is not None
    assert second_preview.plan is not None

    first = app.confirm(
        confirmation_request("preview-first", "command-first"), NOW + dt.timedelta(seconds=1)
    )
    second_result = app.confirm(
        confirmation_request("preview-second", "command-second"),
        NOW + dt.timedelta(seconds=2),
    )

    assert first.status == "accepted"
    assert second_result.status == "rejected"
    assert second_result.reason == "account_facts_changed"
    assert broker.calls == 1
    replay = app.confirm(
        confirmation_request("preview-first", "command-first"), NOW + dt.timedelta(seconds=3)
    )
    assert replay.status == "accepted"
    assert broker.calls == 1


def test_partial_manual_fill_blocks_a_second_overlapping_action(tmp_path):
    broker = QuotedBroker()
    broker.auto_fill = False
    _engine, broker, _, app, correction = setup_manual(tmp_path, broker=broker)
    app.preview(preview_request(correction, "partial-preview-1"), NOW)
    first = app.confirm(
        confirmation_request("partial-preview-1", "partial-command-1"),
        NOW + dt.timedelta(seconds=1),
    )
    assert first.status == "accepted"
    assert first.client_id is not None

    broker.fill(first.client_id, "1")
    second_preview = app.preview(
        preview_request(correction, "partial-preview-2"), NOW + dt.timedelta(seconds=2)
    )
    assert second_preview.plan is None
    assert "related_manual_action" in second_preview.reasons
    second = app.confirm(
        confirmation_request("partial-preview-2", "partial-command-2"),
        NOW + dt.timedelta(seconds=3),
    )

    assert second.status == "rejected"
    assert broker.calls == 1
    assert app.result("partial-command-1").status == "partially_filled"


def test_manual_decision_does_not_cancel_a_competing_pending_order(tmp_path):
    broker = QuotedBroker()
    broker.auto_fill = False
    engine, broker, _, app, correction = setup_manual(tmp_path, broker=broker)
    automatic = StockSignal.model_validate(event("competing-entry"))
    engine.receive(
        destination_signal(automatic, full_position_usd="300", account_id="paper-demo"), NOW
    )
    engine.process(NOW)
    assert broker.calls == 1

    preview = app.preview(preview_request(correction), NOW + dt.timedelta(seconds=1))

    assert preview.plan is None
    assert "wait_pending_order" in preview.reasons
    assert broker.calls == 1
    assert broker.cancel_calls == 0


@pytest.mark.parametrize(
    ("change", "expected_reason"),
    [
        ("holdings", "account_facts_changed"),
        ("configuration", "configuration_changed"),
        ("expiration", "preview_expired"),
    ],
)
def test_confirmation_rejects_changed_holdings_configuration_or_expired_preview(
    tmp_path, change, expected_reason
):
    engine, broker, _, app, correction = setup_manual(tmp_path)
    app.preview(preview_request(correction), NOW)
    confirm_at = NOW + dt.timedelta(seconds=1)
    if change == "holdings":
        broker.holdings["XYZ"] = Decimal("1")
    elif change == "configuration":
        engine.config = engine.config.model_copy(update={"max_order_usd": Decimal("90")})
    else:
        confirm_at = NOW + dt.timedelta(seconds=31)

    result = app.confirm(confirmation_request(), confirm_at)
    assert result.status == "rejected"
    assert result.reason == expected_reason
    assert broker.calls == 0


def test_cancelled_manual_order_is_reconciled_before_a_new_preview(tmp_path):
    broker = QuotedBroker()
    broker.auto_fill = False
    engine, broker, _, app, correction = setup_manual(tmp_path, broker=broker)
    app.preview(preview_request(correction), NOW)
    first = app.confirm(confirmation_request(), NOW + dt.timedelta(seconds=1))
    assert first.status == "accepted"
    assert first.client_id is not None
    engine.cancel(engine.ledger.order(first.client_id), NOW + dt.timedelta(seconds=2))

    cancelled = app.confirm(confirmation_request(), NOW + dt.timedelta(seconds=3))
    assert cancelled.status == "cancelled"
    assert broker.calls == 1
    app.preview(preview_request(correction, "preview-after-cancel"), NOW + dt.timedelta(seconds=4))
    second = app.confirm(
        confirmation_request("preview-after-cancel", "command-after-cancel"),
        NOW + dt.timedelta(seconds=5),
    )
    assert second.status == "accepted"
    assert broker.calls == 2


def test_manual_close_uses_the_matching_app_owned_lot(tmp_path):
    broker = QuotedBroker()
    engine = CopyEngine(MemoryRepository(), broker, CopyConfig(sources=("discord:demo",)))
    engine.bind(NOW)
    entry = StockSignal.model_validate(event("entry-1"))
    engine.receive(destination_signal(entry, full_position_usd="600", account_id="paper-demo"), NOW)
    engine.process(NOW)
    assert broker.holdings["ABC"] == Decimal("4")

    signal = reviewed_signal("review-exit", NOW + dt.timedelta(seconds=1))
    engine.receive(destination_signal(signal, account_id="paper-demo"), NOW)
    instruction = Instruction(
        action="close",
        symbol="ABC",
        price=Decimal("24"),
        entry_price=Decimal("25"),
        fraction=Decimal("1"),
    )
    correction = correction_for(signal, instruction, correction_id="close-1")
    engine.ledger.record_manual_correction(correction)
    app = ManualTradingApplication(
        engine,
        local_account_id="paper-demo",
        broker_account_id="paper-demo",
        environment="paper",
        halted=lambda: False,
        entry_block_reason=lambda: None,
        recovery_ready=lambda: True,
        stopping=lambda: False,
    )
    preview = app.preview(
        preview_request(correction, "exit-preview"), NOW + dt.timedelta(seconds=2)
    )
    assert preview.plan is not None
    assert preview.plan.side == "sell"
    assert preview.plan.qty == Decimal("4")
    assert preview.plan.lot_id in engine.ledger.snapshot().lots
    result = app.confirm(
        confirmation_request("exit-preview", "exit-command"), NOW + dt.timedelta(seconds=3)
    )
    assert result.status == "filled"
    assert broker.holdings["ABC"] == 0


def test_manual_exit_cannot_sell_external_only_shares(tmp_path):
    broker = QuotedBroker()
    broker.holdings["ABC"] = Decimal("4")
    signal = reviewed_signal()
    _engine, broker, _, app, correction = setup_manual(
        tmp_path,
        broker=broker,
        signal=signal,
        instruction=Instruction(
            action="close",
            symbol="ABC",
            price=Decimal("24"),
            entry_price=Decimal("25"),
            fraction=Decimal("1"),
        ),
    )
    preview = app.preview(preview_request(correction), NOW)
    assert preview.plan is None
    assert "missing_or_ambiguous_lot" in preview.reasons
    assert broker.calls == 0


def test_lost_confirmation_response_recovers_uncertain_manual_intent_after_restart(tmp_path):
    broker = QuotedBroker()
    broker.auto_fill = False
    broker.timeout_after_accept = True
    broker.hide_lookup = True
    _engine, broker, store, app, correction = setup_manual(tmp_path, sqlite=True, broker=broker)
    app.preview(preview_request(correction), NOW)
    request = confirmation_request()
    # Discard the response as if the local pipe connection closed after the
    # durable intent and broker submit completed.
    app.confirm(request, NOW + dt.timedelta(seconds=1))
    assert broker.calls == 1

    store.close()
    reopened = Store(tmp_path / "execution.sqlite3")
    reopened.bind_identity("paper-demo", "paper")
    restored = CopyEngine(reopened, broker, CopyConfig(sources=("discord:demo",)))
    restored.bind(NOW + dt.timedelta(seconds=2))
    restored_app = ManualTradingApplication(
        restored,
        local_account_id="paper-demo",
        broker_account_id="paper-demo",
        environment="paper",
        halted=lambda: False,
        entry_block_reason=lambda: None,
        recovery_ready=lambda: True,
        stopping=lambda: False,
    )
    page = restored_app.command_page(correction.source_id, limit=1)
    assert page.account_id == "paper-demo"
    assert page.source_id == correction.source_id
    assert [item.command.request.command_id for item in page.items] == [request.command_id]
    assert page.items[0].status == "uncertain"
    assert page.items[0].client_id is not None

    replayed = restored_app.confirm(request, NOW + dt.timedelta(seconds=3))
    assert replayed.status == "uncertain"
    assert broker.calls == 1

    second_request = request.model_copy(update={"command_id": "command-second-manual"})
    second = restored_app.confirm(second_request, NOW + dt.timedelta(seconds=4))
    assert second.status == "rejected"
    latest = restored_app.command_page(correction.source_id, limit=1)
    assert [item.command.request.command_id for item in latest.items] == [second_request.command_id]
    assert latest.next_before_command_id == second_request.command_id
    older = restored_app.command_page(
        correction.source_id, before_command_id=latest.next_before_command_id, limit=1
    )
    assert [item.command.request.command_id for item in older.items] == [request.command_id]
    assert older.items[0].status == "uncertain"
    reopened.close()


async def test_paused_runtime_pipe_recovers_retained_command_without_owner_or_resubmit(tmp_path):
    broker = QuotedBroker()
    broker.auto_fill = False
    broker.timeout_after_accept = True
    broker.hide_lookup = True
    account_dir = tmp_path / "accounts" / "paper-demo"
    _, broker, store, app, correction = setup_manual(account_dir, sqlite=True, broker=broker)
    app.preview(preview_request(correction), NOW)
    request = confirmation_request()
    result = app.confirm(request, NOW + dt.timedelta(seconds=1))
    assert result.status == "uncertain"
    assert broker.calls == 1
    store.close()

    retired_dir = tmp_path / "accounts" / "retired"
    retired_dir.mkdir(parents=True)
    (retired_dir / "execution.sqlite3").write_bytes(b"not an sqlite ledger")
    runtime = TradingRuntime(tmp_path)
    assert runtime.status().state == "paused"
    assert runtime._accounts == {}

    with (
        Installation(tmp_path / "application.db") as installation,
        SQLiteSelfTestStore(installation) as workflow_store,
    ):
        server = PipeServer(
            SelfTestService(workflow_store, SelfTestParser()),
            EngineQueries(workflow_store, workflow_store.installation.instance_id),
            TradingServices.of(runtime),
        )
        response = json.loads(
            await server.handle_line(
                json.dumps(
                    {
                        "version": 1,
                        "request_id": "request-after-restart",
                        "operation": "list_manual_commands",
                        "account_id": "paper-demo",
                        "source_id": correction.source_id,
                        "limit": 50,
                    }
                ).encode()
            )
        )

    assert response["ok"]["type"] == "manual_command_page"
    page = response["ok"]["commands"]
    assert page["account_id"] == "paper-demo"
    assert page["source_id"] == correction.source_id
    assert [item["command"]["request"]["command_id"] for item in page["items"]] == [
        request.command_id
    ]
    assert page["items"][0]["status"] == "uncertain"
    assert runtime.status().state == "paused"
    assert runtime._accounts == {}
    assert broker.calls == 1

    other_account = tmp_path / "accounts" / "other-account"
    other_account.mkdir()
    shutil.copy2(account_dir / "execution.sqlite3", other_account / "execution.sqlite3")

    async def list_for(account_id: str):
        with (
            Installation(tmp_path / "application.db") as installation,
            SQLiteSelfTestStore(installation) as workflow_store,
        ):
            pipe = PipeServer(
                SelfTestService(workflow_store, SelfTestParser()),
                EngineQueries(workflow_store, workflow_store.installation.instance_id),
                TradingServices.of(runtime),
            )
            return json.loads(
                await pipe.handle_line(
                    json.dumps(
                        {
                            "version": 1,
                            "request_id": f"request-account-{account_id}",
                            "operation": "list_manual_commands",
                            "account_id": account_id,
                            "source_id": correction.source_id,
                            "limit": 50,
                        }
                    ).encode()
                )
            )

    wrong_identity = await list_for("other-account")
    assert wrong_identity["error"]["code"] == "unavailable"
    unsafe_account = await list_for("../paper-demo")
    assert unsafe_account["error"]["code"] == "unavailable"

    class DormantOwner:
        async def manual_command_page(self, *_args, **_kwargs):
            raise AssertionError("inactive account owner must not be queried")

    for state in ("paused", "failed"):
        runtime._accounts["paper-demo"] = SimpleNamespace(owner=DormantOwner(), state=state)
        retained = await list_for("paper-demo")
        assert retained["ok"]["commands"]["items"][0]["status"] == "uncertain"
        runtime._accounts.clear()

    assert runtime.status().state == "paused"
    assert runtime._accounts == {}
    assert broker.calls == 1


@pytest.mark.parametrize(
    ("later", "expired"),
    [
        pytest.param(dt.timedelta(hours=4), False, id="later-the-same-trading-day"),
        pytest.param(dt.timedelta(days=1), True, id="the-next-trading-day"),
    ],
)
def test_a_waiting_call_can_be_copied_only_through_its_own_trading_day(tmp_path, later, expired):
    engine, broker, _, app, correction = setup_manual(tmp_path)
    engine.bind(NOW + later)
    broker.quote_time = NOW + later

    preview = app.preview(preview_request(correction), NOW + later)

    assert ("waiting_expired" in preview.reasons) is expired
    source = next(check for check in preview.checks if check.name == "source")
    assert source.status == ("blocked" if expired else "passed")


def test_command_history_is_read_by_the_apps_account_name():
    """The ledger records the broker's account number; history is asked for by the app's name."""
    from copytrading_engine.execution.application.manual_commands import (
        manual_command_page_from_snapshot,
    )
    from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot

    snapshot = LedgerSnapshot(account_id="8f3c1a52-alpaca-paper-account", environment="paper")
    page = manual_command_page_from_snapshot(snapshot, account_id="primary", source_id="post-1")
    assert (page.account_id, page.items, page.next_before_command_id) == ("primary", (), None)


def test_an_account_named_apart_from_its_broker_number_copies_a_call_by_hand(tmp_path):
    """The ledger records Alpaca's account number; the owner picks accounts by the app's name."""
    broker = QuotedBroker()
    broker.account_data = {**broker.account_data, "id": "8f3c1a52-alpaca-paper-account"}
    engine = CopyEngine(MemoryRepository(), broker, CopyConfig(sources=("discord:demo",)))
    engine.bind(NOW)
    signal = reviewed_signal()
    engine.receive(destination_signal(signal, account_id="primary"), NOW)
    instruction = Instruction(
        action="buy", symbol="ABC", price=Decimal("25"), fraction=Decimal("0.25")
    )
    correction = correction_for(signal, instruction).model_copy(
        update={"selected_account_ids": ("primary",)}
    )
    app = ManualTradingApplication(
        engine,
        local_account_id="primary",
        broker_account_id="8f3c1a52-alpaca-paper-account",
        environment="paper",
        halted=lambda: False,
        entry_block_reason=lambda: None,
        recovery_ready=lambda: True,
        stopping=lambda: False,
    )

    app.record_correction(correction)
    request = preview_request(correction).model_copy(update={"account_id": "primary"})
    preview = app.preview(request, NOW)
    assert preview.plan is not None, preview.reasons
    confirm = confirmation_request().model_copy(update={"account_id": "primary"})
    result = app.confirm(confirm, NOW + dt.timedelta(seconds=1))

    assert result.status != "rejected", result.reason
    assert broker.calls == 1
