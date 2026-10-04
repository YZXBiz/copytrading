"""Read-only profile work: learn a playbook, evaluate history, and check examples."""

import asyncio
import logging
from collections.abc import Callable, Collection
from pathlib import Path

from pydantic import SecretStr, ValidationError

from copytrading_engine.execution.domain.sizing import RouteConnection
from copytrading_engine.parsing.extraction import DecodeError, normalize, without_mentions
from copytrading_engine.parsing.learning import PlaybookProposal
from copytrading_engine.parsing.providers.registry import NamedDecoderFactory
from copytrading_engine.shared.cleanup import close_logged
from copytrading_engine.shared.owner_facing import OwnerFacingError
from copytrading_engine.trading.application.ports import ChannelHistory, OperatorEvidence
from copytrading_engine.trading.domain.config import ProviderConfiguration
from copytrading_engine.trading.domain.profiles import (
    LearnedPlaybook,
    ProfileEvaluation,
    ProfileEvaluationService,
    ProfileExample,
    ProfileExampleReview,
    ProfileExampleReviewService,
    ProfileRevision,
)

# Enough posts to see a guru's habits; few enough to stay one bounded model call.
LEARNING_POST_LIMIT = 80
# Writing a whole playbook takes far longer than reading one post.
LEARNING_TIMEOUT_SECONDS = 150

log = logging.getLogger(__name__)


class ProfileReviewService:
    """Interpret with a temporary decoder; never open execution owners or order outboxes."""

    def __init__(
        self,
        data_dir: Path,
        decoder: NamedDecoderFactory,
        register_secrets: Callable[[Collection[str]], None],
        evidence: OperatorEvidence,
        history: ChannelHistory,
    ) -> None:
        self._data_dir = data_dir
        self._evidence = evidence
        self._history = history
        self._decoder = decoder
        self._register_secrets = register_secrets

    async def evaluate_historical_profile(
        self,
        source_id: str,
        profile: ProfileRevision,
        provider: ProviderConfiguration,
        provider_api_key: SecretStr,
        destinations: list[RouteConnection],
    ) -> ProfileEvaluation:
        """Evaluate one captured historical message without opening execution owners."""
        self._register_secrets((provider_api_key.get_secret_value(),))
        source = await asyncio.to_thread(
            self._evidence.historical_source_message, self._data_dir / "application.db", source_id
        )
        decoder = await self._decoder(
            provider.name,
            provider.reader(provider_api_key, timeout=20),
        )
        try:
            service = ProfileEvaluationService(
                decoder, provider=provider.name, model=provider.model
            )
            return await service.evaluate(source, profile, destinations=tuple(destinations))
        finally:
            await close_logged(decoder.close, resource="provider", log=log)

    async def review_profile_examples(
        self,
        profile: ProfileRevision,
        provider: ProviderConfiguration,
        provider_api_key: SecretStr,
        destinations: list[RouteConnection],
    ) -> ProfileExampleReview:
        """Interpret draft examples in memory without opening execution owners or stores."""
        self._register_secrets((provider_api_key.get_secret_value(),))
        if not profile.examples:
            return ProfileExampleReview(
                guru_id=profile.guru_id,
                profile_revision=profile.profile_revision,
                provider=provider.name,
                model=provider.model,
                cost_notice="No examples, so no provider call was made.",
                automatic_activation_allowed=True,
            )
        decoder = await self._decoder(
            provider.name,
            provider.reader(provider_api_key, timeout=20),
        )
        try:
            service = ProfileExampleReviewService(
                decoder, provider=provider.name, model=provider.model
            )
            return await service.evaluate(profile, destinations=tuple(destinations))
        finally:
            await close_logged(decoder.close, resource="provider", log=log)

    async def learn_playbook(
        self,
        channel_id: str,
        author_id: str | None,
        discord_token: SecretStr,
        provider: ProviderConfiguration,
        provider_api_key: SecretStr,
    ) -> LearnedPlaybook:
        """Read the channel's recent posts and draft a playbook; nothing is saved."""
        self._register_secrets(
            (discord_token.get_secret_value(), provider_api_key.get_secret_value())
        )
        posts = await self._history.recent_posts(
            discord_token.get_secret_value(), channel_id, author_id, LEARNING_POST_LIMIT
        )
        if not posts:
            raise OwnerFacingError("This channel has no text posts to learn from yet.")
        decoder = await self._decoder(
            provider.name,
            provider.reader(provider_api_key, timeout=LEARNING_TIMEOUT_SECONDS),
        )
        try:
            proposal = await decoder.learn(posts)
        except DecodeError as exc:
            raise OwnerFacingError(_LEARNING_FAILURES.get(exc.reason, _LEARNING_FAILED)) from None
        finally:
            await close_logged(decoder.close, resource="provider", log=log)
        return _verified_draft(proposal, posts, provider)


_LEARNING_FAILED = "The model could not draft a playbook. Try again."
_LEARNING_FAILURES = {
    "provider_rejected": "The model provider rejected the request. Check the API key and model.",
    "provider_key_rejected": "The model provider did not accept the API key. Check Connections.",
    "provider_model_not_found": "The model provider has no model by that name. Check Connections.",
    "provider_unavailable": "The model provider is unavailable right now. Try again shortly.",
    "provider_timeout": "The model took too long to answer. Try again.",
}


def _verified_draft(
    proposal: PlaybookProposal, posts: tuple[str, ...], provider: ProviderConfiguration
) -> LearnedPlaybook:
    """Keep only what checks out, compared the way the live pipeline reads posts.

    An example must be one of the posts read (after the same normalization the pipeline
    applies) and must pass ProfileExample validation; the prefix must start at least one post.
    """
    by_normal_form = {normalize(post): post for post in posts}
    examples: list[ProfileExample] = []
    for item in proposal.examples:
        post = by_normal_form.get(normalize(item.message))
        if post is None:
            continue
        try:
            examples.append(
                ProfileExample(
                    message=post,
                    expected_action=item.expected_action,
                    expected_symbol=item.expected_symbol,
                    expected_fraction=item.exact_fraction(),
                )
            )
        except ValidationError:
            continue
    prefix = without_mentions(proposal.prefix or "") or None
    if prefix and not any(normal.startswith(normalize(prefix)) for normal in by_normal_form):
        prefix = None
    return LearnedPlaybook(
        posts_read=len(posts),
        prefix=prefix,
        exit_basis=proposal.exit_basis,
        playbook=proposal.playbook.strip(),
        examples=tuple(examples),
        summary=proposal.summary.strip(),
        provider=provider.name,
        model=provider.model,
    )
