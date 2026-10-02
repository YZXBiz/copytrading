"""Raw messages and decoded replies the parsing tests build on."""

import datetime as dt

from copytrading_engine.parsing.contracts import RawMessage
from copytrading_engine.parsing.extraction import DecodedMessage

TEXT = "25加了6分之一常规仓abc"


def decoded(**changes):
    instruction = dict(
        action="buy",
        symbol="ABC",
        price="25",
        entry_price=None,
        fraction=None,
        action_evidence="加了",
        symbol_evidence="abc",
        price_evidence="25",
        entry_evidence=None,
        fraction_evidence=None,
    )
    instruction.update(changes)
    if instruction["action"] == "close" and instruction["fraction"] is None:
        instruction["fraction"] = "1"
    return DecodedMessage(
        decision="trade", reason="Explicit current entry", instructions=[instruction]
    )


def raw(text=TEXT):
    return RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="demo",
        id="1",
        timestamp=dt.datetime.now(dt.UTC),
        text=text,
    )
