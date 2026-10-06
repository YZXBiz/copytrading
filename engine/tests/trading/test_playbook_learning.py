"""Learning a guru's playbook: only verifiable parts of the model's draft reach the owner."""

# ruff: noqa: RUF001 - the guru's real posts and prefix use a fullwidth colon

from decimal import Decimal
from pathlib import Path
from typing import cast

import pytest
from pydantic import SecretStr

from copytrading_engine.parsing.extraction import DecodeError
from copytrading_engine.parsing.learning import LearnedExample, PlaybookProposal
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
        exit_basis="original_position",
        playbook="  加 means buy\nabc is a literal ticker  ",
        examples=(
            LearnedExample(message=POSTS[0], expected_action="buy", expected_symbol="ABC"),
            LearnedExample(
                message="赵哥-股票：invented post",
                expected_action="buy",
                expected_symbol="ABC",
            ),
            LearnedExample(
                message=POSTS[2], expected_action="reduce", expected_symbol="ABC"
            ),  # a reduce without its fraction is not a valid example
        ),
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


async def test_draft_keeps_only_verbatim_valid_examples(tmp_path):
    history, learner = _History(POSTS), _Learner(_proposal())

    draft, registered = await _learn(tmp_path, history, learner)

    assert learner.seen == POSTS
    assert learner.closed
    assert history.calls == [("discord-token", "1517754775674949742", None, 80)]
    assert registered == ["discord-token", "provider-key"]
    assert draft.posts_read == 3
    assert draft.playbook == "加 means buy\nabc is a literal ticker"
    assert [example.message for example in draft.examples] == [POSTS[0]]
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


@pytest.mark.parametrize(
    ("written", "exact"),
    [
        ("1/6", Decimal(1) / Decimal(6)),
        (" 1 / 2 ", Decimal("0.5")),
        ("0.5", Decimal("0.5")),
        ("1/0", None),
        ("a sixth", None),
        (None, None),
    ],
)
def test_learned_fractions_are_read_exactly(written, exact):
    example = LearnedExample(
        message="post", expected_action="buy", expected_symbol="ABC", expected_fraction=written
    )
    assert example.exact_fraction() == exact
