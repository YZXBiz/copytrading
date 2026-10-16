"""Configuration removal checks persisted ownership without starting broker resources."""

import datetime as dt
import sqlite3
from contextlib import closing
from decimal import Decimal

import pytest

from copytrading_engine.execution.adapters.ownership_probe import (
    UnsettledOwnership,
    unsettled_ownership,
)
from copytrading_engine.execution.domain.ledger_state import (
    CashAnchor,
    LedgerSnapshot,
    MessageRecord,
)
from copytrading_engine.execution.domain.order_lifecycle import OrderStatus
from copytrading_engine.execution.domain.orders import OrderRecord, OwnedLot
from copytrading_engine.execution.domain.ownership import ExternalPosition, OwnershipIncident
from copytrading_engine.execution.domain.progress import OrderLinked
from copytrading_engine.execution.domain.sessions import Session
from copytrading_engine.shared.signals import Evidence, Instruction, StockSignal

from .builders import as_earlier_version, destination_signal, save_snapshot

NOW = dt.datetime(2026, 9, 25, 15, tzinfo=dt.UTC)


def _trade_message() -> MessageRecord:
    instruction = Instruction(action="buy", symbol="ABC", price=Decimal("25"))
    evidence = Evidence(
        **instruction.model_dump(),
        action_evidence="加了",
        symbol_evidence="ABC",
        price_evidence="25",
    )
    signal = StockSignal(
        source="discord",
        channel_id="demo",
        id="1",
        timestamp=NOW,
        text="25加了ABC",
        parser_profile="test",
        model="test",
        decision="trade",
        reason="current buy",
        instructions=(instruction,),
        evidence=(evidence,),
    )
    return MessageRecord.model_validate(
        signal.model_dump()
        | {
            "source_key": "discord:demo",
            "parts": [OrderLinked(client_id="client-1")],
            "status": "done",
            "destination": destination_signal(signal).terms,
            "cash_anchor": CashAnchor(
                account_id="paper-demo",
                message_id="discord:demo:1",
                observed_at=NOW,
                cash=Decimal("100"),
                buying_power=Decimal("100"),
            ),
        }
    )


def _order(message: MessageRecord, status: OrderStatus) -> OrderRecord:
    filled = Decimal(1) if status == OrderStatus.FILLED else Decimal(0)
    return OrderRecord(
        side="buy",
        position_intent="buy_to_open",
        type="limit",
        limit_price=Decimal("25"),
        symbol="ABC",
        qty=Decimal(1),
        source_price=Decimal("25"),
        entry_tolerance_pct=Decimal(0),
        lot_id=None,
        entry_price=Decimal("25"),
        session=Session.REGULAR,
        client_id="client-1",
        message_id=message.key,
        instruction_index=0,
        source_key="discord:demo",
        status=status,
        filled_qty=filled,
        broker_id="broker-1" if filled else None,
        created_at=NOW,
        day=NOW.date(),
        raw_broker_status="filled" if filled else None,
    )


def test_missing_ledger_and_settled_snapshot_are_safe(tmp_path):
    account_dir = tmp_path / "paper-demo"
    assert unsettled_ownership(account_dir) is None
    save_snapshot(account_dir, LedgerSnapshot(account_id="paper-demo"))
    assert unsettled_ownership(account_dir) is None


def test_queued_message_blocks_account_removal(tmp_path):
    account_dir = tmp_path / "paper-demo"
    message = MessageRecord(
        source="discord",
        channel_id="demo",
        id="1",
        timestamp=NOW,
        text="commentary",
        parser_profile="test",
        model="test",
        decision="ignore",
        reason="commentary",
        evidence=(),
        instructions=(),
        source_key="discord:demo",
        parts=(),
        status="queued",
        destination=destination_signal(
            StockSignal(
                source="discord",
                channel_id="demo",
                id="1",
                timestamp=NOW,
                text="commentary",
                parser_profile="test",
                model="test",
                decision="ignore",
                reason="commentary",
                evidence=(),
                instructions=(),
            )
        ).terms,
    )
    save_snapshot(
        account_dir, LedgerSnapshot(account_id="paper-demo", messages={message.key: message})
    )
    assert unsettled_ownership(account_dir) == UnsettledOwnership(needs_review=True)


def test_nonterminal_order_blocks_account_removal(tmp_path):
    account_dir = tmp_path / "paper-demo"
    message = _trade_message()
    order = _order(message, OrderStatus.NEW)
    save_snapshot(
        account_dir,
        LedgerSnapshot(
            account_id="paper-demo",
            messages={message.key: message},
            orders={order.client_id: order},
        ),
    )
    assert unsettled_ownership(account_dir) == UnsettledOwnership(order_symbols=("ABC",))


def test_shares_a_removed_account_still_holds_never_block_it(tmp_path):
    """They stay at the broker; CopyTrading only stops tracking them."""
    account_dir = tmp_path / "paper-demo"
    message = _trade_message()
    order = _order(message, OrderStatus.FILLED)
    lot = OwnedLot(
        symbol="ABC",
        entry_price=Decimal("25"),
        source_key="discord:demo",
        original_qty=Decimal(1),
        remaining_qty=Decimal(1),
        average_price=Decimal("25"),
        entry_remaining={order.client_id: Decimal(1)},
        entry_prices={order.client_id: Decimal("25")},
    )
    save_snapshot(
        account_dir,
        LedgerSnapshot(
            account_id="paper-demo",
            messages={message.key: message},
            orders={order.client_id: order},
            lots={order.client_id: lot},
        ),
    )
    assert unsettled_ownership(account_dir) is None


@pytest.mark.parametrize("corruption", ["bad_json", "unknown_snapshot", "unknown_schema"])
def test_corrupt_or_unknown_state_fails_closed(tmp_path, corruption):
    account_dir = tmp_path / "paper-demo"
    save_snapshot(account_dir, LedgerSnapshot(account_id="paper-demo"))
    with closing(sqlite3.connect(account_dir / "execution.sqlite3")) as db, db:
        if corruption == "bad_json":
            db.execute("UPDATE snapshot SET data='not-json'")
        elif corruption == "unknown_snapshot":
            db.execute("UPDATE snapshot SET data=?", ('{"schema_version":99}',))
        else:
            db.execute(
                "UPDATE copytrading_engine_schema_revisions SET revision=99 "
                "WHERE component='execution'"
            )
    with pytest.raises(RuntimeError):
        unsettled_ownership(account_dir)


def test_terminal_order_without_position_is_settled(tmp_path):
    account_dir = tmp_path / "paper-demo"
    message = _trade_message()
    order = _order(message, OrderStatus.CANCELED)
    save_snapshot(
        account_dir,
        LedgerSnapshot(
            account_id="paper-demo",
            messages={message.key: message},
            orders={order.client_id: order},
        ),
    )
    assert unsettled_ownership(account_dir) is None


def test_external_inventory_alone_does_not_claim_app_owned_shares(tmp_path):
    account_dir = tmp_path / "paper-demo"
    save_snapshot(
        account_dir,
        LedgerSnapshot(
            account_id="paper-demo",
            external_positions={"ABC": ExternalPosition(symbol="ABC", qty=Decimal(100))},
        ),
    )
    assert unsettled_ownership(account_dir) is None


def test_snapshot_environment_mismatch_fails_closed_on_removal(tmp_path):
    account_dir = tmp_path / "paper-demo"
    save_snapshot(account_dir, LedgerSnapshot(account_id="paper-demo"))
    with closing(sqlite3.connect(account_dir / "execution.sqlite3")) as db, db:
        db.execute("UPDATE identity SET environment='live' WHERE singleton=1")
    with pytest.raises(RuntimeError, match="identity"):
        unsettled_ownership(account_dir)


def test_an_open_ownership_incident_does_not_block_account_removal(tmp_path):
    account_dir = tmp_path / "paper-demo"
    save_snapshot(
        account_dir,
        LedgerSnapshot(
            account_id="paper-demo",
            ownership_incidents={
                "incident-1": OwnershipIncident(
                    incident_id="incident-1",
                    symbol="ABC",
                    expected_qty=Decimal(100),
                    actual_qty=Decimal(90),
                    observed_at=NOW,
                    cause="position_mismatch",
                )
            },
        ),
    )
    assert unsettled_ownership(account_dir) is None


def test_unreadable_existing_database_fails_closed(tmp_path):
    account_dir = tmp_path / "paper-demo"
    account_dir.mkdir()
    (account_dir / "execution.sqlite3").write_bytes(b"not a database")
    with pytest.raises(RuntimeError, match="unreadable"):
        unsettled_ownership(account_dir)


def test_an_empty_account_from_an_older_version_does_not_block_setup(tmp_path):
    account_dir = tmp_path / "paper-demo"
    save_snapshot(account_dir, LedgerSnapshot(account_id="paper-demo"))
    as_earlier_version(account_dir)

    assert unsettled_ownership(account_dir) is None


@pytest.mark.parametrize(
    ("contents", "held"),
    [
        (
            {"orders": {"buy-1": {"symbol": "ABC", "status": "accepted"}}},
            UnsettledOwnership(order_symbols=("ABC",)),
        ),
        ({"messages": {"m-1": {"status": "queued"}}}, UnsettledOwnership(needs_review=True)),
        ({"orders": {"buy-1": {"symbol": "ABC"}}}, UnsettledOwnership(needs_review=True)),
        ({"lots": {"buy-1": {"symbol": "ABC", "remaining_qty": "1"}}}, None),
    ],
    ids=["open-order", "post-being-copied", "unreadable", "shares"],
)
def test_an_older_versions_account_with_work_in_flight_still_blocks(tmp_path, contents, held):
    account_dir = tmp_path / "paper-demo"
    save_snapshot(account_dir, LedgerSnapshot(account_id="paper-demo"))
    as_earlier_version(account_dir, **contents)

    assert unsettled_ownership(account_dir) == held
