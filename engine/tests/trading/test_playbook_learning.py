"""Learning a guru's playbook: the model's draft reaches the owner to edit, nothing is saved."""

# ruff: noqa: RUF001 - the guru's real posts and prefix use a fullwidth colon

from pathlib import Path
from typing import cast

import pytest
from pydantic import SecretStr

from copytrading_engine.parsing.extraction import DecodeError
from copytrading_engine.parsing.learning import PlaybookProposal
from copytrading_engine.shared.owner_facing import OwnerFacingError
from copytrading_engine.trading.application.ports import OperatorEvidence
from copytrading_engine.trading.application.profile_review import ProfileReviewService
from copytrading_engine.trading.domain.config import ProviderConfiguration

POSTS = (
    "赵哥-股票：25加了6分之一常规仓abc",
    "今天大盘不错",
    "赵哥-股票：27出一半25的abc",
)
PROVIDER = ProviderConfiguration(name="deepseek", model="test-model")


class _History:
    def __init__(self, posts: tuple[str, ...]) -> None:
        self.posts = posts
        self.calls: list[tuple[str, str, str | None, int]] = []

    async def recent_posts(self, token, channel_id, author_id, limit):
        self.calls.append((token, channel_id, author_id, limit))
        return self.posts


class _Learner:
    def __init__(self, result: PlaybookProposal | DecodeError) -> None:
        self.result = result
        self.seen: tuple[str, ...] = ()
        self.closed = False

    async def learn(self, posts):
        self.seen = posts
        if isinstance(self.result, DecodeError):
            raise self.result
        return self.result

    async def close(self):
        self.closed = True


def _proposal(**changes) -> PlaybookProposal:
    values = dict(
        playbook="  加 means buy\nabc is a literal ticker  ",
        summary=" Buys lead with the price. ",
    )
    return PlaybookProposal.model_validate(values | changes)


async def _learn(tmp_path: Path, history: _History, learner: _Learner):
    registered: list[str] = []

    async def factory(name, config):
        assert name == "deepseek"
        assert config.model == "test-model"
        return learner

    service = ProfileReviewService(
        tmp_path,
        factory,
        registered.extend,
        cast(OperatorEvidence, object()),
        history,
    )
    result = await service.learn_playbook(
        "1517754775674949742",
        None,
        SecretStr("discord-token"),
        PROVIDER,
        SecretStr("provider-key"),
    )
    return result, registered


async def test_draft_reads_the_channel_and_trims_the_playbook(tmp_path):
    history, learner = _History(POSTS), _Learner(_proposal())

    draft, registered = await _learn(tmp_path, history, learner)

    assert learner.seen == POSTS
    assert learner.closed
    assert history.calls == [("discord-token", "1517754775674949742", None, 80)]
    assert registered == ["discord-token", "provider-key"]
    assert draft.posts_read == 3
    assert draft.playbook == "加 means buy\nabc is a literal ticker"
    assert draft.summary == "Buys lead with the price."


async def test_an_empty_channel_is_explained_without_calling_the_model(tmp_path):
    learner = _Learner(_proposal())

    with pytest.raises(OwnerFacingError, match="no text posts"):
        await _learn(tmp_path, _History(()), learner)

    assert learner.seen == ()


async def test_provider_failure_becomes_an_owner_sentence_and_closes_the_client(tmp_path):
    learner = _Learner(DecodeError("provider_rejected", retryable=False))

    with pytest.raises(OwnerFacingError, match="rejected the request") as failure:
        await _learn(tmp_path, _History(POSTS), learner)

    assert "provider_rejected" not in str(failure.value)
    assert learner.closed
