"""The control service: reads and pauses run, proposals wait for the owner, all is audited."""

import datetime as dt
import json

import pytest
from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

from copytrading_engine.control import wire
from copytrading_engine.control.policy import RateWindow
from copytrading_engine.control.proposals import ProposalRefused

from .fakes import BROKER_IDENTITIES, context, service


def line(operation: str, **values: object) -> str:
    return json.dumps(
        {"schema_version": 1, "request_id": f"r-{operation}", "operation": operation, **values}
    )


async def ok(control, request: str, **options: object) -> wire.Result:
    response = await control.handle(request, context(**options), engine_state="running")
    assert response.error is None, response.error
    assert response.ok is not None
    return response.ok


async def error(control, request: str, **options: object) -> wire.ErrorCode:
    response = await control.handle(request, context(**options), engine_state="running")
    assert response.error is not None
    return response.error.code


async def test_status_reports_engine_processing_and_accounts():
    control, *_ = service()
    status = await ok(control, line("get_status"))
    assert isinstance(status, wire.StatusView)
    assert status.engine_state == "running"
    assert [account.account_id for account in status.accounts] == ["paper"]


async def test_reads_never_carry_broker_identities():
    control, *_ = service()
    for request in (line("list_accounts"), line("list_activity")):
        result = await ok(control, request)
        encoded = result.model_dump_json()
        assert "broker_identity" not in encoded
        assert not any(identity in encoded for identity in BROKER_IDENTITIES)


async def test_positions_name_the_posts_that_bought_them():
    control, *_ = service()
    page = await ok(control, line("list_accounts"))
    assert isinstance(page, wire.AccountsPage)
    lot = page.items[0].positions[0].lots[0]
    assert (lot.source_id, lot.guru_id, lot.remaining_qty) == ("discord:demo:1", "alex", 2)
    assert lot.untrusted_source_text == "ABC long here, small size"
    assert "excerpt" not in page.model_dump_json()


async def test_source_text_is_labelled_untrusted():
    control, *_ = service()
    page = await ok(control, line("list_activity"))
    assert isinstance(page, wire.ActivityPage)
    assert page.items[0].untrusted_source_text == "Bought ABC"
    assert [(step.action, step.symbol) for step in page.items[0].understood_as] == [("buy", "ABC")]


async def test_reads_need_an_unlocked_app_but_pausing_does_not():
    control, engine, *_ = service()
    assert await error(control, line("get_status"), unlocked=False) == "locked"
    paused = await ok(control, line("pause_processing"), access="read_pause", unlocked=False)
    assert isinstance(paused, wire.ProcessingPaused)
    assert paused.processing.state == "paused"
    account = await ok(control, line("pause_account", account_id="paper"), unlocked=False)
    assert isinstance(account, wire.AccountControlView)
    assert account.entry_permission == "paused"
    assert engine.actions() == []


async def test_proposals_need_the_propose_level():
    control, engine, *_ = service()
    request = line("propose_resume_account", account_id="paper")
    assert await error(control, request, access="read_pause") == "forbidden"
    assert engine.actions() == []


async def test_resume_runs_only_after_approval_and_only_once():
    control, engine, audit, _ = service()
    proposal = await ok(control, line("propose_resume_account", account_id="paper"))
    assert isinstance(proposal, wire.ProposalView)
    assert proposal.state == "pending"
    assert proposal.requested_by == wire.CallerView(pid=4242, path="/usr/bin/agent")
    assert engine.actions() == []

    with pytest.raises(ProposalRefused):
        await control.approve(proposal.proposal_id, "0" * 64)
    assert engine.actions() == []

    done = await control.approve(proposal.proposal_id, proposal.digest)
    assert done.state == "succeeded"
    ((_, command),) = engine.actions()
    assert command.action == "resume"
    assert command.command_id == proposal.command_id

    with pytest.raises(ProposalRefused):
        await control.approve(proposal.proposal_id, proposal.digest)
    assert len(engine.actions()) == 1
    assert [entry.outcome for entry in audit.entries if entry.proposal_id] == [
        "proposed",
        "approved",
        "succeeded",
    ]


async def test_manual_order_proposal_shows_the_previewed_order():
    control, engine, *_ = service()
    preview = await ok(
        control,
        line(
            "preview_manual_order",
            account_id="paper",
            correction_id="correction-native-1",
            instruction_index=0,
        ),
    )
    assert isinstance(preview, wire.ManualPreview)
    proposal = await ok(
        control,
        line("propose_manual_order", account_id="paper", preview_id=preview.preview_id),
    )
    assert isinstance(proposal, wire.ProposalView)
    assert isinstance(proposal.subject, wire.ManualOrderSubject)
    assert (proposal.subject.symbol, str(proposal.subject.quantity)) == ("ABC", "12")
    assert proposal.expires_at == preview.expires_at

    done = await control.approve(proposal.proposal_id, proposal.digest)
    assert done.outcome == wire.ProposalOutcome(
        status="succeeded", code="accepted", command_id=proposal.command_id
    )
    ((_, (request,)),) = engine.actions()
    assert (request.actor, request.command_id) == ("agent", proposal.command_id)


async def test_manual_order_needs_a_preview_made_through_control():
    control, *_ = service()
    request = line("propose_manual_order", account_id="paper", preview_id="made-elsewhere")
    assert await error(control, request) == "not_found"


async def test_an_unconfirmed_broker_effect_is_reported_as_unknown():
    control, engine, *_ = service()
    proposal = await ok(
        control, line("propose_recovery_preference", account_id="paper", preference="automatic")
    )
    assert isinstance(proposal, wire.ProposalView)
    engine.failure = TimeoutError("broker did not answer")
    done = await control.approve(proposal.proposal_id, proposal.digest)
    assert done.state == "outcome_unknown"


async def test_unknown_account_cannot_be_proposed():
    control, *_ = service()
    assert await error(control, line("propose_resume_account", account_id="ghost")) == "not_found"


async def test_rejections_expiry_and_lock_close_proposals():
    control, engine, _, clock = service()
    first = await ok(control, line("propose_resume_account", account_id="paper"))
    assert isinstance(first, wire.ProposalView)
    assert (await control.reject(first.proposal_id)).state == "rejected"

    second = await ok(control, line("propose_resume_account", account_id="paper"))
    assert isinstance(second, wire.ProposalView)
    clock.advance(minutes=6)
    assert (await ok(control, line("get_proposal", proposal_id=second.proposal_id))).state == (
        "expired"
    )

    third = await ok(control, line("propose_resume_account", account_id="paper"))
    assert isinstance(third, wire.ProposalView)
    assert await control.discard_pending() == 1
    page = await ok(control, line("list_proposals"))
    assert isinstance(page, wire.ProposalsPage)
    assert [item.state for item in page.items] == ["rejected", "expired", "discarded"]
    assert engine.actions() == []


async def test_a_flood_is_refused_but_pausing_still_works():
    control, *_ = service(rate=RateWindow(limit=2, window=dt.timedelta(seconds=10)))
    await ok(control, line("get_status"))
    await ok(control, line("get_status"))
    assert await error(control, line("get_status")) == "busy"
    assert isinstance(await ok(control, line("pause_processing")), wire.ProcessingPaused)


async def test_invalid_requests_echo_their_request_id_and_are_audited():
    control, _, audit, _ = service()
    response = await control.handle(
        json.dumps({"schema_version": 1, "request_id": "abc", "operation": "delete_everything"}),
        context(),
        engine_state="running",
    )
    assert response.request_id == "abc"
    assert response.error is not None
    assert response.error.code == "invalid_request"
    assert audit.entries[-1].operation == "invalid"


async def test_audit_keeps_identifiers_but_never_source_text():
    control, _, audit, _ = service()
    await ok(control, line("list_activity"))
    await ok(control, line("pause_account", account_id="paper"))
    assert [(entry.operation, entry.tier, entry.outcome) for entry in audit.entries] == [
        ("list_activity", "read", "ok"),
        ("pause_account", "safer", "ok"),
    ]
    assert "Bought ABC" not in repr(audit.entries)


REQUESTS = st.sampled_from(
    [
        line("get_status"),
        line("pause_account", account_id="paper"),
        line("propose_resume_account", account_id="paper"),
        line("propose_recovery_preference", account_id="paper", preference="automatic"),
    ]
)


@settings(max_examples=60, suppress_health_check=[HealthCheck.function_scoped_fixture])
@given(
    steps=st.lists(
        st.tuples(REQUESTS, st.sampled_from(("read_pause", "propose")), st.booleans()),
        max_size=12,
    ),
    approvals=st.lists(st.tuples(st.integers(min_value=0), st.booleans()), max_size=12),
)
async def test_actions_happen_only_through_approval_and_at_most_once(steps, approvals):
    control, engine, *_ = service()
    for request, access, unlocked in steps:
        await control.handle(request, context(access, unlocked=unlocked), engine_state="running")
    assert engine.actions() == []

    proposals = control.proposals()
    approved: set[str] = set()
    for index, honest in approvals:
        if not proposals:
            break
        proposal = proposals[index % len(proposals)]
        try:
            await control.approve(proposal.proposal_id, proposal.digest if honest else "e" * 64)
        except ProposalRefused:
            continue
        assert honest
        assert proposal.proposal_id not in approved
        approved.add(proposal.proposal_id)
    assert len(engine.actions()) == len(approved)
