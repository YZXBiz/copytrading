"""Trading sessions follow the exchange calendar, half days, overnight dates, and DST."""

import datetime as dt
from zoneinfo import ZoneInfo

import pytest
from pydantic import ValidationError

from copytrading_engine.execution.domain.sessions import Session, SessionSchedule, trade_date
from copytrading_engine.execution.domain.signals import CopyConfig

ET = ZoneInfo("America/New_York")
NORMAL = SessionSchedule(dt.time(9, 30), dt.time(16), dt.time(4), dt.time(20))
HALF_DAY = SessionSchedule(dt.time(9, 30), dt.time(13), dt.time(4), dt.time(17))


@pytest.mark.parametrize(
    ("hour", "minute", "expected"),
    [
        (0, 0, Session.OVERNIGHT),
        (3, 59, Session.OVERNIGHT),
        (4, 0, Session.EXTENDED),
        (9, 29, Session.EXTENDED),
        (9, 30, Session.REGULAR),
        (15, 59, Session.REGULAR),
        (16, 0, Session.EXTENDED),
        (19, 59, Session.EXTENDED),
        (20, 0, Session.OVERNIGHT),
    ],
)
def test_session_boundaries(hour, minute, expected):
    now = dt.datetime(2026, 1, 5, hour, minute, tzinfo=ET)
    assert NORMAL.at(now, extended=True, overnight=True) == expected


def test_half_day_uses_extended_close_from_calendar():
    now = dt.datetime(2026, 11, 27, 16, 59, tzinfo=ET)
    assert HALF_DAY.at(now, extended=True, overnight=True) == Session.EXTENDED
    assert (
        HALF_DAY.at(now.replace(hour=17, minute=0), extended=True, overnight=True) == Session.CLOSED
    )


def test_overnight_uses_upcoming_trade_date_and_handles_dst():
    for text in ("2026-01-04T20:00:00", "2026-03-08T20:00:00", "2026-11-01T20:00:00"):
        now = dt.datetime.fromisoformat(text).replace(tzinfo=ET)
        assert trade_date(now) == now.date() + dt.timedelta(days=1)
        assert trade_date(now.astimezone(dt.UTC)) == trade_date(now)
        assert trade_date(now.replace(hour=19)) == now.date()


def test_sessions_can_be_disabled_independently():
    now = dt.datetime(2026, 1, 5, 21, tzinfo=ET)
    assert NORMAL.at(now, extended=True, overnight=False) == Session.CLOSED
    assert NORMAL.at(now.replace(hour=17), extended=False, overnight=False) == Session.CLOSED
    with pytest.raises(ValidationError):
        CopyConfig(sources=["discord:demo"], extended_hours=False, overnight=True)
