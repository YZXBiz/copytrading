"""Opt-in: one assistant question answered by the real DeepSeek model.

Runs only when COPYTRADING_TEST_DEEPSEEK_KEY is set (COPYTRADING_TEST_DEEPSEEK_MODEL picks the
model, default deepseek-flash). The tools read a fake engine, so nothing reaches a broker. The key
is never printed: it only travels inside a SecretStr.
"""

import asyncio
import os

import pytest
from pydantic import SecretStr

from copytrading_engine.assistant.service import AskContext, AskGuru, AssistantService
from copytrading_engine.trading.domain.config import ProviderConfiguration

from ..control.fakes import service as control_service

_DEEPSEEK_KEY = os.environ.get("COPYTRADING_TEST_DEEPSEEK_KEY", "")
_DEEPSEEK_MODEL = os.environ.get("COPYTRADING_TEST_DEEPSEEK_MODEL", "deepseek-flash")

pytestmark = pytest.mark.skipif(
    not _DEEPSEEK_KEY, reason="needs COPYTRADING_TEST_DEEPSEEK_KEY for the live assistant check"
)


async def test_the_real_model_answers_a_question_with_text_and_no_error():
    control, engine, _audit, _clock = control_service()
    svc = AssistantService(
        control, engine, engine_state=lambda: "running", register_secrets=lambda _: None
    )
    context = AskContext(
        screen="accounts", gurus=(AskGuru(id="guru-1a2b3c4d", name="Zhao"),), language="en"
    )
    try:
        turn_id = await svc.ask(
            "c-0123456789ab",
            "Is copying running, and what accounts do I have?",
            context,
            ProviderConfiguration(name="deepseek", model=_DEEPSEEK_MODEL),
            SecretStr(_DEEPSEEK_KEY),
        )
        for _ in range(700):
            events, done = svc.turn(turn_id, 0)
            if done:
                break
            await asyncio.sleep(0.1)
        else:
            raise AssertionError("the live answer never finished")
    finally:
        await svc.reset()

    errors = [(e.code, e.text) for e in events if e.kind == "error"]
    assert errors == []
    assert "".join(e.text or "" for e in events if e.kind == "text").strip()
    assert events[-1].kind == "done"
