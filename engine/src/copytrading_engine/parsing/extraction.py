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
    Chatter,
    Conditional,
    Dollars,
    Exact,
    Fraction,
    Instruction,
    Lot,
    NotGiven,
    PostReading,
    Range,
    ReaderReading,
    Sell,
    Stock,
    Suggestion,
    TradeMade,
)

PROMPT_VERSION = "stock-reading-v7"

# Chinese characters and ASCII letters both count as Unicode word characters.
# Match complete numeric tokens and bound English words by ASCII letters so
# half/full next to Chinese still count as allocations.
EXPLICIT_ALLOCATION = re.compile(
    r"(?P<chinese>(?:\d+|[一二两三四五六七八九十])分之"
    r"(?:\d+|[一二两三四五六七八九十]))"
    r"|(?P<ratio>(?<![\d./])\d+\s*/\s*\d+(?![\d./]))"
    r"|(?P<percent>(?<![\d.])\d+(?:\.\d+)?%(?![\d]))"
    r"|(?P<half>一半|半仓|(?<![A-Za-z])half(?![A-Za-z]))"
    r"|(?P<full>全仓|全部|(?<![A-Za-z])full(?![A-Za-z]))"
    # "a third", "two thirds", "a quarter", "three quarters", "quarter position". A bare "third"
    # is an order ("third time") and a bare "quarter" a season ("next quarter"), so both need a
    # count, or for a quarter the word position or size after it.
    r"|(?P<english>(?<![A-Za-z])(?:(?:an?|one|two|three|four|[1-9])[\s-]+"
    r"(?:third|quarter|fourth|fifth|sixth|seventh|eighth|ninth|tenth)s?"
    r"|quarter(?=[\s-]+(?:position|pos|size)(?![A-Za-z])))(?![A-Za-z]))",
    re.I,
)

_ENGLISH_COUNTS = {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4}
_ENGLISH_PARTS = {
    "third": 3,
    "quarter": 4,
    "fourth": 4,
    "fifth": 5,
    "sixth": 6,
    "seventh": 7,
    "eighth": 8,
    "ninth": 9,
    "tenth": 10,
}


class DecodeError(Exception):
    """Provider-independent failure; no provider response or secret is retained."""

    def __init__(
        self, reason: str, *, retryable: bool, issues: tuple[ValidationIssue, ...] = ()
    ) -> None:
        self.reason, self.retryable, self.issues = reason, retryable, issues
        super().__init__(reason)


class ReadingOutput(BaseModel):
    """Anything about stocks or the market: a trade made or to make, a plan, market talk, or a
    post about a trade that cannot be pinned down. One reading of the post."""

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)
    reading: ReaderReading


class JustChat(BaseModel):
    """Small talk with nothing about stocks or the market: a greeting, a reaction, an emoji,
    such as "hi", "how's going", "早上好", or "👍"."""

    model_config = ConfigDict(extra="forbid", frozen=True)


@dataclass(frozen=True)
class Answer:
    """A reading and the model that gave it."""

    reading: PostReading
    model: str | None = None


@dataclass(frozen=True)
class ReadingInput:
    """The post as the checks see it, its guru's route, and the guru's recent calls, so a failed
    check can go back to the model with its reason."""

    text: str
    route: Route
    recent: tuple[RecentCall, ...] = ()


class Decoder(Protocol):
    async def answer(self, text: str, route: Route, recent: tuple[RecentCall, ...] = ()) -> Answer:
        """The post read, and which model answered."""
        ...


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
    elif match.lastgroup == "english":
        *count, part = re.split(r"[\s-]+", token)
        written = count[0] if count else "one"
        numerator = int(written) if written.isdigit() else _ENGLISH_COUNTS[written]
        value = Decimal(numerator) / Decimal(_ENGLISH_PARTS[part.removesuffix("s")])
        return value if value <= 1 else None
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

# An amount as written: 1,500, 200, 2.5, 两百, 一千五.
_AMOUNT = (
    r"(?P<{name}>\d{{1,3}}(?:,\d{{3}})+(?:\.\d+)?|\d+(?:\.\d+)?"
    r"|[一二两三四五六七八九十百千万]+)"
)
# A dollar amount to put in, as a size: "$200 of", "200$ of", "$200 worth", "200 dollars",
# "200 bucks", 200刀, 两百刀, 200美元, 200美金, 200块. A bare "$71" is a price, never a size.
DOLLAR_SIZE = re.compile(
    r"\$\s*" + _AMOUNT.format(name="before") + r"\s+(?:of|worth|in)\b"
    r"|(?<![\d.,])" + _AMOUNT.format(name="after") + r"\s*\$\s*(?:of|worth|in)\b"
    r"|(?<![\d.,])" + _AMOUNT.format(name="word") + r"\s*(?:dollars?|bucks|usd|刀|美元|美金|块)",
    re.I,
)
_CHINESE_UNITS = {"十": 10, "百": 100, "千": 1000, "万": 10000}


def _chinese_amount(words: str) -> Decimal | None:
    """两百 is 200, 一千五 is 1500, 五百 is 500; None when it is not a plain amount."""
    total, current = 0, 0
    for char in words:
        if char in _CHINESE_DIGITS and _CHINESE_DIGITS[char] < 10:
            current = _CHINESE_DIGITS[char]
        elif char in _CHINESE_UNITS:
            total += (current or 1) * _CHINESE_UNITS[char]
            current = 0
        else:
            return None
    if current:
        # A trailing digit after a unit is one step down: 一千五 is 1500.
        last_unit = next((_CHINESE_UNITS[c] for c in reversed(words) if c in _CHINESE_UNITS), 10)
        total += current * (last_unit // 10 if total else 1)
    return Decimal(total) if total else None


def _dollar_value(match: re.Match[str]) -> Decimal | None:
    raw = next(group for group in match.groups() if group)
    if re.fullmatch(r"[\d,.]+", raw):
        return Decimal(raw.replace(",", ""))
    return _chinese_amount(raw)


def dollars_are_grounded(value: Decimal, evidence: str | None, text: str) -> bool:
    """The cited words are in the post and hold exactly one dollar amount, of that value: the
    post's size ("$200 of", "200 dollars"), or only its amount ("$200") when the post states that
    amount as a size. A price with a dollar sign ("at $71") is never a size."""
    if not evidence or evidence not in text:
        return False
    found = list(DOLLAR_SIZE.finditer(evidence))
    if found:
        return len(found) == 1 and _dollar_value(found[0]) == value
    amount = _CITED_AMOUNT.fullmatch(evidence.strip())
    return (
        amount is not None
        and Decimal(next(group for group in amount.groups() if group).replace(",", "")) == value
        and any(
            _dollar_value(size) == value and size.group(0).startswith(evidence.strip())
            for size in DOLLAR_SIZE.finditer(text)
        )
    )


# Only the amount of a dollar size, as a reader may cite it: "$200" of "$200 of", "200$" of
# "200$ of".
_CITED_AMOUNT = re.compile(r"\$\s*([\d,]+(?:\.\d+)?)|([\d,]+(?:\.\d+)?)\s*\$")


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
    # "Half" is half of what is left (ADR-0010). A sell may count from the original buy only
    # when the post's own words, or the playbook's, say so: the model reads, and never assumes.
    if call.counts_from == "original":
        if call.counts_from_words is None:
            raise GroundingError(
                "counts_from_not_grounded",
                f"{path}.counts_from",
                "counts_from original needs counts_from_words, the words of the post that say "
                "the share is of the original buy; leave counts_from out when the post does not",
            )
        _words(call.counts_from_words, text, f"{path}.counts_from_words")
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
    # Posts often glue a ticker to its price ("14.1nfxl"). A ticker of three or more letters may
    # touch a number; a shorter one may not, so "10pm" never reads as PM or "50k" as K.
    edge = "A-Za-z" if len(stock.words.lstrip("$")) >= 3 else "A-Za-z0-9"
    if not named and not re.search(
        rf"(?<![{edge}])" + re.escape(stock.words) + rf"(?![{edge}])", text
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
    elif isinstance(size, Dollars):
        if not dollars_are_grounded(size.value, size.words, text):
            raise GroundingError(
                "dollars_not_grounded",
                path,
                "words must be the post's dollar amount, such as $200 of or 200 dollars",
            )
    elif isinstance(size, NotGiven) and EXPLICIT_ALLOCATION.search(text):
        raise GroundingError("source_fraction_omitted", path, "The post states a size")
    elif isinstance(size, NotGiven) and DOLLAR_SIZE.search(text):
        raise GroundingError("source_dollars_omitted", path, "The post states a dollar amount")


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


def _has_chinese(text: str) -> bool:
    return any("\u3400" <= char <= "\u9fff" or "\uf900" <= char <= "\ufaff" for char in text)


def check_summary_language(reading: PostReading, text: str, *, retried: bool) -> str | None:
    """The summary is written in the post's own language. A post with no Chinese in it gets a
    summary with none either: the reader's examples are Chinese and can pull it there. Asked
    about once; a second answer stands, since a summary is read, never traded on."""
    if isinstance(reading, Chatter) or retried or _has_chinese(text):
        return None
    if not _has_chinese(reading.summary):
        return None
    return "summary: write it in the post's own language, which is English here, not Chinese"


def _side(action: str) -> str:
    return "buy" if action == "buy" else "sell"


def same_side(earlier: RecentCall, call: Buy | Sell) -> bool:
    """Whether a call can restate `earlier`: a buy restates a buy, a sell restates a sell or a
    close. A sell is never a repeat of the buy it sells."""
    return _side(earlier.action) == call.action


def check_references(
    reading: PostReading, recent: tuple[RecentCall, ...], *, retried: bool
) -> str | None:
    """What is wrong with how a reading names the guru's recent calls, if anything. A repeat
    must name a listed call of the same stock and kind, buy or sell. A sell naming a buy price
    none of the guru's open buys of that stock has is asked about once: the guru may hold buys
    from before CopyTrading started, so a second answer stands."""
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
            if not same_side(earlier, call):
                return (
                    f"calls.{index}.repeats: {call.repeats} is a {_side(earlier.action)} and "
                    f"this call is a {call.action}; a repeat restates a call of the same kind, "
                    "so leave repeats empty."
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
