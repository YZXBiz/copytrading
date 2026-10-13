"""The decision model in front of any reader (ADR-0012).

A decision model answers a pick-one with calibrated probabilities instead of writing text. It
sorts each post first: chat or something to read. Chat has nothing to fill, so a confident chat
pick settles the post there. Everything else goes to whichever reader the owner set up, in that
reader's own output mode: a reading, an unsure pick, and any failure of the decision service.
"""

import asyncio
import json
from collections.abc import Awaitable, Callable
from dataclasses import replace

import httpx2 as httpx
from openai import AsyncOpenAI
from pydantic import BaseModel, ConfigDict, Field
from pydantic_ai import Agent, ToolOutput
from pydantic_ai.exceptions import ModelAPIError, ModelHTTPError, UnexpectedModelBehavior
from pydantic_ai.models.decision import DecisionModel, DecisionModelSettings, UnsureRoute
from pydantic_ai.models.openai_decisions import OpenAIDecisionsModel
from pydantic_ai.models.typesafe import TypeSafeModel
from pydantic_ai.providers.openai_decisions import OpenAIDecisionsProvider
from pydantic_ai.providers.typesafe import TypeSafeProvider

from copytrading_engine.parsing.extraction import Answer, JustChat, ReadingInput, ReadingOutput
from copytrading_engine.parsing.history import RecentCall
from copytrading_engine.parsing.learning import PlaybookProposal
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.model_providers import TriageConfig
from copytrading_engine.shared.payload_capture import PayloadCapture
from copytrading_engine.shared.reading import Chatter

from .pydantic_ai import framed
from .registry import ManagedDecoder
from .transport import DiagnosticHTTPTransport

type Close = Callable[[], Awaitable[None]]


def decision_model(
    config: TriageConfig, *, diagnostics: PayloadCapture | None = None
) -> tuple[DecisionModel, Close]:
    """The configured decision model and what closes its client. Its requests are journaled like
    the reader's; the provider label is the closest the diagnostics vocabulary has."""
    transport: httpx.AsyncBaseTransport = httpx.AsyncHTTPTransport(retries=0)
    if diagnostics is not None:
        provider = "openai" if config.provider == "openai-decisions" else "other"
        transport = DiagnosticHTTPTransport(transport, diagnostics, provider=provider)
    http_client = httpx.AsyncClient(
        transport=transport, timeout=config.timeout, follow_redirects=False
    )
    settings = DecisionModelSettings(
        decision_route_threshold=config.route_threshold, timeout=config.timeout
    )
    key = config.api_key.get_secret_value()
    if config.provider == "typesafe":
        model = TypeSafeModel(
            config.model,
            provider=TypeSafeProvider(api_key=key, http_client=http_client),
            settings=settings,
        )
        return model, http_client.aclose
    client = AsyncOpenAI(
        api_key=key, max_retries=0, timeout=config.timeout, http_client=http_client
    )
    model = OpenAIDecisionsModel(
        config.model, provider=OpenAIDecisionsProvider(openai_client=client), settings=settings
    )
    return model, client.close


class _Greeting(BaseModel):
    """Whether a message greets someone."""

    greeting: bool = Field(description="Does this message greet someone?")


async def probe(model: DecisionModel) -> str | None:
    """One cheap decision about "hello", so Connect can tell a working key from a bad one; the
    reason it failed, or None when the model answered."""
    agent = Agent(model, output_type=_Greeting, name="triage_probe")
    try:
        await agent.run("hello")
    except ModelHTTPError as exc:
        if exc.status_code in {401, 403}:
            return "triage_key_rejected"
        if exc.status_code in {400, 404}:
            return "triage_model_not_found"
        return "triage_unreachable"
    except ModelAPIError, TimeoutError:
        return "triage_unreachable"
    return None


class ToRead(BaseModel):
    """The decision model's other pick: the post is for the reader."""

    model_config = ConfigDict(extra="forbid", frozen=True)


type SortingAgent = Agent[ReadingInput, JustChat | ToRead]


def sorting_agent(decision: DecisionModel) -> SortingAgent:
    """Chat or something to read, framed like the reader's own question: its instructions, the
    guru's playbook, and the guru's recent calls."""
    return framed(
        Agent[ReadingInput, JustChat | ToRead](
            decision,
            name="post_sorter",
            output_type=[
                ToolOutput(JustChat, name="JustChat"),
                ToolOutput(ToRead, name="ReadingOutput", description=ReadingOutput.__doc__),
            ],
            deps_type=ReadingInput,
        )
    )


class SortedDecoder:
    """Any reader with the decision model in front of it (ADR-0012)."""

    def __init__(
        self,
        reader: ManagedDecoder,
        sorter: SortingAgent,
        close_sorter: Close,
        timeout: float,
        name: str,
    ) -> None:
        self.reader = reader
        self.name = name
        self.sorter = sorter
        self.close_sorter = close_sorter
        self.timeout = timeout

    async def answer(self, text: str, route: Route, recent: tuple[RecentCall, ...] = ()) -> Answer:
        """Chat the decision model is sure of, settled there; anything else as the reader reads
        it. Either way the answer says the decision model sorted it, and how likely it found the
        post chat, so every post shows what the filter thought."""
        try:
            async with asyncio.timeout(self.timeout):
                result = await self.sorter.run(
                    json.dumps({"message": text}, ensure_ascii=False),
                    deps=ReadingInput(text=text, route=route, recent=recent),
                )
        # An unsure pick goes to the reader with the chance the decision model gave it.
        except UnsureRoute as unsure:
            return await self._read(text, route, recent, _chat(unsure.probabilities))
        # An outage goes to the reader as if there were no decision model.
        except ModelAPIError, TimeoutError, UnexpectedModelBehavior:
            return await self._read(text, route, recent, None)
        picked = (result.response.provider_details or {}).get("route") or {}
        chat = _chat(picked.get("probabilities") or {})
        if not isinstance(result.output, JustChat):
            return await self._read(text, route, recent, chat)
        return Answer(Chatter(), result.response.model_name, chat, sorted_by=self.name)

    async def _read(
        self, text: str, route: Route, recent: tuple[RecentCall, ...], chat: float | None
    ) -> Answer:
        answer = await self.reader.answer(text, route, recent)
        return replace(answer, sorted_confidence=chat, sorted_by=self.name)

    async def learn(self, posts: tuple[str, ...]) -> PlaybookProposal:
        return await self.reader.learn(posts)

    async def model_names(self) -> tuple[str, ...]:
        return await self.reader.model_names()

    async def close(self) -> None:
        try:
            await self.reader.close()
        finally:
            await self.close_sorter()


def sorted_decoder(
    reader: ManagedDecoder, config: TriageConfig, *, diagnostics: PayloadCapture | None = None
) -> SortedDecoder:
    model, close = decision_model(config, diagnostics=diagnostics)
    return SortedDecoder(reader, sorting_agent(model), close, config.timeout, model.model_name)


def _chat(probabilities: object) -> float | None:
    """How likely the decision model found the post chat, from its route probabilities."""
    if not isinstance(probabilities, dict):
        return None
    chance = probabilities.get("JustChat")
    return float(chance) if isinstance(chance, int | float) else None
