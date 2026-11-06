"""The guru's stops, read from Zhao's real posts (channel 1517754775674949742): a stop is a call
of its own that protects shares, never a sell at its price now and never a conditional."""

from decimal import Decimal

import pytest

from copytrading_engine.parsing.application import transform
from copytrading_engine.parsing.extraction import GroundingError, check_reading
from copytrading_engine.parsing.history import RecentCall
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.reading import Alongside, Lot, NotSaid

from ..readings import buy, commentary, stop, trade
from .builders import raw
from .fakes import FakeDecoder

THIRD = "0.3333333333333333333333333333"
HALF_LEFT = "剩下一半49.5的tqqq 设置下 跌破50.95出剩下的保护"
ALL_SOXL = "剩下的一点soxl做个跌破44.5全出的保护 或者不想博弈全出都可以 扛不住要休息下了"
BUY_WITH_STOP = "43.4加了3分之一常规仓soxl 止损放38.4"
CHATTER = (
    "两个都是夜盘的均价低个1毛左右自己也可以按自己的调整 在条件单 回落卖出或者跌破止盈两个选项"
)


async def read(post: str, reading):
    return await transform(raw(post), Route(), FakeDecoder(reading), "test")


async def test_the_stop_on_the_shares_left_of_the_49_5_buy():
    reading = trade(stop("TQQQ", "50.95", said="跌破", bought_at="49.5"))
    check_reading(reading, HALF_LEFT, Route())  # 跌破 is the trigger, not a condition
    signal = await read(HALF_LEFT, reading)
    assert (signal.decision, signal.instructions) == ("trade", ())
    [stop_call] = signal.stops
    assert (stop_call.symbol, stop_call.stop_price, stop_call.entry_price) == (
        "TQQQ",
        Decimal("50.95"),
        Decimal("49.5"),
    )
    assert (stop_call.price_evidence, stop_call.entry_evidence) == ("50.95", "49.5")


async def test_the_stop_on_all_the_soxl_names_no_buy_and_the_options_are_not_calls():
    reading = trade(stop("SOXL", "44.5", said="跌破", ticker_said="soxl"))
    check_reading(reading, ALL_SOXL, Route())
    signal = await read(ALL_SOXL, reading)
    [stop_call] = signal.stops
    assert (stop_call.stop_price, stop_call.entry_price, stop_call.buy_part) == (
        Decimal("44.5"),
        None,
        None,
    )
    assert signal.instructions == ()  # 全出都可以 is not a sell


async def test_a_buy_and_the_stop_on_that_same_buy():
    reading = trade(
        buy(
            "SOXL", "43.4", said="加了", ticker_said="soxl", fraction=THIRD, fraction_said="3分之一"
        ),
        stop("SOXL", "38.4", said="止损", ticker_said="soxl", alongside=0),
    )
    check_reading(reading, BUY_WITH_STOP, Route())
    signal = await read(BUY_WITH_STOP, reading)
    [instruction] = signal.instructions
    [stop_call] = signal.stops
    assert (instruction.action, instruction.price) == ("buy", Decimal("43.4"))
    assert (stop_call.stop_price, stop_call.buy_part, stop_call.entry_price) == (
        Decimal("38.4"),
        0,
        None,
    )


async def test_the_chatter_about_conditional_orders_is_not_a_stop():
    signal = await read(CHATTER, commentary("Order tips for readers"))
    assert (signal.decision, signal.instructions, signal.stops) == ("ignore", (), ())


def test_a_stop_reads_as_a_stop_not_as_a_sell_at_its_price():
    reading = trade(stop("TQQQ", "50.95", said="跌破", bought_at="49.5"))
    [call] = reading.calls
    assert call.action == "stop"
    assert isinstance(call.protects, Lot)
    assert isinstance(stop("SOXL", "44.5").protects, NotSaid)
    assert isinstance(stop("SOXL", "38.4", alongside=0).protects, Alongside)


def test_the_stop_price_must_be_in_the_post():
    reading = trade(stop("TQQQ", "51.95", said="跌破", price_said="51.95", bought_at="49.5"))
    with pytest.raises(GroundingError) as raised:
        check_reading(reading, HALF_LEFT, Route())
    assert raised.value.issue.code == "number_not_grounded"


def test_the_buy_price_a_stop_names_must_be_in_the_post():
    reading = trade(stop("TQQQ", "50.95", said="跌破", bought_at="48.5"))
    with pytest.raises(GroundingError) as raised:
        check_reading(reading, HALF_LEFT, Route())
    assert raised.value.issue.code == "number_not_grounded"


def test_a_stop_beside_a_buy_must_point_at_a_buy_of_its_own_stock():
    reading = trade(
        buy(
            "SOXL", "43.4", said="加了", ticker_said="soxl", fraction=THIRD, fraction_said="3分之一"
        ),
        stop("TQQQ", "38.4", said="止损", ticker_said="soxl", alongside=0),
    )
    with pytest.raises(GroundingError):
        check_reading(reading, BUY_WITH_STOP, Route())
    pointing_at_itself = trade(stop("SOXL", "38.4", said="止损", ticker_said="soxl", alongside=0))
    with pytest.raises(GroundingError) as raised:
        check_reading(pointing_at_itself, BUY_WITH_STOP, Route())
    assert raised.value.issue.code == "stop_buy_not_in_post"


def test_a_ticker_reaches_a_stop_only_through_the_playbook():
    reading = trade(stop("SOXL", "44.5", said="跌破", ticker_said="半导体"))
    with pytest.raises(GroundingError) as raised:
        check_reading(reading, "半导体做个跌破44.5全出的保护", Route())
    assert raised.value.issue.code == "symbol_not_in_playbook"
    check_reading(
        reading,
        "半导体做个跌破44.5全出的保护",
        Route(playbook="半导体 means SOXL"),
    )


async def test_a_stop_posted_with_a_repeated_buy_goes_with_it():
    """The buy this post restates is dropped within the repeat window; its stop goes with it."""
    first = buy(
        "SOXL", "43.4", said="加了", ticker_said="soxl", fraction=THIRD, fraction_said="3分之一"
    )
    again = first.model_copy(update={"repeats": "c1"})
    reading = trade(again, stop("SOXL", "38.4", said="止损", ticker_said="soxl", alongside=0))
    posted = raw(BUY_WITH_STOP)
    recent = (
        RecentCall(
            ref="c1",
            source_key="discord:demo:0",
            index=0,
            at=posted.timestamp,
            action="buy",
            symbol="SOXL",
            price=Decimal("43.4"),
            fraction=Decimal(1) / Decimal(3),
            usd_amount=None,
            entry_price=None,
            open=True,
        ),
    )
    route = Route(repeat_window_minutes=10)
    signal = await transform(posted, route, FakeDecoder(reading), "test", recent)
    assert (signal.decision, signal.reason) == ("ignore", "repeats_a_recent_call")
    assert signal.stops == ()
