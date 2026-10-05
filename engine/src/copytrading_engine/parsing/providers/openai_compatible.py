"""Every model service that speaks OpenAI's chat interface, read through one adapter.

Each named service has its own address and, where PydanticAI knows the service, its own provider
class, which carries that service's model quirks (which token limit field it takes, which settings
a reasoning model refuses). The answer is asked for as JSON in the prompt, the one output mode
every chat model supports; the worker still validates and grounds it like any other answer."""

import logging
from collections.abc import Callable
from dataclasses import dataclass
from functools import partial

import httpx2 as httpx
from openai import APIConnectionError, AsyncOpenAI
from pydantic_ai import Agent, PromptedOutput
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.profiles import ModelProfileSpec
from pydantic_ai.profiles.openai import OpenAIModelProfile
from pydantic_ai.providers import Provider
from pydantic_ai.providers.cerebras import CerebrasProvider
from pydantic_ai.providers.fireworks import FireworksProvider
from pydantic_ai.providers.moonshotai import MoonshotAIProvider
from pydantic_ai.providers.ollama import OllamaProvider
from pydantic_ai.providers.openai import OpenAIProvider
from pydantic_ai.providers.openrouter import OpenRouterProvider
from pydantic_ai.providers.together import TogetherProvider

from copytrading_engine.parsing.extraction import ReadingOutput
from copytrading_engine.parsing.learning import LEARN_INSTRUCTIONS, PlaybookProposal
from copytrading_engine.shared.cleanup import close_logged
from copytrading_engine.shared.model_providers import OLLAMA_ENDPOINT, ModelProvider, ProviderConfig
from copytrading_engine.shared.payload_capture import PayloadCapture

from .pydantic_ai import PydanticAIDecoder, reading_agent
from .registry import DecoderFactory, ManagedDecoder
from .transport import DiagnosticHTTPTransport

log = logging.getLogger(__name__)

# Services whose chat endpoint takes `max_tokens` but not OpenAI's `max_completion_tokens`.
_MAX_TOKENS_ONLY = OpenAIModelProfile(openai_chat_supports_max_completion_tokens=False)


@dataclass(frozen=True)
class Service:
    endpoint: str | None
    provider: Callable[[AsyncOpenAI], Provider[AsyncOpenAI]]
    profile: ModelProfileSpec | None = None


def _openai(client: AsyncOpenAI) -> Provider[AsyncOpenAI]:
    return OpenAIProvider(openai_client=client)


SERVICES: dict[ModelProvider, Service] = {
    "openai": Service("https://api.openai.com/v1", _openai),
    "google": Service(
        "https://generativelanguage.googleapis.com/v1beta/openai/", _openai, _MAX_TOKENS_ONLY
    ),
    "openrouter": Service(
        "https://openrouter.ai/api/v1", lambda client: OpenRouterProvider(openai_client=client)
    ),
    "groq": Service("https://api.groq.com/openai/v1", _openai),
    "xai": Service("https://api.x.ai/v1", _openai),
    "mistral": Service("https://api.mistral.ai/v1", _openai, _MAX_TOKENS_ONLY),
    "together": Service(
        "https://api.together.xyz/v1", lambda client: TogetherProvider(openai_client=client)
    ),
    "fireworks": Service(
        "https://api.fireworks.ai/inference/v1",
        lambda client: FireworksProvider(openai_client=client),
    ),
    "cerebras": Service(
        "https://api.cerebras.ai/v1", lambda client: CerebrasProvider(openai_client=client)
    ),
    "moonshotai": Service(
        "https://api.moonshot.ai/v1", lambda client: MoonshotAIProvider(openai_client=client)
    ),
    "ollama": Service(OLLAMA_ENDPOINT, lambda client: OllamaProvider(openai_client=client)),
    "openai_compatible": Service(None, _openai),
}


def _endpoint(service: Service, config: ProviderConfig) -> str:
    endpoint = config.base_url or service.endpoint
    if endpoint is None:
        raise ValueError("A custom OpenAI-compatible model needs its address")
    return endpoint


def client(
    service: Service, config: ProviderConfig, http_client: httpx.AsyncClient | None = None
) -> AsyncOpenAI:
    return AsyncOpenAI(
        # A local model may take no key; the client still needs a value to send.
        api_key=config.api_key.get_secret_value() or "none",
        base_url=_endpoint(service, config),
        max_retries=0,
        timeout=config.timeout,
        http_client=http_client,
    )


def chat_model(service: Service, config: ProviderConfig, client: AsyncOpenAI) -> OpenAIChatModel:
    """The model the decoder reads with, which the assistant also chats with."""
    return OpenAIChatModel(config.model, provider=service.provider(client), profile=service.profile)


def build_decoder(
    service: Service, config: ProviderConfig, client: AsyncOpenAI
) -> PydanticAIDecoder:
    model = chat_model(service, config, client)
    agent = reading_agent(
        model,
        PromptedOutput(ReadingOutput),
        {"temperature": 0, "max_tokens": 3000},
    )
    learner = Agent(
        model,
        output_type=PromptedOutput(PlaybookProposal),
        instructions=LEARN_INSTRUCTIONS,
        retries=1,
        # A long free-form draft can loop at temperature 0; a little temperature keeps it moving.
        model_settings={"temperature": 0.2, "max_tokens": 8000},
    )
    return PydanticAIDecoder(
        agent, learner, client, config.timeout, connection_errors=(APIConnectionError,)
    )


async def create_decoder(
    name: ModelProvider,
    config: ProviderConfig,
    *,
    diagnostics: PayloadCapture | None = None,
) -> ManagedDecoder:
    service = SERVICES[name]
    _endpoint(service, config)
    http_client = None
    if diagnostics is not None:
        http_client = httpx.AsyncClient(
            transport=DiagnosticHTTPTransport(
                httpx.AsyncHTTPTransport(retries=0), diagnostics, provider=name
            ),
            timeout=config.timeout,
            follow_redirects=False,
        )
    opened = client(service, config, http_client)
    try:
        return build_decoder(service, config, opened)
    except BaseException:
        await close_logged(opened.close, resource="provider_client", log=log)
        raise


def factories() -> dict[ModelProvider, DecoderFactory]:
    return {name: partial(create_decoder, name) for name in SERVICES}
