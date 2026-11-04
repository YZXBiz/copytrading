"""Validate the Electron CopyTrading.app: its identity, update feed, runtime, engine, and seal."""

from __future__ import annotations

import argparse
import plistlib
import re
import stat
from pathlib import Path

from verify_bundle import (
    _DEVELOPER_PATH,
    _DIGEST,
    _SECRET_SUFFIXES,
    _TOOLS,
    _VERSION,
    _binary_architecture,
    _check_dynamic_links,
    _check_inventory,
    _check_locked_packages,
    _launch_sources,
    _macho,
    _read_json,
    code_signature_problems,
)

_FEED = re.compile(r"provider: github\nowner: YZXBiz\nrepo: copytrading\n")
_BUILD = re.compile(r"[0-9]+\Z")


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
    if info.get("CFBundleExecutable") != "CopyTrading":
        problems.append("unexpected bundle executable")
    version = info.get("CFBundleShortVersionString")
    if not isinstance(version, str) or not _VERSION.fullmatch(version) or version == "0.0.0":
        problems.append("the app shows no real version")
    if not _BUILD.fullmatch(str(info.get("CFBundleVersion", ""))):
        problems.append("the app has no build number")

    executable = contents / "MacOS" / "CopyTrading"
    site = runtime / "cpython/python/lib/python3.14/site-packages"
    required = [
        executable,
        resources / "app.asar",
        resources / "app-update.yml",
        resources / "Engine/src/copytrading_engine/__main__.py",
        runtime / "THIRD_PARTY_NOTICES.md",
        runtime / "cpython/python/lib/python3.14/os.py",
        site,
    ]
    for path in required:
        if not path.exists():
            problems.append(f"missing resource: {path.relative_to(contents)}")
    feed = resources / "app-update.yml"
    if feed.is_file() and not _FEED.match(feed.read_text()):
        problems.append("update feed does not point at the GitHub releases of YZXBiz/copytrading")

    manifest = _read_json(runtime / "artifacts.json", problems)
    prepared = _read_json(runtime / "runtime.json", problems)
    record = _read_json(runtime / "python-dependencies.json", problems)
    artifacts = [a for a in manifest.get("artifacts", []) if isinstance(a, dict)]
    if {a.get("name") for a in artifacts} != {"cpython"}:
        problems.append("missing artifact pins")
    identities = {e.get("name"): e for e in prepared.get("artifacts", []) if isinstance(e, dict)}
    binaries = [executable]
    for artifact in artifacts:
        name, pin_version, digest = (
            artifact.get("name"),
            artifact.get("version", ""),
            artifact.get("sha256", ""),
        )
        relative = artifact.get("binary_path", "")
        if (
            not isinstance(pin_version, str)
            or not _VERSION.fullmatch(pin_version)
            or not isinstance(digest, str)
            or not _DIGEST.fullmatch(digest)
            or artifact.get("platform") != "darwin-arm64"
        ):
            problems.append(f"invalid artifact pin: {name}")
        if identities.get(name) != {"name": name, "version": pin_version, "sha256": digest}:
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
    packages = record.get("packages")
    if not isinstance(record.get("lock_sha256"), str) or not _DIGEST.fullmatch(
        record["lock_sha256"]
    ):
        problems.append("missing Python lock pin")
    if not isinstance(packages, dict) or not packages:
        problems.append("un-pinned Python dependency")
    else:
        _check_locked_packages(site, packages, problems)
    for binary in binaries:
        if not binary.is_file() or not (binary.stat().st_mode & stat.S_IXUSR):
            problems.append(f"missing executable: {binary.name}")
        elif inspect_macho:
            _binary_architecture(binary, problems)
    if inspect_macho:
        # The seal covers Electron's frameworks; Python's natives must resolve inside the app.
        natives = {
            p
            for p in runtime.rglob("*")
            if p.is_file() and not p.is_symlink() and p.suffix in {".so", ".dylib", ".bundle"}
        } | {b for b in binaries if b != executable and b.is_file()}
        for native in sorted(natives):
            if _macho(native):
                _binary_architecture(native, problems)
                _check_dynamic_links(native, executable, contents, problems)

    for path in _launch_sources(resources):
        if not path.is_file() or path.is_symlink() or _macho(path):
            continue
        data = path.read_bytes()
        if _DEVELOPER_PATH.search(data):
            problems.append(f"absolute developer path: {path.relative_to(contents)}")
        if _TOOLS.search(data):
            problems.append(f"developer tool required at launch: {path.relative_to(contents)}")
    # The page carries sample paths from captured fixtures; only the build machine's home counts.
    asar = resources / "app.asar"
    if asar.is_file() and str(Path.home()).encode() in asar.read_bytes():
        problems.append("the build machine's home folder is in Resources/app.asar")

    for path in contents.rglob("*"):
        if path.is_symlink() and not path.resolve().is_relative_to(contents.resolve()):
            problems.append(f"escaping symlink: {path.relative_to(contents)}")
        is_secret = path.suffix.lower() in _SECRET_SUFFIXES or (
            path.suffix.lower() == ".pem"
            and any(w in path.stem.lower() for w in ("private", "secret", "key"))
        )
        if path.is_file() and is_secret and path.stat().st_mode & (stat.S_IRGRP | stat.S_IROTH):
            problems.append(f"world-readable secret file: {path.relative_to(contents)}")
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
