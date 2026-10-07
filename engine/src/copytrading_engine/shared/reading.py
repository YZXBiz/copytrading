"""What a guru's post says, in one shape for every guru (ADR-0007).

The reader model fills this in; plain code decides what to do with it. Each choice is a tagged
alternative, so a combination that makes no sense, such as an exact price and a range, or a batch
and a fraction, cannot be written down. Every stated value carries the post's own words beside
it, so a value without its evidence cannot exist. A field the post does not state is `NotGiven`
or `NotSaid`; nothing is filled in for the guru.
"""

import re
from decimal import Decimal
from typing import Annotated, Literal, Self

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, model_validator

Words = Annotated[str, Field(min_length=1, max_length=200)]
"""The post's exact words behind a value."""

Money = Annotated[Decimal, Field(gt=0, le=100000, allow_inf_nan=False)]
Ticker = Annotated[str, Field(pattern=r"^[A-Z]{1,5}(?:[.][A-Z])?$")]


class _Part(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)


class NotGiven(_Part):
    """The post does not state this."""

    kind: Literal["not_given"] = "not_given"


class Exact(_Part):
    kind: Literal["exact"] = "exact"
    value: Money
    words: Words


class Range(_Part):
    """A zone such as 160-179."""

    kind: Literal["range"] = "range"
    low: Money
    high: Money
    low_words: Words
    high_words: Words

    @model_validator(mode="after")
    def low_to_high(self) -> Self:
        if self.low >= self.high:
            raise ValueError("A price range runs from low to high")
        return self


class AtMarket(_Part):
    """Buy or sell now, at whatever the market is, as the post says."""

    kind: Literal["at_market"] = "at_market"
    words: Words


type Price = Annotated[Exact | Range | AtMarket | NotGiven, Field(discriminator="kind")]


def _exact_fraction(value: object) -> object:
    """A value written as a ratio, "1/6", is that exact fraction: a model may write it either way,
    and a rounded decimal such as 0.1667 would no longer match the post's own 1/6."""
    if isinstance(value, str) and (match := re.fullmatch(r"\s*(\d+)\s*/\s*(\d+)\s*", value)):
        numerator, denominator = (int(group) for group in match.groups())
        if denominator:
            return Decimal(numerator) / Decimal(denominator)
    return value


class Fraction(_Part):
    """A share of a full position, as written: 6分之一, half, 1/3."""

    kind: Literal["fraction"] = "fraction"
    value: Annotated[
        Decimal, BeforeValidator(_exact_fraction), Field(gt=0, le=1, allow_inf_nan=False)
    ]
    words: Words


class Batch(_Part):
    """The guru's Nth batch, such as 第二批."""

    kind: Literal["batch"] = "batch"
    number: Annotated[int, Field(ge=1, le=20)]
    words: Words


type Size = Annotated[Fraction | Batch | NotGiven, Field(discriminator="kind")]


class All(_Part):
    """Everything this sell refers to, such as 出掉 or 跑路."""

    kind: Literal["all"] = "all"
    words: Words


# A vague trim ("trimmed", 减仓) states no share; it waits for the owner (ADR-0010).
type Share = Annotated[Fraction | All | NotGiven, Field(discriminator="kind")]


class Lot(_Part):
    """The buy a sell names by its price, such as the 39.5 in 出一半39.5的iren."""

    kind: Literal["lot"] = "lot"
    buy_price: Money
    words: Words


class NotSaid(_Part):
    """The sell does not say which buy it comes from."""

    kind: Literal["not_said"] = "not_said"


type SellFrom = Annotated[Lot | NotSaid, Field(discriminator="kind")]


class Stock(_Part):
    """The ticker, and the post's words for it: the ticker itself or a name the playbook maps."""

    ticker: Ticker
    words: Words


class Buy(_Part):
    action: Literal["buy"] = "buy"
    action_words: Words
    stock: Stock
    price: Price
    size: Size


class Sell(_Part):
    action: Literal["sell"] = "sell"
    action_words: Words
    stock: Stock
    price: Price
    share: Share
    # Whether a share counts from the original buy or from what is left; None when the post does
    # not say, which leaves it to the guru's playbook default.
    counts_from: Literal["original", "remaining"] | None = None
    sell_from: SellFrom


type Call = Annotated[Buy | Sell, Field(discriminator="action")]

Summary = Annotated[str, Field(min_length=1, max_length=300)]
Calls = Annotated[tuple[Call, ...], Field(min_length=1, max_length=20)]


class TradeMade(_Part):
    """The guru did it: 加了, 出掉, 买了, 跑路了."""

    kind: Literal["trade_made"] = "trade_made"
    summary: Summary
    calls: Calls


class Instruction(_Part):
    """Do it now: buy NVDA here."""

    kind: Literal["instruction"] = "instruction"
    summary: Summary
    calls: Calls


class Conditional(_Part):
    """If something happens, the guru would trade: 如果明天20以下我会买第一批."""

    kind: Literal["conditional"] = "conditional"
    summary: Summary
    condition: Words
    calls: Calls


class Suggestion(_Part):
    """Consider it, or a zone to trade in: 建仓区域160-179, 可以考虑一点."""

    kind: Literal["suggestion"] = "suggestion"
    summary: Summary
    calls: Calls


class Commentary(_Part):
    """Market talk with nothing to trade."""

    kind: Literal["commentary"] = "commentary"
    summary: Summary


class Unclear(_Part):
    """The reader cannot tell what the post means; a person should look."""

    kind: Literal["unclear"] = "unclear"
    summary: Summary


type PostReading = Annotated[
    TradeMade | Instruction | Conditional | Suggestion | Commentary | Unclear,
    Field(discriminator="kind"),
]
