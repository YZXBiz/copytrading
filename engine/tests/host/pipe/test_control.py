"""App-only pipe operations for agent control: relay, list, approve, reject, discard."""

import json
from pathlib import Path
from typing import Any

from copytrading_engine.host.installation import Installation
from copytrading_engine.host.pipe.server import PipeServer
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore
from copytrading_engine.host.status import EngineQueries

from ...control.fakes import context, service

AGENT_LINE = json.dumps(
    {
        "schema_version": 1,
        "request_id": "agent-1",
        "operation": "propose_resume_account",
        "account_id": "paper",
    }
)


def _pipe(operation: str, **values: object) -> bytes:
    return json.dumps(
        {"version": 1, "request_id": f"pipe-{operation}", "operation": operation, **values}
    ).encode()


async def _call(server: PipeServer, operation: str, **values: object) -> dict[str, Any]:
    return json.loads(await server.handle_line(_pipe(operation, **values)))


def _server(database: Path, *, with_control: bool = True, restore_gated: bool = False):
    control, engine, *_ = service()
    installation = Installation(database)
    store = SQLiteSelfTestStore(installation)
    return (
        installation,
        store,
        engine,
        lambda: PipeServer(
            SelfTestService(store, SelfTestParser()),
            EngineQueries(store, installation.instance_id),
            restore_gated=restore_gated,
            control=control if with_control else None,
        ),
    )


async def test_owner_approves_a_relayed_proposal_once(tmp_path):
    installation, store, engine, build = _server(tmp_path / "application.db")
    with installation, store:
        server = build()
        relayed = await _call(
            server, "control", line=AGENT_LINE, context=context().model_dump(mode="json")
        )
        proposal = json.loads(relayed["ok"]["line"])["ok"]
        assert (relayed["ok"]["type"], proposal["state"]) == ("control", "pending")

        listed = await _call(server, "list_proposals")
        assert [item["proposal_id"] for item in listed["ok"]["proposals"]] == [
            proposal["proposal_id"]
        ]

        wrong = await _call(
            server, "approve_proposal", proposal_id=proposal["proposal_id"], digest="0" * 64
        )
        assert wrong["error"]["code"] == "invalid_request"

        approved = await _call(
            server,
            "approve_proposal",
            proposal_id=proposal["proposal_id"],
            digest=proposal["digest"],
        )
        assert approved["ok"]["proposal"]["state"] == "succeeded"
        again = await _call(
            server,
            "approve_proposal",
            proposal_id=proposal["proposal_id"],
            digest=proposal["digest"],
        )
        assert again["error"]["code"] == "invalid_request"
    assert len(engine.actions()) == 1


async def test_reject_discard_and_unknown_proposals(tmp_path):
    installation, store, engine, build = _server(tmp_path / "application.db")
    with installation, store:
        server = build()
        ctx = context().model_dump(mode="json")
        first = json.loads(
            (await _call(server, "control", line=AGENT_LINE, context=ctx))["ok"]["line"]
        )
        rejected = await _call(server, "reject_proposal", proposal_id=first["ok"]["proposal_id"])
        assert rejected["ok"]["proposal"]["state"] == "rejected"

        await _call(server, "control", line=AGENT_LINE, context=ctx)
        discarded = await _call(server, "discard_proposals")
        assert discarded["ok"] == {"type": "proposals_discarded", "count": 1}

        missing = await _call(server, "reject_proposal", proposal_id="p-000000000000")
        assert missing["error"]["code"] == "not_found"
    assert engine.actions() == []


async def test_control_is_unavailable_without_a_service_or_during_restore(tmp_path):
    for name, options in (
        ("no-service", {"with_control": False}),
        ("restoring", {"restore_gated": True}),
    ):
        installation, store, _, build = _server(tmp_path / name / "application.db", **options)
        with installation, store:
            reply = await _call(
                build(), "control", line=AGENT_LINE, context=context().model_dump(mode="json")
            )
        assert reply["error"]["code"] == "unavailable"


async def test_owner_reads_the_agent_audit_trail(tmp_path):
    installation, store, _, build = _server(tmp_path / "application.db")
    with installation, store:
        server = build()
        await _call(server, "control", line=AGENT_LINE, context=context().model_dump(mode="json"))
        reply = await _call(server, "agent_audit", limit=10)
    entries = reply["ok"]["entries"]
    assert reply["ok"]["type"] == "agent_audit"
    assert [(entry["operation"], entry["outcome"]) for entry in entries] == [
        ("propose_resume_account", "proposed")
    ]
    assert entries[0]["caller_path"] == "/usr/bin/agent"
