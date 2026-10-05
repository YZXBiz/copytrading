"""Readings the tests build, in the reading contract's own words (ADR-0007)."""

from decimal import Decimal

from copytrading_engine.shared.reading import (
    All,
    Buy,
    Commentary,
    Exact,
    Fraction,
    Lot,
    NotGiven,
    NotSaid,
    Sell,
    Stock,
    TradeMade,
)


def buy(
    ticker: str,
    price: str,
    *,
    said: str = "加了",
    ticker_said: str | None = None,
    price_said: str | None = None,
    fraction: str | None = None,
    fraction_said: str | None = None,
) -> Buy:
    """A buy at an exact price, sized by a fraction when `fraction` is given."""
    return Buy(
        action_words=said,
        stock=Stock(ticker=ticker, words=ticker_said or ticker.lower()),
        price=Exact(value=Decimal(price), words=price_said or price),
        size=(
            Fraction(value=Decimal(fraction), words=fraction_said or fraction)
            if fraction is not None
            else NotGiven()
        ),
    )


def sell(
    ticker: str,
    price: str,
    *,
    bought_at: str | None,
    said: str = "出掉",
    ticker_said: str | None = None,
    price_said: str | None = None,
    bought_at_said: str | None = None,
    fraction: str | None = None,
    fraction_said: str | None = None,
    counts_from: str | None = None,
) -> Sell:
    """A sell of everything, or of `fraction`, from the lot bought at `bought_at`."""
    return Sell(
        action_words=said,
        stock=Stock(ticker=ticker, words=ticker_said or ticker.lower()),
        price=Exact(value=Decimal(price), words=price_said or price),
        share=(
            Fraction(value=Decimal(fraction), words=fraction_said or fraction)
            if fraction is not None
            else All(words=said)
        ),
        counts_from=counts_from,  # ty: ignore[invalid-argument-type]
        sell_from=(
            Lot(buy_price=Decimal(bought_at), words=bought_at_said or bought_at)
            if bought_at is not None
            else NotSaid()
        ),
    )


def trade(*calls: Buy | Sell, summary: str = "A current call") -> TradeMade:
    return TradeMade(summary=summary, calls=calls)


def commentary(summary: str = "No trade action") -> Commentary:
    return Commentary(summary=summary)
