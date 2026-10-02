"""Pure session classification using the broker's trading-day calendar."""

import datetime as dt
from dataclasses import dataclass
from enum import StrEnum
from zoneinfo import ZoneInfo

ET = ZoneInfo("America/New_York")


class Session(StrEnum):
    CLOSED = "closed"
    REGULAR = "regular"
    EXTENDED = "extended"
    OVERNIGHT = "overnight"


def trade_date(now: dt.datetime) -> dt.date:
    local = now.astimezone(ET)
    return local.date() + dt.timedelta(days=int(local.hour >= 20))


@dataclass(frozen=True)
class SessionSchedule:
    regular_open: dt.time
    regular_close: dt.time
    extended_open: dt.time
    extended_close: dt.time

    def at(self, now: dt.datetime, *, extended: bool, overnight: bool) -> Session:
        time = now.astimezone(ET).time().replace(tzinfo=None)
        if time >= dt.time(20) or time < dt.time(4):
            return Session.OVERNIGHT if overnight and extended else Session.CLOSED
        if self.regular_open <= time < self.regular_close:
            return Session.REGULAR
        if extended and self.extended_open <= time < self.extended_close:
            return Session.EXTENDED
        return Session.CLOSED
