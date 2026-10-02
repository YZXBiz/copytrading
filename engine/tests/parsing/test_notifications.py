"""Every parser decision has a truthful notification with the real timing problem."""

import datetime as dt

import pytest

from copytrading_engine.parsing.diagnostics import ValidationIssue
from copytrading_engine.parsing.notifications import review_notification
from copytrading_engine.shared.signals import Evidence, Instruction, StockSignal


def signal(decision, reason, *, timestamp="2026-09-21T15:00:00+00:00", text="synthetic"):
    instructions = evidence = ()
    if decision == "trade":
        instruction = Instruction(action="buy", symbol="ABC", price="25")
        instructions = (instruction,)
        evidence = (
            Evidence(
                **instruction.model_dump(),
                action_evidence="加了",
                symbol_evidence="abc",
                price_evidence="25",
            ),
        )
    return StockSignal(
        source="discord",
        channel_id="test",
        id="123",
        timestamp=timestamp,
        text=text,
        parser_profile="stock-extraction-v2",
        model="test",
        decision=decision,
        reason=reason,
        instructions=instructions,
        evidence=evidence,
    )


@pytest.mark.parametrize("reason", ["stale_signal", "future_signal"])
def test_clock_rejections_explain_the_actual_timing_problem(reason):
    notice = review_notification(
        "discord:test:clock",
        signal(decision="review", reason=reason),
        (ValidationIssue(path="instructions.0.price", code="price_not_grounded"),),
    )
    annotations = notice.payload.annotations
    assert annotations["reason"] == reason
    assert "(instructions.0.price: price_not_grounded)" in annotations["evidence"]
    assert "No order can be created" in annotations["impact"]
    if reason == "future_signal":
        assert "ahead of the parser clock" in annotations["evidence"]
        assert "Check the source timestamp and host clock" in annotations["action"]
        assert "exceeded" not in annotations["evidence"]
    else:
        assert "exceeded the permitted processing age" in annotations["evidence"]


def test_future_source_timestamp_is_evidence_not_the_notification_start():
    from copytrading_engine.parsing.notifications import decision_notification

    source_at = "2026-09-21T15:30:00+00:00"
    serialized_source_at = "2026-09-21T15:30:00Z"
    observed_at = "2026-09-21T15:00:00+00:00"
    notice = decision_notification(
        "discord:test:clock",
        signal(decision="review", reason="future_signal", timestamp=source_at),
        (),
        observed_at=dt.datetime.fromisoformat(observed_at),
    )
    assert notice.payload.starts_at == dt.datetime.fromisoformat(observed_at)
    assert notice.payload.annotations["observed_time"] == observed_at
    assert notice.payload.annotations["source_time"] == serialized_source_at


def test_utc_source_timestamp_keeps_canonical_pydantic_z_representation():
    from copytrading_engine.parsing.notifications import decision_notification

    source_at = "2026-09-21T15:30:00Z"
    notice = decision_notification(
        "discord:test:utc",
        signal(decision="review", reason="Commentary", timestamp=source_at),
        (),
    )

    assert notice.payload.annotations["source_time"] == source_at
    assert (
        notice.payload.starts_at
        == signal(decision="review", reason="Commentary", timestamp=source_at).timestamp
    )


@pytest.mark.parametrize("decision", ["trade", "ignore", "review"])
def test_every_parser_decision_has_a_truthful_notification(decision):
    from copytrading_engine.parsing.notifications import decision_notification

    result = signal(
        decision=decision,
        reason="Explicit current action" if decision == "trade" else "Commentary",
        timestamp="2026-09-16T19:15:11+00:00",
        text="25加了abc",
    )
    notice = decision_notification("discord:test:123", result, ())
    assert notice.payload.annotations["source_excerpt"] == "25加了abc"
    if decision == "trade":
        assert "BUY ABC" in notice.payload.annotations["evidence"]
        assert "Explicit current action" not in notice.payload.annotations["evidence"]
        assert "does not confirm an order or fill" in notice.payload.annotations["impact"]
    elif decision == "ignore":
        assert "Signal ignored" in notice.payload.annotations["summary"]
    else:
        assert notice.payload.labels["alertname"] == "SignalNeedsReview"
