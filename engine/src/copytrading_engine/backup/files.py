"""Private file copies, hashing, fsync, and tree walks that backup and restore rely on."""

from __future__ import annotations

import hashlib
import os
import stat
from pathlib import Path, PurePosixPath

from copytrading_engine.backup.manifest import (
    CANDIDATE_MANIFEST_NAME,
    BackupManifest,
    BackupManifestError,
)


def require_regular_file(path: Path, message: str) -> None:
    try:
        info = path.lstat()
    except OSError as exc:
        raise BackupManifestError(message) from exc
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise BackupManifestError(message)


def require_directory(path: Path, message: str) -> None:
    try:
        info = path.lstat()
    except OSError as exc:
        raise BackupManifestError(message) from exc
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise BackupManifestError(message)


def copy_private_bytes(path: Path, content: bytes) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def copy_private_file(source: Path, destination: Path, limit: int) -> tuple[str, int]:
    source_descriptor = os.open(
        source,
        os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
    )
    destination_descriptor = -1
    try:
        if not stat.S_ISREG(os.fstat(source_descriptor).st_mode):
            raise BackupManifestError("source attachment is invalid")
        destination_descriptor = os.open(
            destination,
            os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
        digest = hashlib.sha256()
        size = 0
        with os.fdopen(source_descriptor, "rb") as input_stream:
            source_descriptor = -1
            with os.fdopen(destination_descriptor, "wb") as output_stream:
                destination_descriptor = -1
                while chunk := input_stream.read(1024 * 1024):
                    size += len(chunk)
                    if size > limit:
                        raise BackupManifestError("source attachment exceeds the supported size")
                    digest.update(chunk)
                    output_stream.write(chunk)
                output_stream.flush()
                os.fsync(output_stream.fileno())
        os.chmod(destination, 0o600)
        return digest.hexdigest(), size
    finally:
        if source_descriptor >= 0:
            os.close(source_descriptor)
        if destination_descriptor >= 0:
            os.close(destination_descriptor)


def tree_paths(
    root: Path,
    manifest: BackupManifest,
    *,
    allow_candidate_manifest: bool = False,
) -> tuple[set[str], set[str]]:
    require_directory(root, "restore generation directory is unavailable")
    expected_files = {member.path for member in manifest.members}
    if allow_candidate_manifest:
        expected_files.add(CANDIDATE_MANIFEST_NAME)
    expected_directories: set[str] = set()
    for member in manifest.members:
        parts = PurePosixPath(member.path).parts
        for index in range(1, len(parts)):
            expected_directories.add(PurePosixPath(*parts[:index]).as_posix())

    actual_files: set[str] = set()
    actual_directories: set[str] = set()
    for current, directories, filenames in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        for name in directories:
            child = current_path / name
            require_directory(child, "restore generation contains an unsafe directory")
            actual_directories.add(child.relative_to(root).as_posix())
        for name in filenames:
            child = current_path / name
            require_regular_file(child, "restore generation contains an unsafe file")
            actual_files.add(child.relative_to(root).as_posix())
    if actual_files != expected_files or actual_directories != expected_directories:
        raise BackupManifestError("restore generation members changed after validation")
    return actual_files, actual_directories


def fsync_directory(path: Path) -> None:
    descriptor = os.open(
        path,
        os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
    )
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def fsync_tree(root: Path) -> None:
    directories: list[Path] = []
    for current, child_directories, filenames in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        directories.append(current_path)
        for name in child_directories:
            require_directory(
                current_path / name,
                "restore candidate contains an unsafe directory",
            )
        for name in filenames:
            path = current_path / name
            descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
            try:
                if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                    raise BackupManifestError("restore candidate contains an unsafe file")
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
    for directory in reversed(directories):
        fsync_directory(directory)
