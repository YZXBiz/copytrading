"""An account that asks for approval sends no order by itself (ADR-0008)."""

import pytest

from copytrading_engine.execution.domain.progress import Skipped
from copytrading_engine.execution.domain.signals import CopyConfig

from .builders import NOW, deliver, event


def ask_for_approval(engine) -> None:
    engine.config = CopyConfig.model_validate(engine.config.model_dump() | {"approve_orders": True})


def test_a_buy_waits_for_the_owner_instead_of_going_to_the_broker(system):
    engine, broker, _ = system
    ask_for_approval(engine)
    deliver(engine, event())
    message = engine.ledger.message("discord:demo:1")
    assert broker.calls == 0
    assert engine.ledger.orders() == ()
    assert message.parts == (Skipped(reason="approval_required"),)
    assert message.waits_for_owner, "only a post that waits can be approved by hand"


def test_an_exit_waits_for_the_owner_and_the_shares_stay(system):
    engine, broker, _ = system
    deliver(engine, event())
    held = engine.ledger.owned("ABC")
    calls = broker.calls
    ask_for_approval(engine)
    deliver(engine, event("2", "close", "24", "25"))
    message = engine.ledger.message("discord:demo:2")
    assert broker.calls == calls
    assert message.parts == (Skipped(reason="approval_required"),)
    assert engine.ledger.owned("ABC") == held


def test_an_account_that_never_asked_still_sends_by_itself(system):
    engine, broker, _ = system
    deliver(engine, event())
    assert broker.calls == 1
    assert engine.ledger.message("discord:demo:1").parts != (Skipped(reason="approval_required"),)


def test_a_call_that_would_have_been_skipped_anyway_is_not_held(system):
    engine, broker, _ = system
    ask_for_approval(engine)
    deliver(engine, event("1", "close", "24", "25"))
    message = engine.ledger.message("discord:demo:1")
    assert broker.calls == 0
    assert message.parts != (Skipped(reason="approval_required"),)
    assert not message.waits_for_owner, "a call nothing could place is not worth asking about"


def test_the_owner_approving_a_held_call_by_hand_gets_a_ready_order(system):
    engine, _, _ = system
    ask_for_approval(engine)
    deliver(engine, event())

    decision = engine.decide(
        engine.ledger.message("discord:demo:1").instructions[0],
        "discord:demo:1",
        "discord:demo",
        NOW,
        halted=False,
        manual=True,
    )

    assert decision.reason == "ready"
    assert decision.plan is not None
    assert decision.plan.side == "buy"


@pytest.mark.parametrize("value", ["yes", 1, "false"])
def test_the_switch_is_a_real_boolean(value):
    with pytest.raises(ValueError, match="approve_orders"):
        CopyConfig(sources=["discord:demo"], approve_orders=value)
