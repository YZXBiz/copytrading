"""Model invariants hold outside the Kafka entrypoint and survive serialization."""

import datetime as dt

import pytest
from pydantic import ValidationError

from copytrading_engine.parsing.application import outcome
from copytrading_engine.parsing.contracts import RawMessage
from copytrading_engine.parsing.extraction import DecodedMessage
from copytrading_engine.shared.signals import StockSignal

from .builders import decoded, raw


@pytest.mark.parametrize(
    "changes",
    [
        {"timestamp": "2026-01-05T15:00:00"},
        {"schema_version": True},
        {"schema_version": "1"},
        {"image_count": True},
        {"image_count": 1.5},
    ],
)
def test_raw_value_rejects_ambiguous_inputs_without_a_service_guard(changes):
    with pytest.raises(ValidationError):
        RawMessage.model_validate(raw().model_dump() | changes)


def test_raw_value_cannot_change_after_validation():
    message = raw()
    with pytest.raises(ValidationError):
        message.__setattr__("timestamp", dt.datetime(2026, 1, 1))


def test_decoded_instructions_cannot_mutate_a_validated_decision():
    original = decoded()
    items = list(original.instructions)
    result = DecodedMessage(decision="trade", reason="Current entry", instructions=items)
    items.clear()
    assert result.instructions == original.instructions
    with pytest.raises(ValidationError):
        result.__setattr__("instructions", ())


def test_signal_collection_and_time_invariants_survive_json():
    message = raw()
    signal = outcome(message, "ignore", "Commentary", model="test")
    assert signal.timestamp == message.timestamp
    assert signal.instructions == signal.evidence == ()
    with pytest.raises(ValidationError):
        signal.__setattr__("decision", "trade")
    with pytest.raises(ValidationError):
        StockSignal.model_validate(signal.model_dump() | {"timestamp": "yesterday"})
    assert StockSignal.model_validate_json(signal.model_dump_json()) == signal
