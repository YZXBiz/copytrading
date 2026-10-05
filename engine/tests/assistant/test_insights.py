"""Counting rules of the assistant's insights, on hand-built operator views."""

import datetime as dt
from decimal import Decimal

import pytest

from copytrading_engine.assistant.insights import explain_skip, guru_record
from copytrading_engine.execution.presentation.operator_views import DestinationView
from copytrading_engine.shared.signals import Instruction
from copytrading_engine.trading.presentation.operator_models import (
    SourceActivity,
    SourceActivityPage,
    SourceEventEvidence,
)

NOW = dt.datetime(2026, 9, 30, 15, 0, tzinfo=dt.UTC)


def destination(account_id: str, *outcomes: str) -> DestinationView:
    return DestinationView(
        account_id=account_id,
        environment="paper",
        status="done",
        instruction_outcomes=outcomes,
        limits_hit=(),
        orders=(),
    )


def call(source_id: str, *destinations: DestinationView) -> SourceActivity:
    return SourceActivity(
        sequence=1,
        source_id=source_id,
        source_revision=1,
        source_at=NOW,
        captured_at=NOW,
        text=f"ZHAO: {source_id}",
        capture_status="complete",
        parse_status="parsed",
        delivery_status="delivered",
        decision="trade",
        parser_reason=None,
        parser_profile=None,
        interpreted_by=None,
        instructions=(Instruction(action="buy", symbol="NVDA", price=Decimal("125")),),
        guru_id="zhao",
        source_event=SourceEventEvidence(
            event_type="raw_message",
            content="",
            embeds=(),
            attachments=(),
            attachments_omitted=0,
            capture_status="complete",
            payload_bytes=0,
        ),
        destinations=destinations,
    )


class FakeOperator:
    def __init__(self, *items: SourceActivity) -> None:
        self.items = items

    async def source_activity(self, before_seq: int | None, limit: int) -> SourceActivityPage:
        return SourceActivityPage(items=self.items, rejected_items=())


async def test_a_pending_call_is_neither_copied_nor_skipped():
    operator = FakeOperator(call("a", destination("one", "pending"), destination("two", "pending")))

    record = await guru_record(operator, "zhao", 7, NOW)

    assert (record.calls, record.copied, record.skipped) == (1, 0, {})


async def test_a_call_skipped_in_two_accounts_for_one_reason_counts_once():
    operator = FakeOperator(
        call("a", destination("one", "insufficient_cash"), destination("two", "insufficient_cash"))
    )

    record = await guru_record(operator, "zhao", 7, NOW)

    assert (record.copied, record.skipped) == (0, {"insufficient_cash": 1})


async def test_a_call_copied_in_one_account_and_skipped_in_another_counts_as_copied():
    operator = FakeOperator(
        call("a", destination("one", "order_linked"), destination("two", "insufficient_cash"))
    )

    record = await guru_record(operator, "zhao", 7, NOW)

    assert (record.copied, record.skipped) == (1, {})


async def test_a_call_with_different_reasons_in_two_accounts_counts_each_reason_once():
    operator = FakeOperator(
        call("a", destination("one", "insufficient_cash"), destination("two", "stale"))
    )

    record = await guru_record(operator, "zhao", 7, NOW)

    assert record.skipped == {"insufficient_cash": 1, "stale": 1}


async def test_explaining_an_unknown_post_raises_key_error():
    with pytest.raises(KeyError):
        await explain_skip(FakeOperator(call("a", destination("one", "stale"))), "missing")


async def test_a_pending_outcome_reads_as_still_being_processed():
    operator = FakeOperator(call("a", destination("one", "pending")))

    explanation = await explain_skip(operator, "a")

    assert [(i.outcome, i.reason) for i in explanation.accounts] == [
        ("pending", "Still being processed.")
    ]


class StuckOperator(FakeOperator):
    """A pager whose next page always points at the same place."""

    def __init__(self, *items: SourceActivity) -> None:
        super().__init__(*items)
        self.pages = 0

    async def source_activity(self, before_seq: int | None, limit: int) -> SourceActivityPage:
        self.pages += 1
        return SourceActivityPage(items=self.items, rejected_items=(), next_before_seq=7)


async def test_a_page_that_does_not_move_back_ends_the_reading():
    operator = StuckOperator(call("a", destination("one", "order_linked")))

    record = await guru_record(operator, "zhao", 7, NOW)

    assert operator.pages == 2
    assert record.calls == 2
