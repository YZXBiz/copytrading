"""Entries size to their route's budget, shared caps, cash, and tolerated limit."""

import datetime as dt
from decimal import Decimal

import pytest
from pydantic import ValidationError

from copytrading_engine.execution.adapters.alpaca.models import (
    decode_broker_order,
)
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.ports import BrokerError
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.domain.sizing import (
    RouteConnection,
)
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, deliver, destination_signal, event, evidence, set_tolerance
from .fakes import FakeBroker, MemoryRepository


def test_fixed_budget_ignores_source_fraction(system):
    engine, broker, _ = system
    message = event()
    message["instructions"][0]["fraction"] = "1"
    message["evidence"][0]["fraction"] = "1"
    deliver(engine, message)
    order = next(iter(broker.orders.values()))
    assert Decimal(order["qty"]) * Decimal(order["limit_price"]) == Decimal("100")


def test_each_account_sizes_a_call_from_its_own_full_position():
    signal_data = event()
    signal_data["instructions"][0]["fraction"] = "0.3333333333333333333333333333"
    signal_data["evidence"][0]["fraction"] = "0.3333333333333333333333333333"
    signal = StockSignal.model_validate(signal_data)
    config = CopyConfig(
        sources=["discord:demo"],
        max_order_usd=Decimal(2000),
        max_symbol_usd=Decimal(2000),
        max_total_usd=Decimal(5000),
    )
    small_broker = FakeBroker()
    small_broker.account_data["id"] = "account-a"
    large_broker = FakeBroker()
    large_broker.account_data["id"] = "account-b"
    small = CopyEngine(MemoryRepository(), small_broker, config)
    large = CopyEngine(MemoryRepository(), large_broker, config)
    small.bind(NOW)
    large.bind(NOW)
    small.receive(destination_signal(signal, account_id="account-a", full_position_usd="500"), NOW)
    large.receive(
        destination_signal(signal, account_id="account-b", full_position_usd="3000"),
        NOW,
    )
    small.process(NOW)
    large.process(NOW)
    # A third of $500 is $166.66 and of $3000 is $1000, at the $25 limit.
    assert small.ledger.orders()[0].qty == Decimal("6.6664")
    assert large.ledger.orders()[0].qty == Decimal(40)


def test_compound_alert_sizes_each_entry_on_its_own(system):
    engine, broker, _ = system
    message = event()
    message["instructions"].append({**message["instructions"][0], "symbol": "DEF", "price": "20"})
    message["evidence"].append(evidence(message["instructions"][1]))
    deliver(engine, message)
    assert len(broker.orders) == 2
    assert [Decimal(o["qty"]) * Decimal(o["limit_price"]) for o in broker.orders.values()] == [
        Decimal(100),
        Decimal(100),
    ]


def test_compound_entries_obey_shared_total_cap(system):
    engine, broker, _ = system
    engine.config = CopyConfig.model_validate(engine.config.model_dump() | {"max_total_usd": "150"})
    message = event()
    message["instructions"].append({**message["instructions"][0], "symbol": "DEF", "price": "20"})
    message["evidence"].append(evidence(message["instructions"][1]))
    deliver(engine, message)
    assert broker.calls == 1
    skipped = engine.ledger.message("discord:demo:1").parts[1]
    assert isinstance(skipped, Skipped)
    assert (skipped.reason, [limit.scope for limit in skipped.exposure]) == (
        "total_exposure_cap",
        ["total"],
    )


def test_compound_entries_obey_shared_cash_when_broker_balance_is_stale(system):
    engine, broker, _ = system
    broker.account_data["cash"] = "150"
    broker.account_data["buying_power"] = "150"
    message = event()
    message["instructions"].append({**message["instructions"][0], "symbol": "DEF", "price": "20"})
    message["evidence"].append(evidence(message["instructions"][1]))
    deliver(engine, message)
    assert broker.calls == 1
    assert engine.ledger.message("discord:demo:1").parts[1] == Skipped(reason="insufficient_cash")


def compound_buys():
    message = event()
    message["instructions"].append({**message["instructions"][0], "symbol": "DEF", "price": "20"})
    message["evidence"].append(evidence(message["instructions"][1]))
    return StockSignal.model_validate(message)


def test_compound_entries_allow_fresh_broker_cash_after_fill_and_reopen(system):
    engine, broker, store = system
    broker.account_data.update(cash="200", buying_power="200")
    original_account = broker.account
    calls = 0

    def interrupted_account():
        nonlocal calls
        calls += 1
        if calls == 2:
            raise RuntimeError("interrupted between entries")
        return original_account()

    original_fill = broker.fill

    def debit_fill(client_id, qty):
        original_fill(client_id, qty)
        cost = Decimal(qty) * Decimal(broker.orders[client_id]["limit_price"])
        for field in ("cash", "buying_power"):
            broker.account_data[field] = str(Decimal(broker.account_data[field]) - cost)

    broker.account = interrupted_account
    broker.fill = debit_fill
    signal = compound_buys()
    engine.receive(destination_signal(signal), NOW)
    with pytest.raises(RuntimeError, match="interrupted"):
        engine.process(NOW)
    assert broker.calls == 1
    anchor = store.load().messages["discord:demo:1"].cash_anchor
    assert anchor is not None
    assert anchor.cash == Decimal(200)

    broker.account = original_account
    reopened = CopyEngine(MemoryRepository(store.snapshot_json), broker, engine.config)
    reopened.bind(NOW)
    reopened.process(NOW)
    assert broker.calls == 2
    assert [Decimal(o["qty"]) * Decimal(o["limit_price"]) for o in broker.orders.values()] == [
        Decimal(100),
        Decimal(100),
    ]
    assert reopened.ledger.message("discord:demo:1").cash_anchor == anchor


@pytest.mark.parametrize(
    ("first_status", "first_fill", "expected_calls"),
    [
        ("canceled", "0", 2),
        ("rejected", "0", 2),
        ("canceled", "2", 2),
        ("uncertain", "0", 1),
    ],
)
def test_compound_cash_releases_only_unspent_commitment(
    system, first_status, first_fill, expected_calls
):
    engine, broker, _ = system
    broker.account_data.update(cash="150", buying_power="150")
    broker.auto_fill = False
    original_submit = broker.submit

    def first_submission(order):
        result = original_submit(order)
        if broker.calls == 1:
            client_id = order.client_order_id
            if first_fill != "0":
                broker.fill(client_id, first_fill)
            if first_status == "uncertain":
                raise BrokerError()
            broker.orders[client_id]["status"] = first_status
            return decode_broker_order(broker.orders[client_id])
        return result

    broker.submit = first_submission
    engine.receive(destination_signal(compound_buys()), NOW)
    engine.process(NOW)
    assert broker.calls == expected_calls
    if first_status == "uncertain":
        assert engine.ledger.message("discord:demo:1").parts[1] == Skipped(
            reason="insufficient_cash"
        )


def test_cash_anchor_commit_failure_stops_before_order_and_can_reopen(system):
    engine, broker, store = system
    store.fail_event = "cash_anchor_recorded"
    engine.receive(destination_signal(compound_buys()), NOW)
    with pytest.raises(RuntimeError, match="persistence failure"):
        engine.process(NOW)
    assert broker.calls == 0
    assert store.load().messages["discord:demo:1"].cash_anchor is None
    reopened = CopyEngine(MemoryRepository(store.snapshot_json), broker, engine.config)
    reopened.bind(NOW)
    reopened.process(NOW)
    assert broker.calls == 2
    assert reopened.ledger.message("discord:demo:1").cash_anchor is not None


def test_entry_tolerance_keeps_budget_and_source_lot_reference(system):
    engine, broker, store = system
    set_tolerance(engine)
    deliver(engine, event())
    order = next(iter(broker.orders.values()))
    assert Decimal(order["limit_price"]) == Decimal("25.25")
    assert Decimal(order["qty"]) * Decimal(order["limit_price"]) <= 100
    lot = next(iter(store.load().lots.values()))
    assert lot.entry_price == Decimal("25")
    assert Decimal(lot.average_price) == Decimal("25.25")
    original_qty = Decimal(lot.original_qty)
    deliver(engine, event("2", "reduce", "27", "25"))
    assert next(iter(store.load().lots.values())).remaining_qty == original_qty / 2
    sell = list(broker.orders.values())[-1]
    assert sell["type"] == "market"
    assert "limit_price" not in sell
    assert sell["extended_hours"] is False
    assert sell["filled_avg_price"] == "24.50"
    recorded = {order.side: order for order in store.load().orders.values()}
    assert recorded["buy"].filled_avg_price == Decimal("25.25")
    assert recorded["sell"].filled_avg_price == Decimal("24.50")
    deliver(engine, event("3", "close", "28", "25"))
    assert next(iter(store.load().lots.values())).remaining_qty == 0
    assert list(broker.orders.values())[-1]["type"] == "market"
    assert "limit_price" not in list(broker.orders.values())[-1]


def test_compound_alert_with_tolerance_applies_each_entry_budget(system):
    engine, broker, _ = system
    set_tolerance(engine)
    message = event()
    message["instructions"].append({**message["instructions"][0], "symbol": "DEF", "price": "20"})
    message["evidence"].append(evidence(message["instructions"][1]))
    deliver(engine, message)
    assert len(broker.orders) == 2
    amounts = [Decimal(o["qty"]) * Decimal(o["limit_price"]) for o in broker.orders.values()]
    assert all(Decimal(99) < amount <= Decimal(100) for amount in amounts)


def test_whole_share_sizing_uses_tolerated_limit(system):
    engine, broker, _ = system
    set_tolerance(engine)
    original_asset = broker.asset
    broker.asset = lambda symbol: original_asset(symbol).model_copy(update={"fractionable": False})
    deliver(engine, event(price="100"))
    assert broker.calls == 0  # one share at the permitted $101 would exceed the budget


def test_fill_above_permitted_ceiling_stops_processing(system):
    engine, broker, _ = system
    set_tolerance(engine)
    broker.auto_fill = False
    deliver(engine, event())
    client_id = next(iter(broker.orders))
    broker.fill(client_id, broker.orders[client_id]["qty"])
    broker.orders[client_id]["filled_avg_price"] = "25.26"
    with pytest.raises(RuntimeError, match="exceeds the saved limit"):
        engine.reconcile(NOW)


@pytest.mark.parametrize("whole_shares", [False, True])
def test_configured_500_budget_keeps_limit_price_sizing(system, whole_shares):
    engine, broker, _ = system
    engine.config = CopyConfig.model_validate(
        engine.config.model_dump()
        | {
            "max_order_usd": "500",
            "entry_pricing": {"max_above_signal_pct": "1"},
        }
    )
    original_asset = broker.asset
    broker.asset = lambda symbol: original_asset(symbol).model_copy(
        update={"fractionable": not whole_shares}
    )
    # A 1/6 call into a $3000 full position is a $500 budget.
    deliver(engine, event(price="33.12"), full_position_usd="3000")
    order = engine.ledger.orders()[0]
    assert order.limit_price == Decimal("33.45")
    assert Decimal("450") < order.qty * order.limit_price <= Decimal("500")
    if whole_shares:
        assert order.qty == 14
    later = NOW + dt.timedelta(minutes=11)
    deliver(
        engine, event(id="second", price="33.12", timestamp=later), later, full_position_usd="3000"
    )
    assert broker.calls == 1  # the configured $600 per-symbol cap still applies
    [skipped] = engine.ledger.message("discord:demo:second").parts
    assert isinstance(skipped, Skipped)
    # The skip keeps the limit it would have passed, with its numbers, for Activity to show.
    [limit] = skipped.exposure
    assert (skipped.reason, limit.scope, limit.limit) == ("symbol_exposure_cap", "symbol", 600)


@pytest.mark.parametrize("field", ["full_position_usd", "max_order_usd"])
@pytest.mark.parametrize("value", ["0", "-1", "NaN", "Infinity"])
def test_entry_sizing_configuration_rejects_invalid_money(field, value):
    def build() -> object:
        if field == "full_position_usd":
            return RouteConnection(account_id="paper-demo", full_position_usd=value)
        return CopyConfig.model_validate({"sources": ["discord:demo"], field: value})

    with pytest.raises(ValidationError, match=field):
        build()
