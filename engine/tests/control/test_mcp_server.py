"""The MCP server exposes the CLI's operations as tools, with the same contract and tiers."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from mcp import Client

from copytrading_engine.control.client import ControlClient
from copytrading_engine.control.mcp_server import build_server

from .fakes import FakeEngine, Relay, running_app, service

READ_TOOLS = {
    "get_status",
    "list_accounts",
    "list_activity",
    "list_account_events",
    "list_manual_commands",
    "get_manual_command",
    "preview_manual_order",
    "list_proposals",
    "get_proposal",
}
PAUSE_TOOLS = {"pause_processing", "pause_account"}
PROPOSE_TOOLS = {"propose_resume_account", "propose_recovery_preference", "propose_manual_order"}


@asynccontextmanager
async def session(directory: Path) -> AsyncIterator[tuple[Client, Relay, FakeEngine]]:
    """Open the MCP client inside the test's own task, as anyio's cancel scopes require."""
    control, engine, *_ = service()
    async with (
        running_app(directory / "application.db", control) as relay,
        Client(build_server(ControlClient(relay.path, timeout=5))) as client,
    ):
        yield client, relay, engine


async def test_tools_and_annotations_follow_the_tiers(tmp_path):
    async with session(tmp_path) as (client, _, _):
        tools = {tool.name: tool for tool in (await client.list_tools()).tools}
    assert set(tools) == READ_TOOLS | PAUSE_TOOLS | PROPOSE_TOOLS
    for name, tool in tools.items():
        hints = tool.annotations
        assert hints is not None
        assert hints.read_only_hint is (name in READ_TOOLS)
        assert hints.destructive_hint is (name in PROPOSE_TOOLS)
        assert hints.open_world_hint is False
        assert tool.output_schema is not None


async def test_status_is_structured(tmp_path):
    async with session(tmp_path) as (client, _, _):
        result = await client.call_tool("get_status")
    assert not result.is_error
    assert result.structured_content is not None
    assert result.structured_content["engine_state"] == "running"


async def test_accounts_list_each_position_with_the_posts_that_bought_it(tmp_path):
    async with session(tmp_path) as (client, _, _):
        result = await client.call_tool("list_accounts")
        tools = {tool.name: tool for tool in (await client.list_tools()).tools}
    assert not result.is_error
    assert result.structured_content is not None
    [position] = result.structured_content["items"][0]["positions"]
    [lot] = position["lots"]
    assert (lot["source_id"], lot["guru_id"]) == ("discord:demo:1", "alex")
    assert lot["untrusted_source_text"] == "ABC long here, small size"
    schema = tools["list_accounts"].output_schema
    assert schema is not None
    assert "LotView" in schema.get("$defs", {})


async def test_propose_only_asks_the_owner(tmp_path):
    async with session(tmp_path) as (client, _, engine):
        result = await client.call_tool("propose_resume_account", {"account_id": "paper"})
    assert not result.is_error
    assert result.structured_content is not None
    assert result.structured_content["state"] == "pending"
    assert engine.actions() == []


async def test_refusals_are_tool_errors_that_name_their_code(tmp_path):
    async with session(tmp_path) as (client, relay, _):
        relay.unlocked = False
        refused = await client.call_tool("list_accounts")
        paused = await client.call_tool("pause_processing")
    assert refused.is_error
    assert "locked: Unlock CopyTrading first." in refused.content[0].text
    assert not paused.is_error
