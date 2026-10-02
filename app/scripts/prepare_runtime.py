"""Download and stage the pinned, native macOS runtime artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import posixpath
import re
import shutil
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = REPOSITORY_ROOT / "app/Resources/Runtime/artifacts.json"
SUPPORTED_PLATFORM = "darwin-arm64"
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
SAFE_ARTIFACT_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
CHUNK_SIZE = 1024 * 1024
DOWNLOAD_TIMEOUT_SECONDS = 30
MAX_DOWNLOAD_ATTEMPTS = 3


class ArtifactManifestError(ValueError):
    """The pinned runtime manifest is incomplete or unsupported."""


class ArtifactIntegrityError(ValueError):
    """An artifact failed integrity or safe-extraction checks."""


class RuntimeDownloadError(RuntimeError):
    """A pinned artifact could not be downloaded within the bounded retries."""


@dataclass(frozen=True, slots=True)
class Artifact:
    name: str
    version: str
    platform: str
    url: str
    sha256: str
    license: str
    license_url: str
    filename: str
    archive_root: str


def _required_text(value: object, field: str, *, artifact_index: int) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ArtifactManifestError(f"artifact {artifact_index} has missing or invalid {field}")
    return value.strip()


def load_artifacts(manifest_path: Path = DEFAULT_MANIFEST) -> tuple[Artifact, ...]:
    """Load a versioned manifest containing only supported pinned artifacts."""
    try:
        raw = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactManifestError(f"cannot read runtime manifest: {exc}") from exc

    if not isinstance(raw, dict) or raw.get("schema_version") != 1:
        raise ArtifactManifestError("unsupported runtime manifest schema")
    entries = raw.get("artifacts")
    if not isinstance(entries, list) or not entries:
        raise ArtifactManifestError("runtime manifest must contain artifacts")

    parsed: list[Artifact] = []
    names: set[str] = set()
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ArtifactManifestError(f"artifact {index} must be an object")
        fields = {
            field: _required_text(entry.get(field), field, artifact_index=index)
            for field in (
                "name",
                "version",
                "platform",
                "url",
                "sha256",
                "license",
                "license_url",
                "filename",
                "archive_root",
            )
        }
        if not SAFE_ARTIFACT_NAME_PATTERN.fullmatch(fields["name"]):
            raise ArtifactManifestError("artifact name must be a safe single path component")
        if fields["name"] in names:
            raise ArtifactManifestError(f"duplicate artifact name: {fields['name']}")
        names.add(fields["name"])
        if fields["platform"] != SUPPORTED_PLATFORM:
            raise ArtifactManifestError(
                f"unsupported platform for {fields['name']}: {fields['platform']}"
            )
        if not SHA256_PATTERN.fullmatch(fields["sha256"]):
            raise ArtifactManifestError(f"invalid sha256 for {fields['name']}")
        if not fields["url"].startswith("https://"):
            raise ArtifactManifestError(f"artifact URL must use HTTPS: {fields['name']}")
        if Path(fields["filename"]).name != fields["filename"]:
            raise ArtifactManifestError(f"filename must not contain a path: {fields['name']}")
        if (
            fields["archive_root"].startswith("/")
            or ".." in PurePosixPath(fields["archive_root"]).parts
        ):
            raise ArtifactManifestError(
                f"archive_root must stay inside extraction root: {fields['name']}"
            )
        parsed.append(Artifact(**fields))

    return tuple(parsed)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest()


def _archive_path(name: str) -> PurePosixPath:
    if not name or "\x00" in name or "\\" in name:
        raise ArtifactIntegrityError(f"unsafe archive member path: {name!r}")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise ArtifactIntegrityError(f"unsafe archive member path: {name!r}")
    if path.parts and re.match(r"^[A-Za-z]:", path.parts[0]):
        raise ArtifactIntegrityError(f"unsafe archive member path: {name!r}")
    return path


def _safe_link_target(member: tarfile.TarInfo, member_path: PurePosixPath) -> None:
    target = member.linkname
    if not target or "\x00" in target or "\\" in target:
        raise ArtifactIntegrityError(f"unsafe archive link target: {target!r}")
    target_path = PurePosixPath(target)
    if target_path.is_absolute() or (target_path.parts and ":" in target_path.parts[0]):
        raise ArtifactIntegrityError(f"unsafe archive link target: {target!r}")
    if member.issym():
        resolved = posixpath.normpath(posixpath.join(str(member_path.parent), target))
    else:
        resolved = posixpath.normpath(target)
    if resolved == ".." or resolved.startswith("../"):
        raise ArtifactIntegrityError(f"archive link escapes extraction root: {target!r}")


def _validate_members(members: list[tarfile.TarInfo]) -> None:
    if not members:
        raise ArtifactIntegrityError("archive is empty")
    seen: set[str] = set()
    for member in members:
        member_path = _archive_path(member.name)
        normalized_name = str(member_path)
        if normalized_name in seen:
            raise ArtifactIntegrityError(f"archive contains duplicate member: {member.name}")
        seen.add(normalized_name)
        if member.isdir() or member.isfile():
            continue
        if member.issym() or member.islnk():
            _safe_link_target(member, member_path)
            continue
        raise ArtifactIntegrityError(f"unsupported archive member type: {member.name}")


def verify_and_extract(
    archive: Path,
    *,
    expected_sha256: str,
    destination: Path,
) -> None:
    """Verify bytes, validate all members, then atomically extract a tar archive."""
    if not SHA256_PATTERN.fullmatch(expected_sha256):
        raise ArtifactIntegrityError("expected sha256 must be 64 lowercase hex characters")
    actual_sha256 = _sha256(archive)
    if actual_sha256 != expected_sha256:
        raise ArtifactIntegrityError("artifact sha256 does not match the pinned digest")

    try:
        with tarfile.open(archive, mode="r:*") as source:
            members = source.getmembers()
            _validate_members(members)
            destination = destination.absolute()
            if destination.exists():
                raise ArtifactIntegrityError("extraction destination already exists")
            destination.parent.mkdir(parents=True, exist_ok=True)
            stage = Path(
                tempfile.mkdtemp(prefix=f".{destination.name}.stage-", dir=destination.parent)
            )
            try:
                source.extractall(stage, members=members, filter="data")
                root = stage.resolve()
                for link in stage.rglob("*"):
                    if link.is_symlink() and not link.resolve(strict=False).is_relative_to(root):
                        raise ArtifactIntegrityError("extracted symlink escapes extraction root")
                stage.replace(destination)
            except Exception:
                shutil.rmtree(stage, ignore_errors=True)
                raise
    except ArtifactIntegrityError:
        raise
    except (OSError, tarfile.TarError, ValueError) as exc:
        raise ArtifactIntegrityError(f"artifact archive is invalid: {exc}") from exc


def _download(url: str, destination: Path) -> None:
    """Stream one pinned artifact to a sibling temporary file before promotion."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    last_error: Exception | None = None
    for attempt in range(MAX_DOWNLOAD_ATTEMPTS):
        fd, temporary_name = tempfile.mkstemp(
            prefix=f".{destination.name}.download-", dir=destination.parent
        )
        temporary_path = Path(temporary_name)
        try:
            request = urllib.request.Request(
                url,
                headers={"User-Agent": "copytrading-desktop-runtime/1"},
            )
            with (
                os.fdopen(fd, "wb") as output,
                urllib.request.urlopen(request, timeout=DOWNLOAD_TIMEOUT_SECONDS) as response,
            ):
                while chunk := response.read(CHUNK_SIZE):
                    output.write(chunk)
                output.flush()
                os.fsync(output.fileno())
            temporary_path.replace(destination)
            return
        except (OSError, urllib.error.URLError, TimeoutError) as exc:
            last_error = exc
            try:
                os.close(fd)
            except OSError:
                pass
            temporary_path.unlink(missing_ok=True)
            if attempt + 1 < MAX_DOWNLOAD_ATTEMPTS:
                time.sleep(0.5 * (2**attempt))
    raise RuntimeDownloadError(f"download failed after bounded retries: {last_error}")


def _verify_host() -> None:
    if sys.platform != "darwin" or platform.machine() not in {"arm64", "aarch64"}:
        raise RuntimeError("runtime preparation requires native Apple Silicon macOS")


def prepare_runtime(output: Path, *, manifest_path: Path = DEFAULT_MANIFEST) -> None:
    _verify_host()
    artifacts = load_artifacts(manifest_path)
    output = output.expanduser().absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise FileExistsError(f"runtime output already exists: {output}")

    cache = REPOSITORY_ROOT / "dist/desktop-runtime/cache"
    cache.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{output.name}.stage-", dir=output.parent))
    try:
        prepared: list[dict[str, str]] = []
        for artifact in artifacts:
            cached_archive = cache / artifact.filename
            if not cached_archive.is_file() or _sha256(cached_archive) != artifact.sha256:
                _download(artifact.url, cached_archive)
            if _sha256(cached_archive) != artifact.sha256:
                raise ArtifactIntegrityError(
                    f"downloaded {artifact.name} does not match its pinned digest"
                )
            extracted = stage / artifact.name
            verify_and_extract(
                cached_archive,
                expected_sha256=artifact.sha256,
                destination=extracted,
            )
            payload_root = extracted / artifact.archive_root if artifact.archive_root else extracted
            if not payload_root.is_dir():
                raise ArtifactIntegrityError(
                    f"{artifact.name} archive is missing its declared archive root"
                )
            prepared.append(
                {
                    "name": artifact.name,
                    "version": artifact.version,
                    "sha256": artifact.sha256,
                }
            )

        (stage / "runtime.json").write_text(
            json.dumps({"schema_version": 1, "artifacts": prepared}, indent=2) + "\n",
            encoding="utf-8",
        )
        stage.replace(output)
    except Exception:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()
    try:
        prepare_runtime(args.output, manifest_path=args.manifest)
    except (
        ArtifactManifestError,
        ArtifactIntegrityError,
        RuntimeDownloadError,
        OSError,
        RuntimeError,
    ) as exc:
        print(f"runtime preparation failed: {exc}", file=sys.stderr)
        return 1
    print(f"pinned runtime prepared at {args.output.expanduser().absolute()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
