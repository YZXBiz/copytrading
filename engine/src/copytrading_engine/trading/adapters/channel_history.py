"""Read a Discord channel's recent posts so the model can learn a guru's style."""

import asyncio
import logging
from collections.abc import Callable

import discord

from copytrading_engine.shared.cleanup import close_logged
from copytrading_engine.shared.owner_facing import OwnerFacingError
from copytrading_engine.sources.source import (
    InvalidSourceMessage,
    envelope,
    require_history_channel,
)

log = logging.getLogger(__name__)


class ChannelHistoryError(OwnerFacingError):
    """Discord could not provide the channel's recent posts."""


class DiscordChannelHistory:
    """Log in with the owner's token, read recent text posts, and log out again."""

    def __init__(
        self,
        *,
        client_factory: Callable[..., discord.Client] = discord.Client,
        timeout_seconds: float = 45,
    ) -> None:
        if timeout_seconds <= 0:
            raise ValueError("History timeout must be positive")
        self._client_factory = client_factory
        self._timeout_seconds = timeout_seconds

    async def recent_posts(
        self, token: str, channel_id: str, author_id: str | None, limit: int
    ) -> tuple[str, ...]:
        """Newest-last text of up to `limit` posts, optionally from one author."""
        client = self._client_factory()
        try:
            async with asyncio.timeout(self._timeout_seconds):
                await client.login(token)
                channel = require_history_channel(await client.fetch_channel(int(channel_id)))
                posts: list[str] = []
                async for message in channel.history(limit=limit * 3):
                    if author_id is not None and str(message.author.id) != author_id:
                        continue
                    # The same text the live pipeline reads: message body plus embeds.
                    try:
                        text = envelope(message).text.strip()
                    except InvalidSourceMessage:
                        continue
                    if text:
                        posts.append(text)
                    if len(posts) == limit:
                        break
                return tuple(reversed(posts))
        except asyncio.CancelledError:
            raise
        except TimeoutError:
            raise ChannelHistoryError(
                "Discord took too long to return the channel's history."
            ) from None
        except discord.Forbidden:
            raise ChannelHistoryError("Discord refused to show this channel's history.") from None
        except discord.LoginFailure:
            raise ChannelHistoryError("Discord rejected the saved token.") from None
        except discord.HTTPException, ValueError:
            raise ChannelHistoryError("Discord could not read this channel.") from None
        finally:
            await close_logged(client.close, resource="channel_history", log=log)
