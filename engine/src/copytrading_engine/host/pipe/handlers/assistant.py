"""The in-app assistant: questions start answers the app polls; nothing outlives a reset."""

from copytrading_engine.assistant.service import AssistantService
from copytrading_engine.host.pipe.requests import (
    AssistantAskRequest,
    AssistantCancelRequest,
    AssistantResetRequest,
    AssistantTurnRequest,
    PipeRequest,
    RequestHandler,
)
from copytrading_engine.host.pipe.responses import reply


class AssistantHandlers:
    def __init__(self, *, assistant: AssistantService | None) -> None:
        self._assistant = assistant

    def handlers(self) -> dict[type[PipeRequest], RequestHandler]:
        return {
            AssistantAskRequest: self._ask,
            AssistantTurnRequest: self._turn,
            AssistantCancelRequest: self._cancel,
            AssistantResetRequest: self._reset,
        }

    async def _ask(self, request: AssistantAskRequest) -> bytes:
        if self._assistant is None:
            return reply(request.version, request.request_id, error="unavailable")
        turn_id = await self._assistant.ask(
            request.conversation_id,
            request.text,
            request.context,
            request.provider,
            request.provider_api_key,
        )
        return reply(
            request.version,
            request.request_id,
            ok={"type": "assistant_turn_started", "turn_id": turn_id},
        )

    async def _turn(self, request: AssistantTurnRequest) -> bytes:
        if self._assistant is None:
            return reply(request.version, request.request_id, error="unavailable")
        events, done = self._assistant.turn(request.turn_id, request.after)
        return reply(
            request.version,
            request.request_id,
            ok={
                "type": "assistant_turn",
                "turn_id": request.turn_id,
                "done": done,
                "events": [event.model_dump(mode="json") for event in events],
            },
        )

    async def _cancel(self, request: AssistantCancelRequest) -> bytes:
        if self._assistant is None:
            return reply(request.version, request.request_id, error="unavailable")
        return reply(
            request.version,
            request.request_id,
            ok={
                "type": "assistant_cancelled",
                "cancelled": self._assistant.cancel(request.turn_id),
            },
        )

    async def _reset(self, request: AssistantResetRequest) -> bytes:
        if self._assistant is not None:
            await self._assistant.reset()
        return reply(request.version, request.request_id, ok={"type": "assistant_reset"})
