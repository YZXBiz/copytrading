"""Canonical tagged progress and aggregate snapshot invariants."""

import json

import pytest
from pydantic import TypeAdapter, ValidationError

from copytrading_engine.execution.adapters.sqlite_ledger import decode_ledger_snapshot
from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot, MessageRecord
from copytrading_engine.execution.domain.progress import (
    InstructionProgress,
    OrderLinked,
    Pending,
    Skipped,
)
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, destination_signal, event, evidence, receive
from .fakes import FakeBroker, MemoryRepository


@pytest.mark.parametrize(
    "value",
    [
        Pending(),
        OrderLinked(client_id="copy-order-1"),
        Skipped(reason="outside_session"),
    ],
)
def test_progress_uses_one_canonical_form(value):
    adapter = TypeAdapter(InstructionProgress)

    encoded = adapter.dump_json(value)

    assert adapter.validate_json(encoded) == value
    assert json.loads(encoded)["kind"] == value.kind


@pytest.mark.parametrize(
    "encoded",
    [
        b'{"kind":"unknown"}',
        b'"free text"',
        b"null",
    ],
)
def test_progress_rejects_values_outside_the_tagged_union(encoded):
    with pytest.raises(ValidationError):
        TypeAdapter(InstructionProgress).validate_json(encoded)


def _message(*, part: object, status: str = "queued") -> MessageRecord:
    signal = StockSignal.model_validate(event())
    return MessageRecord.model_validate(
        signal.model_dump()
        | {
            "source_key": "discord:demo",
            "parts": [part],
            "status": status,
            "destination": destination_signal(signal).terms,
        }
    )


def _two_instruction_signal(message_id: str) -> StockSignal:
    payload = event(id=message_id)
    second = payload["instructions"][0] | {"symbol": "XYZ"}
    payload["instructions"].append(second)
    payload["evidence"].append(evidence(second))
    return StockSignal.model_validate(payload)


def test_completed_message_has_no_pending_instructions():
    with pytest.raises(ValidationError, match="Pending"):
        _message(part=Pending(), status="done")


def test_snapshot_rejects_order_link_without_order_for_same_message():
    message = _message(part=OrderLinked(client_id="missing-order"))

    with pytest.raises(ValidationError, match=r"[Oo]rder"):
        LedgerSnapshot(
            messages={message.key: message},
        )


def test_snapshot_round_trip_preserves_tagged_progress_json():
    message = _message(part=Skipped(reason="outside_session"))
    snapshot = LedgerSnapshot(messages={message.key: message})

    encoded = snapshot.model_dump_json()
    loaded = LedgerSnapshot.model_validate_json(encoded)

    assert loaded == snapshot
    assert json.loads(encoded)["messages"][message.key]["parts"] == [
        {"kind": "skipped", "reason": "outside_session"}
    ]


def test_snapshot_rejects_order_link_to_wrong_instruction():
    repository = MemoryRepository()
    engine = CopyEngine(repository, FakeBroker(), CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, _two_instruction_signal("two-parts"), NOW)
    engine.process(NOW)
    snapshot = engine.ledger.snapshot()
    assert len(snapshot.orders) == 2
    assert {order.instruction_index for order in snapshot.orders.values()} == {0, 1}
    client_id, order = next(
        (client_id, order)
        for client_id, order in snapshot.orders.items()
        if order.instruction_index == 0
    )
    assert len(snapshot.messages[order.message_id].parts) == 2
    serialized = snapshot.model_dump(mode="json")
    serialized["orders"][client_id]["instruction_index"] = 1

    with pytest.raises(
        ValidationError,
        match="Order link does not match its message instruction",
    ):
        LedgerSnapshot.model_validate_json(json.dumps(serialized))


def test_snapshot_rejects_order_link_to_another_message():
    engine = CopyEngine(
        MemoryRepository(),
        FakeBroker(),
        CopyConfig(sources=["discord:demo"]),
    )
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event(id="first-message")), NOW)
    receive(engine, StockSignal.model_validate(event(id="second-message")), NOW)
    engine.process(NOW)
    snapshot = engine.ledger.snapshot()
    first_message_key = next(
        key for key, message in snapshot.messages.items() if message.id == "first-message"
    )
    second_message_key = next(
        key for key, message in snapshot.messages.items() if message.id == "second-message"
    )
    first_order = next(
        order for order in snapshot.orders.values() if order.message_id == first_message_key
    )
    data = snapshot.model_dump(mode="json")
    data["messages"][second_message_key]["parts"][0] = OrderLinked(
        client_id=first_order.client_id
    ).model_dump(mode="json")

    with pytest.raises(ValidationError, match="message instruction"):
        LedgerSnapshot.model_validate_json(json.dumps(data))


def test_snapshot_rejects_order_without_explicit_type():
    engine = CopyEngine(
        MemoryRepository(),
        FakeBroker(),
        CopyConfig(sources=["discord:demo"]),
    )
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    snapshot = engine.ledger.snapshot().model_dump(mode="json")
    next(iter(snapshot["orders"].values())).pop("type")

    with pytest.raises(ValidationError, match="type"):
        LedgerSnapshot.model_validate_json(json.dumps(snapshot))


def test_snapshot_accepts_only_schema_version_nine_and_requires_control():
    assert LedgerSnapshot().schema_version == 9
    for old_version in (2, 6, 7, 8):
        with pytest.raises(ValueError, match="Unsupported execution snapshot schema"):
            decode_ledger_snapshot(json.dumps({"schema_version": old_version}))
    with pytest.raises(ValueError, match="account control evidence"):
        decode_ledger_snapshot(json.dumps({"schema_version": 9}))


def test_buy_order_requires_matching_durable_cash_anchor():
    engine = CopyEngine(MemoryRepository(), FakeBroker(), CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    engine.process(NOW)
    snapshot = engine.ledger.snapshot().model_dump(mode="json")
    message = snapshot["messages"]["discord:demo:1"]
    assert message["cash_anchor"]["cash"] == "5000"
    message["cash_anchor"] = None
    with pytest.raises(ValidationError, match="preceding cash anchor"):
        LedgerSnapshot.model_validate_json(json.dumps(snapshot))
    message["cash_anchor"] = {
        "account_id": "other",
        "message_id": "discord:demo:1",
        "observed_at": NOW.isoformat(),
        "cash": "5000",
        "buying_power": "5000",
    }
    with pytest.raises(ValidationError, match="anchor does not match"):
        LedgerSnapshot.model_validate_json(json.dumps(snapshot))
