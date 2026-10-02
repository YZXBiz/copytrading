"""Untrusted model output and deterministic grounding checks."""

import re
import unicodedata
from decimal import Decimal
from typing import Literal, Protocol, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator

from copytrading_engine.parsing.diagnostics import ValidationIssue
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.signals import Evidence

PROMPT_VERSION = "stock-extraction-v2"

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


ExtractedInstruction = Evidence


class DecodedMessage(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)
    decision: Literal["trade", "ignore", "review"]
    reason: str = Field(min_length=1, max_length=300)
    instructions: tuple[ExtractedInstruction, ...] = Field(max_length=20)

    @model_validator(mode="after")
    def consistent_decision(self) -> Self:
        if (self.decision == "trade") != bool(self.instructions):
            raise ValueError("Only trade decisions can contain instructions")
        return self


class DecodeError(Exception):
    """Provider-independent failure; no provider response or secret is retained."""

    def __init__(
        self, reason: str, *, retryable: bool, issues: tuple[ValidationIssue, ...] = ()
    ) -> None:
        self.reason, self.retryable, self.issues = reason, retryable, issues
        super().__init__(reason)


class Decoder(Protocol):
    async def decode(self, text: str, route: Route) -> DecodedMessage: ...


def playbook_maps(playbook: str, phrase: str, symbol: str) -> bool:
    """A name resolves to a ticker only when one playbook line states both."""
    ticker = re.compile(r"(?<![A-Za-z0-9])" + re.escape(symbol) + r"(?![A-Za-z0-9])")
    return any(phrase in line and ticker.search(line) for line in playbook.splitlines())


MASS_MENTIONS = ("@everyone", "@here")


def without_mentions(text: str) -> str:
    for mention in MASS_MENTIONS:
        text = text.replace(mention, "")
    return text.strip()


def normalize(text: str) -> str:
    return without_mentions(unicodedata.normalize("NFKC", text))


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


def validate_grounding(result: DecodedMessage, text: str, route: Route) -> None:
    if result.decision != "trade":
        return
    # Conservative vetoes supplement semantic classification, not a sentence parser.
    if re.search(
        r"如果|假如|计划|附近|突破.*再|昨天.*加了|\b(if|would|might|yesterday)\b", text, re.I
    ):
        raise GroundingError(
            "noncurrent_trade", "<root>", "Conditional or historical language requires review"
        )
    for index, item in enumerate(result.instructions):
        # What the words mean is the model's call, guided by the guru's playbook; the words
        # themselves must be in the post.
        if not item.action_evidence.strip() or item.action_evidence not in text:
            raise GroundingError(
                "action_not_grounded",
                f"instructions.{index}.action_evidence",
                "Action is not supported by source text",
            )
        symbol_text = item.symbol_evidence
        if symbol_text not in text:
            raise GroundingError(
                "symbol_evidence_missing",
                f"instructions.{index}.symbol_evidence",
                "Symbol evidence is absent",
            )
        named = symbol_text.lstrip("$").upper() != item.symbol
        if named and not playbook_maps(route.playbook, symbol_text, item.symbol):
            raise GroundingError(
                "symbol_not_in_playbook",
                f"instructions.{index}.symbol",
                "A company name resolves only when the playbook states its ticker",
            )
        if not named and not re.search(
            r"(?<![A-Za-z0-9])" + re.escape(symbol_text) + r"(?![A-Za-z0-9])", text
        ):
            raise GroundingError(
                "partial_symbol",
                f"instructions.{index}.symbol_evidence",
                "Symbol evidence must be a complete ticker",
            )
        if not number_is_grounded(item.price, item.price_evidence, text):
            raise GroundingError(
                "price_not_grounded",
                f"instructions.{index}.price_evidence",
                "Price is not grounded",
            )
        if item.entry_price is not None and not number_is_grounded(
            item.entry_price, item.entry_evidence, text
        ):
            raise GroundingError(
                "entry_not_grounded",
                f"instructions.{index}.entry_evidence",
                "Entry reference is not grounded",
            )
        if item.entry_price == item.price:
            occurrences = re.findall(r"(?<![\d.])\d+(?:\.\d+)?(?![\d.])", text)
            if sum(Decimal(value) == item.price for value in occurrences) < 2:
                raise GroundingError(
                    "price_occurrence_reused",
                    f"instructions.{index}.entry_evidence",
                    "Current and entry price require distinct source occurrences",
                )
        if item.action == "reduce":
            if item.fraction is None or not allocation_is_grounded(
                item.fraction, item.fraction_evidence, text
            ):
                raise GroundingError(
                    "fraction_not_grounded",
                    f"instructions.{index}.fraction_evidence",
                    "Trim fraction is not explicitly supported",
                )
        if item.action == "buy":
            if item.fraction is None:
                if item.fraction_evidence is not None:
                    raise GroundingError(
                        "fraction_without_value",
                        f"instructions.{index}.fraction_evidence",
                        "Fraction evidence requires a matching fraction",
                    )
                if EXPLICIT_ALLOCATION.search(text):
                    raise GroundingError(
                        "source_fraction_omitted",
                        f"instructions.{index}.fraction",
                        "An explicit source allocation was omitted from a buy",
                    )
            elif not allocation_is_grounded(item.fraction, item.fraction_evidence, text):
                raise GroundingError(
                    "fraction_not_grounded",
                    f"instructions.{index}.fraction_evidence",
                    "Buy fraction is not explicitly supported",
                )
        if item.action == "close" and item.fraction != 1:
            raise GroundingError(
                "invalid_close_fraction",
                f"instructions.{index}.fraction",
                "A close must refer to all remaining shares",
            )
