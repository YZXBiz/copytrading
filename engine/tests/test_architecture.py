"""The engine is organized by capability; dependencies point from composition toward policy."""

import ast
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1] / "src" / "copytrading_engine"
TESTS = Path(__file__).resolve().parent
LAYERS = frozenset({"domain", "application", "adapters", "presentation", "entrypoints"})
LAYERED = frozenset({"execution", "trading"})
EXTERNAL_SDKS = frozenset(
    {"alpaca", "anthropic", "boto3", "discord", "httpx", "mcp", "openai", "pydantic_ai"}
)
PACKAGES = frozenset(
    {
        "assistant",
        "backup",
        "bootstrap",
        "control",
        "diagnostics",
        "execution",
        "host",
        "parsing",
        "shared",
        "sources",
        "trading",
    }
)

EXECUTION_POLICY = frozenset(
    {"execution/domain", "execution/application", "execution/presentation"}
)
EXECUTION = EXECUTION_POLICY | {"execution", "execution/adapters"}
TRADING_POLICY = frozenset({"trading/domain", "trading/application", "trading/presentation"})
TRADING = TRADING_POLICY | {"trading/adapters", "trading/entrypoints"}

# Each unit may import only the listed copytrading_engine units. A unit is a top-level
# package, or a layer of a layered package such as "execution/domain".
ALLOWED: dict[str, frozenset[str]] = {
    "shared": frozenset(),
    "sources": frozenset({"shared"}),
    "parsing": frozenset({"shared", "sources"}),
    "execution/domain": frozenset({"shared"}),
    "execution/application": frozenset({"shared", "execution/domain"}),
    "execution/presentation": frozenset({"shared", "execution/domain"}),
    "execution/adapters": frozenset({"shared"}) | EXECUTION_POLICY,
    "execution": frozenset({"shared"}) | EXECUTION,
    "trading/domain": frozenset({"shared", "parsing", "execution/domain"}),
    "trading/presentation": frozenset(
        {"shared", "execution/domain", "execution/presentation", "trading/domain"}
    ),
    "trading/application": frozenset({"shared", "parsing"}) | EXECUTION_POLICY | TRADING_POLICY,
    "trading/adapters": frozenset({"shared", "parsing", "sources", "diagnostics"})
    | EXECUTION
    | TRADING_POLICY,
    "trading/entrypoints": frozenset({"shared", "parsing", "sources", "diagnostics", "backup"})
    | EXECUTION
    | TRADING,
    "trading": frozenset({"trading/domain"}),
    # Diagnostics exports the engine self-test's durable stages and decorates host status.
    "diagnostics": frozenset({"shared", "host"}),
    # Agent control presents execution and trading results; it never reaches their adapters.
    "control": frozenset({"shared", "execution/domain", "execution/presentation"})
    | {"trading/domain", "trading/presentation"},
    # The assistant asks the control service and reads trading views; it never reaches adapters.
    "assistant": frozenset(
        {"shared", "control", "parsing", "trading/domain", "trading/presentation"}
    )
    | {"execution/domain", "execution/presentation"},
    "backup": frozenset({"shared", "sources", "parsing", "host", "control", "trading/adapters"})
    | {"execution/domain", "execution/application", "execution/adapters"},
    "host": frozenset({"shared", "backup", "control", "assistant"}) | EXECUTION_POLICY | TRADING,
}

# Flat packages keep their I/O in named modules; the rest of each package is policy
# and must not reach those modules or an external SDK.
FLAT_IO_MODULES: dict[str, frozenset[str]] = {
    "assistant": frozenset({"agent", "service"}),
    "control": frozenset({"sqlite", "client", "cli", "mcp_server", "__main__"}),
    "parsing": frozenset({"sqlite", "providers"}),
    "sources": frozenset({"sqlite", "session", "source", "attachments"}),
}

# The CLI and MCP server run outside the engine process, so they may import only the
# published contract and each other.
CONTROL_CLIENT_MODULES = frozenset({"client", "cli", "mcp_server", "__main__", "wire"})


def _unit(relative: Path) -> str:
    parts = relative.with_suffix("").parts
    if len(parts) == 1:
        return parts[0]
    if len(parts) > 2 and parts[0] in LAYERED and parts[1] in LAYERS:
        return f"{parts[0]}/{parts[1]}"
    return parts[0]


def _target(module: str) -> str | None:
    parts = module.split(".")
    if parts[0] != "copytrading_engine" or len(parts) < 2:
        return None
    if len(parts) > 2 and parts[1] in LAYERED and parts[2] in LAYERS:
        return f"{parts[1]}/{parts[2]}"
    return parts[1]


def imports(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    found: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            if node.level == 0 and node.module:
                found.add(node.module)
                found.update(f"{node.module}.{alias.name}" for alias in node.names)
            elif node.level:
                package = path.relative_to(ROOT).with_suffix("").parts[:-1]
                prefix = ("copytrading_engine", *package[: len(package) - node.level + 1])
                base = (*prefix, *(node.module.split(".") if node.module else ()))
                found.add(".".join(base))
                found.update(".".join((*base, alias.name)) for alias in node.names)
    return found


def _sources() -> list[Path]:
    return [path for path in ROOT.rglob("*.py") if "__pycache__" not in path.parts]


def test_every_module_belongs_to_a_known_package():
    unknown = {
        _unit(path.relative_to(ROOT)).split("/")[0]
        for path in _sources()
        if path.parent != ROOT or path.stem not in {"__init__", "__main__", "bootstrap"}
    } - PACKAGES
    assert unknown == set()


def test_units_import_only_allowed_units():
    violations = []
    for path in _sources():
        relative = path.relative_to(ROOT)
        unit = _unit(relative)
        allowed = ALLOWED.get(unit)
        if allowed is None:
            continue
        for name in imports(path):
            target = _target(name)
            if target is None or target == unit or target.split("/")[0] == unit:
                continue
            if target in allowed:
                continue
            violations.append(f"{relative}: {name}")
    assert violations == []


def test_policy_layers_do_not_import_external_sdks():
    violations = [
        f"{path.relative_to(ROOT)}: {name}"
        for path in _sources()
        if _unit(path.relative_to(ROOT)) in {"shared", "execution/domain", "execution/application"}
        for name in imports(path)
        if name.split(".")[0] in EXTERNAL_SDKS
    ]
    assert violations == []


def test_layered_packages_contain_only_layers():
    violations = []
    for package in (path for path in ROOT.rglob("*") if path.is_dir()):
        if package.name == "__pycache__":
            continue
        children = {child for child in package.iterdir() if child.name != "__pycache__"}
        if not any(child.is_dir() and child.name in LAYERS for child in children):
            continue
        extra = {
            child.name
            for child in children
            if child.name != "__init__.py" and not (child.is_dir() and child.name in LAYERS)
        }
        if extra:
            violations.append(f"{package.relative_to(ROOT)}: {sorted(extra)}")
    assert violations == []


def test_flat_package_policy_modules_do_not_import_their_io_modules():
    violations = []
    for package, io_modules in FLAT_IO_MODULES.items():
        for path in (ROOT / package).rglob("*.py"):
            if "__pycache__" in path.parts:
                continue
            module = path.relative_to(ROOT / package).parts[0].removesuffix(".py")
            if module in io_modules:
                continue
            for name in imports(path):
                parts = name.split(".")
                reaches_io = parts[:2] == ["copytrading_engine", package] and (
                    len(parts) > 2 and parts[2] in io_modules
                )
                if reaches_io or parts[0] in EXTERNAL_SDKS:
                    violations.append(f"{path.relative_to(ROOT)}: {name}")
    assert violations == []


def test_flat_io_guard_catches_policy_reaching_storage(tmp_path, monkeypatch):
    package = tmp_path / "copytrading_engine" / "parsing"
    package.mkdir(parents=True)
    (package / "relay.py").write_text(
        "from copytrading_engine.parsing.sqlite import SQLiteExtractionStore\n", encoding="utf-8"
    )
    monkeypatch.setattr(sys.modules[__name__], "ROOT", tmp_path / "copytrading_engine")

    with pytest.raises(AssertionError):
        test_flat_package_policy_modules_do_not_import_their_io_modules()


def _private_imports(path: Path) -> list[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    return [
        f"{node.module}.{alias.name}"
        for node in ast.walk(tree)
        if isinstance(node, ast.ImportFrom) and node.module
        for alias in node.names
        if alias.name.startswith("_")
    ]


def test_modules_do_not_import_private_names_from_other_modules():
    violations = [
        f"{path.relative_to(ROOT)}: {name}"
        for path in _sources()
        for name in _private_imports(path)
    ]
    assert violations == []


def test_tests_reach_the_engine_through_public_names():
    violations = [
        f"{path.relative_to(TESTS)}: {name}"
        for path in TESTS.rglob("*.py")
        if "__pycache__" not in path.parts
        for name in _private_imports(path)
        if name.startswith("copytrading_engine.")
    ]
    assert violations == []


def test_private_import_guard_catches_a_private_name(tmp_path, monkeypatch):
    package = tmp_path / "copytrading_engine" / "backup"
    package.mkdir(parents=True)
    (package / "probe.py").write_text(
        "from copytrading_engine.parsing.sqlite import _SCHEMA\n", encoding="utf-8"
    )
    monkeypatch.setattr(sys.modules[__name__], "ROOT", tmp_path / "copytrading_engine")

    with pytest.raises(AssertionError):
        test_modules_do_not_import_private_names_from_other_modules()


@pytest.mark.parametrize(
    ("unit", "source"),
    [
        (
            "execution/domain",
            "from copytrading_engine.execution.adapters.alpaca.broker import AlpacaBroker\n",
        ),
        ("execution/domain", "from ..adapters import alpaca\n"),
        ("sources", "import copytrading_engine.trading.entrypoints.runtime\n"),
        ("shared", "from copytrading_engine.host import status\n"),
    ],
)
def test_dependency_guard_catches_absolute_and_relative_imports(
    tmp_path, monkeypatch, unit, source
):
    package = tmp_path / "copytrading_engine" / unit
    package.mkdir(parents=True)
    (package / "probe.py").write_text(source, encoding="utf-8")
    monkeypatch.setattr(sys.modules[__name__], "ROOT", tmp_path / "copytrading_engine")

    with pytest.raises(AssertionError):
        test_units_import_only_allowed_units()


def test_layer_guard_catches_loose_module_beside_layers(tmp_path, monkeypatch):
    package = tmp_path / "copytrading_engine" / "execution"
    (package / "domain").mkdir(parents=True)
    (package / "loose.py").write_text("", encoding="utf-8")
    monkeypatch.setattr(sys.modules[__name__], "ROOT", tmp_path / "copytrading_engine")

    with pytest.raises(AssertionError):
        test_layered_packages_contain_only_layers()


def test_control_clients_import_only_the_published_contract():
    violations = [
        f"{path.relative_to(ROOT)}: {name}"
        for path in (ROOT / "control").glob("*.py")
        if path.stem in CONTROL_CLIENT_MODULES
        for name in imports(path)
        if name.startswith("copytrading_engine.")
        and not any(
            name == f"copytrading_engine.control.{allowed}"
            or name.startswith(f"copytrading_engine.control.{allowed}.")
            for allowed in CONTROL_CLIENT_MODULES
        )
        and name != "copytrading_engine.control"
    ]
    assert violations == []


def test_control_client_guard_catches_an_engine_import(tmp_path, monkeypatch):
    package = tmp_path / "copytrading_engine" / "control"
    package.mkdir(parents=True)
    (package / "cli.py").write_text(
        "from copytrading_engine.control.service import ControlService\n", encoding="utf-8"
    )
    monkeypatch.setattr(sys.modules[__name__], "ROOT", tmp_path / "copytrading_engine")

    with pytest.raises(AssertionError):
        test_control_clients_import_only_the_published_contract()
