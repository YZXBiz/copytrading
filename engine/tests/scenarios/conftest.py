import pytest
import time_machine

from .rig import MARKET_MORNING


@pytest.fixture(autouse=True)
def clock():
    """Every scenario runs on a weekday morning in regular hours, whatever the real clock says;
    `clock.shift(...)` moves it on."""
    with time_machine.travel(MARKET_MORNING, tick=True) as traveller:
        yield traveller
