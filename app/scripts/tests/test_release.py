from __future__ import annotations

import hashlib
import importlib.util
import json
import plistlib
import shutil
import stat
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("release", SCRIPTS / "release.py")
assert SPEC and SPEC.loader
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


def test_release_version_requires_preview_identity_and_matching_tag() -> None:
    assert release.validate_version("0.1.0-alpha.1", "v0.1.0-alpha.1") == (
        "0.1.0",
        "alpha",
    )
    with pytest.raises(release.ReleaseError, match="release version"):
        release.validate_version("0.1.0", "v0.1.0")
    with pytest.raises(release.ReleaseError, match="exactly match"):
        release.validate_version("0.1.0-alpha.1", "v0.1.0-alpha.2")
    with pytest.raises(release.ReleaseError, match="release version"):
        release.validate_version("0.1.0-alpha.01", "v0.1.0-alpha.01")


def test_release_core_version_must_match_app_and_engine(tmp_path: Path) -> None:
    app = tmp_path / "app/Resources"
    engine = tmp_path / "engine"
    app.mkdir(parents=True)
    engine.mkdir()
    with (app / "Info.plist").open("wb") as stream:
        plistlib.dump({"CFBundleShortVersionString": "0.1.0"}, stream)
    (engine / "pyproject.toml").write_text('[project]\nversion = "0.1.0"\n')

    assert release.validate_bundle_versions("0.1.0-alpha.1", root=tmp_path) == "0.1.0"

    (engine / "pyproject.toml").write_text('[project]\nversion = "0.1.1"\n')
    with pytest.raises(release.ReleaseError, match="engine version"):
        release.validate_bundle_versions("0.1.0-alpha.1", root=tmp_path)


def _git(root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments], cwd=root, check=True, text=True, capture_output=True
    )
    return result.stdout.strip()


def test_source_archive_uses_exact_commit_and_ignores_untracked_files(tmp_path: Path) -> None:
    _git(tmp_path, "init", "-q")
    _git(tmp_path, "config", "user.name", "Release Test")
    _git(tmp_path, "config", "user.email", "release-test@example.invalid")
    source = tmp_path / "tracked.txt"
    source.write_text("pinned source\n")
    _git(tmp_path, "add", "tracked.txt")
    _git(tmp_path, "commit", "-qm", "release source")
    commit = _git(tmp_path, "rev-parse", "HEAD")
    (tmp_path / "untracked-secret.txt").write_text("not in the source commit")

    archive = tmp_path / "release.tar.gz"
    digest = release.create_source_archive(tmp_path, commit, "0.1.0-alpha.1", archive)

    assert digest == hashlib.sha256(archive.read_bytes()).hexdigest()
    with tarfile.open(archive, "r:gz") as source_archive:
        files = {}
        for member in source_archive.getmembers():
            if member.isfile():
                source = source_archive.extractfile(member)
                assert source is not None
                files[member.name] = source.read()
    assert files == {"copytrading-v0.1.0-alpha.1/tracked.txt": b"pinned source\n"}


def test_release_commit_refuses_tracked_or_untracked_changes(tmp_path: Path) -> None:
    _git(tmp_path, "init", "-q")
    _git(tmp_path, "config", "user.name", "Release Test")
    _git(tmp_path, "config", "user.email", "release-test@example.invalid")
    tracked = tmp_path / "tracked.txt"
    tracked.write_text("clean\n")
    _git(tmp_path, "add", "tracked.txt")
    _git(tmp_path, "commit", "-qm", "clean source")
    commit, _ = release.resolve_source_commit(None, root=tmp_path)
    assert len(commit) == 40

    tracked.write_text("modified\n")
    with pytest.raises(release.ReleaseError, match="clean checkout"):
        release.resolve_source_commit(None, root=tmp_path)
    _git(tmp_path, "checkout", "--", "tracked.txt")
    (tmp_path / "untracked.txt").write_text("untracked\n")
    with pytest.raises(release.ReleaseError, match="clean checkout"):
        release.resolve_source_commit(None, root=tmp_path)


def _zip_info(name: str, mode: int = stat.S_IFREG | 0o644) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name)
    info.create_system = 3
    info.external_attr = mode << 16
    return info


def _valid_app_zip(
    path: Path, *, executable_mode: int = 0o755, include_licenses: bool = True
) -> None:
    app = release.APP_NAME
    runtime = release.RUNTIME.as_posix()
    commit = "1" * 40
    provenance = {
        "version": "0.1.0-alpha.1",
        "tag": "v0.1.0-alpha.1",
        "source": {"commit": commit},
    }
    info = {
        "CFBundleIdentifier": "dev.copytrading.app",
        "CFBundleShortVersionString": "0.1.0",
    }
    with zipfile.ZipFile(path, "w") as archive:
        for relative in (
            "Contents/MacOS/CopyTrading",
            f"{runtime}/cpython/python/bin/python3.14",
        ):
            archive.writestr(
                _zip_info(f"{app}/{relative}", stat.S_IFREG | executable_mode), b"executable"
            )
        archive.writestr(
            _zip_info(f"{app}/Contents/Resources/ReleaseProvenance.json"),
            json.dumps(provenance),
        )
        archive.writestr(_zip_info(f"{app}/Contents/Info.plist"), plistlib.dumps(info))
        if include_licenses:
            archive.writestr(
                _zip_info(f"{app}/Contents/Resources/THIRD_PARTY_NOTICES.md"),
                b"third-party notices",
            )
            archive.writestr(
                _zip_info(f"{app}/Contents/Resources/ThirdPartyLicenses/README.json"),
                b'{"components": []}',
            )
            archive.writestr(
                _zip_info(f"{app}/Contents/Resources/ThirdPartyLicenses/README.md"),
                b"license review notes",
            )
            archive.writestr(
                _zip_info(f"{app}/Contents/Resources/ThirdPartyLicenses/cpython/LICENSE.txt"),
                b"PSF-2.0",
            )


def test_app_zip_requires_provenance_and_executable_modes(tmp_path: Path) -> None:
    archive = tmp_path / "app.zip"
    _valid_app_zip(archive)

    release.inspect_app_zip(archive, "0.1.0-alpha.1", "v0.1.0-alpha.1", "1" * 40)

    _valid_app_zip(archive, executable_mode=0o644)
    with pytest.raises(release.ReleaseError, match="executable permission"):
        release.inspect_app_zip(archive, "0.1.0-alpha.1", "v0.1.0-alpha.1", "1" * 40)


def test_app_zip_requires_embedded_notices_and_python_license(tmp_path: Path) -> None:
    archive = tmp_path / "app.zip"
    _valid_app_zip(archive, include_licenses=False)

    with pytest.raises(release.ReleaseError, match="missing required paths"):
        release.inspect_app_zip(archive, "0.1.0-alpha.1", "v0.1.0-alpha.1", "1" * 40)


@pytest.mark.parametrize(
    "member,mode,payload",
    [
        ("CopyTrading.app/../../outside", stat.S_IFREG | 0o644, b"escape"),
        (
            "CopyTrading.app/Contents/Resources/Runtime/escape",
            stat.S_IFLNK | 0o777,
            b"../../../../outside",
        ),
    ],
)
def test_app_zip_rejects_traversal_and_escaping_symlinks(
    tmp_path: Path, member: str, mode: int, payload: bytes
) -> None:
    archive = tmp_path / "app.zip"
    _valid_app_zip(archive)
    with zipfile.ZipFile(archive, "a") as output:
        output.writestr(_zip_info(member, mode), payload)

    with pytest.raises(release.ReleaseError, match=r"unsafe ZIP member|escaping symlink"):
        release.inspect_app_zip(archive, "0.1.0-alpha.1", "v0.1.0-alpha.1", "1" * 40)


def test_checksum_manifest_rejects_tampered_or_unlisted_assets(tmp_path: Path) -> None:
    asset = tmp_path / "CopyTrading.zip"
    asset.write_bytes(b"first build")
    digest = hashlib.sha256(asset.read_bytes()).hexdigest()
    (tmp_path / "SHA256SUMS").write_text(f"{digest}  {asset.name}\n")
    release.verify_checksums(tmp_path)

    asset.write_bytes(b"changed after checksum")
    with pytest.raises(release.ReleaseError, match="checksum mismatch"):
        release.verify_checksums(tmp_path)

    asset.write_bytes(b"first build")
    (tmp_path / "extra.txt").write_text("unlisted")
    with pytest.raises(release.ReleaseError, match="cover every release asset"):
        release.verify_checksums(tmp_path)


def test_python_inventory_collects_declared_license_and_license_text(tmp_path: Path) -> None:
    site = tmp_path / "site-packages"
    distribution = site / "example_pkg-1.2.3.dist-info"
    license_directory = distribution / "licenses"
    license_directory.mkdir(parents=True)
    (distribution / "METADATA").write_text(
        "Metadata-Version: 2.4\nName: example_pkg\nVersion: 1.2.3\nLicense-Expression: MIT\n"
    )
    (license_directory / "LICENSE.txt").write_text("MIT notice\n")

    components, license_files, missing, missing_material = release.python_inventory(site)

    assert components[0]["purl"] == "pkg:pypi/example-pkg@1.2.3"
    assert components[0]["licenses"] == [{"expression": "MIT"}]
    assert license_files[0]["path"] == "python/example-pkg-1.2.3/licenses/LICENSE.txt"
    assert missing == []
    assert missing_material == []


def test_python_inventory_reports_missing_license_material(tmp_path: Path) -> None:
    site = tmp_path / "site-packages"
    distribution = site / "no_license-1.0.dist-info"
    distribution.mkdir(parents=True)
    (distribution / "METADATA").write_text(
        "Metadata-Version: 2.4\nName: no-license\nVersion: 1.0\nLicense-Expression: MIT\n"
    )

    components, license_files, missing, missing_material = release.python_inventory(site)

    assert components[0]["licenses"] == [{"expression": "MIT"}]
    assert license_files == []
    assert missing == []
    assert missing_material == ["no-license==1.0"]


def test_python_inventory_uses_supplied_text_only_for_the_checked_version(tmp_path: Path) -> None:
    site = tmp_path / "site-packages"
    for name, version in (("checked-pkg", "1.0"), ("bumped-pkg", "2.0")):
        distribution = site / f"{name.replace('-', '_')}-{version}.dist-info"
        distribution.mkdir(parents=True)
        (distribution / "METADATA").write_text(
            f"Metadata-Version: 2.4\nName: {name}\nVersion: {version}\nLicense-Expression: MIT\n"
        )
    supplied = tmp_path / "licenses"
    for checked in ("checked-pkg-1.0", "bumped-pkg-1.0"):
        (supplied / checked).mkdir(parents=True)
        (supplied / checked / "LICENSE").write_text("MIT notice from upstream\n")

    components, license_files, _, missing_material = release.python_inventory(site, supplied)

    assert [item["path"] for item in license_files] == ["python/checked-pkg-1.0/supplied/LICENSE"]
    assert missing_material == ["bumped-pkg==2.0"]
    checked = next(item for item in components if item["name"] == "checked-pkg")
    assert {
        "name": "copytrading:license-file",
        "value": "python/checked-pkg-1.0/supplied/LICENSE",
    } in checked["properties"]


def test_collect_licenses_embeds_available_runtime_text(tmp_path: Path) -> None:
    runtime = tmp_path / "CopyTrading.app" / release.RUNTIME
    cpython_license = runtime / "cpython/python/lib/python3.14/LICENSE.txt"
    cpython_license.parent.mkdir(parents=True)
    cpython_license.write_text("CPython license text\n")
    python_license = tmp_path / "package" / "LICENSE"
    python_license.parent.mkdir()
    python_license.write_text("package license text\n")
    destination = tmp_path / "CopyTrading.app/Contents/Resources/ThirdPartyLicenses"

    missing = release.collect_licenses(
        tmp_path / "CopyTrading.app",
        destination,
        [{"source": str(python_license), "path": "python/example-1.0/LICENSE"}],
        ["incomplete-package==1.0"],
    )

    assert (destination / "cpython/LICENSE.txt").read_text() == "CPython license text\n"
    assert (destination / "python/example-1.0/LICENSE").read_text() == "package license text\n"
    assert missing == ["incomplete-package==1.0"]
    metadata = json.loads((destination / "README.json").read_text())
    assert metadata["missing_material"] == ["incomplete-package==1.0"]
    assert "requires qualified legal review" in json.dumps(metadata)


def test_build_release_keeps_contents_path_relative_to_app_root(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = tmp_path / "checkout"
    root.mkdir()
    commit = "a" * 40
    inventory_checks: list[str] = []
    sealed_apps: list[str] = []
    packed_app: Path | None = None

    monkeypatch.setattr(release, "validate_host", lambda: None)
    monkeypatch.setattr(release, "validate_bundle_versions", lambda *_args, **_kwargs: "0.1.0")
    monkeypatch.setattr(
        release,
        "resolve_source_commit",
        lambda *_args, **_kwargs: (commit, "c" * 40),
    )

    def write_source_archive(_root: Path, _commit: str, _version: str, output: Path) -> str:
        output.write_bytes(b"exact app source")
        return hashlib.sha256(output.read_bytes()).hexdigest()

    monkeypatch.setattr(release, "create_source_archive", write_source_archive)

    def run(*arguments: str, **_kwargs: object) -> str:
        nonlocal packed_app
        if arguments[0] == "ditto" and arguments[1] == "-c":
            app = Path(arguments[-2])
            output = Path(arguments[-1])
            packed_app = app
            with zipfile.ZipFile(output, "w") as archive:
                for path in sorted(app.rglob("*")):
                    if path.is_symlink():
                        mode = stat.S_IFLNK | 0o777
                        payload = str(path.readlink()).encode()
                    elif path.is_file():
                        mode = stat.S_IFREG | stat.S_IMODE(path.stat().st_mode)
                        payload = path.read_bytes()
                    else:
                        continue
                    info = _zip_info(f"{app.name}/{path.relative_to(app).as_posix()}", mode)
                    archive.writestr(info, payload)
            return ""
        if arguments[0] == "ditto" and arguments[1] == "-x":
            assert packed_app is not None
            shutil.copytree(packed_app, Path(arguments[-1]) / packed_app.name, symlinks=True)
            return ""
        assert Path(arguments[1]).name == "build_app.py"
        app = Path(arguments[arguments.index("--app") + 1])
        contents = app / "Contents"
        runtime = app / release.RUNTIME
        runtime.mkdir(parents=True)
        info = {
            "CFBundleIdentifier": "dev.copytrading.app",
            "CFBundleExecutable": "CopyTrading",
            "CFBundleShortVersionString": "0.1.0",
        }
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump(info, stream)
        for binary in (
            contents / "MacOS/CopyTrading",
            runtime / "cpython/python/bin/python3.14",
        ):
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.write_bytes(b"native executable")
            binary.chmod(0o755)
        (runtime / "cpython/python/lib/python3.14/LICENSE.txt").parent.mkdir(parents=True)
        (runtime / "cpython/python/lib/python3.14/LICENSE.txt").write_text("CPython license\n")
        (runtime / "THIRD_PARTY_NOTICES.md").write_text("Runtime native notices\n")
        return ""

    def write_sbom(_app: Path, _version: str, _commit: str, output: Path):
        output.write_text("{}\n")
        return [], []

    def verify_inventory(app: Path) -> list[str]:
        contents = app / "Contents"
        inventory = contents / "Resources/Runtime/bundle-files.json"
        if not inventory.is_file():
            return [f"missing inventory at {inventory.relative_to(app)}"]
        if json.loads(inventory.read_text()) != release.bundle_inventory(contents):
            return ["bundle inventory does not match app Contents"]
        inventory_checks.append(inventory.relative_to(app).as_posix())
        return []

    def sign_preview(app: Path, *, ad_hoc: bool = False) -> None:
        assert ad_hoc
        assert (app / "Contents/Resources/ReleaseProvenance.json").is_file()
        assert (app / "Contents/Resources/ThirdPartyLicenses/README.json").is_file()
        contents = app / "Contents"
        inventory = contents / "Resources/Runtime/bundle-files.json"
        assert json.loads(inventory.read_text()) == release.bundle_inventory(contents)
        sealed_apps.append(app.name)

    monkeypatch.setattr(release, "_run", run)
    monkeypatch.setattr(release, "write_sbom", write_sbom)
    monkeypatch.setattr(release, "python_inventory", lambda _site: ([], [], [], []))
    monkeypatch.setattr(release, "verify", verify_inventory)
    monkeypatch.setattr(release, "sign_if_available", sign_preview)

    output = tmp_path / "release-assets"
    assets = release.build_release(
        version="0.1.0-alpha.1",
        tag="v0.1.0-alpha.1",
        commit=commit,
        runtime=tmp_path / "prepared-runtime",
        output=output,
        root=root,
    )

    assert assets == output
    assert sealed_apps == ["CopyTrading.app"]
    assert inventory_checks == [
        "Contents/Resources/Runtime/bundle-files.json",
        "Contents/Resources/Runtime/bundle-files.json",
    ]
    release.verify_checksums(assets)
