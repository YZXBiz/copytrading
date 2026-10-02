from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tarfile
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).parents[1]


def runtime_module():
    module_path = SCRIPTS_DIR / "prepare_runtime.py"
    if not module_path.is_file():
        pytest.fail("prepare_runtime.py does not implement the runtime contract")
    spec = importlib.util.spec_from_file_location("prepare_runtime", module_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_tar(path: Path, members: list[tuple[tarfile.TarInfo, bytes | None]]) -> None:
    with tarfile.open(path, "w:gz") as archive:
        for info, contents in members:
            if contents is None:
                archive.addfile(info)
            else:
                import io

                archive.addfile(info, io.BytesIO(contents))


def file_member(name: str, contents: bytes) -> tuple[tarfile.TarInfo, bytes]:
    info = tarfile.TarInfo(name)
    info.size = len(contents)
    return info, contents


def valid_artifact(**overrides: object) -> dict[str, object]:
    artifact: dict[str, object] = {
        "name": "cpython",
        "version": "3.14.7+20260924",
        "platform": "darwin-arm64",
        "url": "https://github.com/astral-sh/python-build-standalone/releases/download/20260924/cpython-3.14.7%2B20260924-aarch64-apple-darwin-install_only.tar.gz",
        "sha256": "a" * 64,
        "license": "PSF-2.0",
        "license_url": "https://docs.python.org/3/license.html",
        "source_url": "https://github.com/astral-sh/python-build-standalone/releases/tag/20260924",
        "filename": "cpython-3.14.7+20260924-aarch64-apple-darwin-install_only.tar.gz",
        "archive_root": "python",
    }
    artifact.update(overrides)
    return artifact


def write_manifest(path: Path, artifact: dict[str, object]) -> None:
    path.write_text(json.dumps({"schema_version": 1, "artifacts": [artifact]}))


def test_corrupt_artifact_is_never_extracted(tmp_path: Path) -> None:
    runtime = runtime_module()
    archive = tmp_path / "runtime.tar.gz"
    archive.write_bytes(b"changed bytes")
    destination = tmp_path / "unpacked"

    with pytest.raises(runtime.ArtifactIntegrityError):
        runtime.verify_and_extract(
            archive,
            expected_sha256="0" * 64,
            destination=destination,
        )

    assert not destination.exists()


def test_valid_artifact_is_extracted_under_selected_destination(tmp_path: Path) -> None:
    runtime = runtime_module()
    archive = tmp_path / "valid.tar.gz"
    write_tar(archive, [file_member("runtime/python3.14", b"native binary")])
    destination = tmp_path / "unpacked"

    runtime.verify_and_extract(
        archive,
        expected_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
        destination=destination,
    )

    assert (destination / "runtime/python3.14").read_bytes() == b"native binary"


def test_path_traversal_archive_is_rejected_without_writing_outside(tmp_path: Path) -> None:
    runtime = runtime_module()
    archive = tmp_path / "traversal.tar.gz"
    write_tar(archive, [file_member("../outside.txt", b"outside")])
    destination = tmp_path / "unpacked"

    with pytest.raises(runtime.ArtifactIntegrityError):
        runtime.verify_and_extract(
            archive,
            expected_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
            destination=destination,
        )

    assert not destination.exists()
    assert not (tmp_path / "outside.txt").exists()


def test_escaping_symlink_archive_is_rejected(tmp_path: Path) -> None:
    runtime = runtime_module()
    archive = tmp_path / "symlink.tar.gz"
    link = tarfile.TarInfo("runtime/link")
    link.type = tarfile.SYMTYPE
    link.linkname = "../../outside.txt"
    write_tar(archive, [(link, None)])
    destination = tmp_path / "unpacked"

    with pytest.raises(runtime.ArtifactIntegrityError):
        runtime.verify_and_extract(
            archive,
            expected_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
            destination=destination,
        )

    assert not destination.exists()
    assert not (tmp_path / "outside.txt").exists()


def test_manifest_rejects_unsupported_architecture(tmp_path: Path) -> None:
    runtime = runtime_module()
    manifest = tmp_path / "artifacts.json"
    write_manifest(manifest, valid_artifact(platform="darwin-x86_64"))

    with pytest.raises(runtime.ArtifactManifestError, match="unsupported platform"):
        runtime.load_artifacts(manifest)


def test_manifest_rejects_path_like_artifact_name(tmp_path: Path) -> None:
    runtime = runtime_module()
    manifest = tmp_path / "artifacts.json"
    write_manifest(manifest, valid_artifact(name="../outside"))

    with pytest.raises(runtime.ArtifactManifestError, match="safe single path component"):
        runtime.load_artifacts(manifest)


def test_manifest_rejects_missing_license_metadata(tmp_path: Path) -> None:
    runtime = runtime_module()
    manifest = tmp_path / "artifacts.json"
    artifact = valid_artifact()
    artifact.pop("license")
    write_manifest(manifest, artifact)

    with pytest.raises(runtime.ArtifactManifestError, match="license"):
        runtime.load_artifacts(manifest)


def test_native_manifest_records_exact_pins_and_license_sources() -> None:
    runtime = runtime_module()

    artifacts = {artifact.name: artifact for artifact in runtime.load_artifacts()}

    assert set(artifacts) == {"cpython"}
    assert artifacts["cpython"].version == "3.14.7+20260924"
    assert artifacts["cpython"].sha256 == (
        "d3da099bb2bdd57e2f5ff8496cb9827f7d92eee332b09f8dc93706dabfc51a96"
    )
    assert artifacts["cpython"].license == "PSF-2.0"
