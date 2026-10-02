"""The restore gate is atomic, durable, fail-closed, and never follows a symlink."""

import os

from copytrading_engine.backup.restore.gate import (
    clear_restore_manual_disabled,
    persist_restore_manual_disabled,
    restore_manual_disabled,
    restore_manual_disabled_path,
)


def test_restore_gate_is_atomic_durable_and_fail_closed(tmp_path, monkeypatch):
    owner = tmp_path / "owner"
    owner.mkdir()
    marker = restore_manual_disabled_path(owner)
    synced = []
    real_fsync = os.fsync

    def record_fsync(descriptor):
        synced.append(descriptor)
        return real_fsync(descriptor)

    monkeypatch.setattr(os, "fsync", record_fsync)

    persist_restore_manual_disabled(marker, b'{"state":"manual-disabled"}')

    assert marker.read_bytes() == b'{"state":"manual-disabled"}'
    assert restore_manual_disabled(marker)
    assert len(synced) == 2
    assert not list(owner.glob("*.tmp"))


def test_restore_gate_treats_symlink_as_active_and_never_follows_it(tmp_path):
    owner = tmp_path / "owner"
    owner.mkdir()
    target = tmp_path / "outside"
    target.write_text("outside", encoding="utf-8")
    marker = restore_manual_disabled_path(owner)
    marker.symlink_to(target)

    assert restore_manual_disabled(marker)
    persist_restore_manual_disabled(marker, b"blocked")
    assert marker.read_bytes() == b"blocked"
    assert target.read_text(encoding="utf-8") == "outside"


def test_restore_gate_clear_is_durable(tmp_path, monkeypatch):
    owner = tmp_path / "owner"
    owner.mkdir()
    marker = restore_manual_disabled_path(owner)
    persist_restore_manual_disabled(marker, b"pending")
    synced = []
    real_fsync = os.fsync

    def record_fsync(descriptor):
        synced.append(descriptor)
        return real_fsync(descriptor)

    monkeypatch.setattr(os, "fsync", record_fsync)

    clear_restore_manual_disabled(marker)

    assert not restore_manual_disabled(marker)
    assert len(synced) == 1
