"""The assistant evaluated: offline for the plumbing on every run, live against a real model
when its key is set (`COPYTRADING_TEST_DEEPSEEK_KEY`), like the live paper scenarios."""

import datetime as dt
import os
from collections.abc import Iterator

import pytest
from pydantic import SecretStr
from pydantic_ai.models.test import TestModel

from copytrading_engine.assistant.conversation import Turn
from copytrading_engine.assistant.tools import AssistantTools
from copytrading_engine.assistant.wording import REASONS
from copytrading_engine.trading.domain.config import ProviderConfiguration

from ...control.fakes import service
from .cases import SAFETY, dataset
from .scenario import ZHAO, EvalEngine, Question, ask

KEY_VARIABLE = "COPYTRADING_TEST_DEEPSEEK_KEY"
# The reading tools that take no name: a test model's made-up account or post ids would be sent
# back for correction, which `test_service.py` covers.
READ_TOOLS = ["get_status", "list_accounts", "list_activity", "list_proposals"]
MODEL = os.environ.get("COPYTRADING_TEST_DEEPSEEK_MODEL", "deepseek-flash")


def _strings(value: object) -> Iterator[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from _strings(item)
    elif isinstance(value, list | tuple):
        for item in value:
            yield from _strings(item)


async def test_every_tool_reads_in_the_owners_words():
    control, engine, _audit, _clock = service(engine=EvalEngine())
    tools = AssistantTools(
        control,
        engine,
        Turn("t-1"),
        engine_state=lambda: "running",
        now=lambda: dt.datetime(2026, 9, 26, 15, tzinfo=dt.UTC),
        guru_names={ZHAO.id: ZHAO.name},
    )
    results = [
        await tools.get_status(),
        await tools.list_accounts(),
        await tools.list_activity(),
        await tools.list_account_events("paper"),
        await tools.list_proposals(),
        await tools.guru_record(ZHAO.id),
        await tools.explain_skip("discord:calls:post-9"),
    ]
    values = [text for result in results for text in _strings(result)]
    codes = [text for text in values if text in REASONS]
    assert codes == [], "a tool handed the model an engine code instead of the app's words"
    activity = results[2]
    [wmt] = [post for post in activity["posts"] if post["post"] == "discord:calls:post-9"]
    assert wmt["guru"] == "Zhao"
    assert wmt["read_as"] == ["Buy WMT at $109.80, 1/6 of a full position"]
    assert wmt["accounts"][0]["outcome"] == ["Still checking the account after a restart"]
    assert results[6]["accounts"][0]["outcome"] == "Still checking the account after a restart"


async def test_the_assistant_runs_every_tool_through_the_service():
    """Plumbing: a model that calls every tool gets an answer, and every step names a tool."""

    async def open_test_model(name, config):
        async def close():
            pass

        return TestModel(call_tools=READ_TOOLS), close

    answer = await ask(
        Question("Tell me everything."),
        ProviderConfiguration(name="deepseek", model="deepseek-flash"),
        SecretStr("test-only"),
        open_model=open_test_model,
        timeout=20,
    )
    assert answer.failed is None
    assert answer.tools
    assert not [tool for tool in answer.tools if tool.startswith("? ")]


@pytest.mark.skipif(not os.environ.get(KEY_VARIABLE), reason=f"set {KEY_VARIABLE}")
async def test_the_assistant_answers_owner_questions_with_a_real_model():
    provider = ProviderConfiguration(name="deepseek", model=MODEL)
    key = SecretStr(os.environ[KEY_VARIABLE])

    async def task(question: Question):
        return await ask(question, provider, key)

    report = await dataset().evaluate(task, max_concurrency=4, progress=False)
    lines, failed_safety, passed = [], [], 0
    for case in report.cases:
        checks = case.assertions
        ok = bool(checks) and all(result.value for result in checks.values())
        passed += ok
        missed = [name for name, result in checks.items() if not result.value]
        lines.append(f"{'PASS' if ok else 'FAIL'} {case.name} {missed or ''}")
        if not ok and case.name in SAFETY:
            failed_safety.append(case.name)
    errors = [f"ERROR {failure.name}: {failure.error_message}" for failure in report.failures]
    total = len(report.cases) + len(report.failures)
    print("\n".join([*lines, *errors, f"{passed}/{total} cases passed"]))
    assert not errors
    assert failed_safety == []
    assert passed / total >= 0.85
