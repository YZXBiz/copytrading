"""The assistant's insights read the real ledger through the operator views."""

import datetime as dt

from copytrading_engine.assistant.conversation import AssistantLink, Turn
from copytrading_engine.assistant.insights import explain_skip
from copytrading_engine.assistant.tools import AssistantTools

from ..control.fakes import service as control_service
from .rig import Account, Rig
from .zhao import GURU_ID, NAME, buy


async def test_a_gurus_record_counts_calls_copied_and_why_the_rest_were_skipped(tmp_path):
    prices = {"NVDA": "125", "AMD": "100", "TSLA": "250"}
    async with Rig(tmp_path, {"paper": Account(cash="1000")}, prices) as rig:
        for text, instruction in (
            ("买入 NVDA 125", buy("NVDA", "125")),
            ("买入 AMD 100", buy("AMD", "100")),
            ("买入 TSLA 250", buy("TSLA", "250")),
        ):
            rig.reader.expect(text, instruction)
            await rig.post(text)
        rig.reader.expect("今天休息")
        await rig.post("今天休息", expect_destinations=False)

        turn = Turn("t-1")
        control, *_ = control_service()
        tools = AssistantTools(
            control,
            rig.runtime.operator,
            turn,
            engine_state=lambda: "running",
            now=lambda: dt.datetime.now(dt.UTC),
            guru_names={GURU_ID: NAME},
        )
        record = await tools.guru_record(GURU_ID)

    assert (record["posts"], record["calls"], record["copied"]) == (4, 3, 2)
    assert record["skipped"] == {"insufficient_cash": 1}
    assert record["guru_name"] == "Zhao"
    assert [e.text for e in turn.events(0) if e.kind == "step"] == ["Added up Zhao's calls"]
    assert [e.link for e in turn.events(0) if e.link] == [
        AssistantLink(kind="guru", id=GURU_ID, title="Zhao")
    ]


async def test_a_skip_is_explained_account_by_account_in_plain_words(tmp_path):
    accounts = {"rich": Account(cash="5000"), "poor": Account(cash="100")}
    async with Rig(tmp_path, accounts, {"NVDA": "125"}) as rig:
        rig.reader.expect("买入 NVDA 125", buy("NVDA", "125"))
        post = await rig.post("买入 NVDA 125")
        explanation = await explain_skip(rig.runtime.operator, post.source_id)

    assert explanation.untrusted_source_text.endswith("买入 NVDA 125")
    assert explanation.understood_as == ["buy NVDA at $125"]
    outcomes = {item.account_id: (item.outcome, item.reason) for item in explanation.accounts}
    assert outcomes["rich"][0] == "order_linked"
    assert outcomes["poor"][0] == "insufficient_cash"
    assert "cash" in outcomes["poor"][1].lower()
