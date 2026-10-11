"""Build the local ARM64 app from pinned native and Python artifacts."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.metadata
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

from local_signing import sign_if_available
from prepare_runtime import (
    SAFE_ARTIFACT_NAME_PATTERN,
    ArtifactManifestError,
    load_artifacts,
    verify_and_extract,
)
from verify_bundle import bundle_inventory, sha256, verify

ROOT = Path(__file__).resolve().parents[2]
MACOS = ROOT / "app"
ENGINE = ROOT / "engine"
BUILD_CONSTRAINTS = Path(__file__).with_name("python-build-constraints.txt")
BUILD_CONSTRAINTS_SHA256 = "4e7767f6fb8df1c6a395e419daf6cf06030fb71af6cce0caed46d0bcdcd03c84"
ALLOWED_SOURCE_BUILDS = {
    "discord-protos": (
        "0.0.2",
        "sha256:23953a05f32beedb40b708ec4b457530a6196a49c8d75d337ae9282a2a41c997",
    )
}


def run(
    *arguments: str, cwd: Path = ROOT, capture: bool = False, env: dict[str, str] | None = None
) -> str:
    result = subprocess.run(
        arguments, cwd=cwd, check=True, text=True, capture_output=capture, env=env
    )
    return result.stdout.strip() if capture else ""


def pinned_packages(requirements: str) -> dict[str, str]:
    matches = re.findall(r"(?m)^([A-Za-z0-9_.-]+)==([A-Za-z0-9.+_-]+)", requirements)
    if not matches or len(matches) != len(set(name for name, _ in matches)):
        raise ValueError("exported runtime dependencies lack unique exact pins")
    return dict(sorted(matches))


def applicable_packages(requirements: str) -> dict[str, str]:
    """Evaluate the restricted markers present in the locked macOS export."""
    target = {"sys_platform": "darwin", "implementation_name": "cpython"}
    applicable: dict[str, str] = {}
    for line in requirements.splitlines():
        if not line or line[0].isspace():
            continue
        requirement = re.fullmatch(
            r"([A-Za-z0-9_.-]+)==([A-Za-z0-9.+_-]+)(?:\s*;\s*([^\\]+?))?\s*\\",
            line,
        )
        if requirement is None:
            raise ValueError(f"unsupported exported Python requirement: {line}")
        name, version, marker = requirement.groups()
        if marker is not None:
            condition = re.fullmatch(
                r"(sys_platform|implementation_name)\s*(==|!=)\s*'([^']+)'",
                marker.strip(),
            )
            if condition is None:
                raise ValueError(f"unsupported Python dependency marker: {marker}")
            key, operator, value = condition.groups()
            applies = target[key] == value
            if operator == "!=":
                applies = not applies
            if not applies:
                continue
        applicable[name] = version
    if not applicable:
        raise ValueError("exported Python requirements lack applicable pins")
    if not applicable.keys() <= pinned_packages(requirements).keys():
        raise ValueError("applicable Python package lacks an exported pin")
    return dict(sorted(applicable.items()))


def source_build_policy(
    requirements: str, lock_path: Path, constraints_path: Path
) -> dict[str, dict[str, str]]:
    """Allow only the audited sdist and exact hashed build toolchain."""
    if sha256(constraints_path) != BUILD_CONSTRAINTS_SHA256:
        raise ValueError("source build constraints differ from pinned build tool hashes")
    exported = pinned_packages(requirements)
    sections = list(re.finditer(r"(?m)^([A-Za-z0-9_.-]+)==([A-Za-z0-9.+_-]+)[^\n]*", requirements))
    exported_hashes = {
        match.group(1): set(
            re.findall(
                r"--hash=(sha256:[0-9a-f]{64})",
                requirements[match.end() : sections[index + 1].start()]
                if index + 1 < len(sections)
                else requirements[match.end() :],
            )
        )
        for index, match in enumerate(sections)
    }
    lock = tomllib.loads(lock_path.read_text())
    source_builds: dict[str, dict[str, str]] = {}
    for package in lock["package"]:
        name = package["name"]
        if name not in exported or package.get("wheels"):
            continue
        version = package["version"]
        allowed = ALLOWED_SOURCE_BUILDS.get(name)
        sdist = package.get("sdist")
        if allowed != (version, sdist.get("hash") if isinstance(sdist, dict) else None):
            raise ValueError(f"unapproved source build: {name}=={version}")
        if exported[name] != version or exported_hashes.get(name) != {allowed[1]}:
            raise ValueError(f"source build export lacks exact archive hash: {name}")
        source_builds[name] = {
            "version": version,
            "sdist_sha256": allowed[1].removeprefix("sha256:"),
            "build_constraints_sha256": BUILD_CONSTRAINTS_SHA256,
        }
    if any(name in exported and name not in source_builds for name in ALLOWED_SOURCE_BUILDS):
        raise ValueError("source build lock is missing the audited archive")
    return source_builds


def source_install_options(
    source_builds: dict[str, dict[str, str]], constraints_path: Path
) -> tuple[str, ...]:
    options = ["--only-binary", ":all:"]
    for name in sorted(source_builds):
        options.extend(("--no-binary", name))
    if source_builds:
        options.extend(("--build-constraints", str(constraints_path)))
    return tuple(options)


def _distribution_versions(site: Path) -> dict[str, str]:
    installed: dict[str, str] = {}
    for distribution in importlib.metadata.distributions(path=[str(site)]):
        raw_name = distribution.metadata.get("Name", "")
        name = re.sub(r"[-_.]+", "-", raw_name).lower()
        version = distribution.version
        if not name or name in installed:
            raise ValueError(f"unlocked installed Python package: {raw_name}=={version}")
        installed[name] = version
    return installed


def installed_packages(
    site: Path, expected: dict[str, str], preinstalled: dict[str, str]
) -> dict[str, str]:
    """Require precisely the target pins, excluding intact native-runtime tools."""
    installed = _distribution_versions(site)
    for name, version in preinstalled.items():
        if name not in expected and installed.get(name) == version:
            del installed[name]
    for name, version in installed.items():
        if expected.get(name) != version:
            raise ValueError(f"unlocked installed Python package: {name}=={version}")
    missing = expected.keys() - installed.keys()
    if missing:
        raise ValueError(f"missing locked Python package: {', '.join(sorted(missing))}")
    return dict(sorted(installed.items()))


def restore_native_runtime(runtime: Path, manifest: dict, cache: Path) -> None:
    """Re-extract native bytes from archives that match the committed pins."""
    for artifact in manifest["artifacts"]:
        name = artifact.get("name")
        if not isinstance(name, str) or not SAFE_ARTIFACT_NAME_PATTERN.fullmatch(name):
            raise ArtifactManifestError("artifact name must be a safe single path component")
        relative = artifact.get("binary_path")
        if (
            not isinstance(relative, str)
            or Path(relative).is_absolute()
            or ".." in Path(relative).parts
            or not Path(relative).parts
            or Path(relative).parts[0] != name
        ):
            raise ArtifactManifestError(f"binary path must stay inside artifact: {name}")
    runtime.mkdir(parents=True)
    identities: list[dict[str, str]] = []
    for artifact in manifest["artifacts"]:
        archive = cache / artifact["filename"]
        if not archive.is_file() or sha256(archive) != artifact["sha256"]:
            raise ValueError(f"cached {artifact['name']} archive does not match its pinned digest")
        verify_and_extract(
            archive, expected_sha256=artifact["sha256"], destination=runtime / artifact["name"]
        )
        if not (runtime / artifact["binary_path"]).is_file():
            raise ValueError(f"pinned {artifact['name']} archive lacks its native binary")
        identities.append({field: artifact[field] for field in ("name", "version", "sha256")})
    (runtime / "runtime.json").write_text(
        json.dumps({"schema_version": 1, "artifacts": identities}, indent=2) + "\n"
    )


def remove_console_scripts(site_packages: Path) -> None:
    """Drop pip's console-script wrappers and their RECORD entries.

    Their shebangs name the Python that built the bundle, so they cannot run on another Mac, and
    the app starts the engine with `python -m`. Package RECORDs must keep matching the files that
    remain, as `pip uninstall` would leave them.
    """
    scripts = site_packages / "bin"
    if not scripts.is_dir():
        return
    shutil.rmtree(scripts)
    for record in site_packages.glob("*.dist-info/RECORD"):
        with record.open(newline="", encoding="utf-8") as stream:
            rows = list(csv.reader(stream))
        kept = [row for row in rows if not (row and Path(row[0]).parts[:1] == ("bin",))]
        if len(kept) != len(rows):
            with record.open("w", newline="", encoding="utf-8") as stream:
                csv.writer(stream, lineterminator="\n").writerows(kept)


def copy_localization_bundle(bin_dir: Path, resources: Path) -> Path:
    """Place SwiftPM's module resource bundle where Bundle.module searches in an app."""
    source = bin_dir / "CopyTrading_AppLocalizationCore.bundle"
    if not source.is_dir():
        raise ValueError("Swift build is missing the AppLocalizationCore resource bundle")
    for language in ("en", "zh-Hans"):
        catalog = source / "Contents/Resources" / f"{language}.lproj/Localizable.strings"
        if not catalog.is_file():
            raise ValueError(f"Swift resource bundle is missing {language} localization catalog")
    destination = resources / source.name
    shutil.copytree(source, destination)
    return destination


def copy_ui_bundle(bin_dir: Path, resources: Path) -> Path:
    """Place the UI module's resource bundle, which carries the display font, beside the app's
    other resources, where Bundle.module finds it."""
    source = bin_dir / "CopyTrading_CopyTradingUI.bundle"
    if not (source / "Contents/Resources/Fonts/JosefinSans.ttf").is_file():
        raise ValueError("Swift build is missing the display font in the CopyTradingUI bundle")
    destination = resources / source.name
    shutil.copytree(source, destination)
    return destination


def build_number() -> str:
    """Commits on the checked-out history: it only grows on main, so Sparkle sees each release as
    newer than the last (CFBundleVersion)."""
    return run("git", "rev-list", "--count", "HEAD", cwd=ROOT, capture=True).strip()


def stamp_versions(info_path: Path, version: str | None) -> None:
    """A release shows its full version, such as 0.1.0-alpha.4; every build gets a build number."""
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    if version is not None:
        info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = build_number()
    with info_path.open("wb") as stream:
        plistlib.dump(info, stream)


def build(app: Path, prepared: Path, version: str | None = None) -> None:
    manifest_path = MACOS / "Resources/Runtime/artifacts.json"
    load_artifacts(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    prepared_identity = json.loads((prepared / "runtime.json").read_text())
    wanted = {a["name"]: (a["version"], a["sha256"]) for a in manifest["artifacts"]}
    available = {a["name"]: (a["version"], a["sha256"]) for a in prepared_identity["artifacts"]}
    if wanted != available:
        raise ValueError("prepared runtime does not match the committed artifact pins")
    for artifact in manifest["artifacts"]:
        if not (prepared / artifact["binary_path"]).is_file():
            raise ValueError(f"missing prepared native binary: {artifact['name']}")

    run(
        "arch",
        "-arm64",
        "swift",
        "build",
        "--package-path",
        str(MACOS),
        "--product",
        "CopyTrading",
        "-c",
        "release",
        "-Xswiftc",
        "-strict-concurrency=complete",
        "-Xswiftc",
        "-warnings-as-errors",
    )
    bin_dir = Path(
        run(
            "arch",
            "-arm64",
            "swift",
            "build",
            "--package-path",
            str(MACOS),
            "-c",
            "release",
            "--show-bin-path",
            capture=True,
        )
    )
    requirements = run(
        "uv",
        "export",
        "--directory",
        str(ENGINE),
        "--frozen",
        "--no-dev",
        "--no-emit-project",
        "--format",
        "requirements.txt",
        "--no-header",
        "--no-annotate",
        capture=True,
    )
    expected_packages = applicable_packages(requirements)
    source_builds = source_build_policy(requirements, ENGINE / "uv.lock", BUILD_CONSTRAINTS)
    app.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="desktop-build-", dir=app.parent) as temporary:
        staged = Path(temporary) / app.name
        macos = staged / "Contents/MacOS"
        resources = staged / "Contents/Resources"
        runtime = resources / "Runtime"
        macos.mkdir(parents=True)
        resources.mkdir(parents=True)
        shutil.copy2(MACOS / "Resources/Info.plist", staged / "Contents/Info.plist")
        stamp_versions(staged / "Contents/Info.plist", version)
        shutil.copy2(MACOS / "Resources/AppIcon.icns", resources / "AppIcon.icns")
        shutil.copy2(bin_dir / "CopyTrading", macos / "CopyTrading")
        run("/usr/bin/strip", "-S", str(macos / "CopyTrading"))
        # Sparkle, the updater (ADR-0009), keeps its own signature; the app finds it through
        # its @executable_path/../Frameworks run path.
        frameworks = staged / "Contents/Frameworks"
        frameworks.mkdir()
        shutil.copytree(
            bin_dir / "Sparkle.framework", frameworks / "Sparkle.framework", symlinks=True
        )
        copy_localization_bundle(bin_dir, resources)
        copy_ui_bundle(bin_dir, resources)
        helpers = staged / "Contents/Helpers"
        helpers.mkdir()
        shutil.copy2(MACOS / "Resources/Helpers/copytrading", helpers / "copytrading")
        (helpers / "copytrading").chmod(0o755)
        restore_native_runtime(runtime, manifest, ROOT / "dist/desktop-runtime/cache")
        for name in ("artifacts.json", "THIRD_PARTY_NOTICES.md"):
            shutil.copy2(MACOS / "Resources/Runtime" / name, runtime / name)
        shutil.copytree(MACOS / "Resources/Contracts", resources / "Contracts")
        shutil.copytree(
            ENGINE / "src",
            resources / "Engine/src",
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )

        python = runtime / "cpython/python/bin/python3.14"
        site_packages = runtime / "cpython/python/lib/python3.14/site-packages"
        preinstalled_packages = _distribution_versions(site_packages)
        with tempfile.TemporaryDirectory(prefix="desktop-requirements-") as requirements_dir:
            requirements_file = Path(requirements_dir) / "requirements.txt"
            requirements_file.write_text(requirements)
            run(
                "uv",
                "pip",
                "install",
                "--python",
                str(python),
                "--target",
                str(site_packages),
                "--python-platform",
                "aarch64-apple-darwin",
                "--python-version",
                "3.14",
                "--require-hashes",
                "--no-deps",
                *source_install_options(source_builds, BUILD_CONSTRAINTS),
                "-r",
                str(requirements_file),
            )
        remove_console_scripts(site_packages)
        packages = installed_packages(site_packages, expected_packages, preinstalled_packages)
        if not source_builds.keys() <= packages.keys():
            raise ValueError("audited source package missing from bundled Python packages")
        (runtime / "python-dependencies.json").write_text(
            json.dumps(
                {
                    "lock_sha256": hashlib.sha256((ENGINE / "uv.lock").read_bytes()).hexdigest(),
                    "packages": packages,
                    "source_builds": source_builds,
                },
                indent=2,
            )
            + "\n"
        )
        env = os.environ.copy()
        env["PYTHONPATH"] = str(resources / "Engine/src")
        run(
            str(python),
            "-c",
            "import copytrading_engine, pydantic, cryptography",
            env=env,
        )
        (runtime / "bundle-files.json").write_text(
            json.dumps(bundle_inventory(staged / "Contents"), sort_keys=True) + "\n"
        )
        # The resource envelope must include the finished inventory and all packaged files.
        # Retaining the owner's Team ID also preserves Keychain trust across local rebuilds.
        signed_by = sign_if_available(staged)
        problems = verify(staged)
        if problems:
            raise ValueError("bundle verification failed: " + "; ".join(problems))
        if app.exists():
            shutil.rmtree(app)
        staged.rename(app)
    signature = "signed with Apple Development" if signed_by else "ad-hoc signed"
    print(f"built local app ({signature}): {app}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "dist/CopyTrading.app")
    parser.add_argument("--runtime", type=Path, default=ROOT / "dist/desktop-runtime/prepared")
    parser.add_argument("--version", help="the release version to show, such as 0.1.0-alpha.4")
    arguments = parser.parse_args()
    try:
        build(arguments.app.resolve(), arguments.runtime.resolve(), arguments.version)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"desktop build failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
