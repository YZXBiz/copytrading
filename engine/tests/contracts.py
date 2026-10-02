"""The app's contract fixtures, shared by every test that speaks the pipe or control wire format."""

import json
from pathlib import Path
from typing import Any

CONTRACTS = Path(__file__).resolve().parents[2] / "app" / "Resources" / "Contracts"


def contract(name: str) -> Any:
    """Decode one fixture file."""
    return json.loads((CONTRACTS / name).read_text())
