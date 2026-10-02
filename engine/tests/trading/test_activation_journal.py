"""Activation commits survive restarts; an unfinished activation is marked interrupted."""

from uuid import uuid4

from copytrading_engine.trading.adapters.activation import TradingActivationJournal


def test_unresolved_activation_is_interrupted_after_engine_restart(tmp_path):
    activation_id = str(uuid4())
    candidate_revision = "a" * 64
    path = tmp_path / "trading-activation.json"

    TradingActivationJournal(path).begin(activation_id, candidate_revision)
    reopened = TradingActivationJournal(path)

    status = reopened.status(activation_id, "paused")
    assert status.phase == "interrupted"
    assert status.candidate_revision == candidate_revision
    assert status.committed_revision is None
    assert status.committed_activation_id is None
    assert status.runtime_state == "paused"


def test_ready_activation_remains_committed_after_engine_restart(tmp_path):
    activation_id = str(uuid4())
    candidate_revision = "b" * 64
    path = tmp_path / "trading-activation.json"

    journal = TradingActivationJournal(path)
    journal.begin(activation_id, candidate_revision)
    journal.mark_ready(activation_id)
    reopened = TradingActivationJournal(path)

    status = reopened.status(activation_id, "paused")
    assert status.phase == "stopped"
    assert status.candidate_revision == candidate_revision
    assert status.committed_revision == candidate_revision
    assert status.committed_activation_id == activation_id


def test_failed_activation_preserves_prior_committed_revision(tmp_path):
    path = tmp_path / "trading-activation.json"
    first_id, second_id = str(uuid4()), str(uuid4())
    prior_revision = "c" * 64
    journal = TradingActivationJournal(path)
    journal.begin(first_id, prior_revision)
    journal.mark_ready(first_id)
    journal.mark_stopped(first_id)
    journal.begin(second_id, prior_revision)
    journal.mark_failed(second_id, "source_unavailable")

    status = journal.status(second_id, "failed")
    assert status.phase == "failed"
    assert status.candidate_revision == prior_revision
    assert status.committed_revision == prior_revision
    assert status.committed_activation_id == first_id
    assert status.error_code == "source_unavailable"


def test_reopened_interrupted_same_revision_retains_prior_commit_identity(tmp_path):
    path = tmp_path / "trading-activation.json"
    prior_id, interrupted_id = str(uuid4()), str(uuid4())
    revision = "e" * 64
    journal = TradingActivationJournal(path)
    journal.begin(prior_id, revision)
    journal.mark_ready(prior_id)
    journal.mark_stopped(prior_id)
    journal.begin(interrupted_id, revision)

    reopened = TradingActivationJournal(path)
    status = reopened.status(interrupted_id, "paused")

    assert status.phase == "interrupted"
    assert status.committed_revision == revision
    assert status.committed_activation_id == prior_id


def test_ready_commit_identity_survives_stop_and_engine_reopen(tmp_path):
    path = tmp_path / "trading-activation.json"
    activation_id = str(uuid4())
    revision = "f" * 64
    journal = TradingActivationJournal(path)
    journal.begin(activation_id, revision)
    journal.mark_ready(activation_id)
    journal.mark_stopped(activation_id)

    reopened = TradingActivationJournal(path)
    status = reopened.status(activation_id, "paused")

    assert status.phase == "stopped"
    assert status.committed_revision == revision
    assert status.committed_activation_id == activation_id
