"""Every operation has a fixed tier; access and lock decide what may run."""

import datetime as dt
from typing import get_args

import pytest
from hypothesis import given
from hypothesis import strategies as st

from copytrading_engine.control import wire
from copytrading_engine.control.policy import (
    Propose,
    RateWindow,
    Refuse,
    Run,
    decide,
    describe_refusal,
    tier,
)

OPERATIONS = get_args(wire.Operation.__value__)
APPROVAL = {"propose_resume_account", "propose_recovery_preference", "propose_manual_order"}
SAFER = {"pause_processing", "pause_account"}


def test_every_request_model_is_an_operation_with_a_tier():
    union = get_args(get_args(wire.Request.__value__)[0])
    discriminators = {model.model_fields["operation"].default for model in union}
    assert discriminators == set(OPERATIONS)
    assert {operation for operation in OPERATIONS if tier(operation) == "approval"} == APPROVAL
    assert {operation for operation in OPERATIONS if tier(operation) == "safer"} == SAFER


@pytest.mark.parametrize(
    ("operation", "access", "unlocked", "expected"),
    [
        ("get_status", "read_pause", True, Run()),
        ("get_status", "read_pause", False, Refuse("locked")),
        ("pause_account", "read_pause", False, Run()),
        ("pause_processing", "propose", False, Run()),
        ("propose_resume_account", "read_pause", True, Refuse("forbidden")),
        ("propose_resume_account", "propose", False, Refuse("locked")),
        ("propose_manual_order", "propose", True, Propose()),
    ],
)
def test_decisions(operation, access, unlocked, expected):
    assert decide(operation, access, unlocked=unlocked) == expected


@given(
    st.sampled_from(OPERATIONS),
    st.sampled_from(("read_pause", "propose")),
    st.booleans(),
)
def test_nothing_that_needs_the_owner_ever_runs_directly(operation, access, unlocked):
    decision = decide(operation, access, unlocked=unlocked)
    if operation in APPROVAL:
        assert not isinstance(decision, Run)
        assert isinstance(decision, Propose) == (unlocked and access == "propose")
    elif operation in SAFER:
        assert decision == Run()
    else:
        assert decision == (Run() if unlocked else Refuse("locked"))


def test_rate_window_admits_a_burst_then_recovers():
    window = RateWindow(limit=2, window=dt.timedelta(seconds=10))
    start = dt.datetime(2026, 9, 26, tzinfo=dt.UTC)
    assert window.admit(start)
    assert window.admit(start + dt.timedelta(seconds=1))
    assert not window.admit(start + dt.timedelta(seconds=2))
    assert window.admit(start + dt.timedelta(seconds=10))


def test_every_refusal_has_a_message():
    assert all(describe_refusal(code) for code in get_args(wire.ErrorCode.__value__))
