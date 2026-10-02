"""Entries respect sessions, cash, and loss limits; exits of owned lots are never blocked."""

import datetime as dt
from decimal import Decimal

import pytest

from copytrading_engine.execution.adapters.alpaca.models import (
    decode_calendar,
)
from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, deliver, event, receive, set_tolerance


@pytest.mark.parametrize("kind", ["old", "future", "unknown_lot", "halt", "loss", "mismatch"])
def test_fail_closed_guards(system, kind):
    engine, broker, _ = system
    message = event()
    if kind == "old":
        message = event(timestamp=NOW - dt.timedelta(minutes=3))
    elif kind == "future":
        message = event(timestamp=NOW + dt.timedelta(minutes=3))
    elif kind == "unknown_lot":
        message = event(action="close", entry="25")
    elif kind == "loss":
        broker.account_data["equity"] = "4700"
    elif kind == "mismatch":
        broker.holdings["ABC"] = Decimal(3)
    receive(engine, StockSignal.model_validate(message), NOW)
    engine.process(NOW, halted=kind == "halt")
    assert broker.calls == 0


@pytest.mark.parametrize(
    ("instant", "expected_calls", "expected_session"),
    [
        ("2026-01-05T06:00:00-05:00", 1, "extended"),
        ("2026-01-05T18:00:00-05:00", 1, "extended"),
        ("2026-01-04T21:00:00-05:00", 1, "overnight"),
        ("2026-01-05T02:00:00-05:00", 1, "overnight"),
        ("2026-01-09T21:00:00-05:00", 0, None),
        ("2026-01-10T12:00:00-05:00", 0, None),
        ("2026-01-18T21:00:00-05:00", 0, None),
    ],
)
def test_all_supported_sessions_respect_calendar(system, instant, expected_calls, expected_session):
    engine, broker, store = system
    set_tolerance(engine)
    engine.config = CopyConfig.model_validate(engine.config.model_dump() | {"overnight": True})
    original_asset = broker.asset
    broker.asset = lambda symbol: original_asset(symbol).model_copy(
        update={"attributes": ("overnight_tradable",)}
    )

    def calendar(date):
        day = dt.date.fromisoformat(date)
        return (
            []
            if day.weekday() >= 5 or date == "2026-01-19"
            else [
                {
                    "date": date,
                    "open": "09:30",
                    "close": "16:00",
                    "session_open": "0400",
                    "session_close": "2000",
                }
            ]
        )

    broker.calendar = lambda date: decode_calendar(calendar(date))
    now = dt.datetime.fromisoformat(instant)
    deliver(engine, event(timestamp=now), now)
    assert broker.calls == expected_calls
    if expected_calls:
        order = next(iter(store.load().orders.values()))
        assert order.session == expected_session
        assert broker.orders[order.client_id]["extended_hours"] is True
        assert order.qty * order.limit_price <= 100
        if instant.startswith("2026-01-04"):
            assert order.day == dt.date(2026, 1, 5)


@pytest.mark.parametrize(
    "flags",
    [
        {},
        {"overnight_tradable": True, "overnight_halted": True},
        {"attributes": ["overnight_tradable", "overnight_halted"]},
    ],
)
def test_overnight_requires_eligible_unhalted_asset(system, flags):
    engine, broker, _ = system
    engine.config = CopyConfig.model_validate(engine.config.model_dump() | {"overnight": True})
    original_asset = broker.asset
    broker.asset = lambda symbol: original_asset(symbol).model_copy(update=flags)
    now = dt.datetime.fromisoformat("2026-01-05T21:00:00-05:00")
    deliver(engine, event(timestamp=now), now)
    assert broker.calls == 0


@pytest.mark.parametrize(
    ("cash", "buying_power", "allowed"),
    [
        ("0", "5000", False),
        ("99.99", "5000", False),
        ("5000", "99.99", False),
        ("100", "100", True),
    ],
)
def test_entry_requires_full_budget_in_cash_and_buying_power(system, cash, buying_power, allowed):
    engine, broker, store = system
    broker.account_data.update(cash=cash, buying_power=buying_power)
    deliver(engine, event())
    assert broker.calls == int(allowed)
    if not allowed:
        assert next(iter(store.load().messages.values())).parts == (
            Skipped(reason="insufficient_cash"),
        )
        assert not store.load().orders


@pytest.mark.parametrize(
    ("equity", "allowed"), [("4750.01", True), ("4750", False), ("4749.99", False)]
)
def test_daily_loss_threshold_includes_exact_boundary(system, equity, allowed):
    engine, broker, store = system
    broker.account_data.update(equity=equity, last_equity="5000")
    deliver(engine, event())
    assert broker.calls == int(allowed)
    if not allowed:
        assert next(iter(store.load().messages.values())).parts == (
            Skipped(reason="daily_loss_cap"),
        )


@pytest.mark.parametrize("restriction", ["cash", "buying_power", "loss", "halt"])
@pytest.mark.parametrize(
    ("action", "remaining"), [("reduce", Decimal("2")), ("close", Decimal("0"))]
)
def test_entry_restrictions_do_not_block_owned_lot_exits(system, restriction, action, remaining):
    engine, broker, _ = system
    deliver(engine, event())
    if restriction in {"cash", "buying_power"}:
        broker.account_data[restriction] = "0"
    elif restriction == "loss":
        broker.account_data["equity"] = "4700"
    receive(engine, StockSignal.model_validate(event("exit", action, "24", "25")), NOW)
    engine.process(NOW, halted=restriction == "halt")
    assert broker.calls == 2
    assert broker.holdings["ABC"] == remaining


@pytest.mark.parametrize("action", ["reduce", "close"])
@pytest.mark.parametrize("hour", [6, 18])
def test_exits_outside_regular_hours_sell_with_a_limit_under_the_signal(system, action, hour):
    engine, broker, _ = system
    deliver(engine, event())
    engine.config = CopyConfig.model_validate(
        engine.config.model_dump() | {"entry_pricing": {"max_above_signal_pct": "1"}}
    )
    broker.calendar = lambda date: decode_calendar(
        [{"date": date, "open": "09:30", "close": "16:00", "session_close": "2000"}]
    )
    engine._calendar.clear()
    now = dt.datetime.fromisoformat(f"2026-01-06T{hour:02}:00:00-05:00")
    deliver(engine, event("exit", action, "27", "25", timestamp=now), now)
    order = engine.ledger.orders()[-1]
    assert (order.side, order.type, order.limit_price) == ("sell", "limit", Decimal("26.73"))
    assert order.entry_tolerance_pct == Decimal("1")
    assert broker.orders[order.client_id]["extended_hours"] is True
    assert not engine.ledger.queued()


def test_exits_outside_every_enabled_session_are_skipped(system):
    engine, broker, _ = system
    deliver(engine, event())
    engine.config = CopyConfig.model_validate(
        engine.config.model_dump() | {"extended_hours": False}
    )
    engine._calendar.clear()
    now = dt.datetime.fromisoformat("2026-01-06T18:00:00-05:00")
    deliver(engine, event("exit", "close", "27", "25", timestamp=now), now)
    assert broker.calls == 1
    assert engine.ledger.message("discord:demo:exit").parts == (Skipped(reason="outside_session"),)
