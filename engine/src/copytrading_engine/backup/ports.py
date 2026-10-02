"""What backup and restore need from the engine: a write fence, schemas, account preparation."""

from __future__ import annotations

from contextlib import AbstractAsyncContextManager
from pathlib import Path
from typing import Protocol


class BackupFence(Protocol):
    def __call__(self) -> AbstractAsyncContextManager[None]: ...


class SchemaCatalogProvider(Protocol):
    def __call__(self, member_path: str) -> tuple[tuple[str, str, str, str], ...]: ...


class AccountSnapshotSchemaProvider(Protocol):
    @property
    def execution_schema_revision(self) -> int: ...

    @property
    def snapshot_json_schema_version(self) -> int: ...

    def validate_snapshot(self, serialized: str) -> tuple[str | None, str | None]: ...


class RestoredAccountPreparer(Protocol):
    def __call__(self, path: Path) -> None: ...
