"""The pipe answers the bars and guru-performance reads, and refuses malformed asks."""

import datetime as dt
from decimal import Decimal

from copytrading_engine.execution.domain.market import Bar
from copytrading_engine.execution.presentation.guru_performance import GuruPerformance
from copytrading_engine.host.pipe.server import PipeServer
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.status import EngineQueries

from .builders import decode, request_line, services

AT = dt.datetime(2026, 11, 3, 14, 30, tzinfo=dt.UTC)


class _Operator:
    async def bars(self, account_id, symbols):
        if account_id != "paper":
            raise KeyError(account_id)
        return {
            symbol: (Bar(at=AT, open=Decimal("40.10"), close=Decimal("40.25")),)
            if symbol == "SOXL"
            else ()
            for symbol in symbols
        }

    async def guru_performance(self, account_id, guru_id):
        if account_id != "paper":
            raise KeyError(account_id)
        return GuruPerformance(
            guru_id=guru_id,
            account_id=account_id,
            realized_usd=Decimal("12.50"),
            unrealized_usd=None,
            closed_trades=0,
            winning_trades=0,
            unmatched_sells=2,
            best=None,
            worst=None,
            series=(),
        )


def _server(store):
    return PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        services(_Operator()),
    )


async def test_bars_answer_each_asked_symbol_with_its_series_or_none(store):
    reply = decode(
        await _server(store).handle_line(
            request_line("get_bars", "bars", account_id="paper", symbols=["SOXL", "BTC/USD"])
        )
    )
    assert reply["ok"] == {
        "type": "bars",
        "account_id": "paper",
        "bars": {
            "SOXL": [{"at": "2026-11-03T14:30:00Z", "open": "40.10", "close": "40.25"}],
            "BTC/USD": [],
        },
    }


async def test_guru_performance_answers_the_figures_as_decimal_strings(store):
    reply = decode(
        await _server(store).handle_line(
            request_line("get_guru_performance", "perf", account_id="paper", guru_id="guru-1")
        )
    )
    assert reply["ok"]["type"] == "guru_performance"
    assert reply["ok"]["performance"]["realized_usd"] == "12.50"
    assert reply["ok"]["performance"]["unmatched_sells"] == 2


async def test_an_account_without_read_keys_is_not_found_and_bad_asks_are_invalid(store):
    server = _server(store)
    for line in (
        request_line("get_bars", "x", account_id="other", symbols=["SOXL"]),
        request_line("get_guru_performance", "x", account_id="other", guru_id="guru-1"),
    ):
        assert decode(await server.handle_line(line))["error"] == {"code": "not_found"}
    for line in (
        request_line("get_bars", "x", account_id="paper", symbols=[]),
        request_line("get_bars", "x", account_id="paper", symbols=["soxl"]),
        request_line("get_bars", "x", account_id="paper", symbols=["SOXL", "SOXL"]),
        request_line("get_bars", "x", account_id="paper", symbols=["A"] * 51),
        request_line("get_guru_performance", "x", account_id="paper", guru_id=""),
    ):
        assert decode(await server.handle_line(line))["error"] == {"code": "invalid_request"}
