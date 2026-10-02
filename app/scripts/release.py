"""Build and verify an unsigned macOS ARM64 developer-preview release."""

from __future__ import annotations

import argparse
import gzip
import json
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import tomllib
import uuid
import zipfile
from email.message import Message
from email.parser import Parser
from pathlib import Path, PurePosixPath
from urllib.parse import quote

from local_signing import sign_if_available
from verify_bundle import bundle_inventory, sha256, verify

ROOT = Path(__file__).resolve().parents[2]
APP_NAME = "CopyTrading.app"
APP_EXECUTABLE = "Contents/MacOS/CopyTrading"
RUNTIME = Path("Contents/Resources/Runtime")
# License texts for distributions that declare a license but ship no file, one directory per
# `<normalized-name>-<version>` so a version bump is reported again until it is checked.
SUPPLIED_LICENSES = ROOT / "docs/release-materials/licenses"
_VERSION = re.compile(
    r"(?P<core>(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))"
    r"-(?P<channel>alpha|beta|rc)\.(?:0|[1-9][0-9]*)\Z"
)
_HEX_COMMIT = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
_LICENSE_PREFIXES = ("license", "licence", "copying", "notice")


class ReleaseError(ValueError):
    """A release input or artifact failed a release invariant."""


def _run(*arguments: str, cwd: Path = ROOT, capture: bool = False) -> str:
    result = subprocess.run(
        arguments,
        cwd=cwd,
        check=True,
        text=True,
        capture_output=capture,
    )
    return result.stdout.strip() if capture else ""


def _write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def validate_version(version: str, tag: str) -> tuple[str, str]:
    """Require an explicit developer-preview SemVer and its exact v-prefixed tag."""
    match = _VERSION.fullmatch(version)
    if match is None:
        raise ReleaseError("release version must be MAJOR.MINOR.PATCH-alpha.N, beta.N, or rc.N")
    if tag != f"v{version}":
        raise ReleaseError(f"release tag must exactly match the version: v{version}")
    return match.group("core"), match.group("channel")


def validate_bundle_versions(version: str, *, root: Path = ROOT) -> str:
    """Require the preview's core version to match the app and engine metadata."""
    match = _VERSION.fullmatch(version)
    if match is None:
        raise ReleaseError("invalid developer-preview version")
    info_path = root / "app/Resources/Info.plist"
    try:
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
        engine = tomllib.loads((root / "engine/pyproject.toml").read_text(encoding="utf-8"))
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise ReleaseError(f"cannot read release version metadata: {error}") from error
    core = match.group("core")
    app_version = info.get("CFBundleShortVersionString")
    engine_version = engine.get("project", {}).get("version")
    if app_version != core:
        raise ReleaseError(f"app bundle version {app_version!r} does not match {core}")
    if engine_version != core:
        raise ReleaseError(f"engine version {engine_version!r} does not match {core}")
    return core


def validate_host() -> None:
    """Fail closed unless release packaging runs on native Apple Silicon macOS 26+."""
    if sys.platform != "darwin" or platform.machine() not in {"arm64", "aarch64"}:
        raise ReleaseError("developer-preview releases must be built on native Apple Silicon macOS")
    match = re.match(r"([0-9]+)\.([0-9]+)", platform.mac_ver()[0])
    if match is None or tuple(map(int, match.groups())) < (26, 0):
        raise ReleaseError("developer-preview releases require macOS 26 or later")


def resolve_source_commit(commit: str | None, *, root: Path = ROOT) -> tuple[str, str]:
    """Bind a release to a clean checkout and return its commit and tree IDs."""
    head = _run("git", "rev-parse", "HEAD", cwd=root, capture=True)
    if commit is not None and commit != head:
        raise ReleaseError(f"requested commit {commit} does not match checked out HEAD {head}")
    if _HEX_COMMIT.fullmatch(head) is None:
        raise ReleaseError("Git returned an unsupported source commit ID")
    dirty = _run("git", "status", "--porcelain", "--untracked-files=all", cwd=root, capture=True)
    if dirty:
        raise ReleaseError("release builds require a clean checkout")
    tree = _run("git", "rev-parse", f"{head}^{{tree}}", cwd=root, capture=True)
    return head, tree


def create_source_archive(root: Path, commit: str, version: str, output: Path) -> str:
    """Create a gzip source archive from tracked files at one exact Git commit."""
    output.parent.mkdir(parents=True, exist_ok=True)
    prefix = f"copytrading-v{version}/"
    with tempfile.NamedTemporaryFile(prefix="copytrading-source-", suffix=".tar") as raw:
        _run(
            "git",
            "archive",
            "--format=tar",
            f"--prefix={prefix}",
            f"--output={raw.name}",
            commit,
            cwd=root,
        )
        raw.seek(0)
        with output.open("wb") as destination:
            with gzip.GzipFile(
                filename="",
                fileobj=destination,
                mode="wb",
                mtime=0,
                compresslevel=9,
            ) as compressed:
                shutil.copyfileobj(raw, compressed)
    return sha256(output)


def _normalized_name(value: str) -> str:
    return re.sub(r"[-_.]+", "-", value).lower()


def _metadata_license(metadata: Message) -> tuple[list[dict[str, object]], str]:
    expression = metadata.get("License-Expression")
    if expression:
        return ([{"expression": expression}], expression)
    declared = metadata.get("License", "").strip()
    classifiers = [
        item.removeprefix("License :: ")
        for item in metadata.get_all("Classifier", [])
        if item.startswith("License :: ")
    ]
    label = declared or "; ".join(classifiers)
    if not label:
        return [], "Not declared in distribution metadata"
    return ([{"license": {"name": label}}], label)


def _license_paths(distribution: Path) -> list[Path]:
    matches = []
    for path in sorted(distribution.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        relative_parts = path.relative_to(distribution).parts
        name = path.name.lower()
        in_license_dir = any(
            part.lower() in {"license", "licenses"} for part in relative_parts[:-1]
        )
        if in_license_dir or name.startswith(_LICENSE_PREFIXES):
            matches.append(path)
    return matches


def python_inventory(
    site_packages: Path,
    supplied_licenses: Path = SUPPLIED_LICENSES,
) -> tuple[list[dict], list[dict[str, str]], list[str], list[str]]:
    """Read every installed distribution, declared license, and available text file."""
    components: list[dict] = []
    license_files: list[dict[str, str]] = []
    missing_metadata: list[str] = []
    missing_license_material: list[str] = []
    seen: set[str] = set()
    for distribution in sorted(site_packages.glob("*.dist-info")):
        metadata_path = distribution / "METADATA"
        try:
            metadata = Parser().parsestr(
                metadata_path.read_text(encoding="utf-8"), headersonly=True
            )
            name = metadata.get("Name", "").strip()
            version = metadata.get("Version", "").strip()
        except OSError as error:
            raise ReleaseError(
                f"cannot read Python distribution metadata at {metadata_path}"
            ) from error
        normalized = _normalized_name(name)
        if not normalized or not version or normalized in seen:
            raise ReleaseError(
                f"invalid or duplicate bundled Python distribution: {distribution.name}"
            )
        seen.add(normalized)
        license_entries, license_label = _metadata_license(metadata)
        if not license_entries:
            missing_metadata.append(f"{name}=={version}")
        component_ref = f"pkg:pypi/{quote(normalized, safe='-._~')}@{quote(version, safe='-._~')}"
        files_for_component: list[str] = []
        for path in _license_paths(distribution):
            relative = path.relative_to(distribution).as_posix()
            asset_path = f"python/{normalized}-{version}/{relative}"
            files_for_component.append(asset_path)
            license_files.append({"source": str(path), "path": asset_path})
        supplied = supplied_licenses / f"{normalized}-{version}"
        if not files_for_component and supplied.is_dir():
            for path in sorted(item for item in supplied.iterdir() if item.is_file()):
                asset_path = f"python/{normalized}-{version}/supplied/{path.name}"
                files_for_component.append(asset_path)
                license_files.append({"source": str(path), "path": asset_path})
        if not files_for_component:
            missing_license_material.append(f"{name}=={version}")
        component = {
            "type": "library",
            "bom-ref": component_ref,
            "name": name,
            "version": version,
            "purl": component_ref,
            "properties": [
                {"name": "copytrading:license-metadata", "value": license_label},
                *(
                    {"name": "copytrading:license-file", "value": path}
                    for path in files_for_component
                ),
            ],
        }
        if license_entries:
            component["licenses"] = license_entries
        components.append(component)
    return components, license_files, missing_metadata, missing_license_material


def collect_licenses(
    app: Path,
    destination: Path,
    python_files: list[dict[str, str]],
    missing_python_material: list[str],
) -> list[str]:
    """Collect the CPython and Python distribution license texts from the built runtime."""
    problems: list[str] = []
    destination.mkdir(parents=True, exist_ok=False)
    runtime = app / RUNTIME
    cpython_license = runtime / "cpython/python/lib/python3.14/LICENSE.txt"
    if cpython_license.is_file():
        cpython_target = destination / "cpython" / "LICENSE.txt"
        cpython_target.parent.mkdir(parents=True)
        shutil.copyfile(cpython_license, cpython_target)
    else:
        problems.append("CPython license text missing from bundled runtime")
    problems.extend(missing_python_material)
    for entry in python_files:
        source_path = Path(entry["source"])
        target = destination / entry["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_path, target)
    _write_json(
        destination / "README.json",
        {
            "schema_version": 1,
            "collection_method": "Copied license-named files from the exact built runtime.",
            "review_status": "requires qualified legal review",
            "limitations": [
                "Package metadata can be absent, incomplete, or ambiguous.",
                "This file collection does not determine whether all notice "
                "obligations are satisfied.",
            ],
            "missing_material": problems,
        },
    )
    (destination / "README.md").write_text(
        "# Third-party license materials\n\n"
        "These files are collected from the exact packaged runtime. "
        "They are included in the app at `Contents/Resources/ThirdPartyLicenses`.\n\n"
        "## Review status\n\n"
        "License collection is evidence for review. It does not establish that all notice "
        "or other redistribution obligations have been met. "
        "Qualified legal review remains required.\n",
        encoding="utf-8",
    )
    return problems


def _native_component(artifact: dict, runtime: Path) -> dict:
    name = artifact["name"]
    version = artifact["version"]
    binary_path = runtime / artifact["binary_path"]
    component_ref = f"pkg:generic/{quote(name, safe='-._~')}@{quote(version, safe='-._~')}"
    license_id = artifact.get("license")
    component = {
        "type": "library",
        "bom-ref": component_ref,
        "name": "CPython standalone" if name == "cpython" else name,
        "version": version,
        "purl": component_ref,
        "hashes": [{"alg": "SHA-256", "content": sha256(binary_path)}],
        "externalReferences": [
            {"type": "distribution", "url": artifact["url"]},
            {"type": "vcs", "url": artifact["source_url"]},
        ],
        "properties": [
            {"name": "copytrading:upstream-artifact-filename", "value": artifact["filename"]},
            {"name": "copytrading:upstream-artifact-sha256", "value": artifact["sha256"]},
        ],
    }
    if license_id:
        component["licenses"] = [{"expression": license_id}]
    return component


def write_sbom(app: Path, version: str, commit: str, output: Path) -> tuple[list[str], list[str]]:
    """Write a CycloneDX 1.6 inventory for the actual app runtime."""
    runtime = app / RUNTIME
    artifacts = json.loads((runtime / "artifacts.json").read_text(encoding="utf-8"))["artifacts"]

    site_packages = runtime / "cpython/python/lib/python3.14/site-packages"
    (
        python_components,
        _license_files,
        missing_metadata,
        missing_license_material,
    ) = python_inventory(site_packages)
    native_components = [_native_component(item, runtime) for item in artifacts]
    components = sorted([*native_components, *python_components], key=lambda item: item["bom-ref"])
    app_ref = f"pkg:generic/copytrading@{quote(version, safe='-._~')}"
    dependency_refs = sorted(component["bom-ref"] for component in components)
    sbom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, f'{commit}:{version}')}",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": app_ref,
                "name": "CopyTrading",
                "version": version,
                "purl": app_ref,
            },
            "properties": [
                {"name": "copytrading:source-commit", "value": commit},
                {"name": "copytrading:architecture", "value": "arm64"},
                {"name": "copytrading:minimum-macos", "value": "26.0"},
            ],
        },
        "components": components,
        "dependencies": [{"ref": app_ref, "dependsOn": dependency_refs}],
    }
    _write_json(output, sbom)
    return missing_metadata, missing_license_material


def write_notices(
    app: Path,
    version: str,
    python_rows: list[dict],
    output: Path,
) -> None:
    """Combine the bundled native notices with observed Python package metadata."""
    runtime_notices = (app / RUNTIME / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
    rows = []
    for component in python_rows:
        name = component["name"]
        version_value = component["version"]
        license_value = next(
            (
                item["value"]
                for item in component.get("properties", [])
                if item["name"] == "copytrading:license-metadata"
            ),
            "Not declared in distribution metadata",
        )
        text_paths = [
            item["value"]
            for item in component.get("properties", [])
            if item["name"] == "copytrading:license-file"
        ]
        text_value = "; ".join(text_paths) if text_paths else "Not collected"
        safe_license = license_value.replace("|", "\\|").replace("\n", " ")
        rows.append(f"| `{name}=={version_value}` | {safe_license} | {text_value} |")
    table = "\n".join(rows) if rows else "| _No installed Python distributions found_ | | |"
    output.write_text(
        runtime_notices.rstrip()
        + f"\n\n## Bundled Python distributions in {version}\n\n"
        + "| Package | License metadata | Collected text |\n| --- | --- | --- |\n"
        + table
        + "\n\nThe package license fields above are copied from installed distribution metadata. "
        + "The license archive contains only license-named files present in the built runtime. "
        + "Missing or ambiguous metadata and redistribution obligations require "
        "qualified review.\n",
        encoding="utf-8",
    )


def _zip_member_target_is_internal(name: str, target: str, root_name: str) -> bool:
    if not target or target.startswith("/") or "\\" in target:
        return False
    resolved: list[str] = []
    for part in [*PurePosixPath(name).parent.parts, *PurePosixPath(target).parts]:
        if part in {"", "."}:
            continue
        if part == "..":
            if not resolved:
                return False
            resolved.pop()
        else:
            resolved.append(part)
    return bool(resolved) and resolved[0] == root_name


def inspect_app_zip(archive: Path, version: str, tag: str, commit: str) -> None:
    """Require provenance, embedded license materials, and executable modes."""
    root_name = APP_NAME
    required = {
        f"{APP_NAME}/{APP_EXECUTABLE}",
        f"{APP_NAME}/{RUNTIME.as_posix()}/cpython/python/bin/python3.14",
        f"{APP_NAME}/Contents/Resources/ReleaseProvenance.json",
        f"{APP_NAME}/Contents/Resources/THIRD_PARTY_NOTICES.md",
        f"{APP_NAME}/Contents/Resources/ThirdPartyLicenses/README.json",
        f"{APP_NAME}/Contents/Resources/ThirdPartyLicenses/README.md",
        f"{APP_NAME}/Contents/Resources/ThirdPartyLicenses/cpython/LICENSE.txt",
    }
    executable_members = {
        f"{APP_NAME}/{APP_EXECUTABLE}",
        f"{APP_NAME}/{RUNTIME.as_posix()}/cpython/python/bin/python3.14",
    }
    seen: set[str] = set()
    found: set[str] = set()
    try:
        with zipfile.ZipFile(archive) as source:
            for entry in source.infolist():
                raw_name = entry.filename
                if "\\" in raw_name:
                    raise ReleaseError(f"ZIP member uses a non-POSIX path: {raw_name}")
                member = PurePosixPath(raw_name)
                normalized = member.as_posix().rstrip("/")
                if not normalized or member.is_absolute() or ".." in member.parts:
                    raise ReleaseError(f"unsafe ZIP member path: {raw_name}")
                if normalized in seen:
                    raise ReleaseError(f"duplicate ZIP member path: {normalized}")
                seen.add(normalized)
                if member.parts[0] != root_name:
                    raise ReleaseError(f"unexpected ZIP root entry: {raw_name}")
                mode = entry.external_attr >> 16
                if stat.S_ISLNK(mode):
                    try:
                        target = source.read(entry).decode("utf-8", errors="strict")
                    except UnicodeDecodeError as error:
                        raise ReleaseError(
                            f"invalid symlink target in ZIP: {normalized}"
                        ) from error
                    if not _zip_member_target_is_internal(normalized, target, root_name):
                        raise ReleaseError(f"escaping symlink in ZIP: {normalized}")
                if normalized in executable_members:
                    if not (mode & stat.S_IXUSR):
                        raise ReleaseError(f"ZIP lost executable permission: {normalized}")
                    found.add(normalized)
                if normalized == f"{APP_NAME}/Contents/Resources/ReleaseProvenance.json":
                    try:
                        provenance = json.loads(source.read(entry))
                    except (UnicodeDecodeError, ValueError) as error:
                        raise ReleaseError("app ZIP has invalid release provenance") from error
                    if (
                        not isinstance(provenance, dict)
                        or not isinstance(provenance.get("source"), dict)
                        or provenance.get("version") != version
                        or provenance.get("tag") != tag
                        or provenance.get("source", {}).get("commit") != commit
                    ):
                        raise ReleaseError("app ZIP provenance does not match the release identity")
                if normalized == f"{APP_NAME}/Contents/Info.plist":
                    try:
                        info = plistlib.loads(source.read(entry))
                    except (ValueError, plistlib.InvalidFileException) as error:
                        raise ReleaseError("app ZIP has an invalid Info.plist") from error
                    version_match = _VERSION.fullmatch(version)
                    if (
                        version_match is None
                        or not isinstance(info, dict)
                        or info.get("CFBundleIdentifier") != "dev.copytrading.app"
                        or info.get("CFBundleShortVersionString") != version_match.group("core")
                    ):
                        raise ReleaseError("app ZIP Info.plist does not match the release identity")
            missing = required - seen
            if missing:
                raise ReleaseError(
                    f"app ZIP is missing required paths: {', '.join(sorted(missing))}"
                )
            if found != executable_members:
                raise ReleaseError("app ZIP is missing one or more executable mode bits")
    except (OSError, zipfile.BadZipFile) as error:
        raise ReleaseError(f"cannot inspect app ZIP: {error}") from error


def extract_and_verify_app_zip(
    archive: Path, destination: Path, version: str, tag: str, commit: str
) -> Path:
    """Validate paths before using ditto, then verify the extracted app bundle."""
    inspect_app_zip(archive, version, tag, commit)
    if destination.exists():
        raise ReleaseError("app extraction destination must not already exist")
    destination.mkdir(parents=True)
    _run("ditto", "-x", "-k", str(archive), str(destination))
    app = destination / APP_NAME
    provenance_path = app / "Contents/Resources/ReleaseProvenance.json"
    try:
        provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ReleaseError("extracted app has invalid release provenance") from error
    if (
        not isinstance(provenance, dict)
        or not isinstance(provenance.get("source"), dict)
        or provenance.get("version") != version
        or provenance.get("tag") != tag
        or provenance.get("source", {}).get("commit") != commit
    ):
        raise ReleaseError("extracted app provenance does not match the release identity")
    problems = verify(app)
    if problems:
        raise ReleaseError("extracted app bundle verification failed: " + "; ".join(problems))
    return app


def _create_license_zip(source: Path, output: Path) -> None:
    """Write a stable license archive with Unix modes and sorted member names."""
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(source.rglob("*")):
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(source).as_posix()
            info = zipfile.ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | (path.stat().st_mode & 0o777)) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())


def _write_checksums(directory: Path) -> None:
    lines = []
    for path in sorted(directory.iterdir(), key=lambda item: item.name):
        if path.is_file() and path.name != "SHA256SUMS":
            lines.append(f"{sha256(path)}  {path.name}")
    (directory / "SHA256SUMS").write_text("\n".join(lines) + "\n", encoding="utf-8")


def verify_checksums(directory: Path) -> None:
    """Verify every listed SHA-256 and reject paths that escape the asset directory."""
    checksum_path = directory / "SHA256SUMS"
    try:
        rows = checksum_path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise ReleaseError("missing SHA256SUMS") from error
    if not rows:
        raise ReleaseError("SHA256SUMS is empty")
    seen: set[str] = set()
    for row in rows:
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._+-]+)", row)
        if match is None:
            raise ReleaseError(f"invalid checksum row: {row}")
        expected, name = match.groups()
        if name == "SHA256SUMS" or name in seen:
            raise ReleaseError(f"invalid or duplicate checksum entry: {name}")
        seen.add(name)
        target = directory / name
        if not target.is_file() or sha256(target) != expected:
            raise ReleaseError(f"checksum mismatch or missing asset: {name}")
    actual = {
        path.name for path in directory.iterdir() if path.is_file() and path.name != "SHA256SUMS"
    }
    if seen != actual:
        raise ReleaseError("SHA256SUMS does not cover every release asset")


def _asset_record(directory: Path, name: str, media_type: str) -> dict[str, str | int]:
    path = directory / name
    return {
        "name": name,
        "media_type": media_type,
        "size_bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def build_release(
    *,
    version: str,
    tag: str,
    commit: str | None = None,
    runtime: Path | None = None,
    output: Path | None = None,
    root: Path = ROOT,
) -> Path:
    """Build all unsigned developer-preview assets into a new output directory."""
    validate_host()
    core, channel = validate_version(version, tag)
    validate_bundle_versions(version, root=root)
    source_commit, tree = resolve_source_commit(commit, root=root)
    release_root = (output or root / "dist/releases" / tag).expanduser().absolute()
    if release_root.exists():
        raise ReleaseError(f"release output already exists; refusing to overwrite: {release_root}")
    release_root.parent.mkdir(parents=True, exist_ok=True)
    runtime_path = runtime or root / "dist/desktop-runtime/prepared"
    with tempfile.TemporaryDirectory(prefix=f".{tag}.stage-", dir=release_root.parent) as temporary:
        stage = Path(temporary)
        assets = stage / "assets"
        assets.mkdir()
        built_app = stage / APP_NAME
        _run(
            sys.executable,
            str(root / "app/scripts/build_app.py"),
            "--app",
            str(built_app),
            "--runtime",
            str(runtime_path.expanduser().absolute()),
            cwd=root,
        )
        source_name = f"copytrading-source-v{version}.tar.gz"
        source_sha = create_source_archive(root, source_commit, version, assets / source_name)

        provenance = {
            "schema_version": 1,
            "release_type": "developer-preview",
            "version": version,
            "core_version": core,
            "channel": channel,
            "tag": tag,
            "target": {
                "operating_system": "macOS",
                "minimum_version": "26.0",
                "architecture": "arm64",
            },
            "source": {
                "commit": source_commit,
                "tree": tree,
                "archive": {"name": source_name, "sha256": source_sha},
            },
            "signature": {"signed": False, "notarized": False, "automatic_updates_trusted": False},
        }
        provenance_path = built_app / "Contents/Resources/ReleaseProvenance.json"
        _write_json(provenance_path, provenance)
        contents = built_app / "Contents"

        sbom_name = "sbom.cyclonedx.json"
        missing_metadata, missing_python_license_material = write_sbom(
            built_app, version, source_commit, assets / sbom_name
        )
        site_packages = built_app / RUNTIME / "cpython/python/lib/python3.14/site-packages"
        python_components, python_license_files, _, _ = python_inventory(site_packages)
        resources = contents / "Resources"
        licenses = resources / "ThirdPartyLicenses"
        license_gaps = collect_licenses(
            built_app, licenses, python_license_files, missing_python_license_material
        )
        notices = resources / "THIRD_PARTY_NOTICES.md"
        write_notices(built_app, version, python_components, notices)
        shutil.copyfile(notices, assets / "THIRD_PARTY_NOTICES.md")

        license_zip_name = "THIRD_PARTY_LICENSES.zip"
        _create_license_zip(licenses, assets / license_zip_name)
        inventory_path = built_app / RUNTIME / "bundle-files.json"
        _write_json(inventory_path, bundle_inventory(contents))
        # Preview provenance and licenses change the local build's resources. Seal the final
        # archive contents ad-hoc; preview releases remain explicitly unsigned and untrusted.
        sign_if_available(built_app, ad_hoc=True)
        problems = verify(built_app)
        if problems:
            raise ReleaseError("built app bundle verification failed: " + "; ".join(problems))

        app_name = f"CopyTrading-v{version}-macos-arm64.zip"
        app_zip = assets / app_name
        _run("ditto", "-c", "-k", "--keepParent", str(built_app), str(app_zip), cwd=root)
        extraction = stage / "extracted"
        extracted_app = extract_and_verify_app_zip(app_zip, extraction, version, tag, source_commit)
        if not extracted_app.is_dir():
            raise ReleaseError("app ZIP extraction did not produce an application bundle")

        manifest = {
            "schema_version": 1,
            "release": {
                "type": "developer-preview",
                "version": version,
                "core_version": core,
                "channel": channel,
                "tag": tag,
                "prerelease": True,
            },
            "source": {
                "commit": source_commit,
                "tree": tree,
                "archive": {"name": source_name, "sha256": source_sha},
            },
            "target": {
                "operating_system": "macOS",
                "minimum_version": "26.0",
                "architecture": "arm64",
            },
            "signature": {"signed": False, "notarized": False, "automatic_updates_trusted": False},
            "license_review": {
                "status": "required",
                "embedded_notices": "Contents/Resources/THIRD_PARTY_NOTICES.md",
                "embedded_license_material": "Contents/Resources/ThirdPartyLicenses",
                "missing_python_license_metadata": missing_metadata,
                "missing_license_material": license_gaps,
                "statement": (
                    "The inventory is evidence for review and is not a legal determination."
                ),
            },
            "assets": [
                _asset_record(assets, app_name, "application/zip"),
                _asset_record(assets, source_name, "application/gzip"),
                _asset_record(assets, sbom_name, "application/vnd.cyclonedx+json"),
                _asset_record(assets, "THIRD_PARTY_NOTICES.md", "text/markdown"),
                _asset_record(assets, license_zip_name, "application/zip"),
            ],
        }
        _write_json(assets / "release-manifest.json", manifest)
        _write_checksums(assets)
        verify_checksums(assets)
        assets.replace(release_root)
    return release_root


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="prerelease SemVer, such as 0.1.0-alpha.1")
    parser.add_argument("--tag", help="exact v-prefixed release tag; defaults to v<version>")
    parser.add_argument("--commit", help="require this exact checked out Git commit")
    parser.add_argument("--runtime", type=Path, help="prepared pinned macOS runtime directory")
    parser.add_argument("--output", type=Path, help="new output directory for all release assets")
    arguments = parser.parse_args()
    tag = arguments.tag or f"v{arguments.version}"
    try:
        release_root = build_release(
            version=arguments.version,
            tag=tag,
            commit=arguments.commit,
            runtime=arguments.runtime,
            output=arguments.output,
        )
    except (OSError, ReleaseError, subprocess.CalledProcessError) as error:
        print(f"release build failed: {error}", file=sys.stderr)
        return 1
    print(f"developer-preview assets built and verified in {release_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
