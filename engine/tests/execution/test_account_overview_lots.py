"""Accounts show each position's lots with the post that bought them."""

import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.presentation.operator_views import account_overview
from copytrading_engine.shared.queue_snapshot import QueueSnapshot

from .builders import NOW, system_with_queued_buy


def _overview(engine):
    return account_overview(
        engine.ledger.snapshot(),
        None,
        QueueSnapshot(0, None, 0),
        local_account_id="paper-demo",
        active_configuration=True,
        readiness="ready",
        balance=None,
    )


def test_each_position_lists_its_lots_with_the_post_that_bought_them():
    engine, broker, _ = system_with_queued_buy()
    broker.auto_fill = False
    engine.process(NOW)
    client_id = next(iter(broker.orders))
    broker.fill(client_id, broker.orders[client_id]["qty"])
    engine.reconcile(NOW)

    (position,) = _overview(engine).positions
    (lot,) = position.lots
    assert position.owned_qty == lot.remaining_qty == lot.original_qty
    assert lot.lot_id == client_id
    assert lot.source_id == "discord:demo:1"
    assert lot.posted_at == NOW
    assert lot.bought_at is not None
    assert NOW <= lot.bought_at < NOW + dt.timedelta(seconds=1)
    assert lot.excerpt == "synthetic fixture"
    assert lot.average_price == Decimal(broker.orders[client_id]["filled_avg_price"])


def test_sold_out_lots_leave_the_position():
    engine, _, _ = system_with_queued_buy()
    engine.process(NOW)
    snapshot = engine.ledger.snapshot()
    key, lot = next(iter(snapshot.lots.items()))
    emptied = snapshot.model_copy(
        update={"lots": {key: lot.model_copy(update={"remaining_qty": Decimal(0)})}}
    )
    engine.ledger._snapshot = emptied

    (position,) = _overview(engine).positions
    assert position.owned_qty == 0
    assert position.lots == ()


def test_long_posts_are_shortened_to_one_line():
    engine, _, _ = system_with_queued_buy()
    engine.process(NOW)
    snapshot = engine.ledger.snapshot()
    (message_key,) = snapshot.messages
    message = snapshot.messages[message_key]
    long_text = "ABC long here\n\n" + "and more " * 40
    engine.ledger._snapshot = snapshot.model_copy(
        update={"messages": {message_key: message.model_copy(update={"text": long_text})}}
    )

    (lot,) = _overview(engine).positions[0].lots
    assert lot.excerpt is not None
    assert "\n" not in lot.excerpt
    assert len(lot.excerpt) <= 140
    assert lot.excerpt.startswith("ABC long here and more")
    assert lot.excerpt.endswith("…")
