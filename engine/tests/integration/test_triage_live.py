"""Opt-in: the labelled eval set through the real triage decision model (ADR-0012).

Runs only when COPYTRADING_TEST_OPENAI_KEY is set (COPYTRADING_TEST_TRIAGE_MODEL picks the model,
default gpt-6-luna; COPYTRADING_TEST_TRIAGE_THRESHOLD the route threshold, default 0.9). Each post
goes through `triaged_reading_agent`, the agent copying uses, with the reader's instructions, a
guru playbook, and recent calls, since they frame the route question. The reader behind the
decision model is a stub that never answers, so only the decision model is paid for and DeepSeek
is never called. It asserts that no post labelled trade, market talk, or unclear is taken as chat
at or above the threshold, and prints each post's chat probability, the input tokens it cost, and
how close the worst one came. The key is never printed: it only travels inside a SecretStr.
"""

import datetime as dt
import json
import os
from decimal import Decimal

import pytest
from pydantic import SecretStr
from pydantic_ai.exceptions import FallbackExceptionGroup, ModelAPIError
from pydantic_ai.models.decision import UnsureRoute
from pydantic_ai.models.function import FunctionModel

from copytrading_engine.parsing.extraction import ReadingInput, normalize
from copytrading_engine.parsing.history import RecentCall
from copytrading_engine.parsing.providers.pydantic_ai import triaged_reading_agent
from copytrading_engine.parsing.providers.triage import decision_model
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.model_providers import TriageConfig

from ..parsing.triage_cases import CASES

_KEY = os.environ.get("COPYTRADING_TEST_OPENAI_KEY", "")
_MODEL = os.environ.get("COPYTRADING_TEST_TRIAGE_MODEL", "gpt-6-luna")
_THRESHOLD = float(os.environ.get("COPYTRADING_TEST_TRIAGE_THRESHOLD", "0.9"))

pytestmark = pytest.mark.skipif(
    not _KEY, reason="needs COPYTRADING_TEST_OPENAI_KEY for the live triage eval"
)

# What a guru's route carries into every read: a playbook and the guru's open calls.
_ROUTE = Route(playbook="英伟达 means NVDA\n减仓 means 1/2\n第二批 means 1/3")
_RECENT = (
    RecentCall(
        ref="c1",
        source_key="discord:demo:1",
        index=0,
        at=dt.datetime.now(dt.UTC) - dt.timedelta(days=1),
        action="buy",
        symbol="NFLX",
        price=Decimal(73),
        fraction=Decimal(1) / 6,
        entry_price=None,
        open=True,
    ),
)


class _StubReader(ModelAPIError):
    """The reader behind the decision model, which this check never pays for."""


def _never(messages, info):
    raise _StubReader("stub-reader", "the live triage eval never calls the reader")


def _chat_probability(probabilities: dict[str, float]) -> float:
    return next(p for label, p in probabilities.items() if "chat" in label.lower())


async def _sort(post: str) -> tuple[float, int]:
    """How likely the decision model finds the post chat, and the input tokens it was sent. Every
    pick is held below a threshold of 1, so the decision model reports its probabilities and hands
    the step to the stub."""
    model, close = decision_model(
        TriageConfig(
            provider="openai-decisions",
            model=_MODEL,
            api_key=SecretStr(_KEY),
            route_threshold=1.0,
            timeout=20,
        )
    )
    tokens = []
    decide = model.decide

    async def counted(request, settings):
        response = await decide(request, settings)
        tokens.append(response.usage.input_tokens)
        return response

    model.decide = counted  # ty: ignore[invalid-assignment]
    agent = triaged_reading_agent(model, FunctionModel(_never, model_name="stub-reader"))
    text = normalize(post).strip()
    unsure: list[UnsureRoute] = []
    try:
        result = await agent.run(
            json.dumps({"message": text}, ensure_ascii=False),
            deps=ReadingInput(text=text, route=_ROUTE, recent=_RECENT),
        )
    except FallbackExceptionGroup as group:
        unsure = [e for e in group.exceptions if isinstance(e, UnsureRoute)]
        result = None
    finally:
        await close()
    if result is None:
        if not unsure:
            pytest.fail(f"the decision model failed on {post!r}")
        return _chat_probability(unsure[0].probabilities), sum(tokens)
    # A pick of probability 1 is taken even at a threshold of 1.
    picked = (result.response.provider_details or {})["route"]
    return _chat_probability(picked["probabilities"]), sum(tokens)


async def test_nothing_but_chat_is_taken_as_chat_above_the_threshold():
    sorted_ = {case.post: await _sort(case.post) for case in CASES}

    wrong = {case.post: sorted_[case.post][0] for case in CASES if case.reason != "chatter"}
    worst = max(wrong, key=wrong.__getitem__)
    print(f"\ntriage model {_MODEL}, threshold {_THRESHOLD}")
    for case in CASES:
        chat, tokens = sorted_[case.post]
        mark = "chat" if case.reason == "chatter" else case.label
        print(f"  {chat:.2f}  {tokens:>5} tokens  {mark:<7} {case.post}")
    average = sum(tokens for _, tokens in sorted_.values()) / len(sorted_)
    print(f"input tokens per post: {average:.0f} on average")
    print(f"margin: worst non-chat post {worst!r} at {wrong[worst]:.2f}")
    assert wrong[worst] < _THRESHOLD, (
        f"{worst!r} would be let go as chat at {wrong[worst]:.2f} (threshold {_THRESHOLD})"
    )
