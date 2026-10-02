"""The audit trail keeps the newest decisions in application.db."""

import datetime as dt

from copytrading_engine.backup.schema_catalog import APPLICATION_COMPONENTS
from copytrading_engine.control.audit import AuditEntry
from copytrading_engine.control.sqlite import CONTROL_AUDIT_SCHEMA, SQLiteControlAudit


def entry(index: int) -> AuditEntry:
    return AuditEntry(
        at=dt.datetime(2026, 9, 26, 15, index, tzinfo=dt.UTC),
        actor="agent",
        caller_pid=4242,
        caller_path="/usr/bin/agent",
        operation="get_status",
        tier="read",
        outcome="ok",
    )


async def test_recent_entries_come_back_newest_first_and_bounded(tmp_path):
    audit = await SQLiteControlAudit.open(tmp_path / "application.db", retention=3)
    try:
        for index in range(5):
            await audit.record(entry(index))
        recent = await audit.recent(50)
    finally:
        await audit.close()
    assert [item.at.minute for item in recent] == [4, 3, 2]
    assert recent[0] == entry(4)


async def test_a_database_at_revision_one_opens_unchanged(tmp_path):
    first = await SQLiteControlAudit.open(tmp_path / "application.db")
    await first.record(entry(0))
    await first.close()
    again = await SQLiteControlAudit.open(tmp_path / "application.db")
    try:
        assert await again.recent(5) == (entry(0),)
    finally:
        await again.close()
    assert CONTROL_AUDIT_SCHEMA.revision == 1


def test_backups_carry_the_audit_component():
    assert CONTROL_AUDIT_SCHEMA in APPLICATION_COMPONENTS
