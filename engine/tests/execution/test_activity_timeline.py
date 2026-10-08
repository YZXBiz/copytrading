"""Activity's timeline: every step a post took in an account, read from the account's journal,
and why an order ended unfilled."""

import datetime as dt

from copytrading_engine.execution.application.engine import CopyEngine
from copytrading_engine.execution.domain.events import AccountControlChanged, JournalEvent
from copytrading_engine.execution.domain.lifecycle import (
    AccountControlCommand,
    AccountControlResult,
)
from copytrading_engine.execution.domain.signals import CopyConfig
from copytrading_engine.execution.presentation.operator_views import destination_views
from copytrading_engine.shared.signals import StockSignal

from .builders import NOW, event, receive
from .fakes import FakeBroker, MemoryRepository

SOURCE = "discord:demo:1"


def system(*, auto_fill: bool) -> tuple[MemoryRepository, FakeBroker, CopyEngine]:
    repository = MemoryRepository()
    broker = FakeBroker()
    broker.auto_fill = auto_fill
    engine = CopyEngine(repository, broker, CopyConfig(sources=["discord:demo"]))
    engine.bind(NOW)
    receive(engine, StockSignal.model_validate(event()), NOW)
    return repository, broker, engine


def view(repository: MemoryRepository, engine: CopyEngine, *extra: JournalEvent):
    events = (*repository.events, *extra)
    return destination_views(engine.ledger.snapshot(), {SOURCE}, events)[SOURCE]


def test_a_filled_buy_shows_each_step_with_its_time():
    repository, _, engine = system(auto_fill=True)
    engine.process(NOW)
    engine.reconcile(NOW + dt.timedelta(seconds=1))

    destination = view(repository, engine)

    steps = [step.step for step in destination.timeline]
    assert steps[:3] == ["received", "sized", "sent"]
    assert steps[-1] == "filled"
    assert all(
        a.at <= b.at for a, b in zip(destination.timeline, destination.timeline[1:], strict=False)
    )
    [order] = destination.orders
    assert order.order_type == "limit"
    assert order.submitted_at is not None
    assert order.source_price is not None
    assert order.cancel_reason is None


def test_an_unfilled_buy_says_it_was_cancelled_for_running_out_of_time():
    repository, _, engine = system(auto_fill=False)
    engine.process(NOW)
    later = NOW + dt.timedelta(seconds=engine.config.order_timeout_seconds + 1)
    engine.reconcile(later)
    engine.reconcile(later + dt.timedelta(seconds=1))

    destination = view(repository, engine)

    [order] = destination.orders
    assert order.status == "canceled"
    assert order.cancel_reason == "timeout"
    assert order.ended_at is not None
    requested = [step for step in destination.timeline if step.step == "cancel_requested"]
    assert [step.reason for step in requested] == ["timeout"]
    assert destination.timeline[-1].step == "cancelled"


def test_a_buy_held_until_the_owner_resumed_says_so():
    repository, _, engine = system(auto_fill=True)
    resumed = JournalEvent(
        at=NOW + dt.timedelta(milliseconds=1),
        payload=AccountControlChanged(
            result=AccountControlResult(
                command=AccountControlCommand(
                    command_id="resume-1", account_id="paper", action="resume"
                ),
                applied_at=NOW + dt.timedelta(milliseconds=1),
                entry_permission="enabled",
                recovery_preference="manual",
            )
        ),
    )
    engine.process(NOW + dt.timedelta(seconds=2))

    destination = view(repository, engine, resumed)

    steps = [(step.step, step.reason) for step in destination.timeline]
    assert ("held", "waiting_for_resume") in steps
    assert [name for name, _ in steps].index("resumed") < [name for name, _ in steps].index("sized")


def test_without_journal_events_the_outcome_still_reads():
    _, _, engine = system(auto_fill=True)
    engine.process(NOW)

    destination = destination_views(engine.ledger.snapshot(), {SOURCE})[SOURCE]

    assert destination.timeline == ()
    assert destination.orders
