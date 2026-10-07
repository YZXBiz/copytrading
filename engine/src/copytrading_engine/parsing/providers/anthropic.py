"""Anthropic's adapter. The reading's schema goes in the instructions and the answer is checked
like any other: Anthropic compiles a strict output schema into a grammar, and the reading's is too
large for it on every Claude model, and newer models refuse a forced tool call."""

import logging

import httpx2 as httpx
from anthropic import APIConnectionError, AsyncAnthropic
from pydantic_ai import Agent, PromptedOutput
from pydantic_ai.models.anthropic import AnthropicModel
from pydantic_ai.providers.anthropic import AnthropicProvider

from copytrading_engine.parsing.extraction import ReadingOutput
from copytrading_engine.parsing.learning import LEARN_INSTRUCTIONS, PlaybookProposal
from copytrading_engine.shared.cleanup import close_logged
from copytrading_engine.shared.model_providers import ProviderConfig
from copytrading_engine.shared.payload_capture import PayloadCapture

from .pydantic_ai import PydanticAIDecoder, reading_agent
from .registry import ManagedDecoder
from .transport import DiagnosticHTTPTransport

log = logging.getLogger(__name__)


def client(config: ProviderConfig, http_client: httpx.AsyncClient | None = None) -> AsyncAnthropic:
    return AsyncAnthropic(
        api_key=config.api_key.get_secret_value(),
        max_retries=0,
        timeout=config.timeout,
        http_client=http_client,
    )


def chat_model(config: ProviderConfig, client: AsyncAnthropic) -> AnthropicModel:
    """The model the decoder reads with, which the assistant also chats with."""
    return AnthropicModel(config.model, provider=AnthropicProvider(anthropic_client=client))


def build_decoder(config: ProviderConfig, client: AsyncAnthropic) -> PydanticAIDecoder:
    model = chat_model(config, client)
    agent = reading_agent(
        model,
        PromptedOutput(ReadingOutput),
        {"temperature": 0, "max_tokens": 3000},
    )
    learner = Agent(
        model,
        output_type=PromptedOutput(PlaybookProposal),
        name="playbook_learner",
        instructions=LEARN_INSTRUCTIONS,
        retries=1,
        model_settings={"temperature": 0, "max_tokens": 8000},
    )
    return PydanticAIDecoder(
        agent, learner, client, config.timeout, connection_errors=(APIConnectionError,)
    )


async def create_decoder(
    config: ProviderConfig,
    *,
    diagnostics: PayloadCapture | None = None,
) -> ManagedDecoder:
    http_client = None
    if diagnostics is not None:
        http_client = httpx.AsyncClient(
            transport=DiagnosticHTTPTransport(
                httpx.AsyncHTTPTransport(retries=0), diagnostics, provider="anthropic"
            ),
            timeout=config.timeout,
            follow_redirects=False,
        )
    opened = client(config, http_client)
    try:
        return build_decoder(config, opened)
    except BaseException:
        await close_logged(opened.close, resource="provider_client", log=log)
        raise
