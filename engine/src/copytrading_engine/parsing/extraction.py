"""The model's reading of a post is untrusted: plain checks hold it to the post's own words."""

import re
import unicodedata
from dataclasses import dataclass
from decimal import Decimal
from typing import Protocol

from pydantic import BaseModel, ConfigDict

from copytrading_engine.parsing.diagnostics import ValidationIssue
from copytrading_engine.parsing.history import RecentCall
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.reading import (
    All,
    AtMarket,
    Batch,
    Buy,
    Call,
    Conditional,
    Exact,
    Fraction,
    Instruction,
    Lot,
    NotGiven,
    PostReading,
    Range,
    Sell,
    Stock,
    Suggestion,
    TradeMade,
)

PROMPT_VERSION = "stock-reading-v4"

# Chinese characters and ASCII letters both count as Unicode word characters.
# Match complete numeric tokens and bound English words by ASCII letters so
# half/full next to Chinese still count as allocations.
EXPLICIT_ALLOCATION = re.compile(
    r"(?P<chinese>(?:\d+|[一二两三四五六七八九十])分之"
    r"(?:\d+|[一二两三四五六七八九十]))"
    r"|(?P<ratio>(?<![\d./])\d+\s*/\s*\d+(?![\d./]))"
    r"|(?P<percent>(?<![\d.])\d+(?:\.\d+)?%(?![\d]))"
    r"|(?P<half>一半|半仓|(?<![A-Za-z])half(?![A-Za-z]))"
    r"|(?P<full>全仓|全部|(?<![A-Za-z])full(?![A-Za-z]))",
    re.I,
)


class DecodeError(Exception):
    """Provider-independent failure; no provider response or secret is retained."""

    def __init__(
        self, reason: str, *, retryable: bool, issues: tuple[ValidationIssue, ...] = ()
    ) -> None:
        self.reason, self.retryable, self.issues = reason, retryable, issues
        super().__init__(reason)


class ReadingOutput(BaseModel):
    """What the reader model returns: one reading of the post."""

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)
    reading: PostReading


@dataclass(frozen=True)
class ReadingInput:
    """The post as the checks see it, its guru's route, and the guru's recent calls, so a failed
    check can go back to the model with its reason."""

    text: str
    route: Route
    recent: tuple[RecentCall, ...] = ()


class Decoder(Protocol):
    async def decode(
        self, text: str, route: Route, recent: tuple[RecentCall, ...] = ()
    ) -> PostReading: ...


def playbook_maps(playbook: str, phrase: str, symbol: str) -> bool:
    """A name resolves to a ticker only when one playbook line states both."""
    ticker = re.compile(r"(?<![A-Za-z0-9])" + re.escape(symbol) + r"(?![A-Za-z0-9])")
    return any(phrase in line and ticker.search(line) for line in playbook.splitlines())


_PLAYBOOK_SIZE = re.compile(
    r"^\s*(?P<words>.+?)\s+means\s+(?:sell\s+|buy\s+)?(?P<size>\d+/\d+|\d*\.\d+|half|all)\s*$",
    re.IGNORECASE,
)


def playbook_size(playbook: str, words: str) -> Decimal | None:
    """The size the owner's playbook gives a guru's own words, as in "减仓 means 1/2" or
    "第二批 means 1/3" (ADR-0010); None when no line names these words."""
    for line in playbook.splitlines():
        match = _PLAYBOOK_SIZE.match(line)
        if match is None or match.group("words").strip().strip('"“”') != words.strip():
            continue
        size = match.group("size").lower()
        if size == "half":
            return Decimal("0.5")
        if size == "all":
            return Decimal(1)
        if "/" in size:
            numerator, denominator = (Decimal(part) for part in size.split("/"))
            return numerator / denominator if denominator else None
        return Decimal(size)
    return None


MASS_MENTIONS = ("@everyone", "@here")


def without_mentions(text: str) -> str:
    for mention in MASS_MENTIONS:
        text = text.replace(mention, "")
    return text.strip()


# A Chinese keyboard types the full stop as a decimal point: "381。3" or "16 。1" is 381.3 or
# 16.1. Only a stop between two digits is a decimal point; one ending a sentence stays.
CHINESE_DECIMAL_POINT = re.compile(r"(?<=\d)\s*[。｡]\s*(?=\d)")


def normalize(text: str) -> str:
    """The post as the reader and its checks see it: compatibility forms folded, Chinese
    decimal points written as ".", and mass mentions removed."""
    text = unicodedata.normalize("NFKC", text)
    return without_mentions(CHINESE_DECIMAL_POINT.sub(".", text))


# Models write 1/6 as 0.16666666666666666; Decimal division gives 28 digits. Same fraction.
FRACTION_TOLERANCE = Decimal("1e-9")


def same_fraction(first: Decimal | None, second: Decimal | None) -> bool:
    """Both absent, or equal within rounding."""
    if first is None or second is None:
        return first is second
    return abs(first - second) <= FRACTION_TOLERANCE


def number_is_grounded(value: Decimal, evidence: str | None, text: str) -> bool:
    if not evidence or evidence not in text or not re.fullmatch(r"\d+(?:\.\d+)?", evidence):
        return False
    # Require a complete numeric token, not 25 extracted from 125 or 25.8.
    return Decimal(evidence) == value and bool(
        re.search(r"(?<![\d.])" + re.escape(evidence) + r"(?![\d.])", text)
    )


def allocation_is_grounded(value: Decimal, evidence: str | None, text: str) -> bool:
    """The cited evidence is in the post and covers exactly one complete allocation token (read
    as a whole token of the post, so "half" inside "halfway" never counts) of that value."""
    if not evidence:
        return False
    tokens = list(EXPLICIT_ALLOCATION.finditer(text))
    start = text.find(evidence)
    while start != -1:
        end = start + len(evidence)
        inside = [token for token in tokens if start <= token.start() and token.end() <= end]
        if len(inside) == 1 and same_fraction(_allocation_value(inside[0]), value):
            return True
        start = text.find(evidence, start + 1)
    return False


def _allocation_value(match: re.Match[str]) -> Decimal | None:
    """Read the value of a complete source allocation token, if valid."""
    token = match.group().lower()
    chinese = {
        "一": 1,
        "二": 2,
        "两": 2,
        "三": 3,
        "四": 4,
        "五": 5,
        "六": 6,
        "七": 7,
        "八": 8,
        "九": 9,
        "十": 10,
    }

    def integer(part: str) -> int | None:
        if part.isascii() and part.isdigit():
            return int(part)
        if part in chinese:
            return chinese[part]
        return None

    if match.lastgroup == "chinese":
        denominator_text, numerator_text = token.split("分之", 1)
        denominator, numerator = integer(denominator_text), integer(numerator_text)
        if denominator and numerator:
            return Decimal(numerator) / Decimal(denominator)
    elif match.lastgroup == "ratio":
        numerator_text, denominator_text = token.split("/", 1)
        denominator = int(denominator_text.strip())
        if denominator:
            return Decimal(numerator_text.strip()) / Decimal(denominator)
    elif match.lastgroup == "percent":
        return Decimal(token[:-1]) / 100
    elif match.lastgroup == "half":
        return Decimal("0.5")
    elif match.lastgroup == "full":
        return Decimal(1)
    return None


class GroundingError(ValueError):
    def __init__(self, code: str, path: str, explanation: str) -> None:
        self.issue = ValidationIssue(path=path, code=code)
        super().__init__(explanation)


# Words that make a trade conditional or historical. A reading that calls such a post a trade
# made or an instruction goes back to the model.
NONCURRENT = re.compile(
    r"如果|假如|计划|附近|突破.*再|昨天.*加了|\b(if|would|might|yesterday)\b", re.I
)

# The batch number as written: 第二批, 第2批, batch 2.
BATCH_NUMBER = re.compile(r"第\s*(\d+|[一二两三四五六七八九十])\s*批|batch\s*(\d+)", re.I)
_CHINESE_DIGITS = dict(zip("一二三四五六七八九十", range(1, 11), strict=True)) | {"两": 2}


def check_reading(reading: PostReading, text: str, route: Route) -> None:
    """Every stated value must be the post's own words, a name a ticker only through the
    playbook, and a trade must not be conditional or historical. Raises GroundingError."""
    if not isinstance(reading, TradeMade | Instruction | Conditional | Suggestion):
        return
    if isinstance(reading, TradeMade | Instruction) and NONCURRENT.search(text):
        raise GroundingError(
            "noncurrent_trade", "kind", "Conditional or historical words make this not a trade"
        )
    if isinstance(reading, Conditional):
        _words(reading.condition, text, "condition")
    for index, call in enumerate(reading.calls):
        _check_call(call, text, route, f"calls.{index}")


def _check_call(call: Call, text: str, route: Route, path: str) -> None:
    _words(call.action_words, text, f"{path}.action_words")
    _check_stock(call.stock, text, route, f"{path}.stock")
    _check_price(call.price, text, f"{path}.price")
    if isinstance(call, Buy):
        _check_size(call, text, route.playbook, f"{path}.size")
        return
    _check_share(call, text, route.playbook, f"{path}.share")
    if isinstance(call.sell_from, Lot):
        _number(call.sell_from.buy_price, call.sell_from.words, text, f"{path}.sell_from")
        if isinstance(call.price, Exact) and call.price.value == call.sell_from.buy_price:
            occurrences = re.findall(r"(?<![\d.])\d+(?:\.\d+)?(?![\d.])", text)
            if sum(Decimal(value) == call.price.value for value in occurrences) < 2:
                raise GroundingError(
                    "price_occurrence_reused",
                    f"{path}.sell_from",
                    "The current price and the buy price need two numbers in the post",
                )


def _check_stock(stock: Stock, text: str, route: Route, path: str) -> None:
    _words(stock.words, text, path)
    named = stock.words.lstrip("$").upper() != stock.ticker
    if named and not playbook_maps(route.playbook, stock.words, stock.ticker):
        raise GroundingError(
            "symbol_not_in_playbook",
            path,
            "A company name becomes a ticker only when the playbook says so",
        )
    if not named and not re.search(
        r"(?<![A-Za-z0-9])" + re.escape(stock.words) + r"(?![A-Za-z0-9])", text
    ):
        raise GroundingError("partial_symbol", path, "The ticker must be a whole word in the post")


def _check_price(price: object, text: str, path: str) -> None:
    if isinstance(price, Exact):
        _number(price.value, price.words, text, path)
    elif isinstance(price, Range):
        _number(price.low, price.low_words, text, f"{path}.low")
        _number(price.high, price.high_words, text, f"{path}.high")
    elif isinstance(price, AtMarket):
        _words(price.words, text, path)


def _check_size(buy: Buy, text: str, playbook: str, path: str) -> None:
    size = buy.size
    if isinstance(size, Fraction):
        if not allocation_is_grounded(size.value, size.words, text) and not _playbook_sized(
            size.value, size.words, text, playbook
        ):
            raise GroundingError("fraction_not_grounded", path, "The size is not in the post")
    elif isinstance(size, Batch):
        _words(size.words, text, path)
        match = BATCH_NUMBER.search(size.words)
        written = match and (match.group(1) or match.group(2))
        number = None
        if written:
            number = int(written) if written.isdigit() else _CHINESE_DIGITS.get(written)
        if number != size.number:
            raise GroundingError("batch_not_grounded", path, "The batch number is not in the post")
    elif isinstance(size, NotGiven) and EXPLICIT_ALLOCATION.search(text):
        raise GroundingError("source_fraction_omitted", path, "The post states a size")


def _check_share(sell: Sell, text: str, playbook: str, path: str) -> None:
    share = sell.share
    if isinstance(share, All):
        _words(share.words, text, path)
    elif isinstance(share, NotGiven):
        if EXPLICIT_ALLOCATION.search(text):
            raise GroundingError("source_fraction_omitted", path, "The post states a share")
    elif not allocation_is_grounded(share.value, share.words, text) and not _playbook_sized(
        share.value, share.words, text, playbook
    ):
        raise GroundingError("fraction_not_grounded", path, "The share is not in the post")


def _playbook_sized(value: Decimal, words: str, text: str, playbook: str) -> bool:
    """The words are in the post and the owner's playbook gives them exactly this size."""
    sized = playbook_size(playbook, words) if words and words in text else None
    return sized is not None and same_fraction(sized, value)


def _words(words: str, text: str, path: str) -> None:
    if not words.strip() or words not in text:
        raise GroundingError(
            "words_not_in_post", path, "words must be copied exactly from the post"
        )


def _number(value: Decimal, words: str, text: str, path: str) -> None:
    if not number_is_grounded(value, words, text):
        raise GroundingError(
            "number_not_grounded",
            path,
            f"words must be only this number exactly as the post writes it, such as {value}",
        )


def check_references(
    reading: PostReading, recent: tuple[RecentCall, ...], *, retried: bool
) -> str | None:
    """What is wrong with how a reading names the guru's recent calls, if anything. A repeat
    must name a listed call of the same stock. A sell naming a buy price none of the guru's open
    buys of that stock has is asked about once: the guru may hold buys from before CopyTrading
    started, so a second answer stands."""
    if not isinstance(reading, TradeMade | Instruction | Conditional | Suggestion):
        return None
    by_ref = {call.ref: call for call in recent}
    for index, call in enumerate(reading.calls):
        if call.repeats is not None:
            earlier = by_ref.get(call.repeats)
            if earlier is None:
                return (
                    f"calls.{index}.repeats: {call.repeats} is not one of the listed calls; "
                    "name a listed reference or leave repeats empty."
                )
            if earlier.symbol != call.stock.ticker:
                return (
                    f"calls.{index}.repeats: {call.repeats} is {earlier.symbol}, not "
                    f"{call.stock.ticker}; a repeat restates a call of the same stock."
                )
        if retried or not isinstance(call, Sell) or not isinstance(call.sell_from, Lot):
            continue
        held = sorted(
            {
                listed.price
                for listed in recent
                if listed.open
                and listed.action == "buy"
                and listed.symbol == call.stock.ticker
                and listed.price is not None
            }
        )
        if held and call.sell_from.buy_price not in held:
            prices = ", ".join(str(price) for price in held)
            return (
                f"calls.{index}.sell_from: the guru's open {call.stock.ticker} buys are at "
                f"{prices}, not {call.sell_from.buy_price}. Read the post again: name one of "
                "those if the post means it, or keep the post's own price."
            )
    return None
