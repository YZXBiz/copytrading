"""Post one message into a test channel as the test account, for UI journeys.

Uses the same Discord client as the engine, reading the token from the environment, never from
arguments, so it does not appear in the process list.
"""

from __future__ import annotations

import asyncio
import os
import sys

import discord


async def post(channel_id: int, text: str) -> None:
    client = discord.Client()
    ready = asyncio.Event()

    @client.event
    async def on_ready() -> None:
        ready.set()

    runner = asyncio.create_task(client.start(os.environ["COPYTRADING_TEST_DISCORD_TOKEN"]))
    try:
        await asyncio.wait_for(ready.wait(), timeout=60)
        channel = client.get_channel(channel_id) or await client.fetch_channel(channel_id)
        await channel.send(text)  # ty: ignore[unresolved-attribute]
    finally:
        await client.close()
        await asyncio.gather(runner, return_exceptions=True)


if __name__ == "__main__":
    asyncio.run(post(int(sys.argv[1]), sys.argv[2]))
