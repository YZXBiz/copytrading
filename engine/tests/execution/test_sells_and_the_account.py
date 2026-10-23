"""What of the rest of the account can hold a sell (ADR-0010): only what is on its own stock, and
an open-order list that can't be trusted at all."""

import datetime as dt

from copytrading_engine.execution.domain.progress import OrderLinked, Pending, Skipped
from copytrading_engine.execution.domain.recovery import ReleaseEvidence

from .builders import NOW, deliver, event, evidence


def _on(symbol, *args, **kwargs):
    post = event(*args, **kwargs)
    post["instructions"][0]["symbol"] = symbol
    post["evidence"] = [evidence(instruction) for instruction in post["instructions"]]
    return post


def _outside(broker, count, symbol="XYZ", client_id=None):
    """Open orders the owner placed at Alpaca outside CopyTrading."""
    for index in range(count):
        key = client_id or f"outside-{index}"
        broker.orders[f"{key}-{index}"] = {
            "id": f"outside-broker-{index}",
            "client_order_id": key,
            "symbol": symbol,
            "side": "buy",
            "qty": "1",
            "type": "limit",
            "limit_price": "10",
            "filled_qty": "0",
            "status": "new",
            "filled_avg_price": None,
        }


def _part(engine, post):
    return engine.ledger.message(f"discord:demo:{post}").parts[0]


def test_a_sell_waits_out_a_truncated_open_order_list_and_sells_once_it_is_whole(system):
    """Alpaca lists at most 500 open orders: with 500 listed, an order on this stock may be
    missing from the page, so the sell can't tell whether one is in its way. It waits, asking
    again at most every 30 seconds, and sells once the list is whole: a sell is never lost."""
    engine, broker, _ = system
    deliver(engine, event())
    _outside(broker, 500)

    later = NOW + dt.timedelta(minutes=1)
    deliver(engine, event("sell", "close", "27", "25", timestamp=later), later)
    assert _part(engine, "sell") == Pending()
    assert broker.holdings["ABC"] == 4

    for key in [key for key in broker.orders if key.startswith("outside-")]:
        broker.orders[key]["status"] = "canceled"
    engine.process(later + dt.timedelta(seconds=10))
    assert _part(engine, "sell") == Pending(), "asked again before 30 seconds"

    engine.process(later + dt.timedelta(seconds=31))
    assert isinstance(_part(engine, "sell"), OrderLinked)
    assert broker.holdings["ABC"] == 0


def test_a_sell_waits_out_an_open_order_list_with_repeats(system):
    engine, broker, _ = system
    deliver(engine, event())
    _outside(broker, 2, client_id="repeated")

    later = NOW + dt.timedelta(minutes=1)
    deliver(engine, event("sell", "close", "27", "25", timestamp=later), later)

    assert _part(engine, "sell") == Pending()


def test_a_buy_is_still_skipped_against_a_truncated_open_order_list(system):
    engine, broker, _ = system
    _outside(broker, 500)

    deliver(engine, event())

    assert _part(engine, "1") == Skipped(reason="incomplete_account_orders")


def test_an_outside_order_on_another_stock_still_does_not_hold_a_sell(system):
    engine, broker, _ = system
    deliver(engine, event())
    _outside(broker, 1)

    later = NOW + dt.timedelta(minutes=1)
    deliver(engine, event("sell", "close", "27", "25", timestamp=later), later)

    assert isinstance(_part(engine, "sell"), OrderLinked)
    assert broker.holdings["ABC"] == 0


def _incident_on_abc(system):
    """DEF is held; then an ABC buy's outcome goes unclear, is released, and fills late: a
    late-order incident on ABC that stops every buy until the owner settles it."""
    engine, broker, _ = system
    deliver(engine, _on("DEF", "def-buy"))
    assert broker.holdings["DEF"] == 4
    broker.auto_fill = False
    broker.timeout_after_accept = True
    at = NOW + dt.timedelta(minutes=1)
    deliver(engine, event("abc-buy", timestamp=at), at)
    [unclear] = engine.pending()
    broker.timeout_after_accept = False
    engine.ledger.release_uncertain_intent(unclear.client_id, _release(at))
    broker.fill(unclear.client_id, str(unclear.qty))
    engine.reconcile(at + dt.timedelta(seconds=2))
    assert engine.ledger.state.entry_halted
    broker.auto_fill = True
    return engine, broker


def _release(at):
    return ReleaseEvidence(
        actor="operator@example.test",
        reason="broker histories confirm no accepted order or fills",
        order_history_ref="ticket-order-history",
        fill_history_ref="ticket-fill-history",
        checked_at=at + dt.timedelta(seconds=1),
        account_id="paper-demo",
    )


def test_an_order_incident_on_another_stock_does_not_hold_a_sell(system):
    engine, broker = _incident_on_abc(system)

    later = NOW + dt.timedelta(minutes=2)
    deliver(engine, _on("DEF", "def-sell", "close", "27", "25", timestamp=later), later)

    assert isinstance(_part(engine, "def-sell"), OrderLinked)
    assert broker.holdings["DEF"] == 0


def test_an_order_incident_on_the_stock_holds_its_sell(system):
    engine, broker = _incident_on_abc(system)

    later = NOW + dt.timedelta(minutes=2)
    deliver(engine, event("abc-sell", "close", "27", "25", timestamp=later), later)

    # It waits for the owner to settle the incident, and is never lost.
    assert _part(engine, "abc-sell") == Pending()
    assert broker.holdings["ABC"] == 4
