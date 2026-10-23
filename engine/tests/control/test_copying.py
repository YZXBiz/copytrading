"""Every state the engine reports reads as exactly one of the five words the owner sees."""

import itertools

import pytest

from copytrading_engine.control import copying, wire
from copytrading_engine.control.copying import Copying

PROCESSING = ("running", "degraded", "starting", "pausing", "paused", "failed", "stopped")
RUN_STATES = (None, "ready", "running", "failed", "paused")
ENTRIES = ("enabled", "paused", "disabled", "unknown")
READINESS = (
    "enabled",
    "enabled_waiting_for_session",
    "paused",
    "disabled",
    "manual_resume_required",
    "recovery_pending",
    "reconciliation_unavailable",
    "session_unavailable",
    "processing_stopped",
    "inactive_evidence",
    "unavailable",
    *sorted(copying.UNHELD),
)


@pytest.mark.parametrize(
    ("state", "error", "expected"),
    [
        ("running", None, Copying("copying")),
        ("degraded", "source_unavailable", Copying("copying", "source_unavailable")),
        ("degraded", None, Copying("not_started", "starting")),
        ("starting", None, Copying("not_started", "starting")),
        ("pausing", None, Copying("copying", "pausing")),
        ("failed", "broker_keys_rejected", Copying("stopped", "broker_keys_rejected")),
        ("failed", None, Copying("stopped", "processing_unavailable")),
        ("paused", None, Copying("paused")),
    ],
)
def test_copying_as_a_whole(state, error, expected):
    assert copying.overall(state, error) == expected


def test_every_combination_is_one_of_five_words():
    for processing, run, entry, readiness, active in itertools.product(
        (None, *PROCESSING), RUN_STATES, ENTRIES, READINESS, (True, False)
    ):
        words = copying.account(
            processing_state=processing,
            active_configuration=active,
            entry_permission=entry,
            readiness=readiness,
            run_state=run,
        )
        assert words.word in wire.COPYING_WORDS
        # A problem always says which; only Stopped and Sells only need a reason.
        if words.word in {"stopped", "sells_only"}:
            assert words.detail


@pytest.mark.parametrize(
    ("facts", "expected"),
    [
        ({"entry_permission": "enabled", "readiness": "enabled"}, Copying("copying")),
        (
            {"entry_permission": "paused", "readiness": "paused"},
            Copying("sells_only", "account_paused"),
        ),
        (
            {"entry_permission": "enabled", "readiness": "manual_resume_required"},
            Copying("sells_only", "manual_resume_required"),
        ),
        (
            {"entry_permission": "enabled", "readiness": "broker_keys_rejected"},
            Copying("stopped", "broker_keys_rejected"),
        ),
        ({"entry_permission": "disabled", "readiness": "disabled"}, Copying("not_started")),
        (
            {"entry_permission": "enabled", "readiness": "processing_stopped"},
            Copying("paused"),
        ),
    ],
)
def test_one_account_while_copying_runs(facts, expected):
    assert (
        copying.account(processing_state="running", active_configuration=True, **facts) == expected
    )


def test_an_account_outside_the_setup_was_never_started_with_it():
    assert copying.account(
        processing_state="running",
        active_configuration=False,
        entry_permission="enabled",
        readiness="inactive_evidence",
    ) == Copying("not_started")


def test_copying_that_failed_stops_every_account_with_its_reason():
    assert copying.account(
        processing_state="failed",
        active_configuration=True,
        entry_permission="enabled",
        readiness="enabled",
    ) == Copying("stopped", "processing_unavailable")
