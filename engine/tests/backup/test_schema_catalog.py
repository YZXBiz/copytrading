"""The backup schema catalog is exactly what the real operational stores create."""

import sqlite3
from contextlib import closing

import pytest

from copytrading_engine.backup.schema_catalog import (
    APPLICATION_COMPONENTS,
    APPLICATION_DATABASE_VERSION,
    current_operational_schema_catalog,
)
from copytrading_engine.control.sqlite import SQLiteControlAudit
from copytrading_engine.execution.adapters.sqlite_ledger import EXECUTION_SCHEMA, Store
from copytrading_engine.host.installation import INSTALLATION_SCHEMA, Installation
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore
from copytrading_engine.parsing.sqlite import SQLiteExtractionStore
from copytrading_engine.shared.sqlite import SchemaComponent, SchemaMismatch, verify_schema
from copytrading_engine.sources.sqlite import SQLiteSourceStore
from copytrading_engine.trading.adapters.routing import RoutingRevision


def _catalog(path) -> tuple[tuple[str, str, str, str], ...]:
    with closing(sqlite3.connect(path)) as connection:
        rows = connection.execute(
            "SELECT type,name,tbl_name,sql FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name"
        ).fetchall()
    return tuple((kind, name, table, sql.strip()) for kind, name, table, sql in rows if sql)


def _revisions(path) -> dict[str, int]:
    with closing(sqlite3.connect(path)) as connection:
        return dict(
            connection.execute(
                "SELECT component, revision FROM copytrading_engine_schema_revisions"
            )
        )


async def test_application_catalog_matches_real_store_creation(tmp_path):
    path = tmp_path / "application.db"
    with Installation(path) as installation, SQLiteSelfTestStore(installation):
        for opener in (
            SQLiteExtractionStore.open,
            SQLiteSourceStore.open,
            RoutingRevision.open,
            SQLiteControlAudit.open,
        ):
            store = await opener(path)
            await store.close()

    assert _catalog(path) == current_operational_schema_catalog("application.db")
    assert _revisions(path) == {c.name: c.revision for c in APPLICATION_COMPONENTS}
    with closing(sqlite3.connect(path)) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == (
            APPLICATION_DATABASE_VERSION
        )


def test_account_catalog_matches_real_ledger_creation(tmp_path):
    path = tmp_path / "accounts" / "paper-a" / "execution.sqlite3"
    Store(path).close()

    assert _catalog(path) == current_operational_schema_catalog(
        "accounts/paper-a/execution.sqlite3"
    )
    assert _revisions(path) == {EXECUTION_SCHEMA.name: EXECUTION_SCHEMA.revision}


def test_application_components_have_unique_names():
    names = [component.name for component in APPLICATION_COMPONENTS]
    assert len(names) == len(set(names))


def test_verify_schema_rejects_changed_objects_without_writing(tmp_path):
    path = tmp_path / "application.db"
    with Installation(path):
        pass
    changed = SchemaComponent(
        INSTALLATION_SCHEMA.name,
        INSTALLATION_SCHEMA.revision,
        INSTALLATION_SCHEMA.ddl.replace("value TEXT", "value BLOB"),
    )
    before = _catalog(path)

    with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)) as connection:
        verify_schema(connection, INSTALLATION_SCHEMA)
        with pytest.raises(SchemaMismatch, match="engine_metadata"):
            verify_schema(connection, changed)

    assert _catalog(path) == before


def test_schema_component_rejects_unsupported_statements():
    with pytest.raises(ValueError, match="unsupported statement"):
        SchemaComponent("broken", 1, "DROP TABLE engine_metadata")
