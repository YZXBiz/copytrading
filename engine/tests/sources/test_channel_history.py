"""Learning from a channel reads recent posts once and always logs out again."""

import asyncio
from types import SimpleNamespace

import discord
import pytest

from copytrading_engine.trading.adapters.channel_history import (
    ChannelHistoryError,
    DiscordChannelHistory,
)


def post(text: str, author: int = 7, *, embeds=()) -> SimpleNamespace:
    return SimpleNamespace(
        id=hash(text) % 10_000,
        content=text,
        embeds=list(embeds),
        attachments=[],
        author=SimpleNamespace(id=author),
        channel=SimpleNamespace(id=11),
        created_at=__import__("datetime").datetime(2026, 1, 5, tzinfo=__import__("datetime").UTC),
    )


class FakeChannel(discord.abc.Messageable):
    def __init__(self, messages) -> None:
        self.messages = messages
        self.asked_for = None

    async def _get_channel(self):  # pragma: no cover - never used by the fake
        return self

    async def history(self, limit):
        self.asked_for = limit
        for message in self.messages:
            yield message


class FakeClient:
    def __init__(self, channel=None, *, login_error=None, fetch_error=None, hang=False) -> None:
        self.channel, self.login_error, self.fetch_error, self.hang = (
            channel,
            login_error,
            fetch_error,
            hang,
        )
        self.closed = False

    async def login(self, token: str) -> None:
        if self.hang:
            await asyncio.sleep(10)
        if self.login_error:
            raise self.login_error

    async def fetch_channel(self, channel_id: int):
        if self.fetch_error:
            raise self.fetch_error
        return self.channel

    async def close(self) -> None:
        self.closed = True


def reader(client: FakeClient, **options) -> DiscordChannelHistory:
    return DiscordChannelHistory(client_factory=lambda: client, **options)


async def test_posts_come_back_oldest_first_and_skip_empty_ones():
    channel = FakeChannel([post("third"), post(""), post("second"), post("first")])
    client = FakeClient(channel)

    posts = await reader(client).recent_posts("token", "11", None, limit=2)

    assert posts == ("second", "third")
    assert channel.asked_for == 6
    assert client.closed


async def test_only_the_chosen_author_is_read():
    channel = FakeChannel([post("theirs", author=7), post("someone else", author=8)])

    assert await reader(FakeClient(channel)).recent_posts("t", "11", "7", limit=5) == ("theirs",)


async def test_an_oversized_post_is_skipped_not_fatal():
    channel = FakeChannel([post("x" * 10_001), post("fine")])

    assert await reader(FakeClient(channel)).recent_posts("t", "11", None, limit=5) == ("fine",)


@pytest.mark.parametrize(
    ("client", "message"),
    [
        (FakeClient(login_error=discord.LoginFailure("bad")), "rejected the saved token"),
        (
            FakeClient(fetch_error=discord.Forbidden(SimpleNamespace(status=403, reason=""), "")),
            "refused to show",
        ),
        (
            FakeClient(
                fetch_error=discord.HTTPException(SimpleNamespace(status=500, reason=""), "")
            ),
            "could not read",
        ),
        (FakeClient(channel=object()), "could not read"),
    ],
)
async def test_discord_problems_become_plain_owner_messages(client, message):
    with pytest.raises(ChannelHistoryError, match=message):
        await reader(client).recent_posts("t", "11", None, limit=3)
    assert client.closed


async def test_a_slow_discord_times_out_and_still_logs_out():
    client = FakeClient(hang=True)

    with pytest.raises(ChannelHistoryError, match="too long"):
        await reader(client, timeout_seconds=0.05).recent_posts("t", "11", None, limit=3)
    assert client.closed


def test_the_timeout_must_be_positive():
    with pytest.raises(ValueError, match="positive"):
        DiscordChannelHistory(timeout_seconds=0)
