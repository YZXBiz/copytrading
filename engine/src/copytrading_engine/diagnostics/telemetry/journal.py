"""The private diagnostics journal: one JSON object per line, kept by age and by size."""

import logging
import os
import re
import stat
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from io import TextIOWrapper
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any

JOURNAL_NAME = "diagnostics.jsonl"
_ROTATIONS = 7
_ROTATION_PATTERN = re.compile(r"diagnostics\.jsonl(\.\d+)?")


class _PrivateRotatingFileHandler(RotatingFileHandler):
    def __init__(self, *args: Any, on_error: Callable[[], None], **kwargs: Any) -> None:  # noqa: ANN401 - forwards RotatingFileHandler's arguments
        self._on_error = on_error
        super().__init__(*args, **kwargs)

    def handleError(self, record: logging.LogRecord) -> None:
        self._on_error()

    def _open(self) -> TextIOWrapper:
        # A buffered text stream may retry an ENOSPC write during close and
        # again from its finalizer, leaking a traceback after degradation.
        raw = open(self.baseFilename, f"{self.mode}b", buffering=0)
        stream = TextIOWrapper(raw, encoding=self.encoding, errors=self.errors, write_through=True)
        try:
            os.chmod(self.baseFilename, 0o600)
        except OSError:
            stream.close()
            raise
        return stream


def journal_logger(
    directory: Path,
    *,
    retention_age_days: int,
    max_bytes: int,
    on_error: Callable[[], None],
) -> tuple[logging.Logger | None, OSError | None]:
    """Open the journal; the newest file plus its rotations never exceed `max_bytes`."""
    try:
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(directory, 0o700)
        prune_journal(directory, retention_age_days=retention_age_days)
        handler = _PrivateRotatingFileHandler(
            directory / JOURNAL_NAME,
            maxBytes=max(1, max_bytes // (_ROTATIONS + 1)),
            backupCount=_ROTATIONS,
            encoding="utf-8",
            on_error=on_error,
        )
        os.chmod(directory / JOURNAL_NAME, 0o600)
        logger = logging.Logger(f"copytrading-diagnostics-{id(handler)}", logging.INFO)
        logger.propagate = False
        handler.setFormatter(logging.Formatter("%(message)s"))
        logger.addHandler(handler)
        return logger, None
    except OSError as exc:
        return None, exc


def prune_journal(directory: Path, *, retention_age_days: int, now: datetime | None = None) -> int:
    """Remove journal files last written before the retained window, by whole UTC day."""
    if not 1 <= retention_age_days <= 3_650:
        raise ValueError("diagnostics retention age is outside the supported bounds")
    current = (now or datetime.now(UTC)).astimezone(UTC).date()
    oldest_retained_day = current - timedelta(days=retention_age_days)
    deleted_bytes = 0
    for path in directory.iterdir():
        if not _ROTATION_PATTERN.fullmatch(path.name):
            continue
        try:
            info = os.lstat(path)
        except FileNotFoundError:
            continue
        if not stat.S_ISREG(info.st_mode):
            continue
        if datetime.fromtimestamp(info.st_mtime, UTC).date() < oldest_retained_day:
            path.unlink()
            deleted_bytes += info.st_size
    return deleted_bytes
