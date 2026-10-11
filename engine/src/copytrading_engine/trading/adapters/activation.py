"""Durable, secret-free activation state for explicit trading Start commands."""

import json
import os
from pathlib import Path
from typing import Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field

from copytrading_engine.trading.domain.status import TradingRunState

type ActivationPhase = Literal["starting", "ready", "failed", "stopped", "interrupted"]
type ActivationQueryPhase = Literal[
    "not_found", "starting", "ready", "failed", "stopped", "interrupted"
]


class ActivationRecord(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    activation_id: str = Field(pattern=r"^[0-9a-f-]{36}$")
    candidate_revision: str = Field(pattern=r"^[0-9a-f]{64}$")
    committed_revision: str | None = Field(default=None, pattern=r"^[0-9a-f]{64}$")
    committed_activation_id: str | None = Field(default=None, pattern=r"^[0-9a-f-]{36}$")
    phase: ActivationPhase
    error_code: str | None = Field(default=None, max_length=64)


class TradingActivationStatus(BaseModel):
    """Status returned for one requested activation, including last committed revision."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    requested_activation_id: str = Field(pattern=r"^[0-9a-f-]{36}$")
    activation_id: str | None = Field(default=None, pattern=r"^[0-9a-f-]{36}$")
    candidate_revision: str | None = Field(default=None, pattern=r"^[0-9a-f]{64}$")
    committed_revision: str | None = Field(default=None, pattern=r"^[0-9a-f]{64}$")
    committed_activation_id: str | None = Field(default=None, pattern=r"^[0-9a-f-]{36}$")
    phase: ActivationQueryPhase
    runtime_state: TradingRunState
    error_code: str | None = Field(default=None, max_length=64)


class TradingActivationJournal:
    """Atomically persist the last activation transition without storing credentials."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._record = self._read()
        # A new process has no running activation, so a saved "starting" or "ready" one ended
        # with the last process. Only the in-memory view says so: opening must not write,
        # because a restored copy is checked byte for byte before it is used.
        if self._record is not None and self._record.phase in {"starting", "ready"}:
            next_phase: ActivationPhase = (
                "interrupted" if self._record.phase == "starting" else "stopped"
            )
            self._record = self._record.model_copy(update={"phase": next_phase})

    @property
    def record(self) -> ActivationRecord | None:
        return self._record

    def begin(self, activation_id: str, candidate_revision: str) -> ActivationRecord:
        canonical_id = str(UUID(activation_id))
        if self._record is not None and self._record.activation_id == canonical_id:
            if self._record.candidate_revision != candidate_revision:
                raise ValueError("activation_id_reused_for_different_revision")
            if self._record.phase == "starting":
                return self._record
            raise ValueError("activation_id_already_used")
        if self._record is not None and self._record.phase == "starting":
            raise ValueError("activation_already_starting")
        record = ActivationRecord(
            activation_id=canonical_id,
            candidate_revision=candidate_revision,
            committed_revision=(
                self._record.committed_revision if self._record is not None else None
            ),
            committed_activation_id=(
                self._record.committed_activation_id if self._record is not None else None
            ),
            phase="starting",
        )
        self._replace(record)
        return record

    def mark_ready(self, activation_id: str) -> ActivationRecord:
        record = self._matching(activation_id)
        if record.phase == "ready":
            return record
        if record.phase != "starting":
            raise ValueError("activation_not_starting")
        record = record.model_copy(
            update={
                "phase": "ready",
                "committed_revision": record.candidate_revision,
                "committed_activation_id": record.activation_id,
            }
        )
        self._replace(record)
        return record

    def adopt(self, activation_id: str, revision: str) -> ActivationRecord:
        """The running activation now copies `revision`: limits changed while copying."""
        record = self._matching(activation_id)
        if record.phase not in {"starting", "ready"}:
            raise ValueError("activation_not_running")
        update = {"candidate_revision": revision}
        if record.committed_activation_id == record.activation_id:
            update["committed_revision"] = revision
        record = record.model_copy(update=update)
        self._replace(record)
        return record

    def mark_failed(self, activation_id: str, error_code: str) -> ActivationRecord:
        record = self._matching(activation_id)
        if record.phase == "failed":
            return record
        if record.phase != "starting":
            raise ValueError("activation_not_starting")
        record = record.model_copy(update={"phase": "failed", "error_code": error_code})
        self._replace(record)
        return record

    def mark_stopped(self, activation_id: str) -> ActivationRecord:
        record = self._matching(activation_id)
        if record.phase in {"failed", "interrupted", "stopped"}:
            return record
        record = record.model_copy(update={"phase": "stopped"})
        self._replace(record)
        return record

    def status(self, activation_id: str, runtime_state: TradingRunState) -> TradingActivationStatus:
        requested_id = str(UUID(activation_id))
        record = self._record
        if record is None:
            return TradingActivationStatus(
                requested_activation_id=requested_id,
                phase="not_found",
                runtime_state=runtime_state,
            )
        matches = record.activation_id == requested_id
        return TradingActivationStatus(
            requested_activation_id=requested_id,
            activation_id=record.activation_id,
            candidate_revision=record.candidate_revision,
            committed_revision=record.committed_revision,
            committed_activation_id=record.committed_activation_id,
            phase=record.phase if matches else "not_found",
            runtime_state=runtime_state,
            error_code=record.error_code if matches else None,
        )

    def _matching(self, activation_id: str) -> ActivationRecord:
        canonical_id = str(UUID(activation_id))
        if self._record is None or self._record.activation_id != canonical_id:
            raise ValueError("activation_record_not_found")
        return self._record

    def _replace(self, record: ActivationRecord) -> None:
        self._write(record)
        self._record = record

    def _read(self) -> ActivationRecord | None:
        if not self._path.exists():
            return None
        if self._path.is_symlink() or self._path.stat().st_size > 64 * 1024:
            raise ValueError("activation_journal_invalid")
        try:
            wrapper = json.loads(self._path.read_text(encoding="utf-8"))
            if not isinstance(wrapper, dict) or wrapper.get("version") != 1:
                raise ValueError("activation_journal_invalid")
            return ActivationRecord.model_validate(wrapper["record"])
        except OSError, AttributeError, KeyError, TypeError, json.JSONDecodeError, ValueError:
            raise ValueError("activation_journal_invalid") from None

    def _write(self, record: ActivationRecord) -> None:
        parent = self._path.parent
        parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        if parent.is_symlink() or self._path.is_symlink():
            raise ValueError("activation_journal_invalid")
        temporary = parent / f".{self._path.name}.{uuid4().hex}.tmp"
        encoded = json.dumps(
            {"version": 1, "record": record.model_dump(mode="json")},
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(encoded)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, self._path)
            directory_fd = os.open(parent, os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        except BaseException:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
            raise
