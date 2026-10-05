"""A scripted decoder, source session, and account owner for runtime tests."""

import asyncio
import sqlite3
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

from copytrading_engine.parsing.extraction import DecodedMessage
from copytrading_engine.shared.signals import Evidence


class Decoder:
    async def decode(self, text, route):
        if text == "Market commentary only. No trade action.":
            return DecodedMessage(decision="ignore", reason="No trade action", instructions=())
        assert text == "Bought AAPL at 200"
        assert route.prefix == "ALERT:"
        return DecodedMessage(
            decision="trade",
            reason="Current buy",
            instructions=(
                Evidence(
                    action="buy",
                    symbol="AAPL",
                    price=Decimal("200"),
                    action_evidence="Bought",
                    symbol_evidence="AAPL",
                    price_evidence="200",
                ),
            ),
        )

    async def close(self):
        pass


class Session:
    def __init__(self, source, event):
        self.source = source
        self.event = event
        self.ready = True
        self.capture_task = None

    def start(self, token):
        assert token == "discord-secret"
        if self.event is not None:
            self.capture_task = asyncio.create_task(self.source.add(self.event))

    async def ensure_running(self):
        if self.capture_task is not None:
            await self.capture_task

    async def forward_if_ready(self, forwarder):
        await forwarder.flush()

    async def close(self):
        if self.capture_task is not None:
            await self.capture_task


class Owner:
    def __init__(self, path: Path, fail_once: dict[str, int], attempts: dict[str, int]):
        self.name = path.name
        self.fail_once = fail_once
        self.attempts = attempts
        self.db = sqlite3.connect(path / "fake-receipts.sqlite3")
        self.db.execute("CREATE TABLE IF NOT EXISTS receipts (id TEXT PRIMARY KEY)")
        self.stopped = False
        self.closed = False
        self.cycles = 0
        self.outstanding_work = False
        self.deliveries = []

    async def receive(self, delivery, now):
        assert now.tzinfo is not None
        assert delivery.terms.connection.account_id == self.name
        signal = delivery.signal
        self.attempts[self.name] = self.attempts.get(self.name, 0) + 1
        if self.fail_once.get(self.name, 0):
            self.fail_once[self.name] -= 1
            raise RuntimeError("fake account unavailable")
        self.deliveries.append(delivery)
        identity = f"{signal.source}:{signal.channel_id}:{signal.id}"
        self.db.execute("INSERT OR IGNORE INTO receipts VALUES (?)", (identity,))
        self.db.commit()

    async def cycle(self, now, *, halted):
        assert not halted
        self.cycles += 1
        return SimpleNamespace(ledger=SimpleNamespace(has_outstanding_work=self.outstanding_work))

    async def account_status(self):
        from copytrading_engine.execution.application.ports import AccountRuntimeView

        return AccountRuntimeView("disabled", "manual", "disabled", "ready", None, "ready", None)

    async def operator_overview(self):
        from copytrading_engine.execution.presentation.operator_views import AccountOverview

        return AccountOverview(
            account_id=self.name,
            environment="paper",
            active_configuration=True,
            broker_identity=self.name,
            entry_permission="disabled",
            recovery_preference="manual",
            readiness="disabled",
            account_risk_status="ready",
            account_risk_reason=None,
            account_activity_status="ready",
            account_activity_reason=None,
            total_exposure_usd=0,
            app_cost_basis_usd=0,
            positions=(),
            unresolved_incidents=(),
            ownership_incidents=(),
            pending_orders=0,
            pending_reports=0,
            oldest_report_at=None,
            balance=None,
        )

    async def destination_views(self, source_ids):
        from copytrading_engine.execution.presentation.operator_views import DestinationView

        received = {item[0] for item in self.db.execute("SELECT id FROM receipts").fetchall()}
        return {
            source_id: DestinationView(
                account_id=self.name,
                environment="paper",
                status="done",
                instruction_outcomes=(),
                orders=(),
            )
            for source_id in source_ids
            if source_id in received
        }

    async def pending_notifications(self):
        return ()

    async def confirm_notification(self, notification_id):
        raise AssertionError(notification_id)

    def request_stop(self):
        self.stopped = True

    async def close(self):
        self.closed = True
        self.db.close()
