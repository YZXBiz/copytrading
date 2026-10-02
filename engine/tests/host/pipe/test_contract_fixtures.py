"""App contract fixtures keep the shared tagged response shapes."""

from ...contracts import contract


def test_contract_fixtures_have_the_shared_tagged_response_shapes():
    completed = contract("completed-self-test.json")
    failed = contract("failed-self-test.json")
    unknown = contract("unknown-version.json")

    assert completed["ok"]["type"] == "workflow"
    assert completed["ok"]["workflow"]["stage"] == "completed"
    assert len(completed["ok"]["workflow"]["outcomes"]) == 2
    assert failed["ok"]["type"] == "workflow"
    assert failed["ok"]["workflow"]["stage"] == "failed"
    assert failed["ok"]["workflow"]["outcomes"] == []
    assert unknown == {
        "version": 2,
        "request_id": "req-unknown",
        "error": {"code": "invalid_request"},
    }
