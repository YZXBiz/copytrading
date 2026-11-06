"""A stop the guru posts is placed as a stop order only when the account follows stops, for the
shares CopyTrading bought, and follows those shares afterwards (ADR-0015)."""

import datetime as dt
from decimal import Decimal

import pytest

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.progress import OrderLinked, Pending, Skipped
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, deliver, event, evidence
from .fakes import FakeBroker, MemoryRepository

NIGHT = dt.datetime(2026, 1, 5, 22, tzinfo=dt.UTC)  # 17:00 in New York: after the close


def engine_for(*, follow: bool = True, owned: str | None = None) -> tuple[CopyEngine, FakeBroker]:
    broker = FakeBroker()
    if owned is not None:
        broker.holdings["ABC"] = Decimal(owned)  # shares the owner bought themselves
    engine = CopyEngine(
        MemoryRepository(), broker, CopyConfig(sources=["discord:demo"], follow_stops=follow)
    )
    engine.bind(NOW)
    return engine, broker


def stop_post(
    id: str,
    price: str,
    *,
    entry: str | None = None,
    buy: dict | None = None,
    at: dt.datetime = NOW,
) -> dict:
    """A post that sets a stop, and, with `buy`, makes that buy too, as 43.4加了…止损放38.4 does."""
    post = event(id, timestamp=at)
    post["instructions"] = [buy] if buy is not None else []
    post["evidence"] = [evidence(buy)] if buy is not None else []
    post["stops"] = [
        {
            "symbol": "ABC",
            "stop_price": price,
            "entry_price": entry,
            "buy_part": 0 if buy is not None else None,
            "action_evidence": "stop",
            "symbol_evidence": "ABC",
            "price_evidence": price,
            "entry_evidence": entry,
        }
    ]
    return post


def stop_orders(engine: CopyEngine) -> list:
    return [o for o in engine.ledger.orders() if o.type == "stop"]


def live_stops(engine: CopyEngine) -> list:
    return [o for o in stop_orders(engine) if o.pending]


def buy_at(engine: CopyEngine, id: str, price: str) -> None:
    deliver(engine, event(id, price=price))


def test_a_stop_is_off_by_default_and_a_setup_without_it_reads_as_off():
    assert CopyConfig(sources=["discord:demo"]).follow_stops is False


def test_a_stop_post_is_skipped_when_following_stops_is_off():
    engine, broker = engine_for(follow=False)
    buy_at(engine, "1", "49.5")
    deliver(engine, stop_post("2", "50.95", entry="49.5"))
    message = engine.ledger.message("discord:demo:2")
    assert message.stop_parts == (Skipped(reason="follow_stops_off"),)
    assert message.status == "done"
    assert stop_orders(engine) == []
    assert not message.waits_for_owner
    assert all(o["type"] != "stop" for o in broker.orders.values())


def test_a_stop_is_a_sell_stop_order_for_the_named_buys_remaining_shares():
    engine, broker = engine_for()
    buy_at(engine, "1", "49.5")
    held = engine.ledger.owned("ABC")
    deliver(engine, stop_post("2", "50.95", entry="49.5"))
    [order] = live_stops(engine)
    assert (order.side, order.type, order.stop_price, order.qty) == (
        "sell",
        "stop",
        Decimal("50.95"),
        held,
    )
    request = broker.orders[order.client_id]
    assert (request["type"], request["time_in_force"], request["extended_hours"]) == (
        "stop",
        "day",
        False,
    )
    assert "limit_price" not in request
    assert order.from_entries == tuple(engine.ledger.state.lots[order.lot_id or ""].entry_remaining)
    assert engine.ledger.message("discord:demo:2").stop_parts == (
        OrderLinked(client_id=order.client_id),
    )
    assert len(order.client_id) <= 48


def test_a_stop_naming_one_buy_leaves_the_other_buys_unprotected():
    engine, _ = engine_for()
    buy_at(engine, "1", "49.5")
    first = engine.ledger.owned("ABC")
    deliver(engine, event("2", price="47"))
    deliver(engine, stop_post("3", "44", entry="47"))
    [order] = live_stops(engine)
    assert order.qty == engine.ledger.owned("ABC") - first


def test_a_stop_naming_no_buy_protects_every_share_bought_for_the_guru():
    engine, _ = engine_for()
    buy_at(engine, "1", "49.5")
    deliver(engine, event("2", price="47"))
    deliver(engine, stop_post("3", "44"))
    [order] = live_stops(engine)
    assert order.qty == engine.ledger.owned("ABC")


def test_a_stop_never_covers_the_owners_own_shares():
    engine, broker = engine_for(owned="10")
    buy_at(engine, "1", "49.5")
    deliver(engine, stop_post("2", "44"))
    [order] = live_stops(engine)
    assert order.qty == engine.ledger.owned("ABC")
    assert order.qty < broker.holdings["ABC"] - Decimal(10) + Decimal("0.000001")


def test_a_copied_sell_shrinks_the_stop_to_what_remains_and_then_cancels_it():
    engine, broker = engine_for()
    buy_at(engine, "1", "49.5")
    deliver(engine, stop_post("2", "44"))
    [first] = live_stops(engine)
    deliver(engine, event("3", action="reduce", price="50"))
    engine.process(NOW)
    assert broker.orders[first.client_id]["status"] == "canceled"
    [shrunk] = live_stops(engine)
    assert shrunk.client_id != first.client_id
    assert shrunk.qty == engine.ledger.owned("ABC") < first.qty
    deliver(engine, event("4", action="close", price="50"))
    engine.process(NOW)
    assert live_stops(engine) == []
    assert engine.ledger.state.stops == {}
    assert engine.ledger.owned("ABC") == 0


def test_a_copied_sell_is_not_blocked_by_the_stop_that_holds_its_shares():
    engine, _ = engine_for()
    buy_at(engine, "1", "49.5")
    deliver(engine, stop_post("2", "44"))
    held = engine.ledger.owned("ABC")
    deliver(engine, event("3", action="close", price="50"))
    sells = [o for o in engine.ledger.orders() if o.side == "sell" and o.type == "limit"]
    assert [o.qty for o in sells] == [held]
    assert engine.ledger.message("discord:demo:3").parts == (
        OrderLinked(client_id=sells[0].client_id),
    )


def test_a_copied_buy_beside_a_resting_stop_goes_out_and_the_stop_comes_back():
    """Alpaca refuses a buy while a sell stop of the stock rests (a possible wash trade), so the
    stop is cancelled first and placed again for the buys it protects once the buy is done."""
    engine, broker = engine_for()
    buy_at(engine, "1", "49.5")
    first_qty = engine.ledger.owned("ABC")
    deliver(engine, stop_post("2", "44"))
    [first] = live_stops(engine)
    deliver(engine, event("3", price="48"))
    engine.process(NOW)
    assert engine.ledger.owned("ABC") > first_qty
    assert broker.orders[first.client_id]["status"] == "canceled"
    [again] = live_stops(engine)
    assert again.client_id != first.client_id
    assert (again.qty, again.stop_price) == (first_qty, Decimal("44"))


def test_a_new_stop_for_the_same_buy_replaces_the_old_one():
    engine, broker = engine_for()
    buy_at(engine, "1", "49.5")
    deliver(engine, stop_post("2", "44", entry="49.5"))
    [old] = live_stops(engine)
    deliver(engine, stop_post("3", "45.5", entry="49.5"))
    assert broker.orders[old.client_id]["status"] == "canceled"
    assert live_stops(engine) == [old], "the new one waits for Alpaca to confirm the cancel"
    engine.reconcile(NOW)
    engine.process(NOW)
    [new] = live_stops(engine)
    assert (new.stop_price, new.qty) == (Decimal("45.5"), old.qty)
    assert list(engine.ledger.state.stops) == [new.stop_rule]
    # The post that set the new stop is the new order's source.
    assert new.message_id == "discord:demo:3"


def test_the_same_stop_posted_again_is_a_duplicate():
    engine, _ = engine_for()
    buy_at(engine, "1", "49.5")
    deliver(engine, stop_post("2", "44"))
    deliver(engine, stop_post("3", "44"))
    assert engine.ledger.message("discord:demo:3").stop_parts == (Skipped(reason="duplicate"),)
    assert len(live_stops(engine)) == 1


def test_a_stop_fill_is_recorded_as_a_sell_from_that_buy_with_the_post_as_its_source():
    engine, broker = engine_for()
    buy_at(engine, "1", "49.5")
    deliver(engine, stop_post("2", "44", entry="49.5"))
    [order] = live_stops(engine)
    broker.fill(order.client_id, order.qty)
    engine.reconcile(NOW)
    filled = engine.ledger.order(order.client_id)
    assert filled.status == OrderStatus.FILLED
    assert (filled.message_id, filled.side) == ("discord:demo:2", "sell")
    assert filled.filled_avg_price == Decimal("44")
    assert engine.ledger.owned("ABC") == 0
    engine.process(NOW)
    assert engine.ledger.state.stops == {}


def test_no_stop_is_placed_for_a_buy_that_did_not_fill():
    engine, broker = engine_for()
    broker.auto_fill = False
    buy = event("1", price="43.4")["instructions"][0]
    deliver(engine, stop_post("1", "38.4", buy=buy))
    message = engine.ledger.message("discord:demo:1")
    assert message.stop_parts == (Pending(),)
    assert stop_orders(engine) == []
    later = NOW + dt.timedelta(seconds=120)
    engine.reconcile(later)  # the buy times out and is cancelled
    engine.reconcile(later)
    engine.process(later)
    assert engine.ledger.message("discord:demo:1").stop_parts == (
        Skipped(reason="stop_buy_not_filled"),
    )
    assert stop_orders(engine) == []


def test_a_stop_beside_a_buy_is_placed_once_the_buy_fills():
    engine, broker = engine_for()
    broker.auto_fill = False
    buy = event("1", price="43.4")["instructions"][0]
    deliver(engine, stop_post("1", "38.4", buy=buy))
    [buy_order] = engine.ledger.orders()
    broker.fill(buy_order.client_id, buy_order.qty)
    later = NOW + dt.timedelta(seconds=31)  # a waiting stop asks again every 30 seconds
    engine.reconcile(later)
    engine.process(later)
    [stop] = live_stops(engine)
    assert (stop.stop_price, stop.qty) == (Decimal("38.4"), buy_order.qty)


def test_a_stop_waits_for_the_regular_session_and_is_never_placed_outside_it():
    engine, broker = engine_for()
    buy_at(engine, "1", "49.5")
    deliver(engine, stop_post("2", "44"), now=NIGHT)
    assert stop_orders(engine) == []
    assert engine.ledger.message("discord:demo:2").stop_parts == (Pending(),)
    assert all(o["type"] != "stop" for o in broker.orders.values())


def test_a_stop_is_placed_again_each_session_until_it_fills_or_its_shares_are_gone():
    engine, broker = engine_for()
    buy_at(engine, "1", "49.5")
    deliver(engine, stop_post("2", "44"))
    [today] = live_stops(engine)
    # Alpaca expires a day order at the close.
    broker.orders[today.client_id]["status"] = "expired"
    engine.reconcile(NIGHT)
    engine.process(NIGHT)
    assert live_stops(engine) == [], "no protection outside regular hours"
    tomorrow = NOW + dt.timedelta(days=1)
    engine.process(tomorrow)
    [again] = live_stops(engine)
    assert again.client_id != today.client_id
    assert len(again.client_id) <= 48
    assert (again.stop_price, again.qty) == (today.stop_price, today.qty)
    assert again.status in {OrderStatus.NEW, OrderStatus.ACCEPTED}
    assert len({o.client_id for o in stop_orders(engine)}) == 2
    # And a third session, after the second order expires too.
    broker.orders[again.client_id]["status"] = "expired"
    engine.reconcile(tomorrow + dt.timedelta(hours=8))
    engine.process(tomorrow + dt.timedelta(days=1))
    assert len(live_stops(engine)) == 1
    assert len(stop_orders(engine)) == 3


def test_a_stop_alpaca_refuses_is_tried_again_later_not_every_cycle():
    engine, broker = engine_for()
    buy_at(engine, "1", "49.5")
    broker.refuse_stops = True
    deliver(engine, stop_post("2", "44"))
    refused = len(stop_orders(engine))
    assert refused == 1
    assert live_stops(engine) == []
    for _ in range(3):
        engine.process(NOW)
    assert len(stop_orders(engine)) == refused
    broker.refuse_stops = False
    engine.process(NOW + dt.timedelta(minutes=6))
    assert len(live_stops(engine)) == 1


def test_a_stop_is_never_placed_for_a_coin():
    engine, _ = engine_for()
    post = stop_post("1", "44")
    post["stops"][0]["symbol"] = "BTC/USD"
    post["stops"][0]["symbol_evidence"] = "BTC"
    deliver(engine, post)
    assert engine.ledger.message("discord:demo:1").stop_parts == (
        Skipped(reason="stop_not_for_coins"),
    )


def test_a_stop_for_a_buy_the_account_does_not_hold_is_skipped():
    engine, _ = engine_for()
    deliver(engine, stop_post("1", "44", entry="49.5"))
    assert engine.ledger.message("discord:demo:1").stop_parts == (
        Skipped(reason="stop_buy_not_held"),
    )


def test_stops_survive_a_restart_of_the_ledger():
    engine, broker = engine_for()
    buy_at(engine, "1", "49.5")
    deliver(engine, stop_post("2", "44"))
    repository = MemoryRepository(engine.ledger.snapshot().model_dump_json())
    reopened = CopyEngine(
        repository, broker, CopyConfig(sources=["discord:demo"], follow_stops=True)
    )
    assert list(reopened.ledger.state.stops) == list(engine.ledger.state.stops)
    assert [o.client_id for o in live_stops(reopened)] == [o.client_id for o in live_stops(engine)]


def test_a_stop_post_alone_is_a_trade_and_never_a_buy_or_sell_instruction():
    post = StockSignal.model_validate(stop_post("1", "44"))
    assert post.decision == "trade"
    assert post.instructions == ()
    assert len(post.stops) == 1


def test_a_stop_for_a_buy_in_the_post_must_be_a_buy_of_its_own_stock():
    post = stop_post("1", "44", buy=event("1")["instructions"][0])
    post["stops"][0]["symbol"] = "XYZ"
    post["stops"][0]["symbol_evidence"] = "XYZ"
    with pytest.raises(ValueError, match="same post"):
        StockSignal.model_validate(post)
