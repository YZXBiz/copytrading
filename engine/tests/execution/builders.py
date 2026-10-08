"""Signals, events, and engines the execution tests build on."""

import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.adapters.sqlite_ledger import Store
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.application.recovery import RecoveryApplication
from copytrading_engine.execution.domain.ledger_state import (
    LedgerSnapshot,
)
from copytrading_engine.execution.domain.recovery import (
    ManualSale,
)
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.domain.sizing import (
    DestinationSignal,
    DestinationTerms,
    RouteConnection,
)
from copytrading_engine.shared.signals import StockSignal

from .fakes import FakeBroker, MemoryRepository

NOW = dt.datetime(2026, 1, 5, 15, tzinfo=dt.UTC)


def destination_signal(
    signal: StockSignal,
    *,
    full_position_usd: str = "600",
    revision: str = "a" * 64,
    account_id: str = "paper-demo",
    repeat_window_minutes: int | None = 10,
) -> DestinationSignal:
    return DestinationSignal(
        signal=signal,
        terms=DestinationTerms(
            connection=RouteConnection.model_validate(
                {
                    "account_id": account_id,
                    "full_position_usd": full_position_usd,
                }
            ),
            environment="paper",
            configuration_revision=revision,
            repeat_window_minutes=repeat_window_minutes,
        ),
    )


def receive(
    engine: CopyEngine,
    signal: StockSignal,
    now: dt.datetime,
    *,
    full_position_usd: str = "600",
    repeat_window_minutes: int | None = 10,
) -> None:
    engine.receive(
        destination_signal(
            signal,
            full_position_usd=full_position_usd,
            repeat_window_minutes=repeat_window_minutes,
        ),
        now,
    )


def evidence(instruction):
    return {
        **instruction,
        "action_evidence": "synthetic",
        "symbol_evidence": instruction["symbol"],
        "price_evidence": instruction["price"],
        "entry_evidence": instruction["entry_price"],
        "fraction_evidence": None,
    }


def event(id="1", action="buy", price="25", entry=None, timestamp=NOW, channel="demo"):
    result = {
        "schema_version": 2,
        "event_type": "stock_signal",
        "source": "discord",
        "channel_id": channel,
        "id": id,
        "timestamp": timestamp.isoformat(),
        "text": "synthetic fixture",
        "parser_profile": "fixture",
        "model": "fixture",
        "decision": "trade",
        "reason": "synthetic trade",
        "evidence": [{}],
        "instructions": [
            {
                "action": action,
                "symbol": "ABC",
                "price": price,
                "entry_price": entry,
                "fraction": "0.5"
                if action == "reduce"
                else "0.1666666666666666666666666667"
                if action == "buy"
                else "1",
            }
        ],
    }

    result["evidence"] = [evidence(i) for i in result["instructions"]]
    return result


def deliver(engine, message, now=NOW, *, full_position_usd="600"):
    receive(engine, StockSignal.model_validate(message), now, full_position_usd=full_position_usd)
    engine.process(now)


def system_with_queued_buy():
    repository = MemoryRepository()
    broker = FakeBroker()
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    return engine, broker, repository


def manual_sale(engine, **changes):

    lot_id = next(iter(engine.ledger.snapshot().lots))
    return ManualSale.model_validate(
        {
            "lot_id": lot_id,
            "order": {
                "id": "manual-broker-1",
                "client_order_id": "manual-client-1",
                "symbol": "ABC",
                "side": "sell",
                "qty": Decimal("4"),
                "filled_qty": Decimal("4"),
                "filled_avg_price": Decimal("26"),
                "status": "filled",
            },
            "filled_at": NOW,
            "recorded_at": NOW,
            "reason": "Operator confirmed manual sale; verified against broker",
        }
        | changes
    )


def late_sell_with_consumed_source_lot():
    """Leave a released ABC reduction whose source lot is later fully sold."""

    repository = MemoryRepository()
    broker = FakeBroker()
    # The late sell is a limit order; a long timeout keeps the engine from cancelling it.
    config = CopyConfig(sources=["discord:demo"], order_timeout_seconds=600)
    engine = CopyEngine(repository, broker, config)
    engine.bind(NOW)

    first_at = NOW
    second_at = NOW + dt.timedelta(minutes=1)
    receive(engine, StockSignal.model_validate(event("first-entry", price="25")), first_at)
    engine.process(first_at)
    receive(
        engine,
        StockSignal.model_validate(event("second-entry", price="26", timestamp=second_at)),
        second_at,
    )
    engine.process(second_at)
    first_lot_id = engine.ledger.orders()[0].client_id

    third_at = NOW + dt.timedelta(minutes=1, seconds=30)
    unrelated_entry = event("def-entry", timestamp=third_at)
    unrelated_entry["instructions"][0]["symbol"] = "DEF"
    unrelated_entry["evidence"] = [
        evidence(instruction) for instruction in unrelated_entry["instructions"]
    ]
    receive(engine, StockSignal.model_validate(unrelated_entry), third_at)
    engine.process(third_at)

    reduction_at = NOW + dt.timedelta(minutes=2)
    broker.auto_fill = False
    broker.timeout_after_accept = True
    reduction = event(
        "uncertain-reduction",
        "reduce",
        "27",
        "25",
        timestamp=reduction_at,
    )
    receive(engine, StockSignal.model_validate(reduction), reduction_at)
    engine.process(reduction_at)
    late_order = next(order for order in engine.ledger.orders() if order.side == "sell")
    late_broker_record = dict(broker.orders.pop(late_order.client_id))
    RecoveryApplication(
        engine.ledger,
        broker,
        clock=lambda: NOW + dt.timedelta(minutes=2, seconds=1),
    ).release_uncertain_intent(
        late_order.client_id,
        actor="operator@example.test",
        reason="Broker history confirms no accepted order or fills",
        order_history_ref="late-order-history-1",
        fill_history_ref="late-fill-history-1",
        account_id="paper-demo",
    )

    close_at = NOW + dt.timedelta(minutes=3)
    broker.timeout_after_accept = False
    broker.auto_fill = True
    receive(
        engine,
        StockSignal.model_validate(
            event("independent-close", "close", "27", "25", timestamp=close_at)
        ),
        close_at,
    )
    engine.process(close_at)
    # Both buys joined one lot (ADR-0010); the close named the first buy's price, so only that
    # buy is sold out.
    [lot] = [lot for lot in engine.ledger.lots() if lot.symbol == "ABC"]
    assert lot.entry_remaining[first_lot_id] == 0
    assert engine.ledger.order(first_lot_id).filled_qty > 0
    return engine, broker, repository, late_order, late_broker_record


def mixed_account():
    store = MemoryRepository()
    broker = FakeBroker()
    broker.holdings["ABC"] = Decimal("100")
    engine = engine_with_wide_limits(store, broker)
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW, full_position_usd="7500")
    engine.process(NOW)
    assert engine.ledger.owned("ABC") == 50
    return store, broker, engine


def save_snapshot(account_dir, snapshot: LedgerSnapshot) -> None:
    store = Store(account_dir / "execution.sqlite3")
    try:
        store.bind_identity("paper-demo", "paper")
        snapshot = LedgerSnapshot.model_validate(snapshot.model_dump() | {"environment": "paper"})
        store.db.execute(
            "INSERT INTO identity(singleton,environment,account_id) VALUES (1,'paper','paper-demo')"
        )
        store.db.execute(
            "INSERT INTO snapshot(singleton,data) VALUES (1,?)",
            (snapshot.model_dump_json(),),
        )
    finally:
        store.close()


def engine_with_wide_limits(store, broker):
    return CopyEngine(
        store,
        broker,
        CopyConfig(
            sources=["discord:demo"],
            max_order_usd=Decimal("1250"),
            max_symbol_usd=Decimal("10000"),
            max_total_usd=Decimal("10000"),
        ),
    )


def set_tolerance(engine, percent="1"):
    engine.config = CopyConfig.model_validate(
        engine.config.model_dump() | {"entry_pricing": {"max_above_signal_pct": percent}}
    )
