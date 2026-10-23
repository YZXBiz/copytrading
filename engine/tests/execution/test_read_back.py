"""Posts read back after CopyTrading was off (ADR-0010): each one is on the timeline, and the
owner hears about them once, not once per post."""

import datetime as dt

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.events import Skipped as SkippedEvent
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.presentation.notifications import execution_notification
from copytrading_engine.execution.presentation.operator_views import destination_views

from .builders import NOW, deliver, event, evidence
from .fakes import FakeBroker, MemoryRepository

BACK = NOW + dt.timedelta(hours=2)


class NotifyingRepository(MemoryRepository):
    """Keeps the notifications the account's store would send, as it commits each event."""

    def __init__(self) -> None:
        super().__init__()
        self.sent: list[tuple[str, str]] = []

    def save(self, snapshot, event) -> None:
        super().save(snapshot, event)
        if (notification := execution_notification(snapshot, event)) is not None:
            annotations = notification.payload.annotations
            self.sent.append((annotations["summary"], annotations["evidence"]))


def _engine() -> tuple[CopyEngine, NotifyingRepository, FakeBroker]:
    repository, broker = NotifyingRepository(), FakeBroker()
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    deliver(engine, event())
    repository.sent.clear()
    return engine, repository, broker


def _on(symbol, *args, **kwargs):
    post = event(*args, **kwargs)
    post["instructions"][0]["symbol"] = symbol
    post["evidence"] = [evidence(instruction) for instruction in post["instructions"]]
    return post


def _mixed(post_id: str, posted: dt.datetime):
    """A post that sells ABC and buys DEF."""
    post = event(post_id, "close", "27", "25", timestamp=posted)
    post["instructions"].append({**_on("DEF", price="20")["instructions"][0]})
    post["evidence"] = [evidence(instruction) for instruction in post["instructions"]]
    return post


def test_a_late_posts_buy_skipped_as_too_old_is_on_its_timeline():
    engine, repository, _ = _engine()

    deliver(engine, _mixed("mixed", NOW + dt.timedelta(minutes=1)), BACK)

    skips = [
        (e.payload.part, e.payload.reason)
        for e in repository.events
        if isinstance(e.payload, SkippedEvent) and e.payload.message_id == "discord:demo:mixed"
    ]
    assert skips == [(1, "stale")]
    view = destination_views(
        engine.ledger.snapshot(), {"discord:demo:mixed"}, tuple(repository.events)
    )
    timeline = view["discord:demo:mixed"].timeline
    assert ("skipped", "stale") in [(step.step, step.reason) for step in timeline]


def test_posts_read_back_after_a_stop_are_reported_once():
    """A weekend away: three buys and a post that sells ABC and buys DEF are read back at once.
    The owner gets one message saying what was read, not a "Trade skipped" for each."""
    engine, repository, _ = _engine()
    for index in range(3):
        posted = NOW + dt.timedelta(minutes=1 + index)
        deliver(engine, _on("GHI", f"buy-{index}", timestamp=posted), BACK)
    deliver(engine, _mixed("mixed", NOW + dt.timedelta(minutes=5)), BACK)

    engine.process(BACK + dt.timedelta(seconds=61))
    engine.process(BACK + dt.timedelta(seconds=120))

    summaries = [sent for sent in repository.sent if "while CopyTrading was off" in sent[0]]
    assert summaries == [
        (
            "Read 4 posts posted while CopyTrading was off",
            "1 sell copied, 4 buys too old to copy",
        )
    ]
    assert not [sent for sent in repository.sent if sent[0] == "Trade skipped"]
    assert not [sent for sent in repository.sent if "trade skipped" in sent[0]]
