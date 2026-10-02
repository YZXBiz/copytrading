"""Deterministic parser for the published engine self-test fixture."""

import re
from decimal import Decimal, InvalidOperation
from fractions import Fraction

from copytrading_engine.host.errors import UnsupportedSelfTest
from copytrading_engine.host.self_test.model import ParsedSelfTest

_SIMULATION_TEXT = re.compile(
    r"Bought\s+(?P<symbol>[A-Z][A-Z0-9.-]{0,9})\s+"
    r"(?P<quantity>\d+(?:/\d+|\.\d+)?)\s+at\s+"
    r"(?P<price>\d+(?:\.\d{1,4})?)"
)


class SelfTestParser:
    """Parse the deliberately narrow local self-test grammar without network calls."""

    def parse(self, text: str) -> ParsedSelfTest:
        match = _SIMULATION_TEXT.fullmatch(text)
        if match is None:
            raise UnsupportedSelfTest("unsupported self-test text")

        try:
            quantity = Fraction(match.group("quantity"))
            unit_price = Decimal(match.group("price"))
        except (ValueError, ZeroDivisionError, InvalidOperation) as exc:
            raise UnsupportedSelfTest("unsupported self-test text") from exc
        if quantity <= 0 or unit_price <= 0:
            raise UnsupportedSelfTest("unsupported self-test text")

        return ParsedSelfTest(
            symbol=match.group("symbol"),
            action="buy",
            quantity=quantity,
            unit_price=unit_price,
        )
