"""The owner sells one copied lot: a fresh preview first, then one durable confirmation."""

import datetime as dt
from decimal import Decimal
from pathlib import Path

import pytest

from copytrading_engine.execution.adapters.sqlite_ledger import Store
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.lot_sales import LotSaleApplication
from copytrading_engine.execution.domain.lot_sales import (
    LotSaleConfirmation,
    LotSalePreviewRequest,
)
from copytrading_engine.execution.domain.market import Quote
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.presentation.operator_views import account_overview
from copytrading_engine.shared.queue_snapshot import QueueSnapshot
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, event, receive
from .fakes import FakeBroker, MemoryRepository


class QuotedBroker(FakeBroker):
    def __init__(self) -> None:
        super().__init__()
        self.bid = Decimal("26.10")
        self.quote_time = NOW

    def quote(self, symbol: str) -> Quote:
        return Quote(
            feed="iex", bid=self.bid, ask=self.bid + Decimal("0.02"), timestamp=self.quote_time
        )


def owned_lot(
    tmp_path: Path,
    *,
    sqlite: bool = False,
    copy_exits: bool = True,
    recovery_ready: bool = True,
):
    broker = QuotedBroker()
    store = Store(tmp_path / "execution.sqlite3") if sqlite else MemoryRepository()
    if sqlite:
        store.bind_identity("paper-demo", "paper")
    engine = CopyEngine(store, broker, CopyConfig(sources=("discord:demo",), copy_exits=copy_exits))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    engine.reconcile(NOW)
    lot_id, lot = next(iter(engine.ledger.snapshot().lots.items()))
    app = LotSaleApplication(
        engine,
        local_account_id="paper-demo",
        broker_account_id="paper-demo",
        environment="paper",
        halted=lambda: False,
        entry_block_reason=lambda: None,
        recovery_ready=lambda: recovery_ready,
        stopping=lambda: False,
    )
    return engine, broker, app, lot_id, lot


def preview_request(lot_id: str, qty: Decimal, preview_id: str = "sale-preview-1"):
    return LotSalePreviewRequest(
        preview_id=preview_id, account_id="paper-demo", lot_id=lot_id, qty=qty
    )


def confirmation(preview_id: str = "sale-preview-1", command_id: str = "sale-1"):
    return LotSaleConfirmation(
        command_id=command_id, preview_id=preview_id, account_id="paper-demo", actor="owner"
    )


def test_selling_a_whole_lot_sells_its_remaining_shares_at_market_and_closes_it(tmp_path):
    engine, broker, app, lot_id, lot = owned_lot(tmp_path)
    submitted_before = broker.calls

    preview = app.preview(preview_request(lot_id, lot.remaining_qty), NOW)
    assert preview.reasons == ()
    assert preview.plan is not None
    assert preview.plan.lot_id == lot_id
    assert preview.plan.qty == lot.remaining_qty
    assert preview.plan.type == "market"
    assert broker.calls == submitted_before, "a preview never touches the broker"

    result = app.confirm(confirmation(), NOW + dt.timedelta(seconds=2))
    assert result.status == "filled"
    assert broker.calls == submitted_before + 1
    snapshot = engine.ledger.snapshot()
    assert snapshot.lots[lot_id].remaining_qty == 0
    sale_order = snapshot.orders[result.client_id or ""]
    assert sale_order.lot_id == lot_id
    assert sale_order.message_id == snapshot.orders[lot_id].message_id, "filed under its post"

    overview = account_overview(
        snapshot,
        None,
        QueueSnapshot(0, None, 0),
        local_account_id="paper-demo",
        active_configuration=True,
        readiness="ready",
        balance=None,
    )
    assert all(position.lots == () for position in overview.positions)


def test_part_of_a_lot_can_be_sold_and_the_rest_stays_attributed(tmp_path):
    engine, _, app, lot_id, lot = owned_lot(tmp_path)

    app.preview(preview_request(lot_id, Decimal("1")), NOW)
    result = app.confirm(confirmation(), NOW + dt.timedelta(seconds=2))

    assert result.status == "filled"
    assert result.filled_qty == Decimal("1")
    assert engine.ledger.snapshot().lots[lot_id].remaining_qty == lot.remaining_qty - 1


def test_a_lot_sale_works_when_exits_are_not_copied(tmp_path):
    _, _, app, lot_id, lot = owned_lot(tmp_path, copy_exits=False)

    preview = app.preview(preview_request(lot_id, lot.remaining_qty), NOW)

    assert preview.reasons == ()


def test_confirming_twice_places_one_order(tmp_path):
    _, broker, app, lot_id, lot = owned_lot(tmp_path)
    app.preview(preview_request(lot_id, lot.remaining_qty), NOW)
    first = app.confirm(confirmation(), NOW + dt.timedelta(seconds=2))
    calls = broker.calls

    again = app.confirm(confirmation(), NOW + dt.timedelta(seconds=3))

    assert again.sale == first.sale
    assert broker.calls == calls


def test_an_expired_preview_is_rejected_without_an_order(tmp_path):
    engine, broker, app, lot_id, lot = owned_lot(tmp_path)
    app.preview(preview_request(lot_id, lot.remaining_qty), NOW)
    calls = broker.calls

    result = app.confirm(confirmation(), NOW + dt.timedelta(seconds=31))

    assert result.status == "rejected"
    assert result.reason == "preview_expired"
    assert broker.calls == calls
    assert engine.ledger.snapshot().lots[lot_id].remaining_qty == lot.remaining_qty


def test_a_changed_account_since_the_preview_is_rejected(tmp_path):
    _, broker, app, lot_id, lot = owned_lot(tmp_path)
    app.preview(preview_request(lot_id, lot.remaining_qty), NOW)
    broker.holdings["XYZ"] = Decimal("3")
    calls = broker.calls

    result = app.confirm(confirmation(), NOW + dt.timedelta(seconds=2))

    assert result.status == "rejected"
    assert result.reason == "account_facts_changed"
    assert broker.calls == calls


def test_pending_recovery_blocks_the_sale(tmp_path):
    _, _, app, lot_id, lot = owned_lot(tmp_path, recovery_ready=False)

    preview = app.preview(preview_request(lot_id, lot.remaining_qty), NOW)

    assert preview.plan is None
    assert "recovery_pending" in preview.reasons


def test_a_stale_quote_blocks_the_sale(tmp_path):
    _, broker, app, lot_id, lot = owned_lot(tmp_path)
    broker.quote_time = NOW - dt.timedelta(minutes=5)

    preview = app.preview(preview_request(lot_id, lot.remaining_qty), NOW)

    assert preview.plan is None
    assert preview.reasons == ("quote_stale",)


def test_an_unknown_lot_cannot_be_previewed(tmp_path):
    _, _, app, _, _ = owned_lot(tmp_path)

    with pytest.raises(ValueError, match="Lot is unavailable"):
        app.preview(preview_request("copy-unknown", Decimal("1")), NOW)


def test_a_lot_sale_survives_a_restart_without_a_second_order(tmp_path):
    engine, broker, app, lot_id, lot = owned_lot(tmp_path, sqlite=True)
    original = engine.ledger._repository
    app.preview(preview_request(lot_id, lot.remaining_qty), NOW)
    first = app.confirm(confirmation(), NOW + dt.timedelta(seconds=2))
    calls = broker.calls

    reopened = Store(tmp_path / "execution.sqlite3")
    reopened.bind_identity("paper-demo", "paper")
    restored = CopyEngine(reopened, broker, CopyConfig(sources=("discord:demo",)))
    restored_app = LotSaleApplication(
        restored,
        local_account_id="paper-demo",
        broker_account_id="paper-demo",
        environment="paper",
        halted=lambda: False,
        entry_block_reason=lambda: None,
        recovery_ready=lambda: True,
        stopping=lambda: False,
    )
    again = restored_app.confirm(confirmation(), NOW + dt.timedelta(seconds=5))

    assert again.status == first.status == "filled"
    assert broker.calls == calls
    assert restored.ledger.snapshot().lots[lot_id].remaining_qty == 0
    reopened.close()
    original.close()
