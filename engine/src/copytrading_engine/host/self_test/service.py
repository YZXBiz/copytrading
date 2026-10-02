"""Engine self-test: durable acceptance followed by recoverable local processing."""

import asyncio

from copytrading_engine.host.errors import InvalidTransition, UnsupportedSelfTest
from copytrading_engine.host.self_test.model import (
    DestinationOutcome,
    ParseRejected,
    Stage,
    SubmitSelfTest,
    WorkflowView,
)
from copytrading_engine.host.self_test.ports import SelfTestParser, WorkflowStore

_DEFAULT_PROCESS_LIMIT = 100


class SelfTestService:
    """Accept and process self-tests using caller-owned ports."""

    def __init__(self, store: WorkflowStore, parser: SelfTestParser) -> None:
        self._store = store
        self._parser = parser
        self._processing_lock = asyncio.Lock()

    async def submit(self, command: SubmitSelfTest) -> WorkflowView:
        """Commit acceptance before returning the stable workflow identity."""
        acceptance = await self._store.accept_async(command)
        return acceptance.workflow

    async def process_pending(self, max_items: int = _DEFAULT_PROCESS_LIMIT) -> None:
        """Advance at most a bounded batch, leaving remaining jobs for recovery."""
        if max_items < 0:
            raise ValueError("max_items must not be negative")
        async with self._processing_lock:
            command_ids = await self._store.pending_async(limit=max_items)
            for command_id in command_ids:
                await self._process_one(command_id)

    async def _process_one(self, command_id: str) -> None:
        workflow = await self._store.get_async(command_id)
        if workflow.stage is Stage.CAPTURED:
            command = await self._store.load_command_async(command_id)
            try:
                parsed = self._parser.parse(command.text)
            except UnsupportedSelfTest:
                await self._store.advance_async(
                    command_id,
                    Stage.CAPTURED,
                    Stage.FAILED,
                    (),
                    parse_rejection=ParseRejected(command_id),
                )
                return
            workflow = await self._store.advance_async(
                command_id,
                Stage.CAPTURED,
                Stage.PARSED,
                (),
                parsed=parsed,
            )

        if workflow.stage is Stage.PARSED:
            command = await self._store.load_command_async(command_id)
            outcomes = tuple(
                DestinationOutcome(account_id=destination_id)
                for destination_id in command.destination_ids
            )
            await self._store.load_parsed_async(command_id)
            await self._store.advance_async(
                command_id,
                Stage.PARSED,
                Stage.COMPLETED,
                outcomes,
            )
            return

        if workflow.stage not in {Stage.COMPLETED, Stage.FAILED}:
            raise InvalidTransition("pending workflow is in an unsupported state")
