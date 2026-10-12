"""The decision model in front of the reader (ADR-0012).

A decision model answers a pick-one with calibrated probabilities instead of writing text. The
reader agent runs on `FallbackModel(decision model, reader)`: the decision model picks between
chat and a reading. Chat has nothing to fill, so a confident pick settles the post there; a
reading has the post's own words to cite, which a decision model cannot write, so it hands the
step to the reader, as it does any pick below the route threshold.
"""

from collections.abc import Awaitable, Callable

import httpx2 as httpx
from openai import AsyncOpenAI
from pydantic import BaseModel, Field
from pydantic_ai import Agent
from pydantic_ai.exceptions import ModelAPIError, ModelHTTPError
from pydantic_ai.models.decision import DecisionModel, DecisionModelSettings
from pydantic_ai.models.openai_decisions import OpenAIDecisionsModel
from pydantic_ai.models.typesafe import TypeSafeModel
from pydantic_ai.providers.openai_decisions import OpenAIDecisionsProvider
from pydantic_ai.providers.typesafe import TypeSafeProvider

from copytrading_engine.shared.model_providers import TriageConfig
from copytrading_engine.shared.payload_capture import PayloadCapture

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
