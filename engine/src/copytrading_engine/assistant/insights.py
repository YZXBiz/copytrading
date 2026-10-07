"""What the assistant may know beyond the agent API, read from the existing operator views."""

import datetime as dt
from collections import Counter
from decimal import Decimal
from typing import Protocol

from pydantic import BaseModel, ConfigDict

from copytrading_engine.execution.presentation.notifications import REASONS
from copytrading_engine.trading.presentation.operator_models import (
    SourceActivity,
    SourceActivityPage,
)

PAGE = 100
# An order went out: copied by itself, or approved by the owner from a held call.
FILLED = {"order_linked", "approved_by_owner"}
PENDING = "pending"


class Operator(Protocol):
    async def source_activity(self, before_seq: int | None, limit: int) -> SourceActivityPage: ...


class AccountOutcome(BaseModel):
    model_config = ConfigDict(frozen=True)
    account_id: str
    outcome: str
    reason: str


class SkipExplanation(BaseModel):
    model_config = ConfigDict(frozen=True)
    source_id: str
    untrusted_source_text: str
    understood_as: list[str]
    accounts: list[AccountOutcome]


class GuruRecord(BaseModel):
    model_config = ConfigDict(frozen=True)
    guru_id: str
    days: int
    posts: int
    calls: int
    copied: int
    skipped: dict[str, int]


def _money(value: Decimal) -> str:
    return f"${value.normalize():f}"


def _reason(code: str) -> str:
    if code in FILLED:
        return "An order was placed."
    if code == PENDING:
        return "Still being processed."
    return REASONS.get(code, code.replace("_", " "))


async def _items(operator: Operator, since: dt.datetime | None = None) -> list[SourceActivity]:
    items: list[SourceActivity] = []
    before: int | None = None
    while True:
        page = await operator.source_activity(before, PAGE)
        for item in page.items:
            if since is not None and item.source_at < since:
                return items
            items.append(item)
        # A page that does not move further back would repeat forever; it is the last one.
        if page.next_before_seq is None or (before is not None and page.next_before_seq >= before):
            return items
        before = page.next_before_seq


async def guru_record(operator: Operator, guru_id: str, days: int, now: dt.datetime) -> GuruRecord:
    """Counts per call (a post with instructions): copied when any account linked an order.

    Every other call that is not still pending adds each distinct skip reason across its
    accounts once.
    """
    since = now - dt.timedelta(days=days)
    mine = [item for item in await _items(operator, since) if item.guru_id == guru_id]
    calls = [item for item in mine if item.instructions]
    copied = 0
    skipped: Counter[str] = Counter()
    for item in calls:
        codes = {code for d in item.destinations for code in d.instruction_outcomes}
        if codes & FILLED:
            copied += 1
        elif PENDING not in codes:
            skipped.update(codes)
    return GuruRecord(
        guru_id=guru_id,
        days=days,
        posts=len(mine),
        calls=len(calls),
        copied=copied,
        skipped=dict(skipped),
    )


async def explain_skip(operator: Operator, source_id: str) -> SkipExplanation:
    item = next((i for i in await _items(operator) if i.source_id == source_id), None)
    if item is None:
        raise KeyError(source_id)
    return SkipExplanation(
        source_id=source_id,
        untrusted_source_text=item.text,
        understood_as=[f"{i.action} {i.symbol} at {_money(i.price)}" for i in item.instructions],
        accounts=[
            AccountOutcome(account_id=d.account_id, outcome=code, reason=_reason(code))
            for d in item.destinations
            for code in d.instruction_outcomes
        ],
    )
