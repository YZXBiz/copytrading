"""Changing an account's limits is an approval the app performs: the engine only records it."""

import pytest

from copytrading_engine.control import wire
from copytrading_engine.control.proposals import APP_REPORT_WINDOW, ProposalRefused

from .fakes import service
from .test_service import error, line, ok


def change(**values: str) -> list[dict[str, str]]:
    return [{"field": field, "value": value} for field, value in values.items()]


async def propose(control, **values: str) -> wire.ProposalView:
    proposal = await ok(
        control, line("propose_set_account_limits", account_id="paper", changes=change(**values))
    )
    assert isinstance(proposal, wire.ProposalView)
    return proposal


async def test_a_limit_change_waits_for_the_owner_and_names_exactly_what_changes():
    control, engine, *_ = service()
    proposal = await propose(control, max_order_usd="300.0", overnight="TRUE")
    assert proposal.state == "pending"
    assert proposal.subject == wire.LimitsSubject(
        account_id="paper",
        changes=(
            wire.LimitChange(field="max_order_usd", value="300"),
            wire.LimitChange(field="overnight", value="true"),
        ),
    )
    assert engine.actions() == []


async def test_the_same_change_in_any_spelling_has_one_digest():
    control, *_ = service()
    first = await propose(control, max_order_usd="300", copy_exits="false")
    await control.reject(first.proposal_id)
    second = await propose(control, copy_exits="FALSE", max_order_usd="300.00")
    assert first.digest == second.digest


async def test_approving_leaves_it_running_for_the_app_and_the_engine_changes_nothing():
    control, engine, *_ = service()
    proposal = await propose(control, max_entries_per_day="200")
    running = await control.approve(proposal.proposal_id, proposal.digest)
    assert running.state == "running"
    assert engine.actions() == []
    with pytest.raises(ProposalRefused):  # approved once
        await control.approve(proposal.proposal_id, proposal.digest)


async def test_the_app_reports_how_it_went_and_saying_it_twice_changes_nothing():
    control, *_ = service()
    proposal = await propose(control, max_entries_per_day="200")
    await control.approve(proposal.proposal_id, proposal.digest)
    done = await control.complete(proposal.proposal_id, "succeeded", None)
    assert (done.state, done.outcome.status if done.outcome else None) == ("succeeded", "succeeded")
    again = await control.complete(proposal.proposal_id, "succeeded", None)
    assert again.state == "succeeded"
    with pytest.raises(ProposalRefused):
        await control.complete(proposal.proposal_id, "failed", "conflict")


async def test_a_failure_the_app_reports_is_recorded_with_its_code():
    control, *_ = service()
    proposal = await propose(control, max_entries_per_day="200")
    await control.approve(proposal.proposal_id, proposal.digest)
    done = await control.complete(proposal.proposal_id, "failed", "unsaved_changes")
    assert done.state == "failed"
    assert done.outcome is not None
    assert done.outcome.code == "unsaved_changes"


async def test_nothing_is_completed_before_the_owner_approves_or_for_other_kinds():
    control, *_ = service()
    proposal = await propose(control, max_entries_per_day="200")
    with pytest.raises(ProposalRefused):
        await control.complete(proposal.proposal_id, "succeeded", None)
    resume = await ok(control, line("propose_resume_account", account_id="paper"))
    assert isinstance(resume, wire.ProposalView)
    await control.approve(resume.proposal_id, resume.digest)
    with pytest.raises(ProposalRefused):
        await control.complete(resume.proposal_id, "succeeded", None)


async def test_an_app_that_never_reports_ends_as_outcome_unknown():
    control, _, _, clock = service()
    proposal = await propose(control, max_entries_per_day="200")
    await control.approve(proposal.proposal_id, proposal.digest)
    clock.advance(seconds=APP_REPORT_WINDOW.total_seconds())
    seen = await ok(control, line("get_proposal", proposal_id=proposal.proposal_id))
    assert isinstance(seen, wire.ProposalView)
    assert seen.state == "outcome_unknown"
    assert seen.outcome is not None
    assert seen.outcome.code == "app_did_not_report"


@pytest.mark.parametrize(
    "values",
    [
        {"max_order_usd": "0"},
        {"max_order_usd": "-5"},
        {"max_order_usd": "abc"},
        {"max_order_usd": "NaN"},
        {"max_entries_per_day": "2.5"},
        {"max_entries_per_day": "0"},
        {"max_signal_age_seconds": "601"},
        {"order_timeout_seconds": "-1"},
        {"poll_seconds": "0.5"},
        {"overnight": "yes"},
        {"max_below_signal_pct": "101"},
    ],
)
async def test_a_value_settings_would_refuse_never_reaches_the_owner(values):
    control, *_ = service()
    code = await error(
        control,
        line("propose_set_account_limits", account_id="paper", changes=change(**values)),
    )
    assert code == "invalid_request"


async def test_a_setting_named_twice_or_an_unknown_one_is_refused():
    control, *_ = service()
    twice = change(max_order_usd="100") + change(max_order_usd="200")
    assert (
        await error(control, line("propose_set_account_limits", account_id="paper", changes=twice))
        == "invalid_request"
    )
    unknown = [{"field": "api_key", "value": "x"}]
    assert (
        await error(
            control, line("propose_set_account_limits", account_id="paper", changes=unknown)
        )
        == "invalid_request"
    )


async def test_an_unknown_account_is_not_found_and_a_server_without_the_app_cannot_change_limits():
    control, *_ = service()
    request = line(
        "propose_set_account_limits", account_id="nope", changes=change(overnight="true")
    )
    assert await error(control, request) == "not_found"
    request = line(
        "propose_set_account_limits", account_id="paper", changes=change(overnight="true")
    )
    assert await error(control, request, app_actions=False) == "unavailable"
