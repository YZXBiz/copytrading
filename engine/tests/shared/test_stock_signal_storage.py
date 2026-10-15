"""Signals stored while the chat filter existed still load, with its two fields dropped."""

from copytrading_engine.shared.signals import StockSignal

from ..execution.builders import event

RETIRED = {"sorted_by": "gpt-6-luna", "sorted_confidence": 0.97}


def test_a_stored_signal_with_the_retired_chat_filter_fields_loads_without_them():
    signal = StockSignal.model_validate(event() | RETIRED)

    assert signal == StockSignal.model_validate(event())
    assert not RETIRED.keys() & signal.model_dump().keys()


def test_a_stored_signal_with_null_chat_filter_fields_loads_from_json():
    stored = StockSignal.model_validate(event()).model_dump_json()[:-1]
    stored += ',"sorted_by":null,"sorted_confidence":null}'

    assert StockSignal.model_validate_json(stored) == StockSignal.model_validate(event())
