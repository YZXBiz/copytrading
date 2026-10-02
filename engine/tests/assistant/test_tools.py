"""Each tool is one control request audited under the assistant's caller, with a step line."""

import datetime as dt

from copytrading_engine.assistant.conversation import AssistantLink, Turn
from copytrading_engine.assistant.tools import ASSISTANT_CALLER, AssistantTools
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand

from ..control.fakes import FakeEngine, MemoryAudit, service

ZHAO = "guru-1a2b3c4d"


def tools(turn: Turn) -> tuple[AssistantTools, FakeEngine, MemoryAudit]:
    control, engine, audit, _clock = service()
    return (
        AssistantTools(
            control,
            engine,
            turn,
            engine_state=lambda: "running",
            now=lambda: dt.datetime(2026, 9, 30, 15, tzinfo=dt.UTC),
            guru_names={ZHAO: "Zhao"},
        ),
        engine,
        audit,
    )


async def test_reads_answer_with_the_contract_and_say_what_they_looked_at():
    turn = Turn("t-1")
    assistant, _, audit = tools(turn)
    accounts = await assistant.list_accounts()
    assert accounts["items"][0]["account_id"] == "paper"
    assert [e.text for e in turn.events(0)] == ["Looked at your accounts"]
    [entry] = await audit.recent(1)
    assert (entry.actor, entry.caller_path) == ("agent", ASSISTANT_CALLER)
    assert ASSISTANT_CALLER == "CopyTrading Assistant"


async def test_pausing_runs_now():
    turn = Turn("t-1")
    assistant, engine, _ = tools(turn)
    result = await assistant.pause_account("paper")
    assert result["type"] == "account_control"
    # The fake engine's actions() leaves pausing out, so read the raw call record.
    paused = [
        value.action
        for name, value in engine.calls
        if name == "control_account" and isinstance(value, AccountControlCommand)
    ]
    assert paused == ["pause"]


async def test_resuming_only_asks_the_owner():
    turn = Turn("t-1")
    assistant, engine, _ = tools(turn)
    result = await assistant.propose_resume_account("paper")
    assert result["state"] == "pending"
    assert engine.actions() == []
    assert [e.kind for e in turn.events(0)] == ["step", "proposal"]


async def test_a_refused_proposal_returns_its_code_and_says_it_could_not_ask():
    turn = Turn("t-1")
    assistant, _, _ = tools(turn)
    await assistant.propose_resume_account("paper")
    again = await assistant.propose_resume_account("paper")
    assert again == {"refused": "proposal_limit"}
    assert [(e.kind, e.text) for e in turn.events(0)] == [
        ("step", "Asked you to approve resuming paper"),
        ("proposal", None),
        ("step", "Couldn't ask you to approve resuming paper"),
    ]


async def test_a_refused_pause_never_reads_as_paused():
    turn = Turn("t-1")
    assistant, engine, _ = tools(turn)
    engine.failure = TimeoutError("broker did not answer")
    result = await assistant.pause_account("paper")
    assert "refused" in result
    assert [(e.kind, e.text) for e in turn.events(0)] == [
        ("step", "Couldn't pause new entries for paper")
    ]


async def test_a_post_that_is_not_found_says_so():
    turn = Turn("t-1")
    assistant, _, _ = tools(turn)
    assert await assistant.explain_skip("discord:calls:404") == {"refused": "not_found"}
    assert [e.text for e in turn.events(0)] == ["Couldn't find that post"]


async def test_a_guru_is_named_by_display_name_whether_asked_by_id_or_name():
    for asked in (ZHAO, "zhao"):
        turn = Turn("t-1")
        assistant, _, _ = tools(turn)
        record = await assistant.guru_record(asked)
        assert (record["guru_id"], record["guru_name"]) == (ZHAO, "Zhao")
        events = turn.events(0)
        assert [e.text for e in events if e.kind == "step"] == ["Added up Zhao's calls"]
        assert [e.link for e in events if e.link] == [
            AssistantLink(kind="guru", id=ZHAO, title="Zhao")
        ]


async def test_a_guru_the_app_did_not_name_keeps_their_id():
    turn = Turn("t-1")
    assistant, _, _ = tools(turn)
    await assistant.guru_record("guru-99999999")
    steps = [e.text for e in turn.events(0) if e.kind == "step"]
    assert steps == ["Added up guru-99999999's calls"]


async def test_a_cancelled_turn_cannot_reach_the_engine():
    turn = Turn("t-1")
    assistant, engine, _ = tools(turn)
    turn.cancel()
    assert await assistant.pause_processing() == {"refused": "cancelled"}
    assert await assistant.propose_resume_account("paper") == {"refused": "cancelled"}
    assert await assistant.list_accounts() == {"refused": "cancelled"}
    assert await assistant.guru_record("g-1") == {"refused": "cancelled"}
    assert await assistant.explain_skip("s-1") == {"refused": "cancelled"}
    assert engine.actions() == []
    assert engine.calls == []
    assert [e.kind for e in turn.events(0)] == ["done"]
