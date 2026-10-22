"""Guru profiles: evaluate a past post, review examples, learn a playbook."""

from copytrading_engine.host.pipe.requests import (
    EvaluateHistoricalProfileRequest,
    LearnGuruPlaybookRequest,
    PipeRequest,
    RequestHandler,
    ReviewProfileExamplesRequest,
)
from copytrading_engine.host.pipe.responses import reply
from copytrading_engine.host.pipe.services import TradingServices


class ProfileHandlers:
    """Evaluate, review, and learn guru profiles from past posts."""

    def __init__(self, *, trading: TradingServices | None) -> None:
        self._trading = trading

    def handlers(self) -> dict[type[PipeRequest], RequestHandler]:
        return {
            EvaluateHistoricalProfileRequest: self._on_evaluate_historical_profile,
            ReviewProfileExamplesRequest: self._on_review_profile_examples,
            LearnGuruPlaybookRequest: self._on_learn_guru_playbook,
        }

    async def _on_evaluate_historical_profile(
        self, request: EvaluateHistoricalProfileRequest
    ) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        evaluation = await self._trading.profiles.evaluate_historical_profile(
            request.source_id,
            request.profile,
            request.provider,
            request.provider_api_key,
            request.destinations,
        )
        return reply(
            request.version,
            request.request_id,
            ok={
                "type": "profile_evaluation",
                "evaluation": evaluation.model_dump(mode="json"),
            },
        )

    async def _on_review_profile_examples(self, request: ReviewProfileExamplesRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        review = await self._trading.profiles.review_profile_examples(
            request.profile,
            request.provider,
            request.provider_api_key,
            request.destinations,
        )
        return reply(
            request.version,
            request.request_id,
            ok={
                "type": "profile_example_review",
                "review": review.model_dump(mode="json"),
            },
        )

    async def _on_learn_guru_playbook(self, request: LearnGuruPlaybookRequest) -> bytes:
        if self._trading is None:
            return reply(request.version, request.request_id, error="unavailable")
        learned = await self._trading.profiles.learn_playbook(
            request.channel_id,
            request.author_id,
            request.discord_token,
            request.provider,
            request.provider_api_key,
        )
        return reply(
            request.version,
            request.request_id,
            ok={"type": "learned_playbook", "playbook": learned.model_dump(mode="json")},
        )
