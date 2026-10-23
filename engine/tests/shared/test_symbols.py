"""One spelling per instrument: a stock's ticker, or a coin's US dollar pair (ADR-0014)."""

from decimal import Decimal

import pytest
from pydantic import TypeAdapter, ValidationError

from copytrading_engine.shared.reading import Stock
from copytrading_engine.shared.signals import Instruction
from copytrading_engine.shared.symbols import crypto_pair, held_symbol, is_crypto, path_symbol


@pytest.mark.parametrize(
    ("words", "pair"),
    [
        ("BTC", "BTC/USD"),
        ("btc", "BTC/USD"),
        ("$BTC", "BTC/USD"),
        ("BTC/USD", "BTC/USD"),
        ("btc-usd", "BTC/USD"),
        ("BTCUSD", "BTC/USD"),
        ("BTC/USDT", "BTC/USD"),
        ("比特币", "BTC/USD"),
        ("Bitcoin", "BTC/USD"),
        ("bitcoin cash", "BCH/USD"),
        ("以太坊", "ETH/USD"),
        ("ETHUSD", "ETH/USD"),
        ("狗狗币", "DOGE/USD"),
        ("SOL", "SOL/USD"),
    ],
)
def test_the_words_for_a_coin_name_its_pair(words, pair):
    assert crypto_pair(words) == pair


@pytest.mark.parametrize("words", ["NVDA", "苹果", "USDT", "USD", "BTCX", "", "比特"])
def test_words_for_no_coin_alpaca_trades_name_none(words):
    assert crypto_pair(words) is None


def test_a_held_coin_is_its_pair_and_a_stock_is_itself():
    assert held_symbol("BTCUSD", "crypto") == "BTC/USD"
    assert held_symbol("BTC/USD", "crypto") == "BTC/USD"
    assert held_symbol("SOXL", "us_equity") == "SOXL"
    assert held_symbol("USD", "crypto") == "USD"
    assert path_symbol("BTC/USD") == "BTCUSD"
    assert (is_crypto("BTC/USD"), is_crypto("BRK.B")) == (True, False)


@pytest.mark.parametrize(("written", "ticker"), [("BTCUSD", "BTC/USD"), ("btc-usd", "BTC/USD")])
def test_the_reader_writing_a_pair_another_way_is_read_as_the_pair(written, ticker):
    assert Stock(ticker=written, words="btc").ticker == ticker


def test_the_reader_writing_a_bare_ticker_keeps_it_for_the_etf_of_that_name():
    assert Stock(ticker="BTC", words="btc").ticker == "BTC"


def test_a_call_can_name_a_coins_pair_at_a_coins_price():
    call = TypeAdapter(Instruction).validate_python(
        {"action": "buy", "symbol": "BTC/USD", "price": "126000", "fraction": "0.5"}
    )

    assert (call.symbol, call.price) == ("BTC/USD", Decimal(126000))


@pytest.mark.parametrize("symbol", ["BTC/EUR", "btc/usd", "BTCUSD", "B/USD", "TOOLONGNAMEX/USD"])
def test_a_call_names_only_a_stock_or_a_coins_dollar_pair(symbol):
    with pytest.raises(ValidationError):
        Instruction.model_validate(
            {"action": "buy", "symbol": symbol, "price": "100", "fraction": "0.5"}
        )
