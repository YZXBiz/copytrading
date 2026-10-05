"""Raw messages the parsing tests build on; readings come from `tests.readings`."""

import datetime as dt

from copytrading_engine.parsing.contracts import RawMessage

TEXT = "25加了6分之一常规仓abc"


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
