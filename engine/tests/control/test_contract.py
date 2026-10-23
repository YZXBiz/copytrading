"""The published contract changes only on purpose."""

import json
from pathlib import Path

from copytrading_engine.control import wire
from copytrading_engine.control.cli import main

from ..contracts import contract

SCHEMA = Path(__file__).parent / "contract" / "schema-v1.json"


def test_published_schema_matches_the_models(capsys):
    assert main(["schema"]) == 0
    printed = json.loads(capsys.readouterr().out)
    assert printed == wire.json_schema()
    assert printed == json.loads(SCHEMA.read_text()), (
        "The control contract changed. Update contract/schema-v1.json deliberately, and raise "
        "SCHEMA_VERSION if the change breaks existing clients."
    )


def test_every_example_round_trips(tmp_path):
    examples = json.loads((Path(__file__).parent / "contract" / "examples.json").read_text())
    for request in examples["requests"]:
        assert json.loads(wire.REQUEST.dump_json(wire.REQUEST.validate_python(request))) == {
            **request
        }
    for response in examples["responses"]:
        model = wire.Response.model_validate_json(json.dumps(response))
        assert json.loads(model.model_dump_json()) == response


def test_app_fixtures_match_the_contract():
    single = contract("agent-proposal-response.json")["ok"]
    listed = contract("agent-proposals-response.json")["ok"]
    audit = contract("agent-audit-response.json")["ok"]
    for proposal in (single["proposal"], *listed["proposals"]):
        view = wire.ProposalView.model_validate_json(json.dumps(proposal))
        assert json.loads(view.model_dump_json()) == proposal
    assert {kind for kind in (item["subject"]["kind"] for item in listed["proposals"])} == {
        "resume_account",
        "confirm_manual_order",
    }
    assert audit["entries"]
    fields = {"at", "actor", "caller_pid", "caller_path", "operation", "tier", "outcome"}
    assert all(set(entry) == fields | {"proposal_id"} for entry in audit["entries"])


def test_setup_fixtures_match_the_contract():
    """The app decodes these requests and emits these responses; both sides check the files."""
    for request in contract("agent-setup-requests.json")["requests"]:
        parsed = wire.REQUEST.validate_json(json.dumps(request))
        assert parsed.operation in wire.SETUP_OPERATIONS
        assert json.loads(wire.REQUEST.dump_json(parsed)) == request
    assert {item["operation"] for item in contract("agent-setup-requests.json")["requests"]} == set(
        wire.SETUP_OPERATIONS
    )
    for response in contract("agent-setup-responses.json")["responses"]:
        wire.Response.model_validate_json(json.dumps(response))


def test_the_apps_setup_authorization_matches_the_pipe_contract():
    from copytrading_engine.host.pipe.requests import REQUEST_ADAPTER, AuthorizeSetupRequest

    request = REQUEST_ADAPTER.validate_json(json.dumps(contract("authorize-setup-request.json")))
    assert isinstance(request, AuthorizeSetupRequest)
    assert request.setup.apply is not None
    assert request.setup.apply.touches_live
    assert contract("setup-allowed-response.json")["ok"] == {"type": "setup_allowed"}
