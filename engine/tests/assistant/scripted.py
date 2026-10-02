"""Scripted models and a service wired to them, shared by the assistant's service tests."""

import asyncio
import inspect
import json
from collections.abc import Callable

from pydantic_ai.messages import ModelMessage, ModelResponse, TextPart, ToolCallPart
from pydantic_ai.models.function import AgentInfo, DeltaToolCall, FunctionModel

from copytrading_engine.assistant.service import AssistantService

from ..control.fakes import service as control_service


def streamed(reply: Callable[[list[ModelMessage], AgentInfo], object]) -> FunctionModel:
    """A model answering each request with `reply`'s ModelResponse, sync or async, and streaming it.

    The assistant always streams, so a scripted model needs a stream function beside the plain one.
    """

    async def respond(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        response = reply(messages, info)
        return await response if inspect.isawaitable(response) else response

    async def stream(messages: list[ModelMessage], info: AgentInfo):
        response = await respond(messages, info)
        for index, part in enumerate(response.parts):
            if isinstance(part, TextPart):
                yield part.content
            elif isinstance(part, ToolCallPart):
                args = part.args if isinstance(part.args, str) else json.dumps(part.args or {})
                yield {
                    index: DeltaToolCall(
                        name=part.tool_name, json_args=args, tool_call_id=part.tool_call_id
                    )
                }

    return FunctionModel(respond, stream_function=stream)


def scripted(*replies: ModelResponse) -> FunctionModel:
    """A model that answers each request with the next scripted response."""
    queue = list(replies)
    return streamed(lambda messages, info: queue.pop(0))


def assistant(model, **options):
    """A service whose model opener hands back `model`; returns it, the engine, and the secrets."""
    control, engine, _audit, _clock = control_service()

    async def default_open(name, config):
        async def close():
            pass

        return model, close

    options.setdefault("open_model", default_open)

    registered: list[str] = []
    svc = AssistantService(
        control,
        engine,
        engine_state=lambda: "running",
        register_secrets=registered.extend,
        **options,
    )
    return svc, engine, registered


async def settle(svc, turn_id):
    """Wait for a turn to finish and return all of its events."""
    for _ in range(200):
        events, done = svc.turn(turn_id, 0)
        if done:
            return events
        await asyncio.sleep(0.01)
    raise AssertionError("turn never finished")
