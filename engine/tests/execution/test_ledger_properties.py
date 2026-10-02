"""Generated fractional fills exercise accounting across failures and restarts."""

from decimal import Decimal

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.recovery import ManualSale

from .builders import NOW, deliver, event, manual_sale, system_with_queued_buy
from .fakes import MemoryRepository

MICRO = Decimal("0.000001")
FILL_STEPS = st.lists(st.integers(min_value=1, max_value=4_000_000), min_size=1, max_size=8)


@settings(max_examples=50, deadline=None)
@given(buy_steps=FILL_STEPS, sell_steps=FILL_STEPS, fail_commits=st.booleans())
def test_fills_conserve_shares_through_replay_failure_and_restart(
    buy_steps, sell_steps, fail_commits
):
    engine, broker, repository = system_with_queued_buy()
    broker.auto_fill = False
    engine.process(NOW)

    for side, steps in (("buy", buy_steps), ("sell", sell_steps)):
        if side == "sell":
            deliver(engine, event("exit", "close", "27", "25"))
        order = engine.pending()[0]
        if side == "sell":
            assert order.type == "market"
            assert order.limit_price is None
        for units in sorted(set(steps) | {4_000_000}):
            quantity = MICRO * units
            broker.fill(order.client_id, str(quantity))
            if fail_commits:
                before = engine.ledger.snapshot()
                events_before = list(repository.events)
                repository.fail_event = "order_update"
                with pytest.raises(RuntimeError, match="persistence"):
                    engine.reconcile(NOW)
                assert engine.ledger.snapshot() == before == repository.load()
                assert repository.events == events_before
                repository.fail_event = None

            engine.reconcile(NOW)
            expected = quantity if side == "buy" else Decimal(4) - quantity
            assert engine.ledger.owned("ABC") == expected == broker.holdings["ABC"]
            assert engine.ledger.snapshot() == repository.load()
            events_before = list(repository.events)
            engine.reconcile(NOW)
            assert repository.events == events_before

            repository = MemoryRepository(repository.snapshot_json)
            engine = CopyEngine(repository, broker, engine.config)
            engine.bind(NOW)
            engine.reconcile(NOW)
            assert engine.ledger.owned("ABC") == expected
            assert not repository.events
            assert broker.calls == (1 if side == "buy" else 2)

    assert not engine.pending()
    assert engine.ledger.owned("ABC") == 0


@settings(max_examples=50, deadline=None)
@given(units=st.integers(min_value=1, max_value=4_000_000))
def test_manual_sales_conserve_fractional_shares_and_replay_once(units):
    engine, broker, repository = system_with_queued_buy()
    engine.process(NOW)
    before = engine.ledger.snapshot()
    quantity = MICRO * units
    evidence = manual_sale(engine).model_dump()
    evidence["order"].update(qty=quantity, filled_qty=quantity)
    sale = ManualSale.model_validate(evidence)
    repository.fail_event = "manual_sale_recorded"
    with pytest.raises(RuntimeError, match="persistence"):
        engine.ledger.record_manual_sale(sale)
    assert engine.ledger.snapshot() == before == repository.load()

    repository.fail_event = None
    engine.ledger.record_manual_sale(sale)
    after = engine.ledger.snapshot()
    assert engine.ledger.owned("ABC") + quantity == Decimal(4)
    assert after.orders == before.orders
    assert after.messages == before.messages
    assert after == repository.load()
    restarted_repository = MemoryRepository(repository.snapshot_json)
    restarted = CopyEngine(restarted_repository, broker, engine.config)
    restarted.ledger.record_manual_sale(sale)
    assert restarted.ledger.snapshot() == after
    assert not restarted_repository.events
    assert broker.calls == 1
