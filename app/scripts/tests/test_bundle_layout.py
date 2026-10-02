from __future__ import annotations

import importlib.util
import json
import plistlib
import stat
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "verify_bundle.py"
SPEC = importlib.util.spec_from_file_location("verify_bundle", SCRIPT)
assert SPEC and SPEC.loader
verify_bundle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify_bundle)
SCRIPTS = Path(__file__).resolve().parents[1]
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
BUILD_SPEC = importlib.util.spec_from_file_location(
    "build_app_under_test", SCRIPTS / "build_app.py"
)
assert BUILD_SPEC and BUILD_SPEC.loader
build_app = importlib.util.module_from_spec(BUILD_SPEC)
BUILD_SPEC.loader.exec_module(build_app)


@pytest.fixture
def app(tmp_path: Path) -> Path:
    bundle = tmp_path / "CopyTrading.app"
    macos = bundle / "Contents" / "MacOS"
    runtime = bundle / "Contents" / "Resources" / "Runtime"
    localization_resources = (
        bundle / "Contents/Resources/CopyTrading_AppLocalizationCore.bundle/Contents/Resources"
    )
    engine = bundle / "Contents" / "Resources" / "Engine" / "src" / "copytrading_engine"
    contracts = bundle / "Contents" / "Resources" / "Contracts"
    for directory in (macos, runtime, engine, contracts):
        directory.mkdir(parents=True, exist_ok=True)
    for language in ("en", "zh-Hans"):
        catalog = localization_resources / f"{language}.lproj/Localizable.strings"
        catalog.parent.mkdir(parents=True, exist_ok=True)
        catalog.write_text('"Language" = "Language";\n')
    with (bundle / "Contents" / "Info.plist").open("wb") as stream:
        plistlib.dump(
            {
                "CFBundleExecutable": "CopyTrading",
                "CFBundleIdentifier": "dev.copytrading.app",
            },
            stream,
        )
    (macos / "CopyTrading").write_bytes(b"Mach-O arm64\n")
    (macos / "CopyTrading").chmod(0o755)
    helpers = bundle / "Contents" / "Helpers"
    helpers.mkdir()
    (helpers / "copytrading").write_bytes(
        b'#!/bin/sh\nexec python3.14 -m copytrading_engine.control "$@"\n'
    )
    (helpers / "copytrading").chmod(0o755)
    artifacts = [
        {
            "name": "cpython",
            "version": "3.14.7+20260924",
            "platform": "darwin-arm64",
            "sha256": "a" * 64,
            "binary_path": "cpython/python/bin/python3.14",
        }
    ]
    (runtime / "artifacts.json").write_text(
        json.dumps({"schema_version": 1, "artifacts": artifacts})
    )
    (runtime / "runtime.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "artifacts": [
                    {k: item[k] for k in ("name", "version", "sha256")} for item in artifacts
                ],
            }
        )
    )
    (runtime / "THIRD_PARTY_NOTICES.md").write_text("license and source")
    (runtime / "python-dependencies.json").write_text(
        json.dumps({"lock_sha256": "c" * 64, "packages": {"pydantic": "2.12.5"}})
    )
    (contracts / "submit-self-test-request.json").write_text("{}")
    (engine / "__main__.py").write_text("pass")
    python = runtime / "cpython" / "python" / "bin" / "python3.14"
    python.parent.mkdir(parents=True)
    python.write_bytes(b"Mach-O arm64\n")
    python.chmod(0o755)
    site = runtime / "cpython" / "python" / "lib" / "python3.14" / "site-packages"
    site.mkdir(parents=True)
    (site / "pydantic").mkdir()
    (site / "pydantic" / "__init__.py").write_text("pass\n")
    dist = site / "pydantic-2.12.5.dist-info"
    dist.mkdir()
    (dist / "METADATA").write_text("Metadata-Version: 2.4\nName: pydantic\nVersion: 2.12.5\n")
    (dist / "RECORD").write_text("pydantic/__init__.py,,5\n")
    (runtime / "cpython/python/lib/python3.14/os.py").write_text("pass\n")
    (runtime / "bundle-files.json").write_text(
        json.dumps(verify_bundle.bundle_inventory(bundle / "Contents"))
    )
    return bundle


def test_complete_layout_passes(app: Path) -> None:
    assert verify_bundle.verify(app, inspect_macho=False) == []


def test_agent_command_must_be_an_executable_script(app: Path) -> None:
    command = app / "Contents/Helpers/copytrading"
    command.chmod(0o644)
    assert "agent command is not an executable shell script" in verify_bundle.verify(
        app, inspect_macho=False
    )
    command.unlink()
    assert any(
        "Helpers/copytrading" in problem
        for problem in verify_bundle.verify(app, inspect_macho=False)
    )


def test_missing_resource_fails(app: Path) -> None:
    (app / "Contents/Resources/Contracts/submit-self-test-request.json").unlink()
    assert any("Contracts" in problem for problem in verify_bundle.verify(app, inspect_macho=False))


def test_missing_localization_catalog_fails(app: Path) -> None:
    catalog = (
        app
        / "Contents/Resources/CopyTrading_AppLocalizationCore.bundle/Contents/Resources"
        / "zh-Hans.lproj/Localizable.strings"
    )
    catalog.unlink()
    assert any(
        "zh-Hans" in problem and "Localizable.strings" in problem
        for problem in verify_bundle.verify(app, inspect_macho=False)
    )


def test_packager_copies_localization_bundle(tmp_path: Path) -> None:
    bin_dir = tmp_path / "swift-products"
    resources = tmp_path / "Contents" / "Resources"
    source = bin_dir / "CopyTrading_AppLocalizationCore.bundle/Contents/Resources"
    resources.mkdir(parents=True)
    for language in ("en", "zh-Hans"):
        catalog = source / f"{language}.lproj/Localizable.strings"
        catalog.parent.mkdir(parents=True, exist_ok=True)
        catalog.write_text('"Language" = "Language";\n')

    destination = build_app.copy_localization_bundle(bin_dir, resources)

    assert destination == resources / "CopyTrading_AppLocalizationCore.bundle"
    assert (destination / "Contents/Resources/en.lproj/Localizable.strings").is_file()
    assert (destination / "Contents/Resources/zh-Hans.lproj/Localizable.strings").is_file()


def test_mismatched_artifact_identity_fails(app: Path) -> None:
    runtime = app / "Contents/Resources/Runtime"
    identity = json.loads((runtime / "runtime.json").read_text())
    identity["artifacts"][0]["sha256"] = "d" * 64
    (runtime / "runtime.json").write_text(json.dumps(identity))
    assert any("identity" in problem for problem in verify_bundle.verify(app, inspect_macho=False))


def test_developer_path_and_launch_tool_dependency_fail(app: Path) -> None:
    executable = app / "Contents/MacOS/CopyTrading"
    executable.write_bytes(b"/Users/someone/project /opt/homebrew/bin/uv")
    problems = verify_bundle.verify(app, inspect_macho=False)
    assert any("developer path" in problem for problem in problems)
    assert any("developer tool" in problem for problem in problems)


def test_debug_authentication_bypass_fails(app: Path) -> None:
    executable = app / "Contents/MacOS/CopyTrading"
    executable.write_bytes(b"COPYTRADING_UI_TEST_UNLOCK")
    problems = verify_bundle.verify(app, inspect_macho=False)
    assert "debug-only authentication bypass in executable" in problems


def test_world_readable_secret_fails(app: Path) -> None:
    key = app / "Contents/Resources/Runtime/account.key"
    key.write_text("private")
    key.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
    assert any("secret" in problem for problem in verify_bundle.verify(app, inspect_macho=False))


def test_unpinned_dependency_fails(app: Path) -> None:
    metadata = app / "Contents/Resources/Runtime/python-dependencies.json"
    metadata.write_text('{"lock_sha256":"x","packages":{"pydantic":">=2"}}')
    assert any("pin" in problem for problem in verify_bundle.verify(app, inspect_macho=False))


def test_wrong_native_architecture_fails(app: Path) -> None:
    assert any("architecture mismatch" in problem for problem in verify_bundle.verify(app))


def test_escaping_runtime_link_fails(app: Path, tmp_path: Path) -> None:
    (app / "Contents/Resources/Runtime/escape").symlink_to(tmp_path)
    assert any(
        "escaping symlink" in problem for problem in verify_bundle.verify(app, inspect_macho=False)
    )


def test_missing_locked_distribution_fails(app: Path) -> None:
    metadata = app / "Contents/Resources/Runtime/python-dependencies.json"
    record = json.loads(metadata.read_text())
    record["packages"]["requests"] = "2.34.2"
    metadata.write_text(json.dumps(record))
    assert any(
        "locked package" in problem for problem in verify_bundle.verify(app, inspect_macho=False)
    )


def test_missing_standard_library_file_fails(app: Path) -> None:
    (app / "Contents/Resources/Runtime/cpython/python/lib/python3.14/os.py").unlink()
    assert any(
        "standard library" in problem for problem in verify_bundle.verify(app, inspect_macho=False)
    )


def test_native_extension_architecture_fails(app: Path) -> None:
    extension = (
        app
        / "Contents/Resources/Runtime/cpython/python/lib/python3.14/site-packages"
        / "pydantic/native.so"
    )
    extension.write_bytes(b"x86_64 binary")
    assert any(
        "native.so" in problem and "architecture" in problem
        for problem in verify_bundle.verify(app)
    )


@pytest.mark.parametrize(
    "relative",
    [
        "Engine/src/copytrading_engine/__main__.py",
        "Runtime/cpython/python/bin/pip3.14",
        "Runtime/artifacts.json",
    ],
)
def test_launch_source_developer_reference_fails(app: Path, relative: str) -> None:
    path = app / "Contents/Resources" / relative
    path.write_text("/Users/someone/Files/private /opt/homebrew/bin/uv\n")
    problems = verify_bundle.verify(app, inspect_macho=False)
    assert any("developer path" in problem and path.name in problem for problem in problems)
    assert any("developer tool" in problem and path.name in problem for problem in problems)


def test_script_shebang_naming_a_developer_path_fails(app: Path) -> None:
    site = app / "Contents/Resources/Runtime/cpython/python/lib/python3.14/site-packages"
    script = site / "bin/httpx"
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text("#!/Users/someone/build/python3.14\nimport httpx\n")
    problems = verify_bundle.verify(app, inspect_macho=False)
    assert any("developer path" in problem and "httpx" in problem for problem in problems)


def test_replaced_native_binary_fails_integrity(app: Path) -> None:
    python = app / "Contents/Resources/Runtime/cpython/python/bin/python3.14"
    python.write_bytes(b"different Mach-O arm64\n")
    assert any(
        "bundle file digest" in problem
        for problem in verify_bundle.verify(app, inspect_macho=False)
    )
