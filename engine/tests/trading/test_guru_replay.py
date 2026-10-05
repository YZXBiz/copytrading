"""Replaying a guru's recent posts shows what each would have done, before they are switched on."""

# ruff: noqa: RUF001 - the guru's real posts and prefix use a fullwidth colon

from pathlib import Path
from typing import cast

import pytest
from pydantic import SecretStr

from copytrading_engine.parsing.extraction import DecodeError
from copytrading_engine.shared.owner_facing import OwnerFacingError
from copytrading_engine.trading.application.ports import OperatorEvidence
from copytrading_engine.trading.application.profile_review import ProfileReviewService
from copytrading_engine.trading.domain.config import ProviderConfiguration
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft

from ..readings import buy, commentary, trade

PROVIDER = ProviderConfiguration(name="deepseek", model="test-model")
PROFILE = ProfileBuilder().build(
    ProfileDraft(
        guru_id="zhao",
        display_name="赵哥",
        prefix="赵哥-股票：",
        playbook="",
        exit_basis="original_position",
        batches=3,
    )
)


class _History:
    def __init__(self, posts: tuple[str, ...]) -> None:
        self.posts = posts

    async def recent_posts(self, token, channel_id, author_id, limit):
        return self.posts


class _Reader:
    """Reads the buy as a buy, chatter as chatter, and fails on anything else."""

    def __init__(self) -> None:
        self.closed = False
        self.routes = []

    async def decode(self, text, route):
        self.routes.append(route)
        if text.startswith("25加了"):
            return trade(buy("ABC", "25", fraction="0.5", fraction_said="一半"))
        if text == "今天大盘不错":
            return commentary()
        raise DecodeError("invalid_model_output", retryable=False)

    async def close(self):
        self.closed = True


async def _replay(tmp_path: Path, posts: tuple[str, ...], reader: _Reader):
    async def factory(name, config):
        return reader

    service = ProfileReviewService(
        tmp_path,
        factory,
        lambda secrets: None,
        cast(OperatorEvidence, None),
        _History(posts),
    )
    return await service.replay_posts(
        "123", None, SecretStr("discord"), PROVIDER, SecretStr("model"), PROFILE
    )


async def test_each_recent_post_says_what_it_would_have_done(tmp_path):
    reader = _Reader()

    replay = await _replay(
        tmp_path,
        ("赵哥-股票：25加了一半abc", "赵哥-股票：今天大盘不错", "别人的帖子", "赵哥-股票：???"),
        reader,
    )

    assert [(post.decision, post.reason) for post in replay.posts] == [
        ("trade", "A current call"),
        ("ignore", "No trade action"),
        ("ignore", "source_prefix_mismatch"),
        ("review", "invalid_model_output"),
    ]
    assert replay.posts[0].instructions[0].fraction == 0.5
    # The draft's own rules read the posts, and the reader is closed afterwards.
    assert {route.batches for route in reader.routes} == {3}
    assert reader.closed


async def test_a_channel_with_no_posts_says_so(tmp_path):
    with pytest.raises(OwnerFacingError, match="no text posts to replay"):
        await _replay(tmp_path, (), _Reader())
