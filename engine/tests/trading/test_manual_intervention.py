"""Manual corrections and confirmations run in order per account and replay after loss."""

import asyncio
import datetime as dt
import sqlite3
from types import SimpleNamespace

import pytest

from copytrading_engine.execution.domain.manual_commands import (
    ManualCommandPage,
    ManualCommandPageRequest,
    ManualCommandRecord,
    ManualCommandResult,
    ManualConfirmationRequest,
    ManualCorrectionRecord,
    ManualCorrectionRequest,
    ManualPreviewRequest,
    ManualSourceEvidence,
)
from copytrading_engine.shared.signals import Instruction, StockSignal
from copytrading_engine.trading.adapters import operator_queries
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

NOW = dt.datetime(2026, 1, 5, 15, tzinfo=dt.UTC)


async def test_manual_command_page_keeps_active_owner_read_path(tmp_path):
    runtime = TradingRuntime(tmp_path)
    source_id = "discord:demo:review-1"
    expected = ManualCommandPage(account_id="account-a", source_id=source_id, items=())
    calls = []

    class Owner:
        async def manual_command_page(self, source, *, before_command_id, limit):
            calls.append((source, before_command_id, limit))
            return expected

    runtime._accounts["account-a"] = SimpleNamespace(owner=Owner(), state="ready")
    request = ManualCommandPageRequest(
        account_id="account-a",
        source_id=source_id,
        before_command_id="command-cursor",
        limit=17,
    )

    assert await runtime.operator.list_manual_commands(request) == expected
    assert calls == [(source_id, "command-cursor", 17)]


def _source_evidence() -> ManualSourceEvidence:
    signal = StockSignal(
        source="discord",
        channel_id="demo",
        id="review-1",
        timestamp=NOW,
        text="Ambiguous reviewed trade",
        parser_profile="fixture",
        model="fixture",
        decision="review",
        reason="ambiguous_trade_details",
        evidence=(),
        instructions=(),
    )
    return ManualSourceEvidence(
        source_id="discord:demo:review-1",
        source_revision=7,
        source_at=NOW,
        text=signal.text,
        accepted_interpretation=signal,
    )


def _request(correction_id: str, price: str, reason: str = "Corrected review"):
    return ManualCorrectionRequest(
        correction_id=correction_id,
        source_id="discord:demo:review-1",
        selected_account_ids=("account-a", "account-b"),
        actor="operator",
        reason=reason,
        instructions=(
            Instruction(
                action="buy",
                symbol="ABC",
                price=price,
                fraction="0.25",
            ),
        ),
    )


class _CorrectionOwner:
    def __init__(self, *, fail_first: bool = False):
        self.records: dict[str, ManualCorrectionRecord] = {}
        self.fail_first = fail_first

    async def record_manual_correction(self, correction):
        if self.fail_first:
            self.fail_first = False
            raise OSError("simulated account ledger failure")
        previous = self.records.get(correction.correction_id)
        if previous is not None and previous != correction:
            raise ValueError("correction identity conflict")
        self.records[correction.correction_id] = correction
        return correction


async def test_correction_replication_repairs_one_account_and_serializes_revisions(
    tmp_path, monkeypatch
):
    runtime = TradingRuntime(tmp_path)
    owner_a = _CorrectionOwner(fail_first=True)
    owner_b = _CorrectionOwner()
    runtime._accounts = {
        "account-a": SimpleNamespace(owner=owner_a, state="ready"),
        "account-b": SimpleNamespace(owner=owner_b, state="ready"),
    }
    monkeypatch.setattr(
        runtime.manual._access.evidence, "manual_source_evidence", lambda *_: _source_evidence()
    )

    async def snapshots():
        return {
            "account-a": SimpleNamespace(manual_corrections=owner_a.records),
            "account-b": SimpleNamespace(manual_corrections=owner_b.records),
        }

    monkeypatch.setattr(runtime.manual, "_manual_snapshots", snapshots)
    request = _request("correction-1", "25")
    partial = await runtime.manual.save_manual_correction(request)
    assert partial.correction.revision == 1
    assert [item.status for item in partial.accounts] == ["failed", "recorded"]
    assert "correction-1" not in owner_a.records
    assert owner_b.records["correction-1"] == partial.correction

    repaired = await runtime.manual.save_manual_correction(request)
    assert repaired.correction == partial.correction
    assert [item.status for item in repaired.accounts] == ["recorded", "recorded"]
    assert owner_a.records["correction-1"] == owner_b.records["correction-1"]

    second, third = await asyncio.gather(
        runtime.manual.save_manual_correction(_request("correction-2", "26")),
        runtime.manual.save_manual_correction(_request("correction-3", "27")),
    )
    assert sorted((second.correction.revision, third.correction.revision)) == [2, 3]
    for correction in (second.correction, third.correction):
        assert owner_a.records[correction.correction_id] == correction
        assert owner_b.records[correction.correction_id] == correction

    with pytest.raises(ValueError, match="identity conflicts"):
        await runtime.manual.save_manual_correction(_request("correction-2", "28"))


async def test_manual_confirmation_returns_independent_account_results(tmp_path):
    runtime = TradingRuntime(tmp_path)
    requests = tuple(
        ManualConfirmationRequest(
            command_id=f"command-{account}",
            preview_id=f"preview-{account}",
            account_id=account,
            actor="operator",
        )
        for account in ("account-a", "account-b")
    )

    class Owner:
        def __init__(self, request):
            self.request = request
            self.record = ManualCommandRecord(
                request=request,
                correction_id="correction-1",
                source_id="discord:demo:review-1",
                instruction_index=0,
                confirmed_at=NOW,
                state="prepared",
                client_id=f"manual-{request.command_id}",
            )

        async def observation(self):
            if self.request.account_id == "account-b":
                raise OSError("simulated account read failure")
            return SimpleNamespace(
                ledger=SimpleNamespace(manual_commands={self.request.command_id: self.record})
            )

        async def confirm_manual_order(self, request, now):
            assert request == self.request
            return ManualCommandResult(
                command=self.record,
                status="uncertain",
                client_id=self.record.client_id,
            )

    async def refresh():
        return None

    runtime._accounts = {
        request.account_id: SimpleNamespace(owner=Owner(request), state="ready", refresh=refresh)
        for request in requests
    }

    outcome = await runtime.manual.confirm_manual_orders(requests)

    by_account = {item.account_id: item for item in outcome.outcomes}
    assert by_account["account-a"].result is not None
    assert by_account["account-a"].result.status == "uncertain"
    assert by_account["account-b"].error == "account_unavailable"


async def test_compound_confirmation_replays_durable_result_after_response_loss(
    tmp_path, monkeypatch
):
    runtime = TradingRuntime(tmp_path)
    evidence = _source_evidence()
    correction = ManualCorrectionRecord(
        correction_id="correction-compound",
        source_id=evidence.source_id,
        selected_account_ids=("account-a", "account-b"),
        revision=1,
        actor="operator",
        reason="Corrected the reviewed entry",
        instructions=(Instruction(action="buy", symbol="ABC", price="25", fraction="0.25"),),
        source_revision=evidence.source_revision,
        source_at=evidence.source_at,
        source_text=evidence.text,
        accepted_interpretation=evidence.accepted_interpretation,
        recorded_at=NOW,
    )
    requests = tuple(
        ManualConfirmationRequest(
            command_id=f"compound-{account}",
            preview_id=f"preview-{account}",
            account_id=account,
            actor="operator",
        )
        for account in ("account-a", "account-b")
    )

    class Owner:
        def __init__(self, request):
            self.request = request
            self.commands = {}
            self.submit_count = 0

        async def observation(self):
            preview = SimpleNamespace(
                request=SimpleNamespace(correction_id=correction.correction_id)
            )
            return SimpleNamespace(
                ledger=SimpleNamespace(
                    manual_commands=self.commands,
                    manual_previews={self.request.preview_id: preview},
                    manual_corrections={correction.correction_id: correction},
                )
            )

        async def confirm_manual_order(self, request, now):
            assert request == self.request
            command = self.commands.get(request.command_id)
            if command is None:
                self.submit_count += 1
                command = ManualCommandRecord(
                    request=request,
                    correction_id=correction.correction_id,
                    source_id=correction.source_id,
                    instruction_index=0,
                    confirmed_at=NOW,
                    state="prepared",
                    client_id=f"manual-{request.account_id}",
                )
                self.commands[request.command_id] = command
            return ManualCommandResult(
                command=command,
                status="accepted",
                client_id=command.client_id,
                broker_order_id=f"broker-{request.account_id}",
            )

    class Supervisor:
        def __init__(self, owner, *, lose_first_response=False):
            self.owner = owner
            self.state = "ready"
            self.lose_first_response = lose_first_response

        async def refresh(self):
            if self.lose_first_response:
                self.lose_first_response = False
                raise OSError("simulated response loss after durable intent")

    owners = {request.account_id: Owner(request) for request in requests}
    runtime._accounts = {
        request.account_id: Supervisor(
            owners[request.account_id],
            lose_first_response=request.account_id == "account-a",
        )
        for request in requests
    }

    async def snapshots(account_ids=None):
        return {
            request.account_id: SimpleNamespace(
                manual_corrections={correction.correction_id: correction}
            )
            for request in requests
            if account_ids is None or request.account_id in account_ids
        }

    monkeypatch.setattr(runtime.manual, "_manual_snapshots", snapshots)
    first = await runtime.manual.confirm_manual_orders(requests)
    first_by_account = {item.account_id: item for item in first.outcomes}
    assert first_by_account["account-a"].error == "account_unavailable"
    assert first_by_account["account-b"].result is not None

    replayed = await runtime.manual.confirm_manual_orders(requests)
    replayed_by_account = {item.account_id: item for item in replayed.outcomes}
    assert replayed_by_account["account-a"].result is not None
    assert replayed_by_account["account-a"].result.status == "accepted"
    assert replayed_by_account["account-b"].result is not None
    assert {account: owner.submit_count for account, owner in owners.items()} == {
        "account-a": 1,
        "account-b": 1,
    }


async def test_same_account_commands_are_sequenced_against_fresh_owner_state(tmp_path, monkeypatch):
    runtime = TradingRuntime(tmp_path)
    evidence = _source_evidence()
    correction = ManualCorrectionRecord(
        correction_id="correction-sequence",
        source_id=evidence.source_id,
        selected_account_ids=("account-a",),
        revision=1,
        actor="operator",
        reason="Reviewed a compound signal",
        instructions=(
            Instruction(action="buy", symbol="ABC", price="25", fraction="0.25"),
            Instruction(action="buy", symbol="XYZ", price="25", fraction="0.25"),
        ),
        source_revision=evidence.source_revision,
        source_at=evidence.source_at,
        source_text=evidence.text,
        accepted_interpretation=evidence.accepted_interpretation,
        recorded_at=NOW,
    )
    requests = tuple(
        ManualConfirmationRequest(
            command_id=f"sequence-{index}",
            preview_id=f"preview-{index}",
            account_id="account-a",
            actor="operator",
        )
        for index in (0, 1)
    )
    previews = {
        request.preview_id: SimpleNamespace(
            request=ManualPreviewRequest(
                preview_id=request.preview_id,
                account_id="account-a",
                correction_id=correction.correction_id,
                instruction_index=index,
            )
        )
        for index, request in enumerate(requests)
    }

    class Owner:
        def __init__(self):
            self.commands = {}
            self.commands_seen = []

        async def observation(self):
            self.commands_seen.append(tuple(self.commands))
            return SimpleNamespace(
                ledger=SimpleNamespace(
                    manual_commands=self.commands,
                    manual_previews=previews,
                    manual_corrections={correction.correction_id: correction},
                )
            )

        async def confirm_manual_order(self, request, now):
            if self.commands:
                command = ManualCommandRecord(
                    request=request,
                    correction_id=correction.correction_id,
                    source_id=correction.source_id,
                    instruction_index=1,
                    confirmed_at=now,
                    state="rejected",
                    reason="account_facts_changed",
                )
                result = ManualCommandResult(
                    command=command,
                    status="rejected",
                    reason="account_facts_changed",
                )
            else:
                command = ManualCommandRecord(
                    request=request,
                    correction_id=correction.correction_id,
                    source_id=correction.source_id,
                    instruction_index=0,
                    confirmed_at=now,
                    state="prepared",
                    client_id="manual-sequence-0",
                )
                result = ManualCommandResult(
                    command=command,
                    status="accepted",
                    client_id=command.client_id,
                )
            self.commands[request.command_id] = command
            return result

    class Supervisor:
        def __init__(self, owner):
            self.owner = owner
            self.state = "ready"
            self.refresh_count = 0

        async def refresh(self):
            self.refresh_count += 1

    owner = Owner()
    supervisor = Supervisor(owner)
    runtime._accounts = {"account-a": supervisor}

    async def snapshots(account_ids=None):
        if account_ids is not None and "account-a" not in account_ids:
            return {}
        return {
            "account-a": SimpleNamespace(manual_corrections={correction.correction_id: correction})
        }

    monkeypatch.setattr(runtime.manual, "_manual_snapshots", snapshots)
    outcome = await runtime.manual.confirm_manual_orders(requests)

    assert owner.commands_seen == [(), ("sequence-0",)]
    assert supervisor.refresh_count == 2
    assert [item.result.status for item in outcome.outcomes if item.result is not None] == [
        "accepted",
        "rejected",
    ]
    assert outcome.outcomes[1].result.reason == "account_facts_changed"


async def test_manual_preview_and_confirmation_ignore_corrupt_unselected_store(tmp_path):
    runtime = TradingRuntime(tmp_path)
    evidence = _source_evidence()
    correction = ManualCorrectionRecord(
        correction_id="correction-selected",
        source_id=evidence.source_id,
        selected_account_ids=("selected",),
        revision=1,
        actor="operator",
        reason="Reviewed selected account",
        instructions=(Instruction(action="buy", symbol="ABC", price="25", fraction="0.25"),),
        source_revision=evidence.source_revision,
        source_at=evidence.source_at,
        source_text=evidence.text,
        accepted_interpretation=evidence.accepted_interpretation,
        recorded_at=NOW,
    )
    preview_request = ManualPreviewRequest(
        preview_id="preview-selected",
        account_id="selected",
        correction_id=correction.correction_id,
        instruction_index=0,
    )
    command_request = ManualConfirmationRequest(
        command_id="command-selected",
        preview_id=preview_request.preview_id,
        account_id="selected",
        actor="operator",
    )

    class Owner:
        def __init__(self):
            self.previews = {}
            self.commands = {}
            self.preview_calls = 0
            self.submit_calls = 0

        async def observation(self):
            return SimpleNamespace(
                ledger=SimpleNamespace(
                    manual_corrections={correction.correction_id: correction},
                    manual_previews=self.previews,
                    manual_commands=self.commands,
                )
            )

        async def preview_manual_order(self, request, now):
            self.preview_calls += 1
            preview = SimpleNamespace(request=request)
            self.previews[request.preview_id] = preview
            return preview

        async def confirm_manual_order(self, request, now):
            self.submit_calls += 1
            record = ManualCommandRecord(
                request=request,
                correction_id=correction.correction_id,
                source_id=correction.source_id,
                instruction_index=0,
                confirmed_at=now,
                state="prepared",
                client_id="manual-selected",
            )
            self.commands[request.command_id] = record
            return ManualCommandResult(
                command=record, status="accepted", client_id=record.client_id
            )

    class Supervisor:
        state = "ready"

        def __init__(self, owner):
            self.owner = owner
            self.refresh_calls = 0

        async def refresh(self):
            self.refresh_calls += 1

    owner = Owner()
    supervisor = Supervisor(owner)
    runtime._accounts = {"selected": supervisor}
    selected_path = tmp_path / "accounts" / "selected" / "execution.sqlite3"
    corrupt_path = tmp_path / "accounts" / "retired" / "execution.sqlite3"
    corrupt_path.parent.mkdir(parents=True)
    corrupt_path.write_bytes(b"not a SQLite database")
    runtime.manual._access.retained_paths = lambda: {
        "selected": selected_path,
        "retired": corrupt_path,
    }
    with pytest.raises(sqlite3.DatabaseError):
        operator_queries.retained_account(corrupt_path)

    preview = await runtime.manual.preview_manual_order(preview_request)
    assert preview.request == preview_request
    outcome = await runtime.manual.confirm_manual_orders((command_request,))
    assert outcome.outcomes[0].result is not None
    assert owner.preview_calls == 1
    assert owner.submit_calls == 1
    assert supervisor.refresh_calls == 1
