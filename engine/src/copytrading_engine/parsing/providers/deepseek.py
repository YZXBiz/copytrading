"""DeepSeek's OpenAI-compatible endpoint and prompted-JSON output mode."""

import logging

import httpx2 as httpx
from openai import APIConnectionError, AsyncOpenAI
from pydantic_ai import Agent, PromptedOutput
from pydantic_ai.models.decision import DecisionModel
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.deepseek import DeepSeekProvider
from pydantic_ai.settings import ModelSettings

from copytrading_engine.parsing.learning import LEARN_INSTRUCTIONS, PlaybookProposal
from copytrading_engine.shared.cleanup import close_logged
from copytrading_engine.shared.model_providers import ProviderConfig
from copytrading_engine.shared.payload_capture import PayloadCapture

from .pydantic_ai import PydanticAIDecoder, reading_agent, triaged_reading_agent
from .registry import ManagedDecoder
from .transport import DiagnosticHTTPTransport
from .triage import Close, decision_model

log = logging.getLogger(__name__)

ENDPOINT = "https://api.deepseek.com"


def client(config: ProviderConfig, http_client: httpx.AsyncClient | None = None) -> AsyncOpenAI:
    return AsyncOpenAI(
        api_key=config.api_key.get_secret_value(),
        base_url=ENDPOINT,
        max_retries=0,
        timeout=config.timeout,
        http_client=http_client,
    )


def chat_model(
    config: ProviderConfig, client: AsyncOpenAI, settings: ModelSettings | None = None
) -> OpenAIChatModel:
    """The model the decoder reads with, which the assistant also chats with."""
    return OpenAIChatModel(
        config.model, provider=DeepSeekProvider(openai_client=client), settings=settings
    )


_READING: ModelSettings = {
    "temperature": 0,
    "max_tokens": 3000,
    "extra_body": {"thinking": {"type": "disabled"}},
}


def build_decoder(
    config: ProviderConfig,
    client: AsyncOpenAI,
    *,
    triage: tuple[DecisionModel, Close] | None = None,
) -> PydanticAIDecoder:
    model = chat_model(config, client)
    agent = (
        reading_agent(model, _READING)
        if triage is None
        else triaged_reading_agent(triage[0], chat_model(config, client, _READING))
    )
    learner = Agent(
        model,
        output_type=PromptedOutput(PlaybookProposal),
        name="playbook_learner",
        instructions=LEARN_INSTRUCTIONS,
        retries=1,
        model_settings={
            # A long free-form draft can loop at temperature 0 until it is cut off mid-JSON;
            # a little temperature and a repetition penalty keep it moving.
            "temperature": 0.2,
            "frequency_penalty": 0.5,
            "max_tokens": 8000,
            "extra_body": {"thinking": {"type": "disabled"}},
        },
    )
    return PydanticAIDecoder(
        agent,
        learner,
        client,
        config.timeout,
        connection_errors=(APIConnectionError,),
        close_triage=triage[1] if triage is not None else None,
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
                httpx.AsyncHTTPTransport(retries=0), diagnostics, provider="deepseek"
            ),
            timeout=config.timeout,
            follow_redirects=False,
        )
    opened = client(config, http_client)
    triage = None
    try:
        if config.triage is not None:
            triage = decision_model(config.triage, diagnostics=diagnostics)
        return build_decoder(config, opened, triage=triage)
    except BaseException:
        await close_logged(opened.close, resource="provider_client", log=log)
        if triage is not None:
            await close_logged(triage[1], resource="triage_client", log=log)
        raise
