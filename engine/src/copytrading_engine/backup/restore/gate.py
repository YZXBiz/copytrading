"""Fail-closed restore gate shared by bootstrap and the trading lifecycle."""

from __future__ import annotations

import os
import stat
from pathlib import Path
from uuid import uuid4

RESTORE_MANUAL_DISABLED_MARKER = ".restore-manual-disabled"


def restore_manual_disabled_path(owner_support_directory: Path) -> Path:
    return owner_support_directory / RESTORE_MANUAL_DISABLED_MARKER


def restore_manual_disabled(marker_path: Path) -> bool:
    """Treat every present or unreadable marker path as an active safety gate."""
    try:
        os.lstat(marker_path)
    except FileNotFoundError:
        return False
    except OSError:
        return True
    return True


def persist_restore_manual_disabled(marker_path: Path, payload: bytes) -> None:
    """Atomically persist the gate and sync both its contents and directory entry."""
    parent = marker_path.parent
    try:
        parent_info = os.lstat(parent)
    except OSError as exc:
        raise OSError("restore owner directory is unavailable") from exc
    if not stat.S_ISDIR(parent_info.st_mode) or stat.S_ISLNK(parent_info.st_mode):
        raise OSError("restore owner directory is invalid")
    temporary = parent / f".{RESTORE_MANUAL_DISABLED_MARKER}.{uuid4().hex}.tmp"
    directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    directory_descriptor = os.open(parent, directory_flags)
    file_descriptor = -1
    try:
        file_descriptor = os.open(
            temporary,
            os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
        remaining = memoryview(payload)
        while remaining:
            written = os.write(file_descriptor, remaining)
            if written <= 0:
                raise OSError("restore gate could not be written")
            remaining = remaining[written:]
        os.fsync(file_descriptor)
        os.close(file_descriptor)
        file_descriptor = -1
        os.replace(temporary, marker_path)
        os.fsync(directory_descriptor)
    finally:
        if file_descriptor >= 0:
            os.close(file_descriptor)
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        os.close(directory_descriptor)


def clear_restore_manual_disabled(marker_path: Path) -> None:
    """Remove a valid gate and sync the owner directory after a safe transition."""
    try:
        info = os.lstat(marker_path)
    except FileNotFoundError:
        return
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise OSError("restore gate marker is invalid")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    directory_descriptor = os.open(marker_path.parent, flags)
    try:
        os.unlink(marker_path)
        os.fsync(directory_descriptor)
    finally:
        os.close(directory_descriptor)
