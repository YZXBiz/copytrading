"""Validate a staged, relocatable CopyTrading application bundle."""

from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import json
import plistlib
import re
import stat
import subprocess
from email.parser import Parser
from pathlib import Path

_DIGEST = re.compile(r"[0-9a-f]{64}\Z")
_VERSION = re.compile(r"[0-9]+(?:\.[0-9]+)*(?:[+._-][0-9A-Za-z]+)*\Z")
_TOOLS = re.compile(rb"\b(?:uv|brew|docker)\b")
_ABSOLUTE_TOOLS = re.compile(rb"(?:/opt/homebrew/bin/|/usr/local/bin/)(?:uv|brew|docker)\b")
_DEVELOPER_PATH = re.compile(rb"/Users/[^/\x00\s]+/[^\x00\s]+")
# Debug builds can skip owner authentication for UI journeys; shipped binaries must not.
_UI_TEST_UNLOCK = b"COPYTRADING_UI_TEST_UNLOCK"
# Debug builds can fill Connections with the owner's test keys; shipped binaries must not.
_DEV_PREFILL = b"COPYTRADING_DEV_PREFILL"
_SECRET_SUFFIXES = {".key", ".p12", ".pfx"}
_MACHO_MAGIC = {
    bytes.fromhex(value)
    for value in ("feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca")
}
_INVENTORY = Path("Resources/Runtime/bundle-files.json")
# Signing rewrites these bytes using the resource envelope, which includes the inventory itself.
# The final codesign verification protects them without a circular inventory digest.
_SIGNING_FILES = {Path("MacOS/CopyTrading"), Path("_CodeSignature/CodeResources")}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def bundle_inventory(contents: Path) -> dict[str, dict[str, str]]:
    """Hash packaged content; codesign independently protects the final executable and seal."""
    files: dict[str, str] = {}
    links: dict[str, str] = {}
    for path in sorted(contents.rglob("*")):
        relative = path.relative_to(contents)
        if relative == _INVENTORY or relative in _SIGNING_FILES:
            continue
        if path.is_symlink():
            links[relative.as_posix()] = path.readlink().as_posix()
        elif path.is_file():
            files[relative.as_posix()] = sha256(path)
    return {"files": files, "links": links}


def code_signature_problems(app: Path) -> list[str]:
    """Require a valid executable signature and resource envelope without launching the app."""
    try:
        result = subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
            capture_output=True,
            check=False,
        )
    except OSError:
        return ["cannot verify app code signature"]
    return [] if result.returncode == 0 else ["invalid app code signature or resource seal"]


def _check_inventory(contents: Path, problems: list[str]) -> None:
    expected = _read_json(contents / _INVENTORY, problems)
    actual = bundle_inventory(contents)
    for kind in ("files", "links"):
        pinned = expected.get(kind)
        if not isinstance(pinned, dict):
            problems.append(f"missing bundle {kind} inventory")
            continue
        for relative in sorted(pinned.keys() - actual[kind].keys()):
            problems.append(f"missing bundle file: {relative}")
        for relative in sorted(actual[kind].keys() - pinned.keys()):
            problems.append(f"unexpected bundle file: {relative}")
        for relative in sorted(pinned.keys() & actual[kind].keys()):
            if pinned[relative] != actual[kind][relative]:
                problems.append(f"bundle file digest mismatch: {relative}")


def _normalized_name(value: str) -> str:
    return re.sub(r"[-_.]+", "-", value).lower()


def _check_locked_packages(site: Path, packages: dict[str, str], problems: list[str]) -> None:
    distributions: dict[str, tuple[str, Path]] = {}
    for directory in site.glob("*.dist-info"):
        metadata = directory / "METADATA"
        try:
            message = Parser().parsestr(metadata.read_text(encoding="utf-8"), headersonly=True)
            name = message.get("Name")
            version = message.get("Version")
        except OSError:
            name = version = None
        if not name or not version:
            problems.append(f"invalid installed distribution: {directory.name}")
            continue
        normalized = _normalized_name(name)
        if normalized in distributions:
            problems.append(f"duplicate installed distribution: {normalized}")
        distributions[normalized] = (version, directory)
    for name, version in packages.items():
        normalized = _normalized_name(name)
        installed = distributions.get(normalized)
        if installed is None or installed[0] != version:
            problems.append(f"missing or wrong locked package: {name}=={version}")
            continue
        record = installed[1] / "RECORD"
        try:
            with record.open(newline="", encoding="utf-8") as stream:
                rows = list(csv.reader(stream))
        except OSError:
            problems.append(f"missing locked package RECORD: {name}")
            continue
        if not rows:
            problems.append(f"empty locked package RECORD: {name}")
        for row in rows:
            if len(row) != 3:
                problems.append(f"invalid locked package RECORD: {name}")
                break
            relative, encoded, size = row
            target = (site / relative).resolve()
            if not target.is_relative_to(site.resolve()) or not target.is_file():
                problems.append(f"missing locked package file: {name}: {relative}")
                continue
            try:
                expected_size = int(size) if size else None
            except ValueError:
                problems.append(f"invalid locked package size: {name}: {relative}")
                continue
            if expected_size is not None and target.stat().st_size != expected_size:
                problems.append(f"locked package size mismatch: {name}: {relative}")
            if encoded:
                algorithm, separator, value = encoded.partition("=")
                if algorithm != "sha256" or not separator:
                    problems.append(f"unsupported locked package digest: {name}: {relative}")
                    continue
                actual = base64.urlsafe_b64encode(bytes.fromhex(sha256(target))).rstrip(b"=")
                if actual.decode("ascii") != value:
                    problems.append(f"locked package digest mismatch: {name}: {relative}")


def _read_json(path: Path, problems: list[str]) -> dict:
    try:
        value = json.loads(path.read_text())
        if isinstance(value, dict):
            return value
    except OSError, ValueError:
        pass
    problems.append(f"missing or invalid resource: {path.name}")
    return {}


def _binary_architecture(path: Path, problems: list[str]) -> None:
    result = subprocess.run(
        ["/usr/bin/file", "-b", str(path)], capture_output=True, text=True, check=False
    )
    if result.returncode or "Mach-O" not in result.stdout or "arm64" not in result.stdout:
        problems.append(f"architecture mismatch: {path.name}")


def _macho(path: Path) -> bool:
    with path.open("rb") as stream:
        return stream.read(4) in _MACHO_MAGIC


def _expand_loader_path(value: str, binary: Path, executable: Path) -> Path | None:
    if value.startswith("@loader_path/"):
        return binary.parent / value.removeprefix("@loader_path/")
    if value.startswith("@executable_path/"):
        return executable.parent / value.removeprefix("@executable_path/")
    if value.startswith("/"):
        return Path(value)
    return None


def _check_dynamic_links(
    binary: Path, executable: Path, contents: Path, problems: list[str]
) -> None:
    result = subprocess.run(
        ["/usr/bin/otool", "-l", str(binary)], capture_output=True, text=True, check=False
    )
    if result.returncode:
        problems.append(f"cannot inspect native dependencies: {binary.name}")
        return
    command = ""
    dependencies: list[str] = []
    rpaths: list[str] = []
    for line in result.stdout.splitlines():
        value = line.strip()
        if value.startswith("cmd LC_"):
            command = value.removeprefix("cmd ")
        elif command in {
            "LC_LOAD_DYLIB",
            "LC_LOAD_WEAK_DYLIB",
            "LC_REEXPORT_DYLIB",
        } and value.startswith("name "):
            dependencies.append(value.split()[1])
            command = ""
        elif command == "LC_RPATH" and value.startswith("path "):
            rpaths.append(value.split()[1])
            command = ""
    for dependency in dependencies:
        if dependency.startswith(("/usr/lib/", "/System/Library/")):
            continue
        candidates: list[Path] = []
        if dependency.startswith("@rpath/"):
            suffix = dependency.removeprefix("@rpath/")
            candidates.extend(
                expanded / suffix
                for entry in rpaths
                if (expanded := _expand_loader_path(entry, binary, executable)) is not None
            )
        elif (expanded := _expand_loader_path(dependency, binary, executable)) is not None:
            candidates.append(expanded)
        if not any(
            candidate.resolve().is_relative_to(contents.resolve()) and candidate.is_file()
            for candidate in candidates
        ):
            problems.append(f"unresolved native dependency: {binary.name}: {dependency}")


def _launch_sources(resources: Path) -> list[Path]:
    engine = resources / "Engine/src"
    python = resources / "Runtime/cpython/python"
    site = python / "lib/python3.14/site-packages"
    paths = list(engine.rglob("*.py"))
    paths.extend(path for path in (python / "bin").glob("*") if path.is_file())
    paths.extend(site.rglob("*.pth"))
    paths.extend(site.rglob("sitecustomize.py"))
    paths.extend(site.rglob("usercustomize.py"))
    paths.extend((resources / "Runtime").glob("*.json"))
    return sorted(set(paths))


def verify(app: Path, *, inspect_macho: bool = True) -> list[str]:
    """Return all bundle violations without executing any bundled code."""
    problems: list[str] = []
    contents = app / "Contents"
    resources = contents / "Resources"
    runtime = resources / "Runtime"
    try:
        with (contents / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
    except OSError, ValueError, plistlib.InvalidFileException:
        return ["missing or invalid Info.plist"]
    if info.get("CFBundleIdentifier") != "dev.copytrading.app":
        problems.append("unexpected bundle identity")
    executable_name = info.get("CFBundleExecutable")
    if executable_name != "CopyTrading":
        problems.append("unexpected bundle executable")
    executable = contents / "MacOS" / "CopyTrading"
    manifest = _read_json(runtime / "artifacts.json", problems)
    prepared = _read_json(runtime / "runtime.json", problems)
    dependency_record = _read_json(runtime / "python-dependencies.json", problems)
    artifacts = manifest.get("artifacts", [])
    identities = {
        entry.get("name"): entry
        for entry in prepared.get("artifacts", [])
        if isinstance(entry, dict)
    }
    if not isinstance(artifacts, list) or {
        a.get("name") for a in artifacts if isinstance(a, dict)
    } != {"cpython"}:
        problems.append("missing artifact pins")
        artifacts = []
    binaries = [executable]
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            problems.append("invalid artifact pin")
            continue
        name = artifact.get("name")
        version = artifact.get("version", "")
        digest = artifact.get("sha256", "")
        relative = artifact.get("binary_path", "")
        if (
            not isinstance(version, str)
            or not _VERSION.fullmatch(version)
            or not isinstance(digest, str)
            or not _DIGEST.fullmatch(digest)
            or artifact.get("platform") != "darwin-arm64"
        ):
            problems.append(f"invalid artifact pin: {name}")
        if identities.get(name) != {"name": name, "version": version, "sha256": digest}:
            problems.append(f"prepared artifact identity mismatch: {name}")
        if (
            not isinstance(relative, str)
            or not relative
            or Path(relative).is_absolute()
            or ".." in Path(relative).parts
        ):
            problems.append(f"unsafe binary path: {name}")
            continue
        binaries.append(runtime / relative)
    agent_command = contents / "Helpers" / "copytrading"
    localization_bundle = resources / "CopyTrading_AppLocalizationCore.bundle/Contents/Resources"
    required = [
        executable,
        agent_command,
        localization_bundle / "en.lproj/Localizable.strings",
        localization_bundle / "zh-Hans.lproj/Localizable.strings",
        resources / "CopyTrading_CopyTradingUI.bundle/Fonts/JosefinSans.ttf",
        resources / "Engine" / "src" / "copytrading_engine" / "__main__.py",
        runtime / "THIRD_PARTY_NOTICES.md",
        runtime / "cpython" / "python" / "lib" / "python3.14" / "os.py",
        runtime / "cpython" / "python" / "lib" / "python3.14" / "site-packages",
    ]
    for required_path in required:
        if not required_path.exists():
            category = "standard library" if required_path.name == "os.py" else "resource"
            problems.append(f"missing {category}: {required_path.relative_to(contents)}")
    if agent_command.exists() and (
        agent_command.is_symlink()
        or not agent_command.stat().st_mode & stat.S_IXUSR
        or not agent_command.read_bytes().startswith(b"#!/bin/sh\n")
    ):
        problems.append("agent command is not an executable shell script")
    if not list((resources / "Contracts").glob("*.json")):
        problems.append("missing Contracts resources")
    if not isinstance(dependency_record.get("lock_sha256"), str) or not _DIGEST.fullmatch(
        dependency_record["lock_sha256"]
    ):
        problems.append("missing Python lock pin")
    packages = dependency_record.get("packages")
    if (
        not isinstance(packages, dict)
        or not packages
        or any(
            not isinstance(name, str)
            or not name
            or not isinstance(value, str)
            or not _VERSION.fullmatch(value)
            for name, value in packages.items()
        )
    ):
        problems.append("un-pinned Python dependency")
    else:
        _check_locked_packages(
            runtime / "cpython/python/lib/python3.14/site-packages", packages, problems
        )
    for binary in binaries:
        if not binary.is_file() or not (binary.stat().st_mode & stat.S_IXUSR):
            problems.append(f"missing executable: {binary.name}")
            continue
        if inspect_macho:
            _binary_architecture(binary, problems)
    native_candidates = set(binaries)
    native_candidates.update(
        path
        for path in contents.rglob("*")
        if path.is_file() and not path.is_symlink() and path.suffix in {".so", ".dylib", ".bundle"}
    )
    if inspect_macho:
        for binary in sorted(native_candidates - set(binaries)):
            _binary_architecture(binary, problems)
        for binary in sorted(native_candidates):
            if binary.is_file() and _macho(binary):
                _check_dynamic_links(binary, executable, contents, problems)
    for path in [executable, agent_command, *_launch_sources(resources)]:
        if not path.is_file() or path.is_symlink() or (path != executable and _macho(path)):
            continue
        data = path.read_bytes()
        if _DEVELOPER_PATH.search(data):
            problems.append(f"absolute developer path: {path.relative_to(contents)}")
        if path == executable and _UI_TEST_UNLOCK in data:
            problems.append("debug-only authentication bypass in executable")
        if path == executable and _DEV_PREFILL in data:
            problems.append("debug-only setup prefill in executable")
        tool_pattern = _ABSOLUTE_TOOLS if path == executable else _TOOLS
        if tool_pattern.search(data):
            problems.append(f"developer tool required at launch: {path.relative_to(contents)}")
    for path in contents.rglob("*"):
        if path.is_symlink():
            resolved = path.resolve()
            if not resolved.is_relative_to(contents.resolve()):
                problems.append(f"escaping symlink: {path.relative_to(contents)}")
        is_secret = path.suffix.lower() in _SECRET_SUFFIXES or (
            path.suffix.lower() == ".pem"
            and any(word in path.stem.lower() for word in ("private", "secret", "key"))
        )
        if path.is_file() and is_secret:
            if path.stat().st_mode & (stat.S_IRGRP | stat.S_IROTH):
                problems.append(f"world-readable secret file: {path.relative_to(contents)}")
        if path.is_file() and path.suffix in {".pth", ".cfg"}:
            data = path.read_bytes()
            if b"/Users/" in data or b"/opt/homebrew/" in data:
                problems.append(f"absolute developer path: {path.relative_to(contents)}")
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as stream:
                first_line = stream.readline(512)
            if first_line.startswith(b"#!") and _DEVELOPER_PATH.search(first_line):
                problems.append(f"absolute developer path: {path.relative_to(contents)}")
    if list(contents.rglob("pyvenv.cfg")):
        problems.append("developer virtual environment copied into bundle")
    _check_inventory(contents, problems)
    if inspect_macho:
        problems.extend(code_signature_problems(app))
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    args = parser.parse_args()
    problems = verify(args.app)
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print(f"bundle verified: {args.app}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
