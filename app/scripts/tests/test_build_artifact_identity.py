from __future__ import annotations

import hashlib
import importlib.util
import io
import sys
import tarfile
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("build_app", SCRIPTS / "build_app.py")
assert SPEC and SPEC.loader
build_app = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_app)


def _archive(path: Path, payload: bytes) -> str:
    with tarfile.open(path, "w:gz") as output:
        member = tarfile.TarInfo("python3.14")
        member.size = len(payload)
        member.mode = 0o755
        output.addfile(member, io.BytesIO(payload))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_restore_native_runtime_rechecks_archive_bytes(tmp_path: Path) -> None:
    cache = tmp_path / "cache"
    cache.mkdir()
    archive = cache / "cpython.tar.gz"
    digest = _archive(archive, b"pinned native bytes")
    manifest = {
        "artifacts": [
            {
                "name": "cpython",
                "version": "3.14.7",
                "sha256": digest,
                "filename": archive.name,
                "binary_path": "cpython/python3.14",
            }
        ]
    }
    build_app.restore_native_runtime(tmp_path / "runtime", manifest, cache)
    assert (tmp_path / "runtime/cpython/python3.14").read_bytes() == b"pinned native bytes"

    archive.write_bytes(archive.read_bytes() + b"tampered")
    with pytest.raises(ValueError, match="pinned digest"):
        build_app.restore_native_runtime(tmp_path / "second", manifest, cache)


def test_restore_native_runtime_rejects_path_like_artifact_name_before_extraction(
    tmp_path: Path,
) -> None:
    cache = tmp_path / "cache"
    cache.mkdir()
    archive = cache / "cpython.tar.gz"
    digest = _archive(archive, b"native bytes")
    manifest = {
        "artifacts": [
            {
                "name": "../escaped",
                "version": "1.0.4",
                "sha256": digest,
                "filename": archive.name,
                "binary_path": "../escaped/python3.14",
            }
        ]
    }
    runtime = tmp_path / "stage/runtime"
    with pytest.raises(ValueError, match="safe single path component"):
        build_app.restore_native_runtime(runtime, manifest, cache)
    assert not (tmp_path / "stage/escaped").exists()
    assert not runtime.exists()


def test_source_build_policy_accepts_only_locked_discord_protos_archive(tmp_path: Path) -> None:
    lock = build_app.ENGINE / "uv.lock"
    requirements = (
        "discord-protos==0.0.2 \\\n"
        "    --hash=sha256:23953a05f32beedb40b708ec4b457530a6196a49c8d75d337ae9282a2a41c997\n"
    )
    policy = build_app.source_build_policy(requirements, lock, build_app.BUILD_CONSTRAINTS)
    assert policy["discord-protos"]["version"] == "0.0.2"
    assert policy["discord-protos"]["sdist_sha256"] == (
        "23953a05f32beedb40b708ec4b457530a6196a49c8d75d337ae9282a2a41c997"
    )
    assert build_app.source_install_options(policy, build_app.BUILD_CONSTRAINTS) == (
        "--only-binary",
        ":all:",
        "--no-binary",
        "discord-protos",
        "--build-constraints",
        str(build_app.BUILD_CONSTRAINTS),
    )


@pytest.mark.parametrize("change", ["archive", "requirement", "new-source", "constraints"])
def test_source_build_policy_rejects_unapproved_source_input(tmp_path: Path, change: str) -> None:
    original = (build_app.ENGINE / "uv.lock").read_text()
    digest = "23953a05f32beedb40b708ec4b457530a6196a49c8d75d337ae9282a2a41c997"
    requirements = f"discord-protos==0.0.2 \\\n    --hash=sha256:{digest}\n"
    constraints = build_app.BUILD_CONSTRAINTS
    if change == "archive":
        original = original.replace(digest, "0" * 64, 1)
    elif change == "requirement":
        requirements = requirements.replace(digest, "0" * 64)
    elif change == "new-source":
        original += (
            '\n[[package]]\nname = "unexpected-source"\nversion = "1.0"\n'
            'sdist = { url = "https://example.invalid/source.tar.gz", '
            'hash = "sha256:' + "a" * 64 + '" }\n'
        )
        requirements += "unexpected-source==1.0 \\\n    --hash=sha256:" + "a" * 64 + "\n"
    else:
        constraints = tmp_path / "build-constraints.txt"
        constraints.write_text(
            build_app.BUILD_CONSTRAINTS.read_text().replace("wheel==0.48.0", "wheel>=0.48.0")
        )
    lock = tmp_path / "uv.lock"
    lock.write_text(original)
    with pytest.raises(ValueError, match=r"source build|build constraints"):
        build_app.source_build_policy(requirements, lock, constraints)


def test_dependency_inventory_records_installed_target_packages_only(tmp_path: Path) -> None:
    site = tmp_path / "site-packages"
    dist = site / "discord_protos-0.0.2.dist-info"
    dist.mkdir(parents=True)
    (dist / "METADATA").write_text("Name: discord-protos\nVersion: 0.0.2\n")
    requirements = (
        "discord-protos==0.0.2 \\\n    --hash=sha256:" + "a" * 64 + "\n"
        "httpx2-jsfetch==1.0 ; sys_platform == 'emscripten' \\\n    --hash=sha256:"
        + "b"
        * 64
        + "\n"
        "tzdata==2026.4 ; sys_platform == 'win32' \\\n    --hash=sha256:" + "c" * 64 + "\n"
    )
    expected = build_app.applicable_packages(requirements)
    assert expected == {"discord-protos": "0.0.2"}
    pip = site / "pip-26.2.1.dist-info"
    pip.mkdir()
    (pip / "METADATA").write_text("Name: pip\nVersion: 26.2.1\n")
    baseline = {"pip": "26.2.1"}
    assert build_app.installed_packages(site, expected, baseline) == expected

    (dist / "METADATA").write_text("Name: discord-protos\nVersion: 0.0.3\n")
    with pytest.raises(ValueError, match="unlocked installed Python package"):
        build_app.installed_packages(site, expected, baseline)


def test_dependency_inventory_rejects_missing_applicable_package_and_unknown_marker(
    tmp_path: Path,
) -> None:
    site = tmp_path / "site-packages"
    site.mkdir()
    with pytest.raises(ValueError, match="missing locked Python package"):
        build_app.installed_packages(site, {"discord-protos": "0.0.2"}, {})
    with pytest.raises(ValueError, match="unsupported Python dependency marker"):
        build_app.applicable_packages(
            "example==1.0 ; os_name == 'posix' \\\n  --hash=sha256:" + "a" * 64
        )


def test_console_scripts_are_removed_but_packages_stay(tmp_path: Path) -> None:
    site = tmp_path / "site-packages"
    (site / "bin").mkdir(parents=True)
    (site / "bin" / "uvicorn").write_text("#!/Users/someone/python3.14\n")
    (site / "httpx").mkdir()
    (site / "httpx" / "__init__.py").write_text("")
    record = site / "httpx-0.28.dist-info" / "RECORD"
    record.parent.mkdir()
    record.write_text(
        "httpx/__init__.py,sha256=abc,0\nbin/httpx,sha256=def,10\nhttpx-0.28.dist-info/RECORD,,\n"
    )
    build_app.remove_console_scripts(site)
    assert not (site / "bin").exists()
    assert (site / "httpx" / "__init__.py").is_file()
    assert record.read_text() == "httpx/__init__.py,sha256=abc,0\nhttpx-0.28.dist-info/RECORD,,\n"
    build_app.remove_console_scripts(site)
