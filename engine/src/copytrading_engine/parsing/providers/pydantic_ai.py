"""Provider-neutral decoding and safe error translation for PydanticAI."""

import asyncio
import json
from collections.abc import AsyncIterable, AsyncIterator
from contextlib import asynccontextmanager
from typing import Protocol

import pydantic_ai
from pydantic_ai import Agent, ModelRetry, NativeOutput, PromptedOutput, RunContext
from pydantic_ai.exceptions import (
    ModelAPIError,
    ModelHTTPError,
    UnexpectedModelBehavior,
    UsageLimitExceeded,
)
from pydantic_ai.models import Model
from pydantic_ai.settings import ModelSettings
from pydantic_ai.usage import UsageLimits

from copytrading_engine.parsing.diagnostics import validation_issues
from copytrading_engine.parsing.extraction import (
    DecodeError,
    GroundingError,
    ReadingInput,
    ReadingOutput,
    check_reading,
    check_references,
)
from copytrading_engine.parsing.history import RecentCall
from copytrading_engine.parsing.learning import PlaybookProposal
from copytrading_engine.parsing.prompt import (
    INSTRUCTIONS,
    playbook_instructions,
    recent_calls_instructions,
)
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.reading import PostReading

# The engine owns its output: its stdout and stderr are the app's pipe and log. The library
# leaves the flag unannotated, so its type is inferred as the literal True.
pydantic_ai.BANNER_ENABLED = False  # ty: ignore[invalid-assignment]


class _ListedModel(Protocol):
    @property
    def id(self) -> str: ...


class _ModelPages(Protocol):
    def list(self) -> AsyncIterable[_ListedModel]: ...


class _ProviderClient(Protocol):
    @property
    def models(self) -> _ModelPages: ...

    async def close(self) -> None: ...


# Words a provider uses when a request names a model it does not have. DeepSeek, for one, says
# "The supported API model names are …, but you passed …".
_UNKNOWN_MODEL = (
    "not exist",
    "not found",
    "invalid model",
    "unknown model",
    "no such model",
    "model names are",
    "you passed",
)
_MODEL_NAME_LIMIT = 2000


class PydanticAIDecoder:
    def __init__(
        self,
        agent: Agent[ReadingInput, ReadingOutput],
        learner: Agent[None, PlaybookProposal],
        client: _ProviderClient,
        timeout: float,
        *,
        connection_errors: tuple[type[Exception], ...] = (),
    ) -> None:
        self.agent = agent
        self.learner = learner
        self.client = client
        self.timeout = timeout
        self.connection_errors = connection_errors

    async def decode(
        self, text: str, route: Route, recent: tuple[RecentCall, ...] = ()
    ) -> PostReading:
        async with _translated_errors(self.connection_errors):
            async with asyncio.timeout(self.timeout):
                # A reading that fails a check goes back once with the reason, then to review.
                result = await self.agent.run(
                    json.dumps({"message": text}, ensure_ascii=False),
                    deps=ReadingInput(text=text, route=route, recent=recent),
                    usage_limits=UsageLimits(request_limit=2, output_tokens_limit=6000),
                )
            return result.output.reading

    async def learn(self, posts: tuple[str, ...]) -> PlaybookProposal:
        async with _translated_errors(self.connection_errors):
            async with asyncio.timeout(self.timeout):
                # One retry: a long draft occasionally comes back as invalid JSON.
                result = await self.learner.run(
                    json.dumps({"posts": list(posts)}, ensure_ascii=False),
                    usage_limits=UsageLimits(request_limit=2, output_tokens_limit=16000),
                )
            return result.output

    async def model_names(self) -> tuple[str, ...]:
        """The model names the provider lists for this key, as the owner would type them."""
        async with _translated_errors(self.connection_errors):
            async with asyncio.timeout(self.timeout):
                names: list[str] = []
                async for listed in self.client.models.list():
                    # Google lists "models/gemini-2.5-flash" but is asked for "gemini-2.5-flash".
                    names.append(listed.id.removeprefix("models/"))
                    if len(names) >= _MODEL_NAME_LIMIT:
                        break
                return tuple(names)

    async def close(self) -> None:
        await self.client.close()


def _rejection(exc: ModelHTTPError) -> str:
    """Name what a provider refused: the key, the model name, or something else in the request."""
    if exc.status_code in {401, 403}:
        return "provider_key_rejected"
    text = json.dumps(exc.body, default=str).lower() if exc.body is not None else ""
    # The answer is about the model name only when it quotes the name back and calls it unknown;
    # a 404 that names no model is a wrong address.
    quotes_name = bool(exc.model_name) and exc.model_name.lower() in text
    if exc.status_code in {400, 404} and quotes_name and any(w in text for w in _UNKNOWN_MODEL):
        return "provider_model_not_found"
    return "provider_rejected"


def reading_agent(
    model: Model,
    output_type: NativeOutput[ReadingOutput] | PromptedOutput[ReadingOutput],
    model_settings: ModelSettings,
) -> Agent[ReadingInput, ReadingOutput]:
    """The reader every provider shares: one reading per post, held to the post's own words. Its
    fixed instructions come first, then the guru's playbook, then the guru's recent calls, so a
    provider can cache the part that does not change from post to post."""
    agent = Agent(
        model,
        name="post_reader",
        output_type=output_type,
        instructions=INSTRUCTIONS,
        deps_type=ReadingInput,
        retries=1,
        model_settings=model_settings,
    )

    @agent.instructions
    def playbook(context: RunContext[ReadingInput]) -> str | None:
        return playbook_instructions(context.deps.route.playbook)

    @agent.instructions
    def recent_calls(context: RunContext[ReadingInput]) -> str | None:
        return recent_calls_instructions(context.deps.recent)

    agent.output_validator(_checked)
    return agent


def _checked(context: RunContext[ReadingInput], output: ReadingOutput) -> ReadingOutput:
    """Holds the model to the post's own words and to the calls it was shown; a failure gives it
    one retry with the reason."""
    try:
        check_reading(output.reading, context.deps.text, context.deps.route)
    except GroundingError as exc:
        raise ModelRetry(f"{exc.issue.path}: {exc}") from None
    problem = check_references(output.reading, context.deps.recent, retried=context.retry > 0)
    if problem is not None:
        raise ModelRetry(problem)
    return output


@asynccontextmanager
async def _translated_errors(
    connection_errors: tuple[type[Exception], ...],
) -> AsyncIterator[None]:
    """Turn provider failures into DecodeError without keeping responses or secrets."""
    try:
        yield
    except DecodeError:
        raise
    except ModelHTTPError as exc:
        retryable = exc.status_code == 429 or exc.status_code >= 500
        raise DecodeError(
            "provider_unavailable" if retryable else _rejection(exc), retryable=retryable
        ) from None
    except TimeoutError:
        raise DecodeError("provider_timeout", retryable=True) from None
    except connection_errors:
        raise DecodeError("provider_timeout", retryable=True) from None
    except ModelAPIError as exc:
        reason = (
            "provider_timeout"
            if connection_errors and isinstance(exc.__cause__, connection_errors)
            else "provider_unavailable"
        )
        raise DecodeError(reason, retryable=True) from None
    except UsageLimitExceeded:
        raise DecodeError("model_output_budget_exceeded", retryable=False) from None
    except UnexpectedModelBehavior as exc:
        raise DecodeError(
            "invalid_model_output", retryable=False, issues=validation_issues(exc)
        ) from None
