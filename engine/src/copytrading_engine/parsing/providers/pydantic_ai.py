"""Provider-neutral decoding and safe error translation for PydanticAI."""

import asyncio
import json
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Protocol

from pydantic_ai import Agent
from pydantic_ai.exceptions import (
    ModelAPIError,
    ModelHTTPError,
    UnexpectedModelBehavior,
    UsageLimitExceeded,
)
from pydantic_ai.usage import UsageLimits

from copytrading_engine.parsing.diagnostics import validation_issues
from copytrading_engine.parsing.extraction import DecodedMessage, DecodeError
from copytrading_engine.parsing.learning import PlaybookProposal
from copytrading_engine.parsing.prompt import playbook_instructions
from copytrading_engine.parsing.routes import Route


class _ClosableClient(Protocol):
    async def close(self) -> None: ...


class PydanticAIDecoder:
    def __init__(
        self,
        agent: Agent[None, DecodedMessage],
        learner: Agent[None, PlaybookProposal],
        client: _ClosableClient,
        timeout: float,
        *,
        connection_errors: tuple[type[Exception], ...] = (),
    ) -> None:
        self.agent = agent
        self.learner = learner
        self.client = client
        self.timeout = timeout
        self.connection_errors = connection_errors

    async def decode(self, text: str, route: Route) -> DecodedMessage:
        async with _translated_errors(self.connection_errors):
            async with asyncio.timeout(self.timeout):
                result = await self.agent.run(
                    json.dumps({"message": text}, ensure_ascii=False),
                    instructions=playbook_instructions(route.playbook),
                    usage_limits=UsageLimits(request_limit=1, output_tokens_limit=3000),
                )
            return result.output

    async def learn(self, posts: tuple[str, ...]) -> PlaybookProposal:
        async with _translated_errors(self.connection_errors):
            async with asyncio.timeout(self.timeout):
                # One retry: a long draft occasionally comes back as invalid JSON.
                result = await self.learner.run(
                    json.dumps({"posts": list(posts)}, ensure_ascii=False),
                    usage_limits=UsageLimits(request_limit=2, output_tokens_limit=16000),
                )
            return result.output

    async def close(self) -> None:
        await self.client.close()


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
            "provider_unavailable" if retryable else "provider_rejected", retryable=retryable
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
