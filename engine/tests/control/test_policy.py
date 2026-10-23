"""Every operation has a fixed tier; access and lock decide what may run."""

import datetime as dt
from typing import get_args

import pytest
from hypothesis import given
from hypothesis import strategies as st

from copytrading_engine.control import wire
from copytrading_engine.control.policy import (
    SETUP_CHANGES,
    Propose,
    RateWindow,
    Refuse,
    Run,
    decide,
    describe_refusal,
    tier,
)

OPERATIONS = get_args(wire.Operation.__value__)
PROPOSALS = {
    "propose_resume_account",
    "propose_recovery_preference",
    "propose_manual_order",
    "propose_set_account_limits",
    "propose_start_processing",
}
SETUP = {
    "edit_setup_discord",
    "edit_setup_model",
    "edit_setup_account",
    "edit_setup_guru",
    "edit_setup_alerts",
    "import_setup",
    "apply_setup",
    "discard_setup",
}
APPROVAL = PROPOSALS | SETUP
SAFER = {"pause_processing", "pause_account"}


def test_every_request_model_is_an_operation_with_a_tier():
    union = get_args(get_args(wire.Request.__value__)[0])
    discriminators = {model.model_fields["operation"].default for model in union}
    assert discriminators == set(OPERATIONS)
    assert {operation for operation in OPERATIONS if tier(operation) == "approval"} == APPROVAL
    assert {operation for operation in OPERATIONS if tier(operation) == "safer"} == SAFER
    assert SETUP_CHANGES == SETUP
    assert tier("get_setup") == "read"
    assert set(wire.SETUP_OPERATIONS) == SETUP | {"get_setup"}


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
        ("propose_set_account_limits", "read_pause", True, Refuse("forbidden")),
        ("propose_set_account_limits", "propose", False, Refuse("locked")),
        ("propose_set_account_limits", "propose", True, Propose()),
        ("get_setup", "read_pause", True, Run()),
        ("get_setup", "propose", False, Refuse("locked")),
        ("edit_setup_account", "read_pause", True, Refuse("forbidden")),
        ("edit_setup_account", "propose", False, Refuse("locked")),
    ],
)
def test_decisions(operation, access, unlocked, expected):
    assert decide(operation, access, unlocked=unlocked) == expected


@pytest.mark.parametrize("owner_needed", [False, True])
def test_a_setup_change_runs_unless_it_touches_real_money(owner_needed):
    decision = decide(
        "apply_setup", "propose", unlocked=True, owner_needed=owner_needed, setup_changes=True
    )
    assert decision == (Propose() if owner_needed else Run())
    # Every other approval-tier request is a proposal whatever the caller says.
    assert decide("propose_resume_account", "propose", unlocked=True, owner_needed=False) == (
        Propose()
    )


def test_setup_changes_need_their_own_permission():
    assert decide("edit_setup_model", "propose", unlocked=True) == Refuse("forbidden")
    assert decide("apply_setup", "propose", unlocked=True, owner_needed=False) == Refuse(
        "forbidden"
    )
    assert decide("get_setup", "read_pause", unlocked=True) == Run()


@given(
    st.sampled_from(OPERATIONS),
    st.sampled_from(("read_pause", "propose")),
    st.booleans(),
    st.booleans(),
    st.booleans(),
)
def test_nothing_that_needs_the_owner_ever_runs_directly(
    operation, access, unlocked, owner, setup_changes
):
    decision = decide(
        operation, access, unlocked=unlocked, owner_needed=owner, setup_changes=setup_changes
    )
    granted = unlocked and access == "propose"
    if operation in SETUP:
        granted = granted and setup_changes
    if operation in PROPOSALS or (operation in SETUP and owner):
        assert not isinstance(decision, Run)
        assert isinstance(decision, Propose) == granted
    elif operation in SETUP:
        assert isinstance(decision, Run) == granted
        assert not isinstance(decision, Propose)
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
