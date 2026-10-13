"""The decision model in front of any reader (ADR-0012): the labelled posts in `triage_cases`
through a sorted decoder, with a fake decision model and a scripted reader. No network: the
decision model is a `DecisionModel` subclass, the reader a `FunctionModel`."""

import json
import unicodedata

import pytest
from pydantic import SecretStr
from pydantic_ai import Agent
from pydantic_ai.exceptions import ModelHTTPError
from pydantic_ai.messages import ModelMessage, ModelResponse, TextPart
from pydantic_ai.models.decision import (
    ChoiceAnswer,
    ChoiceQuestion,
    DecisionModel,
    DecisionModelSettings,
    DecisionRequest,
    DecisionResponse,
    NoulAnswer,
)
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.models.test import TestModel

from copytrading_engine.parsing.application import transform
from copytrading_engine.parsing.extraction import DecodeError
from copytrading_engine.parsing.providers.pydantic_ai import PydanticAIDecoder, reading_agent
from copytrading_engine.parsing.providers.registry import ProviderRegistry
from copytrading_engine.parsing.providers.triage import SortedDecoder, probe, sorting_agent
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.model_providers import ProviderConfig, TriageConfig

from .builders import raw
from .triage_cases import CASES


def _post(state: object) -> str | None:
    """The post in a decision request's state: the user prompt is {"message": post}."""
    if isinstance(state, str):
        try:
            value = json.loads(state)
        except ValueError:
            return None
        message = value.get("message") if isinstance(value, dict) else None
        return message if isinstance(message, str) else None
    if isinstance(state, dict):
        state = list(state.values())
    if isinstance(state, list):
        for item in state:
            if (found := _post(item)) is not None:
                return found
    return None


def _nfkc(post: str) -> str:
    """The post as the reader is sent it."""
    return unicodedata.normalize("NFKC", post)


class FakeDecider(DecisionModel):
    """A decision model that finds each post as likely chat as the eval set says."""

    def __init__(
        self, chat: dict[str, float], *, threshold: float = 0.9, fail: int | str | None = None
    ):
        super().__init__(settings=DecisionModelSettings(decision_route_threshold=threshold))
        self.chat, self.fail = {_nfkc(post): p for post, p in chat.items()}, fail
        self.requests = 0

    @property
    def model_name(self) -> str:
        return "fake-decider"

    @property
    def system(self) -> str:
        return "fake"

    @property
    def base_url(self) -> str:
        return "https://decider.invalid"

    async def decide(
        self, request: DecisionRequest, model_settings: DecisionModelSettings
    ) -> DecisionResponse:
        self.requests += 1
        if self.fail == "timeout":
            raise TimeoutError
        if isinstance(self.fail, int):
            raise ModelHTTPError(self.fail, "fake-decider")
        chat = self.chat.get(_post(request.state) or "", 0.5)
        answers = {}
        for key, question in request.questions.items():
            if isinstance(question, ChoiceQuestion):
                labels = list(question.criteria)
                chatter = next(label for label in labels if "chat" in label.lower())
                other = [label for label in labels if label != chatter]
                probabilities = {chatter: chat} | {
                    label: (1 - chat) / len(other) for label in other
                }
                choice = max(probabilities, key=probabilities.__getitem__)
                answers[key] = ChoiceAnswer(
                    choice=choice, confidence=probabilities[choice], probabilities=probabilities
                )
            else:
                answers[key] = NoulAnswer(noul=0.9)
        return DecisionResponse(answers=answers, model_name=self.model_name)


class ScriptedReader:
    """The reader: each post gets the reading in the eval set, or chat."""

    def __init__(self, readings: dict[str, list[dict | None]]):
        self.readings = {_nfkc(post): answers for post, answers in readings.items()}
        self.calls = 0

    def __call__(self, messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        self.calls += 1
        sent = [part.content for m in messages for part in m.parts if hasattr(part, "content")]
        post = _post(sent)
        answers = self.readings[post or ""]
        reading = answers[min(self.calls, len(answers)) - 1]
        # The reader answers in its own output mode, JSON in the text, whatever sorts in front.
        result = (
            {"kind": "JustChat", "data": {}}
            if reading is None
            else {"kind": "ReadingOutput", "data": {"reading": reading}}
        )
        return ModelResponse(parts=[TextPart(json.dumps({"result": result}))])


class _NoClient:
    def __init__(self) -> None:
        self.closed = False

    async def close(self) -> None:
        self.closed = True


def _reader(model: FunctionModel, client: _NoClient | None = None) -> PydanticAIDecoder:
    return PydanticAIDecoder(reading_agent(model, {}), Agent(TestModel()), client or _NoClient(), 5)


def _decoder(decider: DecisionModel, reader: ScriptedReader) -> SortedDecoder:
    return SortedDecoder(
        _reader(FunctionModel(reader, model_name="deepseek-flash")),
        sorting_agent(decider),
        _NoClient().close,
        5,
        decider.model_name,
    )


async def _run(case):
    decider = FakeDecider({case.post: case.chat})
    reader = ScriptedReader({case.post: [case.reading]})
    result = await transform(raw(case.post), Route(), _decoder(decider, reader), "deepseek-flash")
    return result, reader


@pytest.mark.parametrize("case", CASES, ids=lambda case: case.post)
async def test_each_labelled_post_gets_its_label(case):
    result, _ = await _run(case)

    assert result.decision == case.label
    if case.reason is not None:
        assert result.reason == case.reason


async def test_no_real_trade_is_ever_let_go_and_chat_never_waits():
    outcomes = [(case, (await _run(case))[0]) for case in CASES]

    assert [c.post for c, r in outcomes if c.label != "ignore" and r.decision == "ignore"] == []
    chat = [r for c, r in outcomes if c.reason == "chatter"]
    assert chat
    assert all(r.decision == "ignore" and r.suggested == () for r in chat)


async def test_sure_chat_is_settled_by_the_decision_model_alone():
    [case] = [c for c in CASES if c.post == "早上好"]

    result, reader = await _run(case)

    assert reader.calls == 0
    assert (result.model, result.sorted_by) == ("fake-decider", "fake-decider")
    assert result.sorted_confidence == pytest.approx(0.97)


async def test_unsure_chat_and_every_reading_go_to_the_reader():
    for post in ("lol nice 😂", "buy 1/6 nflx at 73"):
        [case] = [c for c in CASES if c.post == post]

        result, reader = await _run(case)

        assert reader.calls == 1
        # The reader read it, and the post still says what the filter thought of it.
        assert (result.model, result.sorted_by) == ("deepseek-flash", "fake-decider")
        assert result.sorted_confidence == pytest.approx(case.chat)


@pytest.mark.parametrize("outage", [503, "timeout"])
async def test_a_decision_service_outage_hands_the_post_to_the_reader(outage):
    [case] = [c for c in CASES if c.post == "sell half wmt"]
    reader = ScriptedReader({case.post: [case.reading]})

    result = await transform(
        raw(case.post), Route(), _decoder(FakeDecider({}, fail=outage), reader), "deepseek-flash"
    )

    assert result.decision == "trade"
    assert (reader.calls, result.model, result.sorted_confidence) == (1, "deepseek-flash", None)
    assert result.sorted_by == "fake-decider"


async def test_the_decision_model_sorts_each_post_once_however_often_the_reader_retries():
    post = "buy 1/6 nflx at 73"
    [case] = [c for c in CASES if c.post == post]
    wrong = json.loads(json.dumps(case.reading).replace('"73"', '"74"'))
    decider = FakeDecider({post: 0.1})
    reader = ScriptedReader({post: [wrong, case.reading]})

    result = await transform(raw(post), Route(), _decoder(decider, reader), "deepseek-flash")

    assert result.decision == "trade"
    assert (decider.requests, reader.calls) == (1, 2)


async def test_a_reader_failure_behind_the_decision_model_keeps_its_reason():
    def rejected(messages, info):
        raise ModelHTTPError(401, "deepseek-flash")

    decoder = SortedDecoder(
        _reader(FunctionModel(rejected)),
        sorting_agent(FakeDecider({})),
        _NoClient().close,
        5,
        "fake-decider",
    )

    with pytest.raises(DecodeError) as raised:
        await decoder.answer("buy 1/6 nflx at 73", Route())

    assert raised.value.reason == "provider_key_rejected"


async def test_the_connection_probe_names_a_rejected_key():
    assert await probe(FakeDecider({})) is None
    assert await probe(FakeDecider({}, fail=401)) == "triage_key_rejected"
    assert await probe(FakeDecider({}, fail=404)) == "triage_model_not_found"
    assert await probe(FakeDecider({}, fail=503)) == "triage_unreachable"


async def test_the_reader_alone_says_chat_through_its_own_output():
    def chat(messages, info):
        return ModelResponse(
            parts=[TextPart(json.dumps({"result": {"kind": "JustChat", "data": {}}}))]
        )

    decoder = _reader(FunctionModel(chat, model_name="deepseek-flash"))

    result = await transform(raw("hi"), Route(), decoder, "deepseek-flash")

    assert (result.decision, result.reason, result.model) == ("ignore", "chatter", "deepseek-flash")
    assert result.sorted_confidence is None


@pytest.mark.parametrize("provider", ["anthropic", "deepseek", "ollama"])
async def test_any_reader_gets_the_decision_model_in_front_and_closes_both(provider):
    client = _NoClient()

    async def create(config):
        return _reader(FunctionModel(ScriptedReader({}), model_name="reader"), client)

    triage = TriageConfig(
        provider="openai-decisions",
        model="gpt-6-luna",
        api_key=SecretStr("test"),
        route_threshold=0.9,
        timeout=5,
    )
    config = ProviderConfig(api_key=SecretStr("test"), model="m", timeout=5, triage=triage)

    decoder = await ProviderRegistry({provider: create}).create(provider, config)
    plain = await ProviderRegistry({provider: create}).create(
        provider, config.model_copy(update={"triage": None})
    )
    await decoder.close()

    assert isinstance(decoder, SortedDecoder)
    assert not isinstance(plain, SortedDecoder)
    assert client.closed
