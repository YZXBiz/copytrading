"""The app names every state root; installation identity lives in the stable owner root."""

from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from copytrading_engine import bootstrap
from copytrading_engine.bootstrap import (
    diagnostics_state_root,
    owner_support_root,
    persist_installation_id,
)


def test_runtime_state_paths_keep_diagnostics_and_restore_staging_outside_generation(
    tmp_path, monkeypatch
):
    owner = tmp_path / "CopyTrading"
    monkeypatch.setenv("COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR", str(owner / "diagnostics"))
    monkeypatch.setenv("COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR", str(owner))

    assert diagnostics_state_root() == owner / "diagnostics"
    assert owner_support_root() == owner


@pytest.mark.parametrize(
    "missing",
    ["COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR", "COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR"],
)
def test_runtime_state_paths_are_required(tmp_path, monkeypatch, missing):
    monkeypatch.setenv("COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR", str(tmp_path / "diagnostics"))
    monkeypatch.setenv("COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR", str(tmp_path))
    monkeypatch.delenv(missing)

    read = {
        "COPYTRADING_DESKTOP_DIAGNOSTICS_STATE_DIR": diagnostics_state_root,
        "COPYTRADING_DESKTOP_OWNER_SUPPORT_DIR": owner_support_root,
    }[missing]

    with pytest.raises(ValueError, match=missing):
        read()


async def test_restore_marker_skips_pending_source_recovery(tmp_path):
    marker = tmp_path / ".restore-manual-disabled"
    marker.write_text("restore pending", encoding="utf-8")
    service = type("Service", (), {"process_pending": AsyncMock()})()

    await bootstrap._process_pending_if_allowed(service, marker)

    service.process_pending.assert_not_awaited()


def test_installation_identity_is_persisted_in_stable_owner_root(tmp_path):
    owner = tmp_path / "CopyTrading"
    generation = owner / "generations" / "candidate"
    generation.mkdir(parents=True)
    identity = str(uuid4())

    persist_installation_id(owner, identity)

    assert (owner / "installation-id").read_text(encoding="ascii").strip() == identity
    assert not (generation / "installation-id").exists()
