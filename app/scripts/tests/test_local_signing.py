from __future__ import annotations

import importlib.util
import json
import plistlib
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("local_signing", SCRIPTS / "local_signing.py")
assert SPEC and SPEC.loader
local_signing = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(local_signing)
VERIFY_SPEC = importlib.util.spec_from_file_location("verify_bundle", SCRIPTS / "verify_bundle.py")
assert VERIFY_SPEC and VERIFY_SPEC.loader
verify_bundle = importlib.util.module_from_spec(VERIFY_SPEC)
VERIFY_SPEC.loader.exec_module(verify_bundle)

_VALID = """
  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Installer: Someone (ABCDE12345)"
  2) 89ABCDEF0123456789ABCDEF0123456789ABCDEF "Apple Development: Owner (FGHIJ67890)"
     2 valid identities found
"""


def test_the_apple_development_identity_signs_local_builds():
    assert local_signing.apple_development_identity(_VALID) == (
        "89ABCDEF0123456789ABCDEF0123456789ABCDEF"
    )


def test_without_an_apple_development_identity_the_build_stays_ad_hoc():
    assert local_signing.apple_development_identity("     0 valid identities found\n") is None


def test_the_executable_is_signed_as_the_app_identifier():
    command = local_signing.sign_command(Path("/x/CopyTrading"), "HASH")
    assert command[:4] == ["/usr/bin/codesign", "--force", "--sign", "HASH"]
    assert command[command.index("--identifier") + 1] == "dev.copytrading.app"
    assert command[-1] == "/x/CopyTrading"


@pytest.fixture
def native_app(tmp_path: Path) -> Path:
    if sys.platform != "darwin":
        pytest.skip("Native bundle sealing requires macOS codesign")
    app = tmp_path / "CopyTrading.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Resources/Runtime").mkdir(parents=True)
    executable = contents / "MacOS/CopyTrading"
    shutil.copyfile("/usr/bin/true", executable)
    executable.chmod(0o755)
    (contents / "Info.plist").write_bytes(
        plistlib.dumps(
            {"CFBundleExecutable": "CopyTrading", "CFBundleIdentifier": "dev.copytrading.app"}
        )
    )
    (contents / "Resources/note.txt").write_text("assembled before signing")
    (contents / "Helpers").mkdir()
    helper = contents / "Helpers/copytrading"
    helper.write_text("#!/bin/sh\nexit 0\n")
    helper.chmod(0o755)
    return app


def _write_inventory(app: Path) -> None:
    contents = app / "Contents"
    (contents / "Resources/Runtime/bundle-files.json").write_text(
        json.dumps(verify_bundle.bundle_inventory(contents))
    )


def _signature_is_valid(app: Path) -> bool:
    return (
        subprocess.run(
            ["/usr/bin/codesign", "--verify", "--strict", str(app)],
            capture_output=True,
            check=False,
        ).returncode
        == 0
    )


def test_final_sealing_preserves_inventory_without_an_apple_identity(
    native_app: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(local_signing, "local_identity", lambda: None)
    _write_inventory(native_app)
    assert local_signing.sign_if_available(native_app) is None
    assert _signature_is_valid(native_app)
    assert verify_bundle.code_signature_problems(native_app) == []
    problems: list[str] = []
    verify_bundle._check_inventory(native_app / "Contents", problems)
    assert problems == []


@pytest.mark.parametrize(
    "relative", ["MacOS/CopyTrading", "Helpers/copytrading", "Resources/note.txt"]
)
def test_final_seal_rejects_tampering_even_after_inventory_is_rewritten(
    native_app: Path, monkeypatch: pytest.MonkeyPatch, relative: str
) -> None:
    monkeypatch.setattr(local_signing, "local_identity", lambda: None)
    _write_inventory(native_app)
    local_signing.sign_if_available(native_app)
    assert _signature_is_valid(native_app)
    target = native_app / "Contents" / relative
    data = bytearray(target.read_bytes())
    data[min(4096, len(data) - 1)] ^= 1
    target.write_bytes(data)
    _write_inventory(native_app)
    assert not _signature_is_valid(native_app)
    assert verify_bundle.code_signature_problems(native_app) == [
        "invalid app code signature or resource seal"
    ]


def test_preview_sealing_does_not_use_the_owner_identity(
    native_app: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    def unexpected_identity_lookup() -> None:
        pytest.fail("Explicit ad-hoc previews must not use the owner's signing identity")

    monkeypatch.setattr(local_signing, "local_identity", unexpected_identity_lookup)
    _write_inventory(native_app)
    assert local_signing.sign_if_available(native_app, ad_hoc=True) is None
    assert verify_bundle.code_signature_problems(native_app) == []


def test_packaging_preserves_the_helper_and_app_seals(
    native_app: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(local_signing, "local_identity", lambda: None)
    _write_inventory(native_app)
    local_signing.sign_if_available(native_app)
    archive = tmp_path / "app.zip"
    extracted = tmp_path / "extracted"
    subprocess.run(
        ["/usr/bin/ditto", "-c", "-k", "--keepParent", str(native_app), str(archive)],
        check=True,
    )
    with zipfile.ZipFile(archive) as contents:
        assert all(
            Path(entry.filename).parts[0] == native_app.name for entry in contents.infolist()
        )
    subprocess.run(["/usr/bin/ditto", "-x", "-k", str(archive), str(extracted)], check=True)
    restored = extracted / native_app.name
    assert verify_bundle.code_signature_problems(restored) == []
    problems: list[str] = []
    verify_bundle._check_inventory(restored / "Contents", problems)
    assert problems == []
